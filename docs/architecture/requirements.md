# Supported environments and requirements

## Version 1 scope

| | Supported | Later |
|---|---|---|
| Host | Windows, macOS, Linux | |
| Target device | Android (phones, tablets, emulators) | iOS (Phase 16) |
| Build modes | debug, profile (hot reload needs debug) | |

Release builds do not support hot reload and are out of scope.

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

The minimums live in `GlideRequirements`
(`tools/glide_cli/lib/src/services/versions.dart`). Dart 3.6 is the floor
because the repository uses pub workspaces. They are conservative lower
bounds, not a statement of which Flutter versions have been tested; record the
validated SDK versions here once Glide has run on real devices.
