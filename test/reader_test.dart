import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/reader/receipt_reader.dart';
import 'package:receipt_splitter/reader/receipt_rules.dart';

List<ParsedItem> items(List<ReaderEvent> ev) => ev.whereType<ReaderItem>().map((e) => e.item).toList();
ParsedItem it(String n, double q, double u, double p) => ParsedItem(name: n, qty: q, unitPrice: u, price: p);

void main() {
  group('ReceiptRules.fixQty', () {
    test('consistent items are untouched', () {
      final i = ReceiptRules.fixQty(it('BRESKVA', 0.562, 1.29, 0.72));
      expect(i.qty, 0.562);
      expect(i.qtyFixed, isFalse);
    });

    test('"HIDRA 0,50" read as qty 0.5 (receipt_0226) → 1', () {
      final i = ReceiptRules.fixQty(it('HIDRA', 0.5, 3.5, 3.5));
      expect(i.qty, 1);
      expect(i.qtyFixed, isTrue);
    });

    test('qty and unit swapped on rotated photo (receipt_0221) → 1', () {
      final i = ReceiptRules.fixQty(it('KAVA SA ŠLAGOM VELIKA', 2.4, 1.0, 2.4));
      expect(i.qty, 1);
      expect(i.qtyFixed, isTrue);
    });

    test('qty recovered from price / unit', () {
      expect(ReceiptRules.fixQty(it('PIVO', 1, 3.5, 7.0)).qty, 2);
      expect(ReceiptRules.fixQty(it('GROZDE', 1, 2.65, 1.56)).qty, 0.589);
    });

    test('whole qty with unit 1.00 is not treated as swapped', () {
      expect(ReceiptRules.fixQty(it('VREĆICA', 2, 1.0, 2.0)).qtyFixed, isFalse);
    });
  });

  group('ReceiptRules rows and sums', () {
    test('rows: whole qty splits, weights stay one row, cents are kept', () {
      expect(ReceiptRules.rowPrices(it('PIVO', 2, 3.5, 7.0)), [3.5, 3.5]);
      expect(ReceiptRules.rowPrices(it('X', 3, 3.33, 10.0)), [3.33, 3.33, 3.34]);
      expect(ReceiptRules.rowPrices(it('BRESKVA', 0.562, 1.29, 0.72)), [0.72]);
    });

    test('adds up', () {
      expect(ReceiptRules.addsUp([3.0, 0.72, 10.27], [-6.49], 7.50), isTrue);
      expect(ReceiptRules.sumDifference([29.01], [0.10], 29.01), 0.10);
    });
  });
}
