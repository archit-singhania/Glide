import 'package:path/path.dart' as p;

import 'host_environment.dart';
import 'tool_probe.dart';
import 'versions.dart';

/// A working Java runtime.
class JavaInfo {
  const JavaInfo({
    required this.executable,
    required this.version,
    required this.major,
  });

  final String executable;

  /// The full version string, for example `17.0.9`.
  final String version;

  /// The feature release, for example `17`.
  final int major;
}

/// Finds Java, preferring `JAVA_HOME`.
class JavaDetector {
  JavaDetector({required ToolProbe probe, required HostEnvironment host})
      : _probe = probe,
        _host = host;

  final ToolProbe _probe;
  final HostEnvironment _host;

  static final RegExp _versionPattern = RegExp(r'version "([^"]+)"');

  Future<Detection<JavaInfo>> detect() async {
    final executables = <String>[];
    final javaHome = _host.variable('JAVA_HOME');
    if (javaHome != null) {
      final bundled = p.join(javaHome, 'bin', _host.executableName('java'));
      if (_host.pathExists(bundled)) executables.add(bundled);
    }
    executables.add('java');

    String? lastFailure;
    for (final executable in executables) {
      final result = await _probe.run(executable, const <String>['-version']);
      if (!result.succeeded) {
        lastFailure = result.failure;
        continue;
      }
      final match = _versionPattern.firstMatch(result.output);
      if (match == null) {
        lastFailure = 'Could not read the Java version.';
        continue;
      }
      final version = match.group(1)!;
      return Detection<JavaInfo>.found(
        JavaInfo(
          executable: executable,
          version: version,
          major: parseJavaMajor(version),
        ),
      );
    }
    return Detection<JavaInfo>.missing(lastFailure ?? 'Java was not found.');
  }
}
