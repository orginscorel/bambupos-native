import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ortak/ortak.dart';
import 'api.dart';
import 'durum.dart';
import 'tema.dart';

/// UYGULAMA İÇİ GÜNCELLEME (POS uygulamasıyla aynı mantık).
/// bambumpos.com/indir/personel/surum.json → { surum, notlar, indir: {android, ios, ios_testflight} }.
/// Açılışta + uygulamaya her dönüşte (30 dk'da bir) bakılır; yeni sürüm varsa
/// alt menünün üstünde kalıcı kart çıkar (kapatılsa da Profil'den güncellenebilir).
///   • Android: APK uygulama içinde iner, aynı imzayla üstüne kurulur (eşleme korunur).
///   • iPhone (siteden kurulum): kurulum doğrudan başlar (itms-services).
///   • iPhone (TestFlight): TestFlight açılır.
class GuncellemeBilgi {
  const GuncellemeBilgi(this.surum, this.adres, this.notlar);
  final String surum;
  final String adres;
  final String? notlar;
}

class Guncelleme {
  static const _adres = 'https://bambumpos.com/indir/personel/surum.json';
  static final bulunan = ValueNotifier<GuncellemeBilgi?>(null);
  static final ilerleme = ValueNotifier<double?>(null);
  static final mesaj = ValueNotifier<String?>(null);
  static final kartGizli = ValueNotifier<bool>(false);
  static DateTime? _sonBakis;
  static StreamSubscription<OtaEvent>? _ota;
  static Future<PackageInfo>? _paket; // sürüm bilgisi bir kez okunur

  static bool dahaYeni(String a, String b) {
    List<int> p(String s) => s.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  /// Siteden (Ad Hoc) kurulan iPhone uygulamasında embedded.mobileprovision bulunur;
  /// TestFlight / App Store kurulumunda Apple bu dosyayı kaldırır.
  static bool get _iosSitedenKurulu {
    try {
      return File('${File(Platform.resolvedExecutable).parent.path}/embedded.mobileprovision').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// App Store / TestFlight kurulumu (iPhone, embedded.mobileprovision yok): güncellemeyi
  /// Apple yapar; uygulama içi kart/bağlantı Apple kuralı (2.4.5/2.5.2) gereği HİÇ gösterilmez.
  static final bool magazaKurulumu = Platform.isIOS && !_iosSitedenKurulu;

  /// Yeni sürüm varsa true. [zorla] = 30 dk sınırını yok say (Profil'deki düğme).
  static Future<bool> bak({bool zorla = false}) async {
    if (magazaKurulumu) {
      bulunan.value = null;
      return false;
    }
    if (!zorla && _sonBakis != null && DateTime.now().difference(_sonBakis!) < const Duration(minutes: 15)) {
      return bulunan.value != null;
    }
    _sonBakis = DateTime.now();
    try {
      final r = await Uyg.api.get('$_adres?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      if (r is! Map) return false;
      final yeni = r['surum']?.toString() ?? '';
      final indir = r['indir'] is Map ? r['indir'] as Map : const {};
      String? adres;
      if (Platform.isAndroid) {
        adres = indir['android']?.toString();
      } else if (Platform.isIOS) {
        adres = (_iosSitedenKurulu ? indir['ios'] : (indir['ios_testflight'] ?? indir['ios']))?.toString();
      }
      final bu = (await (_paket ??= PackageInfo.fromPlatform())).version;
      if (adres == null || adres.isEmpty || !dahaYeni(yeni, bu)) {
        bulunan.value = null;
        return false;
      }
      if (bulunan.value?.surum != yeni) kartGizli.value = false;
      bulunan.value = GuncellemeBilgi(yeni, adres, r['notlar']?.toString());
      return true;
    } on ApiHata {
      return bulunan.value != null; // sürüm dosyasına ulaşılamazsa sessiz geç
    }
  }

  static Future<void> baslat() async {
    final b = bulunan.value;
    if (magazaKurulumu || b == null || ilerleme.value != null) return;
    if (!Platform.isAndroid) {
      mesaj.value = null;
      final ok = await launchUrl(Uri.parse(b.adres), mode: LaunchMode.externalApplication);
      if (!ok) mesaj.value = 'Kurulum açılamadı. Tekrar deneyin.';
      return;
    }
    ilerleme.value = 0;
    mesaj.value = 'İndiriliyor…';
    await _ota?.cancel();
    _ota = OtaUpdate().execute(b.adres, destinationFilename: 'BamBumPOS-Personel-${b.surum}.apk').listen(
      (e) {
        switch (e.status) {
          case OtaStatus.DOWNLOADING:
            final y = double.tryParse(e.value ?? '') ?? 0;
            ilerleme.value = y / 100;
            mesaj.value = 'İndiriliyor… %${y.round()}';
          case OtaStatus.INSTALLING:
          case OtaStatus.INSTALLATION_DONE:
            ilerleme.value = null;
            mesaj.value = 'Kurulum ekranı açıldı — “Güncelle”ye dokunun';
          case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
            ilerleme.value = null;
            mesaj.value = 'Bu uygulamaya “bilinmeyen uygulamaları yükleme” izni verin, sonra tekrar deneyin.';
          case OtaStatus.ALREADY_RUNNING_ERROR:
            mesaj.value = 'Güncelleme zaten sürüyor…';
          case OtaStatus.CANCELED:
            ilerleme.value = null;
            mesaj.value = 'Güncelleme iptal edildi.';
          default:
            ilerleme.value = null;
            mesaj.value = 'Güncelleme tamamlanamadı. Tekrar deneyin.';
        }
      },
      onError: (Object _) {
        ilerleme.value = null;
        mesaj.value = 'İndirme başarısız. İnternet bağlantısını kontrol edin.';
      },
    );
  }
}

/// Alt menünün üstünde duran güncelleme kartı.
class GuncellemeKarti extends StatelessWidget {
  const GuncellemeKarti({super.key});

  @override
  Widget build(BuildContext context) {
    if (Guncelleme.magazaKurulumu) return const SizedBox.shrink();
    return ValueListenableBuilder<GuncellemeBilgi?>(
      valueListenable: Guncelleme.bulunan,
      builder: (_, b, _) => ValueListenableBuilder<bool>(
        valueListenable: Guncelleme.kartGizli,
        builder: (_, gizli, _) {
          final goster = b != null && !gizli;
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (c, a) => SlideTransition(
              position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
              child: FadeTransition(opacity: a, child: c),
            ),
            child: goster ? _Kart(key: ValueKey(b.surum), b: b) : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

class _Kart extends StatelessWidget {
  const _Kart({super.key, required this.b});
  final GuncellemeBilgi b;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: r.kart,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Marka.mor.withValues(alpha: .35)),
          boxShadow: const [BoxShadow(color: Color(0x332A1F8A), blurRadius: 24, offset: Offset(0, 10), spreadRadius: -8)],
        ),
        child: ValueListenableBuilder<double?>(
          valueListenable: Guncelleme.ilerleme,
          builder: (_, ilerleme, _) => ValueListenableBuilder<String?>(
            valueListenable: Guncelleme.mesaj,
            builder: (_, mesaj, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('Yeni sürüm: ${b.surum}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: r.metin)),
                    const SizedBox(height: 2),
                    Text(
                      mesaj ?? (b.notlar?.isNotEmpty == true ? b.notlar! : 'İyileştirmeler ve düzeltmeler'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, height: 1.3, color: r.soluk),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                if (ilerleme == null) ...[
                  Basilir(
                    onTap: Guncelleme.baslat,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(12)),
                      child: const Text('Güncelle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Sonra',
                    onPressed: () => Guncelleme.kartGizli.value = true,
                    icon: Icon(Icons.close_rounded, size: 19, color: r.silik),
                  ),
                ] else
                  const Padding(padding: EdgeInsets.only(right: 10), child: Yukleyici(boyut: 22)),
              ]),
              if (ilerleme != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: ilerleme, minHeight: 6, backgroundColor: r.ic, color: Marka.mor),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Profil'deki "Uygulama güncellemesi" satırının sağ tarafı + dokununca denetleme.
class GuncellemeSatiriDurum extends StatelessWidget {
  const GuncellemeSatiriDurum({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<GuncellemeBilgi?>(
      valueListenable: Guncelleme.bulunan,
      builder: (_, b, _) => b == null
          ? Text('Güncel', style: TextStyle(color: context.pa.silik, fontSize: 13, fontWeight: FontWeight.w600))
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(8)),
              child: Text('${b.surum} hazır', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
    );
  }
}

Future<void> guncellemeDenetle() async {
  if (Guncelleme.bulunan.value != null) {
    Guncelleme.kartGizli.value = false;
    return Guncelleme.baslat();
  }
  final var_ = await Guncelleme.bak(zorla: true);
  if (var_) {
    Guncelleme.kartGizli.value = false;
  } else {
    bildir('Uygulama güncel', mesaj: 'En son sürümü kullanıyorsun.');
  }
}
