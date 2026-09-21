import 'project_model.dart';

/// What a changed file means for a running app.
enum ChangeImpact {
  /// Dart code under `lib/`: Flutter's hot reload picks it up.
  hotReload,

  /// The platform app or its dependencies changed. Hot reload cannot apply
  /// this; the app has to be rebuilt and relaunched.
  fullRestart,
}

/// One relevant file change in a project.
class ProjectChange {
  const ProjectChange({
    required this.path,
    required this.impact,
    required this.reason,
    this.platform,
  });

  /// Project-relative path with forward slashes.
  final String path;
  final ChangeImpact impact;

  /// A short sentence explaining the impact.
  final String reason;

  /// The platform the change belongs to, or null when it applies to all.
  final ProjectPlatform? platform;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'impact': impact.name,
        'reason': reason,
        if (platform != null) 'platform': platform!.name,
      };
}

/// Decides which file changes matter to a running Flutter app.
///
/// Files Flutter and Gradle regenerate during every build (`build/`,
/// `GeneratedPluginRegistrant.*`, `local.properties`, `Pods/`, ...) are
/// ignored, otherwise every build would look like a native change.
///
/// Only the Android and iOS project folders are classified. Desktop and web
/// runner folders are ignored for now.
abstract final class ChangeClassifier {
  /// Returns null for files that do not affect a running app.
  ///
  /// [relativePath] must be relative to the project root. Absolute paths and
  /// paths that leave the project are ignored.
  static ProjectChange? classify(String relativePath) {
    final path = relativePath.replaceAll(r'\', '/');
    if (path.isEmpty ||
        path.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(path)) {
      return null;
    }
    final segments = path.split('/');
    if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    if (_isNoise(segments)) return null;

    switch (segments.first) {
      case 'pubspec.yaml':
        return ProjectChange(
          path: path,
          impact: ChangeImpact.fullRestart,
          reason: 'pubspec.yaml changed (dependencies or project settings)',
        );
      case 'pubspec.lock':
        return ProjectChange(
          path: path,
          impact: ChangeImpact.fullRestart,
          reason: 'pubspec.lock changed (resolved dependencies)',
        );
      case 'lib':
        if (!path.endsWith('.dart')) return null;
        return ProjectChange(
          path: path,
          impact: ChangeImpact.hotReload,
          reason: 'Dart source changed',
        );
      case 'android':
        return _native(path, segments, ProjectPlatform.android);
      case 'ios':
        return _native(path, segments, ProjectPlatform.ios);
      default:
        return null;
    }
  }

  static const Set<String> _ignoredTopLevel = <String>{
    '.dart_tool',
    '.git',
    '.idea',
    '.vscode',
    'build',
  };

  static const Set<String> _generatedNames = <String>{
    'local.properties',
    'Generated.xcconfig',
    'flutter_export_environment.sh',
    'Podfile.lock',
    'Package.resolved',
    '.DS_Store',
    '.gitignore',
  };

  static const Set<String> _ignoredExtensions = <String>{
    '.md',
    '.iml',
    '.log',
    '.tmp',
    '.swp',
    '.swx',
  };

  static bool _isNoise(List<String> segments) {
    final name = segments.last;
    if (_ignoredTopLevel.contains(segments.first)) return true;
    if (_generatedNames.contains(name)) return true;
    if (name.startsWith('GeneratedPluginRegistrant')) return true;
    if (name.endsWith('~') || name.startsWith('.#')) return true;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && _ignoredExtensions.contains(name.substring(dot))) {
      return true;
    }
    for (final segment in segments) {
      if (segment == 'xcuserdata' ||
          segment == 'DerivedData' ||
          segment == 'ephemeral' ||
          segment == '.symlinks' ||
          segment == 'Pods' ||
          segment == '.gradle' ||
          segment == '.kotlin') {
        return true;
      }
    }
    // Build output folders of the platform projects.
    final platformFolder =
        segments.first == 'android' || segments.first == 'ios';
    if (platformFolder && segments.length > 1 && segments[1] == 'build') {
      return true;
    }
    if (segments.first == 'android' &&
        segments.length > 2 &&
        segments[1] == 'app' &&
        segments[2] == 'build') {
      return true;
    }
    return false;
  }

  static ProjectChange? _native(
    String path,
    List<String> segments,
    ProjectPlatform platform,
  ) {
    // A file directly inside `android/` or `ios/` is still a project file;
    // a bare directory name is not.
    if (segments.length < 2) return null;
    final name = segments.last;
    final lower = name.toLowerCase();
    final String reason;
    if (platform == ProjectPlatform.android) {
      if (lower.endsWith('.kt') || lower.endsWith('.java')) {
        reason = 'Android native code changed';
      } else if (name == 'AndroidManifest.xml') {
        reason = 'AndroidManifest.xml changed';
      } else if (lower.endsWith('.gradle') ||
          lower.endsWith('.kts') ||
          lower.endsWith('.properties')) {
        reason = 'Android build configuration changed';
      } else {
        reason = 'An Android project file changed';
      }
    } else {
      if (lower.endsWith('.swift') ||
          lower.endsWith('.m') ||
          lower.endsWith('.mm') ||
          lower.endsWith('.h') ||
          lower.endsWith('.c') ||
          lower.endsWith('.cpp')) {
        reason = 'iOS native code changed';
      } else if (lower.endsWith('.plist')) {
        reason = '$name changed';
      } else if (lower.endsWith('.xcconfig') ||
          lower.endsWith('.pbxproj') ||
          name == 'Podfile' ||
          name == 'Package.swift') {
        reason = 'iOS build configuration changed';
      } else {
        reason = 'An iOS project file changed';
      }
    }
    return ProjectChange(
      path: path,
      impact: ChangeImpact.fullRestart,
      reason: reason,
      platform: platform,
    );
  }
}
