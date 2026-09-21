import 'dart:async';
import 'dart:io';

import 'package:glide_build_manager/glide_build_manager.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:path/path.dart' as p;

/// Raised when DevTools cannot be started.
class DevToolsException extends GlideException {
  const DevToolsException(super.message, {super.cause});
}

// The shape of the address `flutter run --machine` reports: a loopback
// WebSocket URL whose path holds the app's auth code.
final RegExp _vmServiceUriPattern = RegExp(
  r'^wss?://(?:127\.0\.0\.1|localhost|\[::1\]):\d{1,5}/[A-Za-z0-9_\-=+/]*$',
);

/// Whether [uri] looks like the local Dart VM service address Flutter reports.
///
/// The address becomes a command-line argument, so anything that does not
/// match this shape is refused rather than passed on.
bool isSafeVmServiceUri(String uri) =>
    uri.length <= 512 && _vmServiceUriPattern.hasMatch(uri);

/// Starts an external program. Replaced in tests.
typedef DevToolsProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

Future<Process> _startProcess(String executable, List<String> arguments) =>
    Process.start(executable, arguments);

/// The `dart` executable to run: the one running Glide when it is called
/// `dart`, otherwise whatever is on PATH.
String dartExecutable() {
  final resolved = Platform.resolvedExecutable;
  return p.basenameWithoutExtension(resolved).toLowerCase() == 'dart'
      ? resolved
      : 'dart';
}

/// The real [DevToolsOpener]: runs `dart devtools <vm-service-uri>`, which
/// serves DevTools and opens it in the browser on this computer.
///
/// This has never been run against a real app. It assumes `dart devtools`
/// accepts the VM service address as its argument and opens a browser; if
/// that is wrong on your Dart version, this file is the only place to fix.
///
/// Fails if the process exits within [startupGrace], since that means
/// DevTools did not start.
Future<DevToolsHandle> openSystemDevTools(
  String vmServiceUri, {
  DevToolsProcessStarter start = _startProcess,
  Duration startupGrace = const Duration(seconds: 2),
}) async {
  if (!isSafeVmServiceUri(vmServiceUri)) {
    throw const DevToolsException(
      'The app reported a VM service address Glide does not recognise.',
    );
  }
  final Process process;
  try {
    process = await start(dartExecutable(), <String>[
      'devtools',
      vmServiceUri,
    ]);
  } on ProcessException catch (error) {
    throw DevToolsException('Could not run "dart devtools".', cause: error);
  }
  // Nobody reads its output; an unread pipe could eventually block it.
  unawaited(process.stdout.drain<void>());
  unawaited(process.stderr.drain<void>());
  const stillRunning = -1000;
  final earlyExit = await process.exitCode.timeout(
    startupGrace,
    onTimeout: () => stillRunning,
  );
  if (earlyExit != stillRunning) {
    throw DevToolsException(
      '"dart devtools" exited straight away (code $earlyExit).',
    );
  }
  return _ProcessDevTools(process);
}

class _ProcessDevTools implements DevToolsHandle {
  _ProcessDevTools(this._process);

  final Process _process;

  @override
  Future<void> close() async {
    _process.kill();
    await _process.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () => -1,
    );
  }
}
