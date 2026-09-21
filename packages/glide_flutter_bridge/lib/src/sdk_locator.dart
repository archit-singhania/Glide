import 'dart:io';

import 'package:path/path.dart' as p;

/// A discovered Flutter SDK.
class FlutterSdkLocation {
  const FlutterSdkLocation({
    required this.executable,
    required this.root,
    required this.isWindows,
  });

  /// Absolute path to `flutter` / `flutter.bat`.
  final String executable;

  /// SDK root directory, if it could be derived.
  final String? root;

  final bool isWindows;

  /// The `dart` executable bundled with this SDK, when known.
  String? get dartExecutable {
    final r = root;
    if (r == null) return null;
    return p.join(r, 'bin', isWindows ? 'dart.bat' : 'dart');
  }
}

/// Finds the Flutter SDK without hard-coded paths.
///
/// Order: explicit path, `GLIDE_FLUTTER_SDK`, `FLUTTER_ROOT`, `FLUTTER_HOME`,
/// then the `PATH`.
class FlutterSdkLocator {
  FlutterSdkLocator({Map<String, String>? environment, bool? isWindows})
      : _environment = environment ?? Platform.environment,
        _isWindows = isWindows ?? Platform.isWindows;

  final Map<String, String> _environment;
  final bool _isWindows;

  String get _binaryName => _isWindows ? 'flutter.bat' : 'flutter';

  FlutterSdkLocation? locate({String? explicitPath}) {
    if (explicitPath != null) {
      return _fromPath(explicitPath);
    }
    for (final key in const [
      'GLIDE_FLUTTER_SDK',
      'FLUTTER_ROOT',
      'FLUTTER_HOME',
    ]) {
      final value = _environment[key];
      if (value != null && value.isNotEmpty) {
        final found = _fromPath(value);
        if (found != null) return found;
      }
    }
    return _fromPathVariable();
  }

  FlutterSdkLocation? _fromPath(String path) {
    if (File(path).existsSync()) return _describe(path);
    final candidate = p.join(path, 'bin', _binaryName);
    if (File(candidate).existsSync()) return _describe(candidate);
    return null;
  }

  FlutterSdkLocation? _fromPathVariable() {
    final pathValue = _environment['PATH'] ?? _environment['Path'] ?? '';
    final separator = _isWindows ? ';' : ':';
    for (final directory in pathValue.split(separator)) {
      if (directory.isEmpty) continue;
      final candidate = p.join(directory, _binaryName);
      if (File(candidate).existsSync()) return _describe(candidate);
    }
    return null;
  }

  FlutterSdkLocation _describe(String executable) {
    var resolved = executable;
    try {
      resolved = File(executable).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Keep the unresolved path; it still exists.
    }
    final binDir = p.dirname(resolved);
    final root = p.basename(binDir) == 'bin' ? p.dirname(binDir) : null;
    return FlutterSdkLocation(
      executable: resolved,
      root: root,
      isWindows: _isWindows,
    );
  }
}
