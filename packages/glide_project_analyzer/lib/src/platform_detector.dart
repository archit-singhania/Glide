import 'dart:io';

import 'package:path/path.dart' as p;

import 'project_model.dart';

/// Detects which platforms a project supports and its application ids.
abstract final class PlatformDetector {
  /// Platforms whose runner directory (`android/`, `ios/`, ...) exists.
  static Set<ProjectPlatform> detect(String projectDir) => <ProjectPlatform>{
        for (final platform in ProjectPlatform.values)
          if (Directory(p.join(projectDir, platform.name)).existsSync())
            platform,
      };

  static final RegExp _applicationId = RegExp(
    r'''applicationId\s*=?\s*["']([^"']+)["']''',
  );

  /// The Gradle `applicationId`, or null when it is not a plain string.
  static String? androidApplicationId(String projectDir) {
    for (final relative in const <String>[
      'build.gradle.kts',
      'build.gradle',
    ]) {
      final file = File(p.join(projectDir, 'android', 'app', relative));
      if (!file.existsSync()) continue;
      final match = _applicationId.firstMatch(file.readAsStringSync());
      if (match != null) return match.group(1);
    }
    return null;
  }

  static final RegExp _bundleId = RegExp(
    r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";\s]+)"?\s*;',
  );

  /// The app's bundle identifier, ignoring the test target and Xcode
  /// variables such as `$(PRODUCT_NAME)`.
  static String? iosBundleId(String projectDir) {
    final file = File(
      p.join(projectDir, 'ios', 'Runner.xcodeproj', 'project.pbxproj'),
    );
    if (!file.existsSync()) return null;
    for (final match in _bundleId.allMatches(file.readAsStringSync())) {
      final id = match.group(1)!;
      if (id.contains(r'$(') || id.endsWith('.RunnerTests')) continue;
      return id;
    }
    return null;
  }
}
