import 'foundation.dart';

enum DiagnosticSeverity { info, warning, error, fatal }

enum DiagnosticCategory {
  dart,
  flutter,
  build,
  android,
  ios,
  plugin,
  network,
  glide,
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  if (name == null) return fallback;
  return values.asNameMap()[name] ?? fallback;
}

/// A structured, user-facing problem report.
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.severity,
    required this.category,
    required this.source,
    required this.message,
    this.file,
    this.line,
    this.column,
    this.stackTrace,
    this.remediation,
  });

  factory DiagnosticEvent.fromJson(Map<String, Object?> json) =>
      DiagnosticEvent(
        severity: _enumByName(
          DiagnosticSeverity.values,
          json.stringOrNull('severity'),
          DiagnosticSeverity.error,
        ),
        category: _enumByName(
          DiagnosticCategory.values,
          json.stringOrNull('category'),
          DiagnosticCategory.glide,
        ),
        source: json.stringOrNull('source') ?? 'unknown',
        message: json.stringOrNull('message') ?? '',
        file: json.stringOrNull('file'),
        line: json.intOrNull('line'),
        column: json.intOrNull('column'),
        stackTrace: json.stringOrNull('stackTrace'),
        remediation: json.stringOrNull('remediation'),
      );

  final DiagnosticSeverity severity;
  final DiagnosticCategory category;

  /// Which tool produced the report (for example "Dart compiler", "Gradle").
  final String source;
  final String message;
  final String? file;
  final int? line;
  final int? column;
  final String? stackTrace;

  /// Only set when the cause is known; never fabricated.
  final String? remediation;

  Map<String, Object?> toJson() => <String, Object?>{
        'severity': severity.name,
        'category': category.name,
        'source': source,
        'message': message,
        if (file != null) 'file': file,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
        if (stackTrace != null) 'stackTrace': stackTrace,
        if (remediation != null) 'remediation': remediation,
      };

  @override
  String toString() => 'DiagnosticEvent(${category.name}: $message)';
}

enum LogLevel { trace, debug, info, warning, error }

/// One line of application or tool output.
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
  });

  factory LogEntry.fromJson(Map<String, Object?> json) => LogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          json.intOrNull('timestamp') ?? 0,
        ),
        level: _enumByName(
          LogLevel.values,
          json.stringOrNull('level'),
          LogLevel.info,
        ),
        source: json.stringOrNull('source') ?? 'app',
        message: json.stringOrNull('message') ?? '',
      );

  final DateTime timestamp;
  final LogLevel level;
  final String source;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp': timestamp.millisecondsSinceEpoch,
        'level': level.name,
        'source': source,
        'message': message,
      };
}
