import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

/// RelayClient handles WebSocket (/sync) and HTTP proxy to the relay server.
class RelayClient {
  final String baseUrl;
  WebSocketChannel? _ws;

  final _eventController = StreamController<(String, Map<String, dynamic>)>.broadcast();
  Stream<(String, Map<String, dynamic>)> get onEvent => _eventController.stream;

  RelayClient({required this.baseUrl});

  /// Open /sync WebSocket with session token (Bearer or ?token=)
  void connect({String? token}) {
    final uri = Uri.parse('$baseUrl/sync').replace(
      queryParameters: token != null ? {'token': token} : null,
    );
    _ws = WebSocketChannel.connect(uri);
    _ws!.stream.listen(
      (msg) {
        try {
          final data = jsonDecode(msg.toString()) as Map<String, dynamic>;
          final ev = data['type'] ?? 'unknown';
          _eventController.add((ev, data));
        } catch (_) {}
      },
      onDone: () => _ws = null,
      onError: (_) => _ws = null,
    );
  }

  void disconnect() => _ws?.sink.close();

  /// HTTP proxy: POST /auth/login
  Future<Map<String, dynamic>> login({required String username, required String password, String? workspaceUrl}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password, 'workspaceUrl': workspaceUrl}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    throw Exception('login failed: ${body['error']}');
  }

  /// HTTP proxy: POST /v1/chat with SSE streaming.
  /// Returns a Stream<String> that yields delta tokens from `data: {...}` lines.
  Stream<String> postChatStream(Map<String, dynamic> payload, {String? token}) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/v1/chat'));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.body = jsonEncode(payload);

    final streamedRes = await http.Client().send(request);
    final byteStream = streamedRes.stream;

    String buffer = '';
    await for (final chunk in byteStream) {
      buffer += utf8.decode(chunk as List<int>);
      while (buffer.contains('\n')) {
        final nl = buffer.indexOf('\n');
        final line = buffer.substring(0, nl).trim();
        buffer = buffer.substring(nl + 1);
        if (line.startsWith('data: ')) {
          final jsonStr = line.substring(6).trim();
          if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final choices = data['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              final content = delta?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                yield content;
              }
            }
          } catch (_) {
            // Skip malformed lines
          }
        }
      }
    }
  }

  /// HTTP proxy: POST /v1/models
  Future<List<dynamic>> listModels({String? token}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/v1/models'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    return (jsonDecode(res.body) as Map<String, dynamic>)['data'] ?? [];
  }

  /// Send sync request over WS (lastSeq for catch-up)
  void sendSync({int? lastSeq}) => _ws?.sink.add(jsonEncode({'type': 'sync', 'lastSeq': lastSeq ?? 0}));
}
