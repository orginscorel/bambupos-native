import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/bildirim.dart';
import '../core/guncelleme.dart';
import '../core/konum.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'ana_sayfa.dart';
import 'bildirimler.dart';
import 'davet.dart';
import 'destek.dart';
import 'gorevler.dart';
import 'hedefler.dart';
import 'konum_kapisi.dart';
import 'mesaim.dart';
import 'primler.dart';
import 'profil.dart';
import 'qr_okut.dart';
import 'vardiyam.dart';

/// Oturum açıldı → kabuğa geç (geri dönüşsüz).
void kabugaGec(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const Kabuk(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
    (_) => false,
  );
}

/// Yeni sayfa aç (iOS tarzı kaydırmalı geçiş).
Future<T?> git<T>(BuildContext context, Widget sayfa) => Navigator.of(context).push<T>(HizliRota(builder: (_) => sayfa));

/// Web adresini (bildirim bağlantısı) uygulama ekranına çevirir.
void adreseGit(String url) {
  final ctx = Uyg.navigator.currentContext;
  if (ctx == null) return;
  final yol = Uri.tryParse(url)?.path ?? url;
  final sekme = switch (yol) {
    '/panelim' => 0,
    '/gorevlerim' => 1,
    '/takvim' || '/vardiyam' || '/shift' => 2,
    '/profilim' => 3,
    _ => -1,
  };
  if (sekme >= 0) {
    Kabuk.sekme.value = sekme;
    return;
  }
  final Widget? s = switch (yol) {
    '/mesaim' => const MesaimEkrani(),
    '/hedeflerim' || '/raporlarim' => const HedeflerEkrani(),
    '/primlerim' => const PrimlerEkrani(),
    '/davet' => const DavetEkrani(),
    '/bildirimler' => const BildirimlerEkrani(),
    '/destek' => const DestekEkrani(),
    '/qr-okut' => const QrOkutEkrani(),
    _ => null,
  };
  if (s is QrOkutEkrani) {
    qrOkutAc(ctx);
  } else if (s != null) {
    git(ctx, s);
  }
}

/// QR okutucuyu açar — ÖNCE konum: servis kapalı / izin yoksa kamera açılmaz,
/// izin panosu çıkar (işletme kuralı kapalıysa "Şimdilik geç" de var).
/// Tüm girişler (alt çubuk, ana sayfa kartı, Mesaim, bildirim) bunu kullanır.
Future<void> qrOkutAc(BuildContext context, {bool kabuktan = false}) async {
  // Konsolda değişen mesai noktası (konum/yarıçap) beklemeden gelsin.
  unawaited(Uyg.hesapTazele(enAz: Duration.zero));
  if (!await qrOncesiKonum(context) || !context.mounted) return;
  if (!kabuktan) {
    await git(context, const QrOkutEkrani());
    return;
  }
  await Navigator.of(context).push(PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => const QrOkutEkrani(),
    transitionsBuilder: (_, a, _, child) {
      final e = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: e, child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(e), child: child));
    },
  ));
}

class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  static final sekme = ValueNotifier<int>(0);
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> with WidgetsBindingObserver {
  final _ziyaret = <int>{0};
  /// Mesai noktası ayarı konsoldan anlık gelsin diye önde iken dakikada bir hesap tazelenir (küçük istek).
  Timer? _hesapSaati;

  void _hesapSaatiKur() {
    _hesapSaati?.cancel();
    _hesapSaati = Timer.periodic(const Duration(seconds: 60), (_) {
      Uyg.hesapTazele(enAz: const Duration(seconds: 50));
      // Uygulama açık kaldıkça yeni sürüme de bakılır (Guncelleme.bak kendi 15 dk sınırını uygular).
      Guncelleme.bak();
    });
  }

  @override
  void initState() {
    super.initState();
    Kabuk.sekme.value = 0;
    BildirimMerkezi.acildi = adreseGit;
    BildirimMerkezi.basla();
    WidgetsBinding.instance.addObserver(this);
    KonumKapisi.etkin.value = true; // oturumlu alan: konum kuralı denetlensin
    // Canlı uzaklık (yalnız kural açık + izin tamam + önde iken akış çalışır).
    KonumIzleyici.tazele();
    KonumIzleyici.takipBaslat();
    _hesapSaatiKur();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) Guncelleme.bak();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      // Bildirim yoklaması yeniden (son yoklama eskiyse hemen).
      BildirimMerkezi.devam();
      // Uygulamaya dönünce yeni sürüm var mı tekrar bak (30 dk sınırı içinde).
      Guncelleme.bak();
      // Shift planı değişmiş olabilir: sesli hatırlatmaları tazele (Android, 15 dk sınırı).
      BildirimMerkezi.hatirlatmaTazele();
      // Konsolda değişen ayarlar (ör. mesai konum kuralı) hemen gelsin.
      Uyg.hesapTazele(enAz: const Duration(seconds: 10));
      _hesapSaatiKur();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      // Arka planda ön plan yoklaması yok (pil + veri). Android'de WorkManager,
      // iPhone'da APNs bildirimleri getirir.
      BildirimMerkezi.durdur();
      _hesapSaati?.cancel();
    }
  }

  @override
  void dispose() {
    _hesapSaati?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    KonumKapisi.etkin.value = false;
    KonumIzleyici.takipDurdur();
    BildirimMerkezi.durdur();
    super.dispose();
  }

  void _qr() {
    titret(1);
    qrOkutAc(context, kabuktan: true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Kabuk.sekme,
      builder: (_, s, _) {
        _ziyaret.add(s);
        return Scaffold(
          extendBody: true,
          body: Stack(children: [
            // Üstte canlı konum şeridi (tüm sekmeler); altında sekmeler.
            Positioned.fill(
              child: KonumSeridiKatmani(
                child: Stack(children: [
            for (var i = 0; i < 4; i++)
              Offstage(
                offstage: s != i,
                child: TickerMode(
                  enabled: s == i,
                  child: _ziyaret.contains(i)
                      ? AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: KeyedSubtree(key: ValueKey(i), child: _sayfa(i)),
                        )
                      : const SizedBox(),
                ),
              ),
                ]),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: PaAltCubuk.yukseklik + math.max(MediaQuery.paddingOf(context).bottom, 6.0) + 14,
              child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: const GuncellemeKarti())),
            ),
          ]),
          bottomNavigationBar: PaAltCubuk(secili: s, onSec: (i) => Kabuk.sekme.value = i, onQr: _qr),
        );
      },
    );
  }

  Widget _sayfa(int i) => switch (i) {
        0 => const AnaSayfa(),
        1 => const GorevlerEkrani(),
        2 => const VardiyamEkrani(),
        _ => const ProfilEkrani(),
      };
}

class PaAltCubuk extends StatelessWidget {
  const PaAltCubuk({super.key, required this.secili, required this.onSec, required this.onQr});
  final int secili;
  final ValueChanged<int> onSec;
  final VoidCallback onQr;

  static const _ogeler = [
    (Icons.home_rounded, 'Ana sayfa'),
    (Icons.assignment_turned_in_rounded, 'Görevler'),
    (null, 'QR Okut'),
    (Icons.calendar_month_rounded, 'Shift'),
    (Icons.person_rounded, 'Profil'),
  ];

  /// Çubuğun içerik yüksekliği (güvenli alan HARİÇ).
  static const yukseklik = 66.0;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    // ALTA YAPIŞIK (2026-10-27): eskiden yüzen kapsüldü ve güvenli alanın ÜSTÜNE
    // ayrıca pay bırakılıyordu → altta boşluk kalıyordu. Artık çubuk ekranın
    // altına oturur; iPhone ana ekran çizgisi payı çubuğun İÇİNDEDİR.
    final alt = MediaQuery.paddingOf(context).bottom;
    final ic = alt > 0 ? alt : 6.0;
    // Görsel sıra: 0,1,[qr],2,3 → sekme indeksinden yuva indeksine.
    final yuva = secili < 2 ? secili : secili + 1;
    return SizedBox(
      height: yukseklik + ic,
      child: LayoutBuilder(builder: (_, k) {
        final tamGenislik = k.maxWidth;
        final icGenislik = math.min(tamGenislik, 520.0);
        final sol = (tamGenislik - icGenislik) / 2;
        final w = icGenislik / 5;
        final hapW = (w - 16).clamp(40.0, 62.0);
        final cx = tamGenislik / 2;
        final kesim = _CubukKesim(cx: cx);
        return Stack(clipBehavior: Clip.none, children: [
          // Gölge — QR çentiğini de izler
          Positioned.fill(child: CustomPaint(painter: _CubukGolge(kesim: kesim, koyu: r.koyu))),
          // Zemin (çentikli şekil). Eskiden %90-94 opak renk + 22'lik bulanıklıktı:
          // o kadar opak zeminde bulanıklık neredeyse görünmüyordu ama her
          // kaydırma karesinde tüm çubuk alanını yeniden bulanıklaştırıyordu
          // (zayıf tablette takılmanın ana sebebi). Artık bulanıklık yok, zemin
          // tam opak → arkadan kayan yazı silik de olsa görünmez.
          Positioned.fill(
            child: ClipPath(
              clipper: kesim,
              child: ColoredBox(color: r.kart),
            ),
          ),
          // Üst kenar çizgisi
          Positioned.fill(child: CustomPaint(painter: _CubukKenar(kesim: kesim, renk: r.koyu ? const Color(0x33FFFFFF) : r.kenar))),
          // Seçili sekme vurgusu — simgenin arkasında kayar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: sol + w * yuva + (w - hapW) / 2,
            top: 8,
            width: hapW,
            height: 32,
            child: AnimatedOpacity(
              opacity: yuva == 2 ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Marka.morAcik.withValues(alpha: r.koyu ? .40 : .18),
                    Marka.mavi.withValues(alpha: r.koyu ? .32 : .13),
                  ]),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          // Sekmeler
          Positioned(
            left: sol,
            width: icGenislik,
            top: 0,
            height: yukseklik,
            child: Row(children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: i == 2
                      ? _QrYazi(yazi: _ogeler[2].$2, onTap: onQr)
                      : _Oge(
                          ikon: _ogeler[i].$1!,
                          yazi: _ogeler[i].$2,
                          aktif: i == yuva,
                          ev: i == 0,
                          onTap: () {
                            titret();
                            onSec(i < 2 ? i : i - 1);
                          },
                        ),
                ),
            ]),
          ),
          // Ortadaki QR düğmesi — çentiğe oturur, çubuktan yarı taşar
          Positioned(
            left: cx - _CubukKesim.dugme / 2,
            top: _CubukKesim.merkezY - _CubukKesim.dugme / 2,
            child: _QrDugme(onTap: onQr),
          ),
        ]);
      }),
    );
  }
}

/// Çubuk şekli: üst köşeler yuvarlak, ortada QR düğmesi için yumuşak omuzlu çentik.
class _CubukKesim extends CustomClipper<Path> {
  _CubukKesim({required this.cx});
  final double cx;

  static const dugme = 62.0; // QR düğmesi çapı
  static const merkezY = 2.0; // düğme merkezi (çubuk üst kenarına göre)
  static const bosluk = 6.0; // düğme ile çentik arası

  Path yol(Size s) {
    final govde = Path()
      ..addRRect(RRect.fromRectAndCorners(Offset.zero & s, topLeft: const Radius.circular(24), topRight: const Radius.circular(24)));
    final centik = const CircularNotchedRectangle().getOuterPath(
      Offset.zero & s,
      Rect.fromCircle(center: Offset(cx, merkezY), radius: dugme / 2 + bosluk),
    );
    return Path.combine(PathOperation.intersect, govde, centik);
  }

  @override
  Path getClip(Size size) => yol(size);

  @override
  bool shouldReclip(_CubukKesim old) => old.cx != cx;
}

class _CubukGolge extends CustomPainter {
  _CubukGolge({required this.kesim, required this.koyu});
  final _CubukKesim kesim;
  final bool koyu;
  @override
  void paint(Canvas c, Size s) {
    final p = kesim.yol(s);
    c.drawShadow(p.shift(const Offset(0, -2)), koyu ? Colors.black : const Color(0xFF1C1863), koyu ? 14 : 10, false);
  }

  @override
  bool shouldRepaint(_CubukGolge o) => o.koyu != koyu || o.kesim.cx != kesim.cx;
}

class _CubukKenar extends CustomPainter {
  _CubukKenar({required this.kesim, required this.renk});
  final _CubukKesim kesim;
  final Color renk;
  @override
  void paint(Canvas c, Size s) {
    c.drawPath(
      kesim.yol(s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = renk,
    );
  }

  @override
  bool shouldRepaint(_CubukKenar o) => o.renk != renk || o.kesim.cx != kesim.cx;
}

class _Oge extends StatelessWidget {
  const _Oge({required this.ikon, required this.yazi, required this.aktif, required this.onTap, this.ev = false});
  final IconData ikon;
  final String yazi;
  final bool aktif;
  final bool ev;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final renk = aktif ? r.birincil : r.soluk;
    return Semantics(
      button: true,
      selected: aktif,
      label: yazi,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
          const SizedBox(height: 12),
          AnimatedSlide(
            offset: Offset(0, aktif ? -.06 : 0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: AnimatedScale(
              scale: aktif ? 1.1 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: ev
                  ? IconTheme(data: IconThemeData(color: renk), child: PaMark(boyut: 24, tek: !aktif))
                  : Icon(ikon, color: renk, size: 24),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontFamily: 'Poppins', fontSize: 11, height: 1.1, fontWeight: aktif ? FontWeight.w700 : FontWeight.w500, color: renk),
            child: Text(yazi, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
          ),
        ]),
      ),
    );
  }
}

/// QR yuvası: düğme ayrı katmanda; burada yalnız yazı + geniş dokunma alanı.
class _QrYazi extends StatelessWidget {
  const _QrYazi({required this.yazi, required this.onTap});
  final String yazi;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: yazi,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
            const SizedBox(height: 46),
            Text(yazi,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, height: 1.1, fontWeight: FontWeight.w700, color: context.pa.metin)),
          ]),
        ),
      );
}

class _QrDugme extends StatefulWidget {
  const _QrDugme({required this.onTap});
  final VoidCallback onTap;
  @override
  State<_QrDugme> createState() => _QrDugmeState();
}

class _QrDugmeState extends State<_QrDugme> with SingleTickerProviderStateMixin {
  // Nefes: 2,8 sn halka açılır, 2,2 sn dinlenir. Eskiden durmadan dönüyordu →
  // alt çubuk HER sekmede ekranı saniyede 60 kez yeniden çizdiriyordu (pil).
  static const _dinlenme = Duration(milliseconds: 2200);
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _planla(_dinlenme);
    });
  Timer? _zaman;

  @override
  void initState() {
    super.initState();
    _planla(Duration.zero);
  }

  void _planla(Duration d) {
    _zaman?.cancel();
    _zaman = Timer(d, () {
      if (!mounted) return;
      if (!uygulamaOnde.value || hareketAzalt(context)) return _planla(_dinlenme);
      _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _zaman?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const d = _CubukKesim.dugme;
    return Basilir(
      onTap: widget.onTap,
      olcek: .88,
      titresim: false,
      child: SizedBox(
        width: d,
        height: d,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          // Nefes alan halka (ayrı katman: çubuğun geri kalanı yeniden boyanmaz)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = Curves.easeOut.transform(_c.value);
                // Dinlenirken (t = 1) halka tamamen saydam → çizilmez.
                return Container(
                  width: d + 16 * t,
                  height: d + 16 * t,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Marka.mor.withValues(alpha: (1 - t) * .55), width: 2)),
                );
              },
            ),
          ),
          Container(
            width: d,
            height: d,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: Marka.grad,
              boxShadow: [BoxShadow(color: Color(0xCC5443D2), blurRadius: 20, offset: Offset(0, 10), spreadRadius: -6)],
            ),
            child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 28),
          ),
        ]),
      ),
    );
  }
}
