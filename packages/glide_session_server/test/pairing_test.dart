import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glide_protocol/glide_protocol.dart';
import 'package:glide_security/glide_security.dart';
import 'package:glide_session_server/glide_session_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

class _Info implements SessionInfoProvider {
  @override
  Map<String, Object?> sessionSnapshot() => <String, Object?>{
        'state': 'pairing',
      };

  @override
  Map<String, Object?>? projectSnapshot() => null;
}

class _Harness {
  _Harness({
    required this.server,
    required this.manager,
    required this.credential,
    required this.base,
  });

  final GlideSessionServer server;
  final PairingManager manager;
  final PairingCredential credential;
  final Uri base;
}

const String _sessionId = 'GLIDE-TEST-001';

Future<_Harness> _start(
  int port, {
  PairingApprover? approver,
  Duration timeout = const Duration(seconds: 5),
  void Function(Object, StackTrace)? onInternalError,
}) async {
  final manager = PairingManager();
  final credential = manager.issue(sessionId: _sessionId);
  final server = GlideSessionServer(
    authenticator: PairingManagerAuthenticator(manager),
    infoProvider: _Info(),
    preferredPort: port,
    pairingManager: manager,
    pairingApprover: approver,
    pairingTimeout: timeout,
    onInternalError: onInternalError,
  );
  final bound = await server.start();
  return _Harness(
    server: server,
    manager: manager,
    credential: credential,
    base: Uri.parse('http://127.0.0.1:${bound.port}'),
  );
}

/// Opens `/pair`, sends [frame], and returns the raw reply text.
Future<String> _sendFrame(Uri base, String frame) async {
  final channel = IOWebSocketChannel.connect(
    base.replace(scheme: 'ws', path: '/pair'),
  );
  await channel.ready;
  channel.sink.add(frame);
  final reply = await channel.stream.first as String;
  await channel.sink.close();
  return reply;
}

Future<String> _rawPair(
  _Harness h, {
  String? token,
  String? session,
  String deviceId = 'phone-1',
  Object? deviceName = 'Pixel 10',
}) =>
    _sendFrame(
      h.base,
      GlideMessage.create(
        MessageTypes.pairingRequest,
        payload: <String, Object?>{
          'session': session ?? _sessionId,
          'token': token ?? h.credential.token,
          'deviceId': deviceId,
          'deviceName': deviceName,
        },
      ).encode(),
    );

Future<GlideMessage> _pair(
  _Harness h, {
  String? token,
  String? session,
  String deviceId = 'phone-1',
  Object? deviceName = 'Pixel 10',
}) async =>
    GlideMessage.decode(
      await _rawPair(
        h,
        token: token,
        session: session,
        deviceId: deviceId,
        deviceName: deviceName,
      ),
    );

Future<int> _statusOf(Uri uri, {String? token}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (token != null) request.headers.set(controlTokenHeader, token);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _Harness h;
  var nextPort = 47610;

  Future<void> boot({
    PairingApprover? approver,
    Duration timeout = const Duration(seconds: 5),
    void Function(Object, StackTrace)? onInternalError,
  }) async {
    h = await _start(
      nextPort++,
      approver: approver,
      timeout: timeout,
      onInternalError: onInternalError,
    );
  }

  tearDown(() => h.server.stop());

  group('pairing handshake', () {
    test('a valid request is accepted and returns a session token', () async {
      await boot();
      final reply = await _pair(h);

      expect(reply.type, MessageTypes.pairingAccepted);
      expect(reply.payload['sessionId'], _sessionId);
      expect(reply.payload['deviceId'], 'phone-1');
      expect(reply.payload['protocol'], glideProtocolVersion);
      final sessionToken = reply.payload['sessionToken'] as String;
      expect(sessionToken.length, greaterThanOrEqualTo(32));
      expect(h.manager.isSessionTokenValid(sessionToken), isTrue);
    });

    test('the granted token unlocks the authenticated routes', () async {
      await boot();
      final reply = await _pair(h);
      final sessionToken = reply.payload['sessionToken'] as String;

      expect(
        await _statusOf(h.base.resolve('/v1/session'), token: sessionToken),
        200,
      );

      final channel = IOWebSocketChannel.connect(
        h.base.replace(scheme: 'ws', path: '/ws'),
        headers: <String, String>{controlTokenHeader: sessionToken},
      );
      await channel.ready;
      await channel.sink.close();
    });

    test('the QR pairing token is not a session token', () async {
      await boot();
      expect(
        await _statusOf(
          h.base.resolve('/v1/session'),
          token: h.credential.token,
        ),
        403,
      );
    });

    test('a pairing token can only be used once', () async {
      await boot();
      expect((await _pair(h)).type, MessageTypes.pairingAccepted);

      final second = await _pair(h, deviceId: 'phone-2');
      expect(second.type, MessageTypes.pairingRejected);
      expect(second.payload['code'], 'alreadyUsed');
    });

    test('a wrong token is rejected without echoing the real one', () async {
      await boot();
      final raw = await _rawPair(h, token: 'x' * 43);
      final reply = GlideMessage.decode(raw);

      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'invalidToken');
      expect(raw, isNot(contains(h.credential.token)));
    });

    test('a wrong session id is rejected', () async {
      await boot();
      final reply = await _pair(h, session: 'GLIDE-OTHER-999');
      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'noActivePairing');
    });

    test('repeated wrong tokens revoke the pairing', () async {
      await boot();
      for (var i = 0; i < 5; i++) {
        await _pair(h, token: 'y' * 43);
      }
      final reply = await _pair(h);
      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'revoked');
    });

    test('the host can decline a device', () async {
      PairingRequest? seen;
      await boot(
        approver: (request) async {
          seen = request;
          return false;
        },
      );

      final reply = await _pair(h, deviceName: 'Pixel 10');
      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'rejectedByHost');
      expect(seen?.deviceName, 'Pixel 10');
      expect(seen?.remoteAddress, '127.0.0.1');
      expect(h.manager.activeSessionCount, 0);
    });

    test('a frame that is not pairing.request is rejected', () async {
      await boot();
      final raw = await _sendFrame(
        h.base,
        GlideMessage.create('app.run').encode(),
      );
      final reply = GlideMessage.decode(raw);
      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'malformed');
    });

    test('malformed and oversized frames are rejected', () async {
      await boot();
      final notJson = GlideMessage.decode(await _sendFrame(h.base, 'nope'));
      expect(notJson.payload['code'], 'malformed');

      final huge = GlideMessage.decode(
        await _sendFrame(
          h.base,
          jsonEncode(<String, Object?>{'a': 'z' * 5000}),
        ),
      );
      expect(huge.payload['code'], 'malformed');
    });

    test('an unsafe device id is rejected and does not burn the token',
        () async {
      await boot();
      final bad = await _pair(h, deviceId: 'a; rm -rf /');
      expect(bad.type, MessageTypes.pairingRejected);
      expect(bad.payload['code'], 'malformed');

      final good = await _pair(h);
      expect(good.type, MessageTypes.pairingAccepted);
    });

    test('device names are sanitised before reaching the host', () async {
      await boot();
      final paired = h.server.pairedDevices.first;

      await _pair(h, deviceName: 'Evil\u001b[2J\u202ePhone');

      final device = await paired;
      expect(device.deviceName, isNot(contains('\u001b')));
      expect(device.deviceName, isNot(contains('\u202e')));
      expect(device.deviceName, contains('Phone'));
    });

    test('pairedDevices announces a successful pairing', () async {
      await boot();
      final paired = h.server.pairedDevices.first;
      await _pair(h, deviceId: 'phone-9', deviceName: 'Galaxy');

      final device = await paired;
      expect(device.deviceId, 'phone-9');
      expect(device.deviceName, 'Galaxy');
      expect(device.remoteAddress, '127.0.0.1');
    });

    test('a connection that sends nothing times out', () async {
      await boot(timeout: const Duration(milliseconds: 150));
      final channel = IOWebSocketChannel.connect(
        h.base.replace(scheme: 'ws', path: '/pair'),
      );
      await channel.ready;

      final reply = GlideMessage.decode(await channel.stream.first as String);
      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'timeout');
      await channel.sink.close();
    });

    test('an approver that throws yields a generic rejection', () async {
      Object? reported;
      await boot(
        approver: (_) async => throw StateError('boom'),
        onInternalError: (error, _) => reported = error,
      );

      final reply = await _pair(h);
      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'internal');
      expect(reply.payload['reason'], isNot(contains('boom')));
      expect(reported, isA<StateError>());
    });
  });

  group('without a pairing manager', () {
    test('/pair is not available', () async {
      final server = GlideSessionServer(
        authenticator: FixedTokenAuthenticator.single('t'),
        infoProvider: _Info(),
        preferredPort: 47690,
      );
      final bound = await server.start();
      addTearDown(server.stop);

      // Satisfy tearDown for the shared harness variable.
      h = _Harness(
        server: server,
        manager: PairingManager(),
        credential: PairingManager().issue(sessionId: _sessionId),
        base: Uri.parse('http://127.0.0.1:${bound.port}'),
      );

      await expectLater(
        IOWebSocketChannel.connect(
          h.base.replace(scheme: 'ws', path: '/pair'),
        ).ready,
        throwsA(anything),
      );
    });
  });

  group('PairingManagerAuthenticator', () {
    test('rejects null, empty and unknown tokens; accepts granted ones',
        () async {
      final manager = PairingManager();
      final credential = manager.issue(sessionId: _sessionId);
      final grant = await manager.redeem(
        sessionId: _sessionId,
        token: credential.token,
        request: const PairingRequest(deviceId: 'd', deviceName: 'Device'),
      );
      final auth = PairingManagerAuthenticator(manager);

      expect(auth.isValid(null), isFalse);
      expect(auth.isValid(''), isFalse);
      expect(auth.isValid('nope'), isFalse);
      expect(auth.isValid(credential.token), isFalse);
      expect(auth.isValid(grant.sessionToken), isTrue);

      manager.revokeSession(grant.sessionToken);
      expect(auth.isValid(grant.sessionToken), isFalse);
    });
  });
}
