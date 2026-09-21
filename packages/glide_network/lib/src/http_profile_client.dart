import 'network_event.dart';

/// One request as the VM service's HTTP profile reports it.
class HttpProfileEntry {
  const HttpProfileEntry({
    required this.id,
    required this.method,
    required this.uri,
    this.startMicros,
    this.endMicros,
    this.statusCode,
    this.contentLength,
  });

  final String id;
  final String method;

  /// The raw address. Never leaves this package without [sanitizeUrl].
  final String uri;
  final int? startMicros;
  final int? endMicros;
  final int? statusCode;
  final int? contentLength;

  /// True once the VM has recorded an end time for the request.
  bool get finished => endMicros != null;

  NetworkEvent toEvent() {
    final start = startMicros;
    final end = endMicros;
    final durationMs = start != null && end != null && end >= start
        ? (end - start) ~/ 1000
        : null;
    final length = contentLength;
    return NetworkEvent(
      id: id,
      method: method.toUpperCase(),
      url: sanitizeUrl(uri),
      statusCode: statusCode,
      durationMs: durationMs,
      // -1 is how dart:io says "length unknown".
      sizeBytes: length != null && length >= 0 ? length : null,
    );
  }
}

/// The requests the VM updated since a given time, plus the time to ask from
/// next.
class HttpProfileSnapshot {
  const HttpProfileSnapshot({required this.timestamp, required this.entries});

  /// Microseconds since the epoch, as reported by the VM.
  final int timestamp;
  final List<HttpProfileEntry> entries;
}

/// The small slice of the Dart VM service protocol the network monitor needs.
///
/// Real code depends on this interface rather than on `package:vm_service`,
/// so [HttpProfileNetworkMonitor] is testable without a VM service.
abstract interface class HttpProfileClient {
  /// The id of the isolate to observe, or null when none could be found.
  Future<String?> getMainIsolateId();

  /// Turns on HTTP request recording for [isolateId]. Requests made before
  /// this is called are not recorded.
  Future<void> enableLogging(String isolateId);

  /// Requests updated after [updatedSince] (all recorded requests when null).
  Future<HttpProfileSnapshot> fetch(String isolateId, {int? updatedSince});

  /// Closes the underlying connection.
  Future<void> dispose();
}

/// Connects to the Dart VM service at [wsUri] and returns a ready client.
typedef HttpProfileConnector = Future<HttpProfileClient> Function(
  String wsUri,
);
