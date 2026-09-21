import 'package:glide_protocol/glide_protocol.dart';

import 'crypto_utils.dart';

typedef Clock = DateTime Function();

enum PairingFailure {
  noActivePairing,
  invalidToken,
  expired,
  alreadyUsed,
  revoked,
  tooManyAttempts,
  rejectedByHost,
}

class PairingException extends GlideException {
  PairingException(this.failure, super.message);

  final PairingFailure failure;
}

/// The one-time secret shown in the QR code. Held in plain text only by the
/// caller that displays it; [PairingManager] keeps just a hash.
class PairingCredential {
  const PairingCredential({
    required this.sessionId,
    required this.token,
    required this.expiresAt,
  });

  final String sessionId;
  final String token;
  final DateTime expiresAt;

  @override
  String toString() => 'PairingCredential($sessionId, expires $expiresAt)';
}

/// Who is asking to pair.
class PairingRequest {
  const PairingRequest({
    required this.deviceId,
    required this.deviceName,
    this.remoteAddress,
  });

  final String deviceId;
  final String deviceName;
  final String? remoteAddress;
}

/// Result of a successful pairing.
class SessionGrant {
  const SessionGrant({
    required this.deviceId,
    required this.deviceName,
    required this.sessionToken,
    required this.issuedAt,
  });

  final String deviceId;
  final String deviceName;
  final String sessionToken;
  final DateTime issuedAt;

  @override
  String toString() => 'SessionGrant($deviceName)';
}

/// Lets the developer explicitly approve a device on the host.
typedef PairingApprover = Future<bool> Function(PairingRequest request);

class _GrantRecord {
  const _GrantRecord(this.deviceId, this.deviceName, this.issuedAt);

  final String deviceId;
  final String deviceName;
  final DateTime issuedAt;
}

/// Issues single-use pairing credentials and exchanges them for session
/// tokens.
///
/// Guarantees: 256-bit random tokens, 5 minute default expiry, single use,
/// revocable, lockout after repeated failures, only hashes retained.
class PairingManager {
  PairingManager({
    Clock? clock,
    Duration tokenLifetime = const Duration(minutes: 5),
    int maxFailedAttempts = 5,
    SecureRandom? random,
  })  : _clock = clock ?? DateTime.now,
        _lifetime = tokenLifetime,
        _maxFailed = maxFailedAttempts,
        _random = random ?? SecureRandom();

  final Clock _clock;
  final Duration _lifetime;
  final int _maxFailed;
  final SecureRandom _random;

  String? _sessionId;
  String? _tokenHash;
  DateTime? _expiresAt;
  bool _consumed = false;
  bool _revoked = false;
  bool _inFlight = false;
  int _failedAttempts = 0;
  final Map<String, _GrantRecord> _grants = <String, _GrantRecord>{};

  /// Creates a fresh credential, invalidating any previous one.
  PairingCredential issue({required String sessionId}) {
    final token = _random.token();
    _sessionId = sessionId;
    _tokenHash = sha256Hex(token);
    _expiresAt = _clock().add(_lifetime);
    _consumed = false;
    _revoked = false;
    _inFlight = false;
    _failedAttempts = 0;
    return PairingCredential(
      sessionId: sessionId,
      token: token,
      expiresAt: _expiresAt!,
    );
  }

  /// Validates [token] and, after optional host approval, returns a grant.
  Future<SessionGrant> redeem({
    required String sessionId,
    required String token,
    required PairingRequest request,
    PairingApprover? approver,
  }) async {
    final hash = _tokenHash;
    final expires = _expiresAt;
    if (hash == null || expires == null || _sessionId != sessionId) {
      throw PairingException(
        PairingFailure.noActivePairing,
        'No pairing is active for this session.',
      );
    }
    if (_revoked) {
      throw PairingException(PairingFailure.revoked, 'Pairing was revoked.');
    }
    if (_consumed || _inFlight) {
      throw PairingException(
        PairingFailure.alreadyUsed,
        'This pairing code was already used.',
      );
    }
    if (!_clock().isBefore(expires)) {
      throw PairingException(PairingFailure.expired, 'Pairing code expired.');
    }
    if (!constantTimeEquals(sha256Hex(token), hash)) {
      _failedAttempts++;
      if (_failedAttempts >= _maxFailed) {
        _revoked = true;
        throw PairingException(
          PairingFailure.tooManyAttempts,
          'Too many invalid attempts; pairing was revoked.',
        );
      }
      throw PairingException(PairingFailure.invalidToken, 'Invalid token.');
    }

    _inFlight = true;
    try {
      if (approver != null) {
        final approved = await approver(request);
        if (!approved) {
          _revoked = true;
          throw PairingException(
            PairingFailure.rejectedByHost,
            'The developer declined this device.',
          );
        }
      }
      if (!_clock().isBefore(expires)) {
        throw PairingException(PairingFailure.expired, 'Pairing code expired.');
      }
      _consumed = true;
    } finally {
      _inFlight = false;
    }

    final now = _clock();
    final sessionToken = _random.token();
    _grants[sha256Hex(sessionToken)] = _GrantRecord(
      request.deviceId,
      request.deviceName,
      now,
    );
    return SessionGrant(
      deviceId: request.deviceId,
      deviceName: request.deviceName,
      sessionToken: sessionToken,
      issuedAt: now,
    );
  }

  bool isSessionTokenValid(String token) =>
      _grants.containsKey(sha256Hex(token));

  /// Replaces [currentToken] with a new session token (rotation).
  SessionGrant? rotate(String currentToken) {
    final record = _grants.remove(sha256Hex(currentToken));
    if (record == null) return null;
    final next = _random.token();
    final now = _clock();
    _grants[sha256Hex(next)] = _GrantRecord(
      record.deviceId,
      record.deviceName,
      now,
    );
    return SessionGrant(
      deviceId: record.deviceId,
      deviceName: record.deviceName,
      sessionToken: next,
      issuedAt: now,
    );
  }

  void revokeSession(String token) => _grants.remove(sha256Hex(token));

  /// Invalidates the pairing code only.
  void revokePairing() => _revoked = true;

  /// Invalidates the pairing code and every issued session token.
  void revokeAll() {
    _revoked = true;
    _grants.clear();
  }

  int get activeSessionCount => _grants.length;
}
