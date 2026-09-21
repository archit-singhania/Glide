import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:glide_protocol/glide_protocol.dart';

import 'commands/run_command.dart';
import 'commands/start_command.dart';
import 'glide_command_runner.dart';
import 'services/device_session.dart';
import 'services/environment_service.dart';
import 'ui/devices_renderer.dart';
import 'ui/doctor_renderer.dart';
import 'ui/qr_renderer.dart';

/// Runs the `glide` CLI and returns its exit code.
///
/// 0 success, 1 a Glide failure or failed check, 64 bad usage.
Future<int> runGlide(
  List<String> arguments, {
  StringSink? out,
  StringSink? err,
  EnvironmentInspector? environment,
  DoctorRenderer? renderer,
  ProjectAnalyzer? analyzer,
  String? workingDirectory,
  DeviceSessionOpener? deviceSessionOpener,
  DevicesRenderer? devicesRenderer,
  StartEnvironment? startEnvironment,
  RunEnvironment? runEnvironment,
}) async {
  final StringSink output = out ?? stdout;
  final StringSink errors = err ?? stderr;
  final runner = GlideCommandRunner(
    out: output,
    err: errors,
    environment: environment,
    renderer: renderer ?? _terminalRenderer(),
    analyzer: analyzer,
    workingDirectory: workingDirectory,
    deviceSessionOpener: deviceSessionOpener,
    devicesRenderer: devicesRenderer ?? const DevicesRenderer(),
    startEnvironment: startEnvironment ?? StartEnvironment(qr: _terminalQr()),
    runEnvironment: runEnvironment ?? const RunEnvironment(),
  );
  try {
    return await runner.run(arguments) ?? 0;
  } on UsageException catch (error) {
    errors.writeln(error);
    return 64;
  } on GlideException catch (error) {
    errors.writeln('glide: ${error.message}');
    return 1;
  }
}

/// True only when stdout is an ANSI-capable terminal that has not opted out.
bool _supportsAnsi() =>
    stdout.hasTerminal &&
    stdout.supportsAnsiEscapes &&
    !Platform.environment.containsKey('NO_COLOR');

/// Colour and Unicode only when stdout is an ANSI-capable terminal.
DoctorRenderer _terminalRenderer() {
  final ansi = _supportsAnsi();
  return DoctorRenderer(color: ansi, unicode: !Platform.isWindows || ansi);
}

/// The QR code needs colour for reliable polarity; see [QrRenderer].
QrRenderer _terminalQr() {
  final ansi = _supportsAnsi();
  return QrRenderer(color: ansi, unicode: !Platform.isWindows || ansi);
}
