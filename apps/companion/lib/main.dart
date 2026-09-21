import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'core/companion_client.dart';
import 'core/message_channel.dart';
import 'features/session/session_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final deviceId = await loadOrCreateDeviceId(prefs);
  runApp(
    ProviderScope(
      overrides: [
        companionClientProvider.overrideWithValue(
          CompanionClient(connect: connectWebSocket, deviceId: deviceId),
        ),
      ],
      child: const GlideCompanionApp(),
    ),
  );
}
