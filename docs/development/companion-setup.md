# Companion app setup (Phase 7)

The Dart code for `apps/companion` is already in the repository (`lib/`,
`test/`, `pubspec.yaml`). What is **not** in the repository is the native
platform scaffolding (`android/`, `ios/`), because only the Flutter tool can
generate it correctly for your installed SDK.

The app is deliberately **outside the pub workspace**: a Flutter app cannot
resolve inside a pure-Dart workspace. It shares the wire protocol through a path
dependency on `packages/glide_protocol`.

## 1. Generate the platform folders

From `apps/companion`:

```bash
cd apps/companion
flutter create --org dev.glide --project-name glide_companion --platforms android,ios .
```

`flutter create .` on an existing project only adds what is missing, so it
should keep `pubspec.yaml`, `lib/main.dart` and `analysis_options.yaml`. Check
with `git diff` (or compare against your copy) that they are unchanged. If it
generated `test/widget_test.dart` (the counter-app test), **delete it**: it
tests an app that does not exist here and will fail.

`--platforms android,ios` works on Windows; you only need a Mac to build iOS.

## 2. Verify

```bash
flutter pub get
flutter analyze
flutter test
```

The tests use fakes for the network, so no computer or phone is needed.

## 3. Platform settings the app needs

**Already applied in this repository** as of the Phase 16 pass —
`android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` already
have the entries below. This section is kept so you know what was added and
why, and so you can re-apply it if you ever regenerate the platform folders
with `flutter create`, which overwrites both files.

### Android (`android/app/src/main/AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />

<application
    android:usesCleartextTraffic="true"
    ... >
```

Debug builds already get `INTERNET` from the debug manifest; release builds do
not, so add it to the main manifest. `usesCleartextTraffic` is set as a
precaution: Dart's own sockets are generally not subject to Android's cleartext
policy, but the setting costs nothing and avoids a confusing failure if a
future Flutter version changes that. Remove it once the channel uses TLS.

If the build reports a `minSdk` problem from `mobile_scanner`, raise
`minSdk` in `android/app/build.gradle(.kts)` to the value it names.

### iOS (`ios/Runner/Info.plist`)

```xml
<key>NSCameraUsageDescription</key>
<string>Glide scans the QR code shown by "glide start" to pair with your computer.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Glide connects to your computer on the local network to control your Flutter app.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

`mobile_scanner` also sets a minimum iOS deployment target; check its README for
the current value and raise `IPHONEOS_DEPLOYMENT_TARGET` / the Podfile
`platform` line if the build asks for it.

## 4. Try it against a real computer

1. In a Flutter project on your computer: `dart run <path>/tools/glide_cli/bin/glide.dart start`.
2. Phone and computer must be on the same Wi-Fi network.
3. On the phone: `flutter run -d <phone>` from `apps/companion`, then tap
   **Scan QR code** (or paste the link printed by `glide start --print-uri`).
4. Check that the session ID on the phone matches the terminal, tap **Connect**,
   and approve the device in the terminal.
5. Tap **Run**, then edit a `Text` widget on the computer and tap **Hot reload**.

If pairing cannot reach the computer, check the firewall on the computer first
(it must allow inbound connections on the port `glide start` prints, 49400 by
default) and that the Wi-Fi network does not isolate clients from each other.
