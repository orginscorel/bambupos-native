import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/hareket.dart';
import '../core/bildirim.dart';
import '../core/durum.dart';
import '../core/guncelleme.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'bildirimler.dart';
import 'borclar.dart';
import 'kabuk.dart';

/// DAHA FAZLA: borca yazılanlar, bildirimler, hesap, görünüm, sürüm.
/// ÇIKIŞ YOK: patron telefonu cihazdır; eşlemeyi yalnız işletme sahibi
/// panelden (Cihazlar) kaldırır — o anda uygulama eşleme ekranına döner.
class DahaFazlaEkrani extends StatefulWidget {
  const DahaFazlaEkrani({super.key});
  @override
  State<DahaFazlaEkrani> createState() => _DahaFazlaEkraniState();
}

class _DahaFazlaEkraniState extends State<DahaFazlaEkrani> {
  String _surum = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _surum = '${p.version} (${p.buildNumber})');
    }).catchError((_) {});
  }

  Future<void> _temaSec() async {
    final secim = await pencereAc<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Görünüm'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: temaKipi.value,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(children: [
              for (final (m, ad) in const [(ThemeMode.system, 'Telefonla aynı'), (ThemeMode.light, 'Açık'), (ThemeMode.dark, 'Koyu')])
                RadioListTile<ThemeMode>(value: m, title: Text(ad)),
            ]),
          ),
        ],
      ),
    );
    if (secim != null) await Uyg.temaDegistir(secim);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final ad = Uyg.ad;
    return PaSayfa(
      baslik: 'Daha fazla',
      children: [
        Belirme(
          sira: 0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: Marka.geceGrad, borderRadius: Marka.yaricap),
            child: Row(children: [
              const PaMark(boyut: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ad.isEmpty ? 'Patron hesabı' : ad, style: gosterim(19, renk: Colors.white)),
                  Text('Bu telefon patron uygulaması olarak eşli', style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 12.5)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Belirme(
          sira: 1,
          child: SatirGrubu([
            Satir(
              baslik: 'Borca yazılanlar',
              alt: 'Kim, ne zaman, ne kadar',
              ikon: Icons.receipt_long_rounded,
              ikonRenk: r.uyari,
              onTap: () => git(context, const BorclarEkrani()),
            ),
            ValueListenableBuilder<int>(
              valueListenable: BildirimMerkezi.okunmamis,
              builder: (_, n, _) => Satir(
                baslik: 'Bildirimler',
                alt: n > 0 ? '$n okunmamış' : 'Hepsi okundu',
                ikon: Icons.notifications_rounded,
                onTap: () => git(context, const BildirimlerEkrani()),
                sag: n > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Marka.gul, borderRadius: BorderRadius.circular(6)),
                        child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      )
                    : null,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Belirme(
          sira: 2,
          child: SatirGrubu([
            ValueListenableBuilder<ThemeMode>(
              valueListenable: temaKipi,
              builder: (_, m, _) => Satir(
                baslik: 'Görünüm',
                alt: switch (m) { ThemeMode.light => 'Açık', ThemeMode.dark => 'Koyu', _ => 'Telefonla aynı' },
                ikon: Icons.contrast_rounded,
                onTap: _temaSec,
              ),
            ),
            Satir(
              baslik: 'Uygulama güncellemesi',
              alt: Platform.isIOS ? 'iPhone\'da App Store / TestFlight üzerinden' : 'Sürüm $_surum',
              ikon: Icons.system_update_rounded,
              onTap: guncellemeDenetle,
              sag: const GuncellemeSatiriDurum(),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Belirme(
          sira: 3,
          child: PaKart(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: r.silik, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bu telefonda çıkış yapılmaz. Eşlemeyi yalnız işletme sahibi panelde İşletme Yönetimi › Cihazlar bölümünden kaldırabilir; '
                  'kaldırıldığında uygulama eşleme ekranına döner.',
                  style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.45),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Center(child: Text('BamBumPOS Patron${_surum.isEmpty ? '' : ' · $_surum'}', style: TextStyle(color: r.silik, fontSize: 12))),
        const SizedBox(height: 70),
      ],
    );
  }
}
