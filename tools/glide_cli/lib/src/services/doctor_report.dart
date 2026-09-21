import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

/// Outcome of one environment check.
enum CheckStatus {
  ok,

  /// Something is off but Glide can still work.
  warning,

  /// Glide cannot work until this is fixed.
  error,

  /// Not evaluated because a prerequisite is missing.
  skipped,
}

/// One line of the doctor report.
class DoctorCheck {
  const DoctorCheck({
    required this.id,
    required this.title,
    required this.status,
    this.detail,
    this.remediation,
  });

  /// Stable machine-readable identifier, for example `android-sdk`.
  final String id;

  final String title;
  final CheckStatus status;
  final String? detail;

  /// How to fix it. Only set when the cause is known.
  final String? remediation;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'title': title,
        'status': status.name,
        if (detail != null) 'detail': detail,
        if (remediation != null) 'remediation': remediation,
      };
}

/// The complete result of `glide doctor`.
class DoctorReport {
  const DoctorReport({
    required this.checks,
    this.devices = const <FlutterDevice>[],
    this.lanAddresses = const <String>[],
    this.flutterVersion,
    this.dartVersion,
  });

  final List<DoctorCheck> checks;
  final List<FlutterDevice> devices;

  /// Private IPv4 addresses the companion could reach this machine on.
  final List<String> lanAddresses;

  final String? flutterVersion;
  final String? dartVersion;

  bool get hasErrors => checks.any((c) => c.status == CheckStatus.error);

  bool get hasWarnings => checks.any((c) => c.status == CheckStatus.warning);

  int get errorCount =>
      checks.where((c) => c.status == CheckStatus.error).length;

  Map<String, Object?> toJson() => <String, Object?>{
        'ready': !hasErrors,
        if (flutterVersion != null) 'flutterVersion': flutterVersion,
        if (dartVersion != null) 'dartVersion': dartVersion,
        'checks': checks.map((c) => c.toJson()).toList(),
        'devices': devices.map((d) => d.toJson()).toList(),
        'lanAddresses': lanAddresses,
      };
}
