import 'package:path/path.dart' as p;

import 'host_environment.dart';

/// An Android SDK directory.
class AndroidSdkInfo {
  const AndroidSdkInfo({required this.path, required this.hasPlatformTools});

  final String path;

  /// Whether the `platform-tools` directory (which holds `adb`) exists.
  final bool hasPlatformTools;

  String get platformToolsPath => p.join(path, 'platform-tools');
}

/// Finds the Android SDK without hard-coded paths.
///
/// Order: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, then the default location for
/// the operating system.
class AndroidSdkDetector {
  const AndroidSdkDetector(this._host);

  final HostEnvironment _host;

  /// Candidate SDK directories, most specific first.
  List<String> candidates() {
    final result = <String>[];
    void add(String? value) {
      if (value != null) result.add(value);
    }

    add(_host.variable('ANDROID_HOME'));
    add(_host.variable('ANDROID_SDK_ROOT'));

    final home = _host.homeDirectory;
    if (_host.isWindows) {
      final local = _host.variable('LOCALAPPDATA');
      if (local != null) add(p.join(local, 'Android', 'Sdk'));
    } else if (home != null) {
      add(
        _host.isMacOS
            ? p.join(home, 'Library', 'Android', 'sdk')
            : p.join(home, 'Android', 'Sdk'),
      );
    }
    return result;
  }

  /// The first candidate that exists, or null.
  AndroidSdkInfo? detect() {
    for (final candidate in candidates()) {
      if (_host.pathExists(candidate)) {
        return AndroidSdkInfo(
          path: candidate,
          hasPlatformTools:
              _host.pathExists(p.join(candidate, 'platform-tools')),
        );
      }
    }
    return null;
  }
}
