import 'dart:convert';
import 'dart:io';

import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _cameraPlist = '<key>NSCameraUsageDescription</key>';
const String _locationPlist = '<key>NSLocationWhenInUseUsageDescription</key>';

String _pubspecWith(List<String> dependencies) => '''
name: shop_app
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
${dependencies.map((d) => '  $d: ^1.0.0\n').join()}''';

Map<String, Object?> _plugin(String name, {bool native = true}) =>
    <String, Object?>{'name': name, 'native_build': native};

void _write(Directory root, String relative, String contents) {
  File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('glide_plugins_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProjectInfo> project({
    required List<String> dependencies,
    required List<String> platformDirs,
    Map<String, List<Map<String, Object?>>>? plugins,
    Map<String, String> files = const <String, String>{},
  }) async {
    _write(root, 'pubspec.yaml', _pubspecWith(dependencies));
    for (final dir in platformDirs) {
      Directory(p.join(root.path, dir)).createSync(recursive: true);
    }
    if (plugins != null) {
      _write(
        root,
        '.flutter-plugins-dependencies',
        jsonEncode(<String, Object?>{'plugins': plugins}),
      );
    }
    files.forEach((path, contents) => _write(root, path, contents));
    return const FlutterProjectAnalyzer().analyze(root.path);
  }

  group('NativePluginScanner.registered', () {
    test('includes Dart-only and web registrations', () {
      _write(
        root,
        '.flutter-plugins-dependencies',
        jsonEncode(<String, Object?>{
          'plugins': <String, Object?>{
            'ios': <Object?>[_plugin('camera_avfoundation')],
            'web': <Object?>[_plugin('camera_web', native: false)],
            'windows': <Object?>[_plugin('dart_only_impl', native: false)],
          },
        }),
      );

      final scan = NativePluginScanner.scan(root.path);

      expect(scan.registered['camera_web'], <ProjectPlatform>{
        ProjectPlatform.web,
      });
      expect(scan.registered['dart_only_impl'], <ProjectPlatform>{
        ProjectPlatform.windows,
      });
      expect(
        scan.plugins.map((plugin) => plugin.name),
        <String>['camera_avfoundation'],
        reason: 'the native list must still exclude Dart-only and web entries',
      );
    });
  });

  group('PluginAnalyzer', () {
    test('classifies a plugin and checks its host configuration', () async {
      final info = await project(
        dependencies: <String>['camera'],
        platformDirs: <String>['android', 'ios'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[_plugin('camera_android')],
          'ios': <Map<String, Object?>>[_plugin('camera_avfoundation')],
          'web': <Map<String, Object?>>[_plugin('camera_web', native: false)],
        },
        files: <String, String>{'ios/Runner/Info.plist': _cameraPlist},
      );

      final report = const PluginAnalyzer().analyze(info);

      expect(report.resolved, isTrue);
      expect(report.assessments, hasLength(1));
      final camera = report.assessments.single;
      expect(camera.package, 'camera');
      expect(camera.kind, PluginKind.nativeAndroidAndIos);
      expect(
        camera.implementations,
        <String>['camera_android', 'camera_avfoundation'],
      );
      expect(camera.unsupportedOn, isEmpty);
      expect(
        camera.requirements.map((r) => r.state),
        <RequirementState>[
          RequirementState.satisfied,
          RequirementState.missing,
        ],
        reason: 'the camera key is present, the microphone key is not',
      );
      expect(camera.status, PluginStatus.requiresConfiguration);
      expect(report.hasProblems, isTrue);
    });

    test('checks Android permissions in the manifest', () async {
      final info = await project(
        dependencies: <String>['geolocator'],
        platformDirs: <String>['android', 'ios'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[_plugin('geolocator_android')],
          'ios': <Map<String, Object?>>[_plugin('geolocator_apple')],
        },
        files: <String, String>{
          'android/app/src/main/AndroidManifest.xml': '<manifest></manifest>',
          'ios/Runner/Info.plist': _locationPlist,
        },
      );

      final geolocator =
          const PluginAnalyzer().analyze(info).assessments.single;

      expect(
        geolocator.requirements.map((r) => r.state),
        <RequirementState>[
          RequirementState.missing,
          RequirementState.satisfied,
        ],
      );
      expect(
        geolocator.requirements.first.detail,
        'Not found in android/app/src/main/AndroidManifest.xml',
      );
    });

    test('reports a missing configuration file', () async {
      final info = await project(
        dependencies: <String>['geolocator'],
        platformDirs: <String>['android'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[_plugin('geolocator_android')],
        },
      );

      final result = const PluginAnalyzer()
          .analyze(info)
          .assessments
          .single
          .requirements
          .single;

      expect(result.state, RequirementState.missing);
      expect(
        result.detail,
        'File not found: android/app/src/main/AndroidManifest.xml',
      );
    });

    test('flags a plugin with no implementation for a targeted platform',
        () async {
      final info = await project(
        dependencies: <String>['droid_only'],
        platformDirs: <String>['android', 'ios'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[_plugin('droid_only')],
        },
      );

      final assessment =
          const PluginAnalyzer().analyze(info).assessments.single;

      expect(assessment.kind, PluginKind.nativeAndroid);
      expect(assessment.unsupportedOn, <ProjectPlatform>{ProjectPlatform.ios});
      expect(assessment.status, PluginStatus.unsupported);
    });

    test('does not attribute share_plus to a dependency called share',
        () async {
      final info = await project(
        dependencies: <String>['share', 'share_plus'],
        platformDirs: <String>['android'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[_plugin('share_plus')],
        },
      );

      final report = const PluginAnalyzer().analyze(info);

      expect(report.assessments.map((a) => a.package), <String>['share_plus']);
      expect(report.dartOnlyDependencies, 1);
    });

    test('lists native plugins no direct dependency accounts for', () async {
      final info = await project(
        dependencies: <String>['camera'],
        platformDirs: <String>['android'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[
            _plugin('camera_android'),
            _plugin('flutter_plugin_android_lifecycle'),
          ],
        },
      );

      final report = const PluginAnalyzer().analyze(info);

      expect(
        report.transitiveNativePlugins.map((plugin) => plugin.name),
        <String>['flutter_plugin_android_lifecycle'],
      );
      expect(report.assessments.map((a) => a.package), <String>['camera']);
    });

    test('still checks known requirements before pub get has run', () async {
      final info = await project(
        dependencies: <String>['camera', 'provider'],
        platformDirs: <String>['ios'],
      );

      final report = const PluginAnalyzer().analyze(info);

      expect(report.resolved, isFalse);
      expect(report.dartOnlyDependencies, isNull);
      expect(report.assessments, hasLength(1));
      final camera = report.assessments.single;
      expect(camera.kind, PluginKind.unknown);
      expect(
        camera.requirements.every((r) => r.state == RequirementState.missing),
        isTrue,
      );
    });

    test('manual requirements are reminders, not problems', () async {
      final info = await project(
        dependencies: <String>['permission_handler'],
        platformDirs: <String>['android', 'ios'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[
            _plugin('permission_handler_android'),
          ],
          'ios': <Map<String, Object?>>[_plugin('permission_handler_apple')],
        },
      );

      final report = const PluginAnalyzer().analyze(info);

      final requirements = report.assessments.single.requirements;
      expect(
        requirements.map((r) => r.state),
        everyElement(RequirementState.unverified),
      );
      expect(report.hasProblems, isFalse);
    });

    test('skips requirements for platforms the project does not target',
        () async {
      final info = await project(
        dependencies: <String>['camera'],
        platformDirs: <String>['android'],
        plugins: <String, List<Map<String, Object?>>>{
          'android': <Map<String, Object?>>[_plugin('camera_android')],
        },
      );

      final camera = const PluginAnalyzer().analyze(info).assessments.single;

      expect(camera.requirements, isEmpty);
      expect(camera.status, PluginStatus.ready);
    });

    test('counts Dart-only dependencies', () async {
      final info = await project(
        dependencies: <String>['provider', 'http'],
        platformDirs: <String>['android'],
        plugins: <String, List<Map<String, Object?>>>{},
      );

      final report = const PluginAnalyzer().analyze(info);

      expect(report.assessments, isEmpty);
      expect(report.dartOnlyDependencies, 2);
    });

    test('the report serialises to JSON', () async {
      final info = await project(
        dependencies: <String>['camera'],
        platformDirs: <String>['ios'],
        plugins: <String, List<Map<String, Object?>>>{
          'ios': <Map<String, Object?>>[_plugin('camera_avfoundation')],
        },
      );

      final json = const PluginAnalyzer().analyze(info).toJson();

      expect(json, containsPair('resolved', true));
      expect(json, containsPair('hasProblems', true));
      expect(() => jsonEncode(json), returnsNormally);
    });
  });
}
