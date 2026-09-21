import 'dart:convert';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:test/test.dart';

import 'fake_process.dart';

int _idOfLastWrite(FakeProcessHandle handle) {
  final frame = jsonDecode(handle.written.last) as List;
  return (frame.single as Map<String, Object?>)['id'] as int;
}

void _respond(
  FakeProcessHandle handle, {
  Object? result,
  Object? error,
}) {
  final id = _idOfLastWrite(handle);
  handle.emitFrame(
    jsonEncode([
      {'id': id, if (error != null) 'error': error else 'result': result},
    ]),
  );
}

/// Events travel through several asynchronous stream hops before the session
/// sees them, so tests must let them settle before reading session state.
Future<void> _emitAndSettle(FakeProcessHandle handle, String frame) async {
  handle.emitFrame(frame);
  await pumpEventQueue();
}

Future<void> _startApp(FakeProcessHandle handle) => _emitAndSettle(
      handle,
      '[{"event":"app.start","params":{"appId":"app-1"}}]',
    );

void main() {
  group('FlutterAppSession.launch', () {
    late FakeProcessLauncher launcher;

    setUp(() => launcher = FakeProcessLauncher());

    test('refuses an unsafe device id without starting a process', () async {
      expect(
        () => FlutterAppSession.launch(
          launcher: launcher,
          flutterExecutable: 'flutter',
          projectPath: '/project',
          deviceId: 'a; rm -rf /',
        ),
        throwsA(isA<ToolException>()),
      );
      expect(launcher.calls, isEmpty);
    });

    test('builds the correct `flutter run --machine` invocation', () async {
      await FlutterAppSession.launch(
        launcher: launcher,
        flutterExecutable: 'flutter',
        projectPath: '/project',
        deviceId: 'emulator-5554',
        target: 'lib/main_dev.dart',
        mode: AppMode.profile,
      );

      final call = launcher.calls.single;
      expect(call.executable, 'flutter');
      expect(call.workingDirectory, '/project');
      expect(call.arguments, <String>[
        'run',
        '--machine',
        '-d',
        'emulator-5554',
        '--profile',
        '-t',
        'lib/main_dev.dart',
      ]);
    });
  });

  group('FlutterAppSession', () {
    late FakeProcessLauncher launcher;
    late FakeProcessHandle handle;
    late FlutterAppSession session;

    setUp(() async {
      launcher = FakeProcessLauncher();
      session = await FlutterAppSession.launch(
        launcher: launcher,
        flutterExecutable: 'flutter',
        projectPath: '/project',
        deviceId: 'emulator-5554',
      );
      handle = launcher.handles.single;
    });

    test('tracks appId and vmServiceUri as the tool reports them', () async {
      final eventsDone = session.events.toList();

      await _emitAndSettle(
        handle,
        '[{"event":"app.start","params":{"appId":"app-1",'
        '"deviceId":"emulator-5554","mode":"debug"}}]',
      );
      expect(session.appId, 'app-1');

      await _emitAndSettle(
        handle,
        '[{"event":"app.debugPort","params":{"appId":"app-1",'
        '"wsUri":"ws://127.0.0.1:1234/ws"}}]',
      );
      expect(session.vmServiceUri, 'ws://127.0.0.1:1234/ws');

      handle.emitFrame('[{"event":"app.started","params":{"appId":"app-1"}}]');
      await session.started;

      handle.exit(0);
      await eventsDone;
    });

    test('started fails if the tool exits before the app starts', () async {
      handle.exit(1);
      await expectLater(session.started, throwsA(isA<ToolProcessExited>()));
    });

    test('hotReload sends a non-full app.restart and reports timing', () async {
      await _startApp(handle);

      final future = session.hotReload();
      await Future<void>.delayed(Duration.zero);
      final frame = jsonDecode(handle.written.last) as List;
      final request = frame.single as Map<String, Object?>;
      expect(request['method'], 'app.restart');
      final params = request['params'] as Map<String, Object?>;
      expect(params['appId'], 'app-1');
      expect(params['fullRestart'], isFalse);

      _respond(handle, result: {'code': 0, 'message': 'reloaded'});

      final outcome = await future;
      expect(outcome.success, isTrue);
      expect(outcome.message, 'reloaded');
    });

    test('hotRestart sends a full app.restart', () async {
      await _startApp(handle);

      final future = session.hotRestart();
      await Future<void>.delayed(Duration.zero);
      final frame = jsonDecode(handle.written.last) as List;
      final params = (frame.single as Map<String, Object?>)['params']
          as Map<String, Object?>;
      expect(params['fullRestart'], isTrue);

      _respond(handle, result: {'code': 0, 'message': 'ok'});
      expect((await future).success, isTrue);
    });

    test('a non-zero restart code is reported as a failure', () async {
      await _startApp(handle);
      final future = session.hotReload();
      await Future<void>.delayed(Duration.zero);

      _respond(handle, result: {'code': 1, 'message': 'compile error'});

      final outcome = await future;
      expect(outcome.success, isFalse);
      expect(outcome.message, 'compile error');
    });

    test('reload before the app has started throws', () async {
      expect(() => session.hotReload(), throwsA(isA<ToolException>()));
    });

    test('stop sends app.stop and waits for the process to exit', () async {
      await _startApp(handle);

      final future = session.stop();
      await Future<void>.delayed(Duration.zero);
      final frame = jsonDecode(handle.written.last) as List;
      expect((frame.single as Map<String, Object?>)['method'], 'app.stop');

      _respond(handle, result: null);
      handle.exit(0);
      await future;
    });

    test(
      'stop tolerates a process that never acknowledges app.stop',
      () async {
        await _startApp(handle);

        final future = session.stop();
        await Future<void>.delayed(Duration.zero);
        // Never respond to app.stop; the tool simply exits on its own.
        handle.exit(0);

        await future;
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test('stop with no appId just waits for exit', () async {
      final future = session.stop();
      handle.exit(0);
      await future;
    });
  });
}
