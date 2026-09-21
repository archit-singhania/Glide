import 'dart:async';

import '../performance_sample.dart';
import '../performance_sampler.dart';

/// An in-memory [PerformanceSampler] a test drives by hand.
///
/// Test support only: production code never constructs one.
class FakePerformanceSampler implements PerformanceSampler {
  final StreamController<PerformanceSample> _out =
      StreamController<PerformanceSample>.broadcast();

  bool stopped = false;
  int stopCalls = 0;

  @override
  Stream<PerformanceSample> get samples => _out.stream;

  /// Pushes a sample as if a window had just elapsed.
  void emit(PerformanceSample sample) {
    if (!_out.isClosed) _out.add(sample);
  }

  @override
  Future<void> stop() async {
    stopped = true;
    stopCalls++;
    if (!_out.isClosed) await _out.close();
  }
}
