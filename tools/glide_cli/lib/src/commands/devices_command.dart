import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:glide_device_manager/glide_device_manager.dart';

import '../services/device_session.dart';
import '../ui/devices_renderer.dart';

/// `glide devices` - lists devices Glide can run Flutter apps on.
///
/// Without `--watch` this prints one snapshot and exits. With `--watch` it
/// keeps printing snapshots as devices connect or disconnect, until the
/// underlying session ends (currently: until the process is killed, since
/// nothing today calls back to signal a graceful stop while watching).
class DevicesCommand extends Command<int> {
  DevicesCommand({
    required this.openSession,
    required this.out,
    this.renderer = const DevicesRenderer(),
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
        await for (final devices in session.manager.watchDevices()) {
          _print(devices, asJson: asJson);
        }
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
