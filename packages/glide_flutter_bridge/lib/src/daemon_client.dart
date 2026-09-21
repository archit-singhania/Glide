import 'dart:async';

import 'machine_connection.dart';
import 'models.dart';
import 'process.dart';

/// Supervises `flutter daemon`: device discovery events and device queries.
///
/// If the daemon crashes it is restarted with linear backoff, up to
/// [maxRestarts] times, and every incident is surfaced as a [ToolLog].
class FlutterDaemonClient {
  FlutterDaemonClient({
    required this.launcher,
    required this.flutterExecutable,
    this.maxRestarts = 3,
    this.restartBackoff = const Duration(milliseconds: 500),
  });

  final ProcessLauncher launcher;
  final String flutterExecutable;
  final int maxRestarts;
  final Duration restartBackoff;

  final StreamController<FlutterToolEvent> _events =
      StreamController<FlutterToolEvent>.broadcast();
  MachineConnection? _connection;
  StreamSubscription<FlutterToolEvent>? _subscription;
  bool _shuttingDown = false;
  int _restarts = 0;

  Stream<FlutterToolEvent> get events => _events.stream;

  bool get isRunning => _connection?.isRunning ?? false;

  /// Starts the daemon and turns on device polling.
  Future<void> start() => _launch();

  Future<void> _launch() async {
    final connection = MachineConnection(
      launcher: launcher,
      executable: flutterExecutable,
      arguments: const <String>['daemon'],
    );
    _connection = connection;
    _subscription = connection.events.listen(_onEvent);
    await connection.start();
    await connection.request('device.enable');
  }

  void _onEvent(FlutterToolEvent event) {
    if (!_events.isClosed) _events.add(event);
    if (event is ToolExited && !_shuttingDown) {
      unawaited(_recover(event.exitCode));
    }
  }

  Future<void> _recover(int exitCode) async {
    if (_restarts >= maxRestarts) {
      _log(
        'Flutter daemon exited (code $exitCode); giving up after '
        '$maxRestarts restarts.',
        isError: true,
      );
      return;
    }
    _restarts++;
    _log(
      'Flutter daemon exited (code $exitCode); restarting '
      '($_restarts/$maxRestarts).',
      isError: false,
    );
    await Future<void>.delayed(restartBackoff * _restarts);
    if (_shuttingDown) return;
    await _subscription?.cancel();
    try {
      await _launch();
    } on ToolException catch (error) {
      _log(
        'Could not restart the Flutter daemon: ${error.message}',
        isError: true,
      );
    }
  }

  void _log(String message, {required bool isError}) {
    if (!_events.isClosed) _events.add(ToolLog(message, isError: isError));
  }

  /// Lists devices currently visible to the daemon.
  Future<List<FlutterDevice>> getDevices() async {
    final result = await _requireConnection().request('device.getDevices');
    if (result is! List) return const <FlutterDevice>[];
    final devices = <FlutterDevice>[];
    for (final item in result) {
      if (item is! Map) continue;
      final device = FlutterDevice.tryFromJson(Map<String, Object?>.from(item));
      if (device != null) devices.add(device);
    }
    return devices;
  }

  MachineConnection _requireConnection() {
    final connection = _connection;
    if (connection == null || !connection.isRunning) {
      throw ToolProcessExited(-1);
    }
    return connection;
  }

  /// Asks the daemon to exit, killing it if it does not comply.
  Future<void> shutdown() async {
    _shuttingDown = true;
    final connection = _connection;
    if (connection != null && connection.isRunning) {
      try {
        await connection
            .request('daemon.shutdown')
            .timeout(const Duration(seconds: 3));
      } on Object catch (error) {
        _log(
          'Daemon did not acknowledge shutdown ($error); killing it.',
          isError: false,
        );
        connection.kill();
      }
    }
    await _subscription?.cancel();
    await _events.close();
  }
}
