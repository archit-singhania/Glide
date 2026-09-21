# Glide architecture

## Principle

**Glide orchestrates Flutter; it never reimplements it.** Building, installing,
launching and hot reload are performed by the official Flutter SDK. Glide
starts that tooling, speaks its machine-readable protocol, and exposes the
result to a paired companion app.

Never parse human-readable Flutter output when a machine-readable interface
exists. Use `flutter --version --machine`, `flutter devices --machine`,
`flutter daemon` and `flutter run --machine`.

## Components

```text
                DEVELOPER COMPUTER (host)
   Flutter project
        |
   glide CLI ---- glide_project_analyzer   (pubspec, plugins, platforms)
        |
        +-------- glide_flutter_bridge  ->  official Flutter SDK
        |                                     flutter daemon
        |                                     flutter run --machine
        +-------- glide_device_manager        (device state)
        +-------- glide_build_manager         (session orchestration)
        +-------- glide_session_server  <----- HTTP + WebSocket (LAN only)
                        |                          ^
                  glide_security                   |
                  glide_protocol            Glide companion app
                                            (Flutter, on the phone)
```

| Package | Responsibility | Depends on |
|---|---|---|
| `glide_protocol` | Envelope, message types, command allowlist, pairing URI, session state machine | nothing |
| `glide_security` | Single-use pairing tokens, session tokens, redaction, sensitive-path guard, LAN policy | protocol |
| `glide_flutter_bridge` | Process handling, machine-protocol parsing, daemon supervision, `flutter run` session | protocol |
| `glide_project_analyzer` | Read `pubspec.yaml`, platforms, native plugins, classify file changes | protocol |
| `glide_device_manager` | Device discovery and per-device state | bridge, protocol |
| `glide_log_parser` | Normalise tool output into `DiagnosticEvent` | protocol |
| `glide_session_server` | Authenticated local HTTP/WebSocket server | log parser, protocol, security |
| `glide_build_manager` | run / reload / restart / watch orchestration | device manager, bridge, log parser, analyzer, protocol |
| `glide_cli` | The `glide` executable | all of the above |

## Boundary rules

1. UI code (CLI rendering, companion widgets) never spawns processes. All
   external process work goes through `ProcessLauncher` / `ToolRunner`
   (`glide_flutter_bridge`), which tests replace with fakes.
2. The companion is untrusted until pairing completes, and afterwards it may
   only send commands from the allowlist in `CompanionCommandType`. There is no
   command that carries a shell string or an arbitrary path.
3. Sessions are explicit state machines (`SessionStateMachine`), not sets of
   booleans. Illegal transitions throw.
4. Expected failures are typed (`GlideException` subclasses). Nothing is
   swallowed silently; tool failures become check results, diagnostics or
   exceptions.
5. Typed models everywhere; `Map<String, Object?>` only at JSON boundaries.
6. No cloud dependency. Phone and host talk over the local network.

## Session flow (target)

```text
glide start
  -> analyse project, locate SDK, list devices
  -> start session server (LAN address only), issue pairing credential
  -> show QR (glide://pair?...)
  -> companion scans, connects, redeems token, host approves
  -> session token issued, pairing token burned
  -> companion sends allowlisted commands (app.run, app.reload, ...)
  -> bridge drives `flutter run --machine`; events flow back as GlideMessages
```

Implemented today: the protocol, the security primitives, the bridge and
`glide doctor`. The flow above is assembled in Phases 4-9.
