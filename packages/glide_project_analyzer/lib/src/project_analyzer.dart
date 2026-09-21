import 'dart:io';

import 'package:path/path.dart' as p;

import 'dependency_analyzer.dart';
import 'platform_detector.dart';
import 'project_model.dart';
import 'pubspec_reader.dart';

/// Inspects a Flutter project directory.
abstract interface class ProjectAnalyzer {
  /// Reads the project at [directory], which must contain `pubspec.yaml`.
  ///
  /// Throws [ProjectException] when it is missing, unreadable or not a Flutter
  /// project.
  Future<ProjectInfo> analyze(String directory);
}

/// Reads `pubspec.yaml`, platform folders and Flutter's generated plugin list.
class FlutterProjectAnalyzer implements ProjectAnalyzer {
  const FlutterProjectAnalyzer();

  /// Walks up from [start] to the nearest directory with a `pubspec.yaml`.
  static String? findProjectRoot(String start) {
    var current = p.normalize(p.absolute(start));
    while (true) {
      if (File(p.join(current, 'pubspec.yaml')).existsSync()) return current;
      final parent = p.dirname(current);
      if (parent == current) return null;
      current = parent;
    }
  }

  @override
  Future<ProjectInfo> analyze(String directory) async {
    if (!Directory(directory).existsSync()) {
      throw ProjectException('Directory not found: $directory');
    }
    final pubspecFile = File(p.join(directory, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw ProjectException('No pubspec.yaml in $directory.');
    }

    final pubspec = PubspecReader.parse(await pubspecFile.readAsString());
    if (!pubspec.isFlutterProject) {
      throw ProjectException(
        '"${pubspec.name}" is a Dart package, not a Flutter project '
        '(it does not depend on the Flutter SDK).',
      );
    }

    final scan = NativePluginScanner.scan(directory);
    return ProjectInfo(
      name: pubspec.name,
      rootPath: directory,
      description: pubspec.description,
      version: pubspec.version,
      dartConstraint: pubspec.dartConstraint,
      flutterConstraint: pubspec.flutterConstraint,
      dependencies: pubspec.dependencies,
      devDependencies: pubspec.devDependencies,
      platforms: PlatformDetector.detect(directory),
      androidApplicationId: PlatformDetector.androidApplicationId(directory),
      iosBundleId: PlatformDetector.iosBundleId(directory),
      assets: pubspec.assets,
      fontFamilies: pubspec.fontFamilies,
      nativePlugins: scan.plugins,
      pluginsResolved: scan.resolved,
    );
  }
}
