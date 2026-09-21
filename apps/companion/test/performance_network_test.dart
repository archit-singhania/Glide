import 'package:flutter_test/flutter_test.dart';
import 'package:glide_companion/features/session/session_view.dart';
import 'package:glide_protocol/glide_protocol.dart';

GlideMessage _msg(String type, [Map<String, Object?> payload = const {}]) =>
    GlideMessage.create(type, payload: payload);

const SessionView _running = SessionView(
  link: LinkStatus.connected,
  sessionState: 'running',
);

void main() {
  group('performance', () {
    test('a sample becomes the latest reading', () {
      final view = reduceMessage(
        _running,
        _msg(MessageTypes.performanceSample, <String, Object?>{
          'fps': 59.8,
          'frameTimeMs': 8.2,
          'jankyFrameCount': 3,
          'heapUsageBytes': 190 * 1024 * 1024,
        }),
      );

      final performance = view.performance!;
      expect(performance.fps, 59.8);
      expect(performance.frameTimeMs, 8.2);
      expect(performance.jankyFrames, 3);
      expect(performance.memoryLabel, '190 MB');
    });

    test('a sample without memory says so instead of showing zero', () {
      final view = reduceMessage(
        _running,
        _msg(MessageTypes.performanceSample, <String, Object?>{
          'fps': 0,
          'frameTimeMs': 0,
          'jankyFrameCount': 0,
        }),
      );

      expect(view.performance!.memoryLabel, 'n/a');
    });

    test('a snapshot restores it, and a snapshot without one clears it', () {
      final restored = reduceMessage(
        _running,
        _msg(MessageTypes.sessionSnapshot, <String, Object?>{
          'state': 'running',
          'performance': <String, Object?>{'fps': 30.0, 'frameTimeMs': 20.0},
        }),
      );
      expect(restored.performance!.fps, 30.0);

      final cleared = reduceMessage(
        restored,
        _msg(MessageTypes.sessionSnapshot, <String, Object?>{
          'state': 'connected',
        }),
      );
      expect(cleared.performance, isNull);
    });

    test('is cleared when the app stops and when a new build starts', () {
      final withPerformance = reduceMessage(
        _running,
        _msg(MessageTypes.performanceSample, <String, Object?>{'fps': 60.0}),
      );

      expect(
        reduceMessage(withPerformance, _msg(MessageTypes.appStopped))
            .performance,
        isNull,
      );
      expect(
        reduceMessage(withPerformance, _msg(MessageTypes.buildStarted))
            .performance,
        isNull,
      );
    });
  });

  group('network', () {
    Map<String, Object?> call(String id, {int? status = 200}) =>
        <String, Object?>{
          'id': id,
          'method': 'GET',
          'url': 'https://api.example.com/users',
          if (status != null) 'statusCode': status,
          'durationMs': 342,
          'sizeBytes': 18300,
          'failed': status == null,
        };

    test('a completed request is added and summarised', () {
      final view = reduceMessage(
        _running,
        _msg(MessageTypes.networkResponse, call('1')),
      );

      final entry = view.network.single;
      expect(entry.method, 'GET');
      expect(entry.url, 'https://api.example.com/users');
      expect(entry.failed, isFalse);
      expect(entry.summary, '200 - 342 ms - 17.9 KB');
    });

    test('a request without a status is shown as failed', () {
      final view = reduceMessage(
        _running,
        _msg(MessageTypes.networkResponse, call('1', status: null)),
      );

      expect(view.network.single.failed, isTrue);
      expect(view.network.single.summary, startsWith('failed'));
    });

    test('keeps only the most recent requests', () {
      var view = _running;
      for (var i = 0; i < 130; i++) {
        view = reduceMessage(
          view,
          _msg(MessageTypes.networkResponse, call('r$i')),
        );
      }

      expect(view.network, hasLength(100));
      expect(view.network.first.id, 'r30');
      expect(view.network.last.id, 'r129');
    });

    test('a new build clears the list', () {
      final view = reduceMessage(
        reduceMessage(_running, _msg(MessageTypes.networkResponse, call('1'))),
        _msg(MessageTypes.buildStarted),
      );

      expect(view.network, isEmpty);
    });
  });

  group('devtools', () {
    test('opened and failed become notices', () {
      final opened = reduceMessage(_running, _msg(MessageTypes.devtoolsOpened));
      expect(opened.notice, contains('DevTools opened'));
      expect(opened.noticeIsError, isFalse);

      final failed = reduceMessage(
        _running,
        _msg(MessageTypes.devtoolsFailed, <String, Object?>{
          'message': 'DevTools could not be started (StateError).',
        }),
      );
      expect(failed.notice, contains('could not be started'));
      expect(failed.noticeIsError, isTrue);
    });

    test('can only be requested while the app is running', () {
      expect(_running.canOpenDevTools, isTrue);
      expect(
        const SessionView(
          link: LinkStatus.connected,
          sessionState: 'building',
        ).canOpenDevTools,
        isFalse,
      );
      expect(
        const SessionView(
          link: LinkStatus.disconnected,
          sessionState: 'running',
        ).canOpenDevTools,
        isFalse,
      );
    });
  });
}
