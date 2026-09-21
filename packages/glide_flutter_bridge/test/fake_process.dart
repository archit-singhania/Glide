import 'dart:async';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

/// An in-memory [ProcessHandle] the test controls directly: emit lines,
/// inspect what was written to stdin, and finish with any exit code.
class FakeProcessHandle implements ProcessHandle {
  final StreamController<String> _stdout = StreamController<String>.broadcast();
  final StreamController<String> _stderr = StreamController<String>.broadcast();
  final Completer<int> _exit = Completer<int>();

  /// Every line written via [writeLine], in order.
  final List<String> written = <String>[];

  bool killed = false;

  @override
  Stream<String> get stdoutLines => _stdout.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void writeLine(String line) => written.add(line);

  @override
  bool kill() {
    killed = true;
    exit(-9);
    return true;
  }

  /// Emits one line of stdout, as if the process printed it.
  void emitStdout(String line) {
    if (!_stdout.isClosed) _stdout.add(line);
  }

  /// Emits one line of stderr.
  void emitStderr(String line) {
    if (!_stderr.isClosed) _stderr.add(line);
  }

  /// Emits an already-JSON-encoded machine protocol frame, i.e. a line
  /// starting with `[`.
  void emitFrame(String jsonArrayLine) => emitStdout(jsonArrayLine);

  /// Ends the process with [code]. Safe to call more than once.
  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    scheduleMicrotask(() {
      if (!_stdout.isClosed) unawaited(_stdout.close());
      if (!_stderr.isClosed) unawaited(_stderr.close());
    });
  }
}

/// One recorded call to [FakeProcessLauncher.start].
class LaunchCall {
  const LaunchCall(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

/// A [ProcessLauncher] that hands out [FakeProcessHandle]s instead of
/// starting real processes.
///
/// By default every [start] call gets a fresh handle appended to [handles].
/// Set [onStart] to control the handle per call, for example to make the
/// Nth launch behave differently (simulating a daemon crash and restart).
class FakeProcessLauncher implements ProcessLauncher {
  final List<LaunchCall> calls = <LaunchCall>[];
  final List<FakeProcessHandle> handles = <FakeProcessHandle>[];

  FakeProcessHandle Function(LaunchCall call)? onStart;

  @override
  Future<ProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final call = LaunchCall(executable, arguments, workingDirectory);
    calls.add(call);
    final handle = onStart?.call(call) ?? FakeProcessHandle();
    handles.add(handle);
    return handle;
  }
}
