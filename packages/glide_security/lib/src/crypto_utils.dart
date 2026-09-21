import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Cryptographically secure random values.
class SecureRandom {
  SecureRandom([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  Uint8List bytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// A URL-safe token with [byteLength] bytes (256 bits by default).
  String token({int byteLength = 32}) =>
      base64Url.encode(bytes(byteLength)).replaceAll('=', '');
}

/// Lowercase hex SHA-256 digest of [value].
String sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

/// Compares two strings without leaking where they first differ.
bool constantTimeEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  final length = max(x.length, y.length);
  for (var i = 0; i < length; i++) {
    final left = i < x.length ? x[i] : 0;
    final right = i < y.length ? y[i] : 0;
    diff |= left ^ right;
  }
  return diff == 0;
}
