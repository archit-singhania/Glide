import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

/// A [ToolRunner] that answers from a table instead of starting processes.
///
/// Register answers with [on] using the full command line, for example
/// `'/sdk/bin/flutter --version --machine'`. Any command that was not
/// registered behaves like a tool that is not installed.
class FakeToolRunner implements ToolRunner {
  final Map<String, CommandResult> results = <String, CommandResult>{};

  /// Every command line that was requested, in order.
  final List<String> calls = <String>[];

  void on(
    String commandLine, {
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    results[commandLine] = CommandResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
    );
  }

  @override
  Future<CommandResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final key = <String>[executable, ...arguments].join(' ');
    calls.add(key);
    final result = results[key];
    if (result == null) throw ToolNotFoundException(executable);
    return result;
  }
}
