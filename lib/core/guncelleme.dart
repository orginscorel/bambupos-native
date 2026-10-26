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

/// UYGULAMA İÇİ GÜNCELLEME (mağaza dışı dağıtım).
/// bambumpos.com/indir/personel/surum.json → { surum, notlar, indir: {android, ios} }.
/// Android: APK uygulama içinde iner ve aynı imzayla üstüne kurulur (eşleme korunur).
/// iOS: indirme / TestFlight sayfası açılır.
class Guncelleme {
  static const _adres = 'https://bambumpos.com/indir/personel/surum.json';
  static DateTime? _sonBakis;

  static bool dahaYeni(String a, String b) {
    List<int> p(String s) => s.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  static Future<void> bak(BuildContext context) async {
    if (_sonBakis != null && DateTime.now().difference(_sonBakis!) < const Duration(hours: 6)) return;
    _sonBakis = DateTime.now();
    try {
      final r = await Uyg.api.get(_adres);
      if (r is! Map) return;
      final yeni = r['surum']?.toString() ?? '';
      final adres = (r['indir'] is Map ? (r['indir'] as Map)[Platform.isIOS ? 'ios' : 'android'] : null)?.toString();
      final bu = (await PackageInfo.fromPlatform()).version;
      if (adres == null || adres.isEmpty || !dahaYeni(yeni, bu) || !context.mounted) return;
      await panoAc<void>(
        context,
        baslik: 'Yeni sürüm hazır',
        alt: 'BamBumPOS Personel $yeni',
        icerik: (ctx) => _GuncellemePanosu(adres: adres, notlar: r['notlar']?.toString()),
      );
    } on ApiHata {
      // Sürüm dosyasına ulaşılamazsa sessiz geç.
    }
  }
}

class _GuncellemePanosu extends StatefulWidget {
  const _GuncellemePanosu({required this.adres, this.notlar});
  final String adres;
  final String? notlar;
  @override
  State<_GuncellemePanosu> createState() => _GuncellemePanosuState();
}

class _GuncellemePanosuState extends State<_GuncellemePanosu> {
  double? _ilerleme;
  String? _mesaj;
  StreamSubscription<OtaEvent>? _ota;

  @override
  void dispose() {
    _ota?.cancel();
    super.dispose();
  }

  void _baslat() {
    if (!Platform.isAndroid) {
      launchUrl(Uri.parse(widget.adres), mode: LaunchMode.externalApplication);
      return;
    }
    setState(() => _ilerleme = 0);
    _ota = OtaUpdate().execute(widget.adres, destinationFilename: 'BamBumPOS-Personel.apk').listen(
      (e) {
        if (!mounted) return;
        setState(() {
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              _ilerleme = (double.tryParse(e.value ?? '') ?? 0) / 100;
            case OtaStatus.INSTALLING:
              _ilerleme = 1;
              _mesaj = 'Kurulum açılıyor…';
            default:
              _mesaj = 'Güncelleme tamamlanamadı (${e.status.name}). Tekrar deneyin.';
              _ilerleme = null;
          }
        });
      },
      onError: (_) => setState(() {
        _ilerleme = null;
        _mesaj = 'İndirme başarısız. İnternet bağlantısını kontrol edin.';
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.notlar != null && widget.notlar!.isNotEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(18)),
          child: Text(widget.notlar!, style: TextStyle(color: r.soluk, height: 1.4)),
        ),
      const SizedBox(height: 14),
      if (_ilerleme != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: LinearProgressIndicator(value: _ilerleme, minHeight: 10, backgroundColor: r.ic, color: Marka.mor),
        ),
        const SizedBox(height: 8),
        Text(_mesaj ?? 'İndiriliyor… %${((_ilerleme ?? 0) * 100).round()}', textAlign: TextAlign.center, style: TextStyle(color: r.soluk)),
      ] else ...[
        if (_mesaj != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_mesaj!, style: const TextStyle(color: Marka.gul))),
        GradDugme(yazi: 'Şimdi güncelle', ikon: Icons.system_update_rounded, onTap: _baslat),
        const SizedBox(height: 8),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Sonra', style: TextStyle(color: r.soluk))),
      ],
    ]);
  }
}
