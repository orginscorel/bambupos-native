import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bambumpos_pos/core/ajan.dart';
import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/pos_cihaz.dart';
import 'package:bambumpos_pos/core/usb.dart';
import 'package:bambumpos_pos/core/usb_android.dart';
import 'package:bambumpos_pos/core/usb_macos.dart';
import 'package:bambumpos_pos/core/usb_windows.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SahteSoket implements Socket {
  bool kapandi = false;
  @override
  void destroy() => kapandi = true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _BosSunucu implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async => ResponseBody.fromString('{}', 200);
  @override
  void close({bool force = false}) {}
}

UsbCihaz _cihaz(String anahtar, String tur, {String? vid, String? pid}) =>
    UsbCihaz(anahtar: anahtar, tur: tur, ad: anahtar, platform: 'windows', vid: vid, pid: pid);

void main() {
  group('USB sınıflandırma', () {
    test('yazıcı sınıfı (7) her zaman yazıcı', () {
      expect(usbTurBelirle(vid: '1234', pid: '0001', siniflar: [0, 7]), 'yazici');
    });
    test('bilinen fiş yazıcısı üreticileri', () {
      expect(usbTurBelirle(vid: '04b8', pid: '0202'), 'yazici'); // Epson
      expect(usbTurBelirle(vid: '0519', pid: '0003'), 'yazici'); // Star
      expect(usbTurBelirle(vid: '0416', pid: '5011'), 'yazici'); // POS-58
    });
    test('genel yonga üreticisi yalnız vid ile yazıcı sayılmaz', () {
      expect(usbTurBelirle(vid: '0416', pid: 'c141'), 'bilinmiyor');
      expect(usbTurBelirle(vid: '0483', pid: '5740'), 'bilinmiyor');
    });
    test('kart POS üreticileri ve adları', () {
      expect(usbTurBelirle(vid: '0b00', pid: '0084'), 'pos'); // Ingenico
      expect(usbTurBelirle(vid: '11ca', pid: '0219'), 'pos'); // Verifone
      expect(usbTurBelirle(vid: 'ffff', pid: '0001', ad: 'Hugin FT200 (COM4)'), 'pos');
      expect(usbTurBelirle(vid: 'ffff', pid: '0001', ad: 'Inpos M530'), 'pos');
    });
    test('adından yazıcı', () {
      expect(usbTurBelirle(vid: 'ffff', pid: '0001', ad: 'XP-80C'), 'yazici');
      expect(usbTurBelirle(vid: 'ffff', pid: '0001', ad: 'USB Receipt Printer'), 'yazici');
      expect(usbTurBelirle(vid: 'ffff', pid: '0001', ad: 'USB Optical Mouse'), 'bilinmiyor');
    });
    test('hex4', () {
      expect(hex4(1208), '04b8');
      expect(hex4('0x04B8  (Seiko Epson Corp.)'), '04b8');
      expect(hex4(null), isNull);
    });
  });

  group('USB anahtarları', () {
    test('tek cihaz: seri olsa da olmasa da :1 (izin sonrası değişmez)', () {
      expect(usbAnahtarlari([(vid: '04b8', pid: '0202', seri: null, sira: '/dev/bus/usb/001/004')]), ['usb:04b8:0202:1']);
      expect(usbAnahtarlari([(vid: '04b8', pid: '0202', seri: 'X1', sira: '/dev/bus/usb/001/009')]), ['usb:04b8:0202:1']);
    });
    test('aynı iki cihaz: farklı seri varsa seri, yoksa sıra', () {
      expect(
          usbAnahtarlari([
            (vid: '0416', pid: '5011', seri: 'B2', sira: '/b'),
            (vid: '0416', pid: '5011', seri: 'A 1', sira: '/a'),
          ]),
          ['usb:0416:5011:B2', 'usb:0416:5011:A_1']);
      expect(
          usbAnahtarlari([
            (vid: '0416', pid: '5011', seri: null, sira: '/b'),
            (vid: '0416', pid: '5011', seri: null, sira: '/a'),
          ]),
          ['usb:0416:5011:2', 'usb:0416:5011:1']);
    });
  });

  group('iş yönlendirme', () {
    final yerel = {'usb:04b8:0202:1', 'win:EPSON TM-T20'};
    test('ağ yazıcısı', () {
      expect(isYonuBelirle({'ip': '192.168.1.50', 'port': 9100}, yerel).yon, IsYonu.ag);
      expect(isYonuBelirle({'connection': 'network', 'ip': '10.0.0.5'}, yerel).yon, IsYonu.ag);
    });
    test('USB yazıcı bu cihazda', () {
      final y = isYonuBelirle({'connection': 'usb', 'usb_anahtar': 'win:EPSON TM-T20'}, yerel);
      expect(y.yon, IsYonu.usb);
      expect(y.anahtar, 'win:EPSON TM-T20');
    });
    test('USB anahtarı bu cihazda yok → basılmaz', () {
      expect(isYonuBelirle({'connection': 'usb', 'usb_anahtar': 'usb:0519:0003:1'}, yerel).yon, IsYonu.usbYok);
      expect(isYonuBelirle({'connection': 'usb'}, yerel).yon, IsYonu.usbYok);
    });
    test('adres yok', () {
      expect(isYonuBelirle(null, yerel).yon, IsYonu.eksik);
      expect(isYonuBelirle({'connection': 'network'}, yerel).yon, IsYonu.eksik);
    });
  });

  test('Android ham listesi', () {
    final l = androidCihazlari([
      {'ad': '/dev/bus/usb/001/004', 'vid': 0x04b8, 'pid': 0x0202, 'urun': 'TM-T20II', 'uretici': 'EPSON', 'siniflar': [0, 7], 'izin': false, 'bulkOut': true},
      {'ad': '/dev/bus/usb/001/002', 'vid': 0x1d6b, 'pid': 0x0002, 'siniflar': [9, 9], 'izin': true, 'bulkOut': false},
      {'ad': '/dev/bus/usb/001/005', 'vid': 0x0b00, 'pid': 0x0084, 'urun': 'iCT250', 'siniflar': [2, 10], 'izin': true, 'bulkOut': true},
    ]);
    expect(l.map((c) => c.anahtar), ['usb:04b8:0202:1', 'usb:0b00:0084:1']);
    expect(l[0].tur, 'yazici');
    expect(l[0].izinGerekli, isTrue);
    expect(l[0].yazdirilabilir, isTrue);
    expect(l[1].tur, 'pos');
    expect(l[1].uretici, 'Ingenico');
    expect(l[0].sunucuyaJson(), containsPair('platform', 'android'));
    expect(l[0].sunucuyaJson(), containsPair('baglanti', 'usb'));
  });

  group('Windows', () {
    test('USB portu', () {
      expect(windowsUsbPortMu('USB001'), isTrue);
      expect(windowsUsbPortMu('TMUSB002'), isTrue);
      expect(windowsUsbPortMu('ESDPRT001'), isTrue);
      expect(windowsUsbPortMu('PORTPROMPT:'), isFalse);
      expect(windowsUsbPortMu('192.168.1.50'), isFalse);
    });

    test('kuyruktaki USB yazıcı + COM portlu kart POS + sürücüsüz yazıcı', () {
      final l = windowsCihazlari(
        yazicilar: [
          (ad: 'POS-80', port: 'USB001', surucu: 'POS-80 Printer'),
          (ad: 'Microsoft Print to PDF', port: 'PORTPROMPT:', surucu: 'Microsoft Print To PDF'),
        ],
        aygitlar: [
          (id: r'USB\VID_0416&PID_5011\5&1A2B&0&1', sinif: 'USB', ad: 'USB Printing Support', uretici: '(Standard USB Host Controller)', uyumlu: [r'USB\Class_07&SubClass_01']),
          (id: r'USB\VID_0B00&PID_0084\12345678', sinif: 'Ports', ad: 'Ingenico iCT250 (COM5)', uretici: 'Ingenico', uyumlu: const []),
          (id: r'USB\VID_04B8&PID_0E15\5&AA&0&3', sinif: 'USB', ad: 'USB Printing Support', uretici: 'Microsoft', uyumlu: [r'USB\Class_07&SubClass_01&Prot_02']),
          (id: r'USB\VID_046D&PID_C077\5&BB&0&4', sinif: 'HIDClass', ad: 'USB Input Device', uretici: '(Standard system devices)', uyumlu: const []),
        ],
        portlar: {r'USB\VID_0416&PID_5011\5&1A2B&0&1': 'USB001', r'USB\VID_04B8&PID_0E15\5&AA&0&3': 'USB002'},
      );
      final k = {for (final c in l) c.anahtar: c};
      expect(k.keys.toSet(), {'win:POS-80', 'usb:0b00:0084:1', 'usb:04b8:0e15:1'});
      expect(k['win:POS-80']!.vidPid, '0416:5011');
      expect(k['win:POS-80']!.yazdirilabilir, isTrue);
      expect(k['usb:0b00:0084:1']!.tur, 'pos');
      expect(k['usb:0b00:0084:1']!.osAd, 'COM5');
      expect(k['usb:0b00:0084:1']!.ad, 'Ingenico iCT250 (COM5)');
      expect(k['usb:04b8:0e15:1']!.ipucu, 'Windows sürücüsü yok');
      expect(k['usb:04b8:0e15:1']!.yazdirilabilir, isFalse);
    });

    test('isimsiz USB seri cihaz bilinmiyor olarak bildirilir; fare bildirilmez', () {
      final l = windowsCihazlari(yazicilar: const [], portlar: const {}, aygitlar: [
        (id: r'USB\VID_2341&PID_0043\7543', sinif: 'Ports', ad: 'USB Serial Device (COM3)', uretici: 'Microsoft', uyumlu: const []),
      ]);
      expect(l.single.tur, 'bilinmiyor');
      expect(l.single.osAd, 'COM3');
    });
  });

  group('macOS', () {
    test('lpstat -v', () {
      final l = macKuyruklari('device for EPSON_TM_T20: usb://EPSON/TM-T20?serial=123\ndevice for Ofis: ipp://10.0.0.4/ipp/print\n');
      expect(l.single.anahtar, 'mac:EPSON_TM_T20');
      expect(l.single.uretici, 'EPSON');
      expect(l.single.ad, 'EPSON TM T20');
    });
    test('system_profiler yalnız POS bildirir', () {
      final l = macProfilCihazlari(
          '{"SPUSBDataType":[{"_items":[{"_name":"iCT250","vendor_id":"0x0b00  (Ingenico)","product_id":"0x0084","serial_num":"9"},{"_name":"Mouse","vendor_id":"0x046d","product_id":"0xc077"}]}]}');
      expect(l.single.tur, 'pos');
      expect(l.single.anahtar, 'usb:0b00:0084:1');
      expect(l.single.uretici, 'Ingenico');
    });
  });

  test('deneme fişi ESC/POS', () {
    final b = usbTestFisi('Mutfak Yazıcısı', zaman: DateTime(2026, 10, 27, 9, 5));
    expect(b.sublist(0, 2), [0x1b, 0x40]);
    expect(b.sublist(b.length - 4), [0x1d, 0x56, 0x42, 0x00]);
    expect(String.fromCharCodes(b), contains('Mutfak Yazicisi'));
    expect(String.fromCharCodes(b), contains('27.10.2026 09:05'));
    expect(b.every((x) => x < 128), isTrue);
  });

  group('konsoldaki kart POS (ethernet / usb)', () {
    final inpos = {
      'id': 11,
      'marka': 'inPos',
      'model': 'M530',
      'seri_no': 'SD0024139263',
      'baglanti': 'ethernet',
      'ip': '192.168.1.2',
      'port': 59000,
      'zaman_asimi_ms': 10000,
    };
    test('ad, bağlantı, adres, süre', () {
      expect(posCihazAdi(inpos), 'inPos - M530');
      expect(posCihazAdi({...inpos, 'ad': 'Kasa POS'}), 'Kasa POS');
      expect(posCihazAdi({'banka': 'Garanti BBVA'}), 'Garanti BBVA');
      expect(posBaglanti(inpos), 'ethernet');
      expect(posAdres(inpos), (ip: '192.168.1.2', port: 59000));
      expect(posAdres({...inpos, 'baglanti': 'usb'}), isNull);
      expect(posAdres({'id': 1}), isNull); // eski kayıt: değişiklik yok
      expect(posDenetimSuresi(10000), const Duration(seconds: 3));
      expect(posDenetimSuresi(1200), const Duration(milliseconds: 1200));
      expect(posDenetimSuresi(null), const Duration(seconds: 3));
    });

    test('TCP denetimi: bağlanır / reddedilir / zaman aşımı', () async {
      final soket = _SahteSoket();
      String? hedef;
      expect(
          await posTcpErisilebilir('192.168.1.2', 59000, const Duration(seconds: 1), baglan: (ip, port, _) async {
            hedef = '$ip:$port';
            return soket;
          }),
          isTrue);
      expect(hedef, '192.168.1.2:59000');
      expect(soket.kapandi, isTrue);
      expect(
          await posTcpErisilebilir('192.168.1.2', 59000, const Duration(seconds: 1),
              baglan: (_, __, ___) async => throw const SocketException('Connection refused')),
          isFalse);
      expect(
          await posTcpErisilebilir('192.168.1.2', 59000, const Duration(milliseconds: 50), baglan: (_, __, ___) => Completer<Socket>().future),
          isFalse);
    });

    test('önbellek: aynı anda tek deneme, sonuç saklanır', () async {
      var deneme = 0;
      final o = PosErisimOnbellegi(baglan: (_, __, ___) async {
        deneme++;
        throw const SocketException('yok');
      });
      expect(o.durum('192.168.1.2', 59000), isNull);
      final a = o.denetle('192.168.1.2', 59000, const Duration(seconds: 1));
      final b = o.denetle('192.168.1.2', 59000, const Duration(seconds: 1));
      expect(await a, isFalse);
      expect(await b, isFalse);
      expect(deneme, 1);
      expect(o.durum('192.168.1.2', 59000), isFalse);
      expect(o.tazeMi('192.168.1.2', 59000), isTrue);
    });
  });

  group('USB şeridi (1.2.22)', () {
    late YazdirmaAjani a;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      a = YazdirmaAjani(Api.bellekte(_BosSunucu()), 'test');
    });

    test('tanımlı kuyruğun aynı vid:pid ham aygıtı yeniden önerilmez', () {
      a.usbCihazlar = [
        _cihaz('win:EPSON TM-T20', 'yazici', vid: '04b8', pid: '0202'),
        _cihaz('usb:04b8:0202:1', 'yazici', vid: '04b8', pid: '0202'),
        _cihaz('usb:0b00:0084:1', 'pos', vid: '0b00', pid: '0084'),
      ];
      a.usbTanimli = {'win:EPSON TM-T20'};
      expect(a.usbYeniCihaz?.anahtar, 'usb:0b00:0084:1');
    });

    test('sunucudaki usb_gizli ve yerel eklenen kimlik şeritte çıkmaz', () {
      a.usbCihazlar = [_cihaz('usb:0b00:0084:1', 'pos', vid: '0b00', pid: '0084')];
      a.usbGizliSunucu = {'usb:0b00:0084:1'};
      expect(a.usbYeniCihaz, isNull);
      a.usbGizliSunucu = {};
      // Anahtar metni değişse de (ör. :1 → seri) vid:pid kimliği eşleşir.
      a.usbYerelTanimli = {'vp:0b00:0084'};
      a.usbCihazlar = [_cihaz('usb:0b00:0084:SN42', 'pos', vid: '0b00', pid: '0084')];
      expect(a.usbYeniCihaz, isNull);
    });

    test('Bunu gösterme → gizli (sunucu yoksa da), Göster → geri gelir', () async {
      final c = _cihaz('win:XP-80C', 'yazici');
      a.usbCihazlar = [c];
      expect(a.usbYeniCihaz, isNotNull);
      await a.usbGizle(c);
      expect(a.usbYeniCihaz, isNull);
      expect(a.usbGizliMi(c), isTrue);
      final p = await SharedPreferences.getInstance();
      expect(p.getStringList('usb_gizlenen'), contains('win:XP-80C'));
      await a.usbGizle(c, gizli: false);
      expect(a.usbGizliMi(c), isFalse);
      expect(a.usbYeniCihaz?.anahtar, 'win:XP-80C');
    });
  });
}
