import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';

import 'commands/devices_command.dart';
import 'commands/doctor_command.dart';
import 'commands/inspect_command.dart';
import 'commands/plugins_command.dart';
import 'commands/run_command.dart';
import 'commands/start_command.dart';
import 'services/device_session.dart';
import 'services/environment_service.dart';
import 'ui/devices_renderer.dart';
import 'ui/doctor_renderer.dart';
import 'version.dart';

/// The top-level `glide` command.
class GlideCommandRunner extends CommandRunner<int> {
  GlideCommandRunner({
    required this.out,
    required this.err,
    EnvironmentInspector? environment,
    DoctorRenderer renderer = const DoctorRenderer(),
    ProjectAnalyzer? analyzer,
    PluginAnalyzer pluginAnalyzer = const PluginAnalyzer(),
    String? workingDirectory,
    DeviceSessionOpener? deviceSessionOpener,
    DevicesRenderer devicesRenderer = const DevicesRenderer(),
    StartEnvironment startEnvironment = const StartEnvironment(),
    RunEnvironment runEnvironment = const RunEnvironment(),
  }) : super('glide', 'Glide - Flutter development, without friction.') {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the Glide version and exit.',
    );
    final projectAnalyzer = analyzer ?? const FlutterProjectAnalyzer();
    final directory = workingDirectory ?? Directory.current.path;
    addCommand(
      DoctorCommand(
        inspector: environment ?? EnvironmentService.system(),
        out: out,
        renderer: renderer,
      ),
    );
    addCommand(
      InspectCommand(
        analyzer: projectAnalyzer,
        out: out,
        workingDirectory: directory,
      ),
    );
    addCommand(
      PluginsCommand(
        analyzer: projectAnalyzer,
        pluginAnalyzer: pluginAnalyzer,
        out: out,
        workingDirectory: directory,
      ),
    );
    addCommand(
      DevicesCommand(
        openSession: deviceSessionOpener ?? openLiveDeviceSession,
        out: out,
        renderer: devicesRenderer,
      ),
    );
    addCommand(
      StartCommand(
        analyzer: projectAnalyzer,
        out: out,
        err: err,
        workingDirectory: directory,
        environment: startEnvironment,
      ),
    );
    addCommand(
      RunCommand(
        analyzer: projectAnalyzer,
        out: out,
        err: err,
        workingDirectory: directory,
        environment: runEnvironment,
      ),
    );
  }

  /// Where normal output goes.
  final StringSink out;

  /// Where errors go.
  final StringSink err;

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool) {
      out.writeln('glide $glideVersion');
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}
