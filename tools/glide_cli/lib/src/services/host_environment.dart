import 'dart:io';

/// Decides whether a file or directory exists. Replaced in tests.
typedef PathExists = bool Function(String path);

/// What Glide reads from the machine it runs on.
///
/// Everything is injectable so detectors can be tested without touching the
/// real file system or environment.
class HostEnvironment {
  HostEnvironment({
    Map<String, String>? variables,
    String? operatingSystem,
    PathExists? pathExists,
  })  : variables = variables ?? Platform.environment,
        operatingSystem = operatingSystem ?? Platform.operatingSystem,
        pathExists = pathExists ?? _systemPathExists;

  /// Environment variables.
  final Map<String, String> variables;

  /// `windows`, `macos` or `linux`, as reported by [Platform.operatingSystem].
  final String operatingSystem;

  final PathExists pathExists;

  static bool _systemPathExists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  bool get isWindows => operatingSystem == 'windows';

  bool get isMacOS => operatingSystem == 'macos';

  /// The value of [name], or null when it is unset or empty.
  String? variable(String name) {
    final value = variables[name];
    return value == null || value.isEmpty ? null : value;
  }

  String? get homeDirectory => variable(isWindows ? 'USERPROFILE' : 'HOME');

  /// Adds the `.exe` suffix on Windows.
  String executableName(String name) => isWindows ? '$name.exe' : name;
}
