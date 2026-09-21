import 'dart:async';

import '../network_event.dart';
import '../network_monitor.dart';

/// An in-memory [NetworkMonitor] a test drives by hand.
///
/// Test support only: production code never constructs one.
class FakeNetworkMonitor implements NetworkMonitor {
  final StreamController<NetworkEvent> _out =
      StreamController<NetworkEvent>.broadcast();

  bool stopped = false;
  int stopCalls = 0;

  @override
  Stream<NetworkEvent> get events => _out.stream;

  /// Pushes an event as if a request had just finished.
  void emit(NetworkEvent event) {
    if (!_out.isClosed) _out.add(event);
  }

  @override
  Future<void> stop() async {
    stopped = true;
    stopCalls++;
    if (!_out.isClosed) await _out.close();
  }
}
