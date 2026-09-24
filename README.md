# Rafzzermes App — Flutter Project

Android-only Flutter client for the Rafzzermes relay (WebSocket `/sync` + HTTP `/auth/login`, `/v1/chat`, `/v1/models`).

## Build

```bash
flutter pub get
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

The release build type signs with the **debug** keystore (`android/app/build.gradle.kts`), so
this APK installs directly for testing. Add a real `signingConfigs.release` before shipping.

## Required toolchain

Verified against the AGP compatibility table on developer.android.com — this project pins
**AGP 9.1.0** in `android/settings.gradle.kts`.

| Component | Required | Why |
|---|---|---|
| Gradle | **9.3.1** | AGP 9.1 minimum. Already pinned in `gradle-wrapper.properties`. |
| JDK | **17+** | AGP 9.x minimum. `build.gradle.kts` targets JVM 17. |
| SDK Build-Tools | **36.0.0** | AGP 9.1 default. (An earlier README said 34.0.0 — that is wrong.) |
| Android platform | **34+** | `platforms;android-34` minimum; 36 to match build-tools. |
| Flutter | **3.44+** | Lockfile resolved to packages needing Dart `>=3.12.0`. |

```bash
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

## Notes

- `pubspec.lock` is not committed. Run `flutter pub get` to resolve.
- `android/local.properties` is not committed (it is machine-specific). `flutter build`
  generates it. If you run `./gradlew` directly instead of via `flutter`, create it first
  with `flutter.sdk=` and `sdk.dir=` pointing at your SDKs — `settings.gradle.kts`
  hard-fails without `flutter.sdk`.
- Override the relay endpoint at build time:
  ```bash
  flutter build apk --release --dart-define=RELAY_BASE_URL=https://relay.rafzzermes.app
  ```

## Project layout

| Path | Purpose |
|---|---|
| `lib/main.dart` | App entry, provider wiring |
| `lib/core/config.dart` | Relay endpoint config, theme provider |
| `lib/core/relay_provider.dart` | Token storage + relay state |
| `lib/core/client/relay_client.dart` | WebSocket + HTTP client |
| `lib/features/auth/login_screen.dart` | Login UI |
| `lib/features/chat/chat_screen.dart` | Chat UI |

## Known issues

See `ANALYSIS.md` for the full audit, including the cleartext-HTTP credential exposure in
`lib/core/config.dart` and the missing test suite.
