import 'dart:async';

import 'package:glide_companion/core/message_channel.dart';
import 'package:glide_companion/core/recent_sessions.dart';
import 'package:glide_protocol/glide_protocol.dart';

/// Called for every message the app sends on a [FakeMessageChannel].
typedef SendHandler = void Function(
  FakeMessageChannel channel,
  GlideMessage message,
);

/// An in-memory [MessageChannel]. Frames sent to the app are buffered until it
/// listens, like a real WebSocket stream.
class FakeMessageChannel implements MessageChannel {
  FakeMessageChannel({this.onSend});

  final SendHandler? onSend;
  final StreamController<String> _incoming = StreamController<String>();

  /// Everything the app has sent, decoded.
  final List<GlideMessage> sent = <GlideMessage>[];
  bool closed = false;

  @override
  Stream<String> get incoming => _incoming.stream;

  @override
  void send(String text) {
    final message = GlideMessage.decode(text);
    sent.add(message);
    onSend?.call(this, message);
  }

  @override
  Future<void> close() async {
    closed = true;
    dropConnection();
  }

  /// A frame from the computer.
  void receive(GlideMessage message) => _incoming.add(message.encode());

  /// A frame that is not necessarily valid protocol.
  void receiveRaw(String text) => _incoming.add(text);

  /// The computer closes the connection.
  void dropConnection() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }
}

/// One call to the [FakeConnector].
class ConnectCall {
  const ConnectCall(this.uri, this.headers, this.channel);

  final Uri uri;
  final Map<String, String> headers;
  final FakeMessageChannel channel;
}

/// A [ChannelConnector] that records calls and hands out fake channels.
class FakeConnector {
  FakeConnector({this.pairReply, this.onPairRequest});

  /// Sent back as soon as a pairing request arrives on `/pair`.
  GlideMessage? pairReply;

  /// Replaces [pairReply] when a test needs finer control.
  SendHandler? onPairRequest;

  /// Connecting to these paths (for example `/ws`) fails.
  final Map<String, ConnectionFailure> failures = <String, ConnectionFailure>{};

  final List<ConnectCall> calls = <ConnectCall>[];

  Iterable<ConnectCall> callsTo(String path) =>
      calls.where((call) => call.uri.path == path);

  Future<MessageChannel> call(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final failure = failures[uri.path];
    if (failure != null) throw failure;

    SendHandler? handler;
    if (uri.path == '/pair') {
      final reply = pairReply;
      handler = onPairRequest ??
          (reply == null ? null : (channel, message) => channel.receive(reply));
    }
    final channel = FakeMessageChannel(onSend: handler);
    calls.add(ConnectCall(uri, headers, channel));
    return channel;
  }
}

/// A valid pairing payload for tests.
PairingPayload testPayload({DateTime? expiresAt}) => PairingPayload(
      host: '192.168.1.20',
      port: 49400,
      sessionId: 'GLIDE-7X21-K94',
      token: 'a' * 43,
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(minutes: 5)),
    );

GlideMessage acceptedReply({String token = 'session-token-123'}) =>
    GlideMessage.create(
      MessageTypes.pairingAccepted,
      payload: <String, Object?>{
        'sessionId': 'GLIDE-7X21-K94',
        'sessionToken': token,
        'deviceId': 'companion-abc123',
        'protocol': glideProtocolVersion,
      },
    );

GlideMessage rejectedReply(String reason) => GlideMessage.create(
      MessageTypes.pairingRejected,
      payload: <String, Object?>{'code': 'invalidToken', 'reason': reason},
    );

GlideMessage status(String state) => GlideMessage.create(
      MessageTypes.sessionStatus,
      payload: <String, Object?>{'state': state},
    );

/// Lets queued stream events and microtasks run.
Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// An in-memory [RecentSessionsStore] stand-in for tests, so they never
/// touch real `SharedPreferences`.
class FakeRecentSessionsStore implements RecentSessionsStore {
  final List<({String host, int port, DateTime connectedAt})> recorded =
      <({String host, int port, DateTime connectedAt})>[];

  @override
  List<RecentSession> load() => <RecentSession>[
        for (final entry in recorded.reversed)
          RecentSession(
            host: entry.host,
            port: entry.port,
            connectedAt: entry.connectedAt,
          ),
      ];

  @override
  Future<void> record({required String host, required int port}) async {
    recorded.add((host: host, port: port, connectedAt: DateTime.now()));
  }

  @override
  Future<void> remove({required String host, required int port}) async {
    recorded.removeWhere((e) => e.host == host && e.port == port);
  }

  @override
  Future<void> clear() async => recorded.clear();
}
