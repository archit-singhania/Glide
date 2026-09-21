import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glide_build_manager/glide_build_manager.dart';
import 'package:glide_network/glide_network.dart' as net;
import 'package:glide_performance/glide_performance.dart' as perf;
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:glide_security/glide_security.dart';
import 'package:glide_session_server/glide_session_server.dart';
import 'package:path/path.dart' as p;

import '../services/app_launcher.dart';
import '../services/devtools_launcher.dart';
import '../services/lan_address.dart';
import '../services/project_watching.dart';
import '../services/start_session_info.dart';
import '../ui/qr_renderer.dart';
import '../ui/start_renderer.dart';

/// Raised when `glide start` cannot set up a session.
class StartException extends GlideException {
  const StartException(super.message, {super.cause});
}

/// Completes when the developer asks Glide to stop (Ctrl+C by default).
typedef ShutdownTrigger = Future<void> Function();

Future<void> _waitForInterrupt() async {
  await ProcessSignal.sigint.watch().first;
}

/// Asks on the terminal whether to pair with a device. Defaults to "no".
PairingApprover terminalApprover(StringSink out) => (request) async {
      final from =
          request.remoteAddress == null ? '' : ' (${request.remoteAddress})';
      out.write('Pair with "${request.deviceName}"$from? [y/N] ');
      final answer = stdin.readLineSync()?.trim().toLowerCase();
      return answer == 'y' || answer == 'yes';
    };

/// Everything `glide start` reads from the outside world, so tests can
/// replace it. The defaults are the real thing.
class StartEnvironment {
  const StartEnvironment({
    this.resolveLanAddress = resolveSystemLanAddress,
    this.approver,
    this.shutdown = _waitForInterrupt,
    this.pairingLifetime = const Duration(minutes: 5),
    this.qr = const QrRenderer(),
    this.launchApp = launchFlutterApp,
    this.chooseDevice = chooseSystemDefaultDevice,
    this.createWatcher = createSystemProjectWatcher,
    this.connectPerformanceSampler = perf.connectPerformanceSampler,
    this.connectNetworkMonitor = net.connectNetworkMonitor,
    this.openDevTools = openSystemDevTools,
  });

  final LanAddressResolver resolveLanAddress;

  /// Null means "ask on the terminal".
  final PairingApprover? approver;
  final ShutdownTrigger shutdown;
  final Duration pairingLifetime;
  final QrRenderer qr;

  /// Starts `flutter run --machine` when the companion sends `app.run`.
  final FlutterAppLauncher launchApp;

  /// Picks a device when `app.run` does not name one.
  final DefaultDeviceChooser chooseDevice;

  /// Watches the project for changes that need a full restart.
  final ProjectWatcherFactory createWatcher;

  /// Samples FPS, frame time and memory from the running app's VM service.
  final PerformanceSamplerConnector connectPerformanceSampler;

  /// Watches the running app's HTTP requests through its VM service.
  final NetworkMonitorConnector connectNetworkMonitor;

  /// Opens DevTools on this computer when the companion asks.
  final DevToolsOpener openDevTools;
}

enum _Outcome { interrupted, expired }

/// `glide start [project-directory]` - starts a local session, shows a QR
/// code, and waits for the Glide companion to pair.
///
/// Once paired, the companion can run, stop, hot reload and restart the app;
/// each command is handled by a [SessionController], and anything it cannot
/// do is answered with `command.rejected`.
class StartCommand extends Command<int> {
  StartCommand({
    required this.analyzer,
    required this.out,
    required this.err,
    required this.workingDirectory,
    this.environment = const StartEnvironment(),
    this.renderer = const StartRenderer(),
  }) {
    argParser
      ..addOption(
        'host',
        valueHelp: 'ipv4',
        help: 'LAN address to listen on (default: detected automatically).',
      )
      ..addOption(
        'port',
        valueHelp: 'number',
        defaultsTo: '49400',
        help: 'Preferred port; the next few are tried if it is taken.',
      )
      ..addOption(
        'flutter-sdk',
        valueHelp: 'path',
        help: 'Flutter SDK directory or flutter executable to use.',
      )
      ..addFlag(
        'print-uri',
        negatable: false,
        help: 'Also print the pairing link as text. It contains the secret '
            'pairing token, so it stays out of your terminal history by '
            'default.',
      );
  }

  final ProjectAnalyzer analyzer;
  final StringSink out;
  final StringSink err;
  final String workingDirectory;
  final StartEnvironment environment;
  final StartRenderer renderer;

  @override
  String get name => 'start';

  @override
  String get description =>
      'Start a session and show a QR code for the Glide companion app.';

  @override
  String get invocation => 'glide start [project-directory]';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length > 1) {
      usageException('Expected at most one project directory.');
    }
    final start = results.rest.isEmpty
        ? workingDirectory
        : p.join(workingDirectory, results.rest.single);
    final root = FlutterProjectAnalyzer.findProjectRoot(start);
    if (root == null) {
      throw ProjectException(
        'No pubspec.yaml found in "$start" or any parent directory.',
      );
    }
    final project = await analyzer.analyze(root);

    final address = await _resolveAddress(results['host'] as String?);
    final port = _parsePort(results['port'] as String);

    final sessionId = generateSessionId();
    final machine = SessionStateMachine();
    final pairing = PairingManager(tokenLifetime: environment.pairingLifetime);
    final server = GlideSessionServer(
      authenticator: PairingManagerAuthenticator(pairing),
      infoProvider: StartSessionInfo(
        sessionId: sessionId,
        machine: machine,
        project: project,
      ),
      address: address,
      preferredPort: port,
      pairingManager: pairing,
      pairingApprover: environment.approver ?? terminalApprover(out),
      onInternalError: (error, _) =>
          err.writeln('glide: internal pairing error (${error.runtimeType}).'),
    );

    final flutterSdk = results['flutter-sdk'] as String?;
    final controller = SessionController(
      machine: machine,
      publisher: server,
      launchApp: ({required String deviceId}) => environment.launchApp(
        projectPath: root,
        deviceId: deviceId,
        flutterSdkPath: flutterSdk,
      ),
      defaultDevice: () => environment.chooseDevice(flutterSdkPath: flutterSdk),
      connectPerformanceSampler: environment.connectPerformanceSampler,
      connectNetworkMonitor: environment.connectNetworkMonitor,
      openDevTools: environment.openDevTools,
      onInternalError: (error, _) => err.writeln(
        'glide: internal error while handling a command '
        '(${error.runtimeType}).',
      ),
    );

    final BoundSession bound;
    try {
      bound = await server.start();
    } on Object {
      await controller.dispose();
      await machine.dispose();
      rethrow;
    }
    final subscriptions = <StreamSubscription<Object?>>[];
    Timer? expiryTimer;
    Future<void> Function()? stopWatching;
    try {
      machine.transitionTo(SessionState.pairing);
      final credential = pairing.issue(sessionId: sessionId);
      final payload = PairingPayload(
        host: address.address,
        port: bound.port,
        sessionId: sessionId,
        token: credential.token,
        expiresAt: credential.expiresAt,
      );

      var paired = false;
      final expired = Completer<void>();

      subscriptions
        ..add(
          server.pairedDevices.listen((device) {
            paired = true;
            machine.tryTransitionTo(SessionState.connected, reason: 'paired');
            out.writeln('Paired with ${device.deviceName}.');
          }),
        )
        ..add(
          server.commands.listen((command) {
            out.writeln('Received ${command.type.wire}.');
            unawaited(controller.handle(command));
          }),
        );

      stopWatching = watchForRestartNeeds(
        watcher: environment.createWatcher(
          root,
          (error) => err.writeln(
            'glide: watching for file changes stopped '
            '(${error.runtimeType}).',
          ),
        ),
        controller: controller,
      );

      expiryTimer = Timer(credential.expiresAt.difference(DateTime.now()), () {
        if (!paired && !expired.isCompleted) expired.complete();
      });

      out.write(
        renderer.render(
          project: project,
          payload: payload,
          qr: environment.qr.render(payload.toUri().toString()),
          showUri: results['print-uri'] as bool,
        ),
      );

      final outcome = await Future.any<_Outcome>(<Future<_Outcome>>[
        environment.shutdown().then((_) => _Outcome.interrupted),
        expired.future.then((_) => _Outcome.expired),
      ]);
      if (outcome == _Outcome.expired) {
        throw const StartException(
          'The pairing code expired before a device connected. '
          'Run "glide start" again for a new one.',
        );
      }
      out.writeln('Stopping Glide session.');
      return 0;
    } finally {
      expiryTimer?.cancel();
      await stopWatching?.call();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await controller.dispose();
      pairing.revokeAll();
      await server.stop();
      await machine.dispose();
    }
  }

  Future<InternetAddress> _resolveAddress(String? override) async {
    if (override != null) {
      final parsed = InternetAddress.tryParse(override);
      if (parsed == null || parsed.type != InternetAddressType.IPv4) {
        throw const StartException(
          '--host must be an IPv4 address such as 192.168.1.20.',
        );
      }
      if (parsed.rawAddress.every((byte) => byte == 0)) {
        throw StartException(
          'Refusing to listen on the wildcard address $override. Pass the '
          'address of your LAN interface instead.',
        );
      }
      return parsed;
    }
    final resolved = await environment.resolveLanAddress();
    if (resolved == null) {
      throw const StartException(
        'No private LAN address found. Connect to Wi-Fi, or pass '
        '--host <address>.',
      );
    }
    return resolved;
  }

  int _parsePort(String raw) {
    final port = int.tryParse(raw);
    if (port == null || port < 1 || port > 65535) {
      throw StartException('--port must be between 1 and 65535 (got "$raw").');
    }
    return port;
  }
}
