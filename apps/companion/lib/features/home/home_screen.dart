import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

import '../../core/recent_sessions.dart';
import '../../shared/glide_glass.dart';
import '../session/session_notifier.dart';

/// Start screen: scan the QR code, or paste the pairing link.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _link = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _connectWithLink() {
    try {
      final payload = PairingPayload.parse(_link.text);
      setState(() => _error = null);
      context.push('/pair', extra: payload);
    } on ProtocolException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = glideTokens(context);
    final recents = ref.watch(recentSessionsProvider).load();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(context, title: ''),
      body: GlideBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 24),
            children: <Widget>[
              ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: <Color>[tokens.glowPrimary, tokens.glowSecondary],
                ).createShader(bounds),
                child: Text(
                  'Glide',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Flutter development, without friction.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              GlassSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const GlassIconBadge(icon: Icons.qr_code_scanner),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'On your computer, run "glide start" in your '
                            'Flutter project, then scan the QR code it '
                            'shows.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => context.push('/scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR code'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const GlassIconBadge(icon: Icons.link),
                        const SizedBox(width: 14),
                        Text('No camera?', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Run "glide start --print-uri" and paste the pairing '
                      'link. It is secret until used, so do not share it.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _link,
                      decoration: InputDecoration(
                        labelText: 'Pairing link',
                        hintText: 'glide://pair?...',
                        errorText: _error,
                      ),
                      autocorrect: false,
                      enableSuggestions: false,
                      onSubmitted: (_) => _connectWithLink(),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _connectWithLink,
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
              if (recents.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _RecentSessionsCard(
                  recents: recents,
                  onForget: (session) {
                    unawaited(
                      ref.read(recentSessionsProvider).remove(
                            host: session.host,
                            port: session.port,
                          ),
                    );
                    setState(() {});
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Computers this phone has connected to before. Purely informational —
/// tapping one jumps straight to the scanner, since a pairing token is
/// always single-use and Glide never stores one, so nothing here can skip
/// scanning a fresh QR code.
class _RecentSessionsCard extends StatelessWidget {
  const _RecentSessionsCard({required this.recents, required this.onForget});

  final List<RecentSession> recents;
  final ValueChanged<RecentSession> onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.history,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('Recent', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          for (final session in recents)
            Dismissible(
              key: ValueKey('${session.host}:${session.port}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => onForget(session),
              background: const SizedBox.shrink(),
              secondaryBackground: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
              ),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.laptop_mac, size: 20),
                title: Text(session.label),
                subtitle: Text(relativeTimeLabel(session.connectedAt)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => context.push('/scan'),
              ),
            ),
        ],
      ),
    );
  }
}
