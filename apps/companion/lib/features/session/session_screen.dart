import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:go_router/go_router.dart';

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
      appBar: AppBar(
        title: const Text('Glide'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.link_off),
            onPressed: () async {
              await notifier.disconnect();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _StatusCard(view: view),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
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
            if (!linked && view.link != LinkStatus.reconnecting)
              Padding(
                padding: const EdgeInsets.all(16),
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
            if (view.errors.isNotEmpty) _ErrorList(errors: view.errors),
            const Divider(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
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
            ),
            Expanded(child: _LogList(logs: view.logs)),
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
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.circle,
                  size: 12,
                  color: view.isLinked ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _linkLabel(view),
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                Text(view.sessionState, style: theme.textTheme.labelLarge),
              ],
            ),
            if (view.deviceId != null) ...<Widget>[
              const SizedBox(height: 8),
              Text('Device: ${view.deviceId}'),
            ],
            if (view.progress != null) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(view.progress!, style: theme.textTheme.bodySmall),
            ],
            if (view.notice != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(view.notice!, style: TextStyle(color: noticeColor)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorList extends StatelessWidget {
  const _ErrorList({required this.errors});

  final List<DiagnosticEvent> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          for (final error in errors.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (error.file != null)
                    Text(
                      '${error.file}'
                      '${error.line != null ? ':${error.line}' : ''}'
                      '${error.column != null ? ':${error.column}' : ''}',
                      style: theme.textTheme.labelMedium,
                    ),
                  Text(error.message),
                  Text(error.source, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LogList extends StatelessWidget {
  const _LogList({required this.logs});

  final List<LogEntry> logs;

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(child: Text('No log output yet.'));
    }
    final error = Theme.of(context).colorScheme.error;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final entry = logs[logs.length - 1 - index];
        return Text(
          entry.message,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: entry.level == LogLevel.error ? error : null,
          ),
        );
      },
    );
  }
}
