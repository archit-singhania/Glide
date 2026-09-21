/// Removes secrets from text before it is logged or displayed.
class Redactor {
  final Set<String> _secrets = <String>{};

  static final List<RegExp> _patterns = <RegExp>[
    RegExp(r'token=[A-Za-z0-9_\-]{16,}'),
    RegExp(r'Bearer\s+[A-Za-z0-9._\-]{8,}', caseSensitive: false),
    RegExp(r'x-glide-control-token:\s*\S+', caseSensitive: false),
  ];

  /// Registers an exact secret so any occurrence is masked.
  void register(String secret) {
    if (secret.length >= 8) _secrets.add(secret);
  }

  String redact(String input) {
    var output = input;
    for (final secret in _secrets) {
      output = output.replaceAll(secret, '[redacted]');
    }
    for (final pattern in _patterns) {
      output = output.replaceAll(pattern, '[redacted]');
    }
    return output;
  }
}

/// Identifies files that must never be transmitted to a companion.
abstract final class SensitivePathGuard {
  static final List<RegExp> _patterns = <RegExp>[
    RegExp(r'^\.env(\..*)?$'),
    RegExp(r'\.(jks|keystore|pem|p12|p8|pfx|mobileprovision|cer)$'),
    RegExp(r'^key\.properties$'),
    RegExp(r'^id_(rsa|dsa|ecdsa|ed25519)$'),
    RegExp(r'service[-_]?account.*\.json$'),
    RegExp(r'credentials.*\.json$'),
    RegExp(r'^\.(npmrc|netrc|pgpass)$'),
  ];

  static bool isSensitive(String path) {
    final name = path.split(RegExp(r'[\\/]')).last.toLowerCase();
    return _patterns.any((pattern) => pattern.hasMatch(name));
  }
}

/// Address classification used to keep the session LAN-only.
abstract final class NetworkPolicy {
  /// True for RFC 1918, link-local and loopback IPv4 addresses.
  static bool isPrivateIPv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) return false;
      octets.add(value);
    }
    final a = octets[0];
    final b = octets[1];
    return a == 10 ||
        a == 127 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 169 && b == 254);
  }

  static bool isLoopback(String address) =>
      address == 'localhost' || address == '::1' || address.startsWith('127.');

  /// True for the wildcard addresses that expose a service on every interface.
  static bool isWildcard(String address) =>
      address == '0.0.0.0' || address == '::' || address == '[::]';
}
