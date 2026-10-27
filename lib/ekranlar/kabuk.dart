import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/bildirim.dart';
import '../core/canli.dart';
import '../core/durum.dart';
import '../core/guncelleme.dart';
import '../core/tema.dart';
import '../ortak/ust_serit.dart';
import 'daha_fazla.dart';
import 'ekip.dart';
import 'olustur.dart';
import 'ozet.dart';
import 'raporlar.dart';

/// Eşleme tamam → kabuğa geç (geri dönüşsüz).
void kabugaGec(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      transitionDuration: Hareket.kapali(context) ? Duration.zero : const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => const Kabuk(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
    (_) => false,
  );
}

/// Yeni sayfa aç (tema geçişiyle: PosSayfaGecisi / iOS'ta Cupertino).
Future<T?> git<T>(BuildContext context, Widget sayfa) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => sayfa));

class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  static final sekme = ValueNotifier<int>(0);
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _ziyaret = <int>{0};
  int _onceki = 0;

  /// Sekme değişiminde yeni sekme kısa bir kaymayla belirir (EkranGecisi'nin
  /// durum KORUYAN eşi: sekmeler Offstage'de yaşamaya devam eder).
  late final _gecis = AnimationController(vsync: this, duration: Hareket.orta, value: 1);

  @override
  void initState() {
    super.initState();
    Uyg.oturumlu = true;
    Kabuk.sekme.value = 0;
    Kabuk.sekme.addListener(_sekmeDegisti);
    BildirimMerkezi.basla();
    Canli.basla();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) Guncelleme.bak();
      });
    });
  }

  void _sekmeDegisti() {
    if (!mounted) return;
    if (Hareket.kapali(context)) {
      _gecis.value = 1;
    } else {
      _gecis.forward(from: 0);
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      Guncelleme.bak();
      BildirimMerkezi.yokla();
      Canli.basla();
      OzetEkrani.tazele.value++;
    } else if (s == AppLifecycleState.paused) {
      // Arka planda yoklama yok (pil + sunucu yükü).
      Canli.durdur();
    }
  }

  @override
  void dispose() {
    Kabuk.sekme.removeListener(_sekmeDegisti);
    WidgetsBinding.instance.removeObserver(this);
    BildirimMerkezi.durdur();
    Canli.durdur();
    _gecis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Kabuk.sekme.value;
    _ziyaret.add(s);
    final yon = s >= _onceki ? 1 : -1;
    _onceki = s;
    final e = CurvedAnimation(parent: _gecis, curve: Hareket.giris);
    return Scaffold(
      body: Stack(children: [
        for (var i = 0; i < 4; i++)
          Offstage(
            offstage: s != i,
            child: TickerMode(
              enabled: s == i,
              child: _ziyaret.contains(i)
                  ? FadeTransition(
                      opacity: s == i ? e : kAlwaysCompleteAnimation,
                      child: SlideTransition(
                        position: s == i ? Tween(begin: Offset(.03 * yon, 0), end: Offset.zero).animate(e) : const AlwaysStoppedAnimation(Offset.zero),
                        child: _sayfa(i),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: const GuncellemeKarti())),
        ),
      ]),
      bottomNavigationBar: AltCubuk(secili: s, onSec: (i) => Kabuk.sekme.value = i, onOlustur: () => olusturAc(context)),
    );
  }

  Widget _sayfa(int i) => switch (i) {
        0 => const OzetEkrani(),
        1 => const RaporlarEkrani(),
        2 => const EkipEkrani(),
        _ => const DahaFazlaEkrani(),
      };
}

/// ALT GEZİNME ÇUBUĞU: Özet · Raporlar · [+ Oluştur] · Ekip · Daha fazla.
///
/// Seçili sekmenin simgesinin arkasında 8 px köşeli yumuşak vurgu kayar ve
/// üstünde kısa bir çizgi belirir (hap yok). Ekip sekmesinde bekleyen talep
/// + geciken görev, Daha fazla'da okunmamış bildirim rozeti. Ortadaki
/// Oluştur düğmesi çubuktan biraz taşar ve hızlı eylem sayfasını açar.
class AltCubuk extends StatelessWidget {
  const AltCubuk({super.key, required this.secili, required this.onSec, this.onOlustur});
  final int secili;
  final ValueChanged<int> onSec;
  final VoidCallback? onOlustur;

  /// (simge, yazı) — personel uygulamasıyla aynı aile: dolu "rounded" simgeler;
  /// etkin/pasif yalnız renk + ölçekle ayrılır. Sekme 0..3; Oluştur yuva 2'de.
  static const ogeler = [
    (Icons.space_dashboard_rounded, 'Özet'),
    (Icons.bar_chart_rounded, 'Raporlar'),
    (Icons.groups_rounded, 'Ekip'),
    (Icons.grid_view_rounded, 'Daha fazla'),
  ];

  /// Çubuğun içerik yüksekliği (güvenli alan HARİÇ) — personelle aynı.
  static const yukseklik = 66.0;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final alt = MediaQuery.paddingOf(context).bottom;
    final ic = alt > 0 ? alt : 6.0;
    final kapali = Hareket.kapali(context);
    // Sekme → görsel yuva (Oluştur ortada).
    final yuva = secili < 2 ? secili : secili + 1;
    return SizedBox(
      height: yukseklik + ic,
      child: LayoutBuilder(builder: (_, k) {
        final tam = k.maxWidth;
        final icG = math.min(tam, 520.0);
        final sol = (tam - icG) / 2;
        final w = icG / 5;
        final vw = (w - 16).clamp(40.0, 62.0);
        final cx = tam / 2;
        final kesim = _CubukKesim(cx: cx);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(painter: _CubukGolge(kesim: kesim, koyu: r.koyu))),
          Positioned.fill(child: ClipPath(clipper: kesim, child: ColoredBox(color: r.kart))),
          Positioned.fill(child: CustomPaint(painter: _CubukKenar(kesim: kesim, renk: r.koyu ? const Color(0x33FFFFFF) : r.kenar))),
          // Seçili sekme vurgusu — simgenin arkasında kayar (personel ile aynı)
          AnimatedPositioned(
            duration: kapali ? Duration.zero : Hareket.orta,
            curve: Curves.easeOutBack,
            left: sol + w * yuva + (w - vw) / 2,
            top: 8,
            width: vw,
            height: 32,
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
          Positioned(
            left: sol,
            width: icG,
            top: 0,
            height: yukseklik,
            child: Row(children: [
              for (var y = 0; y < 5; y++)
                Expanded(
                  child: y == 2
                      ? _OlusturYazi(onTap: onOlustur)
                      : Builder(builder: (_) {
                          final i = y < 2 ? y : y - 1;
                          return _Oge(
                            ikon: ogeler[i].$1,
                            yazi: ogeler[i].$2,
                            aktif: i == secili,
                            rozet: i == 2 ? Canli.ekipRozet : i == 3 ? BildirimMerkezi.okunmamis : null,
                            rozetAdi: i == 2 ? 'bekleyen iş' : 'okunmamış bildirim',
                            onTap: () {
                              HapticFeedback.selectionClick();
                              onSec(i);
                            },
                          );
                        }),
                ),
            ]),
          ),
          // Ortadaki Oluştur düğmesi — çentiğe oturur, çubuktan yarı taşar
          Positioned(
            left: cx - _CubukKesim.dugme / 2,
            top: _CubukKesim.merkezY - _CubukKesim.dugme / 2,
            child: _OlusturDugme(onTap: onOlustur),
          ),
        ]);
      }),
    );
  }
}

/// Çubuk şekli: üst köşeler yuvarlak, ortada Oluştur için yumuşak omuzlu çentik
/// (personel uygulamasının alt çubuğuyla aynı geometri).
class _CubukKesim extends CustomClipper<Path> {
  _CubukKesim({required this.cx});
  final double cx;

  static const dugme = 62.0;
  static const merkezY = 2.0;
  static const bosluk = 6.0;

  Path yol(Size s) {
    final govde = Path()..addRRect(RRect.fromRectAndCorners(Offset.zero & s, topLeft: const Radius.circular(24), topRight: const Radius.circular(24)));
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
  void paint(Canvas c, Size s) => c.drawShadow(kesim.yol(s).shift(const Offset(0, -2)), koyu ? Colors.black : Marka.gece2, koyu ? 14 : 10, false);

  @override
  bool shouldRepaint(_CubukGolge o) => o.koyu != koyu || o.kesim.cx != kesim.cx;
}

class _CubukKenar extends CustomPainter {
  _CubukKenar({required this.kesim, required this.renk});
  final _CubukKesim kesim;
  final Color renk;
  @override
  void paint(Canvas c, Size s) => c.drawPath(
        kesim.yol(s),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = renk,
      );

  @override
  bool shouldRepaint(_CubukKenar o) => o.renk != renk || o.kesim.cx != kesim.cx;
}

class _Oge extends StatelessWidget {
  const _Oge({required this.ikon, required this.yazi, required this.aktif, required this.onTap, this.rozet, this.rozetAdi = ''});
  final IconData ikon;
  final String yazi;
  final bool aktif;
  final ValueListenable<int>? rozet;
  final String rozetAdi;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final renk = aktif ? r.birincil : r.soluk;
    final sure = Hareket.kapali(context) ? Duration.zero : Hareket.orta;
    Widget govde(int n) => Semantics(
          button: true,
          selected: aktif,
          label: n > 0 ? '$yazi, $n $rozetAdi' : yazi,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Column(children: [
              const SizedBox(height: 12),
              Stack(clipBehavior: Clip.none, children: [
                AnimatedSlide(
                  offset: Offset(0, aktif ? -.06 : 0),
                  duration: sure,
                  curve: Curves.easeOutBack,
                  child: AnimatedScale(
                    scale: aktif ? 1.1 : 1,
                    duration: sure,
                    curve: Curves.easeOutBack,
                    child: Icon(ikon, color: renk, size: 24),
                  ),
                ),
                if (n > 0) Positioned(top: -6, left: 15, child: Rozet(n, kenar: r.kart)),
              ]),
              const SizedBox(height: 10),
              AnimatedDefaultTextStyle(
                duration: sure,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, height: 1.1, fontWeight: aktif ? FontWeight.w700 : FontWeight.w500, color: renk),
                child: Text(yazi, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
            ]),
          ),
        );
    final rz = rozet;
    if (rz == null) return govde(0);
    return ValueListenableBuilder<int>(valueListenable: rz, builder: (_, n, _) => govde(n));
  }
}

/// Oluştur yuvası: düğme ayrı katmanda; burada yalnız yazı + geniş dokunma alanı.
class _OlusturYazi extends StatelessWidget {
  const _OlusturYazi({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Oluştur: görev, vardiya, mesai, izin',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  onTap!();
                },
          child: Column(children: [
            const SizedBox(height: 46),
            Text('Oluştur',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 11, height: 1.1, fontWeight: FontWeight.w700, color: context.pa.metin)),
          ]),
        ),
      );
}

/// Ortadaki yuvarlak Oluştur düğmesi (personeldeki QR düğmesinin eşi).
class _OlusturDugme extends StatelessWidget {
  const _OlusturDugme({required this.onTap});
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    const d = _CubukKesim.dugme;
    return ExcludeSemantics(
      child: Basilir(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onTap!();
              },
        titresim: false,
        olcek: .88,
        child: Container(
          width: d,
          height: d,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: Marka.grad,
            boxShadow: [BoxShadow(color: Color(0xCC5443D2), blurRadius: 20, offset: Offset(0, 10), spreadRadius: -6)],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
