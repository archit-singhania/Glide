# Threat model

## Assets

The developer's machine and source tree, signing keys and credentials
(`.env`, keystores, service-account files, SSH keys), and the development
session itself.

## Actors

- **Legitimate companion** - the developer's own phone after pairing.
- **Network attacker** - anyone on the same Wi-Fi who can reach the host.
- **Shoulder surfer** - someone who photographs the QR code.

## Controls

| Threat | Control | State |
|---|---|---|
| Companion runs arbitrary commands | Allowlisted command enum; no shell field in any message; device ids validated | Implemented (`glide_protocol`), covered by tests |
| Stolen or replayed QR code | Single-use, 256-bit, 5 minute token; hashes only retained; token burned on success | Implemented (`PairingManager`), covered by tests |
| Token guessing | Constant-time compare; pairing revoked after 5 failed attempts | Implemented, covered by tests |
| Unwanted device pairs | Optional host approval callback; rejection burns the credential | Implemented, covered by tests |
| Long-lived session token theft | Session token rotation and revocation | Implemented, covered by tests |
| Secrets in logs or on screen | `Redactor` masks registered secrets and token patterns | Implemented, covered by tests |
| Secret files sent to the phone | `SensitivePathGuard` classifies `.env`, keystores, keys, credentials | Implemented; must be enforced wherever files are served (Phase 5+) |
| Exposure beyond the LAN | Bind to one private interface, never `0.0.0.0`; `NetworkPolicy` helpers | Helpers implemented; server does not exist yet (Phase 5) |
| Oversized or malformed frames | 256 KiB limit and strict envelope validation | Implemented, covered by tests |
| Command injection through Windows `.bat` shells | Device ids restricted to a safe character set before use | Implemented |

## Not yet addressed

- Transport encryption: the LAN channel is plain WebSocket. Decide in Phase 5
  whether to add TLS with certificate pinning through the QR payload.
- Host-side persistence of the local control token (`.glide/`, ignored by Git).
- Rate limiting per remote address.
