import 'dart:async';
import 'dart:io';

import 'package:glide_build_manager/testing.dart';
import 'package:glide_cli/glide_cli.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeAnalyzer implements ProjectAnalyzer {
  @override
  Future<ProjectInfo> analyze(String directory) async => ProjectInfo(
        name: 'shop_app',
        rootPath: directory,
        platforms: <ProjectPlatform>{ProjectPlatform.android},
      );
}

Future<void> _waitFor(StringBuffer out, String needle) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!out.toString().contains(needle)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for "$needle". Output so far:\n$out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory project;
  late StringBuffer out;
  late StringBuffer err;
  late StreamController<String> keys;
  late StreamController<String> changedPaths;
  late Completer<void> interrupt;
  late List<FakeAppSession> sessions;

  setUp(() {
    project = Directory.systemTemp.createTempSync('glide_restart_');
    File(p.join(project.path, 'pubspec.yaml'))
        .writeAsStringSync('name: shop_app\n');
    out = StringBuffer();
    err = StringBuffer();
    keys = StreamController<String>();
    changedPaths = StreamController<String>();
    interrupt = Completer<void>();
    sessions = <FakeAppSession>[];
  });

  tearDown(() {
    unawaited(keys.close());
    unawaited(changedPaths.close());
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  RunEnvironment environment() => RunEnvironment(
        launchApp: ({
          required String projectPath,
          required String deviceId,
          String? flutterSdkPath,
          AppMode? mode,
        }) async {
          final session = FakeAppSession();
          sessions.add(session);
          return session;
        },
        chooseDevice: ({String? flutterSdkPath}) async => null,
        keys: () => keys.stream,
        shutdown: () => interrupt.future,
        createWatcher: (root, onError) => ProjectWatcher(
          projectRoot: root,
          paths: (_) => changedPaths.stream,
          debounce: const Duration(milliseconds: 20),
          onError: onError,
        ),
      );

  Future<int> run() => runGlide(
        <String>['run', '--device', 'pixel-1'],
        out: out,
        err: err,
        analyzer: _FakeAnalyzer(),
        workingDirectory: project.path,
        runEnvironment: environment(),
      );

  Future<FakeAppSession> waitForSession(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (sessions.length < count) {
      if (DateTime.now().isAfter(deadline)) fail('Session $count not started.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return sessions[count - 1];
  }

  test('a native change prints a notice and F performs the full restart',
      () async {
    final done = run();
    final first = await waitForSession(1);
    first.markStarted();
    await _waitFor(out, 'App running on');

    final manifest = p.joinAll(<String>[
      project.path,
      'android',
      'app',
      'src',
      'main',
      'AndroidManifest.xml',
    ]);
    changedPaths.add(manifest);
    await _waitFor(out, 'Press F for a full restart.');
    expect(
      out.toString(),
      contains('android/app/src/main/AndroidManifest.xml - '
          'AndroidManifest.xml changed'),
    );

    keys.add('F');
    final second = await waitForSession(2);
    second.markStarted(appId: 'app-2');
    await _waitFor(out, 'Full restart completed in');
    expect(first.stopped, isTrue);
    expect(second.stopped, isFalse);

    keys.add('q');
    expect(await done, 0);
  });

  test('Dart-only changes print nothing', () async {
    final done = run();
    final session = await waitForSession(1);
    session.markStarted();
    await _waitFor(out, 'App running on');

    changedPaths.add(p.join(project.path, 'lib', 'main.dart'));
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // The key legend printed on startup legitimately contains the substring
    // "full restart" ("F full restart"), so this checks for the distinct
    // restart-required notice text instead of that substring.
    expect(out.toString(), isNot(contains('Press F for a full restart.')));
    expect(out.toString(), isNot(contains('Hot reload cannot apply')));

    keys.add('q');
    expect(await done, 0);
  });

  test('a watcher failure is reported without stopping the app', () async {
    final done = run();
    final session = await waitForSession(1);
    session.markStarted();
    await _waitFor(out, 'App running on');

    changedPaths.addError(const FileSystemException('gone'));
    await _waitFor(err, 'watching for file changes stopped');

    keys.add('q');
    expect(await done, 0);
  });
}
