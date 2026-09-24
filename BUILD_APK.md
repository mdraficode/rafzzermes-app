# Rafzzermes App — Building the Release APK

**Target:** `build/app/outputs/flutter-apk/app-release.apk`

This guide is now project-specific. See `ANALYSIS.md` for the audit of what was broken and
what was fixed.

---

## 0. Toolchain

The project pins **AGP 9.1.0** (`android/settings.gradle.kts`) and **Gradle 9.3.1**
(`android/gradle/wrapper/gradle-wrapper.properties`). Requirements verified against the AGP
compatibility table on developer.android.com:

| Component | Required | Notes |
|---|---|---|
| Gradle | **9.3.1** | AGP 9.1 minimum. Wrapper already pinned — you download nothing by hand. |
| JDK | **17+** | AGP 9.x minimum. `build.gradle.kts` targets JVM 17. |
| SDK Build-Tools | **36.0.0** | AGP 9.1 default. *Not* 34.0.0. |
| Android platform | `platforms;android-34` min, `android-36` to match | |
| Flutter | **3.44+** | Resolved packages need Dart `>=3.12.0`. |

```bash
flutter doctor -v
java -version        # 17 or newer
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

---

## 1. Dependencies

`pubspec.lock` is deliberately not committed (the pushed one was stale). Resolve fresh:

```bash
flutter clean
flutter pub get
```

This regenerates `.dart_tool/` and `android/local.properties`.

## 2. Analyze and test

```bash
dart analyze
flutter test
```

Expect `flutter test` to report **no tests found** — this project has no `test/` directory.
That is not a pass, it is an absence. See ANALYSIS.md.

## 3. Build

```bash
flutter build apk --release
```

Expected on success:

```
Running Gradle task 'assembleRelease'...                          148.2s
√  Built build/app/outputs/flutter-apk/app-release.apk (NN.NMB).
```

`android/app/build.gradle.kts` sets `signingConfig = signingConfigs.getByName("debug")` for
the release build type, so this APK is debug-signed and **installs directly** on a device.
Add a real keystore before distributing — see §6.

To point the app at a different relay:

```bash
flutter build apk --release --dart-define=RELAY_BASE_URL=https://relay.rafzzermes.app
```

Without that define it falls back to the hard-coded `http://79.76.61.69:9602` in
`lib/core/config.dart`.

### If the build fails on a plugin's compileSdk

AGP 9 turned a warning into a hard failure: a plugin Gradle module that hard-codes a low
`compileSdk` fallback now breaks the build, and setting `compileSdk` in the *app* module does
not reach it. If you see a compileSdk error naming `flutter_secure_storage` or another
plugin, add to the **root** `android/build.gradle.kts`:

```kotlin
extra["compileSdkVersion"] = 36
```

## 4. Verify the artifact

A green build hides some mistakes. Check these:

```bash
ls -lh build/app/outputs/flutter-apk/app-release.apk

BUILD_TOOLS=$ANDROID_HOME/build-tools/36.0.0
```

The two checks that matter most for this project:

```bash
# (a) INTERNET permission actually made it into the merged release manifest.
#     This was missing before the fix — the release APK had no network at all.
"$BUILD_TOOLS/aapt" dump permissions build/app/outputs/flutter-apk/app-release.apk \
  | grep -i internet

# (b) the network security config is present, so cleartext HTTP is allowed.
"$BUILD_TOOLS/aapt" dump xmltree build/app/outputs/flutter-apk/app-release.apk \
  AndroidManifest.xml | grep -i networkSecurityConfig
```

Both must produce output. Then the usual:

```bash
"$BUILD_TOOLS/apksigner" verify --print-certs --verbose \
  build/app/outputs/flutter-apk/app-release.apk

"$BUILD_TOOLS/aapt" dump badging build/app/outputs/flutter-apk/app-release.apk \
  | grep -E "package:|launchable-activity:|sdkVersion:|targetSdkVersion:"
```

`package:` should read `com.rafzzermes.rafzzermes_app` and `launchable-activity:` should be
present.

## 5. Install and smoke-test

```bash
adb devices                                  # must read "device", not "unauthorized"
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c && adb logcat -s flutter       # clear, then watch live
```

### What "working correctly" means for this app

1. **Log in.** This exercises `POST /auth/login`. Before the fixes this could not work at
   all in a release build. If it fails, `adb logcat` will show either
   `SecurityException` (permission) or `Cleartext HTTP traffic ... not permitted`
   (network config) — those two messages tell you exactly which fix regressed.
2. **Send a chat message.** Exercises the SSE stream on `POST /v1/chat`.
3. **Background and return.** The WebSocket has no reconnect logic; expect it to drop.
4. **Release-only paths.** R8 minifies. Reflection and dynamic `Type` lookups can pass in
   debug and crash only in release. Exercise every screen on the release build, not the
   debug one.
5. **Confirm the fake history is gone.** A fresh install should show an empty chat, not
   `'Hello, I am ready to help.'` / `'Summarize the Hermes state.'`.

Known non-fatal bugs to expect: the UI reports "connected" before the WebSocket actually
connects, and repeated login/logout leaks sockets. Both are documented in ANALYSIS.md and
neither blocks a build.

## 6. Real signing, for distribution

```bash
keytool -genkey -v -keystore ~/rafzzermes-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias rafzzermes
```

`android/key.properties` (already git-ignored):

```properties
storePassword=...
keyPassword=...
keyAlias=rafzzermes
storeFile=/absolute/path/to/rafzzermes-release.jks
```

Then in `android/app/build.gradle.kts`, replace the debug signing line:

```kotlin
signingConfig = signingConfigs.getByName("debug")
```

with a `signingConfigs.release` block loaded from `key.properties`. Back the `.jks` up —
losing it means you can never ship an update to existing users.

---

## Not verified

No build was run to produce this guide. This sandbox has no `java`, `flutter`, `dart`,
`gradle`, `adb`, `aapt` or `apksigner`, no JDK, a denied `apt-get`, and no network route to
`dl.google.com`, `maven.google.com`, `services.gradle.org`, `storage.googleapis.com` or
`pub.dev` (all `000`). The commands above are checked for syntax and against the documented
toolchain requirements, not executed.
