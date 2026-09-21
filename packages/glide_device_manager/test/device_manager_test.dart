import 'dart:async';

import 'package:glide_device_manager/glide_device_manager.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:test/test.dart';

const FlutterDevice _pixel = FlutterDevice(
  id: 'emulator-5554',
  name: 'Pixel 10',
  platform: 'android-arm64',
);

const FlutterDevice _iphone = FlutterDevice(
  id: 'ios-1234',
  name: 'iPhone',
  platform: 'ios',
);

/// Lets pending microtasks (stream event delivery) run before assertions.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('DeviceManager', () {
    late StreamController<FlutterToolEvent> events;
    late DeviceManager manager;

    setUp(() {
      events = StreamController<FlutterToolEvent>.broadcast();
      manager = DeviceManager(events: events.stream);
    });

    tearDown(() async {
      await manager.dispose();
      await events.close();
    });

    test('starts empty', () {
      expect(manager.devices, isEmpty);
      expect(manager.getDevice(_pixel.id), isNull);
    });

    test('device.added adds and updates a device', () async {
      events.add(const DeviceAdded(_pixel));
      await _settle();

      expect(manager.devices, hasLength(1));
      final tracked = manager.getDevice(_pixel.id);
      expect(tracked, isNotNull);
      expect(tracked!.name, 'Pixel 10');
      expect(tracked.state, DeviceLifecycle.ready);
      expect(tracked.isAndroid, isTrue);
    });

    test('device.removed drops the device', () async {
      events.add(const DeviceAdded(_pixel));
      await _settle();
      events.add(const DeviceRemoved('emulator-5554'));
      await _settle();

      expect(manager.devices, isEmpty);
      expect(manager.getDevice(_pixel.id), isNull);
    });

    test('an unknown event is ignored, not a crash', () async {
      events.add(const DaemonConnected('3.47.0'));
      await _settle();
      expect(manager.devices, isEmpty);
    });

    test('watchDevices immediately yields the current snapshot', () async {
      events.add(const DeviceAdded(_pixel));
      await _settle();

      final first = await manager.watchDevices().first;
      expect(first.single.id, _pixel.id);
    });

    test('watchDevices emits again on every change', () async {
      final snapshots = <int>[];
      final sub = manager.watchDevices().listen((d) => snapshots.add(d.length));
      await _settle();

      events.add(const DeviceAdded(_pixel));
      await _settle();
      events.add(const DeviceAdded(_iphone));
      await _settle();
      events.add(const DeviceRemoved('emulator-5554'));
      await _settle();

      expect(snapshots, <int>[0, 1, 2, 1]);
      await sub.cancel();
    });

    test('devices are sorted by name', () async {
      events
        ..add(const DeviceAdded(_pixel))
        ..add(const DeviceAdded(_iphone));
      await _settle();

      expect(
        manager.devices.map((d) => d.name),
        <String>['Pixel 10', 'iPhone'],
      );
    });

    group('refresh', () {
      test('adds devices the daemon has not announced yet', () async {
        await manager.refresh(() async => const <FlutterDevice>[_pixel]);
        expect(manager.devices, hasLength(1));
      });

      test('drops devices no longer present', () async {
        events.add(const DeviceAdded(_pixel));
        await _settle();

        await manager.refresh(() async => const <FlutterDevice>[]);

        expect(manager.devices, isEmpty);
      });

      test('preserves lifecycle state for devices that remain', () async {
        events.add(const DeviceAdded(_pixel));
        await _settle();
        manager.markBusy(_pixel.id);

        await manager.refresh(() async => const <FlutterDevice>[_pixel]);

        expect(manager.getDevice(_pixel.id)!.state, DeviceLifecycle.busy);
      });

      test('does not publish a change when nothing moved', () async {
        events.add(const DeviceAdded(_pixel));
        await _settle();
        final snapshots = <List<GlideDevice>>[];
        final sub = manager.watchDevices().listen(snapshots.add);
        await _settle();

        await manager.refresh(() async => const <FlutterDevice>[_pixel]);
        await _settle();

        expect(snapshots, hasLength(1), reason: 'only the initial snapshot');
        await sub.cancel();
      });
    });

    group('markBusy / markReady', () {
      test('return false for an unknown device', () {
        expect(manager.markBusy('nope'), isFalse);
        expect(manager.markReady('nope'), isFalse);
      });

      test('toggle a known device between ready and busy', () async {
        events.add(const DeviceAdded(_pixel));
        await _settle();

        expect(manager.markBusy(_pixel.id), isTrue);
        expect(manager.getDevice(_pixel.id)!.state, DeviceLifecycle.busy);

        expect(manager.markReady(_pixel.id), isTrue);
        expect(manager.getDevice(_pixel.id)!.state, DeviceLifecycle.ready);
      });
    });

    test('dispose stops further updates and closes watchDevices', () async {
      await manager.dispose();
      await manager.dispose(); // safe to call twice

      events.add(const DeviceAdded(_pixel));
      await _settle();

      expect(manager.devices, isEmpty);
      await expectLater(manager.watchDevices(), emits(isEmpty));
    });
  });
}
