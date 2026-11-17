import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/reader/receipt_text_rules.dart';

/// Made-up Croatian receipts (no real shops or people), as the OCR layout text the rules read.
/// To adapt the app to another country, add receipts from there and adjust lib/reader/receipt_text_rules.dart.
const cafe = '''
Caffe bar Primjer d.o.o.
Primjerna ulica 1, 10000 Zagreb
OIB: 12345678901
Stol 4    Posluzuje Ana
Broj racuna 123/1/1
ARTIKL    KOLICINA CIJENA IZNOS
KAVA S MLIJEKOM
2,00    2,20    4,40
COCA COLA 0,25
1,00    3,50    3,50
UKUPNO EUR:    7,90
PDV Stopa    OSNOVICA    PDV
25,00%    6,32    1,58
ZKI: 0123456789abcdef0123456789abcdef
JIR: 01234567-89ab-cdef-0123-456789abcdef
HVALA''';

const restaurant = '''
Restoran Primjer
Naziv    Kol    Cijena    Iznos
PIZZA MARGHERITA    2    9,50    19,00
PIVO TOČENO 0,5 l    3    4,00    12,00
VODA 0,75 l    1    2,50    2,50
UKUPNO    33,50
Kartice    33,50''';

/// No "UKUPNO" line, and the paid amount came out unreadable ("1E,80"): the total comes from the VAT row.
const pub = '''
Pub Primjer d.o.o.
Stol 3    Posluzuje Ivo
ARTIKL    KOLICINA CIJENA POPUST IZNOS
PIVO SVIJETLO 0.5
1,00    4,30    0,00    4,30
PIVO PSENICNO 0.5
2,00    5,10    0,00    10,20
Novcanice    €:    1E,80
PDV Stopa    OSNOVICA    PDV    PNP
25,00%    11,60    2,90    0,00
Ukupno porez:    2,90
HVALA''';

const supermarket = '''
SUPERMARKET PRIMJER d.d.
Artikal    Kol Cijena    Iznos €
KRUH 400 g    1 x 1,79    1,79
BANANA
0,562 x    1,29    0,72
SIR 300 g    2 x 3,99    7,98
UKUPNO    10,49
Gotovina    20,00''';

List<List<Object>> items(String text) =>
    [for (final i in parseReceiptText(text).items) [i.name, i.qty, i.unitPrice, i.price]];

void main() {
  test('cafe: names on the line above the numbers', () {
    expect(items(cafe), [
      ['KAVA S MLIJEKOM', 2.0, 2.2, 4.4],
      ['COCA COLA 0,25', 1.0, 3.5, 3.5],
    ]);
    expect(parseReceiptText(cafe).total, 7.9);
  });

  test('restaurant: one row per item', () {
    expect(items(restaurant), [
      ['PIZZA MARGHERITA', 2.0, 9.5, 19.0],
      ['PIVO TOČENO 0,5 l', 3.0, 4.0, 12.0],
      ['VODA 0,75 l', 1.0, 2.5, 2.5],
    ]);
    expect(parseReceiptText(restaurant).total, 33.5);
  });

  test('supermarket: weighed item', () {
    final r = parseReceiptText(supermarket);
    expect(r.items.map((i) => i.price), [1.79, 0.72, 7.98]);
    expect(r.items[1].name, 'BANANA');
    expect(r.total, 10.49);
  });

  test('pub: unreadable paid amount, total from the VAT row', () {
    expect(items(pub), [
      ['PIVO SVIJETLO 0.5', 1.0, 4.3, 4.3],
      ['PIVO PSENICNO 0.5', 2.0, 5.1, 10.2],
    ]);
    expect(parseReceiptText(pub).total, 14.5);
  });

  test('layout joins boxes on one line and orders lines top to bottom', () {
    List<List<double>> box(double x, double y, double w) => [[x, y], [x + w, y], [x + w, y + 20], [x, y + 20]];
    final text = layout([
      OcrBox(box(300, 100, 60), '4,40'),
      OcrBox(box(10, 100, 200), 'KAVA'),
      OcrBox(box(10, 60, 200), 'Caffe bar'),
    ]);
    final lines = text.split('\n');
    expect(lines.first, 'Caffe bar');
    expect(lines.last, startsWith('KAVA'));
    expect(lines.last, endsWith('4,40'));
  });
}
