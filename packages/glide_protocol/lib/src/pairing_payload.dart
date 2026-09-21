import 'envelope.dart';
import 'foundation.dart';

/// The contents of the pairing QR code.
///
/// ```text
/// glide://pair?version=1&host=192.168.1.20&port=49400&session=GLIDE-7X21-K94&token=...&exp=...
/// ```
class PairingPayload {
  const PairingPayload({
    required this.host,
    required this.port,
    required this.sessionId,
    required this.token,
    required this.expiresAt,
    this.version = glideProtocolVersion,
  });

  /// Parses and strictly validates a scanned code.
  factory PairingPayload.parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'glide' || uri.host != 'pair') {
      throw const ProtocolException('This is not a Glide pairing code.');
    }
    final query = uri.queryParameters;
    final version = int.tryParse(query['version'] ?? '');
    if (version != glideProtocolVersion) {
      throw ProtocolException(
        'Unsupported pairing version ${query['version']}.',
      );
    }
    final host = query['host'] ?? '';
    if (!_hostPattern.hasMatch(host)) {
      throw const ProtocolException('Pairing code has an invalid host.');
    }
    final port = int.tryParse(query['port'] ?? '');
    if (port == null || port < 1 || port > 65535) {
      throw const ProtocolException('Pairing code has an invalid port.');
    }
    final session = query['session'] ?? '';
    if (!_sessionPattern.hasMatch(session)) {
      throw const ProtocolException('Pairing code has an invalid session id.');
    }
    final token = query['token'] ?? '';
    if (!_tokenPattern.hasMatch(token)) {
      throw const ProtocolException('Pairing code has an invalid token.');
    }
    final exp = int.tryParse(query['exp'] ?? '');
    if (exp == null) {
      throw const ProtocolException('Pairing code has no expiry.');
    }
    return PairingPayload(
      host: host,
      port: port,
      sessionId: session,
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp),
      version: version!,
    );
  }

  static final RegExp _hostPattern =
      RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.\-]{0,251}[A-Za-z0-9])?$');
  static final RegExp _sessionPattern = RegExp(r'^[A-Z0-9\-]{4,32}$');
  static final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_\-]{32,128}$');

  final int version;
  final String host;
  final int port;
  final String sessionId;
  final String token;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);

  /// The URI that is encoded into the QR code.
  Uri toUri() => Uri(
        scheme: 'glide',
        host: 'pair',
        queryParameters: <String, String>{
          'version': '$version',
          'host': host,
          'port': '$port',
          'session': sessionId,
          'token': token,
          'exp': '${expiresAt.millisecondsSinceEpoch}',
        },
      );

  /// Never includes the token.
  @override
  String toString() => 'PairingPayload($sessionId @ $host:$port)';
}
