import 'package:glide_security/glide_security.dart';
import 'package:test/test.dart';

const _device = PairingRequest(deviceId: 'dev-1', deviceName: 'Pixel 10');

void main() {
  late DateTime now;
  late PairingManager manager;

  setUp(() {
    now = DateTime(2026, 9, 21, 12);
    manager = PairingManager(clock: () => now);
  });

  Future<Object?> redeemError(
    String session,
    String token, {
    PairingApprover? approver,
  }) async {
    try {
      await manager.redeem(
        sessionId: session,
        token: token,
        request: _device,
        approver: approver,
      );
      return null;
    } on PairingException catch (e) {
      return e.failure;
    }
  }

  test('tokens are 256-bit, unique and expire in five minutes', () {
    final a = manager.issue(sessionId: 'S1');
    final b = manager.issue(sessionId: 'S1');
    expect(a.token, isNot(b.token));
    expect(a.token.length, greaterThanOrEqualTo(43));
    expect(b.expiresAt.difference(now), const Duration(minutes: 5));
  });

  test('redeems once and issues a valid session token', () async {
    final credential = manager.issue(sessionId: 'S1');
    final grant = await manager.redeem(
      sessionId: 'S1',
      token: credential.token,
      request: _device,
    );
    expect(manager.isSessionTokenValid(grant.sessionToken), isTrue);
    expect(manager.isSessionTokenValid('nope'), isFalse);
    expect(
      await redeemError('S1', credential.token),
      PairingFailure.alreadyUsed,
    );
  });

  test('rejects wrong tokens and locks out after five failures', () async {
    manager.issue(sessionId: 'S1');
    for (var i = 0; i < 4; i++) {
      expect(await redeemError('S1', 'wrong'), PairingFailure.invalidToken);
    }
    expect(await redeemError('S1', 'wrong'), PairingFailure.tooManyAttempts);
    expect(await redeemError('S1', 'wrong'), PairingFailure.revoked);
  });

  test('rejects expired tokens', () async {
    final credential = manager.issue(sessionId: 'S1');
    now = now.add(const Duration(minutes: 5, seconds: 1));
    expect(await redeemError('S1', credential.token), PairingFailure.expired);
  });

  test('rejects a mismatched session id', () async {
    final credential = manager.issue(sessionId: 'S1');
    expect(
      await redeemError('OTHER', credential.token),
      PairingFailure.noActivePairing,
    );
  });

  test('host rejection burns the credential', () async {
    final credential = manager.issue(sessionId: 'S1');
    expect(
      await redeemError('S1', credential.token, approver: (_) async => false),
      PairingFailure.rejectedByHost,
    );
    expect(await redeemError('S1', credential.token), PairingFailure.revoked);
  });

  test('revocation invalidates pairing and sessions', () async {
    final credential = manager.issue(sessionId: 'S1');
    final grant = await manager.redeem(
      sessionId: 'S1',
      token: credential.token,
      request: _device,
    );
    manager.revokeAll();
    expect(manager.isSessionTokenValid(grant.sessionToken), isFalse);
  });

  test('session tokens rotate', () async {
    final credential = manager.issue(sessionId: 'S1');
    final grant = await manager.redeem(
      sessionId: 'S1',
      token: credential.token,
      request: _device,
    );
    final rotated = manager.rotate(grant.sessionToken)!;
    expect(manager.isSessionTokenValid(grant.sessionToken), isFalse);
    expect(manager.isSessionTokenValid(rotated.sessionToken), isTrue);
    expect(manager.rotate('unknown'), isNull);
  });

  test('constantTimeEquals', () {
    expect(constantTimeEquals('abc', 'abc'), isTrue);
    expect(constantTimeEquals('abc', 'abd'), isFalse);
    expect(constantTimeEquals('abc', 'abcd'), isFalse);
  });

  test('Redactor masks registered secrets and token patterns', () {
    final redactor = Redactor()..register('supersecretvalue');
    expect(redactor.redact('x supersecretvalue y'), 'x [redacted] y');
    expect(
      redactor.redact('glide://pair?token=${'A' * 43}&x=1'),
      isNot(contains('AAAA')),
    );
    expect(
      redactor.redact('Authorization: Bearer abcdefgh12345'),
      contains('[redacted]'),
    );
  });

  test('SensitivePathGuard flags secrets', () {
    for (final path in [
      '.env',
      '.env.production',
      r'android\app\upload.jks',
      'android/key.properties',
      'home/.ssh/id_rsa',
      'ios/cert.p12',
    ]) {
      expect(SensitivePathGuard.isSensitive(path), isTrue, reason: path);
    }
    expect(SensitivePathGuard.isSensitive('lib/main.dart'), isFalse);
  });

  test('NetworkPolicy', () {
    expect(NetworkPolicy.isPrivateIPv4('192.168.1.20'), isTrue);
    expect(NetworkPolicy.isPrivateIPv4('10.0.0.5'), isTrue);
    expect(NetworkPolicy.isPrivateIPv4('172.20.1.1'), isTrue);
    expect(NetworkPolicy.isPrivateIPv4('172.32.0.1'), isFalse);
    expect(NetworkPolicy.isPrivateIPv4('8.8.8.8'), isFalse);
    expect(NetworkPolicy.isWildcard('0.0.0.0'), isTrue);
  });
}
