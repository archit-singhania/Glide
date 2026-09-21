import 'dart:async';

import 'foundation.dart';

/// Lifecycle of a Glide development session.
///
/// Modelled as an explicit state machine instead of a set of booleans.
enum SessionState {
  disconnected,
  pairing,
  connected,
  preparing,
  building,
  installing,
  launching,
  running,
  reloading,
  restarting,
  stopping,
  failed,
}

/// Raised when code attempts a transition the machine does not allow.
class InvalidTransitionException extends GlideException {
  InvalidTransitionException(this.from, this.to)
      : super('Invalid session transition: ${from.name} -> ${to.name}');

  final SessionState from;
  final SessionState to;
}

/// A recorded transition.
class SessionStateChange {
  const SessionStateChange({
    required this.from,
    required this.to,
    required this.at,
    this.reason,
  });

  final SessionState from;
  final SessionState to;
  final DateTime at;
  final String? reason;
}

/// Validates and broadcasts [SessionState] transitions.
class SessionStateMachine {
  SessionStateMachine({
    SessionState initial = SessionState.disconnected,
    DateTime Function()? clock,
  })  : _state = initial,
        _clock = clock ?? DateTime.now;

  static const Map<SessionState, Set<SessionState>> _allowed =
      <SessionState, Set<SessionState>>{
    SessionState.disconnected: {
      SessionState.pairing,
      SessionState.connected,
      SessionState.preparing,
    },
    SessionState.pairing: {SessionState.connected, SessionState.disconnected},
    SessionState.connected: {
      SessionState.preparing,
      SessionState.disconnected,
      SessionState.pairing,
    },
    SessionState.preparing: {
      SessionState.building,
      SessionState.installing,
      SessionState.launching,
      SessionState.running,
      SessionState.stopping,
    },
    SessionState.building: {
      SessionState.installing,
      SessionState.launching,
      SessionState.running,
      SessionState.stopping,
    },
    SessionState.installing: {
      SessionState.launching,
      SessionState.running,
      SessionState.stopping,
    },
    SessionState.launching: {SessionState.running, SessionState.stopping},
    SessionState.running: {
      SessionState.reloading,
      SessionState.restarting,
      SessionState.stopping,
    },
    SessionState.reloading: {SessionState.running, SessionState.stopping},
    SessionState.restarting: {SessionState.running, SessionState.stopping},
    SessionState.stopping: {SessionState.connected, SessionState.disconnected},
    SessionState.failed: {
      SessionState.disconnected,
      SessionState.connected,
      SessionState.pairing,
      SessionState.preparing,
    },
  };

  final DateTime Function() _clock;
  final StreamController<SessionStateChange> _changes =
      StreamController<SessionStateChange>.broadcast();
  SessionState _state;

  SessionState get state => _state;

  /// Emits every accepted transition.
  Stream<SessionStateChange> get changes => _changes.stream;

  /// Whether moving to [next] is legal from the current state.
  /// Any state except `failed` may move to `failed`.
  bool canTransitionTo(SessionState next) {
    if (next == _state) return false;
    if (next == SessionState.failed) return true;
    return _allowed[_state]?.contains(next) ?? false;
  }

  /// Moves to [next] or throws [InvalidTransitionException].
  void transitionTo(SessionState next, {String? reason}) {
    if (!canTransitionTo(next)) {
      throw InvalidTransitionException(_state, next);
    }
    final change = SessionStateChange(
      from: _state,
      to: next,
      at: _clock(),
      reason: reason,
    );
    _state = next;
    if (!_changes.isClosed) _changes.add(change);
  }

  /// Like [transitionTo] but returns `false` instead of throwing.
  bool tryTransitionTo(SessionState next, {String? reason}) {
    if (!canTransitionTo(next)) return false;
    transitionTo(next, reason: reason);
    return true;
  }

  Future<void> dispose() => _changes.close();
}
