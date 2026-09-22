import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

import '../../shared/glide_glass.dart';
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
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(context, title: 'Connect to computer'),
      body: GlideBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 24),
            children: <Widget>[
              GlassSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const GlassIconBadge(icon: Icons.laptop_mac),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Computer',
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                '${payload.host}:${payload.port}',
                                style: theme.textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      children: <Widget>[
                        const GlassIconBadge(icon: Icons.pin),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Session',
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                payload.sessionId,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Check that the same session ID is shown in your terminal. '
                'After you connect, the computer asks you to approve this '
                'phone.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: pairing
                    ? null
                    : () => ref.read(sessionProvider.notifier).connect(payload),
                child: pairing
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Waiting for approval...'),
                        ],
                      )
                    : const Text('Connect'),
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
      ),
    );
  }
}
