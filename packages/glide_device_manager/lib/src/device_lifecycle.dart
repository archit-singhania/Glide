/// Where a tracked device sits relative to Glide, not the OS-level
/// connection state (that is [FlutterDevice] itself appearing/disappearing).
enum DeviceLifecycle {
  /// Known to Glide but not yet confirmed usable for a run.
  discovered,

  /// Free for a new session to launch an app on.
  ready,

  /// A Glide session currently has an app running on this device.
  busy,
}
