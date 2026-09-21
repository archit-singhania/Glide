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
const int _maxNetwork = 100;

const Set<String> _runnable = <String>{'connected', 'failed', 'disconnected'};
const Set<String> _stoppable = <String>{
  'preparing',
  'building',
  'installing',
  'launching',
  'running',
};

/// One file change that hot reload cannot apply, as reported by the host.
class RestartReason {
  const RestartReason({required this.path, required this.reason});

  final String path;
  final String reason;
}

/// The latest performance window reported by the running app.
class PerformanceView {
  const PerformanceView({
    required this.fps,
    required this.frameTimeMs,
    required this.jankyFrames,
    this.heapUsageBytes,
  });

  factory PerformanceView.fromJson(Map<String, Object?> json) =>
      PerformanceView(
        fps: _number(json['fps']),
        frameTimeMs: _number(json['frameTimeMs']),
        jankyFrames: json.intOrNull('jankyFrameCount') ?? 0,
        heapUsageBytes: json.intOrNull('heapUsageBytes'),
      );

  final double fps;
  final double frameTimeMs;
  final int jankyFrames;

  /// Null when the computer had no memory reading for that window.
  final int? heapUsageBytes;

  String get memoryLabel {
    final bytes = heapUsageBytes;
    return bytes == null
        ? 'n/a'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

/// One completed HTTP request the app made. The address arrives already
/// stripped of its query string, user info and fragment by the computer.
class NetworkCall {
  const NetworkCall({
    required this.id,
    required this.method,
    required this.url,
    this.statusCode,
    this.durationMs,
    this.sizeBytes,
  });

  factory NetworkCall.fromJson(Map<String, Object?> json) => NetworkCall(
        id: json.stringOrNull('id') ?? '',
        method: json.stringOrNull('method') ?? '?',
        url: json.stringOrNull('url') ?? '?',
        statusCode: json.intOrNull('statusCode'),
        durationMs: json.intOrNull('durationMs'),
        sizeBytes: json.intOrNull('sizeBytes'),
      );

  final String id;
  final String method;
  final String url;
  final int? statusCode;
  final int? durationMs;
  final int? sizeBytes;

  bool get failed => statusCode == null;

  /// For example `200 - 342 ms - 18.3 KB`, or `failed - 12 ms`.
  String get summary {
    final parts = <String>[
      failed ? 'failed' : '$statusCode',
      if (durationMs != null) '$durationMs ms',
      if (sizeBytes != null) _size(sizeBytes!),
    ];
    return parts.join(' - ');
  }
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

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
    this.restartReasons = const <RestartReason>[],
    this.performance,
    this.network = const <NetworkCall>[],
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

  /// Changes made since the app was built that only a full restart can apply.
  final List<RestartReason> restartReasons;

  /// Latest FPS, frame time and memory; null until the app reports one.
  final PerformanceView? performance;

  /// Recent HTTP requests the app made, oldest first.
  final List<NetworkCall> network;

  bool get needsFullRestart => restartReasons.isNotEmpty;

  /// DevTools opens on the computer, so it needs a running app.
  bool get canOpenDevTools => canReload;

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
    List<RestartReason>? restartReasons,
    PerformanceView? performance,
    bool clearPerformance = false,
    List<NetworkCall>? network,
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
        restartReasons: restartReasons ?? this.restartReasons,
        performance: clearPerformance ? null : performance ?? this.performance,
        network: network ?? this.network,
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
        restartReasons: _reasonsFrom(p['reasons']),
        clearPerformance: p['performance'] is! Map,
        performance: p['performance'] is Map
            ? PerformanceView.fromJson(
                Map<String, Object?>.from(p['performance']! as Map),
              )
            : null,
      );
    case MessageTypes.buildStarted:
      return view.copyWith(
        deviceId: p.stringOrNull('deviceId'),
        progress: 'Starting build...',
        errors: const <DiagnosticEvent>[],
        restartReasons: const <RestartReason>[],
        clearPerformance: true,
        network: const <NetworkCall>[],
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
        restartReasons: const <RestartReason>[],
        notice: 'Build failed: ${p.stringOrNull('message') ?? 'unknown'}',
        noticeIsError: true,
      );
    case MessageTypes.appStopped:
      return view.copyWith(
        clearAppId: true,
        restartReasons: const <RestartReason>[],
        clearPerformance: true,
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
        // A full restart rebuilds the platform app, so nothing is pending.
        restartReasons:
            p.stringOrNull('mode') == 'full' ? const <RestartReason>[] : null,
      );
    case MessageTypes.restartRequired:
      return view.copyWith(restartReasons: _reasonsFrom(p['reasons']));
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
    case MessageTypes.performanceSample:
      return view.copyWith(performance: PerformanceView.fromJson(p));
    case MessageTypes.networkResponse:
      return view.copyWith(
        network: _capped(
          <NetworkCall>[...view.network, NetworkCall.fromJson(p)],
          _maxNetwork,
        ),
      );
    case MessageTypes.devtoolsOpened:
      return view.copyWith(
        notice: 'DevTools opened on your computer.',
        noticeIsError: false,
      );
    case MessageTypes.devtoolsFailed:
      return view.copyWith(
        notice: 'DevTools failed: ${p.stringOrNull('message') ?? ''}',
        noticeIsError: true,
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

List<RestartReason> _reasonsFrom(Object? raw) {
  if (raw is! List) return const <RestartReason>[];
  return <RestartReason>[
    for (final item in raw)
      if (item is Map)
        RestartReason(
          path: '${item['path'] ?? '?'}',
          reason: '${item['reason'] ?? ''}',
        ),
  ];
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

List<LogEntry> _logsFrom(Object? raw) {
  if (raw is! List) return const <LogEntry>[];
  return <LogEntry>[
    for (final item in raw)
      if (item is Map) LogEntry.fromJson(Map<String, Object?>.from(item)),
  ];
}
