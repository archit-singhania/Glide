import 'dart:convert';
import 'dart:io';

import 'package:glide_cli/glide_cli.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _minimalPubspec = '''
name: shop_app
description: A shop app.
environment:
  sdk: ^3.6.0
  flutter: ">=3.27.0"
dependencies:
  flutter:
    sdk: flutter
''';

void main() {
  group('glide inspect', () {
    late Directory projectDir;

    setUp(() {
      projectDir = Directory.systemTemp.createTempSync('glide_inspect_');
      File(
        p.join(projectDir.path, 'pubspec.yaml'),
      ).writeAsStringSync(_minimalPubspec);
    });

    tearDown(() => projectDir.deleteSync(recursive: true));

    test('is registered on the top-level runner', () async {
      final out = StringBuffer();
      final code = await runGlide(
        <String>['inspect'],
        out: out,
        err: StringBuffer(),
        workingDirectory: projectDir.path,
      );

      expect(code, 0);
      expect(out.toString(), contains('Project: shop_app'));
      expect(
        out.toString(),
        contains('Platforms'),
        reason: 'renders cleanly for a project with no platform folders yet',
      );
    });

    test('--json prints machine-readable output', () async {
      final out = StringBuffer();
      final code = await runGlide(
        <String>['inspect', '--json'],
        out: out,
        err: StringBuffer(),
        workingDirectory: projectDir.path,
      );

      expect(code, 0);
      final json = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(json['name'], 'shop_app');
    });

    test('searches upward from a subdirectory for pubspec.yaml', () async {
      final subDir = Directory(p.join(projectDir.path, 'lib', 'src'))
        ..createSync(recursive: true);
      final out = StringBuffer();

      final code = await runGlide(
        <String>['inspect'],
        out: out,
        err: StringBuffer(),
        workingDirectory: subDir.path,
      );

      expect(code, 0);
      expect(out.toString(), contains('shop_app'));
    });

    test('a directory with no pubspec.yaml is a Glide error, not a crash',
        () async {
      final empty = Directory.systemTemp.createTempSync('glide_no_project_');
      addTearDown(() => empty.deleteSync(recursive: true));
      final err = StringBuffer();

      final code = await runGlide(
        <String>['inspect'],
        out: StringBuffer(),
        err: err,
        workingDirectory: empty.path,
      );

      expect(code, 1);
      expect(err.toString(), contains('No pubspec.yaml'));
    });

    test('a custom analyzer can be injected', () async {
      final out = StringBuffer();
      final code = await runGlide(
        <String>['inspect', 'ignored-path'],
        out: out,
        err: StringBuffer(),
        workingDirectory: projectDir.path,
        analyzer: _FixedAnalyzer(
          const ProjectInfo(
            name: 'from_fake_analyzer',
            rootPath: '/fake',
            platforms: <ProjectPlatform>{},
          ),
        ),
      );

      expect(code, 0);
      expect(out.toString(), contains('from_fake_analyzer'));
    });
  });
}

class _FixedAnalyzer implements ProjectAnalyzer {
  const _FixedAnalyzer(this.info);
  final ProjectInfo info;

  @override
  Future<ProjectInfo> analyze(String directory) async => info;
}
