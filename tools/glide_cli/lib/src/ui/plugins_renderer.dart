import 'package:glide_project_analyzer/glide_project_analyzer.dart';

/// Formats a [PluginReport] for the terminal.
class PluginsRenderer {
  const PluginsRenderer();

  String render(ProjectInfo project, PluginReport report) {
    final out = StringBuffer()
      ..writeln('Plugins: ${project.name}')
      ..writeln();

    if (!report.resolved) {
      out
        ..writeln(
          'Native plugins are unknown. Run "flutter pub get" so Flutter can '
          'resolve them.',
        )
        ..writeln(
          'Requirements of well-known plugins are still checked below.',
        )
        ..writeln();
    }

    if (report.assessments.isEmpty) {
      out.writeln(
        report.resolved
            ? 'No dependency uses native code or has host configuration '
                'that Glide knows about.'
            : 'No dependency has requirements that Glide knows about.',
      );
    }

    for (final assessment in report.assessments) {
      out.writeln(
        '${assessment.package}  (${assessment.kind.label})  '
        '${_status(assessment)}',
      );
      if (assessment.implementations.isNotEmpty) {
        out.writeln('  via ${assessment.implementations.join(', ')}');
      }
      if (assessment.unsupportedOn.isNotEmpty) {
        final labels = (assessment.unsupportedOn.map((os) => os.label).toList()
              ..sort())
            .join(', ');
        out.writeln('  [missing] no implementation registered for $labels');
      }
      for (final result in assessment.requirements) {
        final requirement = result.requirement;
        final detail = result.detail == null ? '' : ' (${result.detail})';
        out.writeln(
          '  ${_mark(result.state)} ${requirement.platform.label}: '
          '${requirement.summary}$detail',
        );
      }
    }

    if (report.transitiveNativePlugins.isNotEmpty) {
      out
        ..writeln()
        ..writeln(
          'Other native plugins pulled in by your dependencies '
          '(${report.transitiveNativePlugins.length}):',
        );
      for (final plugin in report.transitiveNativePlugins) {
        final labels = (plugin.platforms.map((os) => os.label).toList()..sort())
            .join(', ');
        out.writeln('  ${plugin.name}  ($labels)');
      }
    }

    final dartOnly = report.dartOnlyDependencies;
    if (dartOnly != null) {
      out
        ..writeln()
        ..writeln('$dartOnly other dependencies are Dart-only or unknown.');
    }
    return out.toString();
  }

  String _status(PluginAssessment assessment) => switch (assessment.status) {
        PluginStatus.ready => 'ok',
        PluginStatus.requiresConfiguration => 'needs configuration',
        PluginStatus.unsupported => 'not supported on every target platform',
      };

  String _mark(RequirementState state) => switch (state) {
        RequirementState.satisfied => '[ok]     ',
        RequirementState.missing => '[missing]',
        RequirementState.unverified => '[check]  ',
      };
}
