import 'package:glide_build_manager/glide_build_manager.dart';
import 'package:glide_build_manager/testing.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:test/test.dart';

class _RecordingPublisher implements EventPublisher {
  final List<GlideMessage> messages = <GlideMessage>[];

  @override
  void publish(GlideMessage message) => messages.add(message);

  Iterable<GlideMessage> of(String type) =>
      messages.where((message) => message.type == type);

  bool saw(String type) => of(type).isNotEmpty;

  GlideMessage last(String type) => of(type).last;
}

CompanionCommand _command(
  CompanionCommandType type, [
  Map<String, Object?> payload = const <String, Object?>{},
]) =>
    CompanionCommand(type: type, payload: payload);

void main() {
  late SessionStateMachine machine;
  late _RecordingPublisher publisher;
  late List<FakeAppSession> sessions;
  late List<String> launchedDevices;
  late SessionController controller;
  Object? launchError;
  String? autoDevice;

  Future<void> settle() => pumpEventQueue();

  Future<FakeAppSession> runApp() async {
    await controller.handle(
      _command(CompanionCommandType.appRun, <String, Object?>{
        'deviceId': 'pixel-1',
      }),
    );
    final session = sessions.last..markStarted();
    await settle();
    return session;
  }

  setUp(() {
    machine = SessionStateMachine(initial: SessionState.connected);
    publisher = _RecordingPublisher();
    sessions = <FakeAppSession>[];
    launchedDevices = <String>[];
    launchError = null;
    autoDevice = null;
    controller = SessionController(
      machine: machine,
      publisher: publisher,
      launchApp: ({required String deviceId}) async {
        final error = launchError;
        if (error != null) throw error;
        launchedDevices.add(deviceId);
        final session = FakeAppSession();
        sessions.add(session);
        return session;
      },
      defaultDevice: () async => autoDevice,
    );
  });

  tearDown(() async {
    await controller.dispose();
    await machine.dispose();
  });

  group('app.run', () {
    test('launches on the requested device and reaches running', () async {
      final session = await runApp();

      expect(launchedDevices, <String>['pixel-1']);
      expect(controller.state, SessionState.running);
      expect(publisher.saw(MessageTypes.buildStarted), isTrue);
      expect(publisher.saw(MessageTypes.appStarting), isTrue);
      expect(publisher.saw(MessageTypes.buildCompleted), isTrue);
      final started = publisher.last(MessageTypes.appStarted).payload;
      expect(started['appId'], 'app-1');
      expect(started['deviceId'], 'pixel-1');
      expect(started.containsKey('vmServiceUri'), isFalse);
      expect(session.stopped, isFalse);
    });

    test('publishes a session.status message for every transition', () async {
      await runApp();

      final states = publisher
          .of(MessageTypes.sessionStatus)
          .map((message) => message.payload['state'])
          .toList();
      expect(states, containsAllInOrder(<String>['preparing', 'building']));
      expect(states.last, 'running');
    });

    test('falls back to the default device when none is given', () async {
      autoDevice = 'emulator-5554';

      await controller.handle(_command(CompanionCommandType.appRun));

      expect(launchedDevices, <String>['emulator-5554']);
    });

    test('is rejected when no device can be chosen', () async {
      await controller.handle(_command(CompanionCommandType.appRun));

      expect(launchedDevices, isEmpty);
      expect(
        publisher.last(MessageTypes.commandRejected).payload['reason'],
        contains('No device'),
      );
      expect(controller.state, SessionState.connected);
    });

    test('is rejected while an app is already running', () async {
      await runApp();

      await controller.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );

      expect(launchedDevices, hasLength(1));
      expect(
        publisher.last(MessageTypes.commandRejected).payload['reason'],
        contains('already'),
      );
    });

    test('a launcher failure becomes build.failed and the failed state',
        () async {
      launchError = ToolNotFoundException('flutter');

      await controller.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );

      expect(controller.state, SessionState.failed);
      expect(
        publisher.last(MessageTypes.buildFailed).payload['message'],
        contains('flutter'),
      );
    });

    test('the tool exiting before the app starts fails the build', () async {
      await controller.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );
      sessions.single.crash(1);
      await settle();

      expect(controller.state, SessionState.failed);
      final failed = publisher.last(MessageTypes.buildFailed).payload;
      expect(failed['exitCode'], 1);
    });

    test('can run again after a failed build', () async {
      launchError = ToolNotFoundException('flutter');
      await controller.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );
      launchError = null;

      await runApp();

      expect(controller.state, SessionState.running);
    });

    test('progress messages are published while building', () async {
      await controller.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );
      sessions.single.emit(
        const AppProgress(
          appId: 'app-1',
          message: 'Running Gradle task assembleDebug...',
          finished: false,
        ),
      );
      await settle();

      expect(
        publisher.last(MessageTypes.buildProgress).payload['message'],
        contains('Gradle'),
      );
    });
  });

  group('hot reload', () {
    test('reloads a running app and reports the duration', () async {
      final session = await runApp();

      await controller.handle(_command(CompanionCommandType.appReload));

      expect(session.reloadCalls, 1);
      expect(publisher.saw(MessageTypes.reloadStarted), isTrue);
      expect(
        publisher.last(MessageTypes.reloadCompleted).payload['durationMs'],
        42,
      );
      expect(controller.state, SessionState.running);
    });

    test('a failed reload is reported and the app stays running', () async {
      final session = await runApp();
      session.reloadOutcome = const ReloadOutcome(
        success: false,
        message: 'Compilation error',
        duration: Duration(milliseconds: 9),
      );

      await controller.handle(_command(CompanionCommandType.appReload));

      expect(
        publisher.last(MessageTypes.reloadFailed).payload['message'],
        'Compilation error',
      );
      expect(controller.state, SessionState.running);
    });

    test('a request error is reported and the app stays running', () async {
      final session = await runApp();
      session.requestError = ToolRequestTimeout(
        'app.restart',
        const Duration(seconds: 60),
      );

      await controller.handle(_command(CompanionCommandType.appReload));

      expect(publisher.saw(MessageTypes.reloadFailed), isTrue);
      expect(controller.state, SessionState.running);
    });

    test('is rejected when nothing is running', () async {
      await controller.handle(_command(CompanionCommandType.appReload));

      expect(
        publisher.last(MessageTypes.commandRejected).payload['command'],
        'app.reload',
      );
      expect(controller.state, SessionState.connected);
    });
  });

  group('restart', () {
    test('hot restart calls the tool and reports the mode', () async {
      final session = await runApp();

      await controller.handle(_command(CompanionCommandType.appRestart));

      expect(session.restartCalls, 1);
      final done = publisher.last(MessageTypes.restartCompleted).payload;
      expect(done['mode'], 'hot');
      expect(done['durationMs'], 120);
      expect(controller.state, SessionState.running);
    });

    test('full restart stops the app and launches it again', () async {
      final first = await runApp();

      await controller.handle(
        _command(CompanionCommandType.appRestart, <String, Object?>{
          'mode': 'full',
        }),
      );
      sessions.last.markStarted(appId: 'app-2');
      await settle();

      expect(first.stopped, isTrue);
      expect(sessions, hasLength(2));
      expect(launchedDevices, <String>['pixel-1', 'pixel-1']);
      expect(controller.state, SessionState.running);
      expect(
        publisher.last(MessageTypes.restartCompleted).payload['mode'],
        'full',
      );
    });

    test('a full restart that fails to relaunch reports restart.failed',
        () async {
      await runApp();

      await controller.handle(
        _command(CompanionCommandType.appRestart, <String, Object?>{
          'mode': 'full',
        }),
      );
      sessions.last.crash(2);
      await settle();

      expect(controller.state, SessionState.failed);
      expect(publisher.saw(MessageTypes.restartFailed), isTrue);
      expect(publisher.saw(MessageTypes.restartCompleted), isFalse);
    });

    test('is rejected when nothing is running', () async {
      await controller.handle(_command(CompanionCommandType.appRestart));

      expect(publisher.saw(MessageTypes.commandRejected), isTrue);
    });
  });

  group('stop', () {
    test('stops the app and returns to connected', () async {
      final session = await runApp();

      await controller.handle(_command(CompanionCommandType.appStop));

      expect(session.stopped, isTrue);
      expect(controller.state, SessionState.connected);
      expect(publisher.saw(MessageTypes.appStopped), isTrue);
    });

    test('can interrupt a build that has not finished', () async {
      await controller.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );

      await controller.handle(_command(CompanionCommandType.appStop));

      expect(sessions.single.stopped, isTrue);
      expect(controller.state, SessionState.connected);
    });

    test('is rejected when nothing is running', () async {
      await controller.handle(_command(CompanionCommandType.appStop));

      expect(publisher.saw(MessageTypes.commandRejected), isTrue);
    });

    test('the app exiting on its own returns to connected', () async {
      final session = await runApp();

      session.crash(0);
      await settle();

      expect(controller.state, SessionState.connected);
      expect(
        publisher.last(MessageTypes.appStopped).payload['exitCode'],
        0,
      );
    });

    test('session.disconnect stops a running app', () async {
      final session = await runApp();

      await controller.handle(_command(CompanionCommandType.sessionDisconnect));

      expect(session.stopped, isTrue);
      expect(controller.state, SessionState.connected);
    });
  });

  group('logs and diagnostics', () {
    test('app output becomes log.entry messages and is buffered', () async {
      final session = await runApp();
      session.emit(
        const AppLog(appId: 'app-1', message: 'hello', isError: false),
      );
      session.emit(
        const AppLog(appId: 'app-1', message: 'boom', isError: true),
      );
      await settle();

      final entries = publisher.of(MessageTypes.logEntry).toList();
      expect(
        entries.map((m) => m.payload['message']),
        <String>['hello', 'boom'],
      );
      expect(entries.last.payload['level'], 'error');
      expect(controller.recentLogs, hasLength(2));
    });

    test('logs.clear empties the buffer', () async {
      final session = await runApp();
      session.emit(
        const AppLog(appId: 'app-1', message: 'hello', isError: false),
      );
      await settle();

      await controller.handle(_command(CompanionCommandType.logsClear));

      expect(controller.recentLogs, isEmpty);
      expect(publisher.saw(MessageTypes.logsCleared), isTrue);
    });

    test('the log buffer is capped', () async {
      final small = SessionController(
        machine: SessionStateMachine(initial: SessionState.connected),
        publisher: publisher,
        launchApp: ({required String deviceId}) async {
          final session = FakeAppSession();
          sessions.add(session);
          return session;
        },
        maxBufferedLogs: 3,
      );
      addTearDown(small.dispose);
      await small.handle(
        _command(CompanionCommandType.appRun, <String, Object?>{
          'deviceId': 'pixel-1',
        }),
      );
      for (var i = 0; i < 10; i++) {
        sessions.last.emit(
          AppLog(appId: 'a', message: 'line $i', isError: false),
        );
      }
      await settle();

      expect(
        small.recentLogs.map((entry) => entry.message),
        <String>['line 7', 'line 8', 'line 9'],
      );
    });

    test('diagnostics.request publishes a snapshot with recent logs', () async {
      final session = await runApp();
      session.emit(
        const AppLog(appId: 'app-1', message: 'hello', isError: false),
      );
      await settle();

      await controller
          .handle(_command(CompanionCommandType.diagnosticsRequest));

      final snapshot = publisher.last(MessageTypes.sessionSnapshot).payload;
      expect(snapshot['state'], 'running');
      expect(snapshot['deviceId'], 'pixel-1');
      expect(snapshot['recentLogs'], hasLength(1));
    });
  });

  test('a compiler error in the output is also reported as error.reported',
      () async {
    await controller.handle(
      _command(CompanionCommandType.appRun, <String, Object?>{
        'deviceId': 'pixel-1',
      }),
    );
    sessions.single.emit(
      const ToolLog(
        "lib/main.dart:82:5: Error: Undefined name 'userss'.",
        isError: true,
      ),
    );
    await settle();

    final report = publisher.last(MessageTypes.errorReported).payload;
    expect(report['file'], 'lib/main.dart');
    expect(report['line'], 82);
    expect(report['category'], 'dart');
    expect(publisher.saw(MessageTypes.logEntry), isTrue);
  });

  test('commands are processed in the order they arrive', () async {
    final session = await runApp();

    final first = controller.handle(_command(CompanionCommandType.appReload));
    final second = controller.handle(_command(CompanionCommandType.appReload));
    await Future.wait<void>(<Future<void>>[first, second]);

    expect(session.reloadCalls, 2);
    expect(publisher.of(MessageTypes.reloadCompleted), hasLength(2));
  });
}
