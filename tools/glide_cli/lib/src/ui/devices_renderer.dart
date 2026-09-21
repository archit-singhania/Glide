import 'package:glide_device_manager/glide_device_manager.dart';

/// Formats a list of [GlideDevice]s for the terminal.
class DevicesRenderer {
  const DevicesRenderer();

  String render(List<GlideDevice> devices) {
    final out = StringBuffer();
    if (devices.isEmpty) {
      out
        ..writeln('No devices found.')
        ..writeln(
          'Connect an Android phone with USB debugging enabled, or start '
          'an emulator.',
        );
      return out.toString();
    }

    out
      ..writeln('Glide Devices')
      ..writeln();
    var index = 1;
    for (final device in devices) {
      final kind =
          device.isEmulator ? '${device.platform}, emulator' : device.platform;
      final busy = device.state == DeviceLifecycle.busy ? '  (busy)' : '';
      out
        ..writeln('$index. ${device.name}$busy')
        ..writeln('   $kind')
        ..writeln('   ${device.id}')
        ..writeln();
      index++;
    }
    return out.toString();
  }
}
