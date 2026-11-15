import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'eval/eval_trigger.dart';
import 'screens/home_screen.dart';
import 'live/live_link.dart';
import 'screens/live_guest_screen.dart';

final _navigator = GlobalKey<NavigatorState>();

void main() {
  runApp(const ReceiptSplitterApp());
  runEvalTrigger();
  // "Open in app" on another phone's live bill page: receiptsplitter://<ip>:<port>/?k=<key>
  // (the stream also delivers the link the app was started with)
  AppLinks().uriLinkStream.listen((uri) {
    if (uri.scheme != 'receiptsplitter' || !isTableLink(uri)) return;
    _openWhenReady(uri);
  });
}

/// On a cold start the link can arrive before the first frame (no navigator yet).
void _openWhenReady(Uri uri) {
  final nav = _navigator.currentState;
  if (nav == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openWhenReady(uri));
    return;
  }
  nav.push(MaterialPageRoute(builder: (_) => LiveGuestScreen(link: uri)));
}

class ReceiptSplitterApp extends StatelessWidget {
  const ReceiptSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Splitter',
      navigatorKey: _navigator,
      // follows the phone's light / dark setting
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
