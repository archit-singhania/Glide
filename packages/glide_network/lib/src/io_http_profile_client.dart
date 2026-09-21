import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

import 'http_profile_client.dart';

/// [HttpProfileClient] backed by a real Dart VM service connection.
///
/// This file has not been exercised against a real `flutter run` process;
/// everything else in this package is tested through [HttpProfileClient]
/// with a fake. Watch this file first if network monitoring misbehaves with a
/// real app.
///
/// It calls the `ext.dart.io.getHttpProfile` service extension directly and
/// reads the raw JSON, rather than using the typed `getHttpProfile` helper.
/// That helper's parameter and result types have changed between `vm_service`
/// releases (`int` versus `DateTime`), while the extension's wire format has
/// not, and a field missing in one VM version degrades to "unknown" instead of
/// failing to compile or throwing.
class IoHttpProfileClient implements HttpProfileClient {
  IoHttpProfileClient._(this._service);

  static Future<HttpProfileClient> connect(String wsUri) async {
    final service = await vm_service_io.vmServiceConnectUri(wsUri);
    return IoHttpProfileClient._(service);
  }

  final vm_service.VmService _service;

  @override
  Future<String?> getMainIsolateId() async {
    final vm = await _service.getVM();
    final isolates = vm.isolates;
    if (isolates == null || isolates.isEmpty) return null;
    return isolates.first.id;
  }

  @override
  Future<void> enableLogging(String isolateId) async {
    await _service.httpEnableTimelineLogging(isolateId, true);
  }

  @override
  Future<HttpProfileSnapshot> fetch(
    String isolateId, {
    int? updatedSince,
  }) async {
    final response = await _service.callServiceExtension(
      'ext.dart.io.getHttpProfile',
      isolateId: isolateId,
      // Service extension arguments travel as strings; the value is
      // microseconds since the epoch, as the VM reported it last time.
      args: <String, dynamic>{
        if (updatedSince != null) 'updatedSince': '$updatedSince',
      },
    );
    final json = _asMap(response.json);
    final entries = <HttpProfileEntry>[];
    final requests = json['requests'];
    if (requests is List) {
      for (final raw in requests) {
        final entry = _entryFrom(_asMap(raw));
        if (entry != null) entries.add(entry);
      }
    }
    return HttpProfileSnapshot(
      timestamp: _asInt(json['timestamp']) ?? updatedSince ?? 0,
      entries: entries,
    );
  }

  HttpProfileEntry? _entryFrom(Map<String, Object?> json) {
    final id = _asString(json['id']);
    final method = _asString(json['method']);
    final uri = _asString(json['uri']);
    if (id == null || method == null || uri == null) return null;
    final response = _asMap(json['response']);
    return HttpProfileEntry(
      id: id,
      method: method,
      uri: uri,
      startMicros: _asInt(json['startTime']),
      endMicros: _asInt(json['endTime']),
      statusCode: _asInt(response['statusCode']),
      contentLength: _asInt(response['contentLength']),
    );
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : <String, Object?>{};

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  static String? _asString(Object? value) => value?.toString();

  @override
  Future<void> dispose() => _service.dispose();
}
