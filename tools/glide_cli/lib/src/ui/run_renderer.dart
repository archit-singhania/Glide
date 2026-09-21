import 'package:glide_protocol/glide_protocol.dart';

/// Turns protocol messages into the lines `glide run` prints.
class RunRenderer {
  const RunRenderer();

  /// The key legend shown once the app is running.
  static const String keyHelp =
      'r hot reload  R hot restart  F full restart  q quit';

  static const Set<String> _shownStates = <String>{
    'preparing',
    'building',
    'installing',
    'launching',
    'stopping',
  };

  /// One line for [message], or null when it should not be printed.
  String? render(GlideMessage message) {
    final p = message.payload;
    switch (message.type) {
      case MessageTypes.sessionStatus:
        final state = p.stringOrNull('state');
        return state != null && _shownStates.contains(state)
            ? '* $state...'
            : null;
      case MessageTypes.buildProgress:
        return '  ${_safe(p.stringOrNull('message') ?? '')}';
      case MessageTypes.buildFailed:
        return 'Build failed: ${_safe(p.stringOrNull('message') ?? 'unknown')}';
      case MessageTypes.appStarted:
        return 'App running on ${p.stringOrNull('deviceId') ?? 'device'} '
            '(${_seconds(p.intOrNull('durationMs'))}).\n$keyHelp';
      case MessageTypes.reloadCompleted:
        return 'Hot reload completed in ${p.intOrNull('durationMs') ?? '?'} ms.';
      case MessageTypes.reloadFailed:
        return 'Hot reload failed: ${_safe(p.stringOrNull('message') ?? '')}';
      case MessageTypes.restartCompleted:
        return '${_mode(p)} restart completed in '
            '${p.intOrNull('durationMs') ?? '?'} ms.';
      case MessageTypes.restartFailed:
        return '${_mode(p)} restart failed: '
            '${_safe(p.stringOrNull('message') ?? '')}';
      case MessageTypes.appStopped:
        return 'App stopped.';
      case MessageTypes.logEntry:
        return _safe(p.stringOrNull('message') ?? '');
      case MessageTypes.commandRejected:
        return 'Cannot do that: ${_safe(p.stringOrNull('reason') ?? '')}';
      default:
        return null;
    }
  }

  String _mode(Map<String, Object?> payload) =>
      payload.stringOrNull('mode') == 'full' ? 'Full' : 'Hot';

  String _seconds(int? milliseconds) => milliseconds == null
      ? 'started'
      : '${(milliseconds / 1000).toStringAsFixed(1)} s';

  /// Output from a device or build tool is untrusted text on the developer's
  /// terminal, so control characters (including escape sequences) are dropped.
  String _safe(String text) => text.replaceAll(_control, '');
}

final RegExp _control = RegExp(
  r'[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]',
);
