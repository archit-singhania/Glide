import 'package:path/path.dart' as p;

import 'android_sdk_detector.dart';
import 'host_environment.dart';
import 'tool_probe.dart';

/// A working `adb`.
class AdbInfo {
  const AdbInfo({required this.executable, required this.version});

  /// The command that worked: an absolute path, or `adb` from `PATH`.
  final String executable;

  /// For example `1.0.41`, or `unknown` if the output was unrecognised.
  final String version;
}

/// Finds `adb`, preferring the one inside the Android SDK.
class AdbDetector {
  AdbDetector({required ToolProbe probe, required HostEnvironment host})
      : _probe = probe,
        _host = host;

  final ToolProbe _probe;
  final HostEnvironment _host;

  static final RegExp _versionPattern = RegExp(
    r'Android Debug Bridge version (\S+)',
  );

  Future<Detection<AdbInfo>> detect({AndroidSdkInfo? sdk}) async {
    final executables = <String>[
      if (sdk != null && sdk.hasPlatformTools)
        p.join(sdk.platformToolsPath, _host.executableName('adb')),
      'adb',
    ];

    String? lastFailure;
    for (final executable in executables) {
      if (p.isAbsolute(executable) && !_host.pathExists(executable)) {
        lastFailure = '"$executable" does not exist.';
        continue;
      }
      final result = await _probe.run(executable, const <String>['version']);
      if (!result.succeeded) {
        lastFailure = result.failure;
        continue;
      }
      final match = _versionPattern.firstMatch(result.output);
      return Detection<AdbInfo>.found(
        AdbInfo(executable: executable, version: match?.group(1) ?? 'unknown'),
      );
    }
    return Detection<AdbInfo>.missing(lastFailure ?? 'adb was not found.');
  }
}
