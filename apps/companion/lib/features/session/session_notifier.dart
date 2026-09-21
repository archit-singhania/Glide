import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glide_protocol/glide_protocol.dart';

import '../../core/companion_client.dart';
import '../../core/message_channel.dart';
import 'session_view.dart';

/// Provided in `main()` (and overridden in tests).
final Provider<CompanionClient> companionClientProvider =
    Provider<CompanionClient>(
  (ref) => throw UnimplementedError('companionClientProvider not overridden'),
);

final NotifierProvider<SessionNotifier, SessionView> sessionProvider =
    NotifierProvider<SessionNotifier, SessionView>(SessionNotifier.new);

/// Owns the connection to the computer and the [SessionView] built from it.
class SessionNotifier extends Notifier<SessionView> {
  MessageChannel? _channel;
  StreamSubscription<String>? _subscription;

  // Kept in memory only, so a dropped connection can be reopened without
  // scanning again. Never persisted or logged. Cleared by [disconnect] and
  // by the next [connect].
  PairingGrant? _grant;
  String? _host;
  int? _port;

  @override
  SessionView build() {
    ref.onDispose(_closeChannel);
    return const SessionView();
  }

  /// Whether [reconnect] can reopen the last session without a new QR code.
  bool get canReconnect => _grant != null;

  /// Pairs using [payload], then opens the session channel.
  Future<void> connect(PairingPayload payload) async {
    await _closeChannel();
    _forgetGrant();
    state = const SessionView(link: LinkStatus.pairing);
    final client = ref.read(companionClientProvider);
    try {
      final grant = await client.pair(payload);
      await _openSession(payload.host, payload.port, grant);
    } on PairingFailure catch (error) {
      _forgetGrant();
      state = SessionView(
        link: LinkStatus.failed,
        linkMessage: error.message,
      );
    }
  }

  /// Reopens the session after the connection was lost, using the session
  /// token from the original pairing. The host replies with a fresh snapshot.
  Future<void> reconnect() async {
    final grant = _grant;
    final host = _host;
    final port = _port;
    if (grant == null || host == null || port == null) return;
    if (state.link == LinkStatus.connected ||
        state.link == LinkStatus.reconnecting) {
      return;
    }
    await _closeChannel();
    state = state.copyWith(link: LinkStatus.reconnecting);
    try {
      await _openSession(host, port, grant);
    } on PairingFailure catch (error) {
      state = state.copyWith(
        link: LinkStatus.disconnected,
        linkMessage: error.message,
      );
    }
  }

  Future<void> _openSession(
    String host,
    int port,
    PairingGrant grant,
  ) async {
    final channel =
        await ref.read(companionClientProvider).openSession(host, port, grant);
    _grant = grant;
    _host = host;
    _port = port;
    _channel = channel;
    _subscription = channel.incoming.listen(
      _onFrame,
      onDone: () => _onClosed('The computer closed the connection.'),
      onError: (Object _) => _onClosed('The connection was lost.'),
    );
    state = const SessionView(link: LinkStatus.connected);
    _send(CompanionCommandType.diagnosticsRequest);
  }

  void _onFrame(String raw) {
    try {
      state = reduceMessage(state, GlideMessage.decode(raw));
    } on ProtocolException {
      state = state.copyWith(
        notice: 'Ignored a message from the computer that could not be read.',
        noticeIsError: true,
      );
    }
  }

  void _onClosed(String reason) {
    if (state.link != LinkStatus.connected) return;
    state = state.copyWith(
      link: LinkStatus.disconnected,
      linkMessage: reason,
    );
  }

  /// Runs the app. The computer picks the device when exactly one mobile
  /// device is ready, or uses [deviceId] when given.
  void run({String? deviceId}) => _send(
        CompanionCommandType.appRun,
        deviceId == null
            ? const <String, Object?>{}
            : <String, Object?>{'deviceId': deviceId},
      );

  void hotReload() => _send(CompanionCommandType.appReload);

  void hotRestart() => _send(CompanionCommandType.appRestart);

  void fullRestart() => _send(
        CompanionCommandType.appRestart,
        const <String, Object?>{'mode': 'full'},
      );

  void stopApp() => _send(CompanionCommandType.appStop);

  /// Asks the computer to open DevTools for the running app. It opens there,
  /// not on the phone.
  void openDevTools() => _send(CompanionCommandType.devtoolsOpen);

  void clearLogs() => _send(CompanionCommandType.logsClear);

  /// Leaves the session and forgets its token. The app keeps running on the
  /// computer; getting back in needs a new QR code.
  Future<void> disconnect() async {
    await _closeChannel();
    _forgetGrant();
    state = const SessionView(
      link: LinkStatus.disconnected,
      linkMessage: 'Disconnected.',
    );
  }

  void _send(
    CompanionCommandType type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) {
    final channel = _channel;
    if (channel == null || !state.isLinked) return;
    channel.send(GlideMessage.create(type.wire, payload: payload).encode());
  }

  void _forgetGrant() {
    _grant = null;
    _host = null;
    _port = null;
  }

  Future<void> _closeChannel() async {
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    await channel?.close();
  }
}
