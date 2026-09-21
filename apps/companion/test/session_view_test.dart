import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/features/session/session_view.dart';
import 'package:glide_protocol/glide_protocol.dart';

GlideMessage _msg(String type, [Map<String, Object?> payload = const {}]) =>
    GlideMessage.create(type, payload: payload);

SessionView _connected([String state = 'connected']) =>
    SessionView(link: LinkStatus.connected, sessionState: state);

void main() {
  group('reduceMessage', () {
    test('session.status updates the state', () {
      final next = reduceMessage(
        _connected(),
        _msg(MessageTypes.sessionStatus, {'state': 'building'}),
      );
      expect(next.sessionState, 'building');
    });

    test('session.snapshot restores state, device and recent logs', () {
      final log = LogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        level: LogLevel.info,
        source: 'app',
        message: 'hello',
      );
      final next = reduceMessage(
        _connected(),
        _msg(MessageTypes.sessionSnapshot, {
          'state': 'running',
          'deviceId': 'pixel-10',
          'recentLogs': [log.toJson()],
        }),
      );
      expect(next.sessionState, 'running');
      expect(next.deviceId, 'pixel-10');
      expect(next.logs.single.message, 'hello');
    });

    test('build.started clears old errors and shows progress', () {
      final withError = _connected().copyWith(
        errors: const [
          DiagnosticEvent(
            severity: DiagnosticSeverity.error,
            category: DiagnosticCategory.dart,
            source: 'Dart compiler',
            message: 'old',
          ),
        ],
      );
      final next = reduceMessage(
        withError,
        _msg(MessageTypes.buildStarted, {'deviceId': 'pixel-10'}),
      );
      expect(next.errors, isEmpty);
      expect(next.progress, isNotNull);
      expect(next.deviceId, 'pixel-10');
      expect(next.noticeIsError, isFalse);
    });

    test('build.progress updates the progress line', () {
      final next = reduceMessage(
        _connected('building'),
        _msg(MessageTypes.buildProgress, {'message': 'Running Gradle task'}),
      );
      expect(next.progress, 'Running Gradle task');
    });

    test('app.started records the app and clears progress', () {
      final building = _connected('building').copyWith(progress: 'Building');
      final next = reduceMessage(
        building,
        _msg(MessageTypes.appStarted, {'appId': 'app-1', 'deviceId': 'p'}),
      );
      expect(next.appId, 'app-1');
      expect(next.progress, isNull);
      expect(next.notice, 'App is running.');
    });

    test('build.failed reports the failure as an error', () {
      final next = reduceMessage(
        _connected('building').copyWith(progress: 'Building'),
        _msg(MessageTypes.buildFailed, {'message': 'Gradle failed'}),
      );
      expect(next.progress, isNull);
      expect(next.noticeIsError, isTrue);
      expect(next.notice, contains('Gradle failed'));
    });

    test('app.stopped forgets the app id', () {
      final running = _connected('running').copyWith(appId: 'app-1');
      final next = reduceMessage(running, _msg(MessageTypes.appStopped));
      expect(next.appId, isNull);
      expect(next.notice, 'App stopped.');
    });

    test('reload results include the duration or a failure', () {
      final ok = reduceMessage(
        _connected('running'),
        _msg(MessageTypes.reloadCompleted, {'durationMs': 42}),
      );
      expect(ok.notice, 'Hot reload completed in 42 ms.');
      expect(ok.noticeIsError, isFalse);

      final missing = reduceMessage(
        _connected('running'),
        _msg(MessageTypes.reloadCompleted),
      );
      expect(missing.notice, 'Hot reload completed in ? ms.');

      final failed = reduceMessage(
        _connected('running'),
        _msg(MessageTypes.reloadFailed, {'message': 'Syntax error'}),
      );
      expect(failed.noticeIsError, isTrue);
      expect(failed.notice, contains('Syntax error'));
    });

    test('restart results name the mode', () {
      final hot = reduceMessage(
        _connected('running'),
        _msg(MessageTypes.restartCompleted, {'mode': 'hot', 'durationMs': 7}),
      );
      expect(hot.notice, 'Hot restart completed in 7 ms.');

      final full = reduceMessage(
        _connected('running'),
        _msg(
          MessageTypes.restartCompleted,
          {'mode': 'full', 'durationMs': 1200},
        ),
      );
      expect(full.notice, 'Full restart completed in 1200 ms.');

      final failed = reduceMessage(
        _connected('running'),
        _msg(MessageTypes.restartFailed, {'mode': 'full', 'message': 'no'}),
      );
      expect(failed.noticeIsError, isTrue);
      expect(failed.notice, startsWith('Full restart failed'));
    });

    test('log.entry appends and the list is capped at 300', () {
      var view = _connected('running');
      for (var i = 0; i < 305; i++) {
        view = reduceMessage(
          view,
          _msg(MessageTypes.logEntry, {
            'timestamp': i,
            'level': 'info',
            'source': 'app',
            'message': 'line $i',
          }),
        );
      }
      expect(view.logs, hasLength(300));
      expect(view.logs.first.message, 'line 5');
      expect(view.logs.last.message, 'line 304');
    });

    test('logs.cleared empties the log', () {
      final withLog = reduceMessage(
        _connected(),
        _msg(MessageTypes.logEntry, {'message': 'x'}),
      );
      expect(withLog.logs, hasLength(1));
      final cleared = reduceMessage(withLog, _msg(MessageTypes.logsCleared));
      expect(cleared.logs, isEmpty);
    });

    test('error.reported keeps file, line and column', () {
      final next = reduceMessage(
        _connected('building'),
        _msg(MessageTypes.errorReported, {
          'severity': 'error',
          'category': 'dart',
          'source': 'Dart compiler',
          'message': "Undefined name 'userss'",
          'file': 'lib/pages/home.dart',
          'line': 82,
          'column': 5,
        }),
      );
      final error = next.errors.single;
      expect(error.file, 'lib/pages/home.dart');
      expect(error.line, 82);
      expect(error.column, 5);
      expect(error.category, DiagnosticCategory.dart);
    });

    test('command.rejected shows the host reason as an error', () {
      final next = reduceMessage(
        _connected(),
        _msg(MessageTypes.commandRejected, {'reason': 'No running app.'}),
      );
      expect(next.noticeIsError, isTrue);
      expect(next.notice, contains('No running app.'));
    });

    test('unknown message types leave the view unchanged', () {
      final view = _connected('running');
      final next = reduceMessage(view, _msg('performance.sample'));
      expect(next, same(view));
    });
  });

  group('SessionView availability', () {
    test('run is offered when idle, failed or disconnected from the app', () {
      expect(_connected('connected').canRun, isTrue);
      expect(_connected('failed').canRun, isTrue);
      expect(_connected('running').canRun, isFalse);
      expect(_connected('building').canRun, isFalse);
    });

    test('reload and restart need a running app', () {
      expect(_connected('running').canReload, isTrue);
      expect(_connected('reloading').canReload, isFalse);
      expect(_connected('connected').canReload, isFalse);
    });

    test('stop works while starting or running', () {
      for (final state in ['preparing', 'building', 'launching', 'running']) {
        expect(_connected(state).canStop, isTrue, reason: state);
      }
      expect(_connected('connected').canStop, isFalse);
    });

    test('nothing is offered when the link is down', () {
      const view = SessionView(
        link: LinkStatus.disconnected,
        sessionState: 'running',
      );
      expect(view.canRun, isFalse);
      expect(view.canReload, isFalse);
      expect(view.canStop, isFalse);
    });
  });
}
