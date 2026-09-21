import 'package:glide_protocol/glide_protocol.dart';

/// Raised when a project cannot be read or is not a Flutter project.
class ProjectException extends GlideException {
  const ProjectException(super.message, {super.cause});
}

/// Platforms a Flutter project can target.
enum ProjectPlatform {
  android,
  ios,
  web,
  windows,
  macos,
  linux;

  String get label => switch (this) {
        ProjectPlatform.android => 'Android',
        ProjectPlatform.ios => 'iOS',
        ProjectPlatform.web => 'Web',
        ProjectPlatform.windows => 'Windows',
        ProjectPlatform.macos => 'macOS',
        ProjectPlatform.linux => 'Linux',
      };
}

/// A dependency with native (non-Dart) code, as resolved by `flutter pub get`.
class NativePlugin {
  const NativePlugin({required this.name, required this.platforms});

  /// The plugin package name. This is the platform implementation package, for
  /// example `camera_android`, not the app-facing `camera`.
  final String name;

  final Set<ProjectPlatform> platforms;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'platforms': (platforms.map((p) => p.name).toList()..sort()),
      };
}

/// Everything `glide inspect` learns about a Flutter project.
class ProjectInfo {
  const ProjectInfo({
    required this.name,
    required this.rootPath,
    required this.platforms,
    this.description,
    this.version,
    this.dartConstraint,
    this.flutterConstraint,
    this.dependencies = const <String, String>{},
    this.devDependencies = const <String, String>{},
    this.androidApplicationId,
    this.iosBundleId,
    this.assets = const <String>[],
    this.fontFamilies = const <String>[],
    this.nativePlugins = const <NativePlugin>[],
    this.pluginsResolved = false,
  });

  final String name;
  final String rootPath;
  final String? description;
  final String? version;

  /// `environment.sdk` from `pubspec.yaml`.
  final String? dartConstraint;

  /// `environment.flutter` from `pubspec.yaml`, if declared.
  final String? flutterConstraint;

  /// Package name to a short description of the constraint.
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;

  final Set<ProjectPlatform> platforms;
  final String? androidApplicationId;
  final String? iosBundleId;
  final List<String> assets;
  final List<String> fontFamilies;

  /// Empty and [pluginsResolved] false until `flutter pub get` has run.
  final List<NativePlugin> nativePlugins;
  final bool pluginsResolved;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'rootPath': rootPath,
        if (description != null) 'description': description,
        if (version != null) 'version': version,
        if (dartConstraint != null) 'dartConstraint': dartConstraint,
        if (flutterConstraint != null) 'flutterConstraint': flutterConstraint,
        'platforms': (platforms.map((p) => p.name).toList()..sort()),
        if (androidApplicationId != null)
          'androidApplicationId': androidApplicationId,
        if (iosBundleId != null) 'iosBundleId': iosBundleId,
        'dependencies': dependencies,
        'devDependencies': devDependencies,
        'assets': assets,
        'fontFamilies': fontFamilies,
        'pluginsResolved': pluginsResolved,
        'nativePlugins': nativePlugins.map((p) => p.toJson()).toList(),
      };
}
