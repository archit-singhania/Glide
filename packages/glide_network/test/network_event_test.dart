import 'package:glide_network/glide_network.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeUrl', () {
    test('keeps scheme, host, port and path', () {
      expect(
        sanitizeUrl('https://api.example.com:8443/v1/users'),
        'https://api.example.com:8443/v1/users',
      );
    });

    test('drops the query and marks that something was removed', () {
      final result = sanitizeUrl('https://api.example.com/u?token=abc123&x=1');
      expect(result, 'https://api.example.com/u?...');
      expect(result, isNot(contains('abc123')));
    });

    test('drops user info and fragments', () {
      final result = sanitizeUrl('https://bob:secret@example.com/a#frag');
      expect(result, 'https://example.com/a');
      expect(result, isNot(contains('secret')));
      expect(result, isNot(contains('bob')));
    });

    test('does not echo something that is not an address', () {
      expect(sanitizeUrl('not a url'), '(unreadable address)');
      expect(sanitizeUrl('/relative/path?token=abc'), '(unreadable address)');
    });

    test('caps very long paths', () {
      final result = sanitizeUrl('https://example.com/${'a' * 2000}');
      expect(result.length, lessThan(520));
    });
  });

  group('HttpProfileEntry.toEvent', () {
    test('computes duration, upper-cases the method, sanitises the url', () {
      const entry = HttpProfileEntry(
        id: '1',
        method: 'get',
        uri: 'https://api.example.com/users?key=SECRET',
        startMicros: 1000000,
        endMicros: 1342000,
        statusCode: 200,
        contentLength: 18300,
      );
      final event = entry.toEvent();
      expect(event.method, 'GET');
      expect(event.url, 'https://api.example.com/users?...');
      expect(event.durationMs, 342);
      expect(event.statusCode, 200);
      expect(event.sizeBytes, 18300);
      expect(event.failed, isFalse);
      expect(event.toJson().toString(), isNot(contains('SECRET')));
    });

    test('a request with no response is reported as failed', () {
      const entry = HttpProfileEntry(
        id: '2',
        method: 'POST',
        uri: 'https://example.com/x',
        startMicros: 10,
        endMicros: 20,
      );
      final event = entry.toEvent();
      expect(event.failed, isTrue);
      expect(event.toJson().containsKey('statusCode'), isFalse);
      expect(event.toJson()['failed'], isTrue);
    });

    test('an unknown content length (-1) is left out', () {
      const entry = HttpProfileEntry(
        id: '3',
        method: 'GET',
        uri: 'https://example.com/x',
        endMicros: 20,
        statusCode: 200,
        contentLength: -1,
      );
      expect(entry.toEvent().sizeBytes, isNull);
    });

    test('an end time before the start time gives no duration', () {
      const entry = HttpProfileEntry(
        id: '4',
        method: 'GET',
        uri: 'https://example.com/x',
        startMicros: 500,
        endMicros: 100,
      );
      expect(entry.toEvent().durationMs, isNull);
    });
  });
}
