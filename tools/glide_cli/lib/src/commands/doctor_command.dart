import 'dart:convert';

import 'package:args/command_runner.dart';

import '../services/environment_service.dart';
import '../ui/doctor_renderer.dart';

/// `glide doctor` - checks the machine can run Glide sessions.
///
/// Exits with 0 unless a check is an error; warnings do not fail the command.
class DoctorCommand extends Command<int> {
  DoctorCommand({
    required this.inspector,
    required this.out,
    required this.renderer,
  }) {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the report as JSON instead of text.',
      )
      ..addOption(
        'flutter-sdk',
        valueHelp: 'path',
        help: 'Flutter SDK directory or flutter executable to use.',
      );
  }

  final EnvironmentInspector inspector;
  final StringSink out;
  final DoctorRenderer renderer;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check that Flutter, the Android toolchain and the network are ready.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final report = await inspector.inspect(
      flutterSdkPath: results['flutter-sdk'] as String?,
    );
    if (results['json'] as bool) {
      out.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      out.write(renderer.render(report));
    }
    return report.hasErrors ? 1 : 0;
  }
}
