import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/live/live_server.dart';
import 'package:receipt_splitter/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding fakes all HTTP; this test needs real sockets
  final live = LiveServer.instance;
  final persons = [Person(id: 1, sessionId: 1, name: 'Ana'), Person(id: 2, sessionId: 1, name: 'Ivo')];
  final items = [
    ReceiptItem(id: 1, sessionId: 1, personId: 1, name: 'Pivo', price: 3.5),
    ReceiptItem(id: 2, sessionId: 1, personId: 1, name: 'Pivo', price: 3.5),
    ReceiptItem(id: 3, sessionId: 1, name: 'Pomfrit', price: 4.2),
  ];

  tearDown(() => live.stop());

  test('guest page, state, claims, wrong key', () async {
    await live.start();
    live.update(persons, items);
    final base = 'http://127.0.0.1:${live.port}';

    final client = HttpClient();
    final bad = await (await client.getUrl(Uri.parse('$base/?k=nope'))).close();
    expect(bad.statusCode, 403);
    final page = await (await client.getUrl(Uri.parse('$base/?k=${live.key}'))).close();
    expect(page.statusCode, 200);
    expect(await page.transform(utf8.decoder).join(), contains('Who are you?'));

    // Android browsers are sent to the app first, with this page as the fallback
    final req = await client.getUrl(Uri.parse('$base/?k=${live.key}'))
      ..followRedirects = false
      ..headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 16) Chrome/140 Mobile');
    final redirect = await req.close();
    expect(redirect.statusCode, 302);
    final loc = redirect.headers.value(HttpHeaders.locationHeader)!;
    expect(loc, startsWith('intent://127.0.0.1:${live.port}/?k=${live.key}#Intent;scheme=receiptsplitter;'));
    expect(Uri.decodeComponent(loc), contains('browser_fallback_url=http://127.0.0.1:${live.port}/?k=${live.key}&web=1;'));
    await redirect.drain<void>();
    final web = await (await client.getUrl(Uri.parse('$base/?k=${live.key}&web=1'))
          ..headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 16) Chrome/140 Mobile'))
        .close();
    expect(web.statusCode, 200);
    await web.drain<void>();

    Future<(WebSocket, StreamQueue)> guest(String d) async {
      final ws = await WebSocket.connect('ws://127.0.0.1:${live.port}/ws?k=${live.key}&d=$d');
      return (ws, StreamQueue(ws.map((m) => jsonDecode(m as String) as Map<String, dynamic>)));
    }

    final (a, qa) = await guest('phoneA');
    var s = await qa.next;
    expect(s['total'], 11.2);
    expect(s['unassigned'], 4.2);
    expect((s['persons'] as List).first['total'], 7.0);

    a.add(jsonEncode({'type': 'claim', 'personId': 1}));
    s = await qa.next;
    expect((s['persons'] as List).first['claimedBy'], 'phoneA');

    // another phone can't take Ana
    final (b, qb) = await guest('phoneB');
    await qb.next;
    b.add(jsonEncode({'type': 'claim', 'personId': 1}));
    b.add(jsonEncode({'type': 'claim', 'personId': 2}));
    s = await qb.next;
    expect((s['persons'] as List)[0]['claimedBy'], 'other'); // other guests' device ids stay private
    expect((s['persons'] as List)[1]['claimedBy'], 'phoneB');

    // host assigns the fries to Ivo -> both phones get it
    items[2].personId = 2;
    live.update(persons, items);
    while ((s = await qa.next)['unassigned'] != 0) {}
    expect((s['persons'] as List)[1]['total'], 4.2);

    // host says "I'm Ivo": Ivo is reserved, the guest who had him goes back to the picker
    live.setHost(2);
    while ((s = await qb.next)['persons'][1]['claimedBy'] != 'host') {}
    b.add(jsonEncode({'type': 'claim', 'personId': 2}));
    live.release(2); // the host's own person can't be freed
    expect(live.isHost(2), isTrue);
    live.setHost(null);

    live.release(1);
    s = await qa.next;
    while ((s['persons'] as List)[0]['claimedBy'] != null) {
      s = await qa.next;
    }
    // oversized message: that guest is disconnected, the others are fine
    a.add('x' * 5000);
    await a.done;
    expect(a.closeCode, WebSocketStatus.policyViolation);

    // key guessing: blocked after 20 wrong keys, even the right key
    for (var i = 0; i < 20; i++) {
      final r = await (await client.getUrl(Uri.parse('$base/?k=guess$i'))).close();
      await r.drain<void>();
    }
    final blocked = await (await client.getUrl(Uri.parse('$base/?k=${live.key}&web=1'))).close();
    expect(blocked.statusCode, 403);
    await blocked.drain<void>();

    await b.close();
    client.close();
  });
}

/// Minimal async queue over a stream (avoids the package:async dependency).
class StreamQueue {
  final _buf = <Map<String, dynamic>>[];
  final _waiters = <Completer<Map<String, dynamic>>>[];
  StreamQueue(Stream<Map<String, dynamic>> s) {
    s.listen((m) => _waiters.isNotEmpty ? _waiters.removeAt(0).complete(m) : _buf.add(m));
  }
  Future<Map<String, dynamic>> get next {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    final c = Completer<Map<String, dynamic>>();
    _waiters.add(c);
    return c.future.timeout(const Duration(seconds: 5));
  }
}
