import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'recent_sessions';
const int _maxEntries = 6;

/// One computer Glide has connected to before, remembered only so the phone
/// can show "you've connected here before" — never a credential. A pairing
/// token is always single-use and is never stored, so recalling a recent
/// session never lets the phone skip scanning a new QR code.
class RecentSession {
  const RecentSession({
    required this.host,
    required this.port,
    required this.connectedAt,
  });

  factory RecentSession.fromJson(Map<String, Object?> json) => RecentSession(
        host: json['host'] as String? ?? '',
        port: json['port'] as int? ?? 0,
        connectedAt: DateTime.fromMillisecondsSinceEpoch(
          json['connectedAt'] as int? ?? 0,
        ),
      );

  final String host;
  final int port;
  final DateTime connectedAt;

  String get label => '$host:$port';

  Map<String, Object?> toJson() => <String, Object?>{
        'host': host,
        'port': port,
        'connectedAt': connectedAt.millisecondsSinceEpoch,
      };
}

/// Reads and writes the small "recently connected computers" list. Backed by
/// [SharedPreferences], which is synchronous once loaded, so this store
/// never needs to be async itself.
class RecentSessionsStore {
  const RecentSessionsStore(this._prefs);

  final SharedPreferences _prefs;

  /// Newest first.
  List<RecentSession> load() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const <RecentSession>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <RecentSession>[];
      final sessions = <RecentSession>[
        for (final item in decoded)
          if (item is Map)
            RecentSession.fromJson(Map<String, Object?>.from(item)),
      ];
      sessions.sort((a, b) => b.connectedAt.compareTo(a.connectedAt));
      return sessions;
    } on FormatException {
      return const <RecentSession>[];
    }
  }

  /// Adds or refreshes an entry for [host]:[port], most-recent first, capped
  /// to [_maxEntries].
  Future<void> record({required String host, required int port}) async {
    final sessions = List<RecentSession>.of(load())
      ..removeWhere((s) => s.host == host && s.port == port);
    sessions.insert(
      0,
      RecentSession(host: host, port: port, connectedAt: DateTime.now()),
    );
    await _save(sessions.take(_maxEntries).toList());
  }

  Future<void> remove({required String host, required int port}) async {
    final sessions = List<RecentSession>.of(load())
      ..removeWhere((s) => s.host == host && s.port == port);
    await _save(sessions);
  }

  Future<void> clear() => _save(const <RecentSession>[]);

  Future<void> _save(List<RecentSession> sessions) async {
    if (sessions.isEmpty) {
      await _prefs.remove(_prefsKey);
      return;
    }
    await _prefs.setString(
      _prefsKey,
      jsonEncode(<Map<String, Object?>>[for (final s in sessions) s.toJson()]),
    );
  }
}

/// A short, human "time ago" label with no locale dependency: "just now",
/// "5m ago", "3h ago", "2d ago", or the date once it's more than a week old.
String relativeTimeLabel(DateTime when, {DateTime Function()? now}) {
  final reference = (now ?? DateTime.now)();
  final diff = reference.difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${when.year}-${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';
}
