# Security policy

Glide can start builds on a developer's machine on request of a phone, so
security is part of the design rather than an add-on. The full model is in
[docs/security/threat-model.md](docs/security/threat-model.md).

## Reporting a vulnerability

Please do not open a public issue for security problems. Report privately to
the project maintainer (add a contact address or enable GitHub private
vulnerability reporting for the repository before the first public release) and
include steps to reproduce. Expect an acknowledgement, then a fix and a
coordinated disclosure.

## Guarantees the code is designed to keep

- The companion may only send allowlisted commands; there is no remote shell.
- Device ids are validated before they reach any external process.
- Pairing tokens are 256-bit, random, single-use, expire after five minutes,
  are scoped to one session, revocable, and only their hashes are retained.
- Repeated invalid pairing attempts revoke the pairing.
- Secrets (tokens, `.env`, keystores, signing keys) are redacted from output and
  never sent to the companion.
- The session server must bind to a specific LAN interface, never `0.0.0.0`.

Items that are designed but not yet enforced by running code (the server does
not exist until Phase 5) are marked in the threat model.
