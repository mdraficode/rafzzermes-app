# Rafzzermes App — Source Audit

Audited 2026-09-24 against commit `9e457c2` ("Update README.md"), the first commit containing
actual source. 31 files, ~26 KB of Dart across 6 files.

**Bottom line:** the project was not buildable as pushed, and even if it had compiled, the
release APK would have been unable to make a single network request. Five defects blocked
it. All five are fixed on this branch. What I could **not** do is compile it — see the last
section.

---

## Release-blocking defects (fixed)

### 1. No `INTERNET` permission in the release manifest — fatal

`android/app/src/debug/AndroidManifest.xml` and `.../profile/AndroidManifest.xml` each
declared `<uses-permission android:name="android.permission.INTERNET"/>`. The **main**
manifest declared nothing.

Those are build-type overlays. A debug build merges `debug/AndroidManifest.xml` in, so debug
works. A **release** build merges neither — so the release APK ships with no network
permission at all. Every `http.post` and every `WebSocketChannel.connect` would throw a
`SecurityException`.

This is the specific failure mode of "works in debug, dead in release," and it kills this
app entirely, because the app is nothing but network calls.

**Fixed:** added `<uses-permission android:name="android.permission.INTERNET"/>` to
`android/app/src/main/AndroidManifest.xml`.

### 2. Cleartext HTTP blocked on Android 9+ — fatal

`lib/core/config.dart` defaults the relay to a plain-HTTP URL:

```dart
return 'http://79.76.61.69:9602';
```

Android 9 (API 28) and later set `cleartextTrafficPermitted=false` by default. Nothing in
the project opted back in — no `android:usesCleartextTraffic`, no `networkSecurityConfig`.
Every request would fail with `java.io.IOException: Cleartext HTTP traffic to 79.76.61.69
not permitted`.

**Fixed:** added `android/app/src/main/res/xml/network_security_config.xml` and referenced it
from the manifest. This is the *minimum* change to make the app function, not the secure end
state — see Security below.

### 3. `firebase_messaging` declared but unused, with no Firebase config — build blocker

`pubspec.yaml` declared `firebase_messaging: ^15.2.0`. Grepping `lib/` for `firebase`
returns **only that pubspec line** — zero imports, zero usage. The lockfile pulled in
`firebase_core 3.15.2` transitively, and the committed `GeneratedPluginRegistrant.java`
registered both `FlutterFirebaseCorePlugin` and `FlutterFirebaseMessagingPlugin`.

But there is no `google-services.json` anywhere in the repo, and the `com.google.gms.google-services`
Gradle plugin is not applied. FlutterFire's documented setup requires both.

**Fixed:** removed `firebase_messaging` from `pubspec.yaml`. Also removed
`webview_flutter: ^4.11.0`, which likewise had **zero** usage in `lib/` and was dragging in
the `jni` + `jni_flutter` native plugins (both 1.0.3, both transitive).

> Confidence note: I am confident the dependency was dead weight and that its removal is
> correct. I am *not* certain whether it failed at build time or at first `Firebase.app`
> call — I could not run a build to observe it. Removal makes the question moot.

### 4. `android/local.properties` committed with another machine's paths

The committed file read:

```properties
flutter.sdk=/opt/flutter
sdk.dir=/opt/android
```

Neither path exists here, and they are sandbox paths, not a developer's.
`android/settings.gradle.kts` hard-requires the first of them:

```kotlin
file("local.properties").inputStream().use { properties.load(it) }
val flutterSdkPath = properties.getProperty("flutter.sdk")
require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
```

Note the `file(...).inputStream()` call — it throws `FileNotFoundException` if the file is
*absent*, it does not return null. Flutter's own template ships this file, and `flutter
build` regenerates it, so a normal `flutter build apk` overwrites it before Gradle runs. But
a stale committed copy pointing at `/opt/flutter` is a trap for anyone running `./gradlew`
directly.

**Fixed:** deleted from the repo and added to `.gitignore`. Documented in the README.

### 5. `android.aapt2FromMavenOverride=` set to an empty value

```properties
android.aapt2FromMavenOverride=
```

This property tells AGP to use a specific `aapt2` binary *instead of* the Maven-provided
one. Setting it to an empty string points it at nothing. A standard `flutter create` does
not emit this line.

**Fixed:** removed. Also reduced `org.gradle.jvmargs` from `-Xmx8G -XX:MaxMetaspaceSize=4G`
to `-Xmx4G -XX:MaxMetaspaceSize=1G` — 8 GB of heap will not start on a typical dev machine
or CI runner, and a Flutter app this size does not need it.

> Unverified: I could not execute Gradle, so I did not observe this property actually
> failing a build. It is non-standard and meaningless at best; removing it is safe either way.

---

## Toolchain: what the README claimed vs. what the build actually needs

The project pins **AGP 9.1.0** and **Gradle 9.3.1**. Checked against the AGP compatibility
table on developer.android.com:

| Component | Old README said | Actually required | Verdict |
|---|---|---|---|
| Gradle | 9.3.1 | 9.3.1 (AGP 9.1 minimum) | ✅ correct |
| JDK | "Java 21+" | 17 minimum | ⚠️ overstated, harmless |
| Build-Tools | `build-tools;34.0.0` | **36.0.0** | ❌ **wrong** |
| Android platform | `platforms;android-34` | 34+ (36 to match) | ⚠️ thin |
| Flutter | 3.47+ | 3.44+ (per resolved lockfile) | ⚠️ overstated |

AGP 9.1 defaults to SDK Build-Tools **36.0.0**. Installing only 34.0.0 as instructed would
have failed the build. **Fixed** in the README.

Also fixed: the README's build command was `flutter build apk --debug`, producing
`app-debug.apk`. Changed to `--release` → `app-release.apk`.

### Version constraint mismatch in `pubspec.yaml`

```yaml
environment:
  sdk: '>=3.7.0 <4.0.0'
```

But the resolved lockfile's `sdks:` section read `dart: ">=3.12.0 <4.0.0"`. So the declared
floor was a lie: `pub get` would fail on any toolchain between Dart 3.7 and 3.11 with a
version-solving error. **Fixed** to `>=3.12.0 <4.0.0` plus `flutter: '>=3.44.0'`.

---

## Residual risk: third-party plugins vs. AGP 9

AGP 9 turned a long-standing warning into a **hard build failure**: a plugin Gradle module
that hard-codes a low `compileSdk` fallback (a common `safeExtGet('compileSdkVersion', 31)`
pattern) now breaks the build, because setting `compileSdk` in the *app* module has no
effect on a plugin's separate module. This is documented against real Flutter plugins and
blocks their AGP 9 migration.

`flutter_secure_storage 9.2.4`, `http 1.6.0`, `provider 6.1.5+1` and
`web_socket_channel 3.0.3` all ship Android modules. **I have not verified** whether any of
them hard-codes an old `compileSdk`. If `flutter build apk --release` fails with a
compileSdk error naming a plugin, the workaround is to add to the **root**
`android/build.gradle.kts`:

```kotlin
extra["compileSdkVersion"] = 36
```

---

## Security

**Credentials travel in cleartext.** `lib/core/client/relay_client.dart` POSTs username and
password to `http://79.76.61.69:9602/auth/login` over plain HTTP. Anyone on the same
network can read them. Fix #2 above made this *work*; it did not make it *safe*. Put the
relay behind TLS and then narrow or delete `network_security_config.xml`.

**A raw IP is hard-coded as the production default** in `lib/core/config.dart`. There is a
`--dart-define=RELAY_BASE_URL` override, which is good, but the fallback ships in every APK
that does not set it.

**The bearer token is passed as a WebSocket query parameter**
(`Uri.replace(queryParameters: {'token': token})` in `relay_client.dart`). Query strings are
routinely logged by proxies and servers. Prefer a header or a subprotocol.

---

## Code-quality issues

**Hard-coded fake chat history (fixed).** `_ChatScreenState._messages` was pre-seeded with
`'Hello, I am ready to help.'` and `'Summarize the Hermes state.'`, rendered as if they were
real conversation. A fresh install would show a conversation the user never had. Removed.

**Unused imports (fixed).** `lib/main.dart` imported `flutter_secure_storage` and never used
it. `lib/core/config.dart` imported `package:flutter/material.dart` for nothing — its only
Flutter need, `ChangeNotifier`, comes via `provider`.

**Not fixed — worth your attention:**

- `RelayProvider.connect()` sets `_connected = true` synchronously, before the WebSocket
  handshake completes. The UI will report "connected" even when the connection fails.
- Each `connect()` calls `_relay.connect()`, which builds a **new** `WebSocketChannel`
  without closing the previous one. Repeated login/logout leaks sockets.
- `login_screen.dart` writes the token to secure storage and calls `_relayClient.connect()`
  on its *own* `RelayClient` instance, then calls `widget.onLogin(token)` →
  `RelayProvider.setToken` → which connects a *second* client. Two sockets per login.
- `_pushStatus()` in `chat_screen.dart` takes `emoji` and `action` parameters that every
  call site leaves at their defaults.

**No tests.** There is no `test/` directory at all, so `flutter test` has nothing to run and
"verify everything is working" has no automated meaning for this project.

**No `.gitignore`** — added.

---

## What I verified, and what I could not

Verified by execution in this environment:

| Check | Result |
|---|---|
| All 8 Android XML files parse | 0 failures |
| `pubspec.yaml` parses as YAML (PyYAML 6.0.3) | OK |
| Every `package:` import in `lib/` is a declared dependency | none undeclared |
| `firebase_messaging` / `webview_flutter` gone from deps | confirmed |
| Every relative Dart import resolves to a real file | 0 broken |
| `networkSecurityConfig="@xml/network_security_config"` → file exists | confirmed |
| AGP 9.1 ↔ Gradle 9.3.1 ↔ JDK 17 ↔ Build-Tools 36 | confirmed vs. developer.android.com |

**Could not verify — no build was run.** This sandbox has no `java`, `flutter`, `dart`,
`gradle`, `adb`, `aapt` or `apksigner`; no JDK anywhere; `apt-get update` is denied; and
`dl.google.com`, `maven.google.com`, `services.gradle.org`, `storage.googleapis.com` and
`pub.dev` are all unreachable (`000`). So I could not run `flutter pub get`,
`dart analyze`, `flutter test` or `flutter build apk`.

That means the fixes above are **not proven by a compiler**. They are derived from reading
the code and the manifests, and checked against the Android platform's documented behaviour.
The single highest-value next step is to run `flutter build apk --release` on a real
toolchain and read the output.

---

## Files changed on this branch

| File | Change |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | + INTERNET permission, + networkSecurityConfig ref |
| `android/app/src/main/res/xml/network_security_config.xml` | **new** |
| `pubspec.yaml` | − firebase_messaging, − webview_flutter, fixed SDK floor |
| `pubspec.lock` | **deleted** (stale; regenerate with `flutter pub get`) |
| `android/local.properties` | **deleted** (machine-specific) |
| `android/gradle.properties` | − aapt2FromMavenOverride, smaller heap |
| `lib/main.dart` | − unused import |
| `lib/core/config.dart` | − unused import |
| `lib/features/chat/chat_screen.dart` | − hard-coded fake history |
| `README.md` | corrected toolchain versions + release build |
| `.gitignore` | **new** |
| `rafzzermes_app.zip` | **deleted** (0 bytes) |
