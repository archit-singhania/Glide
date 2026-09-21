# Changelog

All notable changes are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Pub workspace with eight packages and the `glide_cli` tool.
- `glide_protocol`: versioned envelope, message types, command allowlist,
  pairing URI, session state machine, diagnostics models.
- `glide_security`: pairing manager, session tokens, redaction, sensitive-path
  guard, LAN policy.
- `glide_flutter_bridge`: process abstraction, machine-protocol parser,
  daemon supervisor, `flutter run --machine` session (public barrel added).
- `glide doctor` (text and `--json`): Flutter SDK, Flutter and Dart versions,
  Android SDK, ADB, Java, Git, devices and LAN addresses.
- Documentation, CI workflow, contributing and security policies.
