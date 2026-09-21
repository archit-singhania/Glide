import 'package:glide_log_parser/glide_log_parser.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:test/test.dart';

void main() {
  const parser = DiagnosticParser();

  group('DiagnosticParser', () {
    test('parses a Dart compile error with file, line and column', () {
      final event = parser.parseLine(
        "lib/pages/home.dart:82:5: Error: Undefined name 'userss'.",
      )!;

      expect(event.severity, DiagnosticSeverity.error);
      expect(event.category, DiagnosticCategory.dart);
      expect(event.file, 'lib/pages/home.dart');
      expect(event.line, 82);
      expect(event.column, 5);
      expect(event.message, "Undefined name 'userss'.");
      expect(event.remediation, isNull);
    });

    test('handles a Windows path with a drive letter', () {
      final event = parser.parseLine(
        r'C:\app\lib\main.dart:12:3: Warning: Unused import.',
      )!;

      expect(event.file, r'C:\app\lib\main.dart');
      expect(event.line, 12);
      expect(event.severity, DiagnosticSeverity.warning);
    });

    test('parses a Kotlin compile error as an Android diagnostic', () {
      final event = parser.parseLine(
        'e: file:///app/MainActivity.kt:12:5 Unresolved reference: foo',
      )!;

      expect(event.category, DiagnosticCategory.android);
      expect(event.file, 'app/MainActivity.kt');
      expect(event.line, 12);
      expect(event.message, 'Unresolved reference: foo');
    });

    test('recognises a Gradle failure', () {
      final event = parser.parseLine(
        "Execution failed for task ':app:compileDebugKotlin'.",
      )!;

      expect(event.source, 'Gradle');
      expect(event.category, DiagnosticCategory.android);
    });

    test('recognises a Flutter framework exception banner', () {
      final event = parser.parseLine(
        '══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞═══',
      )!;

      expect(event.category, DiagnosticCategory.flutter);
      expect(event.message, contains('EXCEPTION CAUGHT BY WIDGETS LIBRARY'));
    });

    test('ordinary output is not a diagnostic', () {
      expect(parser.parseLine('flutter: user fetched'), isNull);
      expect(parser.parseLine('Launching lib/main.dart on Pixel...'), isNull);
      expect(parser.parseLine(''), isNull);
    });
  });
}
