import 'dart:async';
import 'dart:collection';

import 'http_profile_client.dart';
import 'io_http_profile_client.dart';
import 'network_event.dart';

const int _maxRemembered = 5000;

/// Reports the HTTP requests a running app finishes. Started and stopped by
/// whoever owns the app's session; nothing here decides when an app runs.
abstract interface class NetworkMonitor {
  /// One event per completed request, in the order they were noticed.
  Stream<NetworkEvent> get events;

  /// Stops polling and releases the connection. Safe to call more than once.
  Future<void> stop();
}

/// Connects to the Dart VM service at [vmServiceUri] and starts watching.
///
/// The returned monitor is already running. If the connection itself fails
/// this throws and nothing is left open. Once connected, a failed poll is
/// swallowed and simply skipped.
Future<NetworkMonitor> connectNetworkMonitor(
  String vmServiceUri, {
  Duration interval = const Duration(seconds: 2),
  HttpProfileConnector connector = IoHttpProfileClient.connect,
}) async {
  final client = await connector(vmServiceUri);
  final monitor = HttpProfileNetworkMonitor(client: client, interval: interval);
  try {
    await monitor.start();
  } on Object {
    await monitor.stop();
    rethrow;
  }
  return monitor;
}

/// [NetworkMonitor] that polls the VM service's HTTP profile.
///
/// This uses the same recording DevTools' Network tab uses, so it sees
/// requests made through `dart:io` (and therefore `package:http`, `dio` and
/// friends on mobile) without the app being changed. It cannot see traffic
/// that does not go through `dart:io`, such as requests made by native
/// plugins or WebViews, and it only sees requests made after recording was
/// switched on.
///
/// Only method, sanitised address, status, duration and size are read.
/// Headers and bodies are never requested.
///
/// Exposed (rather than kept private) so tests can drive it against a fake
/// [HttpProfileClient] by calling [poll] directly.
class HttpProfileNetworkMonitor implements NetworkMonitor {
  HttpProfileNetworkMonitor({
    required this.client,
    this.interval = const Duration(seconds: 2),
    this.maxEventsPerPoll = 50,
  });

  final HttpProfileClient client;
  final Duration interval;

  /// A burst larger than this in one window is truncated, so a chatty app
  /// cannot flood a phone. The remainder of that burst is dropped.
  final int maxEventsPerPoll;

  final StreamController<NetworkEvent> _out =
      StreamController<NetworkEvent>.broadcast();
  final LinkedHashSet<String> _reported = LinkedHashSet<String>();
  Timer? _timer;
  String? _isolateId;
  int? _since;
  bool _stopped = false;
  bool _polling = false;

  @override
  Stream<NetworkEvent> get events => _out.stream;

  /// Resolves the isolate, switches recording on and starts the timer.
  Future<void> start() async {
    _isolateId = await _resolveIsolate();
    _timer = Timer.periodic(interval, (_) => unawaited(poll()));
  }

  /// Looks for the isolate and switches HTTP recording on for it. A hot
  /// restart replaces the isolate, so this also runs again after a failure.
  Future<String?> _resolveIsolate() async {
    try {
      final id = await client.getMainIsolateId();
      if (id == null) return null;
      try {
        await client.enableLogging(id);
      } on Object {
        // Recording may already be on; polling is still worth trying.
      }
      return id;
    } on Object {
      return null;
    }
  }

  /// Reads the requests that finished since the last poll. Public so tests
  /// can drive it without a timer.
  Future<void> poll() async {
    if (_stopped || _polling) return;
    _polling = true;
    try {
      final isolateId = _isolateId ??= await _resolveIsolate();
      if (isolateId == null || _stopped) return;
      final HttpProfileSnapshot snapshot;
      try {
        snapshot = await client.fetch(isolateId, updatedSince: _since);
      } on Object {
        // The isolate may have been replaced; look it up again next time.
        _isolateId = null;
        return;
      }
      if (_stopped) return;
      _since = snapshot.timestamp;
      var emitted = 0;
      for (final entry in snapshot.entries) {
        if (!entry.finished || _reported.contains(entry.id)) continue;
        if (emitted >= maxEventsPerPoll) break;
        _remember(entry.id);
        emitted++;
        if (!_out.isClosed) _out.add(entry.toEvent());
      }
    } finally {
      _polling = false;
    }
  }

  void _remember(String id) {
    _reported.add(id);
    if (_reported.length > _maxRemembered) {
      _reported.remove(_reported.first);
    }
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    try {
      await client.dispose();
    } on Object {
      // The connection may already be gone (app closed first).
    }
    if (!_out.isClosed) await _out.close();
  }
}
