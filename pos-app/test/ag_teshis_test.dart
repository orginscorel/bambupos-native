import 'dart:convert';
import 'dart:io';

import 'package:bambumpos_pos/core/ag_teshis.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _etiket(String ad) => [for (final l in ad.split('.')) ...[l.length, ...ascii.encode(l)], 0];

void main() {
  test('mDNS PTR sorgusu ve sıkıştırmalı yanıt', () {
    final q = DnsPaket.ptrSorgusu('192.168.1.102');
    expect(q.sublist(12, 12 + 4), [3, ...ascii.encode('102')]);
    final hedef = _etiket('Ahmet-iPhone.local');
    final yanit = [
      0x00, 0x2A, 0x84, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
      ...q.sublist(12),
      0xC0, 0x0C, 0x00, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x78, 0x00, hedef.length,
      ...hedef,
    ];
    expect(DnsPaket.ptrYaniti(yanit), 'Ahmet-iPhone.local');
    expect(DnsPaket.ptrYaniti([1, 2, 3]), isNull);
  });

  test('NetBIOS NBSTAT yanıtı: bilgisayar adı + MAC', () {
    List<int> ad(String s, int sonek, int bayrak) => [...ascii.encode(s.padRight(15)), sonek, bayrak, 0x00];
    final p = <int>[
      ...List.filled(12, 0), ...List.filled(34, 0x41), 0x00, 0x21, 0x00, 0x01, 0, 0, 0, 0, 0x00, 0x41,
      3,
      ...ad('WORKGROUP', 0x00, 0x84), // grup adı atlanır
      ...ad('KASA-PC', 0x00, 0x04),
      ...ad('KASA-PC', 0x20, 0x04),
      0x00, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E,
    ];
    final r = NetBios.yanit(p)!;
    expect(r.ad, 'KASA-PC');
    expect(r.mac, '00:1A:2B:3C:4D:5E');
    expect(NetBios.sorgu().length, 50);
  });

  test('HTTP başlık / Server', () {
    final r = HttpIpucu.ayristir('HTTP/1.0 200 OK\r\nServer: GoAhead-Webs\r\n\r\n<html><head><TITLE>\n Printer  Setup </TITLE>');
    expect(r, {'sunucu': 'GoAhead-Webs', 'baslik': 'Printer Setup'});
  });

  test('kapalı port "reddetti" sayılır (cihaz var)', () async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    try {
      await Socket.connect('127.0.0.1', p, timeout: const Duration(seconds: 2));
      fail('bağlanmamalıydı');
    } on SocketException catch (e) {
      expect(AgTeshis.reddedildiMi(e), isTrue);
    }
  });
}
