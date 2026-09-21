import 'dart:async';

import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';

import 'device_lifecycle.dart';
import 'glide_device.dart';

/// Fetches a full, one-shot device listing, e.g. via
/// `flutter devices --machine` or [FlutterDaemonClient.getDevices].
typedef DeviceLister = Future<List<FlutterDevice>> Function();

/// Tracks connected devices from a stream of [FlutterToolEvent]s and exposes
/// a single current snapshot, so callers never have to replay history.
///
/// [DeviceManager] does not start or own any process. Feed it the events of
/// a running [FlutterDaemonClient] (or any other source of
/// [FlutterToolEvent]s); the caller remains responsible for starting and
/// shutting down whatever produces them.
class DeviceManager {
  DeviceManager({
    required Stream<FlutterToolEvent> events,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _subscription = events.listen(_onEvent);
  }

  final DateTime Function() _clock;
  late final StreamSubscription<FlutterToolEvent> _subscription;
  final Map<String, GlideDevice> _devices = <String, GlideDevice>{};
  final StreamController<List<GlideDevice>> _changes =
      StreamController<List<GlideDevice>>.broadcast();

  /// Current devices, sorted by name for stable display.
  List<GlideDevice> get devices =>
      _devices.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  /// Emits the full snapshot whenever it changes. Every new listener first
  /// receives the current snapshot, then every subsequent change.
  Stream<List<GlideDevice>> watchDevices() async* {
    yield devices;
    yield* _changes.stream;
  }

  /// The tracked device with this id, or null if none is known.
  GlideDevice? getDevice(String id) => _devices[id];

  void _onEvent(FlutterToolEvent event) {
    switch (event) {
      case DeviceAdded(:final device):
        _upsert(device);
      case DeviceRemoved(:final deviceId):
        if (_devices.remove(deviceId) != null) _publish();
      default:
        break;
    }
  }

  void _upsert(FlutterDevice device) {
    final existing = _devices[device.id];
    _devices[device.id] = GlideDevice(
      device: device,
      state: existing?.state ?? DeviceLifecycle.ready,
      lastSeenAt: _clock(),
    );
    _publish();
  }

  /// Reconciles tracked devices against a full listing from [list]: adds any
  /// device the daemon has not yet announced and drops any that are no
  /// longer present. Existing lifecycle state is preserved for devices that
  /// remain.
  Future<void> refresh(DeviceLister list) async {
    final found = await list();
    final foundIds = found.map((d) => d.id).toSet();
    var changed = false;

    for (final device in found) {
      final existing = _devices[device.id];
      if (existing == null) {
        _devices[device.id] = GlideDevice(
          device: device,
          state: DeviceLifecycle.ready,
          lastSeenAt: _clock(),
        );
        changed = true;
      }
    }

    final staleIds =
        _devices.keys.where((id) => !foundIds.contains(id)).toList();
    for (final id in staleIds) {
      _devices.remove(id);
      changed = true;
    }

    if (changed) _publish();
  }

  /// Marks [id] busy, e.g. because a session just launched an app on it.
  /// Returns false if [id] is not currently tracked.
  bool markBusy(String id) => _setState(id, DeviceLifecycle.busy);

  /// Marks [id] ready again once a session releases it.
  /// Returns false if [id] is not currently tracked.
  bool markReady(String id) => _setState(id, DeviceLifecycle.ready);

  bool _setState(String id, DeviceLifecycle state) {
    final existing = _devices[id];
    if (existing == null || existing.state == state) return existing != null;
    _devices[id] = existing.copyWith(state: state);
    _publish();
    return true;
  }

  void _publish() {
    if (!_changes.isClosed) _changes.add(devices);
  }

  /// Stops listening for events and closes [watchDevices]. Safe to call
  /// more than once.
  Future<void> dispose() async {
    await _subscription.cancel();
    if (!_changes.isClosed) await _changes.close();
  }
}
