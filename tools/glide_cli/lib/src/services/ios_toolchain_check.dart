import 'doctor_report.dart';
import 'host_environment.dart';
import 'tool_probe.dart';

/// Checks what building for an iPhone needs: Xcode, and CocoaPods for the
/// plugins that still use it.
///
/// iOS apps can only be built on a Mac, so on any other computer this returns
/// a single skipped check and starts no processes. Neither check is an
/// error: a missing toolchain only rules out iOS, and Android keeps working.
///
/// Never run on a real Mac by the author of this code. It only checks that
/// the tools answer, not that a signing identity or provisioning profile is
/// set up.
Future<List<DoctorCheck>> checkIosToolchain({
  required ToolProbe probe,
  required HostEnvironment host,
}) async {
  if (!host.isMacOS) {
    return <DoctorCheck>[
      DoctorCheck(
        id: 'ios-toolchain',
        title: 'iOS toolchain',
        status: CheckStatus.skipped,
        detail: 'Building for iOS needs a Mac with Xcode '
            '(this computer runs ${host.operatingSystem}).',
      ),
    ];
  }

  final xcode = await probe.run('xcodebuild', const <String>['-version']);
  if (!xcode.succeeded) {
    return <DoctorCheck>[
      DoctorCheck(
        id: 'xcode',
        title: 'Xcode',
        status: CheckStatus.warning,
        detail: xcode.failure,
        remediation: 'Install Xcode from the App Store, open it once to '
            'accept the license, then run '
            '"sudo xcode-select --switch /Applications/Xcode.app".',
      ),
      const DoctorCheck(
        id: 'cocoapods',
        title: 'CocoaPods',
        status: CheckStatus.skipped,
        detail: 'Xcode not found.',
      ),
    ];
  }

  final checks = <DoctorCheck>[
    DoctorCheck(
      id: 'xcode',
      title: 'Xcode',
      status: CheckStatus.ok,
      detail: firstLine(xcode.output),
    ),
  ];

  final pods = await probe.run('pod', const <String>['--version']);
  checks.add(
    pods.succeeded
        ? DoctorCheck(
            id: 'cocoapods',
            title: 'CocoaPods',
            status: CheckStatus.ok,
            detail: firstLine(pods.output),
          )
        : DoctorCheck(
            id: 'cocoapods',
            title: 'CocoaPods',
            status: CheckStatus.warning,
            detail: pods.failure,
            remediation: 'Flutter uses either Swift Package Manager or '
                'CocoaPods for each iOS plugin, so CocoaPods is still needed '
                'by plugins that have not moved. Install it with '
                '"brew install cocoapods" if an iOS build asks for it.',
          ),
  );
  return checks;
}
