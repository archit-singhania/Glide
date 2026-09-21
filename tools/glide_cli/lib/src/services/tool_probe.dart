import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

/// The outcome of looking for something on this machine.
class Detection<T> {
  const Detection.found(this.value) : problem = null;
  const Detection.missing(this.problem) : value = null;

  /// Set when the thing was found.
  final T? value;

  /// Human readable reason, set when it was not found.
  final String? problem;
}

/// The result of running a short diagnostic command.
class ProbeResult {
  const ProbeResult.success(this.output) : failure = null;
  const ProbeResult.failure(this.failure) : output = '';

  /// Combined stdout and stderr (some tools, such as `java -version`, print
  /// their version to stderr).
  final String output;

  /// Why the command could not be used; null on success.
  final String? failure;

  bool get succeeded => failure == null;
}

/// Runs short diagnostic commands and reports failures as data.
///
/// Every failure (tool missing, non-zero exit, timeout) is returned with its
/// reason instead of being swallowed.
class ToolProbe {
  const ToolProbe(this._runner);

  final ToolRunner _runner;

  Future<ProbeResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final result = await _runner.run(
        executable,
        arguments,
        timeout: timeout,
      );
      final output = '${result.stdout}\n${result.stderr}'.trim();
      if (!result.succeeded) {
        return ProbeResult.failure(
          firstLine(output) ?? 'exited with code ${result.exitCode}',
        );
      }
      return ProbeResult.success(output);
    } on ToolException catch (error) {
      return ProbeResult.failure(error.message);
    }
  }
}

/// The first non-blank line of [text], or null.
String? firstLine(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}
