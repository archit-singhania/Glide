import 'dart:async';

import 'package:glide_performance/glide_performance.dart';
import 'package:test/test.dart';

/// A [VmServiceClient] test double. Nothing here touches a real VM service.
class _FakeVmServiceClient implements VmServiceClient {
  _FakeVmServiceClient() : isolateId = 'isolate-1';

  final String? isolateId;
  final StreamController<FrameTiming> _frames =
      StreamController<FrameTiming>.broadcast();

  /// Thrown by [getMainIsolateId] when set.
  Object? isolateIdError;

  /// Thrown by [getMemoryUsage] when set. Cleared automatically after one
  /// use, so a test can fail exactly one tick's reading.
  Object? memoryErrorOnce;

  MemoryUsage memoryUsage = const MemoryUsage(
    heapUsageBytes: 1000,
    heapCapacityBytes: 2000,
    externalUsageBytes: 100,
  );

  int disposeCalls = 0;
  int isolateIdCalls = 0;

  void emitFrame(FrameTiming frame) => _frames.add(frame);

  @override
  Future<String?> getMainIsolateId() async {
    isolateIdCalls++;
    final error = isolateIdError;
    if (error != null) throw error;
    return isolateId;
  }

  @override
  Future<MemoryUsage?> getMemoryUsage(String isolateId) async {
    final error = memoryErrorOnce;
    if (error != null) {
      memoryErrorOnce = null;
      throw error;
    }
    return memoryUsage;
  }

  @override
  Stream<FrameTiming> get flutterFrameEvents => _frames.stream;

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _frames.close();
  }
}

Future<PerformanceSample> _nextSample(Stream<PerformanceSample> samples) =>
    samples.first.timeout(const Duration(seconds: 5));

void main() {
  group('VmServicePerformanceSampler', () {
    test('publishes a sample each tick with the buffered frames', () async {
      final client = _FakeVmServiceClient();
      final sampler = VmServicePerformanceSampler(
        client: client,
        interval: const Duration(milliseconds: 20),
      );
      final samples = <PerformanceSample>[];
      final subscription = sampler.samples.listen(samples.add);
      await sampler.start();

      client.emitFrame(const FrameTiming(buildUs: 4000, rasterUs: 4000));
      client.emitFrame(const FrameTiming(buildUs: 5000, rasterUs: 5000));

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(samples, isNotEmpty);
      final sample = samples.firstWhere((s) => s.frameCount > 0);
      expect(sample.frameCount, 2);
      expect(sample.hasMemory, isTrue);
      expect(sample.heapUsageBytes, 1000);

      await subscription.cancel();
      await sampler.stop();
    });

    test('a window with no frames still produces a sample', () async {
      final client = _FakeVmServiceClient();
      final sampler = VmServicePerformanceSampler(
        client: client,
        interval: const Duration(milliseconds: 15),
      );
      await sampler.start();

      final sample = await _nextSample(sampler.samples);
      expect(sample.frameCount, 0);
      expect(sample.fps, 0.0);

      await sampler.stop();
    });

    test('a failure resolving the isolate id disables memory, not frames',
        () async {
      final client = _FakeVmServiceClient()..isolateIdError = StateError('x');
      final sampler = VmServicePerformanceSampler(
        client: client,
        interval: const Duration(milliseconds: 15),
      );
      await sampler.start();
      // Emitted after start(): the fake's frame stream is a broadcast stream,
      // so a frame sent before the sampler subscribes would be dropped.
      client.emitFrame(const FrameTiming(buildUs: 1000, rasterUs: 1000));

      final sample = await _nextSample(sampler.samples);
      expect(sample.hasMemory, isFalse);
      expect(sample.frameCount, 1);

      await sampler.stop();
    });

    test('a memory read failing for one window is just missing that window',
        () async {
      final client = _FakeVmServiceClient()
        ..memoryErrorOnce = StateError('paused');
      final sampler = VmServicePerformanceSampler(
        client: client,
        interval: const Duration(milliseconds: 15),
      );
      final samples = <PerformanceSample>[];
      sampler.samples.listen(samples.add);
      await sampler.start();

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(samples.first.hasMemory, isFalse);
      expect(samples.any((s) => s.hasMemory), isTrue);

      await sampler.stop();
    });

    test('stop cancels the timer, disposes the client, and is idempotent',
        () async {
      final client = _FakeVmServiceClient();
      final sampler = VmServicePerformanceSampler(
        client: client,
        interval: const Duration(milliseconds: 10),
      );
      final samples = <PerformanceSample>[];
      sampler.samples.listen(samples.add);
      await sampler.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      await sampler.stop();
      final countAfterStop = samples.length;
      await sampler.stop();

      expect(client.disposeCalls, 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(samples.length, countAfterStop);
    });

    test('connectPerformanceSampler wires a connector and starts sampling',
        () async {
      final client = _FakeVmServiceClient();
      final sampler = await connectPerformanceSampler(
        'ws://127.0.0.1:1234/abc',
        interval: const Duration(milliseconds: 15),
        connector: (uri) async {
          expect(uri, 'ws://127.0.0.1:1234/abc');
          return client;
        },
      );

      final sample = await _nextSample(sampler.samples);
      expect(sample, isNotNull);

      await sampler.stop();
    });

    test('looks the isolate up again after a memory read fails', () async {
      // A hot restart replaces the isolate, so the id resolved at start-up
      // goes stale and memory reads start failing.
      final client = _FakeVmServiceClient()
        ..memoryErrorOnce = StateError('isolate gone');
      final sampler = VmServicePerformanceSampler(
        client: client,
        interval: const Duration(milliseconds: 15),
      );
      final samples = <PerformanceSample>[];
      sampler.samples.listen(samples.add);
      await sampler.start();
      expect(client.isolateIdCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(client.isolateIdCalls, greaterThan(1));
      expect(samples.any((s) => s.hasMemory), isTrue);

      await sampler.stop();
    });
  });
}
