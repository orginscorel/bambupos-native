import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'usb.dart';

/// macOS: USB yazıcılar CUPS kuyruklarından (`lpstat -v` → usb://), kart POS
/// cihazları `system_profiler` USB ağacından (5 dakikada bir; pahalı).
/// Yazdırma: `lp -d <kuyruk> -o raw`. Uygulama sandbox'ta: Release /
/// DebugProfile entitlements'a `com.apple.security.print` eklendi.
class MacUsb extends UsbKaynak {
  @override
  bool get destekli => true;
  @override
  String get platform => 'macos';

  List<UsbCihaz> _profilOnbellek = const [];
  DateTime? _sonProfil;

  @override
  Future<List<UsbCihaz>> listele({bool zorla = false}) async {
    final lp = await surecCalistir('/usr/bin/lpstat', ['-v']);
    final kuyruklar = macKuyruklari(lp ?? '');
    if (zorla || _sonProfil == null || DateTime.now().difference(_sonProfil!) > const Duration(minutes: 5)) {
      _sonProfil = DateTime.now();
      var json = await surecCalistir('/usr/sbin/system_profiler', ['SPUSBDataType', '-json'], sure: const Duration(seconds: 20));
      var l = json == null ? const <UsbCihaz>[] : macProfilCihazlari(json);
      if (l.isEmpty) {
        // macOS 15+: USB ağacı SPUSBHostDataType altında.
        json = await surecCalistir('/usr/sbin/system_profiler', ['SPUSBHostDataType', '-json'], sure: const Duration(seconds: 20));
        if (json != null) l = macProfilCihazlari(json);
      }
      _profilOnbellek = l;
    }
    return [...kuyruklar, ..._profilOnbellek];
  }

  @override
  Future<void> yaz(UsbCihaz c, Uint8List bayt, {int kopya = 1}) async {
    final kuyruk = c.yerel;
    if (kuyruk == null || !c.yazdirilabilir) throw UsbHata(c.ipucu ?? 'Bu USB cihazına doğrudan yazdırılamıyor');
    final Process p;
    try {
      p = await Process.start('/usr/bin/lp', ['-d', kuyruk, '-o', 'raw', '-n', '${kopya.clamp(1, 5)}'],
          environment: const {'LC_ALL': 'C'});
    } catch (_) {
      throw const UsbHata('USB yazıcıya gönderilemedi (yazdırma izni yok)');
    }
    final hata = p.stderr.transform(utf8.decoder).join();
    p.stdout.drain<void>().ignore();
    p.stdin.add(bayt);
    await p.stdin.close();
    final kod = await p.exitCode.timeout(const Duration(seconds: 20), onTimeout: () {
      p.kill();
      return -1;
    });
    if (kod != 0) {
      final m = (await hata.timeout(const Duration(seconds: 1), onTimeout: () => '')).trim();
      throw UsbHata('USB yazıcıya gönderilemedi${m.isEmpty ? '' : ': $m'}');
    }
  }
}

/// `lpstat -v` çıktısından USB kuyrukları.
List<UsbCihaz> macKuyruklari(String cikti) {
  final r = RegExp(r'^device for (.+?):\s+(\S+)\s*$', multiLine: true);
  return [
    for (final m in r.allMatches(cikti))
      if (m.group(2)!.toLowerCase().startsWith('usb://'))
        UsbCihaz(
          anahtar: 'mac:${m.group(1)!}',
          tur: 'yazici',
          ad: m.group(1)!.replaceAll('_', ' '),
          platform: 'macos',
          uretici: () {
            final u = Uri.decodeComponent(m.group(2)!.substring(6).split('/').first).trim();
            return u.isEmpty ? null : u;
          }(),
          osAd: m.group(1)!,
          yerel: m.group(1)!,
          yazdirilabilir: true,
        ),
  ];
}

/// system_profiler JSON'undan kart POS / sürücüsüz yazıcı adayları (yazıcılar
/// CUPS'tan geldiği için burada yalnız POS ve bilinen yazıcılar ipucuyla).
List<UsbCihaz> macProfilCihazlari(String json) {
  Object? kok;
  try {
    kok = jsonDecode(json);
  } catch (_) {
    return const [];
  }
  final ham = <({String vid, String pid, String? seri, String ad, String? uretici, String sira})>[];
  var sayac = 0;
  void gez(Object? d) {
    if (d is List) {
      for (final x in d) {
        gez(x);
      }
      return;
    }
    if (d is! Map) return;
    String? bul(bool Function(String) k) {
      for (final e in d.entries) {
        if ((e.value is String || e.value is num) && k(e.key.toString().toLowerCase())) return e.value.toString();
      }
      return null;
    }

    final vid = hex4(bul((k) => k == 'vendor_id' || k.endsWith('vendorid')));
    final pid = hex4(bul((k) => k == 'product_id' || k.endsWith('productid')));
    if (vid != null && pid != null) {
      final ad = bul((k) => k == '_name' || k.endsWith('productname')) ?? 'USB cihaz';
      var uretici = bul((k) => k == 'manufacturer' || k.endsWith('vendorname'));
      // "0x04b8  (Seiko Epson Corp.)" biçimindeki vendor_id'den üretici.
      uretici ??= RegExp(r'\((.+)\)').firstMatch(bul((k) => k == 'vendor_id') ?? '')?.group(1);
      ham.add((
        vid: vid,
        pid: pid,
        seri: bul((k) => k == 'serial_num' || k.contains('serialnumber')),
        ad: ad,
        uretici: uretici,
        sira: '${(bul((k) => k == 'location_id' || k.endsWith('locationid')) ?? '')}#${sayac++}',
      ));
    }
    for (final v in d.values) {
      if (v is List || v is Map) gez(v);
    }
  }

  gez(kok);
  final anahtarlar = usbAnahtarlari([for (final h in ham) (vid: h.vid, pid: h.pid, seri: h.seri, sira: h.sira)]);
  final sonuc = <UsbCihaz>[];
  for (var i = 0; i < ham.length; i++) {
    final h = ham[i];
    final tur = usbTurBelirle(vid: h.vid, pid: h.pid, ad: h.ad, uretici: h.uretici);
    if (tur != 'pos') continue; // yazıcılar CUPS kuyruğundan; diğerleri (klavye, disk) bildirilmez
    sonuc.add(UsbCihaz(
      anahtar: anahtarlar[i],
      tur: tur,
      ad: h.ad,
      platform: 'macos',
      uretici: h.uretici ?? usbPosUreticileri[h.vid],
      vid: h.vid,
      pid: h.pid,
      seri: h.seri,
    ));
  }
  return sonuc;
}
