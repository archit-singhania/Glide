import '../services/doctor_report.dart';

/// Formats a [DoctorReport] for the terminal.
///
/// Colour and Unicode symbols are opt-in so output stays readable in pipes,
/// CI logs and legacy Windows consoles.
class DoctorRenderer {
  const DoctorRenderer({this.color = false, this.unicode = true});

  final bool color;
  final bool unicode;

  String render(DoctorReport report) {
    final out = StringBuffer()
      ..writeln(_paint('Glide Doctor', _bold))
      ..writeln();

    var width = 0;
    for (final check in report.checks) {
      if (check.title.length > width) width = check.title.length;
    }

    for (final check in report.checks) {
      final line = '  ${_symbol(check.status)} '
          '${check.title.padRight(width)}  ${check.detail ?? ''}';
      out.writeln(line.trimRight());
      final fix = check.remediation;
      if (fix != null && check.status != CheckStatus.ok) {
        out.writeln('      ${' ' * width}${_paint('$_arrow $fix', _dim)}');
      }
    }

    if (report.devices.isNotEmpty) {
      out
        ..writeln()
        ..writeln(_paint('Devices', _bold));
      for (final device in report.devices) {
        final kind = device.isEmulator
            ? '${device.platform}, emulator'
            : device.platform;
        out.writeln('  ${device.name}  ($kind)  ${device.id}');
      }
    }

    if (report.lanAddresses.isNotEmpty) {
      out
        ..writeln()
        ..writeln(_paint('LAN addresses', _bold))
        ..writeln('  ${report.lanAddresses.join(', ')}');
    }

    out.writeln();
    final errors = report.errorCount;
    if (errors > 0) {
      out.writeln(
        _paint(
          '$errors problem${errors == 1 ? '' : 's'} must be fixed before '
          'running "glide start".',
          _red,
        ),
      );
    } else if (report.hasWarnings) {
      out.writeln(_paint('Environment ready, with warnings.', _yellow));
    } else {
      out.writeln(_paint('Environment ready.', _green));
    }
    return out.toString();
  }

  static const String _bold = '1';
  static const String _dim = '2';
  static const String _red = '31';
  static const String _green = '32';
  static const String _yellow = '33';

  String get _arrow => unicode ? '\u2192' : '->';

  String _paint(String text, String code) =>
      color ? '\x1B[${code}m$text\x1B[0m' : text;

  String _symbol(CheckStatus status) {
    switch (status) {
      case CheckStatus.ok:
        return _paint(unicode ? '\u2713' : '[ok]', _green);
      case CheckStatus.warning:
        return _paint(unicode ? '!' : '[!]', _yellow);
      case CheckStatus.error:
        return _paint(unicode ? '\u2717' : '[x]', _red);
      case CheckStatus.skipped:
        return _paint(unicode ? '-' : '[-]', _dim);
    }
  }
}
