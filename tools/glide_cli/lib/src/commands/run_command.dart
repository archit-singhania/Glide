import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glide_build_manager/glide_build_manager.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:path/path.dart' as p;

import '../services/app_launcher.dart';
import '../services/devtools_launcher.dart';
import '../services/project_watching.dart';
import '../ui/run_renderer.dart';
import 'start_command.dart' show ShutdownTrigger;

/// Raised when `glide run` cannot pick or start a target.
class RunException extends GlideException {
  const RunException(super.message, {super.cause});
}

/// Single key presses from the developer, one string per key.
typedef KeySource = Stream<String> Function();

Future<void> _waitForInterrupt() async {
  await ProcessSignal.sigint.watch().first;
}

/// Reads single key presses from the terminal without waiting for Enter.
/// Yields nothing (and ends) when stdin is not a terminal.
Stream<String> terminalKeys() {
  late final StreamController<String> controller;
  StreamSubscription<List<int>>? subscription;
  var previousEcho = true;
  var previousLine = true;
  controller = StreamController<String>(
    onListen: () {
      if (!stdin.hasTerminal) {
        unawaited(controller.close());
        return;
      }
      previousEcho = stdin.echoMode;
      previousLine = stdin.lineMode;
      stdin
        ..echoMode = false
        ..lineMode = false;
      subscription = stdin.listen(
        (bytes) {
          for (final byte in bytes) {
            controller.add(String.fromCharCode(byte));
          }
        },
        onDone: () => unawaited(controller.close()),
      );
    },
    onCancel: () async {
      await subscription?.cancel();
      if (stdin.hasTerminal) {
        stdin
          ..lineMode = previousLine
          ..echoMode = previousEcho;
      }
    },
  );
  return controller.stream;
}

/// Everything `glide run` reads from the outside world, so tests can replace
/// it. The defaults are the real thing.
class RunEnvironment {
  const RunEnvironment({
    this.launchApp = launchFlutterApp,
    this.chooseDevice = chooseSystemDefaultDevice,
    this.keys = terminalKeys,
    this.shutdown = _waitForInterrupt,
    this.createWatcher = createSystemProjectWatcher,
    this.openDevTools = openSystemDevTools,
  });

  final FlutterAppLauncher launchApp;
  final DefaultDeviceChooser chooseDevice;
  final KeySource keys;
  final ShutdownTrigger shutdown;

  /// Watches the project for changes that need a full restart.
  final ProjectWatcherFactory createWatcher;

  /// Opens DevTools on this computer when `d` is pressed.
  final DevToolsOpener openDevTools;
}

/// Prints protocol messages as terminal lines.
class _TerminalPublisher implements EventPublisher {
  _TerminalPublisher(this.out, this.renderer);

  final StringSink out;
  final RunRenderer renderer;

  @override
  void publish(GlideMessage message) {
    final line = renderer.render(message);
    if (line != null) out.writeln(line);
  }
}

/// `glide run [project-directory]` - builds the app on a device with the
/// official Flutter tool and lets you hot reload it from the keyboard.
///
/// Keys: `r` hot reload, `R` hot restart, `F` full restart, `q` quit.
class RunCommand extends Command<int> {
  RunCommand({
    required this.analyzer,
    required this.out,
    required this.err,
    required this.workingDirectory,
    this.environment = const RunEnvironment(),
    this.renderer = const RunRenderer(),
  }) {
    argParser
      ..addOption(
        'device',
        abbr: 'd',
        valueHelp: 'id',
        help: 'Device to run on (see "glide devices"). Chosen automatically '
            'when exactly one mobile device is ready.',
      )
      ..addOption(
        'flutter-sdk',
        valueHelp: 'path',
        help: 'Flutter SDK directory or flutter executable to use.',
      )
      ..addFlag(
        'profile',
        negatable: false,
        help: 'Run in profile mode instead of debug mode.',
      );
  }

  final ProjectAnalyzer analyzer;
  final StringSink out;
  final StringSink err;
  final String workingDirectory;
  final RunEnvironment environment;
  final RunRenderer renderer;

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run the Flutter app on a device, with hot reload from the keyboard.';

  @override
  String get invocation => 'glide run [project-directory]';

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
    final sdk = results['flutter-sdk'] as String?;
    final mode = results['profile'] as bool ? AppMode.profile : AppMode.debug;

    var device = results['device'] as String?;
    if (device != null && !deviceIdPattern.hasMatch(device)) {
      throw const RunException('--device contains characters Glide refuses.');
    }
    device ??= await environment.chooseDevice(flutterSdkPath: sdk);
    if (device == null) {
      throw const RunException(
        'Could not choose a device automatically. Run "glide devices", then '
        'pass one with --device <id>.',
      );
    }

    out.writeln('Running ${project.name} on $device...');

    final machine = SessionStateMachine();
    final done = Completer<SessionState>();
    late final SessionController controller;
    final changes = machine.changes.listen((change) {
      if ((change.to == SessionState.connected ||
              change.to == SessionState.failed) &&
          !controller.isRestarting &&
          !done.isCompleted) {
        done.complete(change.to);
      }
    });
    controller = SessionController(
      machine: machine,
      publisher: _TerminalPublisher(out, renderer),
      openDevTools: environment.openDevTools,
      launchApp: ({required String deviceId}) => environment.launchApp(
        projectPath: root,
        deviceId: deviceId,
        flutterSdkPath: sdk,
        mode: mode,
      ),
      onInternalError: (error, _) =>
          err.writeln('glide: internal error (${error.runtimeType}).'),
    );
    final keys = environment.keys().listen(
          (key) => _onKey(key, controller),
        );
    final stopWatching = watchForRestartNeeds(
      watcher: environment.createWatcher(
        root,
        (error) => err.writeln(
          'glide: watching for file changes stopped (${error.runtimeType}).',
        ),
      ),
      controller: controller,
    );

    try {
      await controller.handle(
        CompanionCommand(
          type: CompanionCommandType.appRun,
          payload: <String, Object?>{'deviceId': device},
        ),
      );
      final outcome = await Future.any<SessionState?>(<Future<SessionState?>>[
        done.future,
        environment.shutdown().then((_) => null),
      ]);
      if (outcome == null) {
        out.writeln('Stopping...');
        await controller.handle(
          const CompanionCommand(type: CompanionCommandType.appStop),
        );
        return 0;
      }
      return outcome == SessionState.failed ? 1 : 0;
    } finally {
      await stopWatching();
      await keys.cancel();
      await controller.dispose();
      await changes.cancel();
      await machine.dispose();
    }
  }

  void _onKey(String key, SessionController controller) {
    final CompanionCommand? command = switch (key) {
      'r' => const CompanionCommand(type: CompanionCommandType.appReload),
      'R' => const CompanionCommand(type: CompanionCommandType.appRestart),
      'F' => const CompanionCommand(
          type: CompanionCommandType.appRestart,
          payload: <String, Object?>{'mode': 'full'},
        ),
      'd' ||
      'D' =>
        const CompanionCommand(type: CompanionCommandType.devtoolsOpen),
      'q' || 'Q' => const CompanionCommand(type: CompanionCommandType.appStop),
      'h' || '?' => null,
      _ => null,
    };
    if (command != null) {
      unawaited(controller.handle(command));
    } else if (key == 'h' || key == '?') {
      out.writeln(RunRenderer.keyHelp);
    }
  }
}
