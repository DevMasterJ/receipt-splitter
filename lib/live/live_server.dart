/// Live table session: this phone runs a tiny web server, the others open it in their browser
/// (QR code), pick who they are and watch their own tally update as items are added.
///
/// No internet needed: works on the host's hotspot (mobile data off) or any Wi-Fi where the phones
/// can see each other. This phone is the only source of truth — guests only view and claim a person.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import 'live_link.dart';
import 'table_wifi.dart';

class LiveServer extends ChangeNotifier {
  LiveServer._();
  static final instance = LiveServer._();

  static const _port = 8765;

  // Limits: a phone on the table Wi-Fi shouldn't be able to slow down or crash the host.
  static const _maxGuests = 20;
  static const _maxMessage = 1024; // guests only send tiny claim messages
  static const _maxMessagesPer10s = 30;
  static const _maxWrongKeys = 20; // then that address waits 5 minutes (the key has ~30^6 values)
  final _wrongKeys = <String, int>{};
  final _blockedUntil = <String, DateTime>{};

  HttpServer? _server;
  final _sockets = <WebSocket, String>{}; // socket -> guest device id
  String _key = '';
  String? _page;

  List<Person> _persons = [];
  List<ReceiptItem> _items = [];

  /// personId -> guest device id that claimed it ([hostDevice] for the host's own person).
  final claims = <int, String>{};

  static const hostDevice = 'host';
  int? _hostPersonId;

  /// The host says which person they are: reserved for this phone, guests can't pick it.
  void setHost(int? personId) {
    claims.removeWhere((_, d) => d == hostDevice);
    _hostPersonId = personId;
    if (personId != null) claims[personId] = hostDevice; // a guest who had it goes back to the picker
    _broadcast();
    notifyListeners();
  }

  bool isHost(int personId) => claims[personId] == hostDevice;

  bool get running => _server != null;
  int get guestCount => _sockets.length;
  String get key => _key;
  int get port => _server?.port ?? _port;

  /// Who is looking at which person (for the host screen).
  bool isClaimed(int personId) => claims.containsKey(personId);

  Future<void> start() async {
    if (_server != null) return;
    _page ??= await rootBundle.loadString('assets/live/guest.html');
    _key = _randomKey();
    _wrongKeys.clear();
    _blockedUntil.clear();
    claims.clear();
    if (_hostPersonId != null) claims[_hostPersonId!] = hostDevice;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port, shared: true);
    } on SocketException {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0); // port taken: any free one
    }
    _server!.listen(_handle, onError: (Object e) => debugPrint('live server: $e'));
    notifyListeners();
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    for (final ws in _sockets.keys.toList()) {
      await ws.close(WebSocketStatus.goingAway, 'Session ended');
    }
    _sockets.clear();
    claims.clear();
    await s?.close(force: true);
    notifyListeners();
  }

  /// Call after every change on the host (person added, items saved, item reassigned).
  void update(List<Person> persons, List<ReceiptItem> items) {
    _persons = List.of(persons);
    _items = List.of(items);
    claims.removeWhere((pid, _) => !_persons.any((p) => p.id == pid));
    _broadcast();
  }

  /// Host frees a person (e.g. someone picked the wrong name).
  void release(int personId) {
    if (isHost(personId)) return;
    claims.remove(personId);
    _broadcast();
    notifyListeners();
  }

  /// Addresses guests can use: hotspot / Wi-Fi interfaces first.
  static Future<List<String>> addresses() async {
    final out = <(int, String)>[];
    for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in ni.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        final n = ni.name.toLowerCase();
        // Samsung hotspot = swlan0, AOSP = ap0/wlan1; mobile data (rmnet/ccmni) can't be reached by guests
        final rank = n.startsWith('swlan') || n.startsWith('ap')
            ? 0
            : n.startsWith('wlan')
                ? 1
                : n.startsWith('rmnet') || n.startsWith('ccmni') || n.startsWith('dummy')
                    ? 9
                    : 5;
        // only addresses the guests' app accepts (live_link.dart): no VPN / carrier (100.x) or public ones
        if (rank < 9 && isPrivateIPv4(a.address) && !a.address.startsWith('127.')) out.add((rank, a.address));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final o in out) o.$2];
  }

  /// Bill link. With [wifi] it also carries the table Wi-Fi login, so the app's "Join a table"
  /// scanner can connect and open the bill in one scan (browsers ignore the extra parameters).
  String url(String address, {HotspotInfo? wifi}) {
    final q = {
      'k': _key,
      if (wifi != null) ...{'s': wifi.ssid, 'p': wifi.password, 't': '${wifi.security}'},
    };
    return Uri(scheme: 'http', host: address, port: port, path: '/', queryParameters: q).toString();
  }

  static String _randomKey() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final ip = req.connectionInfo?.remoteAddress.address ?? '';
    try {
      if (req.uri.path == '/favicon.ico') {
        res.statusCode = HttpStatus.noContent; // browsers ask without the key
      } else if (_blockedUntil[ip]?.isAfter(DateTime.now()) ?? false) {
        res.statusCode = HttpStatus.forbidden; // guessing keys: wait
      } else if (req.uri.queryParameters['k'] != _key) {
        // also a guest still on an old session's link (their app / page stops retrying on 403)
        final n = (_wrongKeys[ip] ?? 0) + 1;
        _wrongKeys[ip] = n;
        if (n >= _maxWrongKeys) {
          _wrongKeys.remove(ip);
          _blockedUntil[ip] = DateTime.now().add(const Duration(minutes: 5));
        }
        res.statusCode = HttpStatus.forbidden;
        res.headers.contentType = ContentType.html;
        res.write('<h2>This bill session has ended or the link is wrong.</h2>'
            '<p>Scan the QR code on the host phone again.</p>');
      } else if (req.uri.path == '/ws' && WebSocketTransformer.isUpgradeRequest(req)) {
        if (_sockets.length >= _maxGuests) {
          res.statusCode = HttpStatus.serviceUnavailable;
        } else {
          final ws = await WebSocketTransformer.upgrade(req);
          final d = req.uri.queryParameters['d'] ?? '';
          // Device id: chosen by the guest (stays the same across reconnects). Never shown to other guests.
          _onGuest(ws, RegExp(r'^[A-Za-z0-9_-]{4,64}$').hasMatch(d) && d != hostDevice ? d : _randomKey());
          return;
        }
      } else if (req.uri.path == '/' && _wantsApp(req)) {
        // Android: try the app first. Chrome opens it if installed, else loads the fallback (this page with
        // web=1) without asking; Firefox opens it if installed, else asks "Open in app / Stay in Firefox".
        final host = req.headers.host ?? req.requestedUri.host;
        final port = req.headers.port ?? this.port;
        final fallback = Uri.encodeComponent('http://$host:$port/?k=$_key&web=1');
        res.statusCode = HttpStatus.found;
        res.headers.set('Cache-Control', 'no-store');
        res.headers.set(
          HttpHeaders.locationHeader,
          'intent://$host:$port/?k=$_key#Intent;scheme=receiptsplitter;package=$_package;'
          'S.browser_fallback_url=$fallback;end',
        );
      } else if (req.uri.path == '/') {
        res.headers.contentType = ContentType.html;
        res.headers.set('Cache-Control', 'no-store');
        res.write(_page);
      } else {
        res.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      debugPrint('live server request: $e');
    }
    await res.close();
  }

  static const _package = 'dev.webmasterj.receiptsplitter';

  static bool _wantsApp(HttpRequest req) =>
      req.uri.queryParameters['web'] != '1' &&
      (req.headers.value(HttpHeaders.userAgentHeader) ?? '').contains('Android');

  void _onGuest(WebSocket ws, String device) {
    ws.pingInterval = const Duration(seconds: 10);
    _sockets[ws] = device;
    notifyListeners();
    ws.add(_state(device));
    var window = DateTime.now(), count = 0;
    ws.listen(
      (data) {
        final now = DateTime.now();
        if (now.difference(window).inSeconds >= 10) {
          window = now;
          count = 0;
        }
        if (data is! String || data.length > _maxMessage || ++count > _maxMessagesPer10s) {
          ws.close(WebSocketStatus.policyViolation, 'Too much data');
          return;
        }
        try {
          final m = jsonDecode(data) as Map<String, dynamic>;
          _onMessage(device, m);
        } catch (e) {
          debugPrint('live guest message: $e');
        }
      },
      onDone: () {
        _sockets.remove(ws);
        notifyListeners();
      },
      onError: (_) => _sockets.remove(ws),
      cancelOnError: true,
    );
  }

  void _onMessage(String device, Map<String, dynamic> m) {
    switch (m['type']) {
      case 'claim':
        final pid = m['personId'];
        if (pid is! int || !_persons.any((p) => p.id == pid)) return;
        final owner = claims[pid];
        if (owner != null && owner != device) return; // taken: host can release it
        claims.removeWhere((_, d) => d == device); // one person per phone
        claims[pid] = device;
      case 'unclaim':
        claims.removeWhere((_, d) => d == device);
      default:
        return;
    }
    _broadcast();
    notifyListeners();
  }

  void _broadcast() {
    if (_sockets.isEmpty) return;
    _sockets.forEach((ws, device) => ws.add(_state(device)));
  }

  /// The bill as [device] sees it: claimedBy is its own id, 'host', 'other' or null.
  String _state(String device) {
    final totals = <int, double>{};
    var unassigned = 0.0;
    for (final i in _items) {
      if (i.personId == null) {
        unassigned += i.price;
      } else {
        totals[i.personId!] = (totals[i.personId!] ?? 0) + i.price;
      }
    }
    return jsonEncode({
      'type': 'state',
      'persons': [
        for (final p in _persons)
          {'id': p.id, 'name': p.name, 'total': _r(totals[p.id] ?? 0), 'claimedBy': _claimedBy(p.id, device)},
      ],
      'items': [
        for (final i in _items) {'id': i.id, 'name': i.name, 'price': _r(i.price), 'personId': i.personId},
      ],
      'unassigned': _r(unassigned),
      'total': _r(_items.fold(0.0, (a, i) => a + i.price)),
    });
  }

  String? _claimedBy(int? personId, String device) {
    final c = claims[personId];
    return c == null || c == device || c == hostDevice ? c : 'other';
  }

  static double _r(double v) => double.parse(v.toStringAsFixed(2));
}
