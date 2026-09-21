import 'dart:async';
import 'dart:io';

import 'package:glide_build_manager/testing.dart';
import 'package:glide_cli/glide_cli.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
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
  late Completer<void> interrupt;
  late List<FakeAppSession> sessions;
  late List<String> launchedDevices;
  Object? launchError;
  String? chosenDevice;

  setUp(() {
    project = Directory.systemTemp.createTempSync('glide_run_');
    File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: shop_app\n');
    out = StringBuffer();
    err = StringBuffer();
    keys = StreamController<String>();
    interrupt = Completer<void>();
    sessions = <FakeAppSession>[];
    launchedDevices = <String>[];
    launchError = null;
    chosenDevice = null;
  });

  tearDown(() {
    // Not awaited: close() only completes once a listener has consumed the
    // stream, and some tests never reach the point of listening.
    unawaited(keys.close());
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  RunEnvironment environment() => RunEnvironment(
        launchApp: ({
          required String projectPath,
          required String deviceId,
          String? flutterSdkPath,
          AppMode? mode,
        }) async {
          final error = launchError;
          if (error != null) throw error;
          launchedDevices.add(deviceId);
          final session = FakeAppSession();
          sessions.add(session);
          return session;
        },
        chooseDevice: ({String? flutterSdkPath}) async => chosenDevice,
        keys: () => keys.stream,
        shutdown: () => interrupt.future,
      );

  Future<int> run(List<String> args) => runGlide(
        <String>['run', ...args],
        out: out,
        err: err,
        analyzer: _FakeAnalyzer(),
        workingDirectory: project.path,
        runEnvironment: environment(),
      );

  Future<FakeAppSession> waitForSession() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (sessions.isEmpty) {
      if (DateTime.now().isAfter(deadline)) fail('The app was never launched.');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return sessions.single;
  }

  group('glide run', () {
    test('runs on the named device, reloads on r, and quits on q', () async {
      final done = run(<String>['--device', 'pixel-1']);

      final session = await waitForSession();
      session.markStarted();
      await _waitFor(out, 'App running on');
      expect(launchedDevices, <String>['pixel-1']);
      expect(out.toString(), contains('r hot reload'));

      keys.add('r');
      await _waitFor(out, 'Hot reload completed in 42 ms.');
      expect(session.reloadCalls, 1);

      keys.add('R');
      await _waitFor(out, 'Hot restart completed in 120 ms.');
      expect(session.restartCalls, 1);

      keys.add('q');
      expect(await done, 0);
      expect(session.stopped, isTrue);
      expect(out.toString(), contains('App stopped.'));
    });

    test('chooses the device automatically when none is given', () async {
      chosenDevice = 'emulator-5554';
      final done = run(<String>[]);

      final session = await waitForSession();
      session.markStarted();
      await _waitFor(out, 'App running on');
      expect(launchedDevices, <String>['emulator-5554']);

      keys.add('q');
      expect(await done, 0);
    });

    test('Ctrl+C stops the app and exits cleanly', () async {
      final done = run(<String>['--device', 'pixel-1']);
      final session = await waitForSession();
      session.markStarted();
      await _waitFor(out, 'App running on');

      interrupt.complete();

      expect(await done, 0);
      expect(session.stopped, isTrue);
      expect(out.toString(), contains('Stopping...'));
    });

    test('reload with the wrong state is reported, not fatal', () async {
      final done = run(<String>['--device', 'pixel-1']);
      final session = await waitForSession();

      keys.add('r');
      await _waitFor(out, 'Cannot do that: No running app to reload.');
      expect(session.reloadCalls, 0);

      keys.add('q');
      expect(await done, 0);
    });

    test('a failed build exits with code 1', () async {
      launchError = ToolNotFoundException('flutter');

      final code = await run(<String>['--device', 'pixel-1']);

      expect(code, 1);
      expect(out.toString(), contains('Build failed'));
    });

    test('the tool exiting during the build exits with code 1', () async {
      final done = run(<String>['--device', 'pixel-1']);
      final session = await waitForSession();

      session.crash(1);

      expect(await done, 1);
      expect(out.toString(), contains('Build failed'));
    });

    test('fails clearly when no device can be chosen', () async {
      final code = await run(<String>[]);

      expect(code, 1);
      expect(err.toString(), contains('--device'));
      expect(launchedDevices, isEmpty);
    });

    test('refuses an unsafe device id', () async {
      final code = await run(<String>['--device', r'pixel; rm -rf /']);

      expect(code, 1);
      expect(err.toString(), contains('--device'));
      expect(launchedDevices, isEmpty);
    });

    test('fails clearly outside a project', () async {
      final empty = Directory.systemTemp.createTempSync('glide_run_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));

      final code = await runGlide(
        <String>['run', '--device', 'pixel-1'],
        out: out,
        err: err,
        analyzer: _FakeAnalyzer(),
        workingDirectory: empty.path,
        runEnvironment: environment(),
      );

      expect(code, 1);
      expect(err.toString(), contains('pubspec.yaml'));
    });

    test('terminal output from the app has control characters removed',
        () async {
      final done = run(<String>['--device', 'pixel-1']);
      final session = await waitForSession();
      session.markStarted();
      await _waitFor(out, 'App running on');

      session.emit(
        const AppLog(
          appId: 'app-1',
          message: '\u001b[2Jhello',
          isError: false,
        ),
      );
      await _waitFor(out, 'hello');
      expect(out.toString(), isNot(contains('\u001b')));

      keys.add('q');
      expect(await done, 0);
    });
  });
}
