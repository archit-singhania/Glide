# Vocabulary

| Term | Meaning |
|---|---|
| **Host** | The developer computer running the `glide` CLI, the Flutter SDK and the session server. |
| **Companion** | The Glide mobile app that pairs with a host and remote-controls a session. |
| **Target app** | The developer's own Flutter application being built and run. |
| **Target device** | The phone, tablet or emulator the target app runs on. |
| **Session** | One authenticated connection between a host and a companion, with a lifecycle (`SessionState`). |
| **Pairing** | The one-time exchange (QR code, single-use token, host approval) that turns a companion into an authorised client. |
| **Flutter bridge** | The layer that drives the official Flutter tool over its machine-readable protocols. |
| **Build** | Compiling, installing and launching the target app via `flutter run`. |
| **Reload** | Hot reload: injects changed Dart code and keeps application state. |
| **Restart** | Hot restart: restarts the Dart application and resets its state, keeping the platform app alive. |
| **Full restart** | Rebuild and relaunch the platform app. Required after native (Kotlin, Java, Swift, Objective-C), Gradle, manifest or `pubspec.yaml` changes. |

In the protocol, `app.reload` is a hot reload and `app.restart` takes a `mode`
of `hot` (default) or `full`.
