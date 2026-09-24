# Rafzzermes App - Flutter Project Bundle

## Build Instructions
1. Install Flutter SDK 3.47+
2. Install Android SDK with: platform-tools, platforms;android-34, build-tools;34.0.0
3. Run: flutter pub get
4. Run: flutter build apk --debug
5. APK location: build/app/outputs/flutter-apk/app-debug.apk

## Project Files
- lib/main.dart - App entry
- lib/core/config.dart - Configuration
- lib/core/relay_provider.dart - State management
- lib/core/client/relay_client.dart - API client
- lib/features/auth/login_screen.dart - Login UI
- lib/features/chat/chat_screen.dart - Chat UI

## Requirements
- Flutter 3.47+
- Java 21+
- Android SDK 34+
- Gradle 9.3.1
