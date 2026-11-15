class Person {
  final int? id;
  final int sessionId;
  final String name;

  Person({this.id, required this.sessionId, required this.name});

  Person withName(String name) => Person(id: id, sessionId: sessionId, name: name);

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'name': name,
      };

  factory Person.fromMap(Map<String, dynamic> m) =>
      Person(id: m['id'], sessionId: m['sessionId'], name: m['name']);
}

class ReceiptItem {
  final int? id;
  final int sessionId;
  int? personId;
  String name;
  double price;

  ReceiptItem({
    this.id,
    required this.sessionId,
    this.personId,
    required this.name,
    required this.price,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sessionId': sessionId,
        'personId': personId,
        'name': name,
        'price': price,
      };

  factory ReceiptItem.fromMap(Map<String, dynamic> m) => ReceiptItem(
        id: m['id'],
        sessionId: m['sessionId'],
        personId: m['personId'],
        name: m['name'],
        price: m['price'],
      );
}

class Session {
  final int? id;
  final DateTime createdAt;

  /// Which person is the owner of this phone (the host of a live bill).
  int? mePersonId;

  Session({this.id, required this.createdAt, this.mePersonId});

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'mePersonId': mePersonId,
      };

  factory Session.fromMap(Map<String, dynamic> m) => Session(
        id: m['id'],
        createdAt: DateTime.parse(m['createdAt']),
        mePersonId: m['mePersonId'],
      );
}

/// Reads a price the way people type it: "12,50", "12.50", "1.234,56", "1,234.56", "-3,00 €".
/// Returns null when it isn't a number.
double? parsePrice(String input) {
  var s = input.replaceAll(RegExp(r'[\s€]|EUR|eur'), '').replaceAll('−', '-');
  if (s.isEmpty) return null;
  final lastSep = s.lastIndexOf(RegExp(r'[.,]'));
  if (lastSep >= 0) {
    final decimals = s.length - lastSep - 1;
    final seps = RegExp(r'[.,]').allMatches(s).length;
    // "1.234" alone could be 1,234 € or 1.234 €: ask instead of guessing.
    if (decimals == 3 && seps == 1) return null;
    final whole = s.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
    s = decimals == 3 ? whole + s.substring(lastSep + 1) : '$whole.${s.substring(lastSep + 1)}';
  }
  if (!RegExp(r'^[+-]?\d*\.?\d+$').hasMatch(s)) return null;
  return double.tryParse(s);
}
