import 'package:glide_protocol/glide_protocol.dart';

import 'machine_protocol.dart';

/// A device known to the Flutter tool.
///
/// Understands both `flutter devices --machine` and daemon `device.*` shapes.
class FlutterDevice {
  const FlutterDevice({
    required this.id,
    required this.name,
    required this.platform,
    this.category,
    this.isEmulator = false,
    this.isEphemeral = false,
    this.isSupported = true,
  });

  /// Returns null when [json] has no usable id.
  static FlutterDevice? tryFromJson(Map<String, Object?> json) {
    final id = json.stringOrNull('id');
    if (id == null || id.isEmpty) return null;
    return FlutterDevice(
      id: id,
      name: json.stringOrNull('name') ?? id,
      platform: json.stringOrNull('platform') ??
          json.stringOrNull('targetPlatform') ??
          'unknown',
      category: json.stringOrNull('category'),
      isEmulator: json.boolOrNull('emulator') ?? false,
      isEphemeral: json.boolOrNull('ephemeral') ?? false,
      isSupported: json.boolOrNull('isSupported') ?? true,
    );
  }

  final String id;
  final String name;

  /// For example `android-arm64`, `ios`, `windows-x64`, `web-javascript`.
  final String platform;
  final String? category;
  final bool isEmulator;
  final bool isEphemeral;
  final bool isSupported;

  bool get isAndroid => platform.startsWith('android');
  bool get isIos => platform.startsWith('ios');

  /// Whether this is a phone/tablet/emulator target Glide can drive.
  bool get isMobile => category == 'mobile' || isAndroid || isIos;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform,
        if (category != null) 'category': category,
        'emulator': isEmulator,
        'ephemeral': isEphemeral,
        'isSupported': isSupported,
      };

  @override
  bool operator ==(Object other) =>
      other is FlutterDevice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'FlutterDevice($name, $id, $platform)';
}

/// Typed events emitted by the Flutter tool.
sealed class FlutterToolEvent {
  const FlutterToolEvent();

  factory FlutterToolEvent.fromMachine(MachineEvent event) {
    final p = event.params;
    switch (event.name) {
      case 'daemon.connected':
        return DaemonConnected(p.stringOrNull('version') ?? 'unknown');
      case 'daemon.logMessage':
        return ToolLog(
          p.stringOrNull('message') ?? '',
          isError: p.stringOrNull('level') == 'error',
        );
      case 'daemon.log':
        return ToolLog(
          p.stringOrNull('log') ?? '',
          isError: p.boolOrNull('error') ?? false,
        );
      case 'device.added':
        final device = FlutterDevice.tryFromJson(p);
        return device == null
            ? UnknownToolEvent(event.name, p)
            : DeviceAdded(device);
      case 'device.removed':
        final id = p.stringOrNull('id');
        return id == null ? UnknownToolEvent(event.name, p) : DeviceRemoved(id);
      case 'app.start':
        return AppStarting(
          appId: p.stringOrNull('appId') ?? '',
          deviceId: p.stringOrNull('deviceId') ?? '',
          mode: p.stringOrNull('mode') ?? 'debug',
        );
      case 'app.debugPort':
        return AppDebugPort(
          appId: p.stringOrNull('appId') ?? '',
          wsUri: p.stringOrNull('wsUri') ?? '',
        );
      case 'app.started':
        return AppStarted(p.stringOrNull('appId') ?? '');
      case 'app.progress':
        return AppProgress(
          appId: p.stringOrNull('appId') ?? '',
          progressId: p.stringOrNull('progressId'),
          message: p.stringOrNull('message') ?? '',
          finished: p.boolOrNull('finished') ?? false,
        );
      case 'app.log':
        return AppLog(
          appId: p.stringOrNull('appId') ?? '',
          message: p.stringOrNull('log') ?? '',
          isError: p.boolOrNull('error') ?? false,
        );
      case 'app.stop':
        return AppStopped(p.stringOrNull('appId') ?? '');
      default:
        return UnknownToolEvent(event.name, p);
    }
  }
}

final class DaemonConnected extends FlutterToolEvent {
  const DaemonConnected(this.version);
  final String version;
}

final class DeviceAdded extends FlutterToolEvent {
  const DeviceAdded(this.device);
  final FlutterDevice device;
}

final class DeviceRemoved extends FlutterToolEvent {
  const DeviceRemoved(this.deviceId);
  final String deviceId;
}

final class AppStarting extends FlutterToolEvent {
  const AppStarting({
    required this.appId,
    required this.deviceId,
    required this.mode,
  });
  final String appId;
  final String deviceId;
  final String mode;
}

final class AppDebugPort extends FlutterToolEvent {
  const AppDebugPort({required this.appId, required this.wsUri});
  final String appId;

  /// Dart VM service WebSocket URI, used by DevTools.
  final String wsUri;
}

final class AppStarted extends FlutterToolEvent {
  const AppStarted(this.appId);
  final String appId;
}

final class AppProgress extends FlutterToolEvent {
  const AppProgress({
    required this.appId,
    required this.message,
    required this.finished,
    this.progressId,
  });
  final String appId;

  /// Set to `hot.reload` / `hot.restart` while those operations run.
  final String? progressId;
  final String message;
  final bool finished;

  bool get isHotOperation => (progressId ?? '').startsWith('hot.');
}

final class AppLog extends FlutterToolEvent {
  const AppLog({
    required this.appId,
    required this.message,
    required this.isError,
  });
  final String appId;
  final String message;
  final bool isError;
}

final class AppStopped extends FlutterToolEvent {
  const AppStopped(this.appId);
  final String appId;
}

/// Plain (non-protocol) output or tool diagnostics.
final class ToolLog extends FlutterToolEvent {
  const ToolLog(this.message, {required this.isError});
  final String message;
  final bool isError;
}

/// The Flutter tool process ended.
final class ToolExited extends FlutterToolEvent {
  const ToolExited(this.exitCode);
  final int exitCode;
}

final class UnknownToolEvent extends FlutterToolEvent {
  const UnknownToolEvent(this.name, this.params);
  final String name;
  final Map<String, Object?> params;
}
