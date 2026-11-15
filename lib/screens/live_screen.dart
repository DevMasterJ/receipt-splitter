import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../live/live_server.dart';
import '../live/table_wifi.dart';
import '../models/models.dart';

/// Shows the QR codes guests scan, who is connected, and lets the host free a wrongly picked name.
///
/// Default: the app's own table Wi-Fi (no internet sharing, no settings) — step 1 joins it, step 2 opens the
/// bill. Fallback / choice: the Wi-Fi or hotspot this phone is already on (one QR code).
class LiveScreen extends StatefulWidget {
  final List<Person> persons;
  const LiveScreen({super.key, required this.persons});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final _live = LiveServer.instance;
  static bool _useTableWifi = true; // remembered while the app runs
  bool _starting = false;
  String? _hotspotError;
  int _step = 1;
  List<String> _addresses = [];
  String? _address;

  @override
  void initState() {
    super.initState();
    _live.addListener(_changed);
    TableWifi.stopped.addListener(_hotspotStopped);
    _setup();
  }

  @override
  void dispose() {
    _live.removeListener(_changed);
    TableWifi.stopped.removeListener(_hotspotStopped);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _hotspotStopped() {
    setState(() => _hotspotError = 'Android turned the table Wi-Fi off (is your normal hotspot on?). '
        'Tap ↻ to start it again, or let guests use the network below.');
    _loadAddresses();
  }

  Future<void> _setup() async {
    if (_useTableWifi && TableWifi.hotspot == null) {
      setState(() {
        _starting = true;
        _hotspotError = null;
      });
      try {
        await TableWifi.startHotspot();
        _step = 1;
      } on PlatformException catch (e) {
        _hotspotError = switch (e.code) {
          'permission' => 'The table Wi-Fi needs the "Nearby devices" permission.',
          'incompatible' => 'Your normal hotspot is on — guests can join that instead (below).',
          _ => 'Could not start the table Wi-Fi (${e.code}).',
        };
      }
      if (!mounted) return;
      setState(() => _starting = false);
    }
    await _loadAddresses();
  }

  Future<void> _loadAddresses() async {
    final a = await LiveServer.addresses();
    if (!mounted) return;
    setState(() {
      _addresses = a;
      if (!a.contains(_address)) _address = a.isEmpty ? null : a.first;
    });
  }

  Future<void> _setMode(bool tableWifi) async {
    _useTableWifi = tableWifi;
    if (!tableWifi && TableWifi.hotspot != null) await TableWifi.stopHotspot();
    await _setup();
  }

  @override
  Widget build(BuildContext context) {
    final hs = _useTableWifi ? TableWifi.hotspot : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live bill'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Find network again', onPressed: _setup)],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 16),
        children: [
          if (_starting)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Column(children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting the table Wi-Fi…'),
              ]),
            )
          else if (hs != null && hs.address != null)
            ..._tableWifi(context, hs)
          else
            ..._ownNetwork(context),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Table Wi-Fi from this phone'),
            subtitle: const Text('Works anywhere, no internet or mobile data used. Off = use the Wi-Fi / hotspot '
                'this phone is already on.'),
            value: _useTableWifi,
            onChanged: _starting ? null : _setMode,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.devices),
            title: Text('${_live.guestCount} phone${_live.guestCount == 1 ? '' : 's'} connected'),
          ),
          for (final p in widget.persons)
            ListTile(
              leading: Icon(_live.isHost(p.id!)
                  ? Icons.star
                  : _live.isClaimed(p.id!)
                      ? Icons.phone_android
                      : Icons.person_outline),
              title: Text(p.name),
              subtitle: Text(_live.isHost(p.id!)
                  ? 'You (this phone)'
                  : _live.isClaimed(p.id!)
                      ? 'Watching on a phone'
                      : 'Not picked yet'),
              trailing: _live.isClaimed(p.id!) && !_live.isHost(p.id!)
                  ? TextButton(onPressed: () => _live.release(p.id!), child: const Text('Free'))
                  : null,
            ),
        ],
      ),
    );
  }

  List<Widget> _tableWifi(BuildContext context, HotspotInfo hs) {
    final text = Theme.of(context).textTheme;
    final bill = _live.url(hs.address!, wifi: hs);
    return [
      Center(
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1 · Wi-Fi'), icon: Icon(Icons.wifi)),
            ButtonSegment(value: 2, label: Text('2 · Bill'), icon: Icon(Icons.receipt_long)),
          ],
          selected: {_step},
          onSelectionChanged: (s) => setState(() => _step = s.first),
        ),
      ),
      const SizedBox(height: 12),
      _qr(_step == 1 ? hs.wifiQr : bill),
      const SizedBox(height: 8),
      if (_step == 1) ...[
        Text('Scan with the camera → "Join network"', style: text.titleSmall, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        SelectableText('Wi-Fi: ${hs.ssid}\nPassword: ${hs.password}',
            textAlign: TextAlign.center, style: text.bodySmall),
        const SizedBox(height: 8),
        Center(
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next: the bill'),
            onPressed: () => setState(() => _step = 2),
          ),
        ),
      ] else ...[
        Text('Once on the Wi-Fi, scan this to open the bill', style: text.titleSmall, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          'Opens in the Receipt Splitter app if they have it, otherwise in the browser. '
          'With the app they can skip step 1: Join a table → scan this.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ];
  }

  List<Widget> _ownNetwork(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final url = _address == null ? null : _live.url(_address!);
    return [
      if (_hotspotError != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(padding: const EdgeInsets.all(12), child: Text(_hotspotError!)),
        ),
      if (url == null) ...[
        const SizedBox(height: 24),
        const Icon(Icons.wifi_off, size: 48),
        const SizedBox(height: 12),
        Text('No network to share on.', style: text.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
          'Turn on the table Wi-Fi below, your hotspot, or join the same Wi-Fi as the others, then tap ↻.',
          textAlign: TextAlign.center,
        ),
      ] else ...[
        _qr(url),
        const SizedBox(height: 8),
        SelectableText(url, textAlign: TextAlign.center, style: text.bodySmall),
        if (_addresses.length > 1)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              for (final a in _addresses)
                ChoiceChip(label: Text(a), selected: a == _address, onSelected: (_) => setState(() => _address = a)),
            ],
          ),
        const SizedBox(height: 12),
        Text(
          'Others need to be on the same Wi-Fi or your hotspot, then scan this and pick their name.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    ];
  }

  Widget _qr(String data) => Center(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(data: data, size: 240),
        ),
      );
}
