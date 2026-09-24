import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/relay_provider.dart';
import 'package:provider/provider.dart';

class ChatMessage {
  final String role; // user / assistant / status
  final String content;
  final bool transient; // ghost message: auto-clears when assistant replies
  ChatMessage({
    required this.role,
    required this.content,
    this.transient = false,
  });
}

class ChatScreen extends StatefulWidget {
  final String sessionId;
  const ChatScreen({super.key, required this.sessionId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Was pre-seeded with two hard-coded messages ('Hello, I am ready to help.'
  // and 'Summarize the Hermes state.') that rendered as if they were real
  // conversation. Start empty instead.
  final List<ChatMessage> _messages = [];
  final _controller = TextEditingController();

  int? _pendingAssistantIndex;
  StreamSubscription<String>? _streamSub;
  StreamSubscription<(String, Map<String, dynamic>)>? _eventSub;

  @override
  void initState() {
    super.initState();
    // Subscribe to relay events for workflow updates
    final relay = context.read<RelayProvider>();
    _eventSub = relay.relay.onEvent.listen((event) {
      final (ev, data) = event;
      if (ev == 'workflow_update') {
        _pushStatus(data['message'] ?? 'Working...');
      } else if (ev == 'message_new') {
        _clearTransient();
        // Handle new message if needed
      }
    });
  }

  void _pushStatus(String label, {String emoji = '⏳', String action = 'assigned'}) {
    final already = _messages.where((m) => m.role == 'status' && m.content.contains(label));
    if (already.isNotEmpty) return;
    setState(() {
      _messages.add(ChatMessage(
        role: 'status',
        content: '$emoji $label ($action in progress…)',
        transient: true,
      ));
    });
  }

  void _clearTransient() {
    final before = _messages.length;
    _messages.removeWhere((m) => m.transient);
    if (_messages.length != before && mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _streamSub?.cancel();
    _clearTransient();

    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _controller.clear();
      _messages.add(ChatMessage(role: 'assistant', content: ''));
      _pendingAssistantIndex = _messages.length - 1;
    });

    final relay = context.read<RelayProvider>();
    final token = relay.token;
    if (token == null) {
      _updateAssistant(_pendingAssistantIndex!, 'Error: not authenticated');
      _pendingAssistantIndex = null;
      return;
    }

    final payload = {
      'messages': [{'role': 'user', 'content': text}],
      'stream': true,
    };

    try {
      final stream = relay.relay.postChatStream(payload, token: token);
      _streamSub = stream.listen(
        (token) {
          if (_pendingAssistantIndex != null && _pendingAssistantIndex! < _messages.length) {
            final current = _messages[_pendingAssistantIndex!];
            final updated = ChatMessage(
              role: 'assistant',
              content: current.content + token,
              transient: false,
            );
            setState(() {
              _messages[_pendingAssistantIndex!] = updated;
            });
          }
        },
        onError: (err) {
          if (_pendingAssistantIndex != null) {
            _updateAssistant(_pendingAssistantIndex!, 'Error: $err');
          }
          _pendingAssistantIndex = null;
        },
        onDone: () {
          _pendingAssistantIndex = null;
          _clearTransient();
        },
      );
    } catch (e) {
      if (_pendingAssistantIndex != null) {
        _updateAssistant(_pendingAssistantIndex!, 'Error: $e');
      }
      _pendingAssistantIndex = null;
    }
  }

  void _updateAssistant(int index, String content) {
    if (index < _messages.length && mounted) {
      setState(() {
        _messages[index] = ChatMessage(role: 'assistant', content: content, transient: false);
      });
    }
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _eventSub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _messages.length,
          itemBuilder: (context, i) => _MessageBubble(message: _messages[i]),
        )),
        _Composer(controller: _controller, onSend: _send),
      ]);
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.role == 'status') {
      return _StatusBubble(content: message.content);
    }

    final isUser = message.role == 'user';
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Text(message.content, style: TextStyle(color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)),
      ),
    );
  }
}

class _StatusBubble extends StatelessWidget {
  final String content;
  const _StatusBubble({required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(content, style: theme.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _Composer({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(child: TextField(
              controller: controller,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(hintText: 'Type a message…'),
              onSubmitted: (_) => onSend(),
            )),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send)),
          ]),
        ),
      );
}
