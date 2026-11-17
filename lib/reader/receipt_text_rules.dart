/// Photomath-style receipt reading: OCR text boxes -> items with plain rules, no language model.
///
/// Port of the author's Python prototype (rules_parser.py + `layout` from ocr_pipeline.py, not published).
/// The tests check the rules on sample receipts (test/receipt_rules_sample_test.dart).
///
/// An item row is a line whose trailing numbers contain qty x unit_price = price (qty/price columns in either
/// order, optional discount column). Text before those numbers is the name; if there is none (or only units like
/// "kom"), the name comes from the line(s) above (café bills, supermarket weights). The item table runs from the column
/// header (Naziv/Artikl … Kol/Cijena/Iznos) to the first total line / tax table / payment line.
library;

import 'dart:math' as math;

class TextItem {
  final String name;
  final double qty, unitPrice, price;
  const TextItem(this.name, this.qty, this.unitPrice, this.price);
  @override
  String toString() => '$name | $qty | $unitPrice | $price';
}

class TextDiscount {
  final String name;
  final double amount;
  const TextDiscount(this.name, this.amount);
}

class TextReceipt {
  final List<TextItem> items;
  final List<TextDiscount> discounts;
  final double? total;
  const TextReceipt(this.items, this.discounts, this.total);

  /// Items + discounts add up to the printed total (to the cent).
  bool get adds {
    if (total == null || items.isEmpty) return false;
    final s = items.fold(0.0, (a, i) => a + i.price) + discounts.fold(0.0, (a, d) => a + d.amount);
    return (s - total!).abs() <= _tot;
  }
}

/// One OCR box: 4 corner points (x, y) and its text.
class OcrBox {
  final List<List<double>> points;
  final String text;
  const OcrBox(this.points, this.text);
}

const _tot = 0.011;

RegExp _rx(String p) => RegExp(p, caseSensitive: false, unicode: true);
RegExp _rxCase(String p) => RegExp(p, unicode: true);

// Python's \w is Unicode-aware, Dart's is not: use this instead.
const _w = r'[\p{L}\p{N}_]';
const _letter = r'[A-Za-zČĆŠŽĐčćšžđ]';

/// Boxes -> text lines: deskew by the median text angle, group boxes whose vertical centres are close,
/// sort left to right; wide gaps become 4 spaces so columns stay visible.
String layout(List<OcrBox> boxes) {
  if (boxes.isEmpty) return '';
  var pts = [for (final b in boxes) b.points];
  final angs = [
    for (final b in pts)
      if (b.length == 4) math.atan2(b[1][1] - b[0][1], b[1][0] - b[0][0]),
  ]..sort();
  if (angs.isNotEmpty && angs[angs.length ~/ 2].abs() > 0.02) {
    final a0 = -angs[angs.length ~/ 2], c = math.cos(a0), s = math.sin(a0);
    pts = [
      for (final b in pts)
        [
          for (final p in b) [p[0] * c - p[1] * s, p[0] * s + p[1] * c],
        ],
    ];
  }
  final items = <_Cell>[];
  for (var i = 0; i < boxes.length; i++) {
    final xs = pts[i].map((p) => p[0]), ys = pts[i].map((p) => p[1]);
    items.add(
      _Cell(
        xs.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce((a, b) => a + b) / pts[i].length,
        ys.reduce(math.max) - ys.reduce(math.min),
        boxes[i].text,
      ),
    );
  }
  final hs = items.map((i) => i.h).toList()..sort();
  final n = hs.length;
  final h = n.isOdd ? hs[n ~/ 2] : (hs[n ~/ 2 - 1] + hs[n ~/ 2]) / 2;
  final sorted = [...items]..sort((a, b) => a.yc.compareTo(b.yc));
  final rows = <_Row>[];
  for (final it in sorted) {
    if (rows.isNotEmpty && (it.yc - rows.last.yc).abs() < 0.5 * h) {
      rows.last.cells.add(it);
      rows.last.yc = rows.last.cells.fold(0.0, (a, c) => a + c.yc) / rows.last.cells.length;
    } else {
      rows.add(_Row(it.yc, [it]));
    }
  }
  final lines = <String>[];
  for (final r in rows) {
    final cells = [...r.cells]..sort((a, b) => a.x0.compareTo(b.x0));
    final sb = StringBuffer(cells.first.t);
    for (var i = 1; i < cells.length; i++) {
      sb.write(cells[i].x0 - cells[i - 1].x1 > h ? '    ' : ' ');
      sb.write(cells[i].t);
    }
    lines.add(sb.toString());
  }
  return lines.join('\n');
}

class _Cell {
  final double x0, x1, yc, h;
  final String t;
  _Cell(this.x0, this.x1, this.yc, this.h, this.t);
}

class _Row {
  double yc;
  final List<_Cell> cells;
  _Row(this.yc, this.cells);
}

// ---------- numbers ----------

class _Num {
  final double v;
  final int start, end, dec;
  const _Num(this.v, this.start, this.end, this.dec);
}

final _fixes = <(RegExp, String Function(Match))>[
  (_rxCase('(?<!$_w)[CO](?=[,.][0-9]{2}(?!$_w))'), (m) => '0'),
  (_rxCase(r'([0-9])[,.]\s([0-9]{2})(?![0-9])'), (m) => '${m[1]},${m[2]}'),
  (_rxCase(r'([0-9])[.,]{2}([0-9])'), (m) => '${m[1]},${m[2]}'),
  (_rxCase(r'([0-9])O(?=[0-9]|[,.][0-9])'), (m) => '${m[1]}0'),
  (_rxCase(r'([0-9][,.][0-9]{2})[O0o](?=\s|$|€)'), (m) => m[1]!), // ML Kit "9,30O EUR"
  (_rxCase(r'(?<=[\s0-9])([x×*])(?=[0-9])'), (m) => '${m[1]} '), // "1 x2,65" -> "1 x 2,65"
  (_rxCase(r'(?<![\p{L}\p{N}_,.])([0-9]{1,3})([x×])(?=\s|$)'), (m) => '${m[1]} ${m[2]}'), // "1x 12,00"
];

final _num = _rxCase(
  r'(?<![\p{L}\p{N}_/.,])(-?[0-9]{1,6}(?:[.,][0-9]{1,3})?)(?:€|[ABCEHNP](?!'
  '$_w'
  r'))?(?![\p{L}\p{N}_/%])',
);
final _upside = _rxCase(
  r'(?<![\p{L}\p{N}_,.])([01689]{1,3})'
  "'"
  r'([01689]{1,2})(?![\p{L}\p{N}_,.])',
);

List<_Num> _numbers(String line) => [
  for (final m in _num.allMatches(line))
    _Num(
      double.parse(m[1]!.replaceAll(',', '.')),
      m.start,
      m.end,
      m[1]!.contains(RegExp(r'[.,]')) ? m[1]!.split(RegExp(r'[.,]'))[1].length : 0,
    ),
];

/// OCR sometimes reads a price box upside down: "0,99" -> "66'0". Rotate it back.
String _unflip(Match m) {
  final s = ("${m[1]}'${m[2]}").split('').reversed.join();
  return s
      .split('')
      .map(
        (c) => switch (c) {
          '6' => '9',
          '9' => '6',
          "'" => ',',
          _ => c,
        },
      )
      .join();
}

String _cleanLine(String line) {
  line = line.replaceAllMapped(_upside, _unflip);
  for (final (rx, rep) in _fixes) {
    line = line.replaceAllMapped(rx, rep);
  }
  return line;
}

// ---------- line kinds ----------

final _header = _rx(r'\b(naziv|artikl|artikal|artiki|opis|proizvod)\w*');
final _headerCol = _rx(r'\b(kol|kolicina|količina|cijena|cijl|iznos|ukupno|jed)');
final _total = _rx(
  r'^[^\p{L}\p{N}_]*(sve\s*)?(ukupno|za\s*platiti|total|iznos\s*za\s*pla|za\s*naplatu|ukupan\s*iznos)(?!\s*(porez|popust|pdv))(?![a-zčćšž])',
);
final _pay = _rx(
  r'(?<![\p{L}\p{N}_])(novčanice|novcanice|novćanice|gotovina|kartic[\p{L}\p{N}_]*|placeno|plaćeno|monri)(?![\p{L}\p{N}_])|^[^\p{L}\p{N}_]*€\s*:',
);
final _skip = _rx(
  r'(?<![\p{L}\p{N}_])(pdv|pnp|osnovica|porez|stopa|oib|zki|jir|datum|vrijeme|račun\s*br|racun\s*br|broj\s*rač|blagajn|'
  r'operater|stol(?![\p{L}\p{N}_])|poslužuje|posluzuje|artikli(?![\p{L}\p{N}_])|rekapitulacija|tel[.:]|iban|popust|multipluscard|bonus|'
  r'povratn[\p{L}\p{N}_]*\s*naknad|pov\.?\s*naknad|naknada|ambalaž)',
);
final _discountLine = _rx(r'\b(popust|multipluscard)\b');
final _deposit = _rx(r'(pov[\p{L}\p{N}_]*\.?\s*naknad|povratn[\p{L}\p{N}_]*\s*naknad)');
final _unitJunk = _rx(r'^(?:\d+\s*)?(?:\s|x|×|\*|kom|ko|kg|j\.?m\.?|kn|eur|€|=|:|-)*$');
final _taxHead = _rx(r'\b(pdv|osnovica|porez|stopa)\b');
// a VAT row: "25,00%  15,04  3,76  0,00" (rate, base, VAT, PNP)
final _vatRow = _rx(r'^\W*\d{1,2}[,.]\d{2}\s*%');
final _hasWord = _rxCase('$_letter{2}');
final _letterRx = _rxCase(_letter);

bool _isInt(double x) => (x - x.roundToDouble()).abs() < 1e-9;

/// Python round() (banker's) for the integer case.
int _pyRound(double x) {
  final f = x.floorToDouble(), d = x - f;
  if ((d - 0.5).abs() < 1e-12) return f.toInt().isEven ? f.toInt() : f.toInt() + 1;
  return x.round();
}

double _round(double x, int digits) {
  final m = math.pow(10, digits);
  return (x * m).round() / m;
}

(double, double) _whichQty(_Num x, _Num y, bool priceFirst) {
  final a = x.v, b = y.v;
  if (x.dec == 3 && y.dec != 3) return (a, b); // 0,562 weight
  if (y.dec == 3 && x.dec != 3) return (b, a);
  final ai = _isInt(a), bi = _isInt(b);
  if (ai && bi && (a == 1) != (b == 1)) return a == 1 ? (a, b) : (b, a); // "3,00 1,00 = 3,00"
  if (priceFirst) return (bi || !ai) ? (b, a) : (a, b);
  if (ai && !bi) return (a, b);
  if (bi && !ai) return (b, a);
  return (a, b);
}

/// (qty, unit, price, index of the first number used) or null.
(double, double, double, int)? _findTriple(List<_Num> nums, bool priceFirst) {
  if (nums.length < 2) return null;
  var pi = nums.length - 1;
  while (pi >= 0 && nums[pi].dec != 2) {
    pi--;
  }
  if (pi < 1) return null;
  final p = nums[pi].v;
  if (p <= 0) return null;
  for (var i = pi - 1; i >= 0; i--) {
    for (var j = pi - 1; j > i; j--) {
      final a = nums[i].v, b = nums[j].v;
      if (a <= 0 || b <= 0) continue;
      final weight = nums[i].dec == 3 || nums[j].dec == 3;
      var ok = (a * b - p).abs() <= (weight ? 0.031 : _tot);
      if (!ok) {
        for (var k = j + 1; k < pi; k++) {
          if ((a * b - nums[k].v - p).abs() <= _tot) ok = true;
        }
      }
      if (!ok) continue;
      final (q, u) = _whichQty(nums[i], nums[j], priceFirst);
      return (q, u, p, i); // the pair closest to the price column
    }
  }
  // a zero discount column right before the price ("100  1,90  0,00  1,90", qty's dot lost) is not the unit price
  var k = pi - 1;
  while (k > 0 && nums[k].v == 0 && nums[k].dec == 2) {
    k--;
  }
  final prev = nums[k];
  final a = prev.v;
  if ((a - p).abs() < 0.005 && prev.dec == 2) return (1.0, p, p, k); // "12,00  12,00"
  if (prev.dec == 2 && a >= 1 && a <= 20 && a == a.roundToDouble() && (_round(p / a, 2) * a - p).abs() <= _tot) {
    return (a, _round(p / a, 2), p, k); // "1,00  3,00"
  }
  if (prev.dec == 2 && a > 0) {
    final r = _pyRound(p / a);
    if (r >= 2 && r <= 50 && (r * a - p).abs() <= _tot) return (r.toDouble(), a, p, k); // qty dropped
  }
  if ((a - p).abs() <= _tot && prev.dec == 2) return (1.0, p, p, k);
  return null;
}

bool _priceFirst(String line) {
  final l = line.toLowerCase();
  final c = l.indexOf('cijena'), k = l.indexOf('kol');
  return c >= 0 && k >= 0 && c < k;
}

bool _isHeader(String line) => _header.hasMatch(line) && _headerCol.hasMatch(line);

final _prevTotal = _rx(r'^\s*[0-9]+[,.][0-9]{2}\s*(eur|€|kn)?\s*$');
final _spacedCents = _rx(r'([0-9]) ([0-9]{2})\s*(eur|€|kn)?\s*$');

double? _totalAmount(List<String> lines, int i) {
  final prev = i > 0 && _prevTotal.hasMatch(lines[i - 1]) ? lines[i - 1] : '';
  for (var ln in [lines[i], i + 1 < lines.length ? lines[i + 1] : '', prev]) {
    ln = ln.replaceAllMapped(_spacedCents, (m) => '${m[1]},${m[2]}'); // "UKUPNO EUR  27 99"
    final ns = _numbers(ln).where((n) => n.dec == 2).toList();
    if (ns.isNotEmpty) return ns.last.v;
  }
  return null;
}

String _nameFrom(String text) {
  var t = text.replaceFirst(RegExp(r'^\s*[0-9]{8,14}\s+'), ''); // barcode
  t = t.replaceFirst(RegExp(r'^\s*[!*#]\s*'), ''); // Konzum "!" marker
  t = t.replaceFirst(RegExp(r'[\s|x×*=:]+$'), '');
  return t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
}

TextReceipt parseReceiptText(String text) {
  final lines = [for (final l in text.split(RegExp(r'\r?\n'))) _cleanLine(l)];
  int? firstTotal;
  for (var i = 0; i < lines.length; i++) {
    if (_total.hasMatch(lines[i]) && _totalAmount(lines, i) != null) {
      firstTotal = i;
      break;
    }
  }
  var end = firstTotal ?? lines.length;
  var start = 0;
  var priceFirst = false;
  for (var i = 0; i < end; i++) {
    if (_isHeader(lines[i])) {
      start = i + 1;
      priceFirst = _priceFirst(lines[i]);
      if (start < end && _numbers(lines[start]).isEmpty && _headerCol.hasMatch(lines[start])) {
        priceFirst = _priceFirst(lines[start]);
        start++;
      }
    }
  }
  for (var i = start; i < end; i++) {
    if (_taxHead.hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  var payFound = false;
  if (firstTotal == null) {
    for (var i = start; i < lines.length; i++) {
      final both = '${lines[i]} ${i + 1 < lines.length ? lines[i + 1] : ''}';
      if (_pay.hasMatch(lines[i]) && _numbers(both).isNotEmpty) {
        end = i;
        payFound = true;
        break;
      }
    }
  }

  final items = <TextItem>[];
  var pending = <String>[];
  String? unusedAbove; // the previous item's name line that went unused (see the tilt fix below)
  for (final ln in lines.sublist(start, math.max(start, end))) {
    if (_discountLine.hasMatch(ln) || _skip.hasMatch(ln)) {
      pending = [];
      continue;
    }
    final nums = _numbers(ln);
    final t = _findTriple(nums, priceFirst);
    if (t == null) {
      if (_hasWord.hasMatch(ln)) pending.add(ln);
      continue;
    }
    final (q, u, p, first) = t;
    final own = _nameFrom(ln.substring(0, nums[first].start));
    String name;
    if (pending.isNotEmpty && (own.isEmpty || _unitJunk.hasMatch(own) || _letterRx.allMatches(own).length < 3)) {
      final above = pending.sublist(math.max(0, pending.length - 2)).join(' ');
      name = _nameFrom(above) + (own.isEmpty || _unitJunk.hasMatch(own) ? '' : ' $own');
    } else {
      name = own;
    }
    // tilted photo: the number row got joined to the NEXT item's name ("MINERALNA VODA  1,00 3,40 ...") while
    // its own name sits unused above, and the next number row has no name -> every name belongs one row lower
    if (items.isNotEmpty && unusedAbove != null && name.isEmpty && pending.isEmpty) {
      final prev = items.removeLast();
      name = prev.name;
      items.add(TextItem(unusedAbove, prev.qty, prev.unitPrice, prev.price));
    }
    unusedAbove = pending.isNotEmpty && name == own && own.isNotEmpty
        ? _nameFrom(pending.sublist(math.max(0, pending.length - 2)).join(' '))
        : null;
    pending = [];
    items.add(TextItem(name.isEmpty ? '?' : name, q, _round(u, 3), p));
  }

  double? total;
  final discounts = <TextDiscount>[];
  if (firstTotal != null) {
    total = _totalAmount(lines, firstTotal);
    for (var i = firstTotal + 1; i < lines.length && i <= firstTotal + 6; i++) {
      final ns = _numbers(lines[i]);
      final neg = ns.isNotEmpty && ns.last.v < 0;
      if (neg && ns.last.dec == 2 && !_skip.hasMatch(lines[i])) {
        discounts.add(TextDiscount(_nameFrom(lines[i].substring(0, ns.last.start)), ns.last.v));
      } else if (_total.hasMatch(lines[i]) && discounts.isNotEmpty) {
        total = _totalAmount(lines, i);
        break;
      } else if (!_total.hasMatch(lines[i]) && !neg) {
        break;
      }
    }
  } else {
    final s = _round(items.fold(0.0, (a, i) => a + i.price), 2);
    final after = [
      for (final ln in lines.sublist(math.min(end, lines.length), math.min(end + 4, lines.length)))
        if (!_taxHead.hasMatch(ln))
          for (final n in _numbers(ln))
            if (n.dec == 2) n.v,
    ];
    // base + VAT + PNP from the VAT rows = the total (when the paid amount is unreadable, "1E,80")
    double? vatTotal;
    for (final ln in lines.sublist(math.min(end, lines.length), math.min(end + 8, lines.length))) {
      if (!_vatRow.hasMatch(ln)) continue;
      final ns = [for (final n in _numbers(ln).skip(1)) if (n.dec == 2) n.v];
      if (ns.length >= 2) vatTotal = _round((vatTotal ?? 0) + ns.fold(0.0, (a, v) => a + v), 2);
    }
    final cands = [...after, ?vatTotal];
    total = s > 0 && cands.any((a) => (a - s).abs() <= _tot)
        ? s
        : (vatTotal != null && !payFound ? vatTotal : (after.isNotEmpty ? after.first : null));
  }

  // bottle deposit added on top (Konzum, after the tax table), only when it makes the sum match
  final s = _round(items.fold(0.0, (a, i) => a + i.price) + discounts.fold(0.0, (a, d) => a + d.amount), 2);
  if (total != null && (s - total).abs() > _tot) {
    for (final ln in lines) {
      if (!_deposit.hasMatch(ln)) continue;
      final ns = _numbers(ln);
      final t = ns.length >= 2 ? _findTriple(ns, false) : null;
      if (t != null && (s + t.$3 - total).abs() <= _tot) {
        final n = _nameFrom(ln.substring(0, ns[t.$4].start));
        items.add(TextItem(n.isEmpty ? 'Povratna naknada' : n, t.$1, t.$2, t.$3));
        break;
      }
    }
  }
  return TextReceipt(items, discounts, total);
}
