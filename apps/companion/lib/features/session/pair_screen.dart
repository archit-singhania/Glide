import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

import 'session_notifier.dart';
import 'session_view.dart';

/// Shows what was scanned and asks before connecting.
class PairScreen extends ConsumerWidget {
  const PairScreen({required this.payload, super.key});

  final PairingPayload payload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionProvider);
    ref.listen<SessionView>(sessionProvider, (previous, next) {
      if (next.link == LinkStatus.connected &&
          previous?.link != LinkStatus.connected) {
        context.go('/session');
      }
    });
    final pairing = view.link == LinkStatus.pairing;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to computer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text('Computer', style: theme.textTheme.labelLarge),
            Text(
              '${payload.host}:${payload.port}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text('Session', style: theme.textTheme.labelLarge),
            Text(payload.sessionId, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
              'Check that the same session ID is shown in your terminal. '
              'After you connect, the computer asks you to approve this '
              'phone.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: pairing
                  ? null
                  : () => ref.read(sessionProvider.notifier).connect(payload),
              child: Text(pairing ? 'Waiting for approval...' : 'Connect'),
            ),
            if (view.link == LinkStatus.failed && view.linkMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  view.linkMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
