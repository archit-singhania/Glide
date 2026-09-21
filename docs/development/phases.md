# Phase status

"Written" means the files and tests exist. As of the last full run, `dart
analyze --fatal-infos` was clean and every pure-Dart package's tests passed
(`dart run melos run test`). Those tests use fakes: nothing here has been run
against a real Flutter app, phone or emulator, and the Flutter companion
(`apps/companion`) has not been analysed or tested yet because its platform
folders have not been generated. "Written" therefore never means "proven on
real hardware".

| Phase | Scope | State |
|---|---|---|
| 0 | Repository and architecture foundation | Written |
| 1 | Environment doctor (`glide doctor`) | Written with unit tests; never run against a real machine |
| 2 | Project analyzer (`glide inspect`) | Written with unit tests; CLI wired |
| 3 | Flutter machine-protocol bridge | Written with unit tests and a fake process |
| 4 | Device discovery (`glide devices`) | Written with unit tests; CLI wired |
| 5 | Local session server | Written with unit tests |
| 6 | Secure QR pairing (`glide start`) | Written with unit and loopback integration tests |
| 7 | Mobile companion MVP | Dart code and tests written (scanner, paste-a-link, pairing, dashboard with run/reload/restart/stop, logs, structured errors, reconnect). Platform folders generated. First `flutter test` run: 59 of 62 passed; the failures were the generated counter-app test (removed) and one widget-test timing issue (fixed, awaiting re-run). Never run on a device or emulator; see `companion-setup.md` |
| 8 | Android run pipeline (`glide run`, `app.run` over the companion channel) | Written with unit tests against a fake app session; never run against a real Flutter app |
| 9 | Hot reload and restart (`r`/`R`/`F` in `glide run`, `app.reload`/`app.restart` from the companion) | Written with unit tests against a fake app session; never run against a real Flutter app |
| 10 | Logs and diagnostics | Written with unit tests: output becomes `log.entry` and, when a line is a Dart, Kotlin, Gradle or Flutter-framework error, also `error.reported` (`glide_log_parser`). Single-line patterns only; multi-line Gradle explanations are not stitched together |
| 11-16 | Plugin analyzer, full-restart detection, performance, DevTools, network, iOS | Not started |

## What Phase 7 added

- `apps/companion` is a Flutter app (Riverpod, go_router, mobile_scanner). It
  is outside the pub workspace and depends on `glide_protocol` by path, so the
  phone and the CLI share one set of wire models.
- `CompanionClient` performs the `/pair` handshake and opens `/ws` with the
  session token in `x-glide-control-token`. Network access goes through a small
  `MessageChannel` interface, so every test runs against an in-memory fake.
- `SessionNotifier` owns the connection. `reduceMessage` (a pure function)
  turns each host message into the next `SessionView`, and the screens only
  render that view.
- The session token is kept **in memory only**. If the connection drops, the
  dashboard offers **Reconnect**, which reuses the token and asks the host for a
  fresh snapshot. Leaving on purpose discards the token; getting back in needs a
  new QR code.
- Buttons are enabled from the host's session state (for example, reload only
  while `running`), and the host still rejects anything invalid.
- The root `analysis_options.yaml` excludes `apps/**`, and CI has a separate
  `companion` job (`flutter analyze`, `flutter test`).

## What Phases 8 and 9 added

- `glide_build_manager` now holds `SessionController`. It is the only thing
  that drives the session state machine while an app runs. Commands go in
  through `handle()`; protocol messages come out through an `EventPublisher`.
  `glide run` prints them, `glide start` sends them to the paired companion.
- Commands are processed one at a time, in order. `app.run` returns as soon as
  `flutter run --machine` has started, so `app.stop` is never stuck behind a
  slow build.
- A **hot restart** keeps the platform app alive. A **full restart** stops the
  `flutter run` process and starts a new one, which rebuilds the platform app.
- The Dart VM service URI is never published to the companion, because it
  carries a credential for the running app.
- `glide run` output from the device is stripped of control characters before
  it reaches the terminal.
- `package:glide_build_manager/testing.dart` exports `FakeAppSession`, used by
  the controller and CLI tests.

## Immediate next steps

1. In `apps/companion`: add the manifest / Info.plist settings from
   `companion-setup.md`, then re-run `flutter analyze` and `flutter test`.
2. Prove the riskiest assumption on a real machine: from a Flutter project run
   `glide run -d <device>`, edit a `Text` widget, press `r`, and confirm the
   device updates. Then try `R`, `F` and `q`.
3. Pair the real companion with `glide start`, tap Run, edit a widget and tap
   Hot reload. Report anything the real tool or phone does differently from
   the fakes.
4. Phase 11 (plugin analyzer) and Phase 12 (native-change / full-restart
   detection) are the next planned features.

## Known limitations

- The session channel is plain `ws://`/`http://` on the LAN. A session token
  can be observed by anyone who can sniff the network. Acceptable for the
  local-development MVP on a trusted network; TLS or a token-bound handshake
  should be designed before any wider use.
- `/pair` is unauthenticated by design. Five wrong tokens revoke the pending
  pairing, so a hostile device on the LAN can force a re-run of `glide start`
  (a denial of service, not a bypass).
- There are no separate `glide reload`, `glide restart` or `glide stop`
  commands. They would need a local control channel into a running
  `glide run`/`glide start`; today those keys and commands work only inside
  that session.
- `glide start` lets a paired companion run the app without asking the
  developer again. Pairing approval is the only consent step.
- Log lines from the app are forwarded to the companion unredacted. An app
  that prints secrets will show them on the phone.
- The `installing` state is inferred from the Flutter tool's English progress
  text ("Installing ..."), so it may be skipped on other locales or versions.
- `glide devices --watch` has no graceful SIGINT handling yet.
- The terminal approval prompt uses blocking `stdin.readLineSync` and has no
  automated test.
- The single-key reader in `glide run` (`terminalKeys`) has no automated test;
  tests inject keys instead.
- The companion has never run on a device. Its Android and iOS settings
  (cleartext `ws://`, camera, local network) are documented but unverified.
- Every companion reports the same device name ("Glide Companion") to the
  host's approval prompt; only the random device id differs. A real model name
  would need an extra plugin.
- The companion has no history of past computers or projects: the pairing token
  is single-use, so there is nothing useful to remember.
- Reconnect works only while `glide start` is still running on the computer. A
  restarted `glide start` issues a new session, so the phone has to scan again.

## Open decisions

- License (no `LICENSE` file has been added).
- Security contact address in `SECURITY.md`.
- Which Flutter versions to declare as validated once a real device run works.
