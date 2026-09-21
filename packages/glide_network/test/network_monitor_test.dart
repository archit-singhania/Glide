import 'package:glide_network/glide_network.dart';
import 'package:test/test.dart';

/// An [HttpProfileClient] test double. Nothing here touches a VM service.
class _FakeClient implements HttpProfileClient {
  String? isolate = 'isolate-1';
  Object? fetchError;
  Object? enableError;
  List<HttpProfileEntry> entries = <HttpProfileEntry>[];
  int timestamp = 100;

  int isolateCalls = 0;
  int enableCalls = 0;
  int disposeCalls = 0;
  final List<int?> updatedSinceArgs = <int?>[];

  @override
  Future<String?> getMainIsolateId() async {
    isolateCalls++;
    return isolate;
  }

  @override
  Future<void> enableLogging(String isolateId) async {
    enableCalls++;
    final error = enableError;
    if (error != null) throw error;
  }

  @override
  Future<HttpProfileSnapshot> fetch(
    String isolateId, {
    int? updatedSince,
  }) async {
    updatedSinceArgs.add(updatedSince);
    final error = fetchError;
    if (error != null) {
      fetchError = null;
      throw error;
    }
    return HttpProfileSnapshot(timestamp: timestamp, entries: entries);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

HttpProfileEntry _done(String id, {int status = 200}) => HttpProfileEntry(
      id: id,
      method: 'GET',
      uri: 'https://example.com/$id',
      startMicros: 0,
      endMicros: 5000,
      statusCode: status,
    );

HttpProfileEntry _pending(String id) => HttpProfileEntry(
      id: id,
      method: 'GET',
      uri: 'https://example.com/$id',
      startMicros: 0,
    );

// A very long interval: the timer never fires and tests call poll() directly.
const Duration _never = Duration(hours: 1);

void main() {
  group('HttpProfileNetworkMonitor', () {
    late _FakeClient client;
    late HttpProfileNetworkMonitor monitor;
    late List<NetworkEvent> events;

    setUp(() {
      client = _FakeClient();
      monitor = HttpProfileNetworkMonitor(client: client, interval: _never);
      events = <NetworkEvent>[];
      monitor.events.listen(events.add);
    });

    tearDown(() => monitor.stop());

    test('start finds the isolate and switches recording on', () async {
      await monitor.start();
      expect(client.isolateCalls, 1);
      expect(client.enableCalls, 1);
    });

    test('reports finished requests once, and only when they finish', () async {
      await monitor.start();

      client.entries = <HttpProfileEntry>[_done('a'), _pending('b')];
      await monitor.poll();
      await pumpEventQueue();
      expect(events.map((e) => e.id), <String>['a']);

      client.entries = <HttpProfileEntry>[_done('b')];
      await monitor.poll();
      await pumpEventQueue();
      expect(events.map((e) => e.id), <String>['a', 'b']);

      // The VM may report the same request again; it must not repeat.
      client.entries = <HttpProfileEntry>[_done('a'), _done('b')];
      await monitor.poll();
      await pumpEventQueue();
      expect(events, hasLength(2));
    });

    test('asks only for what changed since the previous poll', () async {
      await monitor.start();
      await monitor.poll();
      client.timestamp = 250;
      await monitor.poll();
      await monitor.poll();

      expect(client.updatedSinceArgs, <int?>[null, 100, 250]);
    });

    test('a failed request is reported as failed', () async {
      await monitor.start();
      client.entries = <HttpProfileEntry>[
        const HttpProfileEntry(
          id: 'x',
          method: 'GET',
          uri: 'https://example.com/x',
          startMicros: 0,
          endMicros: 10,
        ),
      ];
      await monitor.poll();
      await pumpEventQueue();

      expect(events.single.failed, isTrue);
    });

    test('a burst is truncated to maxEventsPerPoll', () async {
      final capped = HttpProfileNetworkMonitor(
        client: client,
        interval: _never,
        maxEventsPerPoll: 2,
      );
      final seen = <NetworkEvent>[];
      capped.events.listen(seen.add);
      await capped.start();

      client.entries = <HttpProfileEntry>[
        for (var i = 0; i < 5; i++) _done('r$i'),
      ];
      await capped.poll();
      await pumpEventQueue();

      expect(seen, hasLength(2));
      await capped.stop();
    });

    test('a failed poll is skipped, and the isolate is looked up again',
        () async {
      await monitor.start();
      expect(client.isolateCalls, 1);

      client.fetchError = StateError('isolate gone');
      await monitor.poll(); // must not throw
      await pumpEventQueue();
      expect(events, isEmpty);

      client.entries = <HttpProfileEntry>[_done('after-restart')];
      await monitor.poll();
      await pumpEventQueue();

      expect(client.isolateCalls, 2);
      expect(client.enableCalls, 2); // recording is per isolate
      expect(events.single.id, 'after-restart');
    });

    test('without an isolate nothing is fetched, and it retries later',
        () async {
      client.isolate = null;
      await monitor.start();
      await monitor.poll();
      expect(client.updatedSinceArgs, isEmpty);

      client.isolate = 'isolate-2';
      client.entries = <HttpProfileEntry>[_done('late')];
      await monitor.poll();
      await pumpEventQueue();
      expect(events.single.id, 'late');
    });

    test('failing to switch recording on does not stop polling', () async {
      client.enableError = StateError('nope');
      await monitor.start();
      client.entries = <HttpProfileEntry>[_done('a')];
      await monitor.poll();
      await pumpEventQueue();

      expect(events.single.id, 'a');
    });

    test('stop disposes the client once, closes the stream, and is idempotent',
        () async {
      await monitor.start();
      var closed = false;
      monitor.events.listen(null, onDone: () => closed = true);

      await monitor.stop();
      await monitor.stop();
      await pumpEventQueue();

      expect(client.disposeCalls, 1);
      expect(closed, isTrue);

      // Polling after stop does nothing.
      client.entries = <HttpProfileEntry>[_done('z')];
      await monitor.poll();
      expect(client.updatedSinceArgs, isEmpty);
    });
  });

  group('connectNetworkMonitor', () {
    test('wires the connector and returns a running monitor', () async {
      final client = _FakeClient();
      String? receivedUri;
      final monitor = await connectNetworkMonitor(
        'ws://127.0.0.1:1234/abc=/ws',
        interval: _never,
        connector: (uri) async {
          receivedUri = uri;
          return client;
        },
      );

      expect(receivedUri, 'ws://127.0.0.1:1234/abc=/ws');
      expect(client.enableCalls, 1);
      await monitor.stop();
      expect(client.disposeCalls, 1);
    });

    test('a failing connection throws and leaves nothing open', () async {
      await expectLater(
        connectNetworkMonitor(
          'ws://127.0.0.1:1/x',
          connector: (_) async => throw StateError('refused'),
        ),
        throwsStateError,
      );
    });
  });
}
