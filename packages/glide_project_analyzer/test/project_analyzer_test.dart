import 'dart:io';

import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: shop_app
description: A shop.
version: 1.2.3+4
environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.0
  local_pkg:
    path: ../local_pkg
  from_git:
    git: https://example.com/x.git
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - path: assets/logo.png
  fonts:
    - family: Inter
      fonts:
        - asset: fonts/Inter.ttf
''';

const String _pluginsJson = '''
{
  "info": "This is a generated file; do not edit or check into version control.",
  "plugins": {
    "ios": [
      {"name": "camera_avfoundation", "native_build": true},
      {"name": "shared_preferences_foundation", "native_build": true},
      {"name": "dart_only_impl", "native_build": false}
    ],
    "android": [
      {"name": "camera_android", "native_build": true},
      {"name": "shared_preferences_android"}
    ],
    "web": [
      {"name": "camera_web", "native_build": false}
    ]
  }
}
''';

void _write(Directory root, String relative, String contents) {
  File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('glide_project_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('PubspecReader', () {
    test('reads the fields Glide needs', () {
      final data = PubspecReader.parse(_pubspec);

      expect(data.name, 'shop_app');
      expect(data.description, 'A shop.');
      expect(data.version, '1.2.3+4');
      expect(data.dartConstraint, '^3.6.0');
      expect(data.flutterConstraint, '>=3.27.0');
      expect(data.isFlutterProject, isTrue);
      expect(data.dependencies['camera'], '^0.11.0');
      expect(data.dependencies['flutter'], 'sdk: flutter');
      expect(data.dependencies['local_pkg'], 'path: ../local_pkg');
      expect(data.dependencies['from_git'], 'git');
      expect(data.devDependencies.keys, contains('flutter_test'));
      expect(data.assets, <String>['assets/images/', 'assets/logo.png']);
      expect(data.fontFamilies, <String>['Inter']);
    });

    test('recognises a plain Dart package', () {
      final data = PubspecReader.parse(
        'name: tool\ndependencies:\n  path: ^1.9.0\n',
      );
      expect(data.isFlutterProject, isFalse);
    });

    test('rejects invalid input with typed errors', () {
      expect(
        () => PubspecReader.parse('a: [unclosed'),
        throwsA(isA<ProjectException>()),
      );
      expect(
        () => PubspecReader.parse('- just\n- a list\n'),
        throwsA(isA<ProjectException>()),
      );
      expect(
        () => PubspecReader.parse('description: no name\n'),
        throwsA(isA<ProjectException>()),
      );
      expect(() => PubspecReader.parse(''), throwsA(isA<ProjectException>()));
    });
  });

  group('PlatformDetector', () {
    test('detects platform folders', () {
      Directory(p.join(root.path, 'android')).createSync();
      Directory(p.join(root.path, 'ios')).createSync();

      expect(
        PlatformDetector.detect(root.path),
        <ProjectPlatform>{ProjectPlatform.android, ProjectPlatform.ios},
      );
    });

    test('reads the Gradle application id (kts and groovy)', () {
      _write(
        root,
        'android/app/build.gradle.kts',
        'defaultConfig {\n  applicationId = "com.example.shop"\n}\n',
      );
      expect(
        PlatformDetector.androidApplicationId(root.path),
        'com.example.shop',
      );

      final groovy = Directory.systemTemp.createTempSync('glide_groovy_');
      addTearDown(() => groovy.deleteSync(recursive: true));
      _write(
        groovy,
        'android/app/build.gradle',
        "defaultConfig {\n  applicationId 'com.example.old'\n}\n",
      );
      expect(
        PlatformDetector.androidApplicationId(groovy.path),
        'com.example.old',
      );
    });

    test('returns null when the application id is not a plain string', () {
      _write(
        root,
        'android/app/build.gradle.kts',
        'applicationId = project.property("id")\n',
      );
      expect(PlatformDetector.androidApplicationId(root.path), isNull);
    });

    test('reads the iOS bundle id, skipping the test target', () {
      _write(
        root,
        'ios/Runner.xcodeproj/project.pbxproj',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.shop.RunnerTests;\n'
            'PRODUCT_BUNDLE_IDENTIFIER = com.example.shop;\n',
      );
      expect(PlatformDetector.iosBundleId(root.path), 'com.example.shop');
    });

    test('missing project files give null', () {
      expect(PlatformDetector.androidApplicationId(root.path), isNull);
      expect(PlatformDetector.iosBundleId(root.path), isNull);
    });
  });

  group('NativePluginScanner', () {
    test('reports unresolved when pub get has not run', () {
      final scan = NativePluginScanner.scan(root.path);
      expect(scan.resolved, isFalse);
      expect(scan.plugins, isEmpty);
    });

    test('merges platforms, drops Dart-only and web plugins', () {
      _write(root, '.flutter-plugins-dependencies', _pluginsJson);
      final scan = NativePluginScanner.scan(root.path);

      expect(scan.resolved, isTrue);
      expect(
        scan.plugins.map((plugin) => plugin.name),
        <String>[
          'camera_android',
          'camera_avfoundation',
          'shared_preferences_android',
          'shared_preferences_foundation',
        ],
      );
    });

    test('rejects a corrupt file', () {
      _write(root, '.flutter-plugins-dependencies', '{nope');
      expect(
        () => NativePluginScanner.scan(root.path),
        throwsA(isA<ProjectException>()),
      );
    });
  });

  group('FlutterProjectAnalyzer', () {
    test('analyses a project end to end', () async {
      _write(root, 'pubspec.yaml', _pubspec);
      _write(
        root,
        'android/app/build.gradle.kts',
        'applicationId = "com.example.shop"\n',
      );
      _write(
        root,
        'ios/Runner.xcodeproj/project.pbxproj',
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.shop;\n',
      );
      _write(root, '.flutter-plugins-dependencies', _pluginsJson);

      final info = await const FlutterProjectAnalyzer().analyze(root.path);

      expect(info.name, 'shop_app');
      expect(
        info.platforms,
        <ProjectPlatform>{ProjectPlatform.android, ProjectPlatform.ios},
      );
      expect(info.androidApplicationId, 'com.example.shop');
      expect(info.iosBundleId, 'com.example.shop');
      expect(info.pluginsResolved, isTrue);
      expect(info.nativePlugins, hasLength(4));
      expect(info.toJson()['name'], 'shop_app');
    });

    test('refuses a directory without pubspec.yaml', () {
      expect(
        const FlutterProjectAnalyzer().analyze(root.path),
        throwsA(isA<ProjectException>()),
      );
    });

    test('refuses a plain Dart package', () {
      _write(root, 'pubspec.yaml', 'name: tool\n');
      expect(
        const FlutterProjectAnalyzer().analyze(root.path),
        throwsA(isA<ProjectException>()),
      );
    });

    test('findProjectRoot walks up to the nearest pubspec', () {
      _write(root, 'pubspec.yaml', _pubspec);
      Directory(p.join(root.path, 'lib', 'src')).createSync(recursive: true);

      expect(
        FlutterProjectAnalyzer.findProjectRoot(
          p.join(root.path, 'lib', 'src'),
        ),
        p.normalize(root.path),
      );
    });
  });
}
