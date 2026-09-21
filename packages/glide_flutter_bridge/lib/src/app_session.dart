import 'dart:async';

import 'package:glide_protocol/glide_protocol.dart';

import 'machine_connection.dart';
import 'models.dart';
import 'process.dart';

/// Build mode. Release builds do not support hot reload and are excluded.
enum AppMode { debug, profile }

/// Result of a hot reload / hot restart request.
class ReloadOutcome {
  const ReloadOutcome({
    required this.success,
    required this.message,
    required this.duration,
  });

  final bool success;
  final String message;
  final Duration duration;
}

/// A running (or launching) Flutter application under Glide's control.
abstract interface class AppSession {
  /// Known once the tool reports `app.start`.
  String? get appId;

  /// Dart VM service URI once the app is attachable.
  String? get vmServiceUri;

  /// Every tool event from launch onward. Single-subscription and buffered:
  /// attach exactly one consumer.
  Stream<FlutterToolEvent> get events;

  /// Completes when the app is running; errors if it dies first.
  Future<void> get started;

  Future<int> get exitCode;

  /// Stateful hot reload.
  Future<ReloadOutcome> hotReload();

  /// Hot restart: resets Dart application state.
  Future<ReloadOutcome> hotRestart();

  Future<void> stop();
}

/// [AppSession] backed by `flutter run --machine`.
class FlutterAppSession implements AppSession {
  FlutterAppSession._(this._connection) {
    _subscription = _connection.events.listen(_onEvent);
    _started.future.ignore();
  }

  /// Starts `flutter run --machine` for [deviceId] in [projectPath].
  static Future<FlutterAppSession> launch({
    required ProcessLauncher launcher,
    required String flutterExecutable,
    required String projectPath,
    required String deviceId,
    String? target,
    AppMode mode = AppMode.debug,
  }) async {
    if (!deviceIdPattern.hasMatch(deviceId)) {
      throw ToolException('Refusing to use unsafe device id.');
    }
    final session = FlutterAppSession._(
      MachineConnection(
        launcher: launcher,
        executable: flutterExecutable,
        workingDirectory: projectPath,
        arguments: <String>[
          'run',
          '--machine',
          '-d',
          deviceId,
          '--${mode.name}',
          if (target != null) ...<String>['-t', target],
        ],
      ),
    );
    await session._connection.start();
    return session;
  }

  final MachineConnection _connection;
  final StreamController<FlutterToolEvent> _out =
      StreamController<FlutterToolEvent>();
  final Completer<void> _started = Completer<void>();
  late final StreamSubscription<FlutterToolEvent> _subscription;
  String? _appId;
  String? _vmServiceUri;

  @override
  String? get appId => _appId;

  @override
  String? get vmServiceUri => _vmServiceUri;

  @override
  Stream<FlutterToolEvent> get events => _out.stream;

  @override
  Future<void> get started => _started.future;

  @override
  Future<int> get exitCode => _connection.exitCode;

  void _onEvent(FlutterToolEvent event) {
    switch (event) {
      case AppStarting(:final appId):
        _appId = appId;
      case AppDebugPort(:final wsUri):
        _vmServiceUri = wsUri;
      case AppStarted():
        if (!_started.isCompleted) _started.complete();
      case ToolExited(exitCode: final code):
        if (!_started.isCompleted) {
          _started.completeError(ToolProcessExited(code));
        }
      default:
        break;
    }
    _out.add(event);
    if (event is ToolExited) {
      unawaited(_subscription.cancel());
      unawaited(_out.close());
    }
  }

  @override
  Future<ReloadOutcome> hotReload() => _restart(full: false);

  @override
  Future<ReloadOutcome> hotRestart() => _restart(full: true);

  Future<ReloadOutcome> _restart({required bool full}) async {
    final id = _appId;
    if (id == null) {
      throw ToolException('The app has not started yet.');
    }
    final watch = Stopwatch()..start();
    final result = await _connection.request(
      'app.restart',
      <String, Object?>{
        'appId': id,
        'fullRestart': full,
        'pause': false,
        'reason': 'glide',
      },
    );
    watch.stop();
    var code = 0;
    var message = 'ok';
    if (result is Map) {
      final rawCode = result['code'];
      final rawMessage = result['message'];
      if (rawCode is int) code = rawCode;
      if (rawMessage is String) message = rawMessage;
    }
    return ReloadOutcome(
      success: code == 0,
      message: message,
      duration: watch.elapsed,
    );
  }

  @override
  Future<void> stop() async {
    final id = _appId;
    if (id != null && _connection.isRunning) {
      try {
        await _connection
            .request('app.stop', <String, Object?>{'appId': id}).timeout(
          const Duration(seconds: 10),
        );
      } on Object catch (error) {
        if (!_out.isClosed) {
          _out.add(
            ToolLog(
              'app.stop did not complete cleanly: $error',
              isError: false,
            ),
          );
        }
      }
    }
    try {
      await _connection.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      _connection.kill();
      await _connection.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
  }
}
