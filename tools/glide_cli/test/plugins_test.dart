import 'dart:convert';
import 'dart:io';

import 'package:glide_cli/glide_cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _pubspec = '''
name: shop_app
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.0
  provider: ^6.0.0
''';

const String _plugins = '''
{"plugins": {"ios": [{"name": "camera_avfoundation", "native_build": true}]}}
''';

void _write(Directory root, String relative, String contents) {
  File(p.join(root.path, relative))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

void main() {
  late Directory project;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    project = Directory.systemTemp.createTempSync('glide_plugins_cli_');
    out = StringBuffer();
    err = StringBuffer();
    _write(project, 'pubspec.yaml', _pubspec);
    Directory(p.join(project.path, 'ios')).createSync();
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<int> plugins(List<String> args) => runGlide(
        <String>['plugins', ...args],
        out: out,
        err: err,
        workingDirectory: project.path,
      );

  group('glide plugins', () {
    test('reports missing configuration and exits 0 by default', () async {
      _write(project, '.flutter-plugins-dependencies', _plugins);
      _write(
        project,
        'ios/Runner/Info.plist',
        '<key>NSCameraUsageDescription</key>',
      );

      final code = await plugins(<String>[]);

      expect(code, 0);
      final text = out.toString();
      expect(text, contains('camera'));
      expect(text, contains('needs configuration'));
      expect(text, contains('[missing] iOS: Microphone usage description'));
      expect(text, contains('[ok]      iOS: Camera usage description'));
      expect(text, contains('camera_avfoundation'));
    });

    test('--strict exits 1 while something is missing', () async {
      _write(project, '.flutter-plugins-dependencies', _plugins);

      expect(await plugins(<String>['--strict']), 1);
    });

    test('--strict exits 0 once the configuration is complete', () async {
      _write(project, '.flutter-plugins-dependencies', _plugins);
      _write(
        project,
        'ios/Runner/Info.plist',
        '<key>NSCameraUsageDescription</key>'
            '<key>NSMicrophoneUsageDescription</key>',
      );

      expect(await plugins(<String>['--strict']), 0);
      expect(out.toString(), isNot(contains('[missing]')));
    });

    test('--json prints the report', () async {
      _write(project, '.flutter-plugins-dependencies', _plugins);

      final code = await plugins(<String>['--json']);

      expect(code, 0);
      final json = jsonDecode(out.toString()) as Map<String, Object?>;
      expect(json['resolved'], isTrue);
      expect(json['hasProblems'], isTrue);
      expect(json['dartOnlyDependencies'], 1);
    });

    test('says so when pub get has not run', () async {
      final code = await plugins(<String>[]);

      expect(code, 0);
      expect(out.toString(), contains('flutter pub get'));
    });

    test('fails clearly outside a project', () async {
      final empty = Directory.systemTemp.createTempSync('glide_plugins_none_');
      addTearDown(() => empty.deleteSync(recursive: true));

      final code = await runGlide(
        <String>['plugins'],
        out: out,
        err: err,
        workingDirectory: empty.path,
      );

      expect(code, 1);
      expect(err.toString(), contains('No pubspec.yaml'));
    });
  });
}
