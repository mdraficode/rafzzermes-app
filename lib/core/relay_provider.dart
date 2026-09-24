import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'client/relay_client.dart';
import 'config.dart';
import 'dart:async';

/// Holds the stored token and RelayClient instance.
/// Consumed by LoginScreen and ChatScreen via Provider.of.
class RelayProvider extends ChangeNotifier {
  final FlutterSecureStorage _storage;
  String? _token;
  late final RelayClient _relay;
  bool _loaded = false;
  bool _connected = false;
  
  StreamSubscription<(String, Map<String, dynamic>)>? _eventSub;

  RelayProvider({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage() {
    _relay = RelayClient(baseUrl: AppConfig.relayBaseUrl);
    _loadToken();
  }

  String? get token => _token;
  bool get loaded => _loaded;
  bool get connected => _connected;
  RelayClient get relay => _relay;
  bool get isLoggedIn => _token != null;

  Future<void> _loadToken() async {
    try {
      _token = await _storage.read(key: 'relay_token');
    } catch (_) {}
    _loaded = true;
    notifyListeners();
    if (_token != null) {
      connect();
    }
  }

  Future<void> setToken(String t) async {
    await _storage.write(key: 'relay_token', value: t);
    _token = t;
    notifyListeners();
    connect();
  }

  Future<void> clearToken() async {
    await _storage.delete(key: 'relay_token');
    _token = null;
    disconnect();
    notifyListeners();
  }

  void connect() {
    if (_token != null) {
      _relay.connect(token: _token);
      _connected = true;
      _eventSub?.cancel();
      _eventSub = _relay.onEvent.listen(_handleRelayEvent);
      notifyListeners();
    }
  }

  void disconnect() {
    _relay.disconnect();
    _connected = false;
    _eventSub?.cancel();
    notifyListeners();
  }

  void _handleRelayEvent((String, Map<String, dynamic>) event) {
    // Forward events to listeners via ChangeNotifier
    notifyListeners();
  }
  
  @override
  void dispose() {
    _eventSub?.cancel();
    _relay.disconnect();
    super.dispose();
  }
}
