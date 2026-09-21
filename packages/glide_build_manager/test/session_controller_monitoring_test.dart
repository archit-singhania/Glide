import 'dart:convert';

import 'package:glide_build_manager/glide_build_manager.dart';
import 'package:glide_build_manager/testing.dart';
import 'package:glide_network/glide_network.dart';
import 'package:glide_network/testing.dart';
import 'package:glide_performance/glide_performance.dart';
import 'package:glide_performance/testing.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:test/test.dart';

/// A VM service address shaped like a real one. `SECRETCODE` stands in for
/// the auth code, so tests can prove it never leaves the computer.
const String _vmUri = 'ws://127.0.0.1:5555/SECRETCODE=/ws';

class _Recorder implements EventPublisher {
  final List<GlideMessage> messages = <GlideMessage>[];

  @override
  void publish(GlideMessage message) => messages.add(message);

  Iterable<GlideMessage> ofType(String type) =>
      messages.where((m) => m.type == type);
}

class _FakeDevTools implements DevToolsHandle {
  int closeCalls = 0;

  @override
  Future<void> close() async => closeCalls++;
}

typedef _Rig = ({
  SessionController controller,
  _Recorder recorder,
  FakeAppSession session,
});

_Rig _rig({
  PerformanceSamplerConnector? performance,
  NetworkMonitorConnector? network,
  DevToolsOpener? devTools,
  String? vmServiceUri = _vmUri,
}) {
  final machine = SessionStateMachine();
  final recorder = _Recorder();
  final session = FakeAppSession()..vmServiceUri = vmServiceUri;
  final controller = SessionController(
    machine: machine,
    publisher: recorder,
    launchApp: ({required String deviceId}) async => session,
    connectPerformanceSampler: performance,
    connectNetworkMonitor: network,
    openDevTools: devTools,
  );
  // Registered in this order so the controller is disposed before the
  // machine it drives.
  addTearDown(machine.dispose);
  addTearDown(controller.dispose);
  return (controller: controller, recorder: recorder, session: session);
}

Future<void> _runApp(_Rig rig) async {
  await rig.controller.handle(
    const CompanionCommand(
      type: CompanionCommandType.appRun,
      payload: <String, Object?>{'deviceId': 'pixel-1'},
    ),
  );
  rig.session.markStarted();
  for (var i = 0; i < 100; i++) {
    if (rig.controller.state == SessionState.running) break;
    await pumpEventQueue();
  }
  expect(rig.controller.state, SessionState.running);
  // Let the monitors finish connecting.
  await pumpEventQueue();
}

Future<void> _send(_Rig rig, CompanionCommandType type) =>
    rig.controller.handle(CompanionCommand(type: type));

PerformanceSample _sample() => PerformanceSample.fromWindow(
      frames: const <FrameTiming>[FrameTiming(buildUs: 4000, rasterUs: 4000)],
      window: const Duration(seconds: 1),
      timestamp: DateTime.utc(2026),
    );

void main() {
  group('performance sampling', () {
    test('publishes samples and keeps the latest for snapshots', () async {
      final sampler = FakePerformanceSampler();
      final rig = _rig(performance: (_) async => sampler);
      await _runApp(rig);

      sampler.emit(_sample());
      await pumpEventQueue();

      final published =
          rig.recorder.ofType(MessageTypes.performanceSample).single;
      expect(published.payload['frameCount'], 1);
      expect(published.payload['fps'], 1.0);

      await _send(rig, CompanionCommandType.diagnosticsRequest);
      final snapshot = rig.recorder.ofType(MessageTypes.sessionSnapshot).last;
      final performance = snapshot.payload['performance'] as Map;
      expect(performance['frameCount'], 1);
    });

    test('connects with the VM service address, and only there', () async {
      String? received;
      final rig = _rig(
        performance: (uri) async {
          received = uri;
          return FakePerformanceSampler();
        },
      );
      await _runApp(rig);

      expect(received, _vmUri);
    });

    test('nothing connects when there is no connector', () async {
      final rig = _rig();
      await _runApp(rig);
      await _send(rig, CompanionCommandType.diagnosticsRequest);

      final snapshot = rig.recorder.ofType(MessageTypes.sessionSnapshot).last;
      expect(snapshot.payload.containsKey('performance'), isFalse);
      expect(rig.recorder.ofType(MessageTypes.performanceSample), isEmpty);
    });

    test('nothing connects when the app reports no VM service', () async {
      var connected = false;
      final rig = _rig(
        vmServiceUri: null,
        performance: (_) async {
          connected = true;
          return FakePerformanceSampler();
        },
      );
      await _runApp(rig);

      expect(connected, isFalse);
    });

    test('a connector that throws is logged and the app keeps running',
        () async {
      final rig = _rig(performance: (_) async => throw StateError(_vmUri));
      await _runApp(rig);

      expect(rig.controller.state, SessionState.running);
      final warnings = rig.recorder
          .ofType(MessageTypes.logEntry)
          .map((m) => m.payload['message'] as String)
          .where((m) => m.contains('Performance sampling is unavailable'));
      expect(warnings, hasLength(1));
      // The error text held the address; only the type may be logged.
      expect(
        jsonEncode(rig.recorder.messages.map((m) => m.toJson()).toList()),
        isNot(contains('SECRETCODE')),
      );
    });

    test('stops sampling when the app is stopped', () async {
      final sampler = FakePerformanceSampler();
      final rig = _rig(performance: (_) async => sampler);
      await _runApp(rig);

      await _send(rig, CompanionCommandType.appStop);

      expect(sampler.stopped, isTrue);
      expect(sampler.stopCalls, 1);
    });

    test('stops sampling when the app exits on its own', () async {
      final sampler = FakePerformanceSampler();
      final rig = _rig(performance: (_) async => sampler);
      await _runApp(rig);

      rig.session.crash(0);
      for (var i = 0; i < 50 && !sampler.stopped; i++) {
        await pumpEventQueue();
      }

      expect(sampler.stopped, isTrue);
    });
  });

  group('network monitoring', () {
    test('publishes completed requests as network.response', () async {
      final monitor = FakeNetworkMonitor();
      final rig = _rig(network: (_) async => monitor);
      await _runApp(rig);

      monitor.emit(
        const NetworkEvent(
          id: '1',
          method: 'GET',
          url: 'https://api.example.com/users',
          statusCode: 200,
          durationMs: 342,
          sizeBytes: 18300,
        ),
      );
      await pumpEventQueue();

      final message = rig.recorder.ofType(MessageTypes.networkResponse).single;
      expect(message.payload['method'], 'GET');
      expect(message.payload['url'], 'https://api.example.com/users');
      expect(message.payload['statusCode'], 200);
      expect(message.payload['durationMs'], 342);
      expect(message.payload['sizeBytes'], 18300);
    });

    test('stops watching when the app is stopped', () async {
      final monitor = FakeNetworkMonitor();
      final rig = _rig(network: (_) async => monitor);
      await _runApp(rig);

      await _send(rig, CompanionCommandType.appStop);

      expect(monitor.stopped, isTrue);
    });

    test('a connector that throws is logged and the app keeps running',
        () async {
      final rig = _rig(network: (_) async => throw StateError('refused'));
      await _runApp(rig);

      expect(rig.controller.state, SessionState.running);
      final warnings = rig.recorder
          .ofType(MessageTypes.logEntry)
          .map((m) => m.payload['message'] as String)
          .where((m) => m.contains('Network monitoring is unavailable'));
      expect(warnings, hasLength(1));
    });
  });

  test('the VM service address is never published to the companion', () async {
    final sampler = FakePerformanceSampler();
    final monitor = FakeNetworkMonitor();
    final rig = _rig(
      performance: (_) async => sampler,
      network: (_) async => monitor,
      devTools: (_) async => _FakeDevTools(),
    );
    await _runApp(rig);
    sampler.emit(_sample());
    monitor
        .emit(const NetworkEvent(id: '1', method: 'GET', url: 'https://x.y'));
    await _send(rig, CompanionCommandType.devtoolsOpen);
    await _send(rig, CompanionCommandType.diagnosticsRequest);
    await pumpEventQueue();

    final everything =
        jsonEncode(rig.recorder.messages.map((m) => m.toJson()).toList());
    expect(everything, isNot(contains('SECRETCODE')));
    expect(everything, isNot(contains('127.0.0.1')));
  });

  group('devtools.open', () {
    test('opens DevTools with the VM service address and reports success',
        () async {
      String? received;
      final handle = _FakeDevTools();
      final rig = _rig(
        devTools: (uri) async {
          received = uri;
          return handle;
        },
      );
      await _runApp(rig);

      await _send(rig, CompanionCommandType.devtoolsOpen);

      expect(received, _vmUri);
      expect(rig.recorder.ofType(MessageTypes.devtoolsOpened), hasLength(1));
    });

    test('opening twice reuses the running DevTools', () async {
      var opened = 0;
      final rig = _rig(
        devTools: (_) async {
          opened++;
          return _FakeDevTools();
        },
      );
      await _runApp(rig);

      await _send(rig, CompanionCommandType.devtoolsOpen);
      await _send(rig, CompanionCommandType.devtoolsOpen);

      expect(opened, 1);
      final replies = rig.recorder.ofType(MessageTypes.devtoolsOpened).toList();
      expect(replies, hasLength(2));
      expect(replies.last.payload['alreadyOpen'], isTrue);
    });

    test('closes DevTools when the app is stopped', () async {
      final handle = _FakeDevTools();
      final rig = _rig(devTools: (_) async => handle);
      await _runApp(rig);
      await _send(rig, CompanionCommandType.devtoolsOpen);

      await _send(rig, CompanionCommandType.appStop);

      expect(handle.closeCalls, 1);
    });

    test('is rejected when no app is running', () async {
      final rig = _rig(devTools: (_) async => _FakeDevTools());

      await _send(rig, CompanionCommandType.devtoolsOpen);

      final rejected = rig.recorder.ofType(MessageTypes.commandRejected).single;
      expect(rejected.payload['command'], 'devtools.open');
      expect(rig.recorder.ofType(MessageTypes.devtoolsOpened), isEmpty);
    });

    test('is rejected when the app has no VM service', () async {
      final rig = _rig(
        vmServiceUri: null,
        devTools: (_) async => _FakeDevTools(),
      );
      await _runApp(rig);

      await _send(rig, CompanionCommandType.devtoolsOpen);

      expect(rig.recorder.ofType(MessageTypes.commandRejected), hasLength(1));
    });

    test('is rejected when DevTools is not available in this session',
        () async {
      final rig = _rig();
      await _runApp(rig);

      await _send(rig, CompanionCommandType.devtoolsOpen);

      final rejected = rig.recorder.ofType(MessageTypes.commandRejected).single;
      expect(rejected.payload['reason'], contains('not available'));
    });

    test('a failure to start is reported without leaking the error text',
        () async {
      final rig = _rig(devTools: (_) async => throw StateError(_vmUri));
      await _runApp(rig);

      await _send(rig, CompanionCommandType.devtoolsOpen);

      final failed = rig.recorder.ofType(MessageTypes.devtoolsFailed).single;
      expect(failed.payload['message'], contains('StateError'));
      expect(failed.payload['message'], isNot(contains('SECRETCODE')));
      expect(rig.controller.state, SessionState.running);
    });
  });
}
