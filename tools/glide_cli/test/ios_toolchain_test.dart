import 'package:glide_cli/glide_cli.dart';
import 'package:test/test.dart';

import 'fake_tool_runner.dart';

HostEnvironment _host(String operatingSystem) => HostEnvironment(
      variables: const <String, String>{},
      operatingSystem: operatingSystem,
      pathExists: (_) => false,
    );

DoctorCheck _check(List<DoctorCheck> checks, String id) =>
    checks.firstWhere((c) => c.id == id);

void main() {
  group('checkIosToolchain', () {
    test('is one skipped check that starts nothing off a Mac', () async {
      for (final os in <String>['windows', 'linux']) {
        final runner = FakeToolRunner();
        final checks = await checkIosToolchain(
          probe: ToolProbe(runner),
          host: _host(os),
        );

        expect(checks, hasLength(1), reason: os);
        expect(checks.single.id, 'ios-toolchain');
        expect(checks.single.status, CheckStatus.skipped);
        expect(checks.single.detail, contains(os));
        expect(runner.calls, isEmpty, reason: os);
      }
    });

    test('a Mac with Xcode and CocoaPods passes both checks', () async {
      final runner = FakeToolRunner()
        ..on(
          'xcodebuild -version',
          stdout: 'Xcode 16.2\nBuild version 16C5032a\n',
        )
        ..on('pod --version', stdout: '1.16.2\n');

      final checks = await checkIosToolchain(
        probe: ToolProbe(runner),
        host: _host('macos'),
      );

      expect(_check(checks, 'xcode').status, CheckStatus.ok);
      expect(_check(checks, 'xcode').detail, 'Xcode 16.2');
      expect(_check(checks, 'cocoapods').status, CheckStatus.ok);
      expect(_check(checks, 'cocoapods').detail, '1.16.2');
    });

    test('missing Xcode is a warning and skips CocoaPods', () async {
      final runner = FakeToolRunner();

      final checks = await checkIosToolchain(
        probe: ToolProbe(runner),
        host: _host('macos'),
      );

      final xcode = _check(checks, 'xcode');
      expect(xcode.status, CheckStatus.warning);
      expect(xcode.remediation, contains('xcode-select'));
      expect(_check(checks, 'cocoapods').status, CheckStatus.skipped);
      // CocoaPods is never probed when Xcode is absent.
      expect(runner.calls, <String>['xcodebuild -version']);
    });

    test('missing CocoaPods is only a warning', () async {
      final runner = FakeToolRunner()
        ..on('xcodebuild -version', stdout: 'Xcode 16.2\n');

      final checks = await checkIosToolchain(
        probe: ToolProbe(runner),
        host: _host('macos'),
      );

      expect(_check(checks, 'xcode').status, CheckStatus.ok);
      final pods = _check(checks, 'cocoapods');
      expect(pods.status, CheckStatus.warning);
      expect(pods.remediation, contains('brew install cocoapods'));
      expect(
        checks.any((c) => c.status == CheckStatus.error),
        isFalse,
        reason: 'A missing iOS toolchain must never block Android work.',
      );
    });
  });
}
