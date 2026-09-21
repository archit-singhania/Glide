import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_protocol/glide_protocol.dart';

import 'machine_json.dart';
import 'tool_probe.dart';

/// A Flutter SDK that answered `flutter --version --machine`.
class FlutterSdkInfo {
  const FlutterSdkInfo({
    required this.executable,
    required this.frameworkVersion,
    required this.channel,
    this.root,
    this.dartVersion,
  });

  /// Absolute path to `flutter` / `flutter.bat`.
  final String executable;

  /// SDK root directory, when it could be derived.
  final String? root;

  /// For example `3.27.4`.
  final String frameworkVersion;

  final String channel;

  /// The Dart SDK version bundled with this Flutter, as Flutter reports it.
  final String? dartVersion;
}

/// Locates the Flutter SDK and reads its version through the machine
/// interface (never by scraping the human-readable banner).
class FlutterSdkDetector {
  FlutterSdkDetector({
    required ToolProbe probe,
    required FlutterSdkLocator locator,
  })  : _probe = probe,
        _locator = locator;

  final ToolProbe _probe;
  final FlutterSdkLocator _locator;

  Future<Detection<FlutterSdkInfo>> detect({String? explicitPath}) async {
    final location = _locator.locate(explicitPath: explicitPath);
    if (location == null) {
      return Detection<FlutterSdkInfo>.missing(
        explicitPath == null
            ? 'Flutter SDK not found on PATH, GLIDE_FLUTTER_SDK, '
                'FLUTTER_ROOT or FLUTTER_HOME.'
            : 'No Flutter SDK found at "$explicitPath".',
      );
    }

    final result = await _probe.run(
      location.executable,
      const <String>['--version', '--machine'],
      timeout: const Duration(seconds: 120),
    );
    if (!result.succeeded) {
      return Detection<FlutterSdkInfo>.missing(
        '"${location.executable} --version" failed: ${result.failure}',
      );
    }

    final decoded = decodeEmbeddedJson(result.output, open: '{');
    if (decoded is! Map) {
      return const Detection<FlutterSdkInfo>.missing(
        'Could not read the output of "flutter --version --machine".',
      );
    }
    final json = Map<String, Object?>.from(decoded);
    final version = json.stringOrNull('frameworkVersion');
    if (version == null) {
      return const Detection<FlutterSdkInfo>.missing(
        'The Flutter tool did not report a framework version.',
      );
    }
    return Detection<FlutterSdkInfo>.found(
      FlutterSdkInfo(
        executable: location.executable,
        root: location.root,
        frameworkVersion: version,
        channel: json.stringOrNull('channel') ?? 'unknown',
        dartVersion: json.stringOrNull('dartSdkVersion'),
      ),
    );
  }
}
