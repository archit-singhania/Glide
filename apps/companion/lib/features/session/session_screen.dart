import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

import '../../shared/glide_glass.dart';
import 'session_notifier.dart';
import 'session_view.dart';

/// Dashboard for a paired session: controls, latest result, errors and logs.
class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sessionProvider);
    final notifier = ref.read(sessionProvider.notifier);
    final theme = Theme.of(context);
    final linked = view.isLinked;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(
        context,
        title: 'Glide',
        actions: <Widget>[
          IconButton(
            tooltip: 'Open DevTools on computer',
            icon: const Icon(Icons.developer_mode),
            onPressed: view.canOpenDevTools ? notifier.openDevTools : null,
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Network',
            icon: const Icon(Icons.swap_vert),
            onPressed:
                view.network.isEmpty ? null : () => _showNetwork(context),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.link_off),
            onPressed: () async {
              await notifier.disconnect();
              if (context.mounted) context.go('/');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GlideBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 24),
            children: <Widget>[
              _StatusCard(view: view),
              const SizedBox(height: 16),
              GlassSurface(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: view.canRun ? notifier.run : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Run'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: view.canReload ? notifier.hotReload : null,
                      icon: const Icon(Icons.bolt),
                      label: const Text('Hot reload'),
                    ),
                    OutlinedButton(
                      onPressed: view.canReload ? notifier.hotRestart : null,
                      child: const Text('Hot restart'),
                    ),
                    OutlinedButton(
                      onPressed: view.canReload ? notifier.fullRestart : null,
                      child: const Text('Full restart'),
                    ),
                    OutlinedButton.icon(
                      onPressed: view.canStop ? notifier.stopApp : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                  ],
                ),
              ),
              if (view.needsFullRestart) ...<Widget>[
                const SizedBox(height: 16),
                _RestartBanner(
                  reasons: view.restartReasons,
                  onRestart: view.canReload ? notifier.fullRestart : null,
                ),
              ],
              if (!linked && view.link != LinkStatus.reconnecting) ...[
                const SizedBox(height: 16),
                GlassSurface(
                  strong: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (view.linkMessage != null)
                        Text(
                          view.linkMessage!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      if (notifier.canReconnect)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: FilledButton.tonal(
                            onPressed: notifier.reconnect,
                            child: const Text('Reconnect'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (view.errors.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                _ErrorList(errors: view.errors),
              ],
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.terminal,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text('Logs', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: linked && view.logs.isNotEmpty
                        ? notifier.clearLogs
                        : null,
                    child: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GlassSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: SizedBox(
                  height: 260,
                  child: _LogList(logs: view.logs),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _performanceLine(PerformanceView performance) =>
    '${performance.fps.toStringAsFixed(1)} fps - '
    '${performance.frameTimeMs.toStringAsFixed(1)} ms/frame - '
    '${performance.jankyFrames} janky - '
    '${performance.memoryLabel}';

void _showNetwork(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NetworkSheet(),
  );
}

/// The app's recent HTTP requests, newest first. Updates while open.
class _NetworkSheet extends ConsumerWidget {
  const _NetworkSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calls = ref.watch(sessionProvider.select((view) => view.network));
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.swap_vert, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Network', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
            Expanded(
              child: calls.isEmpty
                  ? const Center(child: Text('No requests yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: calls.length,
                      itemBuilder: (context, index) {
                        final call = calls[calls.length - 1 - index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              '${call.method} ${call.url}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              call.summary,
                              style: call.failed
                                  ? TextStyle(color: theme.colorScheme.error)
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _linkLabel(SessionView view) {
  if (view.isLinked) return 'Connected';
  if (view.link == LinkStatus.reconnecting) return 'Reconnecting...';
  return 'Disconnected';
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.view});

  final SessionView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final noticeColor = view.noticeIsError
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return GlassSurface(
      strong: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              StatusDot(
                color: view.isLinked ? Colors.greenAccent : Colors.grey,
              ),
              const SizedBox(width: 10),
              Text(_linkLabel(view), style: theme.textTheme.titleSmall),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  view.sessionState,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (view.deviceId != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(
                  Icons.phone_iphone,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text('Device: ${view.deviceId}'),
              ],
            ),
          ],
          if (view.progress != null) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: const LinearProgressIndicator(minHeight: 6),
            ),
            const SizedBox(height: 6),
            Text(view.progress!, style: theme.textTheme.bodySmall),
          ],
          if (view.notice != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(view.notice!, style: TextStyle(color: noticeColor)),
          ],
          if (view.performance != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(
                  Icons.speed,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  _performanceLine(view.performance!),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown when files changed that hot reload cannot apply.
class _RestartBanner extends StatelessWidget {
  const _RestartBanner({required this.reasons, required this.onRestart});

  final List<RestartReason> reasons;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = glideTokens(context);
    final shown = reasons.take(2).toList();
    return GlassSurface(
      strong: true,
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassIconBadge(
                icon: Icons.restart_alt,
                size: 36,
                color: tokens.glowSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Full restart required',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text('Hot reload cannot apply these changes:'),
          const SizedBox(height: 4),
          for (final reason in shown)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${reason.path} - ${reason.reason}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (reasons.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '...and ${reasons.length - shown.length} more',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onRestart,
              child: const Text('Full restart now'),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _severityIcon(DiagnosticSeverity severity) => switch (severity) {
      DiagnosticSeverity.info => Icons.info_outline,
      DiagnosticSeverity.warning => Icons.warning_amber_rounded,
      DiagnosticSeverity.error => Icons.error_outline,
      DiagnosticSeverity.fatal => Icons.dangerous_outlined,
    };

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.errors});

  final List<DiagnosticEvent> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      strong: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: <Widget>[
            for (final error in errors.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        _severityIcon(error.severity),
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (error.file != null)
                            Text(
                              '${error.file}'
                              '${error.line != null ? ':${error.line}' : ''}'
                              '${error.column != null ? ':${error.column}' : ''}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.error,
                                fontFamily: 'monospace',
                              ),
                            ),
                          Text(error.message),
                          Text(
                            error.source,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_all_outlined),
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text: <String>[
                            if (error.file != null)
                              '${error.file}:${error.line ?? ''}',
                            error.message,
                            if (error.stackTrace != null) error.stackTrace!,
                          ].join('\n'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color? _logColor(BuildContext context, LogLevel level) {
  final scheme = Theme.of(context).colorScheme;
  final tokens = glideTokens(context);
  return switch (level) {
    LogLevel.error => scheme.error,
    LogLevel.warning => tokens.glowSecondary,
    LogLevel.trace || LogLevel.debug => scheme.onSurfaceVariant.withValues(
        alpha: 0.65,
      ),
    LogLevel.info => null,
  };
}

class _LogList extends StatelessWidget {
  const _LogList({required this.logs});

  final List<LogEntry> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(child: Text('No log output yet.'));
    }
    return ListView.builder(
      reverse: true,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final entry = logs[logs.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            TextSpan(
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              children: <InlineSpan>[
                if (entry.level == LogLevel.error ||
                    entry.level == LogLevel.warning)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        entry.level == LogLevel.error
                            ? Icons.error_outline
                            : Icons.warning_amber_rounded,
                        size: 13,
                        color: _logColor(context, entry.level),
                      ),
                    ),
                  ),
                TextSpan(
                  text: entry.message,
                  style: TextStyle(color: _logColor(context, entry.level)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
