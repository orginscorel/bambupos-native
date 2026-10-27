import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../ortak/ortak.dart';
import 'tema.dart';

/// Mesai/mola QR'ının işletmede okutulduğunu doğrulamak için konum.
/// Yalnız QR okuturken (ve yöneticinin "mesai noktası" ayarında) alınır.
enum KonumDurum { tamam, servisKapali, izinYok, kaliciRed, alinamadi }

class KonumSonuc {
  const KonumSonuc(this.durum, [this.konum]);
  final KonumDurum durum;
  final Position? konum;
  DateTime get zaman => konum?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// Sunucuya giden alanlar (GET sorgusu / POST gövdesi).
  Map<String, dynamic> get alanlar => konum == null
      ? const {}
      : {
          'lat': double.parse(konum!.latitude.toStringAsFixed(7)),
          'lng': double.parse(konum!.longitude.toStringAsFixed(7)),
          'dogruluk': konum!.accuracy.round(),
        };
}

class Konum {
  Konum._();

  /// Konum alır. `izinIste` false ise izin penceresi açılmaz (önceden alma).
  /// Yüksek doğruluk, ~8 sn zaman aşımı; alınamazsa son bilinen konum.
  static Future<KonumSonuc> al({bool izinIste = true, Duration zamanAsimi = const Duration(seconds: 8)}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return const KonumSonuc(KonumDurum.servisKapali);
      var izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied && izinIste) izin = await Geolocator.requestPermission();
      if (izin == LocationPermission.deniedForever) return const KonumSonuc(KonumDurum.kaliciRed);
      if (izin == LocationPermission.denied || izin == LocationPermission.unableToDetermine) return const KonumSonuc(KonumDurum.izinYok);
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: zamanAsimi),
        );
        return KonumSonuc(KonumDurum.tamam, p);
      } catch (_) {
        final son = await Geolocator.getLastKnownPosition();
        if (son != null) return KonumSonuc(KonumDurum.tamam, son);
        return const KonumSonuc(KonumDurum.alinamadi);
      }
    } catch (_) {
      return const KonumSonuc(KonumDurum.alinamadi);
    }
  }
}

/// "Konum gerekli" panosu: neden gerektiğini anlatır, duruma göre
/// "İzin ver" / "Ayarları aç" / "Konumu aç". true → çağıran yeniden denesin.
Future<bool> konumPanosu(BuildContext context, KonumDurum durum, {String? sunucuMesaji}) async {
  final sonuc = await panoAc<bool>(
    context,
    icerik: (ctx) => _KonumPanosu(durum: durum, sunucuMesaji: sunucuMesaji),
  );
  return sonuc == true;
}

class _KonumPanosu extends StatefulWidget {
  const _KonumPanosu({required this.durum, this.sunucuMesaji});
  final KonumDurum durum;
  final String? sunucuMesaji;
  @override
  State<_KonumPanosu> createState() => _KonumPanosuState();
}

class _KonumPanosuState extends State<_KonumPanosu> {
  bool _mesgul = false;

  Future<void> _eylem() async {
    setState(() => _mesgul = true);
    try {
      switch (widget.durum) {
        case KonumDurum.izinYok:
          final i = await Geolocator.requestPermission();
          if (!mounted) return;
          if (i == LocationPermission.deniedForever) {
            await Geolocator.openAppSettings();
            if (mounted) Navigator.pop(context, false);
            return;
          }
          Navigator.pop(context, i == LocationPermission.always || i == LocationPermission.whileInUse);
        case KonumDurum.kaliciRed:
          await Geolocator.openAppSettings();
          if (mounted) Navigator.pop(context, false);
        case KonumDurum.servisKapali:
          await Geolocator.openLocationSettings();
          if (mounted) Navigator.pop(context, false);
        case KonumDurum.tamam:
        case KonumDurum.alinamadi:
          Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final (baslik, aciklama, dugme, ikon) = switch (widget.durum) {
      KonumDurum.izinYok => ('Konum izni gerekli', 'Mesai ve mola QR\'ının işletmede okutulduğunu doğrulamak için konumun yalnızca okutma anında kullanılır. Takip yapılmaz.', 'İzin ver', Icons.my_location_rounded),
      KonumDurum.kaliciRed => ('Konum izni kapalı', 'Konum izni daha önce reddedildi. Ayarlar › BamBumPOS Personel › Konum bölümünden "Uygulamayı kullanırken" seç, sonra QR\'ı yeniden okut.', 'Ayarları aç', Icons.settings_rounded),
      KonumDurum.servisKapali => ('Konum servisi kapalı', 'Telefonunun konum servisi kapalı. Açtıktan sonra QR\'ı yeniden okut.', 'Konumu aç', Icons.location_off_rounded),
      _ => ('Konum alınamadı', 'Konumun belirlenemedi. Açık alana ya da pencere kenarına geçip yeniden dene.', 'Tekrar dene', Icons.location_searching_rounded),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: Marka.grad,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [BoxShadow(color: Marka.mor.withValues(alpha: .45), blurRadius: 24, offset: const Offset(0, 10), spreadRadius: -8)],
          ),
          child: Icon(ikon, color: Colors.white, size: 34),
        ),
      ),
      const SizedBox(height: 16),
      Text(baslik, textAlign: TextAlign.center, style: gosterim(21, renk: r.metin)),
      const SizedBox(height: 8),
      Text(aciklama, textAlign: TextAlign.center, style: TextStyle(color: r.soluk, fontSize: 13.5, height: 1.45)),
      if (widget.sunucuMesaji != null && widget.sunucuMesaji!.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 18, color: r.soluk),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.sunucuMesaji!, style: TextStyle(fontSize: 12.5, height: 1.35, color: r.soluk))),
          ]),
        ),
      ],
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Marka.zumrut.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.shield_rounded, size: 17, color: r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Konumun yalnız QR okutulduğu an gönderilir; arka planda takip edilmez.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857))),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      GradDugme(yazi: dugme, ikon: ikon, yukleniyor: _mesgul, onTap: _eylem),
      const SizedBox(height: 6),
      PaMetinDugme(yazi: 'Vazgeç', onTap: _mesgul ? null : () => Navigator.pop(context, false)),
    ]);
  }
}

/// Konumla ilgili sunucu reddi (uzak / bu telefon başka personelde / QR kullanıldı).
Future<bool> konumUyariPanosu(BuildContext context, {required IconData ikon, required String baslik, required String aciklama, Color renk = Marka.kehribar, String? tekrarYazi}) async {
  final s = await panoAc<bool>(
    context,
    icerik: (ctx) {
      final r = ctx.pa;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: PaIkon(ikon, boyut: 72, zemin: renk.withValues(alpha: .14), renk: renk)),
        const SizedBox(height: 14),
        Text(baslik, textAlign: TextAlign.center, style: gosterim(21, renk: r.metin)),
        const SizedBox(height: 8),
        Text(aciklama, textAlign: TextAlign.center, style: TextStyle(color: r.soluk, fontSize: 13.5, height: 1.45)),
        const SizedBox(height: 18),
        if (tekrarYazi != null) ...[
          GradDugme(yazi: tekrarYazi, ikon: Icons.refresh_rounded, onTap: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 6),
          PaMetinDugme(yazi: 'Kapat', onTap: () => Navigator.pop(ctx, false)),
        ] else
          YumusakDugme(yazi: 'Tamam', onTap: () => Navigator.pop(ctx, false)),
      ]);
    },
  );
  return s == true;
}
