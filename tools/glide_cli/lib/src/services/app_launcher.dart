import 'package:glide_device_manager/glide_device_manager.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

import 'device_session.dart';

/// Starts `flutter run --machine`. The seam `glide run` and `glide start`
/// depend on, so tests never build a real app.
typedef FlutterAppLauncher = Future<AppSession> Function({
  required String projectPath,
  required String deviceId,
  String? flutterSdkPath,
  AppMode? mode,
});

/// Picks a device when none was named; null when there is no single obvious
/// choice.
typedef DefaultDeviceChooser = Future<String?> Function({
  String? flutterSdkPath,
});

/// The real launcher: locates the Flutter SDK and starts `flutter run`.
Future<AppSession> launchFlutterApp({
  required String projectPath,
  required String deviceId,
  String? flutterSdkPath,
  AppMode? mode,
}) async {
  final sdk = FlutterSdkLocator().locate(explicitPath: flutterSdkPath);
  if (sdk == null) {
    throw const ToolException(
      'Flutter SDK not found. Pass --flutter-sdk, set GLIDE_FLUTTER_SDK, or '
      'run "glide doctor" for guidance.',
    );
  }
  return FlutterAppSession.launch(
    launcher: const SystemProcessLauncher(),
    flutterExecutable: sdk.executable,
    projectPath: projectPath,
    deviceId: deviceId,
    mode: mode ?? AppMode.debug,
  );
}

/// The devices Glide would pick from automatically: mobile and ready.
List<GlideDevice> runnableDevices(List<GlideDevice> devices) => devices
    .where((d) => d.isMobile && d.state == DeviceLifecycle.ready)
    .toList();

/// The real chooser: asks the Flutter daemon, and answers only when exactly
/// one mobile device is ready.
Future<String?> chooseSystemDefaultDevice({String? flutterSdkPath}) async {
  final session = await openLiveDeviceSession(flutterSdkPath: flutterSdkPath);
  try {
    final candidates = runnableDevices(session.manager.devices);
    return candidates.length == 1 ? candidates.single.id : null;
  } finally {
    await session.close();
  }
}
