/// Checks for links and data that come from other phones (QR codes, receiptsplitter:// links, the host's
/// bill updates). Anyone can make a QR code, so nothing from it is trusted as is.
library;

/// A bill link points at a phone on the local network: a private IPv4 address, a normal port and a
/// session key like the host makes. Anything else (internet hosts, odd keys) is refused.
bool isTableLink(Uri uri) {
  final key = uri.queryParameters['k'] ?? '';
  if (!RegExp(r'^[a-z0-9]{6}$').hasMatch(key)) return false;
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return false;
  return isPrivateIPv4(uri.host);
}

bool isPrivateIPv4(String host) {
  final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (m == null) return false;
  final b = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
  if (b.any((x) => x > 255)) return false;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      b[0] == 127; // the host's own phone
}

/// The host's bill update with only the fields the guest screen uses, in the right types and sizes.
/// Returns null when it isn't a bill update.
Map<String, dynamic>? cleanBillState(Object? raw) {
  if (raw is! Map || raw['type'] != 'state') return null;
  String str(Object? v) => v is! String ? '' : v.length > 200 ? v.substring(0, 200) : v;
  num money(Object? v) => v is num && v.isFinite ? v : 0;
  int? id(Object? v) => v is int ? v : null;
  List<Map> list(Object? v, int max) => v is List ? v.whereType<Map>().take(max).toList() : const [];
  return {
    'type': 'state',
    'persons': [
      for (final p in list(raw['persons'], 100))
        {'id': id(p['id']), 'name': str(p['name']), 'total': money(p['total']),
         'claimedBy': p['claimedBy'] is String ? str(p['claimedBy']) : null},
    ],
    'items': [
      for (final i in list(raw['items'], 1000))
        {'id': id(i['id']), 'name': str(i['name']), 'price': money(i['price']), 'personId': id(i['personId'])},
    ],
    'unassigned': money(raw['unassigned']),
    'total': money(raw['total']),
  };
}
