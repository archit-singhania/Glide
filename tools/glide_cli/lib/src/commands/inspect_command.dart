import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;

import '../ui/project_renderer.dart';

/// `glide inspect [project-directory]` - shows what Glide detects about a
/// Flutter project. Searches upward from the directory for `pubspec.yaml`.
class InspectCommand extends Command<int> {
  InspectCommand({
    required this.analyzer,
    required this.out,
    required this.workingDirectory,
    this.renderer = const ProjectRenderer(),
  }) {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the result as JSON instead of text.',
    );
  }

  final ProjectAnalyzer analyzer;
  final StringSink out;

  /// Where relative paths and the upward search start.
  final String workingDirectory;
  final ProjectRenderer renderer;

  @override
  String get name => 'inspect';

  @override
  String get description => 'Show what Glide detects about a Flutter project.';

  @override
  String get invocation => 'glide inspect [project-directory]';

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
    if (results['json'] as bool) {
      out.writeln(const JsonEncoder.withIndent('  ').convert(info.toJson()));
    } else {
      out.write(renderer.render(info));
    }
    return 0;
  }
}
