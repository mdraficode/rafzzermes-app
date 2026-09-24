import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Central config for the app's network endpoints.
///
/// The relay base URL is resolved in this order:
///  1. compile-time --dart-define RELAY_BASE_URL (e.g. for a public tunnel)
///  2. falls back to the LAN/development default.
///
/// Build with a public endpoint:
///   flutter build apk --dart-define=RELAY_BASE_URL=https://relay.rafzzermes.app
class AppConfig {
  static const String publicRelayBaseUrl = String.fromEnvironment(
    'RELAY_BASE_URL',
    defaultValue: '',
  );

  /// LAN/development default; overridden by publicRelayBaseUrl when set.
  /// The default is the live public relay on Oracle Cloud.
  static String get relayBaseUrl {
    if (publicRelayBaseUrl.isNotEmpty) return publicRelayBaseUrl;
    return 'http://79.76.61.69:9602';
  }
}

/// Theme controller for light/dark toggle.
class ThemeProvider extends ChangeNotifier {
  bool _dark = false;
  bool get dark => _dark;
  void toggle() {
    _dark = !_dark;
    notifyListeners();
  }
}
