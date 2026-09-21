import 'dart:async';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

/// An in-memory [AppSession] a test drives by hand, so nothing needs a real
/// Flutter SDK, device or build.
///
/// Test support only: production code never constructs one.
class FakeAppSession implements AppSession {
  FakeAppSession() {
    _started.future.ignore();
  }

  final StreamController<FlutterToolEvent> _events =
      StreamController<FlutterToolEvent>();
  final Completer<void> _started = Completer<void>();
  final Completer<int> _exit = Completer<int>();
  String? _appId;

  /// What the next [hotReload] returns.
  ReloadOutcome reloadOutcome = const ReloadOutcome(
    success: true,
    message: 'ok',
    duration: Duration(milliseconds: 42),
  );

  /// What the next [hotRestart] returns.
  ReloadOutcome restartOutcome = const ReloadOutcome(
    success: true,
    message: 'ok',
    duration: Duration(milliseconds: 120),
  );

  /// When set, [hotReload] and [hotRestart] throw this.
  Object? requestError;

  int reloadCalls = 0;
  int restartCalls = 0;
  bool stopped = false;

  @override
  String? get appId => _appId;

  /// The Dart VM service address this session reports. Null (the default)
  /// means the app is not attachable, so no monitoring starts.
  @override
  String? vmServiceUri;

  @override
  Stream<FlutterToolEvent> get events => _events.stream;

  @override
  Future<void> get started => _started.future;

  @override
  Future<int> get exitCode => _exit.future;

  /// Emits any tool event.
  void emit(FlutterToolEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Emits `app.start` and `app.started`, as a healthy launch would.
  void markStarted({String appId = 'app-1', String deviceId = 'pixel-1'}) {
    _appId = appId;
    emit(AppStarting(appId: appId, deviceId: deviceId, mode: 'debug'));
    emit(AppStarted(appId));
    if (!_started.isCompleted) _started.complete();
  }

  /// Ends the process with [code], failing [started] if it never started.
  void crash(int code) {
    if (!_started.isCompleted) {
      _started.completeError(ToolProcessExited(code));
    }
    emit(ToolExited(code));
    _close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Future<ReloadOutcome> hotReload() async {
    reloadCalls++;
    final error = requestError;
    if (error != null) throw error;
    return reloadOutcome;
  }

  @override
  Future<ReloadOutcome> hotRestart() async {
    restartCalls++;
    final error = requestError;
    if (error != null) throw error;
    return restartOutcome;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    _close();
    if (!_exit.isCompleted) _exit.complete(0);
  }

  void _close() {
    // Not awaited: a single-subscription controller's close() only completes
    // once a listener has consumed it, and there may be none.
    if (!_events.isClosed) unawaited(_events.close());
  }
}
