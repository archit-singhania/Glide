import 'dart:async';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_log_parser/glide_log_parser.dart';
import 'package:glide_network/glide_network.dart';
import 'package:glide_performance/glide_performance.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart'
    show ChangeImpact, ProjectChange;
import 'package:glide_protocol/glide_protocol.dart';

import 'devtools.dart';

/// Starts `flutter run --machine` for [deviceId]. The project path, SDK and
/// build mode are already bound by whoever creates the controller.
typedef AppLauncher = Future<AppSession> Function({required String deviceId});

/// Chooses a device when a command does not name one. Returns null when no
/// unambiguous choice exists.
typedef DefaultDeviceResolver = Future<String?> Function();

/// Connects to the app's Dart VM service and starts sampling performance.
/// Null disables performance sampling entirely (the default): nothing
/// publishes `performance.sample` and no VM service connection is ever made.
typedef PerformanceSamplerConnector = Future<PerformanceSampler> Function(
  String vmServiceUri,
);

/// Connects to the app's Dart VM service and starts watching its HTTP
/// requests. Null disables network monitoring entirely (the default).
typedef NetworkMonitorConnector = Future<NetworkMonitor> Function(
  String vmServiceUri,
);

/// Called with unexpected failures while handling a command. The sender only
/// ever sees a generic `command.rejected`.
typedef ControllerErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

const Set<SessionState> _startable = <SessionState>{
  SessionState.disconnected,
  SessionState.connected,
  SessionState.failed,
};

const Set<SessionState> _starting = <SessionState>{
  SessionState.preparing,
  SessionState.building,
  SessionState.installing,
  SessionState.launching,
};

const Set<SessionState> _stoppable = <SessionState>{
  SessionState.preparing,
  SessionState.building,
  SessionState.installing,
  SessionState.launching,
  SessionState.running,
  SessionState.reloading,
  SessionState.restarting,
};

const Set<SessionState> _up = <SessionState>{
  SessionState.running,
  SessionState.reloading,
  SessionState.restarting,
};

const int _maxLogLength = 4000;
const int _snapshotLogCount = 100;
const int _maxRestartReasons = 20;

/// Turns allowlisted [CompanionCommand]s into actions on a Flutter app, and
/// turns what the Flutter tool reports into protocol messages.
///
/// The controller is the only thing that drives the [SessionStateMachine]
/// while an app is being run. It knows nothing about sockets or terminals:
/// commands come in through [handle], messages go out through the
/// [EventPublisher], so the same controller serves `glide run` and
/// `glide start`.
///
/// Commands are processed one at a time, in order. `app.run` returns as soon
/// as the Flutter tool has started; the build continues in the background, so
/// `app.stop` is never stuck behind a slow Gradle build.
///
/// The Dart VM service URI is deliberately never published: it embeds a
/// credential for the running app and a phone has no use for it.
class SessionController {
  SessionController({
    required this.machine,
    required this.publisher,
    required this.launchApp,
    this.defaultDevice,
    this.connectPerformanceSampler,
    this.connectNetworkMonitor,
    this.openDevTools,
    this.onInternalError,
    this.maxBufferedLogs = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _stateSubscription = machine.changes.listen(_onStateChange);
  }

  final SessionStateMachine machine;
  final EventPublisher publisher;
  final AppLauncher launchApp;
  final DefaultDeviceResolver? defaultDevice;

  /// Null (the default) disables performance sampling.
  final PerformanceSamplerConnector? connectPerformanceSampler;

  /// Null (the default) disables network monitoring.
  final NetworkMonitorConnector? connectNetworkMonitor;

  /// Null (the default) makes `devtools.open` answer that DevTools is not
  /// available in this session.
  final DevToolsOpener? openDevTools;
  final ControllerErrorHandler? onInternalError;
  final int maxBufferedLogs;
  final DateTime Function() _clock;
  final DiagnosticParser _parser = const DiagnosticParser();
  late final StreamSubscription<SessionStateChange> _stateSubscription;
  StreamSubscription<FlutterToolEvent>? _eventSubscription;
  AppSession? _session;
  String? _deviceId;
  final List<LogEntry> _logs = <LogEntry>[];
  PerformanceSampler? _performanceSampler;
  // Cancelled in _stopMonitoring through a local alias, which the lint cannot
  // follow across the field reset.
  // ignore: cancel_subscriptions
  StreamSubscription<PerformanceSample>? _performanceSubscription;
  PerformanceSample? _lastPerformanceSample;
  NetworkMonitor? _networkMonitor;
  // Cancelled in _stopMonitoring; see _performanceSubscription.
  // ignore: cancel_subscriptions
  StreamSubscription<NetworkEvent>? _networkSubscription;
  DevToolsHandle? _devTools;

  // Files changed since the running app was built, keyed by path, that hot
  // reload cannot apply. Cleared whenever the app is launched or torn down.
  final Map<String, ProjectChange> _restartReasons = <String, ProjectChange>{};
  final Stopwatch _launchWatch = Stopwatch();
  Future<void> _queue = Future<void>.value();

  // Bumped whenever a session is torn down or replaced, so callbacks that
  // belong to an older session can tell they are stale.
  int _generation = 0;
  bool _restartInFlight = false;

  // Set for the whole duration of the teardown step that a full restart
  // performs on its own old session, so `_teardown` does not mistake that
  // expected step for the session being stopped out from under a restart.
  bool _restartTeardownExpected = false;

  SessionState get state => machine.state;

  /// True from the moment a full restart begins tearing down the old
  /// session until the new one has started or the restart has failed.
  ///
  /// External callers that watch [SessionStateMachine.changes] for a
  /// terminal `connected`/`failed` state should ignore one reached while
  /// this is true: a full restart passes through `connected` on its way
  /// to relaunching, and that is not the session ending.
  bool get isRestarting => _restartInFlight;

  /// The device the current (or most recent) app was launched on.
  String? get deviceId => _deviceId;

  List<LogEntry> get recentLogs => List<LogEntry>.unmodifiable(_logs);

  /// True when files changed that only a full restart can apply.
  bool get restartRequired => _restartReasons.isNotEmpty;

  /// Tells the controller that project files changed on disk.
  ///
  /// Changes that hot reload can apply are ignored. Anything that needs a
  /// full restart (native code, Gradle or Xcode configuration, `pubspec.yaml`)
  /// is remembered and announced once as `restart.required`, only while an
  /// app is starting or running. Hot reload is not blocked: the developer may
  /// have edited a platform they are not running on.
  void reportProjectChanges(Iterable<ProjectChange> changes) {
    if (!_starting.contains(machine.state) && !_up.contains(machine.state)) {
      return;
    }
    var added = false;
    for (final change in changes) {
      if (change.impact != ChangeImpact.fullRestart) continue;
      if (_restartReasons.containsKey(change.path)) continue;
      _restartReasons[change.path] = change;
      added = true;
    }
    if (added) {
      _publish(MessageTypes.restartRequired, _restartPayload());
    }
  }

  Map<String, Object?> _restartPayload() => <String, Object?>{
        'count': _restartReasons.length,
        'reasons': <Map<String, Object?>>[
          for (final change in _restartReasons.values.take(_maxRestartReasons))
            change.toJson(),
        ],
      };

  /// Queues [command]. The returned future completes once it has been acted
  /// on; it never throws.
  Future<void> handle(CompanionCommand command) {
    final result = _queue.then((_) => _dispatch(command));
    _queue = result;
    return result;
  }

  Future<void> _dispatch(CompanionCommand command) async {
    try {
      switch (command.type) {
        case CompanionCommandType.appRun:
          await _run(command);
        case CompanionCommandType.appStop:
          await _stop(command);
        case CompanionCommandType.appReload:
          await _reload(command);
        case CompanionCommandType.appRestart:
          await _restart(command);
        case CompanionCommandType.logsClear:
          _logs.clear();
          _publish(MessageTypes.logsCleared);
        case CompanionCommandType.sessionDisconnect:
          if (_session != null && _stoppable.contains(machine.state)) {
            await _teardown('companion disconnected');
          }
        case CompanionCommandType.diagnosticsRequest:
          _publishSnapshot();
        case CompanionCommandType.devtoolsOpen:
          await _openDevTools(command);
      }
    } on Object catch (error, stackTrace) {
      onInternalError?.call(error, stackTrace);
      _reject(
        command,
        'The command failed unexpectedly (${error.runtimeType}).',
      );
    }
  }

  // ------------------------------------------------------------------ run

  Future<void> _run(CompanionCommand command) async {
    if (!_startable.contains(machine.state)) {
      _reject(command, 'An app is already running or starting.');
      return;
    }
    final device = command.deviceId ?? await defaultDevice?.call();
    if (device == null) {
      _reject(
        command,
        'No device was given and none could be chosen automatically.',
      );
      return;
    }
    if (!deviceIdPattern.hasMatch(device)) {
      _reject(command, 'Invalid device id.');
      return;
    }
    if (!_startable.contains(machine.state)) {
      _reject(command, 'An app is already running or starting.');
      return;
    }
    await _launch(device);
  }

  Future<void> _launch(String device, {bool viaRestart = false}) async {
    final generation = ++_generation;
    _deviceId = device;
    _restartInFlight = viaRestart;
    _restartReasons.clear();
    _launchWatch
      ..reset()
      ..start();
    _transition(SessionState.preparing, 'run');
    _publish(MessageTypes.buildStarted, <String, Object?>{'deviceId': device});

    final AppSession session;
    try {
      session = await launchApp(deviceId: device);
    } on GlideException catch (error) {
      _failLaunch(generation, error.message);
      return;
    } on Object catch (error) {
      _failLaunch(
        generation,
        'Could not start the Flutter tool (${error.runtimeType}).',
      );
      return;
    }
    if (generation != _generation) {
      // Torn down while the tool was starting.
      try {
        await session.stop();
      } on Object catch (error) {
        _log(
          'glide',
          LogLevel.warning,
          'Stopping a stale app failed (${error.runtimeType}).',
        );
      }
      return;
    }
    _session = session;
    _transition(SessionState.building, 'flutter run started');
    _eventSubscription = session.events.listen(
      (event) => _onToolEvent(generation, event),
    );
    unawaited(_awaitStart(generation, session));
    unawaited(session.exitCode.then((code) => _onExit(generation, code)));
  }

  Future<void> _awaitStart(int generation, AppSession session) async {
    try {
      await session.started;
    } on Object catch (_) {
      // The process ended first; _onExit reports that.
      return;
    }
    if (generation != _generation || !_starting.contains(machine.state)) {
      return;
    }
    _transition(SessionState.running, 'app started');
    final elapsed = _launchWatch.elapsed.inMilliseconds;
    _publish(MessageTypes.appStarted, <String, Object?>{
      if (_appIdOf(session) != null) 'appId': _appIdOf(session),
      'deviceId': _deviceId,
      'durationMs': elapsed,
    });
    _publish(MessageTypes.buildCompleted, <String, Object?>{
      'durationMs': elapsed,
    });
    if (_restartInFlight) {
      _restartInFlight = false;
      _publish(MessageTypes.restartCompleted, <String, Object?>{
        'mode': 'full',
        'durationMs': elapsed,
      });
    }
    final vmServiceUri = session.vmServiceUri;
    if (vmServiceUri != null) {
      if (connectPerformanceSampler != null) {
        unawaited(_startPerformanceSampling(generation, vmServiceUri));
      }
      if (connectNetworkMonitor != null) {
        unawaited(_startNetworkMonitoring(generation, vmServiceUri));
      }
    }
  }

  void _failLaunch(int generation, String message, {int? exitCode}) {
    if (generation != _generation) return;
    _session = null;
    _restartReasons.clear();
    unawaited(_stopMonitoring());
    // Reset before the state transition fires, so a listener watching for a
    // terminal `failed` state via `isRestarting` sees the restart as over.
    final wasRestarting = _restartInFlight;
    if (wasRestarting) _restartInFlight = false;
    _transition(SessionState.failed, message);
    _publish(MessageTypes.buildFailed, <String, Object?>{
      'message': message,
      if (_deviceId != null) 'deviceId': _deviceId,
      if (exitCode != null) 'exitCode': exitCode,
    });
    if (wasRestarting) {
      _publish(MessageTypes.restartFailed, <String, Object?>{
        'mode': 'full',
        'message': message,
      });
    }
  }

  Future<void> _onExit(int generation, int code) async {
    // Let events already emitted by the tool reach _onToolEvent first.
    await Future<void>.delayed(Duration.zero);
    if (generation != _generation) return;
    final state = machine.state;
    if (_up.contains(state)) {
      _session = null;
      _restartReasons.clear();
      await _stopMonitoring();
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _publish(MessageTypes.appStopped, <String, Object?>{
        if (_deviceId != null) 'deviceId': _deviceId,
        'exitCode': code,
      });
      _transition(SessionState.stopping, 'app exited');
      _transition(SessionState.connected, 'app exited');
    } else if (_starting.contains(state)) {
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _failLaunch(
        generation,
        'The Flutter tool exited (code $code) before the app started.',
        exitCode: code,
      );
    }
  }

  // ------------------------------------------------------------ tool events

  void _onToolEvent(int generation, FlutterToolEvent event) {
    if (generation != _generation) return;
    switch (event) {
      case final AppStarting starting:
        _transition(SessionState.launching, 'app starting');
        _publish(MessageTypes.appStarting, <String, Object?>{
          'appId': starting.appId,
          'deviceId': starting.deviceId,
          'mode': starting.mode,
        });
      case final AppProgress progress:
        if (progress.isHotOperation || progress.finished) return;
        if (!_starting.contains(machine.state)) return;
        // Heuristic on the tool's English progress text; only affects which
        // state is shown, never whether the app runs.
        if (progress.message.startsWith('Installing')) {
          _transition(SessionState.installing, 'installing');
        }
        _publish(MessageTypes.buildProgress, <String, Object?>{
          'message': _clip(progress.message),
        });
      case final AppLog log:
        _log('app', log.isError ? LogLevel.error : LogLevel.info, log.message);
      case final ToolLog log:
        _log(
          'flutter',
          log.isError ? LogLevel.error : LogLevel.info,
          log.message,
        );
      default:
        break;
    }
  }

  void _log(String source, LogLevel level, String message) {
    final entry = LogEntry(
      timestamp: _clock(),
      level: level,
      source: source,
      message: _clip(message),
    );
    _logs.add(entry);
    if (_logs.length > maxBufferedLogs) {
      _logs.removeRange(0, _logs.length - maxBufferedLogs);
    }
    _publish(MessageTypes.logEntry, entry.toJson());
    final diagnostic = _parser.parseLine(message);
    if (diagnostic != null) {
      _publish(MessageTypes.errorReported, diagnostic.toJson());
    }
  }

  // --------------------------------------------------------- reload/restart

  Future<void> _reload(CompanionCommand command) async {
    final session = _session;
    if (machine.state != SessionState.running || session == null) {
      _reject(command, 'No running app to reload.');
      return;
    }
    _transition(SessionState.reloading, 'hot reload');
    _publish(MessageTypes.reloadStarted);
    try {
      final outcome = await session.hotReload();
      _publish(
        outcome.success
            ? MessageTypes.reloadCompleted
            : MessageTypes.reloadFailed,
        _outcomePayload(outcome),
      );
    } on GlideException catch (error) {
      _publish(MessageTypes.reloadFailed, <String, Object?>{
        'message': error.message,
      });
    } finally {
      _transition(SessionState.running, 'reload finished');
    }
  }

  Future<void> _restart(CompanionCommand command) async {
    final session = _session;
    if (machine.state != SessionState.running || session == null) {
      _reject(command, 'No running app to restart.');
      return;
    }
    if (command.restartMode == RestartMode.full) {
      final device = _deviceId;
      if (device == null) {
        _reject(command, 'The device for this app is unknown.');
        return;
      }
      _restartInFlight = true;
      _transition(SessionState.restarting, 'full restart');
      _publish(MessageTypes.restartStarted, <String, Object?>{'mode': 'full'});
      _restartTeardownExpected = true;
      await _teardown('full restart');
      _restartTeardownExpected = false;
      await _launch(device, viaRestart: true);
      return;
    }
    _transition(SessionState.restarting, 'hot restart');
    _publish(MessageTypes.restartStarted, <String, Object?>{'mode': 'hot'});
    try {
      final outcome = await session.hotRestart();
      _publish(
        outcome.success
            ? MessageTypes.restartCompleted
            : MessageTypes.restartFailed,
        <String, Object?>{'mode': 'hot', ..._outcomePayload(outcome)},
      );
    } on GlideException catch (error) {
      _publish(MessageTypes.restartFailed, <String, Object?>{
        'mode': 'hot',
        'message': error.message,
      });
    } finally {
      _transition(SessionState.running, 'restart finished');
    }
  }

  Map<String, Object?> _outcomePayload(ReloadOutcome outcome) =>
      <String, Object?>{
        'durationMs': outcome.duration.inMilliseconds,
        'message': _clip(outcome.message),
      };

  // ------------------------------------------------------------------ stop

  Future<void> _stop(CompanionCommand command) async {
    if (_session == null || !_stoppable.contains(machine.state)) {
      _reject(command, 'No app is running.');
      return;
    }
    await _teardown('stop');
  }

  Future<void> _teardown(String reason) async {
    final session = _session;
    _generation++;
    _session = null;
    _restartReasons.clear();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _stopMonitoring();
    if (_restartInFlight && !_restartTeardownExpected) {
      _restartInFlight = false;
      _publish(MessageTypes.restartFailed, <String, Object?>{
        'mode': 'full',
        'message': 'The app was stopped.',
      });
    }
    _transition(SessionState.stopping, reason);
    if (session != null) {
      try {
        await session.stop();
      } on Object catch (error) {
        _log(
          'glide',
          LogLevel.warning,
          'Stopping the app failed (${error.runtimeType}).',
        );
      }
    }
    _publish(MessageTypes.appStopped, <String, Object?>{
      if (_deviceId != null) 'deviceId': _deviceId,
    });
    _transition(SessionState.connected, reason);
  }

  // ----------------------------------------------------------- monitoring

  Future<void> _startPerformanceSampling(
    int generation,
    String vmServiceUri,
  ) async {
    final connector = connectPerformanceSampler;
    if (connector == null) return;
    final PerformanceSampler sampler;
    try {
      sampler = await connector(vmServiceUri);
    } on Object catch (error) {
      // Only the type is logged: the error text could contain the VM service
      // address, which is a credential.
      _log(
        'glide',
        LogLevel.warning,
        'Performance sampling is unavailable (${error.runtimeType}).',
      );
      return;
    }
    if (generation != _generation || _performanceSampler != null) {
      await sampler.stop();
      return;
    }
    _performanceSampler = sampler;
    _performanceSubscription = sampler.samples.listen((sample) {
      _lastPerformanceSample = sample;
      _publish(MessageTypes.performanceSample, sample.toJson());
    });
  }

  Future<void> _startNetworkMonitoring(
    int generation,
    String vmServiceUri,
  ) async {
    final connector = connectNetworkMonitor;
    if (connector == null) return;
    final NetworkMonitor monitor;
    try {
      monitor = await connector(vmServiceUri);
    } on Object catch (error) {
      _log(
        'glide',
        LogLevel.warning,
        'Network monitoring is unavailable (${error.runtimeType}).',
      );
      return;
    }
    if (generation != _generation || _networkMonitor != null) {
      await monitor.stop();
      return;
    }
    _networkMonitor = monitor;
    _networkSubscription = monitor.events.listen(
      (event) => _publish(MessageTypes.networkResponse, event.toJson()),
    );
  }

  /// Releases everything attached to the running app: the performance
  /// sampler, the network monitor and any DevTools server. Safe to call when
  /// nothing is attached.
  Future<void> _stopMonitoring() async {
    final performanceSubscription = _performanceSubscription;
    final sampler = _performanceSampler;
    final networkSubscription = _networkSubscription;
    final monitor = _networkMonitor;
    final devTools = _devTools;
    _performanceSubscription = null;
    _performanceSampler = null;
    _lastPerformanceSample = null;
    _networkSubscription = null;
    _networkMonitor = null;
    _devTools = null;
    await performanceSubscription?.cancel();
    await networkSubscription?.cancel();
    try {
      await sampler?.stop();
    } on Object {
      // The connection may already be gone; sampling is over either way.
    }
    try {
      await monitor?.stop();
    } on Object {
      // Same: the app may have closed first.
    }
    try {
      await devTools?.close();
    } on Object {
      // DevTools may already have exited.
    }
  }

  Future<void> _openDevTools(CompanionCommand command) async {
    final opener = openDevTools;
    if (opener == null) {
      _reject(command, 'DevTools is not available in this session.');
      return;
    }
    final session = _session;
    final vmServiceUri = session?.vmServiceUri;
    if (session == null || vmServiceUri == null || !_up.contains(state)) {
      _reject(command, 'No running app to inspect.');
      return;
    }
    if (_devTools != null) {
      _publish(MessageTypes.devtoolsOpened, <String, Object?>{
        'alreadyOpen': true,
      });
      return;
    }
    final DevToolsHandle handle;
    try {
      handle = await opener(vmServiceUri);
    } on Object catch (error) {
      _publish(MessageTypes.devtoolsFailed, <String, Object?>{
        'message': 'DevTools could not be started (${error.runtimeType}).',
      });
      return;
    }
    if (!identical(session, _session)) {
      // The app went away while DevTools was starting.
      try {
        await handle.close();
      } on Object {
        // Nothing more to do.
      }
      return;
    }
    _devTools = handle;
    _publish(MessageTypes.devtoolsOpened);
  }

  // -------------------------------------------------------------- plumbing

  void _publishSnapshot() {
    final logs = _logs.length > _snapshotLogCount
        ? _logs.sublist(_logs.length - _snapshotLogCount)
        : _logs;
    _publish(MessageTypes.sessionSnapshot, <String, Object?>{
      'state': machine.state.name,
      if (_deviceId != null) 'deviceId': _deviceId,
      'recentLogs': logs.map((entry) => entry.toJson()).toList(),
      if (restartRequired) ..._restartPayload(),
      if (_lastPerformanceSample case final sample?)
        'performance': sample.toJson(),
    });
  }

  void _reject(CompanionCommand command, String reason) {
    _publish(MessageTypes.commandRejected, <String, Object?>{
      'command': command.type.wire,
      'reason': reason,
      if (command.requestId != null) 'requestId': command.requestId,
    });
  }

  void _transition(SessionState next, String reason) {
    machine.tryTransitionTo(next, reason: reason);
  }

  void _onStateChange(SessionStateChange change) {
    _publish(MessageTypes.sessionStatus, <String, Object?>{
      'state': change.to.name,
      'previous': change.from.name,
      if (change.reason != null) 'reason': change.reason,
    });
  }

  void _publish(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) {
    try {
      publisher.publish(GlideMessage.create(type, payload: payload));
    } on Object catch (_) {
      // A companion that disconnected mid-publish must not break the session;
      // it re-syncs with diagnostics.request when it reconnects.
    }
  }

  String? _appIdOf(AppSession session) {
    final id = session.appId;
    return id == null || id.isEmpty ? null : id;
  }

  String _clip(String text) => text.length > _maxLogLength
      ? '${text.substring(0, _maxLogLength)}...'
      : text;

  /// Stops any running app and releases resources. Safe to call once.
  Future<void> dispose() async {
    await _queue;
    if (_session != null) await _teardown('shutdown');
    _generation++;
    await _stateSubscription.cancel();
  }
}
