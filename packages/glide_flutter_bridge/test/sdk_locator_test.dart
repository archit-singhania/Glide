import 'dart:io';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('FlutterSdkLocator', () {
    late Directory sdkRoot;

    setUp(() {
      sdkRoot = Directory.systemTemp.createTempSync('glide_sdk_');
      File(
        p.join(sdkRoot.path, 'bin', 'flutter'),
      ).createSync(recursive: true);
    });

    tearDown(() => sdkRoot.deleteSync(recursive: true));

    test('finds the SDK from an explicit root directory', () {
      final locator = FlutterSdkLocator(
        environment: const <String, String>{},
        isWindows: false,
      );
      final found = locator.locate(explicitPath: sdkRoot.path);
      final expectedExecutable = File(
        p.join(sdkRoot.path, 'bin', 'flutter'),
      ).resolveSymbolicLinksSync();

      expect(found, isNotNull);
      expect(found!.executable, expectedExecutable);
      expect(found.root, p.dirname(p.dirname(expectedExecutable)));
    });

    test('finds the SDK from an explicit executable path', () {
      final locator = FlutterSdkLocator(
        environment: const <String, String>{},
        isWindows: false,
      );
      final executablePath = p.join(sdkRoot.path, 'bin', 'flutter');
      final found = locator.locate(explicitPath: executablePath);
      final expectedRoot = p.dirname(
        p.dirname(File(executablePath).resolveSymbolicLinksSync()),
      );

      expect(found, isNotNull);
      expect(found!.root, expectedRoot);
    });

    test('an explicit path that does not exist finds nothing', () {
      final locator = FlutterSdkLocator(
        environment: const <String, String>{},
        isWindows: false,
      );
      expect(locator.locate(explicitPath: '/nowhere/at/all'), isNull);
    });

    test('falls back to GLIDE_FLUTTER_SDK, then FLUTTER_ROOT', () {
      final byGlideVar = FlutterSdkLocator(
        environment: <String, String>{'GLIDE_FLUTTER_SDK': sdkRoot.path},
        isWindows: false,
      ).locate();
      expect(byGlideVar, isNotNull);

      final byFlutterRoot = FlutterSdkLocator(
        environment: <String, String>{
          'GLIDE_FLUTTER_SDK': '',
          'FLUTTER_ROOT': sdkRoot.path,
        },
        isWindows: false,
      ).locate();
      expect(byFlutterRoot, isNotNull);
    });

    test('falls back to PATH when no environment variable resolves', () {
      final binary = Platform.isWindows ? 'flutter.bat' : 'flutter';
      File(p.join(sdkRoot.path, 'bin', binary)).createSync(recursive: true);
      final locator = FlutterSdkLocator(
        environment: <String, String>{
          'PATH': [Directory.systemTemp.path, p.join(sdkRoot.path, 'bin')]
              .join(Platform.isWindows ? ';' : ':'),
        },
        isWindows: Platform.isWindows,
      );
      final found = locator.locate();
      expect(found, isNotNull);
    });

    test('returns null when nothing on PATH has the binary', () {
      final locator = FlutterSdkLocator(
        environment: <String, String>{'PATH': Directory.systemTemp.path},
        isWindows: false,
      );
      expect(locator.locate(), isNull);
    });

    test('uses flutter.bat and dart.bat on Windows', () {
      File(
        p.join(sdkRoot.path, 'bin', 'flutter.bat'),
      ).createSync(recursive: true);
      final locator = FlutterSdkLocator(
        environment: const <String, String>{},
        isWindows: true,
      );
      final found = locator.locate(explicitPath: sdkRoot.path);

      expect(found, isNotNull);
      expect(found!.executable, endsWith('flutter.bat'));
      expect(found.dartExecutable, endsWith('dart.bat'));
    });

    test('dartExecutable is null when the root could not be derived', () {
      final looseDir = Directory.systemTemp.createTempSync('glide_loose_');
      addTearDown(() => looseDir.deleteSync(recursive: true));
      final looseFile = File(p.join(looseDir.path, 'flutter'))..createSync();
      final locator = FlutterSdkLocator(
        environment: const <String, String>{},
        isWindows: false,
      );

      final found = locator.locate(explicitPath: looseFile.path);
      expect(found, isNotNull);
      expect(found!.root, isNull);
      expect(found.dartExecutable, isNull);
    });
  });
}
