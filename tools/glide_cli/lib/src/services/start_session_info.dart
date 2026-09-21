import 'package:glide_project_analyzer/glide_project_analyzer.dart';
import 'package:glide_protocol/glide_protocol.dart';
import 'package:glide_session_server/glide_session_server.dart';

/// Backs `GET /v1/session` and `GET /v1/project` for `glide start`.
class StartSessionInfo implements SessionInfoProvider {
  StartSessionInfo({
    required this.sessionId,
    required this.machine,
    required this.project,
  });

  final String sessionId;
  final SessionStateMachine machine;
  final ProjectInfo project;

  @override
  Map<String, Object?> sessionSnapshot() => <String, Object?>{
        'sessionId': sessionId,
        'protocol': glideProtocolVersion,
        'state': machine.state.name,
        'project': project.name,
      };

  /// The project without its absolute path, which would leak the developer's
  /// directory layout (often including their user name) to the phone.
  @override
  Map<String, Object?>? projectSnapshot() =>
      project.toJson()..remove('rootPath');
}
