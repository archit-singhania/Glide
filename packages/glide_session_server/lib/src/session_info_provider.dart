/// Supplies the data behind `GET /v1/session` and `GET /v1/project`.
///
/// Kept as a plain interface so the session server package has no knowledge
/// of `glide_project_analyzer` or the session state machine; a later phase
/// wires a real implementation on top of those.
abstract interface class SessionInfoProvider {
  /// Always available; describes the current session itself.
  Map<String, Object?> sessionSnapshot();

  /// Null until a project has been detected for this session.
  Map<String, Object?>? projectSnapshot();
}
