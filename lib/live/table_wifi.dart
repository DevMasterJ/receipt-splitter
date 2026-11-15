/// Table Wi-Fi for the live bill (see android/.../TableWifi.kt).
///
/// Host: an app-owned hotspot without internet sharing, so guests can reach this phone anywhere.
/// Guest (with the app): connect only this app to the host's hotspot from the QR code.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HotspotInfo {
  final String ssid;
  final String password;

  /// 1 = WPA2, 2 = WPA3 transition (WPA2 also works), 3 = WPA3 only.
  final int security;

  /// This phone's address on the hotspot (what goes into the bill link).
  final String? address;

  const HotspotInfo(this.ssid, this.password, this.security, this.address);

  /// Standard Wi-Fi QR payload: every Android/iPhone camera offers "Join network".
  String get wifiQr => 'WIFI:T:${security == 3 ? 'SAE' : 'WPA'};S:${_esc(ssid)};P:${_esc(password)};;';

  static String _esc(String s) => s.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');
}

class TableWifi {
  static const _ch = MethodChannel('receipt_splitter/table_wifi');

  static HotspotInfo? _hotspot;
  static HotspotInfo? get hotspot => _hotspot;

  /// Bumped when Android turns the table Wi-Fi off by itself (its QR code is then stale).
  static final stopped = ValueNotifier<int>(0);
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'hotspotStopped' && _hotspot != null) {
        _hotspot = null;
        stopped.value++;
      }
    });
  }

  /// Nearby Wi-Fi devices permission (location on Android 12 and older).
  static Future<bool> ensurePermission() async => await _ch.invokeMethod<bool>('ensurePermission') ?? false;

  /// Starts the table Wi-Fi. Throws [PlatformException] with code `permission`, `incompatible`
  /// (the normal hotspot is already on), `no_channel`, ...
  static Future<HotspotInfo> startHotspot() async {
    if (_hotspot != null) return _hotspot!;
    if (!await ensurePermission()) {
      throw PlatformException(code: 'permission', message: 'Nearby Wi-Fi devices permission was denied');
    }
    _listen();
    final before = await _ipv4s();
    final m = (await _ch.invokeMapMethod<String, dynamic>('startHotspot'))!;
    // the hotspot interface gets its address a moment after the callback
    String? addr;
    for (var i = 0; i < 20 && addr == null; i++) {
      addr = (await _ipv4s()).where((a) => !before.contains(a)).firstOrNull;
      if (addr == null) await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return _hotspot = HotspotInfo(m['ssid'] ?? '', m['password'] ?? '', m['security'] ?? 1, addr);
  }

  static Future<void> stopHotspot() async {
    _hotspot = null;
    await _ch.invokeMethod('stopHotspot');
  }

  /// Guest: connect this app to the host's hotspot (Android asks "Connect to …?").
  static Future<void> join(String ssid, String password, int security) async {
    if (!await ensurePermission()) {
      throw PlatformException(code: 'permission', message: 'Nearby Wi-Fi devices permission was denied');
    }
    await _ch.invokeMethod('join', {'ssid': ssid, 'password': password, 'security': security});
  }

  static Future<void> leave() => _ch.invokeMethod('leave');

  /// Guest who joined the table Wi-Fi outside the app: route this app's traffic through it.
  static Future<bool> bindToHost(String host) async =>
      await _ch.invokeMethod<bool>('bindToHost', {'host': host}) ?? false;

  static Future<Set<String>> _ipv4s() async => {
        for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4))
          for (final a in ni.addresses)
            if (!a.isLoopback) a.address,
      };
}
