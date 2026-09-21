import 'package:glide_device_manager/glide_device_manager.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

/// Ties a live [DeviceManager] to whatever process is feeding it its events,
/// so a caller can shut everything down with one call.
class DeviceSession {
  DeviceSession({
    required this.manager,
    required Future<void> Function() onClose,
  }) : _onClose = onClose;

  final DeviceManager manager;
  final Future<void> Function() _onClose;

  /// Disposes the manager and stops the underlying process. Safe to call
  /// more than once.
  Future<void> close() async {
    await manager.dispose();
    await _onClose();
  }
}

/// Opens a [DeviceSession], given an optional explicit Flutter SDK path.
/// The seam `glide devices` depends on, so tests never spawn a real daemon.
typedef DeviceSessionOpener = Future<DeviceSession> Function({
  String? flutterSdkPath,
});

/// The real opener: locates the Flutter SDK, starts `flutter daemon`, and
/// wires its events into a [DeviceManager] seeded with an initial listing.
Future<DeviceSession> openLiveDeviceSession({String? flutterSdkPath}) async {
  final locator = FlutterSdkLocator();
  final sdk = locator.locate(explicitPath: flutterSdkPath);
  if (sdk == null) {
    throw const ToolException(
      'Flutter SDK not found. Pass --flutter-sdk, set GLIDE_FLUTTER_SDK, or '
      'run "glide doctor" for guidance.',
    );
  }
  final daemon = FlutterDaemonClient(
    launcher: const SystemProcessLauncher(),
    flutterExecutable: sdk.executable,
  );
  await daemon.start();
  final manager = DeviceManager(events: daemon.events);
  await manager.refresh(daemon.getDevices);
  return DeviceSession(manager: manager, onClose: daemon.shutdown);
}
