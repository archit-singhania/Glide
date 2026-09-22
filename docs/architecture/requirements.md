# Supported environments and requirements

## Version 1 scope

| | Supported | Later |
|---|---|---|
| Host | Windows, macOS, Linux for Android; **macOS only for iOS** (Xcode requirement) | |
| Target device | Android (phones, tablets, emulators); **iOS (phones, simulators) — Phase 16** | |
| Build modes | debug, profile (hot reload needs debug) | |

Release builds do not support hot reload and are out of scope.

Glide's run pipeline (`glide run`, `glide start`, hot reload/restart, plugin
analysis, native-change detection, performance sampling, DevTools, the
network inspector) is platform-agnostic by construction: it drives the
official `flutter run --machine -d <device-id>` for whatever device id it is
given, so an iOS device or simulator works through the exact same code path
as Android once one is discovered by `glide devices`. The iOS-specific parts
are the doctor's toolchain check (Xcode/CocoaPods) and the fact that only a
Mac can build and codesign an iOS app at all — Glide does not, and cannot,
work around that. **None of this has been run on a real Mac or iOS device**;
it is written and unit-tested against fakes only.

## Minimum toolchain checked by `glide doctor`

| Requirement | Minimum | Severity if missing |
|---|---|---|
| Flutter SDK | 3.27.0 | error |
| Dart SDK (bundled with Flutter) | 3.6.0 | error |
| Android SDK with platform-tools | present | error |
| `adb` | runnable | error |
| Git | runnable | error |
| JDK | 17 (Android Gradle Plugin 8 needs it) | warning, Flutter can use Android Studio's bundled JDK |
| Connected Android device | one | warning |
| LAN address | one private IPv4 address | warning |
| Xcode (macOS host only) | runnable `xcodebuild -version` | warning; skipped entirely on non-macOS hosts |
| CocoaPods (macOS host only) | runnable `pod --version` | warning; some plugins still need it even with Swift Package Manager |

The minimums live in `GlideRequirements`
(`tools/glide_cli/lib/src/services/versions.dart`). Dart 3.6 is the floor
because the repository uses pub workspaces. They are conservative lower
bounds, not a statement of which Flutter versions have been tested; record the
validated SDK versions here once Glide has run on real devices.

## What `glide doctor` does **not** check for iOS

- Whether Xcode's license has been accepted (`sudo xcodebuild -license`).
- Whether a signing team / provisioning profile is configured in the Xcode
  project — `flutter run -d <ios-device>` will fail with Xcode's own error if
  not, and Glide just relays that error text; it does not diagnose it.
- Whether a physical iPhone has been told to "Trust This Computer" — this is
  an iOS-side prompt outside any tool's control.
- Whether Xcode has downloaded device support for the iOS version on a
  connected phone (Xcode prompts for this itself, per-device, on first
  connect).

These are real prerequisites for a successful iOS run; they simply are not
automated checks yet. If `glide run -d <ios-device>` fails, read the error
text Flutter/Xcode produced — Glide forwards it verbatim rather than
swallowing or reinterpreting it.
