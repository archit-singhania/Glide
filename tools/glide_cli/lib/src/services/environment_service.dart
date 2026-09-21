import 'dart:io';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_security/glide_security.dart';

import 'adb_detector.dart';
import 'android_sdk_detector.dart';
import 'doctor_report.dart';
import 'flutter_sdk_detector.dart';
import 'host_environment.dart';
import 'ios_toolchain_check.dart';
import 'java_detector.dart';
import 'machine_json.dart';
import 'tool_probe.dart';
import 'versions.dart';

/// Supplies the private IPv4 addresses of this machine.
typedef LanAddressProvider = Future<List<String>> Function();

/// Inspects the machine. The seam that commands and tests depend on.
abstract interface class EnvironmentInspector {
  Future<DoctorReport> inspect({String? flutterSdkPath});
}

/// Private, non link-local IPv4 addresses of this machine, `192.168.x.x`
/// first because that is the most common home and office LAN range.
Future<List<String>> systemLanAddresses() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  final addresses = <String>[];
  for (final networkInterface in interfaces) {
    for (final address in networkInterface.addresses) {
      final ip = address.address;
      if (NetworkPolicy.isPrivateIPv4(ip) && !ip.startsWith('169.254.')) {
        addresses.add(ip);
      }
    }
  }
  int rank(String ip) => ip.startsWith('192.168.')
      ? 0
      : ip.startsWith('10.')
          ? 1
          : 2;
  addresses.sort((a, b) => rank(a).compareTo(rank(b)));
  return addresses;
}

/// Runs every environment check behind `glide doctor`.
class EnvironmentService implements EnvironmentInspector {
  EnvironmentService({
    required ToolRunner runner,
    required HostEnvironment host,
    required FlutterSdkLocator locator,
    LanAddressProvider? lanAddresses,
  })  : _probe = ToolProbe(runner),
        _host = host,
        _flutter = FlutterSdkDetector(
          probe: ToolProbe(runner),
          locator: locator,
        ),
        _androidSdk = AndroidSdkDetector(host),
        _adb = AdbDetector(probe: ToolProbe(runner), host: host),
        _java = JavaDetector(probe: ToolProbe(runner), host: host),
        _lanAddresses = lanAddresses ?? systemLanAddresses;

  /// Wires the service to the real machine.
  factory EnvironmentService.system() => EnvironmentService(
        runner: const SystemProcessLauncher(),
        host: HostEnvironment(),
        locator: FlutterSdkLocator(),
      );

  final ToolProbe _probe;
  final HostEnvironment _host;
  final FlutterSdkDetector _flutter;
  final AndroidSdkDetector _androidSdk;
  final AdbDetector _adb;
  final JavaDetector _java;
  final LanAddressProvider _lanAddresses;

  @override
  Future<DoctorReport> inspect({String? flutterSdkPath}) async {
    final checks = <DoctorCheck>[];

    final flutter = await _flutter.detect(explicitPath: flutterSdkPath);
    final sdk = flutter.value;
    if (sdk == null) {
      checks.addAll(<DoctorCheck>[
        DoctorCheck(
          id: 'flutter-sdk',
          title: 'Flutter SDK',
          status: CheckStatus.error,
          detail: flutter.problem,
          remediation: 'Install Flutter, then add flutter/bin to PATH, set '
              'GLIDE_FLUTTER_SDK, or pass --flutter-sdk.',
        ),
        const DoctorCheck(
          id: 'flutter-version',
          title: 'Flutter version',
          status: CheckStatus.skipped,
          detail: 'Flutter SDK not found.',
        ),
        const DoctorCheck(
          id: 'dart-sdk',
          title: 'Dart SDK',
          status: CheckStatus.skipped,
          detail: 'Flutter SDK not found.',
        ),
      ]);
    } else {
      checks.addAll(<DoctorCheck>[
        DoctorCheck(
          id: 'flutter-sdk',
          title: 'Flutter SDK',
          status: CheckStatus.ok,
          detail: sdk.executable,
        ),
        _flutterVersionCheck(sdk),
        _dartCheck(sdk),
      ]);
    }

    final androidSdk = _androidSdk.detect();
    checks.add(_androidSdkCheck(androidSdk));
    checks.add(_adbCheck(await _adb.detect(sdk: androidSdk)));
    checks.add(_javaCheck(await _java.detect()));
    checks.add(await _gitCheck());
    checks.addAll(await checkIosToolchain(probe: _probe, host: _host));

    var devices = const <FlutterDevice>[];
    if (sdk == null) {
      checks.add(
        const DoctorCheck(
          id: 'devices',
          title: 'Connected devices',
          status: CheckStatus.skipped,
          detail: 'Flutter SDK not found.',
        ),
      );
    } else {
      final listing = await _listDevices(sdk);
      devices = listing.devices;
      checks.add(_devicesCheck(listing.devices, listing.problem));
    }

    final lan = await _readLanAddresses();
    checks.add(_networkCheck(lan.addresses, lan.problem));

    return DoctorReport(
      checks: checks,
      devices: devices,
      lanAddresses: lan.addresses,
      flutterVersion: sdk?.frameworkVersion,
      dartVersion: sdk?.dartVersion,
    );
  }

  DoctorCheck _flutterVersionCheck(FlutterSdkInfo sdk) {
    final label = '${sdk.frameworkVersion} (${sdk.channel})';
    final parsed = parseCoreVersion(sdk.frameworkVersion);
    if (parsed == null) {
      return DoctorCheck(
        id: 'flutter-version',
        title: 'Flutter version',
        status: CheckStatus.warning,
        detail: 'Could not interpret "$label".',
      );
    }
    if (parsed < GlideRequirements.minimumFlutter) {
      return DoctorCheck(
        id: 'flutter-version',
        title: 'Flutter version',
        status: CheckStatus.error,
        detail: '$label is older than the minimum '
            '${GlideRequirements.minimumFlutter}.',
        remediation: 'Run "flutter upgrade".',
      );
    }
    return DoctorCheck(
      id: 'flutter-version',
      title: 'Flutter version',
      status: CheckStatus.ok,
      detail: label,
    );
  }

  DoctorCheck _dartCheck(FlutterSdkInfo sdk) {
    final reported = sdk.dartVersion;
    final parsed = reported == null ? null : parseCoreVersion(reported);
    if (parsed == null) {
      return const DoctorCheck(
        id: 'dart-sdk',
        title: 'Dart SDK',
        status: CheckStatus.warning,
        detail: 'The Flutter tool did not report a Dart version.',
      );
    }
    if (parsed < GlideRequirements.minimumDart) {
      return DoctorCheck(
        id: 'dart-sdk',
        title: 'Dart SDK',
        status: CheckStatus.error,
        detail: '$parsed is older than the minimum '
            '${GlideRequirements.minimumDart}.',
        remediation: 'Run "flutter upgrade".',
      );
    }
    return DoctorCheck(
      id: 'dart-sdk',
      title: 'Dart SDK',
      status: CheckStatus.ok,
      detail: '$parsed',
    );
  }

  DoctorCheck _androidSdkCheck(AndroidSdkInfo? sdk) {
    if (sdk == null) {
      return const DoctorCheck(
        id: 'android-sdk',
        title: 'Android SDK',
        status: CheckStatus.error,
        detail: 'Not found.',
        remediation: 'Install Android Studio (or the command-line tools) and '
            'set ANDROID_HOME to the SDK directory.',
      );
    }
    if (!sdk.hasPlatformTools) {
      return DoctorCheck(
        id: 'android-sdk',
        title: 'Android SDK',
        status: CheckStatus.warning,
        detail: '${sdk.path} (platform-tools is missing)',
        remediation: 'Install "Android SDK Platform-Tools" in the SDK Manager.',
      );
    }
    return DoctorCheck(
      id: 'android-sdk',
      title: 'Android SDK',
      status: CheckStatus.ok,
      detail: sdk.path,
    );
  }

  DoctorCheck _adbCheck(Detection<AdbInfo> adb) {
    final info = adb.value;
    if (info == null) {
      return DoctorCheck(
        id: 'adb',
        title: 'ADB',
        status: CheckStatus.error,
        detail: adb.problem,
        remediation: 'Install Android SDK Platform-Tools and make sure adb is '
            'inside the SDK or on PATH.',
      );
    }
    return DoctorCheck(
      id: 'adb',
      title: 'ADB',
      status: CheckStatus.ok,
      detail: '${info.version} (${info.executable})',
    );
  }

  DoctorCheck _javaCheck(Detection<JavaInfo> java) {
    final info = java.value;
    if (info == null) {
      return DoctorCheck(
        id: 'java',
        title: 'Java',
        status: CheckStatus.warning,
        detail: java.problem,
        remediation: 'Install JDK ${GlideRequirements.minimumJavaMajor}+. '
            "Flutter can also use Android Studio's bundled JDK.",
      );
    }
    if (info.major < GlideRequirements.minimumJavaMajor) {
      return DoctorCheck(
        id: 'java',
        title: 'Java',
        status: CheckStatus.warning,
        detail: '${info.version} is older than '
            '${GlideRequirements.minimumJavaMajor}.',
        remediation: 'Install JDK ${GlideRequirements.minimumJavaMajor}+ for '
            'Android Gradle Plugin 8.',
      );
    }
    return DoctorCheck(
      id: 'java',
      title: 'Java',
      status: CheckStatus.ok,
      detail: info.version,
    );
  }

  Future<DoctorCheck> _gitCheck() async {
    final result = await _probe.run('git', const <String>['--version']);
    if (!result.succeeded) {
      return DoctorCheck(
        id: 'git',
        title: 'Git',
        status: CheckStatus.error,
        detail: result.failure,
        remediation: 'Install Git; the Flutter tool requires it.',
      );
    }
    return DoctorCheck(
      id: 'git',
      title: 'Git',
      status: CheckStatus.ok,
      detail: firstLine(result.output),
    );
  }

  Future<({List<FlutterDevice> devices, String? problem})> _listDevices(
    FlutterSdkInfo sdk,
  ) async {
    final result = await _probe.run(
      sdk.executable,
      const <String>['devices', '--machine'],
      timeout: const Duration(seconds: 120),
    );
    if (!result.succeeded) {
      return (devices: const <FlutterDevice>[], problem: result.failure);
    }
    final decoded = decodeEmbeddedJson(result.output, open: '[');
    if (decoded is! List) {
      return (
        devices: const <FlutterDevice>[],
        problem: 'Could not read the output of "flutter devices --machine".',
      );
    }
    final devices = <FlutterDevice>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final device = FlutterDevice.tryFromJson(
        Map<String, Object?>.from(item),
      );
      if (device != null) devices.add(device);
    }
    return (devices: devices, problem: null);
  }

  DoctorCheck _devicesCheck(List<FlutterDevice> devices, String? problem) {
    if (problem != null) {
      return DoctorCheck(
        id: 'devices',
        title: 'Connected devices',
        status: CheckStatus.warning,
        detail: problem,
      );
    }
    const remediation = 'Connect an Android phone with USB debugging enabled '
        '(or start an emulator), then run the doctor again.';
    if (devices.isEmpty) {
      return const DoctorCheck(
        id: 'devices',
        title: 'Connected devices',
        status: CheckStatus.warning,
        detail: 'No devices found.',
        remediation: remediation,
      );
    }
    final android = devices.where((d) => d.isAndroid && d.isSupported).length;
    if (android == 0) {
      return DoctorCheck(
        id: 'devices',
        title: 'Connected devices',
        status: CheckStatus.warning,
        detail: '${devices.length} found, none of them Android.',
        remediation: remediation,
      );
    }
    return DoctorCheck(
      id: 'devices',
      title: 'Connected devices',
      status: CheckStatus.ok,
      detail: '$android Android device${android == 1 ? '' : 's'}',
    );
  }

  Future<({List<String> addresses, String? problem})>
      _readLanAddresses() async {
    try {
      return (addresses: await _lanAddresses(), problem: null);
    } on Exception catch (error) {
      return (
        addresses: const <String>[],
        problem: 'Could not list network interfaces: $error',
      );
    }
  }

  DoctorCheck _networkCheck(List<String> addresses, String? problem) {
    if (problem != null) {
      return DoctorCheck(
        id: 'network',
        title: 'Network',
        status: CheckStatus.warning,
        detail: problem,
      );
    }
    if (addresses.isEmpty) {
      return const DoctorCheck(
        id: 'network',
        title: 'Network',
        status: CheckStatus.warning,
        detail: 'No private LAN address found.',
        remediation: 'Connect to Wi-Fi or Ethernet; the companion pairs over '
            'your local network.',
      );
    }
    return DoctorCheck(
      id: 'network',
      title: 'Network',
      status: CheckStatus.ok,
      detail: addresses.join(', '),
    );
  }
}
