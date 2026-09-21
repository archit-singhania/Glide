import 'frame_timing.dart';

/// The small slice of the Dart VM service protocol Glide needs.
///
/// Real code depends on this interface, not on `package:vm_service`
/// directly, so [PerformanceSampler] can be tested without a real VM
/// service. See `io_vm_service_client.dart` for the real adapter.
abstract interface class VmServiceClient {
  /// The id of the isolate to sample, or null if none could be found.
  Future<String?> getMainIsolateId();

  /// Null if the reading is unavailable, for example while the isolate is
  /// paused.
  Future<MemoryUsage?> getMemoryUsage(String isolateId);

  /// `Flutter.Frame` extension events as they arrive. Broadcast: the caller
  /// may listen once and buffer, or not listen at all.
  Stream<FrameTiming> get flutterFrameEvents;

  /// Closes the underlying connection. Safe to call once.
  Future<void> dispose();
}

/// Connects to the Dart VM service at [wsUri] (as reported by the Flutter
/// tool's `app.debugPort` event) and returns a ready client.
typedef VmServiceConnector = Future<VmServiceClient> Function(String wsUri);
