# Getting started

## Prerequisites

- Dart SDK 3.6+ (installed with Flutter)
- Flutter SDK on `PATH`, or `GLIDE_FLUTTER_SDK` / `FLUTTER_ROOT` /
  `FLUTTER_HOME` pointing at it
- For Android targets: Android SDK with platform-tools, JDK 17+, Git

## First run

```bash
dart pub get
cd tools/glide_cli
dart run bin/glide.dart doctor
dart run bin/glide.dart doctor --json
dart run bin/glide.dart doctor --flutter-sdk C:\src\flutter
```

`glide doctor` exits with `0` when nothing is an error (warnings are allowed)
and `1` when at least one check is an error.

## Verifying a change

```bash
dart format .
dart analyze --fatal-infos
dart run melos run test
```

The first time you run these on a fresh checkout, fix whatever they report
before building further; the code in Phases 0-1 was written without being run.

## Layout of the CLI

```text
tools/glide_cli/
  bin/glide.dart                      entry point
  lib/src/commands/                   one class per command
  lib/src/services/                   detectors and the environment service
  lib/src/ui/                         terminal rendering
  test/                               unit tests with a fake ToolRunner
```
