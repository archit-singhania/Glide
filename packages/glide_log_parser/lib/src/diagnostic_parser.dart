import 'package:glide_protocol/glide_protocol.dart';

/// Recognises compiler and build errors in single lines of tool output.
///
/// Deliberately conservative: a line that is not clearly a diagnostic yields
/// null and stays an ordinary log line. It never guesses a remediation.
class DiagnosticParser {
  const DiagnosticParser();

  // lib/main.dart:82:5: Error: Undefined name 'userss'.
  // C:\app\lib\main.dart:12:3: Warning: ...
  static final RegExp _dart = RegExp(
    r'^(.+?):(\d+):(\d+): (Error|Warning): (.*)$',
  );

  // e: file:///C:/app/MainActivity.kt:12:5 Unresolved reference: foo
  static final RegExp _kotlin =
      RegExp(r'^e: (?:file:///)?(.+?):(\d+):(\d+):? (.*)$');

  /// The diagnostic in [line], or null when it is not one.
  DiagnosticEvent? parseLine(String line) {
    final text = line.trimRight();

    final dart = _dart.firstMatch(text);
    if (dart != null) {
      final isError = dart.group(4) == 'Error';
      return DiagnosticEvent(
        severity:
            isError ? DiagnosticSeverity.error : DiagnosticSeverity.warning,
        category: DiagnosticCategory.dart,
        source: 'Dart compiler',
        message: dart.group(5)!,
        file: dart.group(1),
        line: int.parse(dart.group(2)!),
        column: int.parse(dart.group(3)!),
      );
    }

    final kotlin = _kotlin.firstMatch(text);
    if (kotlin != null) {
      return DiagnosticEvent(
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.android,
        source: 'Kotlin compiler',
        message: kotlin.group(4)!,
        file: kotlin.group(1),
        line: int.parse(kotlin.group(2)!),
        column: int.parse(kotlin.group(3)!),
      );
    }

    if (text.startsWith('FAILURE: Build failed') ||
        text.startsWith('Execution failed for task')) {
      return DiagnosticEvent(
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.android,
        source: 'Gradle',
        message: text,
      );
    }

    if (text.contains('EXCEPTION CAUGHT BY')) {
      return DiagnosticEvent(
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.flutter,
        source: 'Flutter framework',
        message: text.replaceAll(RegExp(r'[═╡╞\s]+'), ' ').trim(),
      );
    }
    return null;
  }
}
