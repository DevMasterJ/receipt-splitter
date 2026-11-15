import 'croatian_words.dart';
import 'receipt_reader.dart';

/// Plausibility rules applied to what a reader returns (from the 2026-11-07 eval: the model's
/// remaining mistakes were almost all quantities; prices and totals were right).
class ReceiptRules {
  static const _eps = 0.011;

  /// If qty × unit ≠ price, trust the line price: qty = price / unit when that is a whole number
  /// (or a weight below 1 kg), otherwise 1.
  /// E.g. the model copied the price into qty ("7.60 | 7.60 | 7.60") → qty 1.
  ///
  /// Also: qty and unit price swapped ("KAVA | 2.4 | 1.0 | 2.4", seen on rotated photos) —
  /// unit exactly 1.00 with a fractional qty above 1 → qty 1.
  /// Everything the review screen applies to a read item: quantity fix + Croatian letter repair.
  static ParsedItem clean(ParsedItem it) {
    final fixed = fixQty(it);
    final name = CroatianWords.fix(fixed.name);
    return name == fixed.name ? fixed : fixed.copyWith(name: name);
  }

  static ParsedItem fixQty(ParsedItem it) {
    final q0 = it.qty;
    if (it.unitPrice == 1.0 && q0 > 1 && q0 != q0.roundToDouble() && (q0 - it.price).abs() <= _eps) {
      return it.copyWith(qty: 1, qtyFixed: true);
    }
    if ((it.qty * it.unitPrice - it.price).abs() <= _eps) return it;
    double q = 1;
    if (it.unitPrice > 0) {
      final r = it.price / it.unitPrice;
      if (r >= 1 && (r - r.round()).abs() < 0.02) {
        q = r.round().toDouble();
      } else if (r > 0 && r < 1) {
        q = double.parse(r.toStringAsFixed(3));
      }
    }
    return it.copyWith(qty: q, qtyFixed: q != it.qty);
  }

  /// items + discounts − total. 0 (within a cent) means the receipt adds up.
  static double sumDifference(Iterable<double> itemPrices, Iterable<double> discounts, double total) {
    final sum = itemPrices.fold<double>(0, (a, b) => a + b) + discounts.fold<double>(0, (a, b) => a + b);
    return double.parse((sum - total).toStringAsFixed(2));
  }

  static bool addsUp(Iterable<double> itemPrices, Iterable<double> discounts, double total) =>
      sumDifference(itemPrices, discounts, total).abs() < _eps;

  /// How many rows an item becomes in the split list: whole quantities are split into
  /// one row per unit (2 beers → two rows), weights and odd quantities stay one row.
  static int rowsFor(ParsedItem it) {
    final q = it.qty;
    if (q >= 1 && q <= 50 && q == q.roundToDouble()) return q.toInt();
    return 1;
  }

  /// Prices of the rows (see [rowsFor]); they always sum to the line price exactly,
  /// the last row takes the rounding remainder (10.00 / 3 → 3.33, 3.33, 3.34).
  static List<double> rowPrices(ParsedItem it) {
    final n = rowsFor(it);
    if (n == 1) return [it.price];
    final cents = (it.price * 100).round();
    final each = cents ~/ n;
    return [for (var i = 0; i < n; i++) (i == n - 1 ? cents - each * (n - 1) : each) / 100];
  }
}
