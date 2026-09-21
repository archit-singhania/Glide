import 'envelope.dart';
import 'foundation.dart';

/// The complete allowlist of commands a companion may send.
///
/// There is deliberately no command that carries a shell string or a path.
enum CompanionCommandType {
  appRun('app.run'),
  appStop('app.stop'),
  appReload('app.reload'),
  appRestart('app.restart'),
  logsClear('logs.clear'),
  sessionDisconnect('session.disconnect'),
  diagnosticsRequest('diagnostics.request');

  const CompanionCommandType(this.wire);

  final String wire;

  static CompanionCommandType? fromWire(String value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// `hot` keeps the platform app alive; `full` rebuilds and relaunches it.
enum RestartMode { hot, full }

enum CommandOrigin { companion, local }

/// Device ids are passed to external tools, so they are validated strictly.
final RegExp deviceIdPattern = RegExp(r'^[A-Za-z0-9._:@\-]{1,128}$');

/// A validated, allowlisted request to control the session.
class CompanionCommand {
  const CompanionCommand({
    required this.type,
    this.payload = const <String, Object?>{},
    this.origin = CommandOrigin.local,
    this.requestId,
  });

  /// Converts a wire message, rejecting anything outside the allowlist.
  factory CompanionCommand.fromMessage(
    GlideMessage message, {
    CommandOrigin origin = CommandOrigin.companion,
  }) {
    final type = CompanionCommandType.fromWire(message.type);
    if (type == null) {
      throw const ProtocolException('Unknown or disallowed command.');
    }
    final command = CompanionCommand(
      type: type,
      payload: message.payload,
      origin: origin,
      requestId: message.id,
    );
    command.validate();
    return command;
  }

  final CompanionCommandType type;
  final Map<String, Object?> payload;
  final CommandOrigin origin;
  final String? requestId;

  /// Optional target device for `app.run`.
  String? get deviceId => payload.stringOrNull('deviceId');

  /// Restart flavour for `app.restart`; defaults to a hot restart.
  RestartMode get restartMode => payload.stringOrNull('mode') == 'full'
      ? RestartMode.full
      : RestartMode.hot;

  /// Throws [ProtocolException] if the payload contains unsafe values.
  void validate() {
    final device = payload['deviceId'];
    if (device != null) {
      if (device is! String || !deviceIdPattern.hasMatch(device)) {
        throw const ProtocolException('Invalid device id.');
      }
    }
    final mode = payload['mode'];
    if (mode != null && mode != 'hot' && mode != 'full') {
      throw const ProtocolException('Invalid restart mode.');
    }
  }

  @override
  String toString() => 'CompanionCommand(${type.wire})';
}

/// Sink for host-to-companion events.
abstract interface class EventPublisher {
  void publish(GlideMessage message);
}

/// Source of validated commands.
abstract interface class CommandSource {
  Stream<CompanionCommand> get commands;
}
