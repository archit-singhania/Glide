import 'package:glide_protocol/glide_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GlideMessage', () {
    test('round-trips through JSON', () {
      final message = GlideMessage.create(
        MessageTypes.sessionStatus,
        payload: {'state': 'running'},
      );
      final decoded = GlideMessage.decode(message.encode());
      expect(decoded.type, MessageTypes.sessionStatus);
      expect(decoded.protocol, glideProtocolVersion);
      expect(decoded.payload['state'], 'running');
      expect(decoded.id, message.id);
    });

    test('rejects an unsupported protocol version', () {
      const raw =
          '{"protocol":99,"id":"a","type":"x","timestamp":1,"payload":{}}';
      expect(
        () => GlideMessage.decode(raw),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects malformed JSON and non-objects', () {
      expect(
        () => GlideMessage.decode('{oops'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => GlideMessage.decode('[1,2]'),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects missing fields', () {
      const raw = '{"protocol":1,"id":"a","timestamp":1}';
      expect(
        () => GlideMessage.decode(raw),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects oversized frames', () {
      final raw = 'x' * (maxMessageBytes + 1);
      expect(
        () => GlideMessage.decode(raw),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('generated ids are unique v4 uuids', () {
      final ids = {for (var i = 0; i < 200; i++) generateMessageId()};
      expect(ids, hasLength(200));
      expect(
        ids.first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('CompanionCommand', () {
    GlideMessage msg(String type, [Map<String, Object?> payload = const {}]) =>
        GlideMessage.create(type, payload: payload);

    test('accepts allowlisted commands', () {
      final command = CompanionCommand.fromMessage(
        msg('app.run', {'deviceId': 'emulator-5554'}),
      );
      expect(command.type, CompanionCommandType.appRun);
      expect(command.deviceId, 'emulator-5554');
      expect(command.origin, CommandOrigin.companion);
    });

    test('rejects anything outside the allowlist', () {
      expect(
        () => CompanionCommand.fromMessage(msg('shell.exec', {'cmd': 'ls'})),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects device ids that could inject shell syntax', () {
      for (final bad in ['a; rm -rf /', 'x && calc', r'$(id)', 'a b', '']) {
        expect(
          () => CompanionCommand.fromMessage(msg('app.run', {'deviceId': bad})),
          throwsA(isA<ProtocolException>()),
          reason: bad,
        );
      }
    });

    test('restart mode defaults to hot and validates values', () {
      expect(
        CompanionCommand.fromMessage(msg('app.restart')).restartMode,
        RestartMode.hot,
      );
      expect(
        CompanionCommand.fromMessage(
          msg('app.restart', {'mode': 'full'}),
        ).restartMode,
        RestartMode.full,
      );
      expect(
        () => CompanionCommand.fromMessage(msg('app.restart', {'mode': 'x'})),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('PairingPayload', () {
    final expires = DateTime.fromMillisecondsSinceEpoch(1789965000000);
    final token = 'A' * 43;

    PairingPayload payload() => PairingPayload(
          host: '192.168.1.20',
          port: 49400,
          sessionId: 'GLIDE-7X21-K94',
          token: token,
          expiresAt: expires,
        );

    test('round-trips through its URI', () {
      final uri = payload().toUri().toString();
      expect(uri, startsWith('glide://pair?'));
      final parsed = PairingPayload.parse(uri);
      expect(parsed.host, '192.168.1.20');
      expect(parsed.port, 49400);
      expect(parsed.sessionId, 'GLIDE-7X21-K94');
      expect(parsed.token, token);
      expect(parsed.expiresAt, expires);
    });

    test('toString never leaks the token', () {
      expect(payload().toString(), isNot(contains(token)));
    });

    test('detects expiry', () {
      expect(payload().isExpired(expires), isTrue);
      expect(
        payload().isExpired(expires.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('rejects foreign schemes and malformed values', () {
      expect(
        () => PairingPayload.parse('https://example.com'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => PairingPayload.parse(
          'glide://pair?version=1&host=h&port=70000&session=ABCD&'
          'token=$token&exp=1',
        ),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => PairingPayload.parse(
          'glide://pair?version=1&host=h&port=1&session=ABCD&'
          'token=short&exp=1',
        ),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => PairingPayload.parse(
          'glide://pair?version=2&host=h&port=1&session=ABCD&'
          'token=$token&exp=1',
        ),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('SessionStateMachine', () {
    test('follows the happy path', () {
      final machine = SessionStateMachine();
      for (final next in [
        SessionState.pairing,
        SessionState.connected,
        SessionState.preparing,
        SessionState.building,
        SessionState.installing,
        SessionState.launching,
        SessionState.running,
        SessionState.reloading,
        SessionState.running,
        SessionState.restarting,
        SessionState.running,
        SessionState.stopping,
        SessionState.connected,
      ]) {
        machine.transitionTo(next);
        expect(machine.state, next);
      }
    });

    test('rejects illegal transitions', () {
      final machine = SessionStateMachine();
      expect(
        () => machine.transitionTo(SessionState.running),
        throwsA(isA<InvalidTransitionException>()),
      );
      expect(machine.tryTransitionTo(SessionState.reloading), isFalse);
      expect(machine.state, SessionState.disconnected);
    });

    test('any state may fail, but failed cannot fail again', () {
      final machine = SessionStateMachine(initial: SessionState.building);
      machine.transitionTo(SessionState.failed, reason: 'gradle');
      expect(machine.state, SessionState.failed);
      expect(machine.canTransitionTo(SessionState.failed), isFalse);
      machine.transitionTo(SessionState.preparing);
    });

    test('emits changes with reasons', () async {
      final machine = SessionStateMachine();
      final future = machine.changes.first;
      machine.transitionTo(SessionState.pairing, reason: 'qr shown');
      final change = await future;
      expect(change.from, SessionState.disconnected);
      expect(change.to, SessionState.pairing);
      expect(change.reason, 'qr shown');
      await machine.dispose();
    });
  });

  group('DiagnosticEvent', () {
    test('serialises and omits null fields', () {
      const event = DiagnosticEvent(
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.dart,
        source: 'Dart compiler',
        message: "Undefined name 'userss'.",
        file: 'lib/pages/home.dart',
        line: 82,
        column: 5,
      );
      final json = event.toJson();
      expect(json.containsKey('stackTrace'), isFalse);
      final back = DiagnosticEvent.fromJson(json);
      expect(back.line, 82);
      expect(back.category, DiagnosticCategory.dart);
    });
  });
}
