import 'dart:async';

import 'package:web_socket_channel/io.dart';

/// A text channel to the computer. Reduced to what the companion needs so
/// tests can replace the network.
abstract interface class MessageChannel {
  /// Text frames from the computer. Ends when the connection closes.
  Stream<String> get incoming;

  void send(String text);

  Future<void> close();
}

/// Opens a [MessageChannel]. Throws [ConnectionFailure] when it cannot.
typedef ChannelConnector = Future<MessageChannel> Function(
  Uri uri, {
  Map<String, String> headers,
});

/// The computer could not be reached.
class ConnectionFailure implements Exception {
  const ConnectionFailure(this.message);

  final String message;

  @override
  String toString() => 'ConnectionFailure: $message';
}

/// The real connector, backed by a WebSocket.
Future<MessageChannel> connectWebSocket(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
}) async {
  final channel = IOWebSocketChannel.connect(
    uri,
    headers: headers,
    connectTimeout: const Duration(seconds: 8),
  );
  try {
    await channel.ready;
  } on Object catch (error) {
    throw ConnectionFailure(
      'Could not reach ${uri.host}:${uri.port} (${error.runtimeType}). '
      'Are the phone and the computer on the same Wi-Fi network?',
    );
  }
  return _WebSocketMessageChannel(channel);
}

class _WebSocketMessageChannel implements MessageChannel {
  _WebSocketMessageChannel(this._channel);

  final IOWebSocketChannel _channel;

  @override
  Stream<String> get incoming =>
      _channel.stream.where((frame) => frame is String).cast<String>();

  @override
  void send(String text) => _channel.sink.add(text);

  @override
  Future<void> close() => _channel.sink.close();
}
