import 'package:glide_build_manager/glide_build_manager.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';

/// Creates the file watcher for a project. [onError] is called when watching
/// stops working, for example because the project directory was deleted.
typedef ProjectWatcherFactory = ProjectWatcher Function(
  String projectRoot,
  void Function(Object error) onError,
);

/// The real thing: the operating system's recursive file watcher.
ProjectWatcher createSystemProjectWatcher(
  String projectRoot,
  void Function(Object error) onError,
) =>
    ProjectWatcher(projectRoot: projectRoot, onError: onError);

/// Starts [watcher] and reports every change that needs a full restart to
/// [controller]. Returns a function that stops watching.
Future<void> Function() watchForRestartNeeds({
  required ProjectWatcher watcher,
  required SessionController controller,
}) {
  final subscription = watcher.batches.listen((batch) {
    final changes = batch.fullRestartChanges;
    if (changes.isNotEmpty) controller.reportProjectChanges(changes);
  });
  watcher.start();
  return () async {
    await subscription.cancel();
    await watcher.stop();
  };
}
