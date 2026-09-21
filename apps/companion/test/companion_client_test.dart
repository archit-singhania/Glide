import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/core/companion_client.dart';
import 'package:glide_companion/core/message_channel.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

CompanionClient _client(
  FakeConnector connector, {
  Duration approvalTimeout = const Duration(seconds: 5),
  DateTime Function()? now,
}) =>
    CompanionClient(
      connect: connector.call,
      deviceId: 'companion-abc123',
      approvalTimeout: approvalTimeout,
      now: now,
    );

Matcher _failureWith(Matcher message) => throwsA(
      isA<PairingFailure>().having((e) => e.message, 'message', message),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CompanionClient.pair', () {
    test('redeems the code and returns the granted session token', () async {
      final connector = FakeConnector(
        pairReply: acceptedReply(token: 'granted-token'),
      );
      final payload = testPayload();

      final grant = await _client(connector).pair(payload);

      expect(grant.sessionToken, 'granted-token');
      final call = connector.calls.single;
      expect(call.uri.toString(), 'ws://192.168.1.20:49400/pair');
      final request = call.channel.sent.single;
      expect(request.type, MessageTypes.pairingRequest);
      expect(request.payload['session'], payload.sessionId);
      expect(request.payload['token'], payload.token);
      expect(request.payload['deviceId'], 'companion-abc123');
      expect(call.channel.closed, isTrue);
    });

    test('the request only carries fields the host expects', () async {
      final connector = FakeConnector(pairReply: acceptedReply());
      await _client(connector).pair(testPayload());

      final keys = connector.calls.single.channel.sent.single.payload.keys;
      expect(
        keys,
        unorderedEquals(<String>['session', 'token', 'deviceId', 'deviceName']),
      );
    });

    test('a rejection surfaces the host reason', () async {
      final connector = FakeConnector(
        pairReply: rejectedReply('That code is not valid.'),
      );

      await expectLater(
        _client(connector).pair(testPayload()),
        _failureWith(equals('That code is not valid.')),
      );
      expect(connector.calls.single.channel.closed, isTrue);
    });

    test('an expired code fails without touching the network', () async {
      final connector = FakeConnector(pairReply: acceptedReply());
      final payload = testPayload(
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      await expectLater(
        _client(connector).pair(payload),
        _failureWith(contains('expired')),
      );
      expect(connector.calls, isEmpty);
    });

    test('no answer from the computer times out with guidance', () async {
      final connector = FakeConnector();

      await expectLater(
        _client(
          connector,
          approvalTimeout: const Duration(milliseconds: 50),
        ).pair(testPayload()),
        _failureWith(contains('did not answer')),
      );
      expect(connector.calls.single.channel.closed, isTrue);
    });

    test('the computer hanging up before answering is reported', () async {
      final connector = FakeConnector(
        onPairRequest: (channel, message) => channel.dropConnection(),
      );

      await expectLater(
        _client(connector).pair(testPayload()),
        _failureWith(contains('closed the connection')),
      );
    });

    test('an unreadable reply is reported', () async {
      final connector = FakeConnector(
        onPairRequest: (channel, message) => channel.receiveRaw('not json'),
      );

      await expectLater(
        _client(connector).pair(testPayload()),
        _failureWith(contains('unreadable')),
      );
    });

    test('an unexpected message type is reported', () async {
      final connector = FakeConnector(pairReply: status('running'));

      await expectLater(
        _client(connector).pair(testPayload()),
        _failureWith(contains('unexpected')),
      );
    });

    test('an accepted reply without a token is refused', () async {
      final connector = FakeConnector(
        pairReply: GlideMessage.create(MessageTypes.pairingAccepted),
      );

      await expectLater(
        _client(connector).pair(testPayload()),
        _failureWith(contains('did not grant')),
      );
    });

    test('a connection failure becomes a pairing failure', () async {
      final connector = FakeConnector()
        ..failures['/pair'] = const ConnectionFailure('Could not reach it.');

      await expectLater(
        _client(connector).pair(testPayload()),
        _failureWith(equals('Could not reach it.')),
      );
    });
  });

  group('CompanionClient.openSession', () {
    test('connects to /ws with the session token header', () async {
      final connector = FakeConnector();

      final channel = await _client(connector).openSession(
        '192.168.1.20',
        49400,
        const PairingGrant(sessionToken: 'tok-123'),
      );

      final call = connector.calls.single;
      expect(call.uri.toString(), 'ws://192.168.1.20:49400/ws');
      expect(call.headers, <String, String>{controlTokenHeader: 'tok-123'});
      expect(channel, same(call.channel));
    });

    test('a connection failure becomes a pairing failure', () async {
      final connector = FakeConnector()
        ..failures['/ws'] = const ConnectionFailure('Unreachable.');

      await expectLater(
        _client(connector).openSession(
          '192.168.1.20',
          49400,
          const PairingGrant(sessionToken: 'tok-123'),
        ),
        _failureWith(equals('Unreachable.')),
      );
    });
  });

  test('a grant never prints its token', () {
    const grant = PairingGrant(sessionToken: 'super-secret-token');
    expect(grant.toString(), isNot(contains('super-secret-token')));
  });

  group('loadOrCreateDeviceId', () {
    test('creates a valid id once and then keeps it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      final first = await loadOrCreateDeviceId(prefs);
      final second = await loadOrCreateDeviceId(prefs);

      expect(deviceIdPattern.hasMatch(first), isTrue);
      expect(second, first);
    });

    test('replaces a stored id that would not pass host validation', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'device_id': 'bad id!'},
      );
      final prefs = await SharedPreferences.getInstance();

      final id = await loadOrCreateDeviceId(prefs);

      expect(id, isNot('bad id!'));
      expect(deviceIdPattern.hasMatch(id), isTrue);
    });
  });
}
