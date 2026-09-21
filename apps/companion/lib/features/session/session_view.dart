import 'package:glide_protocol/glide_protocol.dart';

/// State of the connection to the computer, as the phone sees it.
enum LinkStatus {
  idle,
  pairing,
  connected,
  reconnecting,
  disconnected,
  failed,
}

const int _maxLogs = 300;
const int _maxErrors = 50;

const Set<String> _runnable = <String>{'connected', 'failed', 'disconnected'};
const Set<String> _stoppable = <String>{
  'preparing',
  'building',
  'installing',
  'launching',
  'running',
};

/// Everything the session screen shows. Immutable; [reduceMessage] produces
/// the next value from each message the computer sends.
class SessionView {
  const SessionView({
    this.link = LinkStatus.idle,
    this.linkMessage,
    this.sessionState = 'connected',
    this.deviceId,
    this.appId,
    this.progress,
    this.notice,
    this.noticeIsError = false,
    this.logs = const <LogEntry>[],
    this.errors = const <DiagnosticEvent>[],
  });

  final LinkStatus link;

  /// Why the link failed or ended, when it did.
  final String? linkMessage;

  /// The host's session state name, e.g. `running`.
  final String sessionState;
  final String? deviceId;
  final String? appId;

  /// Latest build progress line while building.
  final String? progress;

  /// Latest one-line result, e.g. "Hot reload completed in 42 ms."
  final String? notice;
  final bool noticeIsError;
  final List<LogEntry> logs;
  final List<DiagnosticEvent> errors;

  bool get isLinked => link == LinkStatus.connected;
  bool get canRun => isLinked && _runnable.contains(sessionState);
  bool get canReload => isLinked && sessionState == 'running';
  bool get canStop => isLinked && _stoppable.contains(sessionState);
  bool get isBusy => isLinked && _stoppable.contains(sessionState);

  SessionView copyWith({
    LinkStatus? link,
    String? linkMessage,
    String? sessionState,
    String? deviceId,
    String? appId,
    bool clearAppId = false,
    String? progress,
    bool clearProgress = false,
    String? notice,
    bool? noticeIsError,
    List<LogEntry>? logs,
    List<DiagnosticEvent>? errors,
  }) =>
      SessionView(
        link: link ?? this.link,
        linkMessage: linkMessage ?? this.linkMessage,
        sessionState: sessionState ?? this.sessionState,
        deviceId: deviceId ?? this.deviceId,
        appId: clearAppId ? null : appId ?? this.appId,
        progress: clearProgress ? null : progress ?? this.progress,
        notice: notice ?? this.notice,
        noticeIsError: noticeIsError ?? this.noticeIsError,
        logs: logs ?? this.logs,
        errors: errors ?? this.errors,
      );
}

/// The view after [message] arrived from the computer.
SessionView reduceMessage(SessionView view, GlideMessage message) {
  final p = message.payload;
  switch (message.type) {
    case MessageTypes.sessionStatus:
      return view.copyWith(
        sessionState: p.stringOrNull('state') ?? view.sessionState,
      );
    case MessageTypes.sessionSnapshot:
      return view.copyWith(
        sessionState: p.stringOrNull('state') ?? view.sessionState,
        deviceId: p.stringOrNull('deviceId'),
        logs: _logsFrom(p['recentLogs']),
      );
    case MessageTypes.buildStarted:
      return view.copyWith(
        deviceId: p.stringOrNull('deviceId'),
        progress: 'Starting build...',
        errors: const <DiagnosticEvent>[],
        notice: 'Building...',
        noticeIsError: false,
      );
    case MessageTypes.buildProgress:
      return view.copyWith(progress: p.stringOrNull('message'));
    case MessageTypes.appStarted:
      return view.copyWith(
        appId: p.stringOrNull('appId'),
        deviceId: p.stringOrNull('deviceId'),
        clearProgress: true,
        notice: 'App is running.',
        noticeIsError: false,
      );
    case MessageTypes.buildFailed:
      return view.copyWith(
        clearProgress: true,
        notice: 'Build failed: ${p.stringOrNull('message') ?? 'unknown'}',
        noticeIsError: true,
      );
    case MessageTypes.appStopped:
      return view.copyWith(
        clearAppId: true,
        clearProgress: true,
        notice: 'App stopped.',
        noticeIsError: false,
      );
    case MessageTypes.reloadCompleted:
      return view.copyWith(
        notice: 'Hot reload completed in ${_ms(p)}.',
        noticeIsError: false,
      );
    case MessageTypes.reloadFailed:
      return view.copyWith(
        notice: 'Hot reload failed: ${p.stringOrNull('message') ?? ''}',
        noticeIsError: true,
      );
    case MessageTypes.restartCompleted:
      return view.copyWith(
        notice: '${_mode(p)} restart completed in ${_ms(p)}.',
        noticeIsError: false,
      );
    case MessageTypes.restartFailed:
      return view.copyWith(
        notice: '${_mode(p)} restart failed: '
            '${p.stringOrNull('message') ?? ''}',
        noticeIsError: true,
      );
    case MessageTypes.logEntry:
      return view.copyWith(
        logs: _capped(<LogEntry>[...view.logs, LogEntry.fromJson(p)], _maxLogs),
      );
    case MessageTypes.logsCleared:
      return view.copyWith(logs: const <LogEntry>[]);
    case MessageTypes.errorReported:
      return view.copyWith(
        errors: _capped(
          <DiagnosticEvent>[...view.errors, DiagnosticEvent.fromJson(p)],
          _maxErrors,
        ),
      );
    case MessageTypes.commandRejected:
      return view.copyWith(
        notice: 'Cannot do that: ${p.stringOrNull('reason') ?? ''}',
        noticeIsError: true,
      );
    default:
      return view;
  }
}

String _ms(Map<String, Object?> payload) =>
    '${payload.intOrNull('durationMs') ?? '?'} ms';

String _mode(Map<String, Object?> payload) =>
    payload.stringOrNull('mode') == 'full' ? 'Full' : 'Hot';

List<T> _capped<T>(List<T> items, int max) =>
    items.length > max ? items.sublist(items.length - max) : items;

List<LogEntry> _logsFrom(Object? raw) {
  if (raw is! List) return const <LogEntry>[];
  return <LogEntry>[
    for (final item in raw)
      if (item is Map) LogEntry.fromJson(Map<String, Object?>.from(item)),
  ];
}
