import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/core/companion_client.dart';
import 'package:glide_companion/core/message_channel.dart';
import 'package:glide_protocol/glide_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pairs and receives a session snapshot from the local Glide host',
      () async {
    final pairingLink =
        File('/private/tmp/glide-pairing-uri').readAsStringSync().trim();
    final payload = PairingPayload.parse(pairingLink);
    final client = CompanionClient(
      connect: connectWebSocket,
      deviceId: 'codex-local-smoke',
      deviceName: 'Mac pairing check',
    );

    final grant = await client.pair(payload);
    final channel = await client.openSession(
      payload.host,
      payload.port,
      grant,
    );
    try {
      channel.send(GlideMessage.create('diagnostics.request').encode());
      final reply = GlideMessage.decode(
        await channel.incoming.first.timeout(const Duration(seconds: 10)),
      );
      expect(reply.type, MessageTypes.sessionSnapshot);
    } finally {
      await channel.close();
    }
  });
}
