# Contributing to Glide

## Setup

```bash
dart pub get          # resolves the whole pub workspace
dart format .
dart analyze --fatal-infos
dart run melos run test
```

Melos scripts (defined in the root `pubspec.yaml`): `format`, `format:check`,
`analyze`, `test`.

## Working style

Build one phase at a time (see `docs/development/phases.md`). For each phase:
inspect the repo, plan briefly, implement the smallest coherent change, add
tests, run format / analyze / tests, fix failures, update docs, then summarise
what changed.

## Definition of done

- [ ] Implementation complete, not merely compiling
- [ ] `dart format` passes
- [ ] `dart analyze --fatal-infos` passes
- [ ] Relevant unit tests added, and they pass
- [ ] Existing tests still pass
- [ ] No swallowed exceptions; error cases covered
- [ ] No TODO used to hide required work
- [ ] Public API documented; docs updated
- [ ] No secrets committed; no unnecessary dependencies

## Coding standards

- No god classes and no business logic in widgets.
- No shell commands built from untrusted input. Validate ids and paths.
- No hard-coded Flutter, Android SDK or JDK paths; no hard-coded IPs; no
  hard-coded ports without a fallback.
- Do not parse human-readable Flutter output when a machine interface exists.
- Typed models instead of `Map<String, dynamic>` soup.
- Never log tokens. Route output through `Redactor` when it may contain them.
- Never weaken `analysis_options.yaml` or delete a failing test to get green.
- All external processes go through `ProcessLauncher` / `ToolRunner` so they can
  be faked in tests.
