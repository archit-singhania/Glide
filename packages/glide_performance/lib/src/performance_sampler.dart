import 'dart:async';

import 'frame_timing.dart';
import 'io_vm_service_client.dart';
import 'performance_sample.dart';
import 'vm_service_client.dart';

/// Periodically produces [PerformanceSample]s for a running app. Started and
/// stopped by whoever owns the app's session; nothing here decides when an
/// app is running.
abstract interface class PerformanceSampler {
  Stream<PerformanceSample> get samples;

  /// Stops sampling and releases the underlying connection. Safe to call
  /// once; safe to call even if [samples] was never listened to.
  Future<void> stop();
}

/// Connects to the Dart VM service at [vmServiceUri] and starts sampling.
///
/// The returned [PerformanceSampler] is already producing samples; there is
/// nothing further to call before listening to [PerformanceSampler.samples].
///
/// If the connection itself fails, this throws and nothing is left running.
/// Once connected, a failure to read one window (for example the isolate is
/// paused at a breakpoint) is swallowed and that window is simply skipped.
Future<PerformanceSampler> connectPerformanceSampler(
  String vmServiceUri, {
  Duration interval = const Duration(seconds: 2),
  VmServiceConnector connector = IoVmServiceClient.connect,
}) async {
  final client = await connector(vmServiceUri);
  final sampler = VmServicePerformanceSampler(
    client: client,
    interval: interval,
  );
  await sampler.start();
  return sampler;
}

/// [PerformanceSampler] backed by a [VmServiceClient].
///
/// Exposed (rather than kept private) so tests can drive it directly against
/// a fake [VmServiceClient], without needing a real VM service.
class VmServicePerformanceSampler implements PerformanceSampler {
  VmServicePerformanceSampler({
    required this.client,
    this.interval = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final VmServiceClient client;
  final Duration interval;
  final DateTime Function() _clock;

  final StreamController<PerformanceSample> _out =
      StreamController<PerformanceSample>.broadcast();
  final List<FrameTiming> _pendingFrames = <FrameTiming>[];
  StreamSubscription<FrameTiming>? _frameSubscription;
  Timer? _timer;
  String? _isolateId;
  bool _stopped = false;

  @override
  Stream<PerformanceSample> get samples => _out.stream;

  /// Connects the frame stream and starts the periodic timer. Errors
  /// resolving the isolate id are not fatal: memory readings are simply
  /// skipped and only frame counts are reported.
  Future<void> start() async {
    try {
      _isolateId = await client.getMainIsolateId();
    } on Object {
      _isolateId = null;
    }
    _frameSubscription = client.flutterFrameEvents.listen(
      _pendingFrames.add,
      onError: (Object _) {
        // A frame we could not read is simply missing from this window's
        // count; it never affects the FPS/jank picture of other frames.
      },
    );
    _timer = Timer.periodic(interval, (_) => unawaited(_tick()));
  }

  Future<void> _tick() async {
    if (_stopped) return;
    final frames = List<FrameTiming>.of(_pendingFrames);
    _pendingFrames.clear();
    MemoryUsage? memory;
    if (_isolateId == null) {
      // Either the first lookup failed or the isolate was replaced (a hot
      // restart starts a new one), so look it up again.
      try {
        _isolateId = await client.getMainIsolateId();
      } on Object {
        _isolateId = null;
      }
    }
    final isolateId = _isolateId;
    if (isolateId != null) {
      try {
        memory = await client.getMemoryUsage(isolateId);
      } on Object {
        memory = null;
        _isolateId = null;
      }
    }
    if (_stopped) return;
    final sample = PerformanceSample.fromWindow(
      frames: frames,
      window: interval,
      timestamp: _clock(),
      memory: memory,
    );
    if (!_out.isClosed) _out.add(sample);
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    _timer = null;
    await _frameSubscription?.cancel();
    _frameSubscription = null;
    try {
      await client.dispose();
    } on Object {
      // The connection may already be gone (app closed first); sampling is
      // stopping either way.
    }
    if (!_out.isClosed) await _out.close();
  }
}
