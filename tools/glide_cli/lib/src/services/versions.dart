import 'package:pub_semver/pub_semver.dart';

/// Minimum toolchain Glide checks for. See docs/architecture/requirements.md.
abstract final class GlideRequirements {
  /// Lowest Flutter framework version `glide doctor` accepts.
  static final Version minimumFlutter = Version(3, 27, 0);

  /// Lowest Dart SDK version (the repository uses pub workspaces).
  static final Version minimumDart = Version(3, 6, 0);

  /// Android Gradle Plugin 8 needs JDK 17.
  static const int minimumJavaMajor = 17;
}

/// Reads the first `major.minor.patch` triple in [text], ignoring any
/// pre-release or build suffix. Returns null when there is none.
Version? parseCoreVersion(String text) {
  final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(text);
  if (match == null) return null;
  return Version(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// The Java feature release for a `java -version` string: `17.0.9` gives 17,
/// `1.8.0_311` gives 8. Returns 0 when it cannot be read.
int parseJavaMajor(String version) {
  final parts = version.split(RegExp(r'[._\-+]'));
  final first = int.tryParse(parts.first) ?? 0;
  if (first == 1 && parts.length > 1) return int.tryParse(parts[1]) ?? 0;
  return first;
}
