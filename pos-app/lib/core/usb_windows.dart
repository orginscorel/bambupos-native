import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'usb.dart';

/// Windows: USB yazıcılar yazdırma kuyruğundan (winspool, portu USB00x),
/// sürücüsü kurulmamış yazıcılar ve kart POS cihazları (çoğu sanal COM
/// portu) SetupAPI'den okunur. Hepsi dart:ffi ile, AYRI ISOLATE'TE: alt
/// süreç / PowerShell penceresi açılmaz, arayüz takılmaz. İşlevlerin hepsi
/// Windows 7'de de var (çalışma anında yüklenir, içe aktarma tablosuna girmez).
///
/// Yazdırma: OpenPrinter → StartDocPrinter(RAW) → WritePrinter. Bilgisayardaki
/// Node ajanı 'os' bağlantılı işleri basar; bu uygulama yalnız kendi
/// ajanına yönlenen 'usb' işlerini alır — çakışma olmaz.
class WindowsUsb extends UsbKaynak {
  @override
  bool get destekli => true;
  @override
  String get platform => 'windows';

  List<String> _sistemYazicilari = const [];

  @override
  List<String> get sistemYazicilari => _sistemYazicilari;

  @override
  Future<List<UsbCihaz>> listele({bool zorla = false}) async {
    final t = await Isolate.run(_winTara).timeout(const Duration(seconds: 20));
    _sistemYazicilari = [for (final y in t.yazicilar) '${y.ad} · ${y.port.isEmpty ? 'port yok' : y.port}'];
    return windowsCihazlari(yazicilar: t.yazicilar, aygitlar: t.aygitlar, portlar: t.portlar);
  }

  @override
  Future<void> yaz(UsbCihaz c, Uint8List bayt, {int kopya = 1}) async {
    final ad = c.yerel;
    if (ad == null || !c.yazdirilabilir) {
      throw UsbHata(c.ipucu ?? 'Bu USB cihazına doğrudan yazdırılamıyor');
    }
    final hata = await Isolate.run(() => _winYaz(ad, bayt, kopya)).timeout(const Duration(seconds: 30));
    if (hata != null) throw UsbHata(hata);
  }
}

typedef WinYazici = ({String ad, String port, String? surucu});
typedef WinAygit = ({String id, String? sinif, String? ad, String? uretici, List<String> uyumlu});

/// Yazdırma kuyruğundaki yazıcının portu USB mi? (USB001, TMUSB001, ESDPRT001 …)
bool windowsUsbPortMu(String port) {
  final u = port.toUpperCase();
  return u.contains('USB') || u.startsWith('ESDPRT');
}

final _vidPid = RegExp(r'VID_([0-9A-F]{4})[&+]PID_([0-9A-F]{4})', caseSensitive: false);
final _com = RegExp(r'\((COM\d+)\)', caseSensitive: false);

/// Windows'un genel adları (cihazın gerçek adı değil).
bool _genelAd(String? s) {
  final l = (s ?? '').toLowerCase();
  return l.isEmpty ||
      l.startsWith('usb composite') ||
      l.startsWith('usb printing support') ||
      l.startsWith('usb input device') ||
      l.startsWith('usb serial converter') ||
      l.startsWith('generic usb') ||
      l.contains('usb-hid');
}

bool _genelUretici(String? s) {
  final l = (s ?? '').toLowerCase();
  return l.isEmpty || l.startsWith('(standard') || l.startsWith('(standart') || l == 'microsoft' || l.startsWith('compatible');
}

String? _surucuUreticisi(String? surucu) {
  final ilk = (surucu ?? '').trim().split(RegExp(r'\s+')).first;
  if (ilk.isEmpty || const {'generic', 'microsoft', 'ms', 'usb'}.contains(ilk.toLowerCase())) return null;
  return ilk;
}

/// Kuyruk + SetupAPI + port eşlemesinden cihaz listesi (saf; birim testli).
///
/// [portlar]: aygıt kimliği (büyük harf) → USB00x (usbprint arayüz kaydından).
List<UsbCihaz> windowsCihazlari({
  required List<WinYazici> yazicilar,
  required List<WinAygit> aygitlar,
  required Map<String, String> portlar,
}) {
  final sonuc = <UsbCihaz>[];
  final usbYazicilar = yazicilar.where((y) => windowsUsbPortMu(y.port)).toList();
  final kuyrukPortlari = {for (final y in usbYazicilar) y.port.toUpperCase()};

  // Port → vid/pid (kuyruktaki yazıcıya kimlik eklemek için).
  final portKimlik = <String, (String, String)>{};
  portlar.forEach((id, port) {
    final m = _vidPid.firstMatch(id);
    if (m != null) portKimlik[port.toUpperCase()] = (m.group(1)!.toLowerCase(), m.group(2)!.toLowerCase());
  });

  for (final y in usbYazicilar) {
    final k = portKimlik[y.port.toUpperCase()];
    sonuc.add(UsbCihaz(
      anahtar: 'win:${y.ad}',
      tur: 'yazici',
      ad: y.ad,
      platform: 'windows',
      uretici: (k != null ? usbYaziciUreticileri[k.$1] : null) ?? _surucuUreticisi(y.surucu),
      vid: k?.$1,
      pid: k?.$2,
      osAd: y.port,
      yerel: y.ad,
      yazdirilabilir: true,
    ));
  }

  // Aygıtları vid:pid'e göre topla (bileşik aygıtın MI_xx çocukları, FTDI COM portu aynı grupta).
  final gruplar = <String, List<WinAygit>>{};
  for (final a in aygitlar) {
    final m = _vidPid.firstMatch(a.id);
    if (m == null) continue;
    gruplar.putIfAbsent('${m.group(1)!.toLowerCase()}:${m.group(2)!.toLowerCase()}', () => []).add(a);
  }

  final adaylar = <({String vid, String pid, String? seri, String sira, String tur, String ad, String? uretici, String? com, String? ipucu})>[];
  gruplar.forEach((vp, dugumler) {
    final vid = vp.substring(0, 4), pid = vp.substring(5);
    final siniflar = <int>{
      for (final d in dugumler)
        for (final u in d.uyumlu)
          if (u.toUpperCase().contains('CLASS_07')) 7,
    };
    final pnp = {for (final d in dugumler) (d.sinif ?? '').toLowerCase()};
    final comlar = [
      for (final d in dugumler)
        if ((d.sinif ?? '').toLowerCase() == 'ports')
          if (_com.firstMatch(d.ad ?? '') case final m?) m.group(1)!.toUpperCase(),
    ];
    final adlar = [for (final d in dugumler) d.ad ?? ''].where((s) => s.isNotEmpty).toList();
    final ureticiler = [for (final d in dugumler) d.uretici].where((s) => !_genelUretici(s)).cast<String>().toList();
    final tur = usbTurBelirle(
      vid: vid,
      pid: pid,
      siniflar: siniflar,
      ad: adlar.join(' '),
      uretici: ureticiler.join(' '),
      pnpSinifi: pnp.contains('printer') ? 'Printer' : null,
    );

    String? ipucu;
    if (tur == 'yazici') {
      // Kuyrukta bu aygıtın portunu kullanan yazıcı varsa yukarıda zaten listelendi.
      final aygitPortlari = [
        for (final d in dugumler)
          if (portlar[d.id.toUpperCase()] case final p?) p.toUpperCase(),
      ];
      if (aygitPortlari.any(kuyrukPortlari.contains)) return;
      // Port eşlemesi okunamadıysa (kayıt defteri) ve kuyrukta USB yazıcı varsa ayırt edilemez: atla.
      if (portlar.isEmpty && usbYazicilar.isNotEmpty) return;
      ipucu = 'Windows sürücüsü yok';
    } else if (tur == 'bilinmiyor' && comlar.isEmpty) {
      return; // fare, klavye, bellek, hub …
    }

    // Fiziksel cihazlar: USB\ düğümleri (MI_xx arayüz çocukları hariç).
    var ebeveyn = dugumler.where((d) => d.id.toUpperCase().startsWith(r'USB\') && !d.id.toUpperCase().contains('&MI_')).toList();
    if (ebeveyn.isEmpty) ebeveyn = [dugumler.first];
    final adOnce = [
      for (final d in dugumler)
        if ((d.sinif ?? '').toLowerCase() == 'ports' && !_genelAd(d.ad)) d.ad!,
      for (final d in dugumler)
        if (!_genelAd(d.ad)) d.ad!,
    ];
    final ad = adOnce.isNotEmpty
        ? adOnce.first.replaceAll(_com, '').trim()
        : (tur == 'pos' ? 'USB kart POS' : (tur == 'yazici' ? 'USB yazıcı' : 'USB seri cihaz'));
    final uretici = ureticiler.isNotEmpty ? ureticiler.first : (usbYaziciUreticileri[vid] ?? usbPosUreticileri[vid]);
    for (var i = 0; i < ebeveyn.length; i++) {
      final son = ebeveyn[i].id.split(r'\').last;
      adaylar.add((
        vid: vid,
        pid: pid,
        seri: son.contains('&') || son.isEmpty ? null : son,
        sira: ebeveyn[i].id.toUpperCase(),
        tur: tur,
        ad: ad,
        uretici: uretici,
        com: comlar.length == ebeveyn.length ? comlar[i] : (ebeveyn.length == 1 && comlar.isNotEmpty ? comlar.first : null),
        ipucu: ipucu,
      ));
    }
  });

  final anahtarlar = usbAnahtarlari([for (final a in adaylar) (vid: a.vid, pid: a.pid, seri: a.seri, sira: a.sira)]);
  for (var i = 0; i < adaylar.length; i++) {
    final a = adaylar[i];
    sonuc.add(UsbCihaz(
      anahtar: anahtarlar[i],
      tur: a.tur,
      ad: a.com != null ? '${a.ad} (${a.com})' : a.ad,
      platform: 'windows',
      uretici: a.uretici,
      vid: a.vid,
      pid: a.pid,
      seri: a.seri,
      osAd: a.com,
      ipucu: a.ipucu,
    ));
  }
  return sonuc;
}

/* ═══════════════ dart:ffi (yalnız ayrı isolate içinde çağrılır) ═══════════════ */

final class _PrinterInfo2 extends Struct {
  external Pointer<Utf16> pServerName;
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pShareName;
  external Pointer<Utf16> pPortName;
  external Pointer<Utf16> pDriverName;
  external Pointer<Utf16> pComment;
  external Pointer<Utf16> pLocation;
  external Pointer<Void> pDevMode;
  external Pointer<Utf16> pSepFile;
  external Pointer<Utf16> pPrintProcessor;
  external Pointer<Utf16> pDatatype;
  external Pointer<Utf16> pParameters;
  external Pointer<Void> pSecurityDescriptor;
  @Uint32()
  external int attributes;
  @Uint32()
  external int priority;
  @Uint32()
  external int defaultPriority;
  @Uint32()
  external int startTime;
  @Uint32()
  external int untilTime;
  @Uint32()
  external int status;
  @Uint32()
  external int cJobs;
  @Uint32()
  external int averagePpm;
}

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

final class _SpDevinfoData extends Struct {
  @Uint32()
  external int cbSize;
  @Array(16)
  external Array<Uint8> classGuid;
  @Uint32()
  external int devInst;
  @IntPtr()
  external int reserved;
}

String? _metin(Pointer<Utf16> p) => p == nullptr ? null : p.toDartString();

({List<WinYazici> yazicilar, List<WinAygit> aygitlar, Map<String, String> portlar}) _winTara() {
  var yazicilar = <WinYazici>[];
  var aygitlar = <WinAygit>[];
  var portlar = <String, String>{};
  try {
    yazicilar = _kuyruk();
  } catch (_) {}
  try {
    aygitlar = [..._setupApi('USB'), ..._setupApi('FTDIBUS')];
  } catch (_) {}
  try {
    portlar = _usbprintPortlari();
  } catch (_) {}
  return (yazicilar: yazicilar, aygitlar: aygitlar, portlar: portlar);
}

List<WinYazici> _kuyruk() {
  final ws = DynamicLibrary.open('winspool.drv');
  final enumPrinters = ws.lookupFunction<
      Int32 Function(Uint32, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>)>('EnumPrintersW');
  const yerel = 0x2; // PRINTER_ENUM_LOCAL
  final gerek = calloc<Uint32>();
  final adet = calloc<Uint32>();
  Pointer<Uint8> tampon = nullptr;
  try {
    enumPrinters(yerel, nullptr, 2, nullptr, 0, gerek, adet);
    if (gerek.value == 0) return const [];
    tampon = calloc<Uint8>(gerek.value);
    if (enumPrinters(yerel, nullptr, 2, tampon, gerek.value, gerek, adet) == 0) return const [];
    final dizi = tampon.cast<_PrinterInfo2>();
    return [
      for (var i = 0; i < adet.value; i++)
        if (_metin(dizi[i].pPrinterName) case final ad?)
          (ad: ad, port: _metin(dizi[i].pPortName) ?? '', surucu: _metin(dizi[i].pDriverName)),
    ];
  } finally {
    calloc.free(gerek);
    calloc.free(adet);
    if (tampon != nullptr) calloc.free(tampon);
  }
}

List<WinAygit> _setupApi(String numaralandirici) {
  final sa = DynamicLibrary.open('setupapi.dll');
  final getClassDevs = sa.lookupFunction<IntPtr Function(Pointer<Void>, Pointer<Utf16>, IntPtr, Uint32),
      int Function(Pointer<Void>, Pointer<Utf16>, int, int)>('SetupDiGetClassDevsW');
  final enumInfo = sa.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<_SpDevinfoData>),
      int Function(int, int, Pointer<_SpDevinfoData>)>('SetupDiEnumDeviceInfo');
  final instanceId = sa.lookupFunction<Int32 Function(IntPtr, Pointer<_SpDevinfoData>, Pointer<Utf16>, Uint32, Pointer<Uint32>),
      int Function(int, Pointer<_SpDevinfoData>, Pointer<Utf16>, int, Pointer<Uint32>)>('SetupDiGetDeviceInstanceIdW');
  final ozellik = sa.lookupFunction<
      Int32 Function(IntPtr, Pointer<_SpDevinfoData>, Uint32, Pointer<Uint32>, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(int, Pointer<_SpDevinfoData>, int, Pointer<Uint32>, Pointer<Uint8>, int, Pointer<Uint32>)>(
      'SetupDiGetDeviceRegistryPropertyW');
  final yokEt = sa.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetupDiDestroyDeviceInfoList');

  final enumAd = numaralandirici.toNativeUtf16();
  // DIGCF_PRESENT | DIGCF_ALLCLASSES: yalnız şu an takılı olanlar.
  final h = getClassDevs(nullptr, enumAd, 0, 0x2 | 0x4);
  calloc.free(enumAd);
  if (h == -1 || h == 0) return const [];
  const tamponBoyu = 2048;
  final veri = calloc<_SpDevinfoData>();
  final tampon = calloc<Uint8>(tamponBoyu);
  final gerek = calloc<Uint32>();
  final sonuc = <WinAygit>[];
  try {
    for (var i = 0; i < 512; i++) {
      veri.ref.cbSize = sizeOf<_SpDevinfoData>();
      if (enumInfo(h, i, veri) == 0) break;
      if (instanceId(h, veri, tampon.cast(), tamponBoyu ~/ 2, gerek) == 0) continue;
      final id = tampon.cast<Utf16>().toDartString();
      String? sz(int p) {
        for (var k = 0; k < tamponBoyu; k++) {
          tampon[k] = 0;
        }
        if (ozellik(h, veri, p, nullptr, tampon, tamponBoyu - 4, gerek) == 0) return null;
        final s = tampon.cast<Utf16>().toDartString().trim();
        return s.isEmpty ? null : s;
      }

      List<String> coklu(int p) {
        for (var k = 0; k < tamponBoyu; k++) {
          tampon[k] = 0;
        }
        if (ozellik(h, veri, p, nullptr, tampon, tamponBoyu - 4, gerek) == 0) return const [];
        // REG_MULTI_SZ: \0 ile ayrılmış, \0\0 ile biten.
        final u = tampon.cast<Uint16>();
        final l = <String>[];
        var bas = 0;
        for (var k = 0; k < tamponBoyu ~/ 2 - 2; k++) {
          if (u[k] == 0) {
            if (k == bas) break;
            l.add(String.fromCharCodes(u.asTypedList(k).sublist(bas)));
            bas = k + 1;
          }
        }
        return l;
      }

      sonuc.add((
        id: id,
        sinif: sz(0x7), // SPDRP_CLASS
        ad: sz(0xC) ?? sz(0x0), // SPDRP_FRIENDLYNAME, SPDRP_DEVICEDESC
        uretici: sz(0xB), // SPDRP_MFG
        uyumlu: coklu(0x2), // SPDRP_COMPATIBLEIDS
      ));
    }
  } finally {
    yokEt(h);
    calloc.free(veri);
    calloc.free(tampon);
    calloc.free(gerek);
  }
  return sonuc;
}

/// usbprint arayüz kayıtları: aygıt kimliği → USB00x portu.
/// HKLM\SYSTEM\CurrentControlSet\Control\DeviceClasses\{28d78fad-…}\##?#USB#VID_…#…#{…}\#\Device Parameters
Map<String, String> _usbprintPortlari() {
  final adv = DynamicLibrary.open('advapi32.dll');
  final ac = adv.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
      int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>)>('RegOpenKeyExW');
  final altAnahtar = adv.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Pointer<Uint32>, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(int, int, Pointer<Utf16>, Pointer<Uint32>, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>)>('RegEnumKeyExW');
  final degerAl = adv.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>)>('RegGetValueW');
  final kapat = adv.lookupFunction<Int32 Function(IntPtr), int Function(int)>('RegCloseKey');

  // HKEY_LOCAL_MACHINE = (HKEY)(ULONG_PTR)(LONG)0x80000002 → işaret genişletilmiş.
  const hklm = 0x80000002 - 0x100000000;
  const guid = '{28d78fad-5a12-11d1-ae5b-0000f803a8c2}';
  final yol = 'SYSTEM\\CurrentControlSet\\Control\\DeviceClasses\\$guid'.toNativeUtf16();
  final anahtar = calloc<IntPtr>();
  final ad = calloc<Uint16>(512);
  final adBoyu = calloc<Uint32>();
  final dword = calloc<Uint32>();
  final metin = calloc<Uint16>(64);
  final boy = calloc<Uint32>();
  final portDeger = 'Port Number'.toNativeUtf16();
  final tabanDeger = 'Base Name'.toNativeUtf16();
  final sonuc = <String, String>{};
  try {
    if (ac(hklm, yol, 0, 0x20019 /* KEY_READ */, anahtar) != 0) return sonuc;
    final h = anahtar.value;
    try {
      for (var i = 0; i < 256; i++) {
        adBoyu.value = 512;
        if (altAnahtar(h, i, ad.cast(), adBoyu, nullptr, nullptr, nullptr, nullptr) != 0) break;
        final alt = ad.cast<Utf16>().toDartString();
        final altYol = '$alt\\#\\Device Parameters'.toNativeUtf16();
        try {
          boy.value = 4;
          if (degerAl(h, altYol, portDeger, 0x10 /* RRF_RT_REG_DWORD */, nullptr, dword.cast(), boy) != 0) continue;
          final no = dword.value;
          boy.value = 128;
          final taban = degerAl(h, altYol, tabanDeger, 0x2 /* RRF_RT_REG_SZ */, nullptr, metin.cast(), boy) == 0
              ? metin.cast<Utf16>().toDartString()
              : 'USB';
          // ##?#USB#VID_04B8&PID_0202#5&1a2b&0&1#{guid} → USB\VID_04B8&PID_0202\5&1a2b&0&1
          var kimlik = alt.startsWith('##?#') ? alt.substring(4) : alt;
          final kes = kimlik.lastIndexOf('#{');
          if (kes > 0) kimlik = kimlik.substring(0, kes);
          sonuc[kimlik.replaceAll('#', r'\').toUpperCase()] = '$taban${no.toString().padLeft(3, '0')}';
        } finally {
          calloc.free(altYol);
        }
      }
    } finally {
      kapat(h);
    }
  } finally {
    for (final p in [yol, anahtar, ad, adBoyu, dword, metin, boy, portDeger, tabanDeger]) {
      calloc.free(p);
    }
  }
  return sonuc;
}

/// Ham baytı yazdırma kuyruğuna RAW olarak gönderir. Hata metni ya da null.
String? _winYaz(String yazici, Uint8List bayt, int kopya) {
  final ws = DynamicLibrary.open('winspool.drv');
  final openPrinter = ws.lookupFunction<Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
      int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>('OpenPrinterW');
  final startDoc = ws.lookupFunction<Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>), int Function(int, int, Pointer<_DocInfo1>)>(
      'StartDocPrinterW');
  final startPage = ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('StartPagePrinter');
  final writePrinter = ws.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>)>('WritePrinter');
  final endPage = ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndPagePrinter');
  final endDoc = ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('EndDocPrinter');
  final closePrinter = ws.lookupFunction<Int32 Function(IntPtr), int Function(int)>('ClosePrinter');

  final ad = yazici.toNativeUtf16();
  final tutamac = calloc<IntPtr>();
  final belge = calloc<_DocInfo1>();
  final belgeAdi = 'BamBumPOS fiş'.toNativeUtf16();
  final tur = 'RAW'.toNativeUtf16();
  final veri = calloc<Uint8>(bayt.isEmpty ? 1 : bayt.length);
  final yazilan = calloc<Uint32>();
  try {
    if (openPrinter(ad, tutamac, nullptr) == 0) return 'USB yazıcı bulunamadı ($yazici)';
    final h = tutamac.value;
    try {
      belge.ref
        ..pDocName = belgeAdi
        ..pOutputFile = nullptr
        ..pDatatype = tur;
      if (startDoc(h, 1, belge) == 0) return 'Yazdırma işi başlatılamadı ($yazici)';
      try {
        veri.asTypedList(bayt.length).setAll(0, bayt);
        for (var k = 0; k < kopya.clamp(1, 5); k++) {
          if (startPage(h) == 0) return 'Yazdırma sayfası açılamadı';
          var ofset = 0;
          while (ofset < bayt.length) {
            if (writePrinter(h, veri + ofset, bayt.length - ofset, yazilan) == 0 || yazilan.value == 0) {
              endPage(h);
              return 'USB yazıcıya gönderilemedi (bağlı ve açık mı?)';
            }
            ofset += yazilan.value;
          }
          endPage(h);
        }
      } finally {
        endDoc(h);
      }
    } finally {
      closePrinter(h);
    }
    return null;
  } finally {
    for (final p in [ad, tutamac, belge, belgeAdi, tur, veri, yazilan]) {
      calloc.free(p);
    }
  }
}
