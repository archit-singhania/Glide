import 'dart:async';
import 'dart:convert';

import 'process.dart';

/// One decoded line from the Flutter machine protocol.
sealed class MachineMessage {
  const MachineMessage();
}

/// `{"event": "app.started", "params": {...}}`
final class MachineEvent extends MachineMessage {
  const MachineEvent(this.name, this.params);

  final String name;
  final Map<String, Object?> params;
}

/// `{"id": 3, "result": ...}` or `{"id": 3, "error": ...}`
final class MachineResponse extends MachineMessage {
  const MachineResponse(this.id, {this.result, this.error});

  final int id;
  final Object? result;
  final Object? error;
}

/// A line that is not protocol JSON (plain tool output).
final class MachineText extends MachineMessage {
  const MachineText(this.text);

  final String text;
}

/// Decodes the newline-delimited JSON-array framing used by
/// `flutter daemon` and `flutter run --machine`.
abstract final class MachineMessageParser {
  static List<MachineMessage> parseLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('[')) {
      return trimmed.isEmpty ? const [] : [MachineText(line)];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      return [MachineText(line)];
    }
    if (decoded is! List) return [MachineText(line)];

    final messages = <MachineMessage>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, Object?>.from(item);
      final event = map['event'];
      final id = map['id'];
      if (event is String) {
        final params = map['params'];
        messages.add(
          MachineEvent(
            event,
            params is Map ? Map<String, Object?>.from(params) : const {},
          ),
        );
      } else if (id is int) {
        messages.add(
          MachineResponse(id, result: map['result'], error: map['error']),
        );
      }
    }
    return messages;
  }
}

/// A request that has been sent and awaits its response.
class PendingRequest {
  const PendingRequest(this.id, this.future);

  final int id;
  final Future<Object?> future;
}

/// Correlates request ids with responses, with timeouts.
class RequestRegistry {
  int _nextId = 0;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, String> _methods = <int, String>{};

  int get pendingCount => _pending.length;

  PendingRequest register(String method, Duration timeout) {
    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _methods[id] = method;
    final future = completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        _methods.remove(id);
        throw ToolRequestTimeout(method, timeout);
      },
    );
    return PendingRequest(id, future);
  }

  void complete(MachineResponse response) {
    final completer = _pending.remove(response.id);
    final method = _methods.remove(response.id) ?? 'unknown';
    if (completer == null) return;
    if (response.error != null) {
      completer.completeError(ToolRequestException(method, response.error));
    } else {
      completer.complete(response.result);
    }
  }

  /// Fails every outstanding request, for example when the process exits.
  void failAll(Object error) {
    final completers = _pending.values.toList();
    _pending.clear();
    _methods.clear();
    for (final completer in completers) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }
}
