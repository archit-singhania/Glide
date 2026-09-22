import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/core/recent_sessions.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RecentSessionsStore> _store() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return RecentSessionsStore(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('starts empty', () async {
    final store = await _store();
    expect(store.load(), isEmpty);
  });

  test('record adds an entry, newest first', () async {
    final store = await _store();
    await store.record(host: '192.168.1.10', port: 49400);
    await store.record(host: '192.168.1.11', port: 49401);

    final sessions = store.load();
    expect(sessions, hasLength(2));
    expect(sessions.first.host, '192.168.1.11');
    expect(sessions.last.host, '192.168.1.10');
  });

  test('recording the same host:port again refreshes it to the top', () async {
    final store = await _store();
    await store.record(host: 'a.local', port: 1);
    await store.record(host: 'b.local', port: 2);
    await store.record(host: 'a.local', port: 1);

    final sessions = store.load();
    expect(sessions, hasLength(2));
    expect(sessions.first.label, 'a.local:1');
  });

  test('caps at six entries, dropping the oldest', () async {
    final store = await _store();
    for (var i = 0; i < 8; i++) {
      await store.record(host: 'host$i.local', port: 1000 + i);
    }
    final sessions = store.load();
    expect(sessions, hasLength(6));
    expect(sessions.first.host, 'host7.local');
    expect(sessions.map((s) => s.host), isNot(contains('host0.local')));
    expect(sessions.map((s) => s.host), isNot(contains('host1.local')));
  });

  test('remove drops a single entry', () async {
    final store = await _store();
    await store.record(host: 'a.local', port: 1);
    await store.record(host: 'b.local', port: 2);
    await store.remove(host: 'a.local', port: 1);

    final sessions = store.load();
    expect(sessions, hasLength(1));
    expect(sessions.single.host, 'b.local');
  });

  test('clear empties the list', () async {
    final store = await _store();
    await store.record(host: 'a.local', port: 1);
    await store.clear();
    expect(store.load(), isEmpty);
  });

  group('relativeTimeLabel', () {
    test('just now, minutes, hours, days and a date fallback', () {
      final now = DateTime(2026, 9, 22, 12);
      expect(
        relativeTimeLabel(
          now.subtract(const Duration(seconds: 5)),
          now: () => now,
        ),
        'just now',
      );
      expect(
        relativeTimeLabel(
          now.subtract(const Duration(minutes: 5)),
          now: () => now,
        ),
        '5m ago',
      );
      expect(
        relativeTimeLabel(
          now.subtract(const Duration(hours: 3)),
          now: () => now,
        ),
        '3h ago',
      );
      expect(
        relativeTimeLabel(
          now.subtract(const Duration(days: 2)),
          now: () => now,
        ),
        '2d ago',
      );
      expect(
        relativeTimeLabel(
          now.subtract(const Duration(days: 10)),
          now: () => now,
        ),
        '2026-09-12',
      );
    });
  });
}
