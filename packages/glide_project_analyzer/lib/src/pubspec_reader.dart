import 'package:yaml/yaml.dart';

import 'project_model.dart';

/// The parts of `pubspec.yaml` Glide cares about.
class PubspecData {
  const PubspecData({
    required this.name,
    required this.isFlutterProject,
    this.description,
    this.version,
    this.dartConstraint,
    this.flutterConstraint,
    this.dependencies = const <String, String>{},
    this.devDependencies = const <String, String>{},
    this.assets = const <String>[],
    this.fontFamilies = const <String>[],
  });

  final String name;
  final bool isFlutterProject;
  final String? description;
  final String? version;
  final String? dartConstraint;
  final String? flutterConstraint;
  final Map<String, String> dependencies;
  final Map<String, String> devDependencies;
  final List<String> assets;
  final List<String> fontFamilies;
}

/// Parses `pubspec.yaml` into typed data.
abstract final class PubspecReader {
  static PubspecData parse(String source) {
    final Object? document;
    try {
      document = loadYaml(source);
    } on YamlException catch (error) {
      throw ProjectException(
        'pubspec.yaml is not valid YAML: ${error.message}',
        cause: error,
      );
    }
    if (document is! Map) {
      throw const ProjectException('pubspec.yaml must be a YAML mapping.');
    }

    final name = _string(document['name']);
    if (name == null || name.isEmpty) {
      throw const ProjectException('pubspec.yaml has no "name".');
    }

    final environment = document['environment'];
    final dependencies = _dependencies(document['dependencies']);
    final flutter = document['flutter'];

    return PubspecData(
      name: name,
      isFlutterProject: dependencies.containsKey('flutter') || flutter is Map,
      description: _string(document['description']),
      version: _string(document['version']),
      dartConstraint: environment is Map ? _string(environment['sdk']) : null,
      flutterConstraint:
          environment is Map ? _string(environment['flutter']) : null,
      dependencies: dependencies,
      devDependencies: _dependencies(document['dev_dependencies']),
      assets: _assets(flutter),
      fontFamilies: _fontFamilies(flutter),
    );
  }

  static String? _string(Object? value) => value is String ? value : null;

  static Map<String, String> _dependencies(Object? raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries) '${entry.key}': _describe(entry.value),
    };
  }

  static String _describe(Object? spec) {
    if (spec == null) return 'any';
    if (spec is String) return spec;
    if (spec is Map) {
      if (spec['sdk'] != null) return 'sdk: ${spec['sdk']}';
      if (spec['path'] != null) return 'path: ${spec['path']}';
      if (spec['git'] != null) return 'git';
      final version = spec['version'];
      if (version is String) return version;
      return 'hosted';
    }
    return '$spec';
  }

  static List<String> _assets(Object? flutter) {
    if (flutter is! Map) return const <String>[];
    final raw = flutter['assets'];
    if (raw is! List) return const <String>[];
    return <String>[
      for (final item in raw)
        if (item is String)
          item
        else if (item is Map && item['path'] is String)
          item['path'] as String,
    ];
  }

  static List<String> _fontFamilies(Object? flutter) {
    if (flutter is! Map) return const <String>[];
    final raw = flutter['fonts'];
    if (raw is! List) return const <String>[];
    return <String>[
      for (final item in raw)
        if (item is Map && item['family'] is String) item['family'] as String,
    ];
  }
}
