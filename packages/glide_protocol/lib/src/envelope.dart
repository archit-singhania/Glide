import 'dart:convert';

import 'foundation.dart';

/// Version of the Glide wire protocol. Every message carries it.
const int glideProtocolVersion = 1;

/// Upper bound for a single encoded message.
const int maxMessageBytes = 256 * 1024;

/// All message types understood by protocol version 1.
abstract final class MessageTypes {
  // Session lifecycle.
  static const String sessionCreated = 'session.created';
  static const String sessionConnected = 'session.connected';
  static const String sessionDisconnected = 'session.disconnected';
  static const String sessionStatus = 'session.status';
  static const String sessionSnapshot = 'session.snapshot';

  // Pairing handshake.
  static const String pairingRequest = 'pairing.request';
  static const String pairingAccepted = 'pairing.accepted';
  static const String pairingRejected = 'pairing.rejected';
  static const String authResume = 'auth.resume';

  // Devices and project.
  static const String deviceDiscovered = 'device.discovered';
  static const String deviceReady = 'device.ready';
  static const String deviceError = 'device.error';
  static const String projectDetected = 'project.detected';
  static const String projectUpdated = 'project.updated';

  // Build and app lifecycle.
  static const String buildStarted = 'build.started';
  static const String buildProgress = 'build.progress';
  static const String buildCompleted = 'build.completed';
  static const String buildFailed = 'build.failed';
  static const String appStarting = 'app.starting';
  static const String appStarted = 'app.started';
  static const String appStopped = 'app.stopped';

  // Reload and restart.
  static const String reloadStarted = 'reload.started';
  static const String reloadCompleted = 'reload.completed';
  static const String reloadFailed = 'reload.failed';
  static const String restartStarted = 'restart.started';
  static const String restartCompleted = 'restart.completed';
  static const String restartFailed = 'restart.failed';
  static const String restartRequired = 'restart.required';

  // Observability.
  static const String logEntry = 'log.entry';
  static const String logsCleared = 'logs.cleared';
  static const String errorReported = 'error.reported';
  static const String performanceSample = 'performance.sample';
  static const String networkRequest = 'network.request';
  static const String networkResponse = 'network.response';

  // DevTools, opened on the computer at the phone's request.
  static const String devtoolsOpened = 'devtools.opened';
  static const String devtoolsFailed = 'devtools.failed';

  // Host feedback about a rejected command.
  static const String commandRejected = 'command.rejected';
}

/// The envelope that wraps every message on the wire.
///
/// ```json
/// {"protocol":1,"id":"uuid","type":"session.status","timestamp":1789965000000,"payload":{}}
/// ```
class GlideMessage {
  const GlideMessage({
    required this.protocol,
    required this.id,
    required this.type,
    required this.timestamp,
    this.payload = const <String, Object?>{},
  });

  /// Creates a message for the current protocol version.
  factory GlideMessage.create(
    String type, {
    Map<String, Object?> payload = const <String, Object?>{},
    DateTime? now,
  }) =>
      GlideMessage(
        protocol: glideProtocolVersion,
        id: generateMessageId(),
        type: type,
        timestamp: (now ?? DateTime.now()).millisecondsSinceEpoch,
        payload: payload,
      );

  /// Validates and parses a decoded JSON object.
  factory GlideMessage.fromJson(Map<String, Object?> json) {
    final protocol = json['protocol'];
    if (protocol is! int) {
      throw const ProtocolException('Missing or invalid "protocol" field.');
    }
    if (protocol != glideProtocolVersion) {
      throw ProtocolException(
        'Unsupported protocol version $protocol '
        '(this build speaks $glideProtocolVersion).',
      );
    }
    final id = json.stringOrNull('id');
    if (id == null || id.isEmpty || id.length > 64) {
      throw const ProtocolException('Missing or invalid "id" field.');
    }
    final type = json.stringOrNull('type');
    if (type == null || type.isEmpty || type.length > 64) {
      throw const ProtocolException('Missing or invalid "type" field.');
    }
    final timestamp = json.intOrNull('timestamp');
    if (timestamp == null) {
      throw const ProtocolException('Missing or invalid "timestamp" field.');
    }
    final rawPayload = json['payload'];
    final Map<String, Object?> payload;
    if (rawPayload == null) {
      payload = const <String, Object?>{};
    } else if (rawPayload is Map) {
      payload = Map<String, Object?>.from(rawPayload);
    } else {
      throw const ProtocolException('"payload" must be a JSON object.');
    }
    return GlideMessage(
      protocol: protocol,
      id: id,
      type: type,
      timestamp: timestamp,
      payload: payload,
    );
  }

  /// Parses a raw text frame, enforcing the size limit.
  factory GlideMessage.decode(String raw) {
    if (raw.length > maxMessageBytes) {
      throw const ProtocolException('Message exceeds the size limit.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw ProtocolException('Malformed JSON.', cause: error);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ProtocolException('A message must be a JSON object.');
    }
    return GlideMessage.fromJson(decoded);
  }

  final int protocol;
  final String id;
  final String type;

  /// Milliseconds since the Unix epoch.
  final int timestamp;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocol': protocol,
        'id': id,
        'type': type,
        'timestamp': timestamp,
        'payload': payload,
      };

  String encode() => jsonEncode(toJson());

  @override
  String toString() => 'GlideMessage($type, id: $id)';
}
