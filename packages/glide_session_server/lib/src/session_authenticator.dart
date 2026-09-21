import 'package:glide_security/glide_security.dart';

/// Validates a control token presented by a connecting companion.
///
/// Kept separate from pairing itself: [PairingManager] (in `glide_security`)
/// issues and tracks session tokens, and [PairingManagerAuthenticator] is the
/// adapter production code hands to [GlideSessionServer]. Tests can supply
/// something simpler.
abstract interface class SessionAuthenticator {
  bool isValid(String? presentedToken);
}

/// Accepts any of a fixed set of tokens, compared in constant time. Useful
/// for tests and for simple embeddings where pairing is handled elsewhere.
class FixedTokenAuthenticator implements SessionAuthenticator {
  FixedTokenAuthenticator(Iterable<String> tokens) : _tokens = List.of(tokens);

  factory FixedTokenAuthenticator.single(String token) =>
      FixedTokenAuthenticator(<String>[token]);

  final List<String> _tokens;

  @override
  bool isValid(String? presentedToken) {
    if (presentedToken == null) return false;
    var matched = false;
    for (final token in _tokens) {
      if (constantTimeEquals(presentedToken, token)) matched = true;
    }
    return matched;
  }
}

/// Accepts exactly the session tokens a [PairingManager] has granted and not
/// revoked or rotated away. The one-time QR pairing token is *not* a session
/// token, so it never passes this check.
class PairingManagerAuthenticator implements SessionAuthenticator {
  const PairingManagerAuthenticator(this._manager);

  final PairingManager _manager;

  @override
  bool isValid(String? presentedToken) =>
      presentedToken != null &&
      presentedToken.isNotEmpty &&
      _manager.isSessionTokenValid(presentedToken);
}
