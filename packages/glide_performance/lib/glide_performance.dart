/// Samples FPS, frame time and memory from the Dart VM service of a running
/// Flutter app, on an interval, without exposing the VM service URI itself
/// to anything outside this process.
library;

export 'src/frame_timing.dart';
export 'src/io_vm_service_client.dart';
export 'src/performance_sample.dart';
export 'src/performance_sampler.dart';
export 'src/vm_service_client.dart';
