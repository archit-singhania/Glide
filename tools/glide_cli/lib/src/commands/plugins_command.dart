import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;

import '../ui/plugins_renderer.dart';

/// `glide plugins [project-directory]` - classifies the project's plugins and
/// checks that the host project has what well-known plugins need.
///
/// Read-only: it reports missing permissions and configuration but never
/// edits `AndroidManifest.xml` or `Info.plist`.
class PluginsCommand extends Command<int> {
  PluginsCommand({
    required this.analyzer,
    required this.pluginAnalyzer,
    required this.out,
    required this.workingDirectory,
    this.renderer = const PluginsRenderer(),
  }) {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the result as JSON instead of text.',
      )
      ..addFlag(
        'strict',
        negatable: false,
        help: 'Exit with code 1 when a plugin needs configuration or is not '
            'supported on a platform the project targets.',
      );
  }

  final ProjectAnalyzer analyzer;
  final PluginAnalyzer pluginAnalyzer;
  final StringSink out;
  final String workingDirectory;
  final PluginsRenderer renderer;

  @override
  String get name => 'plugins';

  @override
  String get description =>
      'Classify native plugins and check the host project configuration.';

  @override
  String get invocation => 'glide plugins [project-directory]';

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.length > 1) {
      usageException('Expected at most one project directory.');
    }
    final start = results.rest.isEmpty
        ? workingDirectory
        : p.join(workingDirectory, results.rest.single);
    final root = FlutterProjectAnalyzer.findProjectRoot(start);
    if (root == null) {
      throw ProjectException(
        'No pubspec.yaml found in "$start" or any parent directory.',
      );
    }

    final info = await analyzer.analyze(root);
    final report = pluginAnalyzer.analyze(info);
    if (results['json'] as bool) {
      out.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    } else {
      out.write(renderer.render(info, report));
    }
    return results['strict'] as bool && report.hasProblems ? 1 : 0;
  }
}
