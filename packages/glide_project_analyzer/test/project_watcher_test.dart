import 'dart:async';
import 'dart:io';

import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String root;
  late StreamController<String> source;
  late ProjectWatcher watcher;
  final errors = <Object>[];

  setUp(() {
    root = p.join(Directory.systemTemp.path, 'glide_watch_project');
    source = StreamController<String>();
    errors.clear();
    watcher = ProjectWatcher(
      projectRoot: root,
      paths: (_) => source.stream,
      debounce: const Duration(milliseconds: 20),
      onError: errors.add,
    );
  });

  tearDown(() async {
    await watcher.stop();
    if (!source.isClosed) await source.close();
  });

  Future<ChangeBatch> nextBatch() =>
      watcher.batches.first.timeout(const Duration(seconds: 2));

  String at(String first, [String? second, String? third, String? fourth]) =>
      p.join(root, first, second, third, fourth);

  test('merges nearby events into one sorted batch', () async {
    watcher.start();
    final batch = nextBatch();

    source
      ..add(at('lib', 'main.dart'))
      ..add(at('lib', 'main.dart'))
      ..add(at('android', 'app', 'build.gradle'));
    final result = await batch;

    expect(
      result.changes.map((change) => change.path),
      <String>['android/app/build.gradle', 'lib/main.dart'],
    );
    expect(result.requiresFullRestart, isTrue);
    expect(result.hasDartChanges, isTrue);
    expect(
      result.fullRestartChanges.map((change) => change.path),
      <String>['android/app/build.gradle'],
    );
  });

  test('a Dart-only batch does not require a full restart', () async {
    watcher.start();
    final batch = nextBatch();

    source.add(at('lib', 'main.dart'));
    final result = await batch;

    expect(result.requiresFullRestart, isFalse);
    expect(result.hasDartChanges, isTrue);
  });

  test('build output and paths outside the project produce no batch', () async {
    watcher.start();
    var batches = 0;
    final subscription = watcher.batches.listen((_) => batches++);

    source
      ..add(at('build', 'app', 'out.apk'))
      ..add(at('android', 'local.properties'))
      ..add(
        p.join(Directory.systemTemp.path, 'somewhere_else', 'lib', 'a.dart'),
      );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(batches, 0);
    await subscription.cancel();
  });

  test('events after a quiet period start a new batch', () async {
    watcher.start();
    final first = nextBatch();
    source.add(at('pubspec.yaml'));
    expect((await first).changes.single.path, 'pubspec.yaml');

    final second = nextBatch();
    source.add(at('lib', 'other.dart'));
    expect((await second).changes.single.path, 'lib/other.dart');
  });

  test('watcher errors go to onError instead of escaping', () async {
    watcher.start();

    source.addError(const FileSystemException('directory removed'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(errors, hasLength(1));
    expect(errors.single, isA<FileSystemException>());
  });

  test('start twice is a programming error', () {
    watcher.start();

    expect(() => watcher.start(), throwsStateError);
  });

  test('stop cancels the underlying subscription', () async {
    watcher.start();
    expect(source.hasListener, isTrue);

    await watcher.stop();

    expect(source.hasListener, isFalse);
  });
}
