/// Repairs Croatian letters that the till printed wrong.
///
/// Some fiscal printers use the wrong code page and print č/ć/š/ž/đ as other symbols
/// (receipt_0189: "Mijeтana", "tofeno", "RAǂUN"). The model copies what it sees, usually as a
/// similar Latin letter ("Mijetana", "tofeno"). The model also sometimes drops the accent
/// ("Mijesana").
///
/// A word is repaired only when it matches exactly one word below at every position except the
/// accented ones. At an accented position we accept: the plain letter (c/s/z/d), another accented or
/// non-ASCII character (т, τ, ǂ…), a symbol, or f/t (what this printer's glyphs look like) in words
/// of 5+ letters. So "tofeno" → "točeno", "Mijesana" → "Miješana", but "Riba" stays "Riba".
library;

class CroatianWords {
  /// Lower case, accented words that are common on bar, restaurant and shop receipts.
  /// Only words with č ć š ž đ matter; others never need fixing.
  /// Leave out words whose plain-ASCII form is another real word ("pića" ↔ "pica").
  static const words = [
    // drinks
    'točeno', 'točena', 'točeni', 'čaj', 'čaja', 'čaša', 'čaše', 'bočica', 'piće', 'špricer', 'gemišt',
    'šampanjac', 'šljivovica', 'cijeđeni', 'cijeđena', 'cijeđeno', 'voćni', 'voćna', 'voćno', 'vruća',
    'vruće', 'čokolada', 'čokoladni', 'čokoladna',
    // food
    'miješana', 'miješano', 'miješani', 'miješane', 'šnicla', 'šnicle', 'ćevapi', 'ćevapčići',
    'ražnjići', 'pršut', 'pršuta', 'pršutom', 'šunka', 'šunke', 'šunkom', 'škampi',
    'školjke', 'pašteta', 'gulaš', 'pečeno', 'pečena', 'pečeni', 'pečene', 'pečenje', 'prženo',
    'pržena', 'prženi', 'pržene', 'žaru', 'čips', 'češnjak', 'češnjaka', 'češnjakom', 'pileći', 'pileća',
    'pileće', 'pureći', 'pureća', 'teleći', 'teleća', 'teleće', 'riža', 'rižoto', 'rižot', 'palačinke',
    'palačinka', 'kolač', 'kolači', 'štrudla', 'štrukli', 'kroštule', 'čvarci', 'ćufte', 'đuveč',
    'šećer', 'šlag', 'šlagom', 'kečap', 'žganci', 'grčka', 'grčki', 'šopska', 'mliječni', 'mliječna',
    'domaći', 'domaća', 'domaće', 'kućni', 'kućna', 'kućno', 'dječji', 'dječja', 'dječje', 'veći',
    'veća', 'veće', 'četiri', 'doručak', 'ručak', 'večera', 'jušni', 'začini', 'umućeno', 'tjesteninom',
    // receipt words
    'račun', 'računa', 'uključ', 'uključena', 'uključeno', 'povratna', 'zaštitni', 'izdavatelja',
  ];

  static const _accented = 'čćšžđ';
  static const _plain = {'č': 'c', 'ć': 'c', 'š': 's', 'ž': 'z', 'đ': 'd'};
  static final _symbol = RegExp(r'''[^A-Za-z0-9\s]''');

  static final Map<int, List<String>> _byLength = () {
    final m = <int, List<String>>{};
    for (final w in words) {
      if (w.split('').any(_accented.contains)) (m[w.length] ??= []).add(w);
    }
    return m;
  }();

  static final _token = RegExp(r'[^\s/,.()0-9:;+*\-]+');

  /// Returns [name] with garbled or unaccented known words repaired.
  static String fix(String name) => name.replaceAllMapped(_token, (m) => _fixWord(m[0]!));

  static String _fixWord(String w) {
    final candidates = _byLength[w.length];
    if (candidates == null) return w;
    final lower = w.toLowerCase();
    String? found;
    for (final c in candidates) {
      if (c == lower) return w;
      if (_matches(lower, c)) {
        if (found != null && found != c) return w; // ambiguous
        found = c;
      }
    }
    return found == null ? w : _sameCase(w, found);
  }

  static bool _matches(String w, String dict) {
    for (var i = 0; i < dict.length; i++) {
      final d = dict[i], c = w[i];
      if (_accented.contains(d)) {
        final ok = c == _plain[d] || _symbol.hasMatch(c) || ((c == 'f' || c == 't') && dict.length >= 5);
        if (!ok) return false;
      } else if (c != d) {
        return false;
      }
    }
    return true;
  }

  static String _sameCase(String original, String word) {
    if (original == original.toUpperCase() && original != original.toLowerCase()) return word.toUpperCase();
    if (original[0] == original[0].toUpperCase() && original[0] != original[0].toLowerCase()) {
      return word[0].toUpperCase() + word.substring(1);
    }
    return word;
  }
}
