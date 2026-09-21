import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:glide_cli/glide_cli.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_tool_runner.dart';

const String _flutterVersionJson = '{"frameworkVersion":"3.30.0",'
    '"channel":"stable","dartSdkVersion":"3.7.0 (build 3.7.0-edge)"}';

const String _pixelJson = '[{"name":"Pixel 10","id":"ABC123",'
    '"isSupported":true,"targetPlatform":"android-arm64","emulator":false}]';

class _StubInspector implements EnvironmentInspector {
  _StubInspector(this.report);

  final DoctorReport report;
  String? receivedPath;

  @override
  Future<DoctorReport> inspect({String? flutterSdkPath}) async {
    receivedPath = flutterSdkPath;
    return report;
  }
}

CheckStatus _statusOf(DoctorReport report, String id) =>
    report.checks.firstWhere((c) => c.id == id).status;

void main() {
  group('decodeEmbeddedJson', () {
    test('finds an object surrounded by tool noise', () {
      const text = 'Waiting for another flutter command to release the '
          'startup lock...\n{"a": 1}\nDone\n';
      expect(decodeEmbeddedJson(text, open: '{'), equals({'a': 1}));
    });

    test('skips bracketed noise before an array', () {
      const text = '[!] some warning\n[\n  {"id": "x"}\n]\n';
      expect(
        decodeEmbeddedJson(text, open: '['),
        equals([
          {'id': 'x'},
        ]),
      );
    });

    test('reads an empty array', () {
      expect(decodeEmbeddedJson('[]\n', open: '['), isEmpty);
    });

    test('returns null when there is no JSON', () {
      expect(decodeEmbeddedJson('nothing here', open: '{'), isNull);
      expect(decodeEmbeddedJson('{oops', open: '{'), isNull);
    });
  });

  group('version parsing', () {
    test('parseCoreVersion ignores suffixes', () {
      expect(parseCoreVersion('3.7.0 (build 3.7.0-edge)').toString(), '3.7.0');
      expect(parseCoreVersion('none'), isNull);
    });

    test('parseJavaMajor understands old and new schemes', () {
      expect(parseJavaMajor('17.0.9'), 17);
      expect(parseJavaMajor('1.8.0_311'), 8);
      expect(parseJavaMajor('21'), 21);
      expect(parseJavaMajor('garbage'), 0);
    });
  });

  group('EnvironmentService', () {
    late Directory sdkDir;
    late FakeToolRunner runner;
    late String flutter;
    late String androidHome;
    late String adb;
    late Set<String> existing;

    setUp(() {
      sdkDir = Directory.systemTemp.createTempSync('glide_doctor_');
      File(p.join(sdkDir.path, 'bin', 'flutter')).createSync(recursive: true);

      flutter = FlutterSdkLocator(
        environment: const <String, String>{},
        isWindows: false,
      ).locate(explicitPath: sdkDir.path)!.executable;

      androidHome = p.join(sdkDir.path, 'android-sdk');
      adb = p.join(androidHome, 'platform-tools', 'adb');
      existing = <String>{
        androidHome,
        p.join(androidHome, 'platform-tools'),
        adb,
      };

      runner = FakeToolRunner()
        ..on('$flutter --version --machine', stdout: _flutterVersionJson)
        ..on('$flutter devices --machine', stdout: _pixelJson)
        ..on(
          '$adb version',
          stdout: 'Android Debug Bridge version 1.0.41\nVersion 35.0.2\n',
        )
        ..on(
          'java -version',
          stderr: 'openjdk version "17.0.9" 2023-10-17\nOpenJDK Runtime\n',
        )
        ..on('git --version', stdout: 'git version 2.43.0');
    });

    tearDown(() => sdkDir.deleteSync(recursive: true));

    EnvironmentService service({
      List<String> lan = const <String>['192.168.1.20'],
    }) =>
        EnvironmentService(
          runner: runner,
          host: HostEnvironment(
            variables: <String, String>{'ANDROID_HOME': androidHome},
            operatingSystem: 'linux',
            pathExists: existing.contains,
          ),
          locator: FlutterSdkLocator(
            environment: const <String, String>{},
            isWindows: false,
          ),
          lanAddresses: () async => lan,
        );

    test('a healthy machine passes every check', () async {
      final report = await service().inspect(flutterSdkPath: sdkDir.path);

      expect(report.hasErrors, isFalse);
      expect(report.hasWarnings, isFalse);
      expect(
        report.checks.map((c) => c.status),
        everyElement(CheckStatus.ok),
      );
      expect(report.flutterVersion, '3.30.0');
      expect(report.devices.single.name, 'Pixel 10');
      expect(report.lanAddresses, <String>['192.168.1.20']);
    });

    test('a missing Flutter SDK is an error and skips dependent checks',
        () async {
      final report = await service().inspect(
        flutterSdkPath: p.join(sdkDir.path, 'nowhere'),
      );

      expect(report.hasErrors, isTrue);
      expect(_statusOf(report, 'flutter-sdk'), CheckStatus.error);
      expect(_statusOf(report, 'flutter-version'), CheckStatus.skipped);
      expect(_statusOf(report, 'devices'), CheckStatus.skipped);
    });

    test('a Flutter older than the minimum is an error', () async {
      runner.on(
        '$flutter --version --machine',
        stdout: '{"frameworkVersion":"3.10.0","channel":"stable",'
            '"dartSdkVersion":"3.0.0"}',
      );
      final report = await service().inspect(flutterSdkPath: sdkDir.path);

      expect(_statusOf(report, 'flutter-version'), CheckStatus.error);
      expect(_statusOf(report, 'dart-sdk'), CheckStatus.error);
    });

    test('a failing flutter tool is reported with its reason', () async {
      runner.on(
        '$flutter --version --machine',
        exitCode: 1,
        stderr: 'Something broke\n',
      );
      final report = await service().inspect(flutterSdkPath: sdkDir.path);

      final check = report.checks.firstWhere((c) => c.id == 'flutter-sdk');
      expect(check.status, CheckStatus.error);
      expect(check.detail, contains('Something broke'));
    });

    test('a missing adb is an error', () async {
      runner.results.remove('$adb version');
      final report = await service().inspect(flutterSdkPath: sdkDir.path);

      expect(_statusOf(report, 'adb'), CheckStatus.error);
      expect(report.hasErrors, isTrue);
    });

    test('a missing Android SDK is an error', () async {
      existing.clear();
      final report = await service().inspect(flutterSdkPath: sdkDir.path);

      expect(_statusOf(report, 'android-sdk'), CheckStatus.error);
    });

    test('old Java, no devices and no LAN are warnings, not errors', () async {
      runner
        ..on('java -version', stderr: 'openjdk version "11.0.21" 2023-10-17\n')
        ..on('$flutter devices --machine', stdout: '[]\n');
      final report = await service(lan: const <String>[])
          .inspect(flutterSdkPath: sdkDir.path);

      expect(_statusOf(report, 'java'), CheckStatus.warning);
      expect(_statusOf(report, 'devices'), CheckStatus.warning);
      expect(_statusOf(report, 'network'), CheckStatus.warning);
      expect(report.hasErrors, isFalse);
      expect(report.hasWarnings, isTrue);
    });

    test('a failing LAN provider becomes a warning', () async {
      final report = await EnvironmentService(
        runner: runner,
        host: HostEnvironment(
          variables: <String, String>{'ANDROID_HOME': androidHome},
          operatingSystem: 'linux',
          pathExists: existing.contains,
        ),
        locator: FlutterSdkLocator(
          environment: const <String, String>{},
          isWindows: false,
        ),
        lanAddresses: () async => throw const SocketException('no adapters'),
      ).inspect(flutterSdkPath: sdkDir.path);

      expect(_statusOf(report, 'network'), CheckStatus.warning);
    });
  });

  group('DoctorRenderer', () {
    const report = DoctorReport(
      checks: <DoctorCheck>[
        DoctorCheck(
          id: 'flutter-sdk',
          title: 'Flutter SDK',
          status: CheckStatus.ok,
          detail: '/x/flutter',
        ),
        DoctorCheck(
          id: 'adb',
          title: 'ADB',
          status: CheckStatus.error,
          detail: 'not found',
          remediation: 'Install platform-tools',
        ),
      ],
    );

    test('plain output has no ANSI codes and shows the fix', () {
      final text = const DoctorRenderer(unicode: false).render(report);

      expect(text, contains('Glide Doctor'));
      expect(text, contains('[ok]'));
      expect(text, contains('[x]'));
      expect(text, contains('Install platform-tools'));
      expect(text, contains('1 problem must be fixed'));
      expect(text, isNot(contains('\x1B')));
    });

    test('colour output uses ANSI codes', () {
      final text = const DoctorRenderer(color: true).render(report);
      expect(text, contains('\x1B['));
    });
  });

  group('glide command', () {
    const healthy = DoctorReport(
      checks: <DoctorCheck>[
        DoctorCheck(id: 'git', title: 'Git', status: CheckStatus.ok),
      ],
      flutterVersion: '3.30.0',
    );
    const broken = DoctorReport(
      checks: <DoctorCheck>[
        DoctorCheck(id: 'adb', title: 'ADB', status: CheckStatus.error),
      ],
    );

    GlideCommandRunner runnerFor(
      EnvironmentInspector inspector,
      StringBuffer out,
    ) =>
        GlideCommandRunner(
          out: out,
          err: StringBuffer(),
          environment: inspector,
        );

    test('doctor --json prints a report and exits 0', () async {
      final out = StringBuffer();
      final inspector = _StubInspector(healthy);

      final code = await runnerFor(inspector, out)
          .run(<String>['doctor', '--json', '--flutter-sdk', '/x']);

      expect(code, 0);
      expect(inspector.receivedPath, '/x');
      final json = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(json['ready'], isTrue);
      expect(json['flutterVersion'], '3.30.0');
    });

    test('doctor exits 1 when a check is an error', () async {
      final out = StringBuffer();
      final code =
          await runnerFor(_StubInspector(broken), out).run(<String>['doctor']);

      expect(code, 1);
      expect(out.toString(), contains('ADB'));
    });

    test('--version prints the version', () async {
      final out = StringBuffer();
      final code = await runnerFor(_StubInspector(healthy), out)
          .run(<String>['--version']);

      expect(code, 0);
      expect(out.toString().trim(), 'glide $glideVersion');
    });

    test('unknown commands are usage errors', () {
      expect(
        () => runnerFor(_StubInspector(healthy), StringBuffer())
            .run(<String>['nope']),
        throwsA(isA<UsageException>()),
      );
    });

    test('runGlide maps usage errors to exit code 64', () async {
      final err = StringBuffer();
      final code = await runGlide(
        <String>['nope'],
        out: StringBuffer(),
        err: err,
        environment: _StubInspector(healthy),
      );

      expect(code, 64);
      expect(err.toString(), contains('nope'));
    });
  });
}
