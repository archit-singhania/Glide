import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'change_classifier.dart';

/// Absolute paths of files that changed under a directory.
typedef PathEventSource = Stream<String> Function(String directory);

/// Watches [directory] with the operating system's file watcher.
///
/// Directory events are dropped. A move reports both its old and new path.
///
/// This is deliberately built from plain stream transformers rather than an
/// `async*` generator: cancelling a generator that is suspended on a quiet
/// watcher would not complete until the next file event, which would hang
/// shutdown.
Stream<String> systemPathEvents(String directory) => Directory(directory)
    .watch(recursive: true)
    .where((event) => !event.isDirectory)
    .expand(_pathsOf);

Iterable<String> _pathsOf(FileSystemEvent event) sync* {
  yield event.path;
  if (event is FileSystemMoveEvent) {
    final destination = event.destination;
    if (destination != null) yield destination;
  }
}

/// The relevant changes seen during one quiet period.
class ChangeBatch {
  const ChangeBatch(this.changes);

  /// One entry per file, sorted by path.
  final List<ProjectChange> changes;

  List<ProjectChange> get fullRestartChanges => <ProjectChange>[
        for (final change in changes)
          if (change.impact == ChangeImpact.fullRestart) change,
      ];

  bool get requiresFullRestart => fullRestartChanges.isNotEmpty;

  bool get hasDartChanges =>
      changes.any((change) => change.impact == ChangeImpact.hotReload);
}

/// Turns file system activity in a project into [ChangeBatch]es.
///
/// Events are classified with [ChangeClassifier], so build output and
/// generated files never produce a batch. Events that arrive close together
/// are merged: a batch is emitted once no relevant event has arrived for
/// [debounce].
class ProjectWatcher {
  ProjectWatcher({
    required this.projectRoot,
    PathEventSource? paths,
    this.debounce = const Duration(milliseconds: 400),
    this.onError,
  }) : _paths = paths ?? systemPathEvents;

  /// Longest [stop] waits for the underlying watcher to close. Shutdown must
  /// never hang because a native watcher is slow to cancel.
  static const Duration stopTimeout = Duration(seconds: 2);

  final String projectRoot;
  final Duration debounce;

  /// Called when the underlying watcher fails, for example when the project
  /// directory is deleted. Watching stops working after that.
  final void Function(Object error)? onError;

  final PathEventSource _paths;
  final StreamController<ChangeBatch> _controller =
      StreamController<ChangeBatch>.broadcast();
  final Map<String, ProjectChange> _pending = <String, ProjectChange>{};
  StreamSubscription<String>? _subscription;
  Timer? _timer;

  /// Subscribe before calling [start]; batches are not replayed.
  Stream<ChangeBatch> get batches => _controller.stream;

  void start() {
    if (_subscription != null) {
      throw StateError('ProjectWatcher is already started.');
    }
    // Cancelled in `stop()`; the analyzer cannot see across that method.
    // ignore: cancel_subscriptions
    _subscription = _paths(projectRoot).listen(
      _onPath,
      onError: (Object error) => onError?.call(error),
    );
  }

  void _onPath(String absolutePath) {
    final relative = p.relative(absolutePath, from: projectRoot);
    final change = ChangeClassifier.classify(
      p.posix.joinAll(p.split(relative)),
    );
    if (change == null) return;
    _pending[change.path] = change;
    _timer?.cancel();
    _timer = Timer(debounce, _flush);
  }

  void _flush() {
    if (_pending.isEmpty || _controller.isClosed) return;
    final changes = _pending.values.toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    _pending.clear();
    _controller.add(ChangeBatch(changes));
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    await _subscription?.cancel().timeout(stopTimeout, onTimeout: () {});
    _subscription = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
