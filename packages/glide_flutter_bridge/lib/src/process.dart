import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glide_protocol/glide_protocol.dart';

/// Base type for failures talking to the Flutter tool.
class ToolException extends GlideException {
  const ToolException(super.message, {super.cause});
}

class ToolNotFoundException extends ToolException {
  ToolNotFoundException(String executable, {super.cause})
      : super(
          'Could not launch "$executable". Is it installed and on PATH?',
        );
}

class ToolRequestException extends ToolException {
  ToolRequestException(String method, Object? error)
      : super('Request "$method" failed: $error');
}

class ToolRequestTimeout extends ToolException {
  ToolRequestTimeout(String method, Duration timeout)
      : super('Request "$method" timed out after ${timeout.inSeconds}s.');
}

class ToolProcessExited extends ToolException {
  ToolProcessExited(this.exitCode)
      : super('The Flutter tool exited unexpectedly (code $exitCode).');

  final int exitCode;
}

/// A running child process, reduced to what Glide needs.
abstract interface class ProcessHandle {
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  Future<int> get exitCode;
  void writeLine(String line);
  bool kill();
}

/// Starts long-running processes. UI code never touches this directly.
abstract interface class ProcessLauncher {
  Future<ProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

/// Runs short-lived commands to completion.
abstract interface class ToolRunner {
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout,
  });
}

/// The real implementation backed by `dart:io`.
///
/// Arguments must only ever come from trusted, validated sources: on Windows
/// `flutter.bat` requires a shell, so callers validate device ids first.
class SystemProcessLauncher implements ProcessLauncher, ToolRunner {
  const SystemProcessLauncher();

  @override
  Future<ProcessHandle> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: Platform.isWindows,
      );
      return _SystemProcessHandle(process);
    } on ProcessException catch (error) {
      throw ToolNotFoundException(executable, cause: error);
    }
  }

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: Platform.isWindows,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      return CommandResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on ProcessException catch (error) {
      throw ToolNotFoundException(executable, cause: error);
    } on TimeoutException catch (error) {
      throw ToolException(
        '"$executable ${arguments.join(' ')}" timed out '
        'after ${timeout.inSeconds}s.',
        cause: error,
      );
    }
  }
}

class _SystemProcessHandle implements ProcessHandle {
  _SystemProcessHandle(Process process)
      : _process = process,
        stdoutLines = _lines(process.stdout),
        stderrLines = _lines(process.stderr);

  final Process _process;

  @override
  final Stream<String> stdoutLines;

  @override
  final Stream<String> stderrLines;

  static Stream<String> _lines(Stream<List<int>> stream) => stream
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter());

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void writeLine(String line) {
    _process.stdin.writeln(line);
  }

  @override
  bool kill() => _process.kill();
}
