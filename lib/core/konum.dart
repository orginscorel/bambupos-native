import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../ortak/ortak.dart';
import 'durum.dart';
import 'tema.dart';

/// Mesai/mola QR'ının işletmede okutulduğunu doğrulamak için konum.
/// Yalnız QR okuturken alınır. İşletme konum kuralını açtıysa izin zorunludur
/// (konum_kapisi.dart); kural ve mesai noktası yalnız web konsolunda ayarlanır.
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

  /// İzin + servis durumu — UCUZ, izin penceresi AÇMAZ (konum kapısı için).
  /// tamam = servis açık ve izin "kullanırken"/"her zaman". Eklenti
  /// yanıt vermezse (ör. desteklenmeyen platform) kilitlememek için tamam.
  static Future<KonumDurum> izinDurumu() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return KonumDurum.servisKapali;
      return switch (await Geolocator.checkPermission()) {
        LocationPermission.deniedForever => KonumDurum.kaliciRed,
        LocationPermission.denied => KonumDurum.izinYok,
        _ => KonumDurum.tamam,
      };
    } catch (_) {
      return KonumDurum.tamam;
    }
  }

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
  const _KonumPanosu({required this.durum, this.sunucuMesaji, this.gecilebilir = false, this.qrIcin = false});
  final KonumDurum durum;
  final String? sunucuMesaji;
  /// "Şimdilik geç" (yalnız işletme kuralı kapalıyken, QR öncesi).
  final bool gecilebilir;
  /// QR okutucu açılmadan önce gösteriliyor (metinler "okutmadan önce").
  final bool qrIcin;
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
      KonumDurum.izinYok => (
          'Konum izni gerekli',
          '${widget.qrIcin ? 'QR okutmadan önce konum iznini ver. ' : ''}Mesai ve mola QR\'ının işletmede okutulduğunu doğrulamak için konumun yalnızca okutma anında kullanılır. Takip yapılmaz.',
          'İzin ver',
          Icons.my_location_rounded
        ),
      KonumDurum.kaliciRed => ('Konum izni kapalı', 'Konum izni daha önce reddedildi. Ayarlar › BamBumPOS Personel › Konum bölümünden "Uygulamayı kullanırken" seç, sonra QR\'ı ${widget.qrIcin ? '' : 'yeniden '}okut.', 'Ayarları aç', Icons.settings_rounded),
      KonumDurum.servisKapali => ('Konum servisi kapalı', 'Telefonunun konum servisi kapalı. Açtıktan sonra QR\'ı ${widget.qrIcin ? '' : 'yeniden '}okut.', 'Konumu aç', Icons.location_off_rounded),
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
      if (widget.gecilebilir)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          PaMetinDugme(yazi: 'Vazgeç', onTap: _mesgul ? null : () => Navigator.pop(context, false)),
          const SizedBox(width: 8),
          PaMetinDugme(yazi: 'Şimdilik geç', onTap: _mesgul ? null : () => Navigator.pop(context, 'gec')),
        ])
      else
        PaMetinDugme(yazi: 'Vazgeç', onTap: _mesgul ? null : () => Navigator.pop(context, false)),
    ]);
  }
}

/// Konumla ilgili sunucu reddi (uzak / bu telefon başka personelde / QR kullanıldı).
Future<bool> konumUyariPanosu(BuildContext context,
    {required IconData ikon, required String baslik, required String aciklama, Color renk = Marka.kehribar, String? tekrarYazi, List<(String, String)>? ozet}) async {
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
        if (ozet != null && ozet.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (var i = 0; i < ozet.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
                  child: Column(children: [
                    Text(ozet[i].$2, style: gosterim(18, renk: i == 0 ? (renk == Marka.kehribar ? kehribarYazi(r.koyu) : renk) : r.metin)),
                    const SizedBox(height: 2),
                    Text(ozet[i].$1, style: TextStyle(fontSize: 11.5, color: r.soluk, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ],
          ]),
        ],
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


/* ───────────────────────── Konum durumu (görünür) ───────────────────────── */

/// Telefonun konum servisi + uygulama izni — ekranlarda görünür durum.
/// Ucuz denetim (izin penceresi açmaz); uygulamaya dönünce ve her eylemden
/// sonra tazelenir. Ana sayfa satırı, Profil satırı ve QR kapısı bunu dinler.
class KonumIzleyici {
  KonumIzleyici._();

  /// İzin + servis durumu (TEK kaynak; ana sayfa satırı, Profil, QR kapısı, şerit).
  static final durum = ValueNotifier<KonumDurum?>(null);

  /// Canlı uzaklık (yalnız kural açık + izin tamam + uygulama önde iken).
  /// null = bilinmiyor / takip yok.
  static final canli = ValueNotifier<KonumCanli?>(null);

  /// Konum akışı (testte sahte verilir). Yüksek doğruluk, 5 m'de bir.
  static Stream<Position> Function() akisKaynagi = () =>
      Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5));

  static bool _takipEtkin = false;
  static bool _takipDinliyor = false;
  static StreamSubscription<Position>? _akis;
  static Position? _son;

  /// Mesai noktası (hesap › mesai_konum: lat/lng/yaricap_m; yalnız kural açıkken gelir).
  static ({double lat, double lng, int yaricap})? get nokta {
    final m = Uyg.hesap.value?['mesai_konum'];
    if (m is! Map || m['zorunlu'] != true) return null;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng, yaricap: ((m['yaricap_m'] as num?) ?? 150).round());
  }

  /// Kabuk açılınca başlar, kapanınca durur. Akış YALNIZ şu koşulda çalışır:
  /// uygulama önde + izin/servis tamam + kural açık + nokta var. Arka plana
  /// geçince, izin gidince (konum kapısı açılınca) ya da kural kapanınca durur.
  static void takipBaslat() {
    _takipEtkin = true;
    if (!_takipDinliyor) {
      _takipDinliyor = true;
      uygulamaOnde.addListener(_takipAyarla);
      durum.addListener(_takipAyarla);
      Uyg.hesap.addListener(_noktaDegisti);
    }
    _takipAyarla();
  }

  static void takipDurdur() {
    _takipEtkin = false;
    _takipAyarla();
  }

  static void _noktaDegisti() {
    _takipAyarla();
    final p = _son;
    if (p != null && _akis != null) _hesapla(p);
  }

  static void _takipAyarla() {
    final calis = _takipEtkin && uygulamaOnde.value && durum.value == KonumDurum.tamam && nokta != null;
    if (calis && _akis == null) {
      try {
        _akis = akisKaynagi().listen(_hesapla, onError: (Object _) {
          // Konum alınamadı: akış kapanır, sonraki öne gelişte yeniden denenir.
          _akis?.cancel();
          _akis = null;
        }, cancelOnError: true);
      } catch (_) {
        _akis = null;
      }
    } else if (!calis && _akis != null) {
      _akis!.cancel();
      _akis = null;
    }
    // Kural kapandı / izin gitti / oturum kapandı → uzaklık bilgisi geçersiz.
    // (Arka plana geçişte son değer kalır; öne gelince akış tazeler.)
    if (!calis && (!_takipEtkin || durum.value != KonumDurum.tamam || nokta == null)) {
      canli.value = null;
      _son = null;
    }
  }

  static void _hesapla(Position p) {
    final n = nokta;
    if (n == null) return;
    _son = p;
    canli.value = KonumCanli.hesapla(
      mesafe: Geolocator.distanceBetween(p.latitude, p.longitude, n.lat, n.lng),
      dogruluk: p.accuracy,
      yaricap: n.yaricap,
    );
  }

  /// Testte sahte durum verilebilir.
  static Future<KonumDurum> Function() denetci = Konum.izinDurumu;

  static bool _dinliyor = false;
  static Future<KonumDurum>? _suren;

  static Future<KonumDurum> tazele() {
    if (!_dinliyor) {
      _dinliyor = true;
      uygulamaOnde.addListener(() {
        if (uygulamaOnde.value) tazele(); // ayarlardan dönünce
      });
    }
    return _suren ??= denetci().then((d) {
      durum.value = d;
      return d;
    }).whenComplete(() => _suren = null);
  }

  /// Duruma göre tek eylem: izin iste / konum ayarı / uygulama ayarı.
  static Future<KonumDurum> eylem([KonumDurum? d]) async {
    try {
      switch (d ?? durum.value) {
        case KonumDurum.servisKapali:
          await Geolocator.openLocationSettings();
        case KonumDurum.kaliciRed:
          await Geolocator.openAppSettings();
        case KonumDurum.izinYok:
          final bas = DateTime.now();
          final i = await Geolocator.requestPermission();
          // Pencere hiç açılmadan döndüyse (kalıcı ret) ayarlara götür.
          if (i == LocationPermission.deniedForever && DateTime.now().difference(bas).inMilliseconds < 600) {
            await Geolocator.openAppSettings();
          }
        default:
          break;
      }
    } catch (_) {}
    return tazele();
  }

  static String metin(KonumDurum? d) => switch (d) {
        KonumDurum.tamam => 'Konum açık · izin verildi',
        KonumDurum.servisKapali => 'Konum servisi kapalı',
        KonumDurum.kaliciRed => 'Konum izni kalıcı reddedildi',
        KonumDurum.izinYok => 'Konum izni yok',
        KonumDurum.alinamadi => 'Konum alınamadı',
        null => 'Konum denetleniyor…',
      };

  static String? eylemYazi(KonumDurum? d) => switch (d) {
        KonumDurum.izinYok => 'İzin ver',
        KonumDurum.servisKapali => 'Aç',
        KonumDurum.kaliciRed => 'Ayarlar',
        _ => null,
      };

  /// "İşletmen konumla doğruluyor · 150 m" (kural açıksa).
  static String? kuralYazi() {
    if (!Uyg.konumZorunlu) return null;
    final y = Uyg.konumYaricap;
    return 'İşletmen konumla doğruluyor${y != null && y > 0 ? ' · ${mesafeYaz(y)}' : ''}';
  }
}

/// Uyarı yazısı rengi (kehribar zemin üstü okunur: açıkta koyu, koyuda açık ton).
Color kehribarYazi(bool koyu) => koyu ? const Color(0xFFFCD34D) : const Color(0xFFB45309);

String mesafeYaz(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} km' : '$m m';

/// Canlı konum sonucu: mesai noktasına uzaklık + içeride mi.
@immutable
class KonumCanli {
  const KonumCanli({required this.mesafe, required this.dogruluk, required this.yaricap, required this.icerde});

  /// Sunucuyla AYNI kural: uzaklık ≤ yarıçap + min(doğruluk, 25) → içeride
  /// (2026-10-27: 50 m ayarda 100 m'ye kadar içeride sayılıyordu; pay 25 m'ye indi).
  factory KonumCanli.hesapla({required double mesafe, required double dogruluk, required int yaricap}) => KonumCanli(
        mesafe: mesafe.round(),
        dogruluk: dogruluk,
        yaricap: yaricap,
        icerde: mesafe <= yaricap + math.min(dogruluk.isFinite ? dogruluk : 25, 25),
      );

  final int mesafe;
  final double dogruluk;
  final int yaricap;
  final bool icerde;

  @override
  bool operator ==(Object other) => other is KonumCanli && other.mesafe == mesafe && other.icerde == icerde && other.yaricap == yaricap;
  @override
  int get hashCode => Object.hash(mesafe, icerde, yaricap);
}

/// Ana sayfadaki küçük konum durumu satırı (simge + yazı + eylem).
class KonumDurumSatiri extends StatefulWidget {
  const KonumDurumSatiri({super.key});
  @override
  State<KonumDurumSatiri> createState() => _KonumDurumSatiriState();
}

class _KonumDurumSatiriState extends State<KonumDurumSatiri> {
  bool _mesgul = false;

  @override
  void initState() {
    super.initState();
    KonumIzleyici.tazele();
  }

  Future<void> _eylem() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    await KonumIzleyici.eylem();
    if (mounted) setState(() => _mesgul = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return ListenableBuilder(
      listenable: Listenable.merge([KonumIzleyici.durum, KonumIzleyici.canli]),
      builder: (_, _) {
        final d = KonumIzleyici.durum.value;
        final c = d == KonumDurum.tamam ? KonumIzleyici.canli.value : null;
        final tamam = d == KonumDurum.tamam;
        final disarida = c != null && !c.icerde;
        final yesil = r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
        final renk = d == null ? r.soluk : tamam && !disarida ? yesil : kehribarYazi(r.koyu);
        final ikon = switch (d) {
          KonumDurum.tamam when disarida => Icons.wrong_location_rounded,
          KonumDurum.tamam => Icons.location_on_rounded,
          KonumDurum.servisKapali => Icons.location_off_rounded,
          null => Icons.location_searching_rounded,
          _ => Icons.wrong_location_rounded,
        };
        final eylem = KonumIzleyici.eylemYazi(d);
        final kural = KonumIzleyici.kuralYazi();
        return Semantics(
          container: true,
          label: 'Konum durumu: ${KonumIzleyici.metin(d)}',
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: r.kart,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: (tamam && !disarida) || d == null ? r.kenar : Marka.kehribar.withValues(alpha: .45)),
            ),
            child: Row(children: [
              PaIkon(ikon, boyut: 34, zemin: renk.withValues(alpha: .12), renk: renk),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    c == null ? KonumIzleyici.metin(d) : (c.icerde ? 'İşletmedesin · konum doğrulandı' : 'İşletme dışındasın · ≈${mesafeYaz(c.mesafe)}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: tamam && !disarida ? r.metin : renk),
                  ),
                  Text(
                    kural ?? (tamam ? 'Mesai QR\'ı okutulurken konumun doğrulanır' : 'QR okutmak için konum gerekli'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: r.soluk),
                  ),
                ]),
              ),
              if (eylem != null) ...[
                const SizedBox(width: 8),
                _mesgul
                    ? Padding(padding: const EdgeInsets.all(8), child: Yukleyici(boyut: 18, renk: r.birincil))
                    : PaMetinDugme(yazi: eylem, kucuk: true, onTap: _eylem),
              ],
            ]),
          ),
        );
      },
    );
  }
}

/// Profil › Güvenlik ve cihaz › "Konum izni" satırı (durum + tek eylem).
class KonumSatiri extends StatefulWidget {
  const KonumSatiri({super.key});
  @override
  State<KonumSatiri> createState() => _KonumSatiriState();
}

class _KonumSatiriState extends State<KonumSatiri> {
  @override
  void initState() {
    super.initState();
    KonumIzleyici.tazele();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return ValueListenableBuilder<KonumDurum?>(
      valueListenable: KonumIzleyici.durum,
      builder: (_, d, _) {
        final tamam = d == KonumDurum.tamam;
        final yesil = r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
        final eylem = KonumIzleyici.eylemYazi(d);
        final kural = KonumIzleyici.kuralYazi();
        return Satir(
          ikon: tamam ? Icons.location_on_rounded : Icons.location_off_rounded,
          baslik: 'Konum izni',
          // Açıkken sağda "Açık" yazar; alt satır işletme kuralını söyler.
          alt: tamam ? (kural ?? KonumIzleyici.metin(d)) : KonumIzleyici.metin(d),
          ikonZemin: tamam ? Marka.zumrut.withValues(alpha: .12) : Marka.kehribar.withValues(alpha: .14),
          ikonRenk: tamam ? yesil : Marka.kehribar,
          onTap: () => KonumIzleyici.eylem(tamam ? KonumDurum.kaliciRed : d), // tamamken: uygulama ayarları
          sag: eylem == null
              ? Text(tamam ? 'Açık' : '—', style: TextStyle(color: tamam ? yesil : r.silik, fontSize: 13, fontWeight: FontWeight.w600))
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Marka.kehribar.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
                  child: Text(eylem, style: TextStyle(color: kehribarYazi(r.koyu), fontSize: 12, fontWeight: FontWeight.w700)),
                ),
        );
      },
    );
  }
}

/// QR okutucuyu açmadan önce: konum servisi + izin tamamsa true.
/// Değilse izin panosu açılır; izin verilirse true. İşletme kuralı KAPALIYSA
/// panoda "Şimdilik geç" de vardır (true döner). Kamera izinsiz AÇILMAZ.
Future<bool> qrOncesiKonum(BuildContext context) async {
  var d = await KonumIzleyici.tazele();
  if (d == KonumDurum.tamam || !context.mounted) return d == KonumDurum.tamam;
  final sonuc = await panoAc<Object>(
    context,
    icerik: (ctx) => _KonumPanosu(durum: d, gecilebilir: !Uyg.konumZorunlu, qrIcin: true),
  );
  if (sonuc == 'gec') return true;
  d = await KonumIzleyici.tazele();
  return d == KonumDurum.tamam;
}

/// Sunucu 403 (mesafe): mesai noktasına uzaklık ve sınır açıkça yazılır.
Future<bool> uzakPanosu(BuildContext context, {int? mesafe, int? yaricap}) {
  final m = mesafe == null ? null : '≈${mesafeYaz(mesafe)}';
  final y = yaricap == null ? null : mesafeYaz(yaricap);
  final aciklama = [
    if (m != null && y != null)
      'Mesai noktasına $m uzaktasın; en fazla $y içinde olmalısın.'
    else if (m != null)
      'Mesai noktasına $m uzaktasın.'
    else if (y != null)
      'QR yalnız mesai noktasının $y yakınında okutulabilir.',
    'İşletmeye geldiğinde yeniden okut; konumun yanlışsa açık alanda tekrar dene.',
  ].join(' ');
  return konumUyariPanosu(
    context,
    ikon: Icons.wrong_location_rounded,
    baslik: 'Mesai noktasına uzaksın',
    aciklama: aciklama,
    ozet: (m != null || y != null) ? [if (m != null) ('Uzaklığın', m), if (y != null) ('İzin verilen', y)] : null,
    tekrarYazi: 'Konumu yenile ve dene',
  );
}


/* ───────────────────────── Canlı konum şeridi (kabuk üstü) ───────────────────────── */

/// Kabuğun EN ÜSTÜNDE (durum çubuğunun altında, tüm sekmelerde) canlı konum:
/// dışarıda → "İşletme dışındasınız · 320 m" (uyarı); içeride → yeşil
/// "İşletmedesiniz", birkaç saniye sonra ince bir çizgiye küçülür.
/// Şerit görünürken alttaki sayfanın üst güvenli alanı şeride devredilir.
class KonumSeridiKatmani extends StatefulWidget {
  const KonumSeridiKatmani({super.key, required this.child});
  final Widget child;
  @override
  State<KonumSeridiKatmani> createState() => _KonumSeridiKatmaniState();
}

class _KonumSeridiKatmaniState extends State<KonumSeridiKatmani> {
  bool _kucuk = false;
  bool? _sonIcerde;
  Timer? _kucult;

  @override
  void initState() {
    super.initState();
    KonumIzleyici.canli.addListener(_degisti);
    _degisti();
  }

  @override
  void dispose() {
    _kucult?.cancel();
    KonumIzleyici.canli.removeListener(_degisti);
    super.dispose();
  }

  void _degisti() {
    final c = KonumIzleyici.canli.value;
    final icerde = c?.icerde;
    if (icerde != _sonIcerde) {
      _sonIcerde = icerde;
      _kucult?.cancel();
      _kucuk = false;
      // İçerideyken yer kaplamasın: 4 sn sonra ince çizgiye küçül.
      if (icerde == true) {
        _kucult = Timer(const Duration(seconds: 4), () {
          if (mounted) setState(() => _kucuk = true);
        });
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = KonumIzleyici.canli.value;
    final ust = MediaQuery.paddingOf(context).top;
    final gorunur = c != null;
    return Column(children: [
      AnimatedSize(
        duration: hareketAzalt(context) ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: gorunur ? _Serit(c: c, ust: ust, kucuk: _kucuk && c.icerde) : const SizedBox(width: double.infinity),
      ),
      Expanded(
        child: gorunur ? MediaQuery.removePadding(context: context, removeTop: true, child: widget.child) : widget.child,
      ),
    ]);
  }
}

class _Serit extends StatelessWidget {
  const _Serit({required this.c, required this.ust, required this.kucuk});
  final KonumCanli c;
  final double ust;
  final bool kucuk;

  @override
  Widget build(BuildContext context) {
    final yesil = const Color(0xFF6EE7B7);
    const sari = Color(0xFFFCD34D);
    final renk = c.icerde ? yesil : sari;
    final yazi = c.icerde ? 'İşletmedesiniz' : 'İşletme dışındasınız · ≈${mesafeYaz(c.mesafe)}';
    return Semantics(
      liveRegion: true,
      label: c.icerde ? 'İşletmedesiniz' : 'İşletme dışındasınız, yaklaşık ${c.mesafe} metre',
      child: AnnotatedRegion(
        value: durumCubugu,
        child: Container(
          width: double.infinity,
          color: Marka.lacivert0,
          padding: EdgeInsets.fromLTRB(16, ust + (kucuk ? 2 : 6), 16, kucuk ? 4 : 8),
          child: Center(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: kucuk ? 8 : 12, vertical: kucuk ? 2 : 6),
              decoration: BoxDecoration(
                color: renk.withValues(alpha: c.icerde ? .14 : .16),
                borderRadius: BorderRadius.circular(kucuk ? 8 : 12),
                border: Border.all(color: renk.withValues(alpha: .35)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(c.icerde ? Icons.location_on_rounded : Icons.wrong_location_rounded, size: kucuk ? 12 : 16, color: renk),
                SizedBox(width: kucuk ? 4 : 7),
                Flexible(
                  child: Text(
                    yazi,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: renk, fontSize: kucuk ? 11 : 13, fontWeight: FontWeight.w700),
                  ),
                ),
                if (!c.icerde && !kucuk) ...[
                  const SizedBox(width: 6),
                  Text('sınır ${mesafeYaz(c.yaricap)}', style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11.5, fontWeight: FontWeight.w500)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// QR okutucunun üstündeki uyarı: dışarıdaysan mesai/mola QR'ı reddedilir
/// (giriş QR'ı yine okutulabilir — engellemez).
class KonumQrUyarisi extends StatelessWidget {
  const KonumQrUyarisi({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<KonumCanli?>(
        valueListenable: KonumIzleyici.canli,
        builder: (_, c, _) {
          if (c == null || c.icerde) return const SizedBox.shrink();
          const sari = Color(0xFFFCD34D);
          return Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sari.withValues(alpha: .45)),
            ),
            child: Row(children: [
              const Icon(Icons.wrong_location_rounded, color: sari, size: 18),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'İşletme dışındasın (≈${mesafeYaz(c.mesafe)}) — mesai/mola QR\'ı yalnız işletmede okutulur',
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
            ]),
          );
        },
      );
}
