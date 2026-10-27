import 'package:flutter/services.dart';

import 'usb.dart';

/// Android: UsbManager köprüsü (android/app/.../UsbKopru.kt).
class AndroidUsb extends UsbKaynak {
  static const _kanal = MethodChannel('bambumpos/usb');
  static const _olay = EventChannel('bambumpos/usb/olay');

  @override
  bool get destekli => true;
  @override
  String get platform => 'android';

  @override
  Stream<void> get degisti => _olay.receiveBroadcastStream().map((_) {});

  @override
  Future<List<UsbCihaz>> listele({bool zorla = false}) async {
    final ham = (await _kanal.invokeListMethod<Map>('liste')) ?? const [];
    return androidCihazlari(ham);
  }

  @override
  Future<bool> izinIste(UsbCihaz c) async {
    if (!c.izinGerekli) return true;
    try {
      return (await _kanal.invokeMethod<bool>('izinIste', {'ad': c.yerel})) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> yaz(UsbCihaz c, Uint8List bayt, {int kopya = 1}) async {
    try {
      await _kanal.invokeMethod<void>('yaz', {'ad': c.yerel, 'veri': bayt, 'kopya': kopya});
    } on PlatformException catch (e) {
      throw UsbHata(switch (e.code) {
        'YOK' => 'USB yazıcı bağlı değil',
        'IZIN' => 'USB yazıcı için izin verilmedi (cihazda "İzin ver" deyin)',
        'ARAYUZ' => 'USB cihazında yazdırma bağlantısı bulunamadı',
        'ACILAMADI' => 'USB yazıcı açılamadı',
        _ => 'USB yazıcıya gönderilemedi${e.message != null ? ': ${e.message}' : ''}',
      });
    }
  }
}

/// Kotlin'den gelen ham listeyi cihazlara çevirir (birim testte de kullanılır).
List<UsbCihaz> androidCihazlari(List<Map> ham) {
  final kayitlar = [
    for (final m in ham)
      (
        vid: hex4(m['vid']) ?? '0000',
        pid: hex4(m['pid']) ?? '0000',
        seri: (m['seri'] as String?)?.trim(),
        sira: '${m['ad'] ?? ''}',
        m: m,
      ),
  ];
  final anahtarlar = usbAnahtarlari([for (final k in kayitlar) (vid: k.vid, pid: k.pid, seri: k.seri, sira: k.sira)]);
  final sonuc = <UsbCihaz>[];
  for (var i = 0; i < kayitlar.length; i++) {
    final k = kayitlar[i];
    final m = k.m;
    final urun = (m['urun'] as String?)?.trim();
    final uretici = (m['uretici'] as String?)?.trim();
    final siniflar = [for (final s in (m['siniflar'] as List? ?? const [])) (s as num).toInt()];
    // Android'in kendi hub / dahili aygıtları (sınıf 9 = hub) listelenmez.
    if (siniflar.isNotEmpty && siniflar.every((s) => s == 9)) continue;
    final tur = usbTurBelirle(vid: k.vid, pid: k.pid, siniflar: siniflar, ad: urun, uretici: uretici);
    final ad = (urun?.isNotEmpty ?? false)
        ? urun!
        : (tur == 'pos' ? 'USB kart POS' : (tur == 'yazici' ? 'USB yazıcı' : 'USB cihaz'));
    sonuc.add(UsbCihaz(
      anahtar: anahtarlar[i],
      tur: tur,
      ad: ad,
      platform: 'android',
      uretici: (uretici?.isNotEmpty ?? false) ? uretici : (usbYaziciUreticileri[k.vid] ?? usbPosUreticileri[k.vid]),
      vid: k.vid,
      pid: k.pid,
      seri: (k.seri?.isNotEmpty ?? false) ? k.seri : null,
      osAd: k.sira,
      yerel: k.sira,
      izinGerekli: m['izin'] != true,
      yazdirilabilir: tur == 'yazici' && m['bulkOut'] == true,
    ));
  }
  return sonuc;
}
