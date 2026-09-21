import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'project_model.dart';

/// Result of reading `.flutter-plugins-dependencies`.
class PluginScan {
  const PluginScan({required this.plugins, required this.resolved});

  final List<NativePlugin> plugins;

  /// False when `flutter pub get` has not produced the file yet, so the list
  /// is empty because it is unknown, not because there are no plugins.
  final bool resolved;
}

/// Finds native plugins from the file Flutter generates during `pub get`.
///
/// Reading that machine-generated JSON is far more reliable than guessing from
/// package names.
abstract final class NativePluginScanner {
  static const String fileName = '.flutter-plugins-dependencies';

  static PluginScan scan(String projectDir) {
    final file = File(p.join(projectDir, fileName));
    if (!file.existsSync()) {
      return const PluginScan(plugins: <NativePlugin>[], resolved: false);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw ProjectException('$fileName is not valid JSON.', cause: error);
    }
    if (decoded is! Map) {
      throw const ProjectException('$fileName has an unexpected structure.');
    }
    final plugins = decoded['plugins'];
    if (plugins is! Map) {
      throw const ProjectException('$fileName has no "plugins" section.');
    }

    final byName = <String, Set<ProjectPlatform>>{};
    for (final entry in plugins.entries) {
      final platform = ProjectPlatform.values.asNameMap()['${entry.key}'];
      if (platform == null || platform == ProjectPlatform.web) continue;
      final list = entry.value;
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final name = item['name'];
        if (name is! String) continue;
        // Dart-only platform implementations have no native build.
        if (item['native_build'] == false) continue;
        byName.putIfAbsent(name, () => <ProjectPlatform>{}).add(platform);
      }
    }

    final names = byName.keys.toList()..sort();
    return PluginScan(
      plugins: <NativePlugin>[
        for (final name in names)
          NativePlugin(name: name, platforms: byName[name]!),
      ],
      resolved: true,
    );
  }
}
