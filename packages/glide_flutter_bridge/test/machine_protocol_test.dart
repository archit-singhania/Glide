import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('MachineMessageParser', () {
    test('parses an event frame', () {
      final messages = MachineMessageParser.parseLine(
        '[{"event":"app.started","params":{"appId":"1"}}]',
      );
      expect(messages, hasLength(1));
      final event = messages.single as MachineEvent;
      expect(event.name, 'app.started');
      expect(event.params['appId'], '1');
    });

    test('parses a success response', () {
      final messages = MachineMessageParser.parseLine(
        '[{"id":3,"result":42}]',
      );
      final response = messages.single as MachineResponse;
      expect(response.id, 3);
      expect(response.result, 42);
      expect(response.error, isNull);
    });

    test('parses an error response', () {
      final messages = MachineMessageParser.parseLine(
        '[{"id":3,"error":"boom"}]',
      );
      final response = messages.single as MachineResponse;
      expect(response.error, 'boom');
    });

    test('parses several frames on one line', () {
      final messages = MachineMessageParser.parseLine(
        '[{"event":"a","params":{}},{"id":1,"result":null}]',
      );
      expect(messages, hasLength(2));
      expect(messages[0], isA<MachineEvent>());
      expect(messages[1], isA<MachineResponse>());
    });

    test('treats plain output as text', () {
      final messages = MachineMessageParser.parseLine(
        'Waiting for another flutter command to release the startup lock...',
      );
      expect(messages.single, isA<MachineText>());
    });

    test('treats malformed JSON starting with [ as text, not a crash', () {
      final messages = MachineMessageParser.parseLine('[{not json');
      expect(messages.single, isA<MachineText>());
    });

    test('ignores blank lines', () {
      expect(MachineMessageParser.parseLine('   '), isEmpty);
    });

    test('ignores array items that are neither events nor responses', () {
      final messages = MachineMessageParser.parseLine('[{"noise":true}]');
      expect(messages, isEmpty);
    });
  });

  group('RequestRegistry', () {
    test('resolves a response to the matching pending request', () async {
      final registry = RequestRegistry();
      final pending = registry.register(
        'app.restart',
        const Duration(seconds: 1),
      );
      expect(registry.pendingCount, 1);

      registry.complete(MachineResponse(pending.id, result: 'ok'));

      expect(await pending.future, 'ok');
      expect(registry.pendingCount, 0);
    });

    test('turns an error response into a ToolRequestException', () async {
      final registry = RequestRegistry();
      final pending = registry.register(
        'app.restart',
        const Duration(seconds: 1),
      );

      registry.complete(MachineResponse(pending.id, error: 'nope'));

      await expectLater(pending.future, throwsA(isA<ToolRequestException>()));
    });

    test('a response for an unknown id is ignored, not thrown', () {
      final registry = RequestRegistry();
      // No matching pending request; should not throw.
      registry.complete(const MachineResponse(999, result: 'ignored'));
      expect(registry.pendingCount, 0);
    });

    test('requests time out on their own', () async {
      final registry = RequestRegistry();
      final pending = registry.register(
        'app.restart',
        const Duration(milliseconds: 20),
      );

      await expectLater(pending.future, throwsA(isA<ToolRequestTimeout>()));
      expect(registry.pendingCount, 0);
    });

    test('failAll rejects every outstanding request', () async {
      final registry = RequestRegistry();
      final a = registry.register('a', const Duration(seconds: 5));
      final b = registry.register('b', const Duration(seconds: 5));

      registry.failAll(ToolProcessExited(1));

      await expectLater(a.future, throwsA(isA<ToolProcessExited>()));
      await expectLater(b.future, throwsA(isA<ToolProcessExited>()));
    });
  });
}
