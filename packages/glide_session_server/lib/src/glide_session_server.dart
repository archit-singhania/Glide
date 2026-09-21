import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glide_protocol/glide_protocol.dart';
import 'package:glide_security/glide_security.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'session_authenticator.dart';
import 'session_info_provider.dart';

/// Raised when the server cannot be started.
class SessionServerException extends GlideException {
  const SessionServerException(super.message, {super.cause});
}

/// The address and port a [GlideSessionServer] ended up bound to.
class BoundSession {
  const BoundSession({required this.address, required this.port});

  final InternetAddress address;
  final int port;

  @override
  String toString() => '${address.address}:$port';
}

/// A companion that completed the pairing handshake.
///
/// Never carries a token.
class PairedDevice {
  const PairedDevice({
    required this.deviceId,
    required this.deviceName,
    this.remoteAddress,
  });

  final String deviceId;

  /// Sanitised: control and bidirectional-override characters are removed and
  /// the length is capped, so it is safe to print to a terminal.
  final String deviceName;
  final String? remoteAddress;

  @override
  String toString() => 'PairedDevice($deviceName)';
}

/// The header a companion presents its session token in. Already treated as
/// a secret to redact by the Redactor in `glide_security`.
const String controlTokenHeader = 'x-glide-control-token';

const Map<String, String> _jsonHeaders = <String, String>{
  'content-type': 'application/json',
};

/// Pairing requests are tiny; anything larger is rejected before parsing.
const int _maxPairingFrameLength = 4096;

/// The local HTTP + WebSocket server a companion pairs and communicates
/// with.
///
/// Routes:
/// - `GET /health` - unauthenticated liveness check.
/// - `GET /pair` - WebSocket upgrade for the pairing handshake. Not
///   authenticated (the companion only holds the QR token yet), so it accepts
///   exactly one `pairing.request` frame, answers with `pairing.accepted` or
///   `pairing.rejected`, and closes. 404 unless a [pairingManager] was given.
/// - `GET /v1/session` - current session snapshot; requires a session token.
/// - `GET /v1/project` - current project snapshot, 404 until one is
///   detected; requires a session token.
/// - `GET /ws` - upgrades to the WebSocket protocol channel; requires a
///   session token.
///
/// Binds to [address] (loopback by default; production callers pass a
/// specific LAN address - never a wildcard address) starting at
/// [preferredPort], trying up to [maxPortAttempts] consecutive ports if one
/// is already in use.
class GlideSessionServer implements CommandSource, EventPublisher {
  GlideSessionServer({
    required this.authenticator,
    required this.infoProvider,
    InternetAddress? address,
    this.preferredPort = 49400,
    this.maxPortAttempts = 5,
    this.pairingManager,
    this.pairingApprover,
    this.pairingTimeout = const Duration(seconds: 10),
    this.onInternalError,
  }) : address = address ?? InternetAddress.loopbackIPv4;

  final SessionAuthenticator authenticator;
  final SessionInfoProvider infoProvider;
  final InternetAddress address;
  final int preferredPort;
  final int maxPortAttempts;

  /// Enables `/pair`. The same manager should back [authenticator] (see
  /// `PairingManagerAuthenticator`) so a granted token is accepted.
  final PairingManager? pairingManager;

  /// Asks the developer to approve a device before it is granted a token.
  final PairingApprover? pairingApprover;

  /// How long a `/pair` connection may wait before sending its request.
  final Duration pairingTimeout;

  /// Called with unexpected failures during pairing (the companion only ever
  /// sees a generic "internal" rejection).
  final void Function(Object error, StackTrace stackTrace)? onInternalError;

  HttpServer? _httpServer;
  BoundSession? _bound;
  final Set<WebSocketChannel> _channels = <WebSocketChannel>{};
  final Set<WebSocketChannel> _pairingChannels = <WebSocketChannel>{};
  final StreamController<CompanionCommand> _commands =
      StreamController<CompanionCommand>.broadcast();
  final StreamController<PairedDevice> _paired =
      StreamController<PairedDevice>.broadcast();

  @override
  Stream<CompanionCommand> get commands => _commands.stream;

  /// Emits each companion that completes pairing.
  Stream<PairedDevice> get pairedDevices => _paired.stream;

  /// Where the server ended up listening, once [start] completes.
  BoundSession? get bound => _bound;

  /// How many companions currently have a WebSocket connection open.
  int get connectionCount => _channels.length;

  /// Binds the server, trying [preferredPort], then the next
  /// [maxPortAttempts] - 1 ports if it is taken.
  Future<BoundSession> start() async {
    if (_httpServer != null) {
      throw const SessionServerException(
        'The session server is already running.',
      );
    }
    Object? lastError;
    for (var attempt = 0; attempt < maxPortAttempts; attempt++) {
      final port = preferredPort + attempt;
      try {
        final server = await shelf_io.serve(_handle, address, port);
        _httpServer = server;
        final bound = BoundSession(address: address, port: port);
        _bound = bound;
        return bound;
      } on SocketException catch (error) {
        lastError = error;
      }
    }
    throw SessionServerException(
      'Could not bind to any port from $preferredPort to '
      '${preferredPort + maxPortAttempts - 1}.',
      cause: lastError,
    );
  }

  /// Closes every connection and stops listening. Safe to call more than
  /// once, including before [start].
  Future<void> stop() async {
    for (final channel in <WebSocketChannel>[
      ..._channels,
      ..._pairingChannels,
    ]) {
      unawaited(channel.sink.close().catchError((_) {}));
    }
    _channels.clear();
    _pairingChannels.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
    _bound = null;
    if (!_commands.isClosed) await _commands.close();
    if (!_paired.isClosed) await _paired.close();
  }

  /// Sends [message] to every currently connected companion.
  @override
  void publish(GlideMessage message) {
    final encoded = message.encode();
    for (final channel in _channels) {
      channel.sink.add(encoded);
    }
  }

  FutureOr<Response> _handle(Request request) {
    switch (request.url.path) {
      case 'health':
        return _health();
      case 'pair':
        return _pairUpgrade(request);
      case 'v1/session':
        return _authorized(request, _session);
      case 'v1/project':
        return _authorized(request, _project);
      case 'ws':
        return _authorized(request, _upgrade);
      default:
        return Response.notFound(
          jsonEncode(<String, Object?>{'error': 'not_found'}),
          headers: _jsonHeaders,
        );
    }
  }

  Response _health() => Response.ok(
        jsonEncode(<String, Object?>{
          'status': 'ok',
          'protocol': glideProtocolVersion,
        }),
        headers: _jsonHeaders,
      );

  FutureOr<Response> _authorized(
    Request request,
    FutureOr<Response> Function(Request request) handler,
  ) {
    if (!authenticator.isValid(request.headers[controlTokenHeader])) {
      return Response.forbidden(
        jsonEncode(<String, Object?>{'error': 'unauthorized'}),
        headers: _jsonHeaders,
      );
    }
    return handler(request);
  }

  Response _session(Request request) => Response.ok(
        jsonEncode(infoProvider.sessionSnapshot()),
        headers: _jsonHeaders,
      );

  Response _project(Request request) {
    final snapshot = infoProvider.projectSnapshot();
    if (snapshot == null) {
      return Response.notFound(
        jsonEncode(<String, Object?>{'error': 'no_project'}),
        headers: _jsonHeaders,
      );
    }
    return Response.ok(jsonEncode(snapshot), headers: _jsonHeaders);
  }

  FutureOr<Response> _upgrade(Request request) =>
      webSocketHandler((WebSocketChannel channel, [String? protocol]) {
        _channels.add(channel);
        channel.stream.listen(
          (data) => _onFrame(channel, data),
          onDone: () => _channels.remove(channel),
          onError: (Object _) => _channels.remove(channel),
          cancelOnError: true,
        );
      })(request);

  void _onFrame(WebSocketChannel channel, Object? data) {
    if (data is! String) return;
    try {
      final message = GlideMessage.decode(data);
      final command = CompanionCommand.fromMessage(
        message,
        origin: CommandOrigin.companion,
      );
      if (!_commands.isClosed) _commands.add(command);
    } on ProtocolException catch (error) {
      channel.sink.add(
        GlideMessage.create(
          MessageTypes.commandRejected,
          payload: <String, Object?>{'reason': error.message},
        ).encode(),
      );
    }
  }

  // ---------------------------------------------------------------- pairing

  FutureOr<Response> _pairUpgrade(Request request) {
    final manager = pairingManager;
    if (manager == null) {
      return Response.notFound(
        jsonEncode(<String, Object?>{'error': 'pairing_disabled'}),
        headers: _jsonHeaders,
      );
    }
    final connection = request.context['shelf.io.connection_info'];
    final remote = connection is HttpConnectionInfo
        ? connection.remoteAddress.address
        : null;
    return webSocketHandler((WebSocketChannel channel, [String? protocol]) {
      _servePairing(channel, manager, remote);
    })(request);
  }

  /// Serves exactly one `pairing.request` on [channel], then closes it.
  void _servePairing(
    WebSocketChannel channel,
    PairingManager manager,
    String? remote,
  ) {
    _pairingChannels.add(channel);
    var handled = false;

    Future<void> finish(GlideMessage reply) async {
      _pairingChannels.remove(channel);
      try {
        channel.sink.add(reply.encode());
        await channel.sink.close();
      } on Object {
        // The companion disconnected before the reply could be delivered.
      }
    }

    final timer = Timer(pairingTimeout, () {
      if (handled) return;
      handled = true;
      unawaited(
        finish(
          _rejected('timeout', 'No pairing request was received in time.'),
        ),
      );
    });

    channel.stream.listen(
      (Object? data) {
        if (handled) return;
        handled = true;
        timer.cancel();
        unawaited(_completePairing(manager, remote, data).then(finish));
      },
      onDone: () {
        timer.cancel();
        _pairingChannels.remove(channel);
      },
      onError: (Object _) {
        timer.cancel();
        _pairingChannels.remove(channel);
      },
      cancelOnError: true,
    );
  }

  Future<GlideMessage> _completePairing(
    PairingManager manager,
    String? remote,
    Object? data,
  ) async {
    try {
      if (data is! String) {
        return _rejected('malformed', 'Expected a text message.');
      }
      if (data.length > _maxPairingFrameLength) {
        return _rejected('malformed', 'Pairing request is too large.');
      }
      final message = GlideMessage.decode(data);
      if (message.type != MessageTypes.pairingRequest) {
        return _rejected('malformed', 'Expected a pairing.request message.');
      }
      final session = message.payload.stringOrNull('session');
      final token = message.payload.stringOrNull('token');
      final deviceId = message.payload.stringOrNull('deviceId');
      if (session == null ||
          token == null ||
          deviceId == null ||
          session.length > 32 ||
          token.length > 128) {
        return _rejected(
          'malformed',
          'The request needs session, token and deviceId.',
        );
      }
      if (!deviceIdPattern.hasMatch(deviceId)) {
        return _rejected('malformed', 'Invalid device id.');
      }
      final deviceName = _sanitizeDeviceName(
        message.payload.stringOrNull('deviceName'),
        fallback: deviceId,
      );

      final grant = await manager.redeem(
        sessionId: session,
        token: token,
        request: PairingRequest(
          deviceId: deviceId,
          deviceName: deviceName,
          remoteAddress: remote,
        ),
        approver: pairingApprover,
      );

      if (!_paired.isClosed) {
        _paired.add(
          PairedDevice(
            deviceId: grant.deviceId,
            deviceName: grant.deviceName,
            remoteAddress: remote,
          ),
        );
      }
      return GlideMessage.create(
        MessageTypes.pairingAccepted,
        payload: <String, Object?>{
          'sessionId': session,
          'sessionToken': grant.sessionToken,
          'deviceId': grant.deviceId,
          'protocol': glideProtocolVersion,
        },
      );
    } on PairingException catch (error) {
      return _rejected(error.failure.name, error.message);
    } on ProtocolException catch (error) {
      return _rejected('malformed', error.message);
    } catch (error, stackTrace) {
      onInternalError?.call(error, stackTrace);
      return _rejected('internal', 'Pairing failed.');
    }
  }

  GlideMessage _rejected(String code, String reason) => GlideMessage.create(
        MessageTypes.pairingRejected,
        payload: <String, Object?>{'code': code, 'reason': reason},
      );
}

final RegExp _unsafeNameCharacters = RegExp(
  r'[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]',
);

/// Device names come from an untrusted peer and end up on the developer's
/// terminal, so strip control and bidi-override characters and cap the length.
String _sanitizeDeviceName(String? raw, {required String fallback}) {
  final cleaned = (raw ?? '').replaceAll(_unsafeNameCharacters, '').trim();
  if (cleaned.isEmpty) return fallback;
  return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
}
