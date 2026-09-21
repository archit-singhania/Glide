import 'dart:async';
import 'dart:math';

import 'package:glide_protocol/glide_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_channel.dart';

/// Must match the header the host's session server checks.
const String controlTokenHeader = 'x-glide-control-token';

/// Pairing did not complete. [message] is safe to show to the user.
class PairingFailure implements Exception {
  const PairingFailure(this.message);

  final String message;

  @override
  String toString() => 'PairingFailure: $message';
}

/// What the host granted after a successful pairing.
class PairingGrant {
  const PairingGrant({required this.sessionToken});

  /// Secret; kept in memory only and never logged or stored.
  final String sessionToken;

  @override
  String toString() => 'PairingGrant(<redacted>)';
}

/// Talks to `glide start` over the local network.
class CompanionClient {
  CompanionClient({
    required this.connect,
    required this.deviceId,
    this.deviceName = 'Glide Companion',
    DateTime Function()? now,
    this.approvalTimeout = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final ChannelConnector connect;

  /// Stable, random per install; matches the host's device id rules.
  final String deviceId;
  final String deviceName;

  /// The developer has to approve the pairing on their computer, so waiting
  /// for the answer can take a while.
  final Duration approvalTimeout;
  final DateTime Function() _now;

  /// Redeems the scanned code and returns a session token.
  Future<PairingGrant> pair(PairingPayload payload) async {
    if (payload.isExpired(_now())) {
      throw const PairingFailure(
        'This pairing code has expired. Run "glide start" again.',
      );
    }
    final channel = await _open(
      Uri(scheme: 'ws', host: payload.host, port: payload.port, path: '/pair'),
    );
    try {
      channel.send(
        GlideMessage.create(
          MessageTypes.pairingRequest,
          payload: <String, Object?>{
            'session': payload.sessionId,
            'token': payload.token,
            'deviceId': deviceId,
            'deviceName': deviceName,
          },
        ).encode(),
      );
      final String raw;
      try {
        raw = await channel.incoming.first.timeout(approvalTimeout);
      } on TimeoutException {
        throw const PairingFailure(
          'The computer did not answer. Approve the pairing in the terminal.',
        );
      } on StateError {
        throw const PairingFailure(
          'The computer closed the connection before answering.',
        );
      }
      return _readReply(raw);
    } finally {
      await channel.close();
    }
  }

  PairingGrant _readReply(String raw) {
    final GlideMessage message;
    try {
      message = GlideMessage.decode(raw);
    } on ProtocolException {
      throw const PairingFailure('The computer sent an unreadable reply.');
    }
    if (message.type == MessageTypes.pairingAccepted) {
      final token = message.payload.stringOrNull('sessionToken');
      if (token == null || token.isEmpty) {
        throw const PairingFailure('The computer did not grant a session.');
      }
      return PairingGrant(sessionToken: token);
    }
    if (message.type == MessageTypes.pairingRejected) {
      throw PairingFailure(
        message.payload.stringOrNull('reason') ?? 'Pairing was rejected.',
      );
    }
    throw const PairingFailure('The computer sent an unexpected reply.');
  }

  /// Opens the authenticated protocol channel.
  Future<MessageChannel> openSession(
    String host,
    int port,
    PairingGrant grant,
  ) =>
      _open(
        Uri(scheme: 'ws', host: host, port: port, path: '/ws'),
        headers: <String, String>{controlTokenHeader: grant.sessionToken},
      );

  Future<MessageChannel> _open(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    try {
      return await connect(uri, headers: headers);
    } on ConnectionFailure catch (error) {
      throw PairingFailure(error.message);
    }
  }
}

/// A random id for this install, created once and then remembered.
Future<String> loadOrCreateDeviceId(SharedPreferences prefs) async {
  const key = 'device_id';
  final existing = prefs.getString(key);
  if (existing != null && deviceIdPattern.hasMatch(existing)) return existing;
  final random = Random.secure();
  final hex = List<String>.generate(
    12,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  final created = 'companion-$hex';
  await prefs.setString(key, created);
  return created;
}
