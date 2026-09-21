import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

import 'device_lifecycle.dart';

/// A device tracked by [DeviceManager]: the Flutter tool's view of it, plus
/// Glide's own lifecycle state and when it was last seen.
class GlideDevice {
  const GlideDevice({
    required this.device,
    required this.state,
    required this.lastSeenAt,
  });

  final FlutterDevice device;
  final DeviceLifecycle state;
  final DateTime lastSeenAt;

  String get id => device.id;
  String get name => device.name;
  String get platform => device.platform;
  bool get isEmulator => device.isEmulator;
  bool get isAndroid => device.isAndroid;
  bool get isIos => device.isIos;
  bool get isMobile => device.isMobile;

  GlideDevice copyWith({
    FlutterDevice? device,
    DeviceLifecycle? state,
    DateTime? lastSeenAt,
  }) =>
      GlideDevice(
        device: device ?? this.device,
        state: state ?? this.state,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        ...device.toJson(),
        'state': state.name,
        'lastSeenAt': lastSeenAt.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is GlideDevice && other.id == id && other.state == state;

  @override
  int get hashCode => Object.hash(id, state);

  @override
  String toString() => 'GlideDevice($name, $id, ${state.name})';
}
