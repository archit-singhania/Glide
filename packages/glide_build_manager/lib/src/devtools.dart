/// A DevTools server started for one running app. Closing it stops the
/// server.
abstract interface class DevToolsHandle {
  Future<void> close();
}

/// Starts DevTools on this computer for the app whose Dart VM service is at
/// [vmServiceUri].
///
/// The address is a credential for the running app, so it is only ever passed
/// to this function on the computer; it is never published to a companion.
/// Throws if DevTools could not be started.
typedef DevToolsOpener = Future<DevToolsHandle> Function(String vmServiceUri);
