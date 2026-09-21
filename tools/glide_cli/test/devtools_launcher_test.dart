import 'dart:async';
import 'dart:io';

import 'package:glide_cli/glide_cli.dart';
import 'package:test/test.dart';

/// A [Process] that never runs anything.
class _FakeProcess implements Process {
  _FakeProcess({int? exitsWith}) {
    if (exitsWith != null) _exit.complete(exitsWith);
  }

  final Completer<int> _exit = Completer<int>();
  int killCalls = 0;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killCalls++;
    if (!_exit.isCompleted) _exit.complete(-15);
    return true;
  }

  @override
  int get pid => 4242;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();
}

const Duration _grace = Duration(milliseconds: 30);

void main() {
  group('isSafeVmServiceUri', () {
    test('accepts the loopback address Flutter reports', () {
      expect(isSafeVmServiceUri('ws://127.0.0.1:53210/AbC-_dEf=/ws'), isTrue);
      expect(isSafeVmServiceUri('ws://localhost:1234/x=/ws'), isTrue);
      expect(isSafeVmServiceUri('ws://[::1]:1234/x=/ws'), isTrue);
    });

    test('refuses anything else', () {
      for (final bad in <String>[
        '',
        'ws://evil.example.com:1234/x/ws',
        'ws://192.168.1.5:1234/x/ws',
        'http://127.0.0.1:1234/x/',
        'ws://127.0.0.1:1234/x; calc',
        'ws://127.0.0.1:1234/x && calc',
        r'ws://127.0.0.1:1234/$(id)',
        'ws://127.0.0.1:1234/x y',
        'ws://127.0.0.1:1234/x\n--other',
        'ws://127.0.0.1:1234/${'a' * 600}',
        '--help',
      ]) {
        expect(isSafeVmServiceUri(bad), isFalse, reason: bad);
      }
    });
  });

  group('openSystemDevTools', () {
    test('refuses an unsafe address without starting anything', () async {
      var started = false;
      await expectLater(
        openSystemDevTools(
          'ws://evil.example.com:1/x',
          start: (_, __) async {
            started = true;
            return _FakeProcess();
          },
        ),
        throwsA(isA<DevToolsException>()),
      );
      expect(started, isFalse);
    });

    test('runs "dart devtools" with the address as a single argument',
        () async {
      String? executable;
      List<String>? arguments;
      final process = _FakeProcess();
      final handle = await openSystemDevTools(
        'ws://127.0.0.1:5555/abc=/ws',
        startupGrace: _grace,
        start: (exe, args) async {
          executable = exe;
          arguments = args;
          return process;
        },
      );

      expect(executable, isNotNull);
      expect(arguments, <String>['devtools', 'ws://127.0.0.1:5555/abc=/ws']);

      await handle.close();
      expect(process.killCalls, 1);
    });

    test('fails when the process exits straight away', () async {
      await expectLater(
        openSystemDevTools(
          'ws://127.0.0.1:5555/abc=/ws',
          startupGrace: _grace,
          start: (_, __) async => _FakeProcess(exitsWith: 64),
        ),
        throwsA(
          isA<DevToolsException>()
              .having((e) => e.message, 'message', contains('64')),
        ),
      );
    });

    test('fails clearly when dart cannot be started', () async {
      await expectLater(
        openSystemDevTools(
          'ws://127.0.0.1:5555/abc=/ws',
          startupGrace: _grace,
          start: (_, __) async =>
              throw const ProcessException('dart', <String>[]),
        ),
        throwsA(isA<DevToolsException>()),
      );
    });
  });
}
