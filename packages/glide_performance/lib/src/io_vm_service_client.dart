import 'dart:async';

import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

import 'frame_timing.dart';
import 'vm_service_client.dart';

/// [VmServiceClient] backed by a real Dart VM service connection.
///
/// This is the one file in this package that has not been exercised against
/// a real `flutter run` process; everything else is tested through the
/// [VmServiceClient] interface with a fake. Watch this file first if
/// performance sampling misbehaves against a real app.
class IoVmServiceClient implements VmServiceClient {
  IoVmServiceClient._(this._service);

  static Future<VmServiceClient> connect(String wsUri) async {
    final service = await vm_service_io.vmServiceConnectUri(wsUri);
    final client = IoVmServiceClient._(service);
    // Flutter's frame-timing events arrive as `Extension` stream events with
    // extensionKind `Flutter.Frame`.
    await service.streamListen(vm_service.EventStreams.kExtension);
    return client;
  }

  final vm_service.VmService _service;
  final StreamController<FrameTiming> _frames =
      StreamController<FrameTiming>.broadcast();
  StreamSubscription<vm_service.Event>? _extensionSubscription;

  @override
  Stream<FrameTiming> get flutterFrameEvents {
    _extensionSubscription ??=
        _service.onExtensionEvent.listen(_onExtensionEvent);
    return _frames.stream;
  }

  void _onExtensionEvent(vm_service.Event event) {
    if (event.extensionKind != 'Flutter.Frame') return;
    final data = event.extensionData?.data;
    if (data == null) return;
    final build = _asInt(data['build']);
    final raster = _asInt(data['raster']);
    if (!_frames.isClosed) {
      _frames.add(FrameTiming(buildUs: build, rasterUs: raster));
    }
  }

  int _asInt(Object? value) => value is num ? value.toInt() : 0;

  @override
  Future<String?> getMainIsolateId() async {
    final vm = await _service.getVM();
    final isolates = vm.isolates;
    if (isolates == null || isolates.isEmpty) return null;
    return isolates.first.id;
  }

  @override
  Future<MemoryUsage?> getMemoryUsage(String isolateId) async {
    final usage = await _service.getMemoryUsage(isolateId);
    return MemoryUsage(
      heapUsageBytes: usage.heapUsage ?? 0,
      heapCapacityBytes: usage.heapCapacity ?? 0,
      externalUsageBytes: usage.externalUsage ?? 0,
    );
  }

  @override
  Future<void> dispose() async {
    await _extensionSubscription?.cancel();
    _extensionSubscription = null;
    await _frames.close();
    await _service.dispose();
  }
}
