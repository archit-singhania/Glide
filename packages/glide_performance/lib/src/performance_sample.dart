import 'frame_timing.dart';

/// A frame is counted as janky once build and raster together pass this
/// many microseconds — the budget for one frame at 60 fps.
const int jankyFrameThresholdUs = 16700;

/// One window's worth of performance data, ready to publish.
class PerformanceSample {
  const PerformanceSample({
    required this.timestamp,
    required this.windowMs,
    required this.frameCount,
    required this.fps,
    required this.avgFrameTimeMs,
    required this.jankyFrameCount,
    this.heapUsageBytes,
    this.heapCapacityBytes,
    this.externalUsageBytes,
  });

  /// Builds a sample from the frames seen during one sampling window.
  /// [frames] may be empty (nothing rendered that window, or the app is
  /// idle); [memory] may be null (the query failed or was skipped).
  factory PerformanceSample.fromWindow({
    required List<FrameTiming> frames,
    required Duration window,
    required DateTime timestamp,
    MemoryUsage? memory,
  }) {
    final count = frames.length;
    final windowSeconds =
        window.inMicroseconds / Duration.microsecondsPerSecond;
    final fps = count == 0 || windowSeconds <= 0 ? 0.0 : count / windowSeconds;
    var avgFrameTimeMs = 0.0;
    var jankyFrameCount = 0;
    if (count > 0) {
      final totalUs = frames.fold<int>(0, (sum, f) => sum + f.totalUs);
      avgFrameTimeMs = (totalUs / count) / 1000;
      jankyFrameCount =
          frames.where((f) => f.totalUs > jankyFrameThresholdUs).length;
    }
    return PerformanceSample(
      timestamp: timestamp,
      windowMs: window.inMilliseconds,
      frameCount: count,
      fps: fps,
      avgFrameTimeMs: avgFrameTimeMs,
      jankyFrameCount: jankyFrameCount,
      heapUsageBytes: memory?.heapUsageBytes,
      heapCapacityBytes: memory?.heapCapacityBytes,
      externalUsageBytes: memory?.externalUsageBytes,
    );
  }

  final DateTime timestamp;
  final int windowMs;
  final int frameCount;
  final double fps;
  final double avgFrameTimeMs;
  final int jankyFrameCount;

  /// Null when no memory reading was available for this window.
  final int? heapUsageBytes;
  final int? heapCapacityBytes;
  final int? externalUsageBytes;

  bool get hasMemory => heapUsageBytes != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'timestamp': timestamp.toIso8601String(),
        'windowMs': windowMs,
        'frameCount': frameCount,
        'fps': double.parse(fps.toStringAsFixed(1)),
        'frameTimeMs': double.parse(avgFrameTimeMs.toStringAsFixed(1)),
        'jankyFrameCount': jankyFrameCount,
        if (heapUsageBytes != null) 'heapUsageBytes': heapUsageBytes,
        if (heapCapacityBytes != null) 'heapCapacityBytes': heapCapacityBytes,
        if (externalUsageBytes != null)
          'externalUsageBytes': externalUsageBytes,
      };
}
