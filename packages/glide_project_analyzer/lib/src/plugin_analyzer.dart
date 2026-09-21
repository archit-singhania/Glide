import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dependency_analyzer.dart';
import 'plugin_knowledge.dart';
import 'project_model.dart';

/// The kind of code a dependency brings to the host app.
enum PluginKind {
  /// `flutter pub get` has not run, so Glide cannot tell.
  unknown('unknown until "flutter pub get" has run'),
  dartOnly('Dart only'),
  nativeAndroid('native code, Android'),
  nativeIos('native code, iOS'),
  nativeAndroidAndIos('native code, Android and iOS'),
  nativeDesktop('native code, desktop only');

  const PluginKind(this.label);

  final String label;
}

/// The overall verdict for one dependency.
enum PluginStatus { ready, requiresConfiguration, unsupported }

enum RequirementState {
  /// Glide found what the plugin needs.
  satisfied,

  /// Glide looked and it is not there.
  missing,

  /// Glide cannot check this; shown as a reminder.
  unverified,
}

/// One [PluginRequirement] checked against the project's files.
class RequirementResult {
  const RequirementResult({
    required this.requirement,
    required this.state,
    this.detail,
  });

  final PluginRequirement requirement;
  final RequirementState state;

  /// Why the requirement is [RequirementState.missing] or unverified.
  final String? detail;

  Map<String, Object?> toJson() => <String, Object?>{
        'platform': requirement.platform.name,
        'summary': requirement.summary,
        'state': state.name,
        if (requirement.file != null) 'file': requirement.file,
        if (detail != null) 'detail': detail,
      };
}

/// What Glide learned about one direct dependency that has native code or
/// known host-project requirements.
class PluginAssessment {
  const PluginAssessment({
    required this.package,
    required this.kind,
    this.implementations = const <String>[],
    this.unsupportedOn = const <ProjectPlatform>{},
    this.requirements = const <RequirementResult>[],
  });

  /// The package named in `pubspec.yaml`.
  final String package;
  final PluginKind kind;

  /// The platform implementation packages that carry native code, for
  /// example `camera_android`.
  final List<String> implementations;

  /// Platforms the project targets that the plugin registers no
  /// implementation for.
  final Set<ProjectPlatform> unsupportedOn;
  final List<RequirementResult> requirements;

  List<RequirementResult> get missingRequirements => <RequirementResult>[
        for (final result in requirements)
          if (result.state == RequirementState.missing) result,
      ];

  PluginStatus get status {
    if (unsupportedOn.isNotEmpty) return PluginStatus.unsupported;
    if (missingRequirements.isNotEmpty) {
      return PluginStatus.requiresConfiguration;
    }
    return PluginStatus.ready;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'package': package,
        'kind': kind.name,
        'status': status.name,
        'implementations': implementations,
        'unsupportedOn': (unsupportedOn.map((os) => os.name).toList()..sort()),
        'requirements': requirements.map((r) => r.toJson()).toList(),
      };
}

/// Everything `glide plugins` reports.
class PluginReport {
  const PluginReport({
    required this.resolved,
    required this.assessments,
    this.transitiveNativePlugins = const <NativePlugin>[],
    this.dartOnlyDependencies,
  });

  /// False when plugins have not been resolved yet.
  final bool resolved;
  final List<PluginAssessment> assessments;

  /// Native plugin packages that no direct dependency accounts for.
  final List<NativePlugin> transitiveNativePlugins;

  /// Direct dependencies with no native code and no known requirements, or
  /// null while [resolved] is false.
  final int? dartOnlyDependencies;

  bool get hasProblems =>
      assessments.any((assessment) => assessment.status != PluginStatus.ready);

  Map<String, Object?> toJson() => <String, Object?>{
        'resolved': resolved,
        'hasProblems': hasProblems,
        'assessments': assessments.map((a) => a.toJson()).toList(),
        'transitiveNativePlugins':
            transitiveNativePlugins.map((n) => n.toJson()).toList(),
        if (dartOnlyDependencies != null)
          'dartOnlyDependencies': dartOnlyDependencies,
      };
}

/// Classifies a project's dependencies and checks the host project for what
/// well-known plugins need.
///
/// This is read-only. It never edits `AndroidManifest.xml` or `Info.plist`,
/// and it only reports what it can verify from those files. Text matching is
/// literal, so an entry inside an XML comment still counts as present.
class PluginAnalyzer {
  const PluginAnalyzer({this.knowledge = defaultPluginKnowledge});

  final List<PluginKnowledge> knowledge;

  PluginReport analyze(ProjectInfo info) {
    final direct = <String>{
      for (final entry in info.dependencies.entries)
        // `flutter: sdk: flutter` and friends are not plugins.
        if (!entry.value.startsWith('sdk:')) entry.key,
    };
    final resolved = info.pluginsResolved;
    final registered = resolved
        ? NativePluginScanner.scan(info.rootPath).registered
        : const <String, Set<ProjectPlatform>>{};
    final known = <String, PluginKnowledge>{
      for (final entry in knowledge) entry.package: entry,
    };

    final claimed = <String>{};
    final assessments = <PluginAssessment>[];
    var dartOnly = 0;

    for (final dep in direct.toList()..sort()) {
      final native = <NativePlugin>[
        for (final plugin in info.nativePlugins)
          if (_owns(dep, plugin.name, direct)) plugin,
      ];
      final family = <Set<ProjectPlatform>>[
        for (final entry in registered.entries)
          if (_owns(dep, entry.key, direct)) entry.value,
      ];
      final knownRequirements = known[dep];
      if (native.isEmpty && family.isEmpty && knownRequirements == null) {
        if (resolved) dartOnly++;
        continue;
      }

      claimed.addAll(native.map((plugin) => plugin.name));
      final nativePlatforms = <ProjectPlatform>{
        for (final plugin in native) ...plugin.platforms,
      };
      final supported = <ProjectPlatform>{
        for (final platforms in family) ...platforms,
      };
      final unsupported = <ProjectPlatform>{
        if (resolved && family.isNotEmpty)
          for (final platform in info.platforms)
            if (platform != ProjectPlatform.web &&
                !supported.contains(platform))
              platform,
      };

      assessments.add(
        PluginAssessment(
          package: dep,
          kind: resolved ? _kindOf(nativePlatforms) : PluginKind.unknown,
          implementations: <String>[for (final plugin in native) plugin.name],
          unsupportedOn: unsupported,
          requirements: _evaluate(knownRequirements, info),
        ),
      );
    }

    return PluginReport(
      resolved: resolved,
      assessments: assessments,
      transitiveNativePlugins: <NativePlugin>[
        for (final plugin in info.nativePlugins)
          if (!claimed.contains(plugin.name)) plugin,
      ],
      dartOnlyDependencies: resolved ? dartOnly : null,
    );
  }

  /// Whether [pluginName] is [dep] itself or one of its platform
  /// implementations (`camera` owns `camera_android`).
  ///
  /// When another direct dependency is a longer, closer match, that one owns
  /// it instead, so `share` does not claim `share_plus`.
  static bool _owns(String dep, String pluginName, Set<String> direct) {
    if (pluginName == dep) return true;
    if (!pluginName.startsWith('${dep}_')) return false;
    return !direct.any(
      (other) =>
          other.length > dep.length &&
          (pluginName == other || pluginName.startsWith('${other}_')),
    );
  }

  static PluginKind _kindOf(Set<ProjectPlatform> native) {
    final android = native.contains(ProjectPlatform.android);
    final ios = native.contains(ProjectPlatform.ios);
    if (android && ios) return PluginKind.nativeAndroidAndIos;
    if (android) return PluginKind.nativeAndroid;
    if (ios) return PluginKind.nativeIos;
    if (native.isNotEmpty) return PluginKind.nativeDesktop;
    return PluginKind.dartOnly;
  }

  static List<RequirementResult> _evaluate(
    PluginKnowledge? entry,
    ProjectInfo info,
  ) =>
      <RequirementResult>[
        if (entry != null)
          for (final requirement in entry.requirements)
            // A platform the project does not target has nothing to check.
            if (info.platforms.contains(requirement.platform))
              _check(requirement, info.rootPath),
      ];

  static RequirementResult _check(PluginRequirement requirement, String root) {
    switch (requirement.check) {
      case RequirementCheck.manual:
        return RequirementResult(
          requirement: requirement,
          state: RequirementState.unverified,
        );
      case RequirementCheck.fileExists:
        final expected = requirement.file!;
        return File(_resolve(root, expected)).existsSync()
            ? RequirementResult(
                requirement: requirement,
                state: RequirementState.satisfied,
              )
            : RequirementResult(
                requirement: requirement,
                state: RequirementState.missing,
                detail: 'File not found: $expected',
              );
      case RequirementCheck.fileContains:
        final relative = requirement.file!;
        final file = File(_resolve(root, relative));
        if (!file.existsSync()) {
          return RequirementResult(
            requirement: requirement,
            state: RequirementState.missing,
            detail: 'File not found: $relative',
          );
        }
        final String text;
        try {
          text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
        } on FileSystemException {
          return RequirementResult(
            requirement: requirement,
            state: RequirementState.unverified,
            detail: 'Could not read $relative',
          );
        }
        final found = requirement.containsAny.any(text.contains);
        return found
            ? RequirementResult(
                requirement: requirement,
                state: RequirementState.satisfied,
              )
            : RequirementResult(
                requirement: requirement,
                state: RequirementState.missing,
                detail: 'Not found in $relative',
              );
    }
  }

  static String _resolve(String root, String relative) =>
      p.joinAll(<String>[root, ...relative.split('/')]);
}
