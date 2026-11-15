/// Common interface for everything that turns a receipt photo into items.
///
/// Readers emit events as they go, so the review screen can show items while the
/// reader is still working.
library;

class ParsedItem {
  final String name;
  final double qty;
  final double unitPrice;
  final double price;

  /// Set by [ReceiptRules.fixQty] when the quantity was corrected.
  final bool qtyFixed;

  const ParsedItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.price,
    this.qtyFixed = false,
  });

  ParsedItem copyWith({String? name, double? qty, bool? qtyFixed}) => ParsedItem(
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unitPrice: unitPrice,
        price: price,
        qtyFixed: qtyFixed ?? this.qtyFixed,
      );

  @override
  String toString() => '$name | $qty | $unitPrice | $price${qtyFixed ? ' (qty fixed)' : ''}';
}

sealed class ReaderEvent {
  const ReaderEvent();
}

/// Free-text progress for the UI ("Loading model…", "Reading image…").
class ReaderProgress extends ReaderEvent {
  final String message;
  const ReaderProgress(this.message);
}

class ReaderStore extends ReaderEvent {
  final String name;
  const ReaderStore(this.name);
}

class ReaderItem extends ReaderEvent {
  final ParsedItem item;
  const ReaderItem(this.item);
}

/// A coupon / discount after the item list (negative amount).
class ReaderDiscount extends ReaderEvent {
  final String name;
  final double amount;
  const ReaderDiscount(this.name, this.amount);
}

class ReaderTotal extends ReaderEvent {
  final double total;
  const ReaderTotal(this.total);
}

/// Generation was cut off (repeating lines / too many items); what came before is kept.
class ReaderStopped extends ReaderEvent {
  final String reason;
  const ReaderStopped(this.reason);
}

abstract class ReceiptReader {
  /// Short name for the UI, e.g. "Quick reader" or "ML Kit".
  String get name;

  /// Whether this reader can run right now (e.g. model files present).
  Future<bool> isAvailable();

  /// Reads the receipt at [imagePath]. Errors are delivered as stream errors.
  Stream<ReaderEvent> read(String imagePath);
}
