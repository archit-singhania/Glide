import 'dart:math';

/// Base type for every typed, expected failure raised inside Glide.
class GlideException implements Exception {
  const GlideException(this.message, {this.cause});

  /// Human readable description. Never contains secrets.
  final String message;

  /// The underlying error, when this wraps another failure.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Raised when a wire message is malformed, oversized or not allowed.
class ProtocolException extends GlideException {
  const ProtocolException(super.message, {super.cause});
}

final Random _random = Random.secure();

/// Generates an RFC 4122 version 4 identifier using secure randomness.
String generateMessageId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

const String _sessionAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Generates a short, human friendly session id such as `GLIDE-7X21-K94`.
String generateSessionId() {
  String part(int length) => List<String>.generate(
        length,
        (_) => _sessionAlphabet[_random.nextInt(_sessionAlphabet.length)],
      ).join();
  return 'GLIDE-${part(4)}-${part(3)}';
}

/// Typed readers for JSON objects, avoiding scattered casts.
extension JsonMapReaders on Map<String, Object?> {
  String? stringOrNull(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  int? intOrNull(String key) {
    final value = this[key];
    return value is int ? value : null;
  }

  bool? boolOrNull(String key) {
    final value = this[key];
    return value is bool ? value : null;
  }

  Map<String, Object?>? mapOrNull(String key) {
    final value = this[key];
    return value is Map ? Map<String, Object?>.from(value) : null;
  }
}
