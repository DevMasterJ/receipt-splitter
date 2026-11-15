import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/reader/croatian_words.dart';
import 'package:receipt_splitter/reader/receipt_reader.dart';
import 'package:receipt_splitter/reader/receipt_rules.dart';

void main() {
  group('CroatianWords.fix', () {
    test('receipt_0189 (wrong code page)', () {
      expect(CroatianWords.fix('Pizza Mijetana/ Capricios'), 'Pizza Miješana/ Capricios');
      expect(CroatianWords.fix('Pivo tofeno 0,5'), 'Pivo točeno 0,5');
      expect(CroatianWords.fix('Pizza Mijeтana'), 'Pizza Miješana');
    });
    test('missing accents and case', () {
      expect(CroatianWords.fix('Salata Mijesana'), 'Salata Miješana');
      expect(CroatianWords.fix('PIVO TOCENO'), 'PIVO TOČENO');
      expect(CroatianWords.fix('caj s limunom'), 'čaj s limunom');
      expect(CroatianWords.fix('Cevapi 10 kom'), 'Ćevapi 10 kom');
    });
    test('leaves correct and ordinary words alone', () {
      for (final s in ['Pivo točeno 0,5', 'Riba dana', 'Pasta carbonara', 'Pica šunka', 'Coca-Cola 0,25',
          'Kava s mlijekom', 'Tips', 'Flag', 'Rita']) {
        expect(CroatianWords.fix(s), s);
      }
    });
    test('ReceiptRules.clean fixes name and qty together', () {
      final c = ReceiptRules.clean(const ParsedItem(name: 'Pivo tofeno', qty: 4.5, unitPrice: 4.5, price: 4.5));
      expect(c.name, 'Pivo točeno');
      expect(c.qty, 1);
    });
  });
}
