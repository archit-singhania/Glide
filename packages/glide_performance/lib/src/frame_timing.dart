/// One rendered frame's build and raster cost, in microseconds, as the
/// Flutter framework reports them on the `Flutter.Frame` VM service
/// extension event.
class FrameTiming {
  const FrameTiming({required this.buildUs, required this.rasterUs});

  final int buildUs;
  final int rasterUs;

  int get totalUs => buildUs + rasterUs;
}

/// A snapshot of the main isolate's heap, from `getMemoryUsage`.
class MemoryUsage {
  const MemoryUsage({
    required this.heapUsageBytes,
    required this.heapCapacityBytes,
    required this.externalUsageBytes,
  });

  final int heapUsageBytes;
  final int heapCapacityBytes;
  final int externalUsageBytes;
}
