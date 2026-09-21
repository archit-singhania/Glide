import 'package:qr/qr.dart';

/// Draws a QR code as text.
///
/// With [color] the code is drawn black-on-white using ANSI colours, which
/// scans correctly on both dark and light terminal themes. Without it the
/// glyphs use the terminal's own foreground colour, so on a dark theme the
/// code appears inverted; most phone scanners cope, but colour is safer.
///
/// With [unicode] two module rows share one text line (half blocks); without
/// it every module is two ASCII characters wide.
class QrRenderer {
  const QrRenderer({
    this.color = false,
    this.unicode = true,
    this.quietZone = 2,
  });

  final bool color;
  final bool unicode;

  /// Blank modules drawn around the code.
  final int quietZone;

  /// Renders [data]. Every line ends with a newline.
  String render(String data) {
    final image = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L),
    );
    final size = image.moduleCount;

    bool dark(int row, int column) {
      if (row < 0 || column < 0 || row >= size || column >= size) return false;
      return image.isDark(row, column);
    }

    final buffer = StringBuffer();
    final end = size + quietZone;
    if (unicode) {
      for (var y = -quietZone; y < end; y += 2) {
        final line = StringBuffer();
        for (var x = -quietZone; x < end; x++) {
          final top = dark(y, x);
          final bottom = dark(y + 1, x);
          line.write(
            top ? (bottom ? '█' : '▀') : (bottom ? '▄' : ' '),
          );
        }
        buffer.writeln(_wrap(line.toString()));
      }
    } else {
      for (var y = -quietZone; y < end; y++) {
        final line = StringBuffer();
        for (var x = -quietZone; x < end; x++) {
          line.write(dark(y, x) ? '##' : '  ');
        }
        buffer.writeln(_wrap(line.toString()));
      }
    }
    return buffer.toString();
  }

  String _wrap(String line) => color ? '\x1B[30;47m$line\x1B[0m' : line;
}
