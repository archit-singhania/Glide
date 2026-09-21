import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/features/session/session_notifier.dart';
import 'package:glide_companion/features/session/session_screen.dart';
import 'package:glide_companion/features/session/session_view.dart';
import 'package:glide_protocol/glide_protocol.dart';

GlideMessage _message(
  String type, [
  Map<String, Object?> payload = const <String, Object?>{},
]) =>
    GlideMessage.create(type, payload: payload);

const SessionView _running = SessionView(
  link: LinkStatus.connected,
  sessionState: 'running',
);

Map<String, Object?> _reasons(int count) => <String, Object?>{
      'count': count,
      'reasons': <Map<String, Object?>>[
        for (var i = 0; i < count; i++)
          <String, Object?>{
            'path': 'android/app/file$i.gradle',
            'impact': 'fullRestart',
            'reason': 'Android build configuration changed',
            'platform': 'android',
          },
      ],
    };

class _SeededNotifier extends SessionNotifier {
  _SeededNotifier(this.seed);

  final SessionView seed;
  int fullRestarts = 0;

  @override
  SessionView build() => seed;

  @override
  void fullRestart() => fullRestarts++;
}

Future<_SeededNotifier> _pump(WidgetTester tester, SessionView view) async {
  final notifier = _SeededNotifier(view);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sessionProvider.overrideWith(() => notifier)],
      child: const MaterialApp(home: SessionScreen()),
    ),
  );
  return notifier;
}

void main() {
  group('restart.required in reduceMessage', () {
    test('records the reasons', () {
      final view = reduceMessage(
        _running,
        _message(MessageTypes.restartRequired, _reasons(2)),
      );

      expect(view.needsFullRestart, isTrue);
      expect(view.restartReasons, hasLength(2));
      expect(view.restartReasons.first.path, 'android/app/file0.gradle');
      expect(
        view.restartReasons.first.reason,
        'Android build configuration changed',
      );
    });

    test('a later message replaces the list', () {
      final first = reduceMessage(
        _running,
        _message(MessageTypes.restartRequired, _reasons(2)),
      );

      final second = reduceMessage(
        first,
        _message(MessageTypes.restartRequired, _reasons(3)),
      );

      expect(second.restartReasons, hasLength(3));
    });

    test('malformed reasons are ignored', () {
      final view = reduceMessage(
        _running,
        _message(MessageTypes.restartRequired, <String, Object?>{
          'reasons': 'not a list',
        }),
      );

      expect(view.needsFullRestart, isFalse);
    });

    test('a snapshot restores or clears the reasons', () {
      final withReasons = reduceMessage(
        _running,
        _message(MessageTypes.sessionSnapshot, <String, Object?>{
          'state': 'running',
          'recentLogs': <Object?>[],
          ..._reasons(1),
        }),
      );
      expect(withReasons.needsFullRestart, isTrue);

      final without = reduceMessage(
        withReasons,
        _message(MessageTypes.sessionSnapshot, <String, Object?>{
          'state': 'running',
          'recentLogs': <Object?>[],
        }),
      );
      expect(without.needsFullRestart, isFalse);
    });

    test('a new build, a stopped app or a failed build clears them', () {
      final pending = reduceMessage(
        _running,
        _message(MessageTypes.restartRequired, _reasons(1)),
      );

      for (final type in <String>[
        MessageTypes.buildStarted,
        MessageTypes.appStopped,
        MessageTypes.buildFailed,
      ]) {
        expect(
          reduceMessage(pending, _message(type)).needsFullRestart,
          isFalse,
          reason: type,
        );
      }
    });

    test('only a completed full restart clears them, not a hot restart', () {
      final pending = reduceMessage(
        _running,
        _message(MessageTypes.restartRequired, _reasons(1)),
      );

      final afterHot = reduceMessage(
        pending,
        _message(MessageTypes.restartCompleted, <String, Object?>{
          'mode': 'hot',
        }),
      );
      final afterFull = reduceMessage(
        pending,
        _message(MessageTypes.restartCompleted, <String, Object?>{
          'mode': 'full',
        }),
      );

      expect(afterHot.needsFullRestart, isTrue);
      expect(afterFull.needsFullRestart, isFalse);
    });
  });

  group('restart banner', () {
    testWidgets('is hidden when nothing needs a full restart', (tester) async {
      await _pump(tester, _running);

      expect(find.text('Full restart required'), findsNothing);
    });

    testWidgets('shows the reasons and triggers a full restart', (
      tester,
    ) async {
      final notifier = await _pump(
        tester,
        _running.copyWith(
          restartReasons: const <RestartReason>[
            RestartReason(
              path: 'android/app/build.gradle',
              reason: 'Android build configuration changed',
            ),
          ],
        ),
      );

      expect(find.text('Full restart required'), findsOneWidget);
      expect(
        find.text(
          'android/app/build.gradle - Android build configuration changed',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Full restart now'));

      expect(notifier.fullRestarts, 1);
    });

    testWidgets('summarises reasons beyond the first two', (tester) async {
      await _pump(
        tester,
        _running.copyWith(
          restartReasons: const <RestartReason>[
            RestartReason(path: 'a.gradle', reason: 'x'),
            RestartReason(path: 'b.gradle', reason: 'x'),
            RestartReason(path: 'c.gradle', reason: 'x'),
            RestartReason(path: 'd.gradle', reason: 'x'),
          ],
        ),
      );

      expect(find.text('...and 2 more'), findsOneWidget);
    });

    testWidgets('the button is disabled while the app is not running', (
      tester,
    ) async {
      await _pump(
        tester,
        const SessionView(
          link: LinkStatus.connected,
          sessionState: 'building',
          restartReasons: <RestartReason>[
            RestartReason(path: 'pubspec.yaml', reason: 'changed'),
          ],
        ),
      );

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Full restart now'),
      );

      expect(button.onPressed, isNull);
    });
  });
}
