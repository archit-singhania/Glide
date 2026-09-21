import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:glide_protocol/glide_protocol.dart';

/// Text shown by `glide start` while it waits for a companion.
class StartRenderer {
  const StartRenderer();

  /// The pairing token is only included, via the URI, when [showUri] is true.
  String render({
    required ProjectInfo project,
    required PairingPayload payload,
    required String qr,
    bool showUri = false,
  }) {
    final platforms = project.platforms.map((p) => p.label).toList()..sort();
    final buffer = StringBuffer()
      ..writeln('Glide - Flutter development, without friction.')
      ..writeln()
      ..writeln('Project    ${project.name}')
      ..writeln(
        'Platforms  ${platforms.isEmpty ? 'none detected' : platforms.join(', ')}',
      )
      ..writeln('Session    ${payload.sessionId}')
      ..writeln('Address    ${payload.host}:${payload.port}')
      ..writeln()
      ..writeln('Scan this QR code with the Glide companion app.')
      ..writeln()
      ..write(qr)
      ..writeln()
      ..writeln(
        'The code works once and expires at '
        '${_clock(payload.expiresAt.toLocal())}.',
      );
    if (showUri) {
      buffer
        ..writeln()
        ..writeln('Pairing link (secret until used - do not share it):')
        ..writeln(payload.toUri());
    }
    buffer
      ..writeln()
      ..writeln('Waiting for Glide companion... (Ctrl+C to stop)');
    return buffer.toString();
  }

  String _clock(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}
