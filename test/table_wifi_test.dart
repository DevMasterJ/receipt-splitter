import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_splitter/live/live_server.dart';
import 'package:receipt_splitter/live/table_wifi.dart';

void main() {
  test('Wi-Fi QR payload escapes special characters', () {
    expect(const HotspotInfo('AndroidShare_1234', 'abc;d:e', 2, null).wifiQr,
        r'WIFI:T:WPA;S:AndroidShare_1234;P:abc\;d\:e;;');
    expect(const HotspotInfo('x', 'y', 3, null).wifiQr, 'WIFI:T:SAE;S:x;P:y;;');
  });

  test('bill link carries the table Wi-Fi login for the in-app scanner', () {
    final u = Uri.parse(LiveServer.instance.url('192.168.49.1', wifi: const HotspotInfo('AndroidShare_1', 'p&w d', 2, null)));
    expect(u.host, '192.168.49.1');
    expect(u.queryParameters, {'k': LiveServer.instance.key, 's': 'AndroidShare_1', 'p': 'p&w d', 't': '2'});
    expect(Uri.parse(LiveServer.instance.url('10.0.0.5')).queryParameters.keys, ['k']);
  });
}
