import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'usb_android.dart';
import 'usb_macos.dart';
import 'usb_windows.dart';

/// USB'YE BAĞLI CİHAZLAR (2026-10-27 işletme isteği): ağı olmayan
/// noktalarda fiş / mutfak yazıcısı ve kart POS cihazı doğrudan USB ile
/// takılı. Uygulama bunları bulur, sunucuya bildirir (İşletme Yönetimi'nde
/// görünür), personel uygulamadan "ekle" der ve USB yazıcıya giden fişleri
/// bu cihaz basar.
///
/// Platformlar: Android (UsbManager, MainActivity → UsbKopru.kt), Windows
/// (yazdırma kuyruğu + SetupAPI, dart:ffi), macOS (CUPS + system_profiler).
/// iOS'ta USB ana makine desteği yok.

/// Bir USB cihazı (sunucuya giden kayıt + yerel hedef).
class UsbCihaz {
  const UsbCihaz({
    required this.anahtar,
    required this.tur,
    required this.ad,
    required this.platform,
    this.uretici,
    this.vid,
    this.pid,
    this.seri,
    this.osAd,
    this.yerel,
    this.izinGerekli = false,
    this.yazdirilabilir = false,
    this.ipucu,
  });

  /// Sabit anahtar: `usb:<vid>:<pid>:<seri|sıra>`, `win:<kuyruk>`, `mac:<kuyruk>`.
  final String anahtar;

  /// yazici | pos | bilinmiyor
  final String tur;
  final String ad;
  final String platform;
  final String? uretici;
  final String? vid;
  final String? pid;
  final String? seri;

  /// İşletim sistemindeki ad (Windows: port / COM, macOS: CUPS kuyruğu).
  final String? osAd;

  /// Platformun yazdırma hedefi (Android aygıt yolu, Windows/macOS kuyruk adı).
  final String? yerel;

  /// Android: kullanıcı henüz USB izni vermedi.
  final bool izinGerekli;

  /// Ham ESC/POS bu cihaza gönderilebilir mi?
  final bool yazdirilabilir;

  /// Ekranda ve sunucuda gösterilecek kısa not (ör. "Windows sürücüsü yok").
  final String? ipucu;

  String? get vidPid => vid == null || pid == null ? null : '$vid:$pid';

  Map<String, dynamic> sunucuyaJson() => {
        'baglanti': 'usb',
        'anahtar': anahtar,
        'tur': tur,
        'ad': ad,
        'uretici': uretici,
        'vid': vid,
        'pid': pid,
        'seri': seri,
        'os_ad': osAd,
        'platform': platform,
        'ipucu': ?ipucu,
      };

  UsbCihaz kopya({bool? izinGerekli}) => UsbCihaz(
        anahtar: anahtar,
        tur: tur,
        ad: ad,
        platform: platform,
        uretici: uretici,
        vid: vid,
        pid: pid,
        seri: seri,
        osAd: osAd,
        yerel: yerel,
        izinGerekli: izinGerekli ?? this.izinGerekli,
        yazdirilabilir: yazdirilabilir,
        ipucu: ipucu,
      );
}

/// Kullanıcıya gösterilecek USB hatası.
class UsbHata implements Exception {
  const UsbHata(this.mesaj);
  final String mesaj;
  @override
  String toString() => mesaj;
}

/* ───────── Sınıflandırma ───────── */

/// Yalnız fiş/etiket yazıcısı üreten firmalar (USB-IF vendor id, küçük harf).
const usbYaziciUreticileri = {
  '04b8': 'Epson',
  '0519': 'Star Micronics',
  '1504': 'Bixolon',
  '1d90': 'Citizen',
  '0dd4': 'Custom',
  '154f': 'SNBC',
};

/// Genel amaçlı yonga üreticilerinin kimliğini kullanan, yazıcı olduğu
/// bilinen vid:pid çiftleri (yalnız vid'e bakılırsa fare/klavye de yazıcı sanılır).
const usbBilinenYazicilar = {
  '0416:5011', // Winbond yongalı POS-58 / Zjiang yazıcılar
  '0fe6:811e', // ICS yongalı USB fiş yazıcıları
};

/// Kart POS / ÖKC üreticileri (USB-IF vendor id).
const usbPosUreticileri = {
  '0b00': 'Ingenico',
  '11ca': 'Verifone',
  '0ca6': 'Castles',
};

final _posKelime = RegExp(r'\b(ingenico|verifone|pax|castles|hugin|profilo|beko|inpos|pavo|yazarkasa|ökc|okc|eft-?pos)\b');
final _yaziciKelime = RegExp(
    r'(printer|yazıcı|yazici|receipt|thermal|termal|pos-?58|pos-?80|xp-?58|xp-?80|xp-?[nq]\d|tm-[tmlpu]\d|rp-?\d{2}|srp-|tsp\d|ct-s\d|gp-\d|text only)');

/// USB cihazının türünü tahmin eder: `yazici`, `pos` ya da `bilinmiyor`.
///
/// [siniflar]: USB aygıt/arayüz sınıfları (7 = yazıcı). [pnpSinifi]:
/// Windows aygıt sınıfı (Printer, Ports, HIDClass …).
String usbTurBelirle({
  String? vid,
  String? pid,
  Iterable<int> siniflar = const [],
  String? ad,
  String? uretici,
  String? pnpSinifi,
}) {
  final v = vid?.toLowerCase();
  final p = pid?.toLowerCase();
  final metin = '${ad ?? ''} ${uretici ?? ''}'.toLowerCase();
  if (siniflar.contains(7) || pnpSinifi?.toLowerCase() == 'printer') return 'yazici';
  if (_posKelime.hasMatch(metin) || usbPosUreticileri.containsKey(v)) return 'pos';
  if (usbYaziciUreticileri.containsKey(v) || usbBilinenYazicilar.contains('$v:$p')) return 'yazici';
  if (_yaziciKelime.hasMatch(metin)) return 'yazici';
  return 'bilinmiyor';
}

/// Dört haneli küçük harf onaltılık (1208 → '04b8', '0x04B8' → '04b8').
String? hex4(Object? v) {
  if (v == null) return null;
  if (v is int) return v.toRadixString(16).padLeft(4, '0');
  final s = v.toString().trim().toLowerCase();
  final m = RegExp(r'^(?:0x)?([0-9a-f]{1,4})\b').firstMatch(s);
  if (m == null) return null;
  return m.group(1)!.padLeft(4, '0');
}

/// Aynı vid:pid'li cihazlara SABİT anahtar verir.
///
/// Tek cihaz (en sık durum) → `usb:<vid>:<pid>:1`: Android'de seri numarası
/// ancak izin verildikten sonra okunabildiği, ucuz yazıcıların çoğunda hiç
/// olmadığı ve aygıt yolu her takışta değiştiği için anahtar seriye
/// dayandırılmaz; yazıcı kapatılıp açılsa da aynı kalır. Birden çok aynı
/// cihaz varsa ve hepsinin farklı seri numarası varsa seri, yoksa sıra
/// numarası (aygıt yoluna göre) kullanılır.
List<String> usbAnahtarlari(List<({String vid, String pid, String? seri, String sira})> cihazlar) {
  final gruplar = <String, List<int>>{};
  for (var i = 0; i < cihazlar.length; i++) {
    gruplar.putIfAbsent('${cihazlar[i].vid}:${cihazlar[i].pid}', () => []).add(i);
  }
  final sonuc = List<String>.filled(cihazlar.length, '');
  gruplar.forEach((vp, idx) {
    if (idx.length == 1) {
      sonuc[idx.first] = 'usb:$vp:1';
      return;
    }
    final seriler = [for (final i in idx) cihazlar[i].seri?.trim() ?? ''];
    final seriIle = seriler.every((s) => s.isNotEmpty) && seriler.toSet().length == seriler.length;
    final sirali = [...idx]..sort((a, b) => cihazlar[a].sira.compareTo(cihazlar[b].sira));
    for (var k = 0; k < sirali.length; k++) {
      final i = sirali[k];
      sonuc[i] = seriIle ? 'usb:$vp:${_anahtarParcasi(cihazlar[i].seri!)}' : 'usb:$vp:${k + 1}';
    }
  });
  return sonuc;
}

String _anahtarParcasi(String s) => s.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

/* ───────── İş yönlendirme ───────── */

enum IsYonu {
  /// Ağ yazıcısı (TCP 9100 …).
  ag,

  /// Bu cihaza takılı USB yazıcı.
  usb,

  /// USB işi ama anahtar bu cihazda yok → basılmaz, hata onayı.
  usbYok,

  /// Ne ağ adresi ne USB anahtarı.
  eksik,
}

/// Sunucudan gelen işin `printer` alanına göre nereye basılacağı.
({IsYonu yon, String? anahtar}) isYonuBelirle(Map? yazici, Set<String> yerelAnahtarlar) {
  if (yazici == null) return (yon: IsYonu.eksik, anahtar: null);
  if (yazici['connection']?.toString() == 'usb') {
    final a = yazici['usb_anahtar']?.toString() ?? '';
    if (a.isEmpty || !yerelAnahtarlar.contains(a)) return (yon: IsYonu.usbYok, anahtar: a.isEmpty ? null : a);
    return (yon: IsYonu.usb, anahtar: a);
  }
  final ip = yazici['ip']?.toString() ?? '';
  return ip.isEmpty ? (yon: IsYonu.eksik, anahtar: null) : (yon: IsYonu.ag, anahtar: null);
}

/* ───────── Deneme fişi ───────── */

/// Kısa ESC/POS deneme fişi (yalnız ASCII: kod sayfası ayarı gerekmez).
Uint8List usbTestFisi(String ad, {DateTime? zaman}) {
  final t = zaman ?? DateTime.now();
  String iki(int n) => n.toString().padLeft(2, '0');
  String ascii(String s) {
    const tr = {'ç': 'c', 'Ç': 'C', 'ğ': 'g', 'Ğ': 'G', 'ı': 'i', 'İ': 'I', 'ö': 'o', 'Ö': 'O', 'ş': 's', 'Ş': 'S', 'ü': 'u', 'Ü': 'U'};
    return s.split('').map((c) => tr[c] ?? c).where((c) => c.codeUnitAt(0) >= 32 && c.codeUnitAt(0) < 127).join();
  }

  final b = BytesBuilder()
    ..add([0x1b, 0x40]) // ESC @ — sıfırla
    ..add([0x1b, 0x61, 0x01]) // ortala
    ..add([0x1d, 0x21, 0x11]) // çift boy
    ..add(ascii('BamBumPOS\n').codeUnits)
    ..add([0x1d, 0x21, 0x00])
    ..add(ascii('USB yazici testi\n').codeUnits)
    ..add(ascii('${ad.length > 40 ? ad.substring(0, 40) : ad}\n').codeUnits)
    ..add(ascii('${iki(t.day)}.${iki(t.month)}.${t.year} ${iki(t.hour)}:${iki(t.minute)}\n').codeUnits)
    ..add([0x1b, 0x64, 0x04]) // 4 satır besle
    ..add([0x1d, 0x56, 0x42, 0x00]); // kağıdı kes
  return b.toBytes();
}

/* ───────── Platform kaynağı ───────── */

/// Platforma özgü USB erişimi. Bütün ağır işler arka planda (Android'de ayrı
/// iş parçacığı, Windows'ta ayrı isolate, macOS'ta alt süreç).
abstract class UsbKaynak {
  bool get destekli;
  String get platform;

  /// Takılı cihazlar. [zorla]: pahalı ek taramayı da şimdi yap (macOS system_profiler).
  Future<List<UsbCihaz>> listele({bool zorla = false});

  /// Ham baytı cihaza gönderir; başarısızsa [UsbHata].
  Future<void> yaz(UsbCihaz c, Uint8List bayt, {int kopya = 1});

  /// Android: izin penceresi. Diğerlerinde her zaman true.
  Future<bool> izinIste(UsbCihaz c) async => true;

  /// Tanı: işletim sisteminin gördüğü bütün yazıcılar (ad · port). Windows'ta
  /// USB yazıcı bulunamayınca ekranda listelenir.
  List<String> get sistemYazicilari => const [];

  /// Takma / çıkarma olayları (yalnız Android'de anlık).
  Stream<void> get degisti => const Stream.empty();

  void kapat() {}
}

class _Desteksiz extends UsbKaynak {
  @override
  bool get destekli => false;
  @override
  String get platform => Platform.operatingSystem;
  @override
  Future<List<UsbCihaz>> listele({bool zorla = false}) async => const [];
  @override
  Future<void> yaz(UsbCihaz c, Uint8List bayt, {int kopya = 1}) async =>
      throw const UsbHata('Bu cihazda USB yazıcı desteklenmez');
}

UsbKaynak usbKaynagi() {
  if (Platform.isAndroid) return AndroidUsb();
  if (Platform.isWindows) return WindowsUsb();
  if (Platform.isMacOS) return MacUsb();
  return _Desteksiz();
}

/// Alt süreç: zaman aşımında öldürülür; LC_ALL=C (CUPS çıktısı Türkçe olmasın).
Future<String?> surecCalistir(String komut, List<String> argumanlar, {Duration sure = const Duration(seconds: 10)}) async {
  try {
    final p = await Process.start(komut, argumanlar, environment: const {'LC_ALL': 'C', 'LANG': 'C'});
    final cikti = p.stdout.transform(const SystemEncoding().decoder).join();
    unawaited(p.stderr.drain<void>());
    final kod = await p.exitCode.timeout(sure, onTimeout: () {
      p.kill();
      return -1;
    });
    if (kod != 0) return null;
    return await cikti.timeout(const Duration(seconds: 2), onTimeout: () => '');
  } catch (_) {
    return null;
  }
}

/// İmza: liste değişti mi (sunucuya yeniden bildirmek için).
String usbImza(List<UsbCihaz> l) => jsonEncode([for (final c in l) c.sunucuyaJson()]);
