import 'package:glide_performance/glide_performance.dart';
import 'package:test/test.dart';

void main() {
  group('PerformanceSample.fromWindow', () {
    test('computes fps and average frame time from a window of frames', () {
      final sample = PerformanceSample.fromWindow(
        frames: const <FrameTiming>[
          FrameTiming(buildUs: 4000, rasterUs: 4000), // 8ms, not janky
          FrameTiming(buildUs: 5000, rasterUs: 5000), // 10ms, not janky
        ],
        window: const Duration(seconds: 2),
        timestamp: DateTime.utc(2026),
      );

      expect(sample.frameCount, 2);
      expect(sample.fps, 1.0); // 2 frames / 2 seconds
      expect(sample.avgFrameTimeMs, closeTo(9.0, 0.001));
      expect(sample.jankyFrameCount, 0);
      expect(sample.hasMemory, isFalse);
    });

    test('counts a frame over the 60fps budget as janky', () {
      final sample = PerformanceSample.fromWindow(
        frames: const <FrameTiming>[
          FrameTiming(buildUs: 10000, rasterUs: 10000), // 20ms, janky
          FrameTiming(buildUs: 3000, rasterUs: 3000), // 6ms, fine
        ],
        window: const Duration(seconds: 1),
        timestamp: DateTime.utc(2026),
      );

      expect(sample.jankyFrameCount, 1);
    });

    test('an empty window reports zero fps rather than dividing by zero', () {
      final sample = PerformanceSample.fromWindow(
        frames: const <FrameTiming>[],
        window: const Duration(seconds: 2),
        timestamp: DateTime.utc(2026),
      );

      expect(sample.frameCount, 0);
      expect(sample.fps, 0.0);
      expect(sample.avgFrameTimeMs, 0.0);
      expect(sample.jankyFrameCount, 0);
    });

    test('carries memory readings through when given', () {
      final sample = PerformanceSample.fromWindow(
        frames: const <FrameTiming>[],
        window: const Duration(seconds: 2),
        timestamp: DateTime.utc(2026),
        memory: const MemoryUsage(
          heapUsageBytes: 1024,
          heapCapacityBytes: 4096,
          externalUsageBytes: 256,
        ),
      );

      expect(sample.hasMemory, isTrue);
      expect(sample.heapUsageBytes, 1024);
      expect(sample.heapCapacityBytes, 4096);
      expect(sample.externalUsageBytes, 256);
    });

    test('toJson omits memory fields when there is no reading', () {
      final sample = PerformanceSample.fromWindow(
        frames: const <FrameTiming>[],
        window: const Duration(seconds: 2),
        timestamp: DateTime.utc(2026),
      );

      final json = sample.toJson();
      expect(json.containsKey('heapUsageBytes'), isFalse);
      expect(json['frameCount'], 0);
      expect(json['fps'], 0.0);
    });

    test('toJson rounds fps and frame time to one decimal place', () {
      final sample = PerformanceSample.fromWindow(
        frames: const <FrameTiming>[
          FrameTiming(buildUs: 3333, rasterUs: 3334),
        ],
        window: const Duration(milliseconds: 900),
        timestamp: DateTime.utc(2026),
      );

      final json = sample.toJson();
      expect(json['fps'], closeTo(1.1, 0.05));
      expect(json['frameTimeMs'], closeTo(6.7, 0.05));
    });
  });
}
