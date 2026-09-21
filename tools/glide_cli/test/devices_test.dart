import 'dart:async';
import 'dart:convert';

import 'package:glide_cli/glide_cli.dart';
import 'package:glide_device_manager/glide_device_manager.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:test/test.dart';

const FlutterDevice _pixel = FlutterDevice(
  id: 'emulator-5554',
  name: 'Pixel 10',
  platform: 'android-arm64',
);

/// A [DeviceSessionOpener] backed by an in-memory event stream instead of a
/// real Flutter daemon.
class _FakeSession {
  _FakeSession() : events = StreamController<FlutterToolEvent>.broadcast() {
    manager = DeviceManager(events: events.stream);
  }

  final StreamController<FlutterToolEvent> events;
  late final DeviceManager manager;
  int closeCalls = 0;

  DeviceSessionOpener get opener =>
      ({String? flutterSdkPath}) async => DeviceSession(
            manager: manager,
            onClose: () async {
              closeCalls++;
              await events.close();
            },
          );
}

void main() {
  group('glide devices', () {
    test('prints "no devices" text when nothing is connected', () async {
      final session = _FakeSession();
      final out = StringBuffer();

      final code = await runGlide(
        <String>['devices'],
        out: out,
        err: StringBuffer(),
        deviceSessionOpener: session.opener,
      );

      expect(code, 0);
      expect(out.toString(), contains('No devices found.'));
      expect(session.closeCalls, 1);
    });

    test('prints connected devices as text', () async {
      final session = _FakeSession();
      session.events.add(const DeviceAdded(_pixel));
      await Future<void>.delayed(Duration.zero);
      final out = StringBuffer();

      final code = await runGlide(
        <String>['devices'],
        out: out,
        err: StringBuffer(),
        deviceSessionOpener: session.opener,
      );

      expect(code, 0);
      expect(out.toString(), contains('Pixel 10'));
      expect(out.toString(), contains('emulator-5554'));
    });

    test('--json prints machine-readable output', () async {
      final session = _FakeSession();
      session.events.add(const DeviceAdded(_pixel));
      await Future<void>.delayed(Duration.zero);
      final out = StringBuffer();

      final code = await runGlide(
        <String>['devices', '--json'],
        out: out,
        err: StringBuffer(),
        deviceSessionOpener: session.opener,
      );

      expect(code, 0);
      final json = jsonDecode(out.toString()) as List<dynamic>;
      expect((json.single as Map<String, dynamic>)['id'], 'emulator-5554');
    });

    test('--watch streams snapshots until the session ends', () async {
      final session = _FakeSession();
      final out = StringBuffer();

      final done = runGlide(
        <String>['devices', '--watch'],
        out: out,
        err: StringBuffer(),
        deviceSessionOpener: session.opener,
      );

      await Future<void>.delayed(Duration.zero);
      session.events.add(const DeviceAdded(_pixel));
      await Future<void>.delayed(Duration.zero);
      // Ending the manager is what allows watchDevices() to complete; in
      // production this happens when the daemon's events stream ends.
      await session.manager.dispose();

      expect(await done, 0);
      expect(out.toString(), contains('No devices found.'));
      expect(out.toString(), contains('Pixel 10'));
    });

    test('a missing Flutter SDK is a Glide error, not a crash', () async {
      final err = StringBuffer();

      final code = await runGlide(
        <String>['devices'],
        out: StringBuffer(),
        err: err,
        deviceSessionOpener: ({String? flutterSdkPath}) async {
          throw const ToolException('Flutter SDK not found.');
        },
      );

      expect(code, 1);
      expect(err.toString(), contains('Flutter SDK not found.'));
    });
  });
}
