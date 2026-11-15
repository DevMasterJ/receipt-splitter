import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../live/table_wifi.dart';
import '../live/live_link.dart';
import 'live_guest_screen.dart';

/// "Join a table": scan the host's bill QR code. If it carries the table Wi-Fi login, connect this app
/// to it first (Android asks "Connect to …?"), then open the bill — one scan instead of two.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  bool _busy = false; // the camera is closed while connecting (the scanner widget is removed)
  String? _message;

  /// QR codes are decoded on the phone by zxing-cpp (flutter_zxing): no Google ML Kit, nothing sent anywhere.
  Future<void> _onScan(Code code) async {
    if (_busy || !mounted) return;
    final raw = code.text;
    if (!code.isValid || raw == null) return;
    if (raw.startsWith('WIFI:')) {
      setState(
        () => _message =
            "That's the Wi-Fi code (step 1). Scan the bill code (step 2) instead — "
            'the app joins the Wi-Fi by itself.',
      );
      return;
    }
    final uri = Uri.tryParse(raw);
    final key = uri?.queryParameters['k'];
    if (uri == null || uri.scheme != 'http' || key == null || !isTableLink(uri)) {
      setState(() => _message = "This isn't a Receipt Splitter bill code.");
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final link = Uri(scheme: 'receiptsplitter', host: uri.host, port: uri.port, path: '/', queryParameters: {'k': key});
    final ssid = uri.queryParameters['s'], password = uri.queryParameters['p'];
    var joined = false;
    if (ssid != null && password != null) {
      try {
        await TableWifi.join(ssid, password, int.tryParse(uri.queryParameters['t'] ?? '') ?? 1);
        joined = true;
      } on PlatformException catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _message = e.code == 'permission'
              ? 'Joining needs the "Nearby devices" permission.'
              : "Couldn't connect to the table Wi-Fi \"$ssid\". Are you close to the host? Try again.";
        });
        return;
      }
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LiveGuestScreen(link: link, joinedWifi: joined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a table')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!_busy)
                  ReaderWidget(
                    onScan: _onScan,
                    codeFormat: Format.qrCode,
                    tryHarder: true,
                    showGallery: false,
                    showToggleCamera: false,
                    scanDelay: const Duration(milliseconds: 300),
                    scanDelaySuccess: const Duration(milliseconds: 1500),
                    cropPercent: 0.7,
                  )
                else
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Connecting to the table…', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _message ?? 'Scan the bill code on the host phone (Live bill → "2 · Bill").',
                textAlign: TextAlign.center,
                style: TextStyle(color: _message != null ? scheme.error : null),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
