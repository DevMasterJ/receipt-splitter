import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../live/table_wifi.dart';
import '../live/live_link.dart';

/// The guest side of a live bill inside the app (same as assets/live/guest.html, but native).
/// Opened from a `receiptsplitter://<ip>:<port>/?k=<key>` link on the host's QR page.
class LiveGuestScreen extends StatefulWidget {
  final Uri link;

  /// The app connected itself to the host's table Wi-Fi ("Join a table" scan).
  final bool joinedWifi;
  const LiveGuestScreen({super.key, required this.link, this.joinedWifi = false});

  @override
  State<LiveGuestScreen> createState() => _LiveGuestScreenState();
}

class _LiveGuestScreenState extends State<LiveGuestScreen> {
  WebSocket? _ws;
  Map<String, dynamic>? _state;
  String? _device;
  String _status = 'Connecting…';
  bool _offline = false;
  bool _ended = false;
  bool _disposed = false;
  int _retry = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _ws?.close();
    TableWifi.leave(); // back to the normal network (and drop the app-only table Wi-Fi connection)
    super.dispose();
  }

  /// Stable per-install id, so a reconnect keeps the picked name.
  static Future<String> _deviceId() async {
    final f = File(p.join((await getApplicationSupportDirectory()).path, 'live_device_id'));
    if (f.existsSync()) return f.readAsStringSync().trim();
    final r = Random.secure();
    final id = List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
    f.writeAsStringSync(id);
    return id;
  }

  Future<void> _start() async {
    _device = await _deviceId();
    // joined the table Wi-Fi with the camera: it has no internet, Android may route via mobile data
    if (!widget.joinedWifi) await TableWifi.bindToHost(widget.link.host);
    _connect();
  }

  Future<void> _connect() async {
    if (_disposed) return;
    final l = widget.link;
    final key = l.queryParameters['k'] ?? '';
    final url = 'ws://${l.host}:${l.hasPort ? l.port : 8765}/ws?k=${Uri.encodeQueryComponent(key)}&d=$_device';
    try {
      final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 6));
      if (_disposed) {
        ws.close();
        return;
      }
      _ws = ws;
      _retry = 0;
      _set('Live — updates as items are added', false);
      ws.listen(
        (data) {
          Map<String, dynamic>? m;
          try {
            m = data is String ? cleanBillState(jsonDecode(data)) : null;
          } on FormatException {
            m = null;
          }
          if (m != null && mounted) setState(() => _state = m);
        },
        onDone: () {
          if (ws.closeCode == WebSocketStatus.goingAway) {
            _ended = true;
            _set('The host ended the session. These were the last numbers.', true);
          } else {
            _reconnect();
          }
        },
        onError: (_) {},
        cancelOnError: true,
      );
    } on WebSocketException catch (e) {
      if (e.httpStatusCode == HttpStatus.forbidden) {
        // the host started a new session (new key) or the link is wrong: retrying can't help
        _ended = true;
        _set("This bill isn't open any more. Scan the new QR code on the host phone.", true);
      } else if (e.httpStatusCode == HttpStatus.serviceUnavailable) {
        _set('The table is full (20 phones). Retrying…', true);
        Future.delayed(const Duration(seconds: 15), _connect);
      } else {
        _reconnect();
      }
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_disposed || _ended) return;
    _set(
      _state == null
          ? "Can't reach the host phone. Are you on its hotspot / the same Wi-Fi? Retrying…"
          : 'Connection lost — reconnecting…',
      true,
    );
    Future.delayed(Duration(milliseconds: 1000 << min(_retry++, 3)), _connect);
  }

  void _set(String s, bool offline) {
    if (!mounted) return;
    setState(() {
      _status = s;
      _offline = offline;
    });
  }

  void _send(Map<String, dynamic> m) {
    if (_ws?.readyState == WebSocket.open) _ws!.add(jsonEncode(m));
  }

  static String _eur(num v) => '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final s = _state;
    final persons = (s?['persons'] as List? ?? []).cast<Map<String, dynamic>>();
    final items = (s?['items'] as List? ?? []).cast<Map<String, dynamic>>();
    final me = persons.where((p) => p['claimedBy'] == _device).firstOrNull;

    Widget section(String title, {Color? color}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Text(title.toUpperCase(), style: text.labelMedium?.copyWith(color: color ?? scheme.outline)),
    );
    Widget row(String a, num v, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(a, style: style)),
          Text(_eur(v), style: style),
        ],
      ),
    );

    final everyone = [
      section('Everyone'),
      Card(
        child: Column(
          children: [
            for (final p in persons) row(p['name'], p['total']),
            if (((s?['unassigned'] ?? 0) as num).abs() >= 0.005)
              row('Not assigned', s!['unassigned'], style: TextStyle(color: scheme.error)),
            if (s != null) row('Total', s['total'], style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ];

    return PopScope(
      // Leaving drops the connection (and the table Wi-Fi), so ask first while the bill is still open.
      canPop: _ended,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave the bill?'),
            content: const Text('You will be disconnected. To see the bill again, scan the QR code on the host phone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('OK')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Bill at the table')),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 24),
          children: [
            Text(_status, style: text.bodySmall?.copyWith(color: _offline ? scheme.error : scheme.outline)),
            if (s == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (me == null) ...[
              section('Who are you?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in persons)
                    FilledButton.tonal(
                      onPressed: p['claimedBy'] != null && !_ended
                          ? null
                          : () => _send({'type': 'claim', 'personId': p['id']}),
                      child: Text(
                        '${p['name']}${p['claimedBy'] == 'host'
                            ? ' (host)'
                            : p['claimedBy'] != null
                            ? ' ✓'
                            : ''}',
                      ),
                    ),
                ],
              ),
              if (persons.any((p) => p['claimedBy'] != null && p['claimedBy'] != 'host'))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '✓ = already picked on another phone. Wrong one? Ask the host to free it.',
                    style: text.bodySmall,
                  ),
                ),
              ...everyone,
            ] else ...[
              const SizedBox(height: 8),
              Card(
                color: scheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${me['name']}, you owe', style: text.titleSmall),
                      Text(_eur(me['total']), style: text.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => _send({'type': 'unclaim'}),
                        child: Text('Not ${me['name']}? Switch'),
                      ),
                    ],
                  ),
                ),
              ),
              ..._itemList(
                'Your items',
                items.where((i) => i['personId'] == me['id']).toList(),
                section,
                row,
                empty: 'Nothing assigned to you yet.',
              ),
              ..._itemList(
                'Not assigned yet',
                items.where((i) => i['personId'] == null).toList(),
                section,
                row,
                color: scheme.error,
                hint: 'Is one of these yours? Tell the host.',
              ),
              ...everyone,
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _itemList(
    String title,
    List<Map<String, dynamic>> list,
    Widget Function(String, {Color? color}) section,
    Widget Function(String, num, {TextStyle? style}) row, {
    String? empty,
    Color? color,
    String? hint,
  }) {
    if (list.isEmpty && empty == null) return [];
    return [
      section('$title (${list.length})', color: color),
      Card(
        child: Column(
          children: [
            if (list.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(empty!)),
            for (final i in list) row(i['name'], i['price']),
          ],
        ),
      ),
      if (hint != null) Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 0), child: Text(hint)),
    ];
  }
}
