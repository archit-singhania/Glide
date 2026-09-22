import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glide_device_manager/glide_device_manager.dart';

import '../services/device_session.dart';
import '../ui/devices_renderer.dart';

/// Waits for Ctrl+C. Overridable so tests never hang on a real signal.
typedef InterruptTrigger = Future<void> Function();

Future<void> _waitForInterrupt() async {
  await ProcessSignal.sigint.watch().first;
}

/// `glide devices` - lists devices Glide can run Flutter apps on.
///
/// Without `--watch` this prints one snapshot and exits. With `--watch` it
/// keeps printing snapshots as devices connect or disconnect, until Ctrl+C
/// is pressed, at which point it stops watching and closes the session
/// cleanly rather than being killed outright.
class DevicesCommand extends Command<int> {
  DevicesCommand({
    required this.openSession,
    required this.out,
    this.renderer = const DevicesRenderer(),
    this.shutdown = _waitForInterrupt,
  }) {
    argParser
      ..addOption(
        'flutter-sdk',
        valueHelp: 'path',
        help: 'Flutter SDK directory or flutter executable to use.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the device list as JSON instead of text.',
      )
      ..addFlag(
        'watch',
        negatable: false,
        help: 'Keep printing updates as devices connect or disconnect.',
      );
  }

  final DeviceSessionOpener openSession;
  final StringSink out;
  final DevicesRenderer renderer;
  final InterruptTrigger shutdown;

  @override
  String get name => 'devices';

  @override
  String get description => 'List devices Glide can run Flutter apps on.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final session = await openSession(
      flutterSdkPath: results['flutter-sdk'] as String?,
    );
    final asJson = results['json'] as bool;
    try {
      if (results['watch'] as bool) {
        final interrupted = Completer<void>();
        unawaited(shutdown().then((_) => interrupted.complete()));
        final devices = session.manager.watchDevices().listen(
              (devices) => _print(devices, asJson: asJson),
            );
        await Future.any<void>(<Future<void>>[
          interrupted.future,
          devices.asFuture<void>(),
        ]);
        await devices.cancel();
      } else {
        _print(session.manager.devices, asJson: asJson);
      }
      return 0;
    } finally {
      await session.close();
    }
  }

  void _print(List<GlideDevice> devices, {required bool asJson}) {
    if (asJson) {
      final encoder = const JsonEncoder.withIndent('  ');
      out.writeln(encoder.convert(devices.map((d) => d.toJson()).toList()));
    } else {
      out.write(renderer.render(devices));
    }
  }
}
