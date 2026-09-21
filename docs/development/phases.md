# Phase status

"Written" means the files and tests exist. As of the last full run (repo
root: `dart pub get`, `dart fix --apply`, `dart format .`, `dart analyze
--fatal-infos`, `dart run melos run test`), `dart analyze --fatal-infos` was
clean across all 11 pure-Dart packages, and 10 of 11 packages' tests passed.
The 11th, `glide_cli`, had one failing test
(`restart_required_test.dart: Dart-only changes print nothing`), which was a
false positive in the test itself, not a product bug — see "Test fix" below.
Every pure-Dart package including `glide_performance`, `glide_network` and
`glide_build_manager`'s DevTools/monitoring tests are confirmed passing in
that run. `apps/companion`'s last confirmed run was `flutter analyze` clean
with 60 tests passing, before the Phase 13-15 companion UI additions
(performance line, Network sheet, DevTools button) were written — those
additions have not been through `flutter analyze`/`flutter test` yet. All
tests use fakes: nothing here has been run against a real Flutter app, phone
or emulator. "Written" therefore never means "proven on real hardware".

## Test fix: false-positive full-restart assertion

`restart_required_test.dart`'s "Dart-only changes print nothing" test
asserted `isNot(contains('full restart'))` on the whole captured output. But
`RunRenderer.keyHelp` (`r hot reload  R hot restart  F full restart  d
devtools  q quit`) is printed unconditionally the moment the app starts, and
it legitimately contains the substring "full restart" as part of the key
legend, not as a restart-required notice. The assertion was therefore always
going to fail once the key legend gained the DevTools key, regardless of
whether `ChangeClassifier`/`SessionController` behaved correctly. Fixed by
asserting against the two strings that are unique to an actual
`restart.required` notice (`Press F for a full restart.` and `Hot reload
cannot apply`) instead of the generic substring. No production code changed.
This has not been re-run; please confirm with `dart run melos run test` from
`tools/glide_cli` or the repo root.

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
| 11 | Plugin analyzer (`glide plugins`) | Written, analyzed clean, tests pass |
| 12 | Native-change / full-restart detection (`restart.required`, `F` key, companion banner) | Written, analyzed clean; tests pass after fixing a false-positive assertion (see below); never seen a real file watcher event |
| 13 | Performance monitoring (`glide_performance`, `performance.sample`) | Written, analyzed clean, tests pass against a fake VM service. Samples fps/frame time/memory from the real Dart VM service protocol on the computer; the VM service address is never sent to the companion (tested explicitly) |
| 14 | DevTools integration (`d` key in `glide run`, `devtools.open` from the companion) | Written, analyzed clean, tests pass. Opens `dart devtools <address>` on the computer only; the phone gets a status message, never the address |
| 15 | Network inspector (`glide_network`, `network.request`/`network.response`) | Written, analyzed clean, tests pass. Polls the VM service's HTTP profile (no app instrumentation needed); method/status/duration/size only, URLs stripped of query strings, credentials and fragments before leaving the computer |
| 16 | iOS | Partial: `checkIosToolchain` (Xcode/CocoaPods) added to `glide doctor`, skips cleanly on non-macOS hosts, has a passing test. No iOS run pipeline, no build/install/launch support |

## Regression found and fixed (full restart)

The first real `dart run melos run test` run turned up a genuine race, not a
flaky test. `glide_cli`'s full-restart test hung waiting for "Full restart
 completed in", and every test after it in that file then timed out.

Root cause: `SessionController._restart()`'s full-restart path tears the old
session down before launching the new one. Tearing down transitions the
session state machine through `connected`, which is also the state a normal
`glide run`/`glide start` shutdown ends on. `run_command.dart` completed its
"the session is finished" future on the **first** `connected`/`failed`
transition it saw, with no way to tell a transient mid-restart `connected`
apart from a real one. It fired early, mid-restart, which disposed the
controller while the new session was still starting and stopped it out from
under itself, printing "Full restart failed: The app was stopped." The
abandoned real timers and file-watch handles from that hung, never-torn-down
`run()` call are the most likely cause of the cascade of unrelated timeouts
later in the same run.

Fix: `SessionController` now exposes `isRestarting`, true for the whole
window from the decision to do a full restart until the new session starts
or fails, including the teardown step. `run_command.dart`'s completion
listener ignores a `connected`/`failed` transition reached while
`isRestarting` is true. `_teardown` also gained a `_restartTeardownExpected`
flag so its own first step (stopping the old session) no longer mistakes
itself for an external interruption and reports a false `restart.failed`.

This is written but **not re-run** (file access only, no test execution
here). The one other failure in that log, `start_test.dart`'s "exits with an
error when nobody pairs before the code expires" showing a wildcard-address
message in its own output, does not point to a matching bug in
`start_command.dart` on inspection (that test passes `--host 127.0.0.1`
explicitly) and is more consistent with fallout from the hang above than a
separate defect. Re-run and report back if it still fails on its own.

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

## What Phases 11 and 12 added

- `glide_project_analyzer` gained `PluginAnalyzer`. For each direct
  dependency it works out what native code the dependency brings (from
  `.flutter-plugins-dependencies`), whether the plugin registers an
  implementation for every platform the project targets, and whether the host
  project has what well-known plugins need (`Info.plist` usage descriptions,
  Android permissions, Firebase config files). It reads files and never edits
  them. `glide plugins [dir]` prints the result; `--json` and `--strict`
  (exit 1 on a missing requirement or an unsupported platform) are available.
- The requirements table (`plugin_knowledge.dart`) is deliberately small and
  only lists well-established requirements. A plugin that is not in it is
  "unknown", not "fine".
- `ChangeClassifier` decides which changed files matter to a running app:
  `lib/**/*.dart` is hot reloadable; `pubspec.yaml`, `pubspec.lock` and
  anything under `android/` or `ios/` needs a full restart. Build output and
  files regenerated by every build (`build/`, `local.properties`,
  `GeneratedPluginRegistrant.*`, `Pods/`, `Generated.xcconfig`, ...) are
  ignored so a normal build never looks like a native change.
- `ProjectWatcher` turns file system events into debounced `ChangeBatch`es.
- `SessionController.reportProjectChanges` remembers full-restart changes
  while an app is starting or running and publishes `restart.required` (with
  a capped list of reasons). A full restart, stop, exit or failed build clears
  them. The diagnostics snapshot carries them too, so a reconnecting phone sees
  the banner again.
- `glide run` prints the notice and `F` performs the full restart. `glide
  start` runs the same watcher; the companion shows a "Full restart required"
  banner with a button.

## Immediate next steps

1. Re-run `dart run melos run test` (repo root) to confirm the
   `restart_required_test.dart` fix above is green and nothing else regressed.
2. In `apps/companion`: run `flutter analyze` and `flutter test` to check the
   Phase 13-15 additions (performance line, Network sheet, DevTools button,
   AppBar icons) compile and pass — they have never been run. Then add the
   manifest / Info.plist settings from `companion-setup.md`.
3. Prove the riskiest assumption on a real machine: from a Flutter project run
   `glide run -d <device>`, edit a `Text` widget, press `r`, and confirm the
   device updates. Then try `R`, `F`, `d` (DevTools) and `q`.
4. Pair the real companion with `glide start`, tap Run, edit a widget and tap
   Hot reload, then check the performance line and Network sheet against a
   real app making HTTP calls. Report anything the real tool or phone does
   differently from the fakes.
5. Try Phases 11-12 for real: run `glide plugins` in a project with camera or
   geolocator, and edit `AndroidManifest.xml` while `glide run` is up. Confirm
   the notice appears once and an ordinary build does not trigger it.
6. Phase 16 (iOS) is the largest remaining gap: only the doctor check exists;
   there is no iOS build/install/launch pipeline at all.

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

- Native-change detection is per project, not per device: an iOS edit while
  running on Android still prints the notice (it says which platform). Hot
  reload is not blocked while a restart is pending.
- Only `android/`, `ios/`, `pubspec.yaml` and `pubspec.lock` are classified.
  Desktop and web runner folders, `assets/` and generated localisation files
  are ignored.
- The plugin requirements check is literal text matching. An entry inside an
  XML comment counts as present, and Gradle-based configuration (for example a
  manifest placeholder for a Maps key) is not understood.
- `glide plugins` cannot tell a plugin that supports a platform with Dart code
  only from one that does not support it at all unless Flutter registered an
  implementation; it reports what Flutter registered.
- The file watcher has only been exercised through fakes. Real recursive
  watching (especially on Windows and Linux) is untested.

## Open decisions

- License (no `LICENSE` file has been added).
- Security contact address in `SECURITY.md`.
- Which Flutter versions to declare as validated once a real device run works.
