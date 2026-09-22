import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/core/companion_client.dart';
import 'package:glide_companion/core/message_channel.dart';
import 'package:glide_companion/features/session/session_notifier.dart';
import 'package:glide_companion/features/session/session_view.dart';
import 'package:glide_protocol/glide_protocol.dart';

import 'support/fakes.dart';

ProviderContainer _container(FakeConnector connector) {
  final container = ProviderContainer(
    overrides: [
      companionClientProvider.overrideWithValue(
        CompanionClient(connect: connector.call, deviceId: 'companion-abc123'),
      ),
      recentSessionsProvider.overrideWithValue(FakeRecentSessionsStore()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Pairs successfully and returns the open session channel.
Future<FakeMessageChannel> _connect(
  ProviderContainer container,
  FakeConnector connector,
) async {
  await container.read(sessionProvider.notifier).connect(testPayload());
  return connector.callsTo('/ws').last.channel;
}

void main() {
  late FakeConnector connector;
  late ProviderContainer container;
  late SessionNotifier notifier;

  SessionView view() => container.read(sessionProvider);

  setUp(() {
    connector = FakeConnector(pairReply: acceptedReply());
    container = _container(connector);
    notifier = container.read(sessionProvider.notifier);
  });

  group('connect', () {
    test('pairs, opens the session and asks for a snapshot', () async {
      final session = await _connect(container, connector);

      expect(view().link, LinkStatus.connected);
      expect(connector.callsTo('/pair'), hasLength(1));
      expect(
        connector.callsTo('/ws').single.headers[controlTokenHeader],
        'session-token-123',
      );
      expect(session.sent.single.type, 'diagnostics.request');
    });

    test('a rejected pairing ends in the failed state', () async {
      connector.pairReply = rejectedReply('That code is not valid.');

      await notifier.connect(testPayload());

      expect(view().link, LinkStatus.failed);
      expect(view().linkMessage, 'That code is not valid.');
      expect(connector.callsTo('/ws'), isEmpty);
      expect(notifier.canReconnect, isFalse);
    });

    test('failing to open the session after pairing is reported', () async {
      connector.failures['/ws'] = const ConnectionFailure('Unreachable.');

      await notifier.connect(testPayload());

      expect(view().link, LinkStatus.failed);
      expect(view().linkMessage, 'Unreachable.');
      expect(notifier.canReconnect, isFalse);
    });

    test('shows the pairing state while waiting for approval', () async {
      final states = <LinkStatus>[];
      container.listen<SessionView>(
        sessionProvider,
        (previous, next) => states.add(next.link),
      );

      await notifier.connect(testPayload());

      expect(states, <LinkStatus>[LinkStatus.pairing, LinkStatus.connected]);
    });
  });

  group('messages from the computer', () {
    test('update the view', () async {
      final session = await _connect(container, connector);

      session.receive(status('running'));
      await flush();

      expect(view().sessionState, 'running');
      expect(view().canReload, isTrue);
    });

    test('an unreadable frame is noted, not fatal', () async {
      final session = await _connect(container, connector);

      session
        ..receiveRaw('garbage')
        ..receive(status('running'));
      await flush();

      expect(view().noticeIsError, isTrue);
      expect(view().sessionState, 'running');
      expect(view().link, LinkStatus.connected);
    });
  });

  group('commands', () {
    test('map to the allowlisted wire commands', () async {
      final session = await _connect(container, connector);
      session.sent.clear();

      notifier
        ..run(deviceId: 'pixel-10')
        ..hotReload()
        ..hotRestart()
        ..fullRestart()
        ..stopApp()
        ..clearLogs();

      expect(
        session.sent.map((m) => m.type),
        <String>[
          'app.run',
          'app.reload',
          'app.restart',
          'app.restart',
          'app.stop',
          'logs.clear',
        ],
      );
      expect(session.sent[0].payload['deviceId'], 'pixel-10');
      expect(session.sent[2].payload, isEmpty);
      expect(session.sent[3].payload['mode'], 'full');
      for (final message in session.sent) {
        expect(CompanionCommandType.fromWire(message.type), isNotNull);
        // The host must accept everything the app can send.
        expect(() => CompanionCommand.fromMessage(message), returnsNormally);
      }
    });

    test('run without a device sends no payload', () async {
      final session = await _connect(container, connector);
      session.sent.clear();

      notifier.run();

      expect(session.sent.single.payload, isEmpty);
    });

    test('are ignored before connecting', () {
      notifier
        ..run()
        ..hotReload()
        ..stopApp();

      expect(connector.calls, isEmpty);
    });

    test('are not sent once the connection is lost', () async {
      final session = await _connect(container, connector);
      session.dropConnection();
      await flush();
      session.sent.clear();

      notifier.hotReload();

      expect(session.sent, isEmpty);
    });
  });

  group('losing the connection', () {
    test('marks the session disconnected and keeps the reason', () async {
      final session = await _connect(container, connector);

      session.dropConnection();
      await flush();

      expect(view().link, LinkStatus.disconnected);
      expect(view().linkMessage, 'The computer closed the connection.');
      expect(notifier.canReconnect, isTrue);
    });

    test('reconnect reuses the token and does not pair again', () async {
      final first = await _connect(container, connector);
      first.dropConnection();
      await flush();

      await notifier.reconnect();

      expect(view().link, LinkStatus.connected);
      expect(connector.callsTo('/pair'), hasLength(1));
      final ws = connector.callsTo('/ws').toList();
      expect(ws, hasLength(2));
      expect(ws.last.headers[controlTokenHeader], 'session-token-123');
      expect(ws.last.channel.sent.single.type, 'diagnostics.request');
    });

    test('a failed reconnect can be retried', () async {
      final first = await _connect(container, connector);
      first.dropConnection();
      await flush();
      connector.failures['/ws'] = const ConnectionFailure('Still down.');

      await notifier.reconnect();

      expect(view().link, LinkStatus.disconnected);
      expect(view().linkMessage, 'Still down.');
      expect(notifier.canReconnect, isTrue);

      connector.failures.clear();
      await notifier.reconnect();

      expect(view().link, LinkStatus.connected);
    });

    test('reconnect does nothing while already connected', () async {
      await _connect(container, connector);

      await notifier.reconnect();

      expect(connector.callsTo('/ws'), hasLength(1));
    });
  });

  group('disconnect', () {
    test('closes the channel and forgets the token', () async {
      final session = await _connect(container, connector);

      await notifier.disconnect();

      expect(session.closed, isTrue);
      expect(view().link, LinkStatus.disconnected);
      expect(view().linkMessage, 'Disconnected.');
      expect(notifier.canReconnect, isFalse);

      await notifier.reconnect();
      expect(connector.callsTo('/ws'), hasLength(1));
    });

    test('a new pairing replaces the old session', () async {
      final first = await _connect(container, connector);

      final second = await _connect(container, connector);

      expect(first.closed, isTrue);
      expect(second, isNot(same(first)));
      expect(view().link, LinkStatus.connected);
    });
  });
}
