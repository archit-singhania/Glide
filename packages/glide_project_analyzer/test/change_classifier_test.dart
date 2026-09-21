import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeClassifier', () {
    test('Dart files under lib are hot reloadable', () {
      final change = ChangeClassifier.classify('lib/ui/home.dart')!;

      expect(change.impact, ChangeImpact.hotReload);
      expect(change.platform, isNull);
    });

    test('Windows separators are normalised', () {
      final change = ChangeClassifier.classify(r'lib\ui\home.dart')!;

      expect(change.path, 'lib/ui/home.dart');
      expect(change.impact, ChangeImpact.hotReload);
    });

    test('pubspec changes need a full restart', () {
      for (final file in <String>['pubspec.yaml', 'pubspec.lock']) {
        final change = ChangeClassifier.classify(file)!;
        expect(change.impact, ChangeImpact.fullRestart, reason: file);
        expect(change.platform, isNull, reason: file);
      }
    });

    test('Android native and build files need a full restart', () {
      const files = <String, String>{
        'android/app/src/main/kotlin/com/x/MainActivity.kt':
            'Android native code changed',
        'android/app/src/main/java/com/x/Legacy.java':
            'Android native code changed',
        'android/app/src/main/AndroidManifest.xml':
            'AndroidManifest.xml changed',
        'android/app/build.gradle.kts': 'Android build configuration changed',
        'android/gradle.properties': 'Android build configuration changed',
        'android/app/src/main/res/values/styles.xml':
            'An Android project file changed',
      };
      files.forEach((file, reason) {
        final change = ChangeClassifier.classify(file)!;
        expect(change.impact, ChangeImpact.fullRestart, reason: file);
        expect(change.platform, ProjectPlatform.android, reason: file);
        expect(change.reason, reason, reason: file);
      });
    });

    test('iOS native and build files need a full restart', () {
      const files = <String, String>{
        'ios/Runner/AppDelegate.swift': 'iOS native code changed',
        'ios/Runner/Bridge.m': 'iOS native code changed',
        'ios/Runner/Info.plist': 'Info.plist changed',
        'ios/Podfile': 'iOS build configuration changed',
        'ios/Flutter/Debug.xcconfig': 'iOS build configuration changed',
      };
      files.forEach((file, reason) {
        final change = ChangeClassifier.classify(file)!;
        expect(change.impact, ChangeImpact.fullRestart, reason: file);
        expect(change.platform, ProjectPlatform.ios, reason: file);
        expect(change.reason, reason, reason: file);
      });
    });

    test('generated, build and unrelated files are ignored', () {
      const ignored = <String>[
        'build/app/outputs/flutter-apk/app-debug.apk',
        '.dart_tool/package_config.json',
        '.git/index',
        'android/local.properties',
        'android/.gradle/8.5/checksums.bin',
        'android/build/reports/x.html',
        'android/app/build/outputs/apk/debug/app-debug.apk',
        'android/app/src/main/java/io/flutter/plugins/'
            'GeneratedPluginRegistrant.java',
        'ios/Pods/Target Support Files/x.xcconfig',
        'ios/Podfile.lock',
        'ios/Flutter/Generated.xcconfig',
        'ios/Flutter/flutter_export_environment.sh',
        'ios/Runner/GeneratedPluginRegistrant.m',
        'ios/build/Runner.app',
        'ios/Runner.xcodeproj/xcuserdata/dev.xcuserdatad/x.plist',
        'lib/main.dart~',
        'lib/l10n/app_en.arb',
        'README.md',
        'test/widget_test.dart',
        'assets/logo.png',
        'windows/runner/main.cpp',
      ];
      for (final file in ignored) {
        expect(ChangeClassifier.classify(file), isNull, reason: file);
      }
    });

    test('a folder named build inside lib is still Dart source', () {
      expect(
        ChangeClassifier.classify('lib/build/step.dart')?.impact,
        ChangeImpact.hotReload,
      );
    });

    test('paths outside the project are ignored', () {
      for (final file in <String>[
        '../other/lib/main.dart',
        '/abs/lib/main.dart',
        'C:/proj/lib/main.dart',
        r'C:\proj\lib\main.dart',
        '',
        'lib/../android/app/build.gradle',
      ]) {
        expect(ChangeClassifier.classify(file), isNull, reason: file);
      }
    });

    test('changes serialise', () {
      final json =
          ChangeClassifier.classify('android/app/build.gradle')!.toJson();

      expect(json['impact'], 'fullRestart');
      expect(json['platform'], 'android');
      expect(json['path'], 'android/app/build.gradle');
    });
  });
}
