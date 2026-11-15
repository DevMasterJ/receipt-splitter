import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/models/models.dart';

void main() {
  test('parsePrice', () {
    const cases = <String, double?>{
      '12,50': 12.5, '12.50': 12.5, '3': 3, ' 4,2 € ': 4.2, '-3,00': -3, '−1,20': -1.2, ',5': 0.5,
      '1.234,56': 1234.56, '1,234.56': 1234.56, '1.234.567,8': 1234567.8, '1.234.567': 1234567,
      '1.234': null, '': null, 'abc': null, '12,5x': null, '1-2': null, '--3': null,
    };
    cases.forEach((input, want) => expect(parsePrice(input), want, reason: input));
  });
}
