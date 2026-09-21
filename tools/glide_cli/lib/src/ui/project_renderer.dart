import 'package:glide_project_analyzer/glide_project_analyzer.dart';

/// Formats a [ProjectInfo] for the terminal.
class ProjectRenderer {
  const ProjectRenderer();

  String render(ProjectInfo info) {
    final out = StringBuffer();
    final version = info.version == null ? '' : '  ${info.version}';
    out.writeln('Project: ${info.name}$version');
    final description = info.description;
    if (description != null && description.isNotEmpty) {
      out.writeln('  $description');
    }
    out
      ..writeln('  ${info.rootPath}')
      ..writeln();

    _row(out, 'Dart SDK', info.dartConstraint ?? 'not declared');
    _row(out, 'Flutter SDK', info.flutterConstraint ?? 'not declared');
    _row(out, 'Platforms', _platforms(info));
    _row(out, 'Android id', info.androidApplicationId ?? '-');
    _row(out, 'iOS bundle id', info.iosBundleId ?? '-');
    _row(
      out,
      'Packages',
      '${info.dependencies.length} dependencies, '
          '${info.devDependencies.length} dev dependencies',
    );
    _row(
      out,
      'Assets',
      info.assets.isEmpty ? 'none declared' : '${info.assets.length} declared',
    );
    _row(
      out,
      'Fonts',
      info.fontFamilies.isEmpty
          ? 'none declared'
          : info.fontFamilies.join(', '),
    );

    out.writeln();
    if (!info.pluginsResolved) {
      out.writeln(
        'Native plugins: unknown. Run "flutter pub get" so Flutter can '
        'resolve them.',
      );
    } else if (info.nativePlugins.isEmpty) {
      out.writeln('Native plugins: none');
    } else {
      out.writeln('Native plugins (${info.nativePlugins.length}):');
      for (final plugin in info.nativePlugins) {
        final platforms =
            (plugin.platforms.map((p) => p.label).toList()..sort()).join(', ');
        out.writeln('  ${plugin.name}  ($platforms)');
      }
    }
    return out.toString();
  }

  String _platforms(ProjectInfo info) {
    if (info.platforms.isEmpty) return 'none detected';
    final labels = info.platforms.map((p) => p.label).toList()..sort();
    return labels.join(', ');
  }

  void _row(StringBuffer out, String label, String value) {
    out.writeln('${label.padRight(14)}$value');
  }
}
