import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glide_build_manager/testing.dart';
import 'package:glide_cli/glide_cli.dart';
import 'package:glide_flutter_bridge/glide_flutter_bridge.dart';
import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:glide_security/glide_security.dart';
import 'package:glide_session_server/glide_session_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

class _FakeAnalyzer implements ProjectAnalyzer {
  @override
  Future<ProjectInfo> analyze(String directory) async => ProjectInfo(
        name: 'shop_app',
        rootPath: directory,
        platforms: <ProjectPlatform>{ProjectPlatform.android},
      );
}

StartEnvironment _env({
  PairingApprover? approver,
  ShutdownTrigger? shutdown,
  Duration lifetime = const Duration(minutes: 5),
  LanAddressResolver? resolver,
  FlutterAppLauncher? launchApp,
}) =>
    StartEnvironment(
      resolveLanAddress: resolver ?? () async => InternetAddress.loopbackIPv4,
      approver: approver ?? (_) async => true,
      shutdown: shutdown ?? () => Completer<void>().future,
      pairingLifetime: lifetime,
      launchApp: launchApp ?? launchFlutterApp,
      chooseDevice: ({String? flutterSdkPath}) async => null,
    );

Future<void> _waitFor(StringBuffer out, String needle) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!out.toString().contains(needle)) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for "$needle". Output so far:\n$out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

PairingPayload _payloadFrom(String output) {
  final match = RegExp(r'glide://pair\?\S+').firstMatch(output);
  if (match == null) fail('No pairing link in output:\n$output');
  return PairingPayload.parse(match.group(0)!);
}

Future<GlideMessage> _pair(
  PairingPayload payload, {
  String deviceName = 'Test Phone',
  String? token,
}) async {
  final channel = IOWebSocketChannel.connect(
    Uri.parse('ws://${payload.host}:${payload.port}/pair'),
  );
  await channel.ready;
  channel.sink.add(
    GlideMessage.create(
      MessageTypes.pairingRequest,
      payload: <String, Object?>{
        'session': payload.sessionId,
        'token': token ?? payload.token,
        'deviceId': 'test-phone-1',
        'deviceName': deviceName,
      },
    ).encode(),
  );
  final reply = await channel.stream.first as String;
  await channel.sink.close();
  return GlideMessage.decode(reply);
}

Future<bool> _isListening(int port) async {
  try {
    final socket = await Socket.connect(
      '127.0.0.1',
      port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    return true;
  } on SocketException {
    return false;
  }
}

void main() {
  late Directory project;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    project = Directory.systemTemp.createTempSync('glide_start_');
    File('${project.path}${Platform.pathSeparator}pubspec.yaml')
        .writeAsStringSync('name: shop_app\n');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() {
    if (project.existsSync()) project.deleteSync(recursive: true);
  });

  Future<int> start(List<String> args, StartEnvironment env) => runGlide(
        <String>['start', ...args],
        out: out,
        err: err,
        analyzer: _FakeAnalyzer(),
        workingDirectory: project.path,
        startEnvironment: env,
      );

  group('glide start', () {
    test('pairs a companion, serves the session, and stops on shutdown',
        () async {
      final stop = Completer<void>();
      final done = start(
        <String>['--host', '127.0.0.1', '--port', '47700', '--print-uri'],
        _env(shutdown: () => stop.future),
      );

      await _waitFor(out, 'Waiting for Glide companion');
      final payload = _payloadFrom(out.toString());
      expect(
        payload.sessionId,
        matches(RegExp(r'^GLIDE-[A-Z0-9]{4}-[A-Z0-9]{3}$')),
      );

      final reply = await _pair(payload);
      expect(reply.type, MessageTypes.pairingAccepted);
      await _waitFor(out, 'Paired with Test Phone.');

      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${payload.port}/v1/session'),
        );
        request.headers.set(
          controlTokenHeader,
          reply.payload['sessionToken']! as String,
        );
        final response = await request.close();
        expect(response.statusCode, 200);
        final body = jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
        expect(body['state'], 'connected');
        expect(body['project'], 'shop_app');
      } finally {
        client.close(force: true);
      }

      stop.complete();
      expect(await done, 0);
      expect(out.toString(), contains('Stopping Glide session.'));
      expect(await _isListening(payload.port), isFalse);
    });

    test('the pairing link is not printed unless --print-uri is given',
        () async {
      final stop = Completer<void>();
      final done = start(
        <String>['--host', '127.0.0.1', '--port', '47710'],
        _env(shutdown: () => stop.future),
      );

      await _waitFor(out, 'Waiting for Glide companion');
      stop.complete();
      expect(await done, 0);

      expect(out.toString(), isNot(contains('glide://')));
      expect(out.toString(), isNot(contains('token=')));
      expect(out.toString(), contains('Scan this QR code'));
    });

    test('a declined device is rejected and never paired', () async {
      final stop = Completer<void>();
      final done = start(
        <String>['--host', '127.0.0.1', '--port', '47720', '--print-uri'],
        _env(approver: (_) async => false, shutdown: () => stop.future),
      );

      await _waitFor(out, 'Waiting for Glide companion');
      final reply = await _pair(_payloadFrom(out.toString()));

      expect(reply.type, MessageTypes.pairingRejected);
      expect(reply.payload['code'], 'rejectedByHost');
      expect(out.toString(), isNot(contains('Paired with')));

      stop.complete();
      expect(await done, 0);
    });

    test('the companion can run, reload and stop the app', () async {
      final session = FakeAppSession();
      final stop = Completer<void>();
      final done = start(
        <String>['--host', '127.0.0.1', '--port', '47750', '--print-uri'],
        _env(
          shutdown: () => stop.future,
          launchApp: ({
            required String projectPath,
            required String deviceId,
            String? flutterSdkPath,
            AppMode? mode,
          }) async =>
              session,
        ),
      );

      await _waitFor(out, 'Waiting for Glide companion');
      final payload = _payloadFrom(out.toString());
      final grant = await _pair(payload);

      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${payload.port}/ws'),
        headers: <String, String>{
          controlTokenHeader: grant.payload['sessionToken']! as String,
        },
      );
      await channel.ready;
      final received = <GlideMessage>[];
      channel.stream.listen(
        (Object? data) => received.add(GlideMessage.decode(data! as String)),
      );

      Future<GlideMessage> waitForMessage(String type) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (true) {
          for (final message in received) {
            if (message.type == type) return message;
          }
          if (DateTime.now().isAfter(deadline)) {
            fail('Timed out waiting for $type. Received: $received');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      channel.sink.add(
        GlideMessage.create(
          'app.run',
          payload: <String, Object?>{'deviceId': 'pixel-1'},
        ).encode(),
      );
      await waitForMessage(MessageTypes.buildStarted);
      session.markStarted();
      final started = await waitForMessage(MessageTypes.appStarted);
      expect(started.payload['deviceId'], 'pixel-1');

      channel.sink.add(GlideMessage.create('app.reload').encode());
      final reloaded = await waitForMessage(MessageTypes.reloadCompleted);
      expect(reloaded.payload['durationMs'], 42);
      expect(session.reloadCalls, 1);

      channel.sink.add(GlideMessage.create('app.stop').encode());
      await waitForMessage(MessageTypes.appStopped);
      expect(session.stopped, isTrue);

      await channel.sink.close();
      stop.complete();
      expect(await done, 0);
    });

    test('commands with nothing to act on are rejected, not ignored', () async {
      final stop = Completer<void>();
      final done = start(
        <String>['--host', '127.0.0.1', '--port', '47730', '--print-uri'],
        _env(shutdown: () => stop.future),
      );

      await _waitFor(out, 'Waiting for Glide companion');
      final payload = _payloadFrom(out.toString());
      final grant = await _pair(payload);

      final channel = IOWebSocketChannel.connect(
        Uri.parse('ws://127.0.0.1:${payload.port}/ws'),
        headers: <String, String>{
          controlTokenHeader: grant.payload['sessionToken']! as String,
        },
      );
      await channel.ready;
      channel.sink.add(GlideMessage.create('app.reload').encode());

      final reply = GlideMessage.decode(await channel.stream.first as String);
      expect(reply.type, MessageTypes.commandRejected);
      expect(reply.payload['command'], 'app.reload');
      await _waitFor(out, 'Received app.reload');

      await channel.sink.close();
      stop.complete();
      expect(await done, 0);
    });

    test('exits with an error when nobody pairs before the code expires',
        () async {
      final code = await start(
        <String>['--host', '127.0.0.1', '--port', '47740'],
        _env(lifetime: const Duration(milliseconds: 200)),
      );

      expect(code, 1);
      expect(err.toString(), contains('expired'));
      expect(await _isListening(47740), isFalse);
    });

    test('refuses a wildcard host', () async {
      final code = await start(<String>['--host', '0.0.0.0'], _env());
      expect(code, 1);
      expect(err.toString(), contains('wildcard'));
    });

    test('rejects a host that is not IPv4', () async {
      final code = await start(<String>['--host', 'example.com'], _env());
      expect(code, 1);
      expect(err.toString(), contains('IPv4'));
    });

    test('rejects an invalid port', () async {
      final code = await start(
        <String>['--host', '127.0.0.1', '--port', '99999'],
        _env(),
      );
      expect(code, 1);
      expect(err.toString(), contains('--port'));
    });

    test('fails clearly when no LAN address can be found', () async {
      final code = await start(
        <String>[],
        _env(resolver: () async => null),
      );
      expect(code, 1);
      expect(err.toString(), contains('No private LAN address'));
    });

    test('fails clearly outside a project', () async {
      final empty = Directory.systemTemp.createTempSync('glide_empty_');
      addTearDown(() => empty.deleteSync(recursive: true));

      final code = await runGlide(
        <String>['start', '--host', '127.0.0.1'],
        out: out,
        err: err,
        analyzer: _FakeAnalyzer(),
        workingDirectory: empty.path,
        startEnvironment: _env(),
      );

      expect(code, 1);
      expect(err.toString(), contains('pubspec.yaml'));
    });
  });
}
