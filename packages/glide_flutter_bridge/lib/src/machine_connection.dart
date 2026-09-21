import 'dart:async';
import 'dart:convert';

import 'machine_protocol.dart';
import 'models.dart';
import 'process.dart';

/// A JSON-RPC style connection to `flutter daemon` or `flutter run --machine`.
///
/// Subscribe to [events] *before* calling [start] to guarantee that no event
/// is missed.
class MachineConnection {
  MachineConnection({
    required this.launcher,
    required this.executable,
    required this.arguments,
    this.workingDirectory,
    this.requestTimeout = const Duration(seconds: 60),
  });

  final ProcessLauncher launcher;
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Duration requestTimeout;

  final StreamController<FlutterToolEvent> _events =
      StreamController<FlutterToolEvent>.broadcast();
  final RequestRegistry _registry = RequestRegistry();
  final Completer<int> _exit = Completer<int>();
  ProcessHandle? _process;

  Stream<FlutterToolEvent> get events => _events.stream;

  /// Completes with the process exit code.
  Future<int> get exitCode => _exit.future;

  bool get isRunning => _process != null && !_exit.isCompleted;

  Future<void> start() async {
    if (_process != null) {
      throw StateError('MachineConnection.start() was already called.');
    }
    final process = await launcher.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
    _process = process;

    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    process.stdoutLines.listen(
      _onStdout,
      onDone: stdoutDone.complete,
      onError: (Object error, StackTrace stack) {},
    );
    process.stderrLines.listen(
      (line) {
        if (line.trim().isNotEmpty) _emit(ToolLog(line, isError: true));
      },
      onDone: stderrDone.complete,
      onError: (Object error, StackTrace stack) {},
    );
    unawaited(
      process.exitCode.then((code) async {
        // Let the pipes drain so trailing output is not lost.
        await Future.wait<void>(<Future<void>>[
          stdoutDone.future,
          stderrDone.future,
        ]).timeout(
          const Duration(seconds: 2),
          onTimeout: () => <void>[],
        );
        _onExit(code);
      }),
    );
  }

  /// Sends a request and waits for its response.
  Future<Object?> request(
    String method, [
    Map<String, Object?> params = const <String, Object?>{},
  ]) async {
    final process = _process;
    if (process == null || _exit.isCompleted) {
      throw ToolProcessExited(-1);
    }
    final pending = _registry.register(method, requestTimeout);
    process.writeLine(
      jsonEncode(<Object?>[
        <String, Object?>{
          'method': method,
          'id': pending.id,
          'params': params,
        },
      ]),
    );
    return pending.future;
  }

  /// Forcefully terminates the process.
  void kill() {
    _process?.kill();
  }

  void _onStdout(String line) {
    for (final message in MachineMessageParser.parseLine(line)) {
      switch (message) {
        case final MachineEvent event:
          _emit(FlutterToolEvent.fromMachine(event));
        case final MachineResponse response:
          _registry.complete(response);
        case MachineText(:final text):
          if (text.trim().isNotEmpty) {
            _emit(ToolLog(text, isError: false));
          }
      }
    }
  }

  void _onExit(int code) {
    if (_exit.isCompleted) return;
    _emit(ToolExited(code));
    _registry.failAll(ToolProcessExited(code));
    _exit.complete(code);
    unawaited(_events.close());
  }

  void _emit(FlutterToolEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
