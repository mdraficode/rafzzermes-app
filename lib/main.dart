import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config.dart';
import 'core/client/relay_client.dart';
import 'core/relay_provider.dart';
import 'features/auth/login_screen.dart';
import 'features/chat/chat_screen.dart';

void main() {
  runApp(const RafzzermesApp());
}

class RafzzermesApp extends StatelessWidget {
  const RafzzermesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),
        ChangeNotifierProxyProvider<ThemeProvider, RelayProvider>(
          create: (_) => RelayProvider(),
          update: (_, theme, relay) => relay!,
        ),
      ],
      child: Consumer2<ThemeProvider, RelayProvider>(
        builder: (context, theme, relay, _) {
          return MaterialApp(
            title: 'Rafzzermes App',
            theme: theme.dark ? ThemeData.dark() : ThemeData.light(),
            home: relay.isLoggedIn
                ? const ChatScreen(sessionId: 'default')
                : LoginScreen(onLogin: (token) => relay.setToken(token)),
          );
        },
      ),
    );
  }
}
