import 'dart:io';

import 'package:bambumpos_pos/core/yazici_kimlik.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ESC/POS durum baytı', () {
    test('tipik çevrimiçi yanıt 0x12 ve çekmece biti 0x16', () {
      expect(KimlikAyristir.durumBaytiMi(0x12), isTrue);
      expect(KimlikAyristir.durumBaytiMi(0x16), isTrue);
      expect(KimlikAyristir.cevrimdisiMi(0x12), isFalse);
      expect(KimlikAyristir.cevrimdisiMi(0x1A), isTrue);
    });
    test('ESC/POS olmayan yanıtlar reddedilir', () {
      for (final b in [0x00, 0xFF, 0x40, 0x5F, 0x48, 0x10, 0x02, 0x92]) {
        expect(KimlikAyristir.durumBaytiMi(b), isFalse, reason: '0x${b.toRadixString(16)}');
      }
    });
  });

  group('GS I ayrıştırma', () {
    test('başlıklı metin (0x5F … 0x00)', () {
      expect(KimlikAyristir.metin([0x5F, ...'XPRINTER'.codeUnits, 0x00]), 'XPRINTER');
      expect(KimlikAyristir.metin([0x5F, ...' TM-T20II '.codeUnits, 0x00]), 'TM-T20II');
      expect(KimlikAyristir.metinTamam([0x5F, 0x41]), isFalse);
      expect(KimlikAyristir.metin([0x5F, 0x41]), isNull);
      expect(KimlikAyristir.metin([0x5F, 0x00]), isNull);
      expect(KimlikAyristir.metin([0x41, 0x00]), isNull);
    });
    test('denetim baytları süzülür', () {
      expect(KimlikAyristir.metin([0x5F, 0x01, ...'AB12'.codeUnits, 0x07, 0x00]), 'AB12');
    });
    test('tek bayt (GS I 1/2)', () {
      expect(KimlikAyristir.tekBayt([0x20]), '20');
      expect(KimlikAyristir.tekBayt([0x02]), '02');
      expect(KimlikAyristir.tekBayt([]), isNull);
    });
    test('anlamsız seri no kimlik sayılmaz', () {
      expect(KimlikAyristir.seriTemizle('00000000'), isNull);
      expect(KimlikAyristir.seriTemizle('123456789'), isNull);
      expect(KimlikAyristir.seriTemizle('ab'), isNull);
      expect(KimlikAyristir.seriTemizle(' X3NB012345 '), 'X3NB012345');
    });
  });

  group('MAC / ARP', () {
    test('biçim birleştirme', () {
      expect(KimlikAyristir.macTemizle('0:11:22:a:b:c'), '00:11:22:0A:0B:0C');
      expect(KimlikAyristir.macTemizle('00-11-22-33-44-55'), '00:11:22:33:44:55');
      expect(KimlikAyristir.macTemizle('ff-ff-ff-ff-ff-ff'), isNull);
      expect(KimlikAyristir.macTemizle('01-00-5e-00-00-16'), isNull);
      expect(KimlikAyristir.macTemizle('(incomplete)'), isNull);
    });
    test('Windows arp -a', () {
      const c = '''
Interface: 192.168.1.34 --- 0x7
  Internet Address      Physical Address      Type
  192.168.1.1           a0-b1-c2-d3-e4-f5     dynamic
  192.168.1.202         00-47-50-4e-54-52     dynamic
  192.168.1.255         ff-ff-ff-ff-ff-ff     static
  224.0.0.22            01-00-5e-00-00-16     static
''';
      expect(KimlikAyristir.arp(c), {'192.168.1.1': 'A0:B1:C2:D3:E4:F5', '192.168.1.202': '00:47:50:4E:54:52'});
    });
    test('macOS arp -an + eksik kayıt', () {
      const c = '''
? (192.168.1.1) at a0:b1:c2:d3:e4:f5 on en0 ifscope [ethernet]
? (192.168.1.102) at 0:47:50:4e:54:1 on en0 ifscope [ethernet]
? (192.168.1.150) at (incomplete) on en0 ifscope [ethernet]
''';
      expect(KimlikAyristir.arp(c), {'192.168.1.1': 'A0:B1:C2:D3:E4:F5', '192.168.1.102': '00:47:50:4E:54:01'});
    });
    test('aynı MAC iki IP\'de (tekrarlayıcı) → kimlik sayılmaz', () {
      const c = '''
  192.168.1.102         00-11-22-33-44-55     dynamic
  192.168.1.197         00-11-22-33-44-55     dynamic
  192.168.1.5           00-11-22-33-44-66     dynamic
''';
      expect(KimlikAyristir.arp(c), {'192.168.1.5': '00:11:22:33:44:66'});
    });
  });

  group('Yoklayıcı (sahte yazıcı soketi)', () {
    Future<(ServerSocket, List<int>)> sahte(List<int>? Function(List<int> istek) cevap) async {
      final alinan = <int>[];
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((k) {
        k.listen((d) {
          alinan.addAll(d);
          final c = cevap(d);
          if (c != null) k.add(c);
        }, onError: (_) {});
      });
      return (s, alinan);
    }

    test('ESC/POS yazıcı: kimlik okunur, yazdırma komutu gitmez', () async {
      final (s, alinan) = await sahte((d) {
        if (d.length >= 3 && d[0] == 0x10 && d[1] == 0x04) return [0x12];
        if (d.length >= 3 && d[0] == 0x1D && d[1] == 0x49) {
          return switch (d[2]) {
            1 => [0x20],
            2 => [0x02],
            65 => [0x5F, ...'V1.08'.codeUnits, 0x00],
            66 => [0x5F, ...'XPRINTER'.codeUnits, 0x00],
            67 => [0x5F, ...'XP-Q80A'.codeUnits, 0x00],
            68 => [0x5F, ...'Q80A2207001234'.codeUnits, 0x00],
            _ => null,
          };
        }
        return null;
      });
      final k = await KimlikYoklayici.sor('127.0.0.1', s.port);
      await s.close();
      expect(k.escpos, isTrue);
      expect(k.uretici, 'XPRINTER');
      expect(k.model, 'XP-Q80A');
      expect(k.seri, 'Q80A2207001234');
      expect(k.surum, 'V1.08');
      expect(k.modelKodu, '20/02');
      // Gönderilen her bayt ya DLE EOT ya GS I'dır; LF/metin YOK.
      expect(alinan.contains(0x0A), isFalse);
      expect(alinan.contains(0x1B), isFalse, reason: 'tüm sorular yanıtlandı; ESC @ gerekmedi');
    });

    test('ESC/POS olmayan cihaz: GS I hiç gönderilmez', () async {
      final (s, alinan) = await sahte((_) => null);
      final k = await KimlikYoklayici.sor('127.0.0.1', s.port);
      await s.close();
      expect(k.escpos, isFalse);
      expect(k.bos, isTrue);
      expect(alinan, [0x10, 0x04, 0x01]);
    });

    test('GS I bilmeyen klon: sonunda ESC @ ile tampon temizlenir', () async {
      final (s, alinan) = await sahte((d) => d[0] == 0x10 ? [0x16] : null);
      final k = await KimlikYoklayici.sor('127.0.0.1', s.port);
      await s.close();
      expect(k.escpos, isTrue);
      expect(k.seri, isNull);
      expect(alinan.sublist(alinan.length - 2), [0x1B, 0x40]);
    });

    test('çevrimdışı yazıcıya GS I gönderilmez', () async {
      final (s, alinan) = await sahte((d) => d[0] == 0x10 ? [0x1A] : null);
      final k = await KimlikYoklayici.sor('127.0.0.1', s.port);
      await s.close();
      expect(k.escpos, isTrue);
      expect(alinan, [0x10, 0x04, 0x01]);
    });

    test('kapalı port: boş kimlik, hata atmaz', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final p = s.port;
      await s.close();
      final k = await KimlikYoklayici.sor('127.0.0.1', p).timeout(const Duration(seconds: 5));
      expect(k.bos, isTrue);
    });
  });
}
