import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/live/live_link.dart';

void main() {
  test('isTableLink', () {
    bool ok(String s) => isTableLink(Uri.parse(s));
    expect(ok('http://192.168.1.12:8765/?k=ab23cd'), isTrue);
    expect(ok('receiptsplitter://10.94.1.7:8765/?k=ab23cd'), isTrue);
    expect(ok('http://172.20.0.1:8765/?k=ab23cd&s=Table&p=x&t=1'), isTrue);
    expect(ok('http://example.com:8765/?k=ab23cd'), isFalse);
    expect(ok('http://8.8.8.8:8765/?k=ab23cd'), isFalse);
    expect(ok('http://172.32.0.1:8765/?k=ab23cd'), isFalse);
    expect(ok('http://192.168.1.300:8765/?k=ab23cd'), isFalse);
    expect(ok('http://192.168.1.3:8765/?k=AB23CD!'), isFalse);
    expect(ok('http://192.168.1.3:8765/'), isFalse);
  });

  test('cleanBillState', () {
    expect(cleanBillState({'type': 'hello'}), isNull);
    expect(cleanBillState('x'), isNull);
    final s = cleanBillState({
      'type': 'state',
      'persons': [{'id': 1, 'name': 'A' * 500, 'total': 'lots', 'claimedBy': 5}, 'junk'],
      'items': List.generate(5000, (i) => {'id': i, 'name': 'x', 'price': 1.5, 'personId': '1'}),
      'unassigned': double.nan,
    })!;
    final p = (s['persons'] as List).single as Map;
    expect((p['name'] as String).length, 200);
    expect(p['total'], 0);
    expect(p['claimedBy'], isNull);
    expect((s['items'] as List).length, 1000);
    expect(((s['items'] as List).first as Map)['personId'], isNull);
    expect(s['unassigned'], 0);
    expect(s['total'], 0);
  });
}
