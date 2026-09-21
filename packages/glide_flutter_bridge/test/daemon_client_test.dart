import 'dart:convert';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:test/test.dart';

import 'fake_process.dart';

int _idOfLastWrite(FakeProcessHandle handle) {
  final frame = jsonDecode(handle.written.last) as List;
  return (frame.single as Map<String, Object?>)['id'] as int;
}

void _respondOk(FakeProcessHandle handle, {Object? result}) {
  final id = _idOfLastWrite(handle);
  handle.emitFrame(
    jsonEncode([
      {'id': id, 'result': result},
    ]),
  );
}

void main() {
  group('FlutterDaemonClient', () {
    late FakeProcessLauncher launcher;
    late FlutterDaemonClient client;

    setUp(() {
      launcher = FakeProcessLauncher();
      client = FlutterDaemonClient(
        launcher: launcher,
        flutterExecutable: 'flutter',
        restartBackoff: const Duration(milliseconds: 1),
      );
    });

    /// Starts the daemon and answers its `device.enable` handshake.
    Future<FakeProcessHandle> start() async {
      final started = client.start();
      await Future<void>.delayed(Duration.zero);
      final handle = launcher.handles.single;
      _respondOk(handle);
      await started;
      return handle;
    }

    test('launches `flutter daemon` and enables device polling', () async {
      final handle = await start();

      expect(launcher.calls.single.executable, 'flutter');
      expect(launcher.calls.single.arguments, <String>['daemon']);
      final frame = jsonDecode(handle.written.single) as List;
      expect(
        (frame.single as Map<String, Object?>)['method'],
        'device.enable',
      );
      expect(client.isRunning, isTrue);
    });

    test('getDevices decodes the device list', () async {
      final handle = await start();

      final future = client.getDevices();
      await Future<void>.delayed(Duration.zero);
      final id = _idOfLastWrite(handle);
      handle.emitFrame(
        jsonEncode([
          {
            'id': id,
            'result': [
              {
                'id': 'emulator-5554',
                'name': 'Pixel',
                'platform': 'android-arm64',
              },
            ],
          },
        ]),
      );

      final devices = await future;
      expect(devices.single.id, 'emulator-5554');
      expect(devices.single.isAndroid, isTrue);
    });

    test('getDevices throws once the daemon is no longer running', () async {
      final handle = await start();
      handle.exit(0);
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(client.getDevices(), throwsA(isA<ToolProcessExited>()));
    });

    test('forwards daemon events to listeners', () async {
      final handle = await start();
      final events = client.events.toList();

      handle.emitFrame(
        '[{"event":"device.added","params":{"id":"emulator-5554",'
        '"name":"Pixel","platform":"android-arm64"}}]',
      );

      final shutdownFuture = client.shutdown();
      await Future<void>.delayed(Duration.zero);
      _respondOk(handle);
      await shutdownFuture;

      final received = await events;
      expect(received.whereType<DeviceAdded>(), hasLength(1));
    });

    test('restarts the daemon after it crashes', () async {
      final handle = await start();
      final logs = <ToolLog>[];
      final sub = client.events.listen((event) {
        if (event is ToolLog) logs.add(event);
      });

      handle.exit(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(launcher.handles, hasLength(2), reason: 'daemon was relaunched');
      expect(logs.any((log) => log.message.contains('restarting')), isTrue);

      // Let the relaunch's handshake complete, then shut down cleanly so no
      // timers are left pending after the test ends.
      _respondOk(launcher.handles.last);
      await Future<void>.delayed(Duration.zero);
      final shutdownFuture = client.shutdown();
      await Future<void>.delayed(Duration.zero);
      _respondOk(launcher.handles.last);
      await shutdownFuture;
      await sub.cancel();
    });

    test('gives up after maxRestarts consecutive crashes', () async {
      client = FlutterDaemonClient(
        launcher: launcher,
        flutterExecutable: 'flutter',
        maxRestarts: 1,
        restartBackoff: const Duration(milliseconds: 1),
      );
      await start();
      final logs = <ToolLog>[];
      client.events.listen((event) {
        if (event is ToolLog) logs.add(event);
      });

      launcher.handles.single.exit(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(launcher.handles, hasLength(2));
      _respondOk(launcher.handles.last);
      await Future<void>.delayed(Duration.zero);

      launcher.handles.last.exit(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        launcher.handles,
        hasLength(2),
        reason: 'no further relaunch once maxRestarts is reached',
      );
      expect(logs.any((log) => log.message.contains('giving up')), isTrue);
    });

    test('shutdown asks the daemon to exit gracefully', () async {
      final handle = await start();
      final shutdownFuture = client.shutdown();
      await Future<void>.delayed(Duration.zero);
      final method = (jsonDecode(handle.written.last) as List).single
          as Map<String, Object?>;
      expect(method['method'], 'daemon.shutdown');

      _respondOk(handle);
      await shutdownFuture;
    });

    test(
      'shutdown kills the process if it does not respond',
      () async {
        final handle = await start();
        await client.shutdown();
        expect(handle.killed, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });
}
