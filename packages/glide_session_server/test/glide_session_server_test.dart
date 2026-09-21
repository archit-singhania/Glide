import 'dart:convert';
import 'dart:io';

import 'package:glide_protocol/glide_protocol.dart';
import 'package:glide_session_server/glide_session_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

class _FakeInfoProvider implements SessionInfoProvider {
  Map<String, Object?>? project;

  @override
  Map<String, Object?> sessionSnapshot() => <String, Object?>{
        'state': 'connected',
      };

  @override
  Map<String, Object?>? projectSnapshot() => project;
}

/// A fully read HTTP response. Reading the body before the client closes
/// avoids "connection closed while receiving data".
class _Reply {
  const _Reply(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

Future<_Reply> _get(
  Uri uri, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    if (token != null) request.headers.set(controlTokenHeader, token);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return _Reply(response.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

void main() {
  group('GlideSessionServer', () {
    late _FakeInfoProvider info;
    late GlideSessionServer server;
    late FixedTokenAuthenticator auth;

    setUp(() {
      info = _FakeInfoProvider();
      auth = FixedTokenAuthenticator.single('secret-token');
    });

    tearDown(() => server.stop());

    test('binds to the preferred port when it is free', () async {
      server = GlideSessionServer(
        authenticator: auth,
        infoProvider: info,
        preferredPort: 47510,
      );
      final bound = await server.start();
      expect(bound.port, 47510);
    });

    test('falls back to the next port when the preferred one is taken',
        () async {
      final blocker = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        47520,
      );
      addTearDown(blocker.close);

      server = GlideSessionServer(
        authenticator: auth,
        infoProvider: info,
        preferredPort: 47520,
      );
      final bound = await server.start();
      expect(bound.port, 47521);
    });

    test('gives up after exhausting every attempt', () async {
      final blockers = <ServerSocket>[
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 47530),
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 47531),
      ];
      addTearDown(() async {
        for (final b in blockers) {
          await b.close();
        }
      });

      server = GlideSessionServer(
        authenticator: auth,
        infoProvider: info,
        preferredPort: 47530,
        maxPortAttempts: 2,
      );
      await expectLater(server.start(), throwsA(isA<SessionServerException>()));
    });

    test('starting twice without stopping is rejected', () async {
      server = GlideSessionServer(
        authenticator: auth,
        infoProvider: info,
        preferredPort: 47540,
      );
      await server.start();
      await expectLater(server.start(), throwsA(isA<SessionServerException>()));
    });

    group('HTTP', () {
      late Uri base;

      setUp(() async {
        server = GlideSessionServer(
          authenticator: auth,
          infoProvider: info,
          preferredPort: 47550,
        );
        final bound = await server.start();
        base = Uri.parse('http://127.0.0.1:${bound.port}');
      });

      test('GET /health needs no token', () async {
        final response = await _get(base.resolve('/health'));
        expect(response.statusCode, 200);
        final body = jsonDecode(response.body) as Map<String, Object?>;
        expect(body['status'], 'ok');
      });

      test('GET /v1/session without a token is forbidden', () async {
        final response = await _get(base.resolve('/v1/session'));
        expect(response.statusCode, 403);
      });

      test('GET /v1/session with an invalid token is forbidden', () async {
        final response = await _get(
          base.resolve('/v1/session'),
          token: 'wrong',
        );
        expect(response.statusCode, 403);
      });

      test('GET /v1/session with the right token returns the snapshot',
          () async {
        final response = await _get(
          base.resolve('/v1/session'),
          token: 'secret-token',
        );
        expect(response.statusCode, 200);
        final body = jsonDecode(response.body) as Map<String, Object?>;
        expect(body['state'], 'connected');
      });

      test('GET /v1/project is 404 until a project is detected', () async {
        final response = await _get(
          base.resolve('/v1/project'),
          token: 'secret-token',
        );
        expect(response.statusCode, 404);
      });

      test('GET /v1/project returns the snapshot once one is set', () async {
        info.project = <String, Object?>{'name': 'shop_app'};
        final response = await _get(
          base.resolve('/v1/project'),
          token: 'secret-token',
        );
        expect(response.statusCode, 200);
        final body = jsonDecode(response.body) as Map<String, Object?>;
        expect(body['name'], 'shop_app');
      });

      test('an unknown path is 404', () async {
        final response = await _get(
          base.resolve('/nope'),
          token: 'secret-token',
        );
        expect(response.statusCode, 404);
      });
    });

    group('WebSocket', () {
      late Uri wsUri;

      setUp(() async {
        server = GlideSessionServer(
          authenticator: auth,
          infoProvider: info,
          preferredPort: 47560,
        );
        final bound = await server.start();
        wsUri = Uri.parse('ws://127.0.0.1:${bound.port}/ws');
      });

      test('a connection with a valid token is accepted', () async {
        final channel = IOWebSocketChannel.connect(
          wsUri,
          headers: <String, String>{controlTokenHeader: 'secret-token'},
        );
        await channel.ready;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(server.connectionCount, 1);
        await channel.sink.close();
      });

      test('a connection without a token is rejected', () async {
        final channel = IOWebSocketChannel.connect(wsUri);
        await expectLater(channel.ready, throwsA(anything));
      });

      test('a valid command reaches the commands stream', () async {
        final channel = IOWebSocketChannel.connect(
          wsUri,
          headers: <String, String>{controlTokenHeader: 'secret-token'},
        );
        await channel.ready;
        final received = server.commands.first;

        channel.sink.add(
          GlideMessage.create(
            'app.reload',
            payload: <String, Object?>{},
          ).encode(),
        );

        final command = await received;
        expect(command.type, CompanionCommandType.appReload);
        expect(command.origin, CommandOrigin.companion);
        await channel.sink.close();
      });

      test('a disallowed message gets rejected, not a crash', () async {
        final channel = IOWebSocketChannel.connect(
          wsUri,
          headers: <String, String>{controlTokenHeader: 'secret-token'},
        );
        await channel.ready;
        final commandsHeard = <Object?>[];
        final sub = server.commands.listen(commandsHeard.add);

        channel.sink.add(
          GlideMessage.create(
            'shell.exec',
            payload: <String, Object?>{'cmd': 'rm -rf /'},
          ).encode(),
        );

        final reply = await channel.stream.first as String;
        final message = GlideMessage.decode(reply);
        expect(message.type, MessageTypes.commandRejected);
        expect(commandsHeard, isEmpty);

        await sub.cancel();
        await channel.sink.close();
      });

      test('publish sends a message to every connected companion', () async {
        final channel = IOWebSocketChannel.connect(
          wsUri,
          headers: <String, String>{controlTokenHeader: 'secret-token'},
        );
        await channel.ready;
        final incoming = channel.stream.first;

        server.publish(
          GlideMessage.create(
            MessageTypes.logEntry,
            payload: <String, Object?>{'message': 'hello'},
          ),
        );

        final raw = await incoming as String;
        final message = GlideMessage.decode(raw);
        expect(message.type, MessageTypes.logEntry);
        expect(message.payload['message'], 'hello');
        await channel.sink.close();
      });

      test('a device id in an app.run payload must be valid', () async {
        final channel = IOWebSocketChannel.connect(
          wsUri,
          headers: <String, String>{controlTokenHeader: 'secret-token'},
        );
        await channel.ready;

        channel.sink.add(
          GlideMessage.create(
            'app.run',
            payload: <String, Object?>{'deviceId': 'a; rm -rf /'},
          ).encode(),
        );

        final reply = await channel.stream.first as String;
        expect(GlideMessage.decode(reply).type, MessageTypes.commandRejected);
        await channel.sink.close();
      });
    });

    test('stop closes open connections and refuses new ones', () async {
      server = GlideSessionServer(
        authenticator: auth,
        infoProvider: info,
        preferredPort: 47570,
      );
      final bound = await server.start();
      final wsUri = Uri.parse('ws://127.0.0.1:${bound.port}/ws');
      final channel = IOWebSocketChannel.connect(
        wsUri,
        headers: <String, String>{controlTokenHeader: 'secret-token'},
      );
      await channel.ready;

      await server.stop();

      await expectLater(
        IOWebSocketChannel.connect(wsUri).ready,
        throwsA(anything),
      );
    });
  });
}
