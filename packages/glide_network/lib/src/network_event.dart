const int _maxUrlLength = 500;

/// Reduces [raw] to what is safe to show on a phone: scheme, host, port and
/// path.
///
/// User info, the query string and the fragment are dropped, because they
/// routinely carry credentials (`?token=...`, `https://user:pass@host`). When
/// a query existed, the result ends in `?...` so it is still visible that
/// something was removed.
String sanitizeUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '(unreadable address)';
  }
  final base = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
  final result = uri.hasQuery ? '$base?...' : base;
  return result.length > _maxUrlLength
      ? '${result.substring(0, _maxUrlLength)}...'
      : result;
}

/// One completed HTTP request made by the app.
///
/// Only the method, a sanitised address, the status, the duration and the
/// size are kept. Headers and bodies are never read.
class NetworkEvent {
  const NetworkEvent({
    required this.id,
    required this.method,
    required this.url,
    this.statusCode,
    this.durationMs,
    this.sizeBytes,
  });

  final String id;
  final String method;

  /// Already passed through [sanitizeUrl].
  final String url;

  /// Null when the request finished without a response (it failed).
  final int? statusCode;
  final int? durationMs;

  /// Response body length, when the server declared one.
  final int? sizeBytes;

  bool get failed => statusCode == null;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'method': method,
        'url': url,
        if (statusCode != null) 'statusCode': statusCode,
        if (durationMs != null) 'durationMs': durationMs,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        'failed': failed,
      };
}
