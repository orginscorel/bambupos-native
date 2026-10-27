import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/tema.dart';

/* ───────────────────────── Dokunma geri bildirimi ───────────────────────── */

void titret([int tur = 0]) {
  switch (tur) {
    case 1:
      HapticFeedback.mediumImpact();
    case 2:
      HapticFeedback.heavyImpact();
    default:
      HapticFeedback.selectionClick();
  }
}

/// Basınca yaylanarak küçülen sarmalayıcı (web'deki .pa-press).
class Basilir extends StatefulWidget {
  const Basilir({super.key, required this.child, this.onTap, this.olcek = .96, this.titresim = true});
  final Widget child;
  final VoidCallback? onTap;
  final double olcek;
  final bool titresim;

  @override
  State<Basilir> createState() => _BasilirState();
}

class _BasilirState extends State<Basilir> {
  bool _bas = false;

  @override
  Widget build(BuildContext context) {
    final aktif = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: aktif ? (_) => setState(() => _bas = true) : null,
      onTapCancel: aktif ? () => setState(() => _bas = false) : null,
      onTapUp: aktif ? (_) => setState(() => _bas = false) : null,
      onTap: aktif
          ? () {
              if (widget.titresim) titret();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _bas ? widget.olcek : 1,
        duration: Duration(milliseconds: _bas ? 90 : 380),
        curve: _bas ? Curves.easeOut : Curves.elasticOut,
        child: AnimatedOpacity(opacity: aktif ? 1 : .5, duration: const Duration(milliseconds: 200), child: widget.child),
      ),
    );
  }
}

/* ───────────────────────── Kart / simge ───────────────────────── */

class PaKart extends StatelessWidget {
  const PaKart({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.radius = 24, this.renk, this.gradient});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? renk;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final kutu = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (renk ?? r.kart) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: gradient == null ? Border.all(color: r.kenar) : null,
        boxShadow: r.golge,
      ),
      child: child,
    );
    return onTap == null ? kutu : Basilir(onTap: onTap, child: kutu);
  }
}

class PaIkon extends StatelessWidget {
  const PaIkon(this.ikon, {super.key, this.boyut = 44, this.zemin, this.renk, this.grad = false, this.ikonBoyut});
  final IconData ikon;
  final double boyut;
  final Color? zemin;
  final Color? renk;
  final bool grad;
  final double? ikonBoyut;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    // Koyu temada açık pastel zeminler parlıyordu: zemin, simge renginin saydam tonu olur.
    final z = r.koyu && renk != null && zemin != null ? renk!.withValues(alpha: .18) : (zemin ?? r.birincilYumusak);
    final ikonRenk = r.koyu && renk != null ? Color.lerp(renk, Colors.white, .25)! : (renk ?? r.birincil);
    return Container(
      width: boyut,
      height: boyut,
      decoration: BoxDecoration(
        color: grad ? null : z,
        gradient: grad ? Marka.grad : null,
        borderRadius: BorderRadius.circular(boyut * .34),
        boxShadow: grad ? const [BoxShadow(color: Color(0x995443D2), blurRadius: 18, offset: Offset(0, 8), spreadRadius: -8)] : null,
      ),
      child: Icon(ikon, size: ikonBoyut ?? boyut * .46, color: grad ? Colors.white : ikonRenk),
    );
  }
}

/// Marka geçişli büyük düğme.
class GradDugme extends StatelessWidget {
  const GradDugme({super.key, required this.yazi, this.ikon, this.onTap, this.yukleniyor = false, this.yukseklik = 54, this.gradient = Marka.grad});
  final String yazi;
  final IconData? ikon;
  final VoidCallback? onTap;
  final bool yukleniyor;
  final double yukseklik;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return Basilir(
      onTap: yukleniyor ? null : onTap,
      child: Container(
        height: yukseklik,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(color: Color(0x885443D2), blurRadius: 22, offset: Offset(0, 12), spreadRadius: -12)],
        ),
        child: Center(
          child: yukleniyor
              ? const Yukleyici(boyut: 24)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (ikon != null) ...[Icon(ikon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                  Text(yazi, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.5)),
                ]),
        ),
      ),
    );
  }
}

/// Yumuşak ikincil düğme.
class YumusakDugme extends StatelessWidget {
  const YumusakDugme({super.key, required this.yazi, this.ikon, this.onTap, this.renk, this.zemin});
  final String yazi;
  final IconData? ikon;
  final VoidCallback? onTap;
  final Color? renk;
  final Color? zemin;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Basilir(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(color: zemin ?? r.birincilYumusak, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (ikon != null) ...[Icon(ikon, color: renk ?? r.birincil, size: 18), const SizedBox(width: 6)],
          Text(yazi, style: TextStyle(color: renk ?? r.birincil, fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      ),
    );
  }
}

/* ───────────────────────── Yükleme ───────────────────────── */

/// Dönen gradyan yay (web .pa-yukleyici).
class Yukleyici extends StatefulWidget {
  const Yukleyici({super.key, this.boyut = 28, this.renk = Colors.white});
  final double boyut;
  final Color renk;
  @override
  State<Yukleyici> createState() => _YukleyiciState();
}

class _YukleyiciState extends State<Yukleyici> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _c,
        child: CustomPaint(size: Size.square(widget.boyut), painter: _YayCizer(widget.renk)),
      );
}

class _YayCizer extends CustomPainter {
  _YayCizer(this.renk);
  final Color renk;
  @override
  void paint(Canvas c, Size s) {
    final rect = Offset.zero & s;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .13
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(colors: [renk.withValues(alpha: 0), renk]).createShader(rect);
    c.drawArc(rect.deflate(s.width * .08), 0, math.pi * 1.6, false, p);
  }

  @override
  bool shouldRepaint(_YayCizer o) => o.renk != renk;
}

/// Parlayan iskelet kutusu.
class Iskelet extends StatefulWidget {
  const Iskelet({super.key, this.yukseklik = 16, this.genislik, this.radius = 12});
  final double yukseklik;
  final double? genislik;
  final double radius;
  @override
  State<Iskelet> createState() => _IskeletState();
}

class _IskeletState extends State<Iskelet> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        height: widget.yukseklik,
        width: widget.genislik,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1 - 2 * (1 - _c.value) + 2, 0),
            end: Alignment(1 - 2 * (1 - _c.value) + 2, 0),
            colors: [r.ic, Color.lerp(r.ic, r.kart, .6)!, r.ic],
          ),
        ),
      ),
    );
  }
}

/* ───────────────────────── Giriş animasyonu ───────────────────────── */

/// Alttan süzülerek beliren içerik (web .pa-in-up / .pa-stagger).
class Belir extends StatefulWidget {
  const Belir({super.key, required this.child, this.gecikme = 0, this.kayma = 18});
  final Widget child;
  final int gecikme;
  final double kayma;
  @override
  State<Belir> createState() => _BelirState();
}

class _BelirState extends State<Belir> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.gecikme), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = CurvedAnimation(parent: _c, curve: const Cubic(.22, 1, .36, 1));
    return AnimatedBuilder(
      animation: e,
      builder: (_, child) => Opacity(
        opacity: e.value,
        child: Transform.translate(offset: Offset(0, widget.kayma * (1 - e.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Sayarak yükselen rakam.
class Sayac extends StatelessWidget {
  const Sayac({super.key, required this.deger, required this.yaz, this.stil});
  final num deger;
  final String Function(num) yaz;
  final TextStyle? stil;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: deger.toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(yaz(v), style: stil),
      );
}

/* ───────────────────────── Marka işareti ───────────────────────── */

class PaMark extends StatelessWidget {
  const PaMark({super.key, this.boyut = 40, this.tek = false});
  final double boyut;
  final bool tek;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(boyut), painter: _MarkCizer(tek ? (IconTheme.of(context).color ?? Colors.grey) : null));
}

class _MarkCizer extends CustomPainter {
  _MarkCizer(this.tekRenk);
  final Color? tekRenk;
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 64;
    c.scale(k);
    final rr = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(16));
    if (tekRenk == null) {
      c.drawRRect(rr, Paint()..shader = Marka.grad.createShader(const Rect.fromLTWH(0, 0, 64, 64)));
    } else {
      c.drawRRect(rr.deflate(2), Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = tekRenk!);
    }
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeJoin = StrokeJoin.round
      ..color = tekRenk ?? Colors.white;
    for (final o in const [Offset(14, 14), Offset(35, 14), Offset(14, 35)]) {
      c.drawRRect(RRect.fromRectAndRadius(o & const Size(12, 12), const Radius.circular(3)), kalem);
    }
    if (tekRenk == null) {
      c.drawCircle(const Offset(45, 45), 11, Paint()..color = Marka.gok);
      c.drawCircle(const Offset(45, 45), 11, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
      c.drawCircle(const Offset(45, 42), 3.2, Paint()..color = Colors.white);
      c.drawPath(Path()..addArc(const Rect.fromLTWH(39.5, 45, 11, 11), math.pi, math.pi), Paint()..color = Colors.white);
    } else {
      c.drawCircle(const Offset(43, 39), 4, Paint()..color = tekRenk!);
      c.drawPath(Path()..addArc(const Rect.fromLTWH(35, 43, 16, 16), math.pi, math.pi), Paint()..color = tekRenk!);
    }
  }

  @override
  bool shouldRepaint(_MarkCizer o) => o.tekRenk != tekRenk;
}

/* ───────────────────────── Gece laciverti üst alan ───────────────────────── */

/// Hareketli ışık katmanları + ince ızgara (web .p-hero).
class Aurora extends StatefulWidget {
  const Aurora({super.key, required this.child});
  final Widget child;
  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: Marka.hero),
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => CustomPaint(painter: _AuroraCizer(Curves.easeInOut.transform(_c.value))),
            ),
          ),
          widget.child,
        ]),
      );
}

class _AuroraCizer extends CustomPainter {
  _AuroraCizer(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    void blob(Offset m, double r, Color renk) {
      c.drawCircle(m, r, Paint()..shader = RadialGradient(colors: [renk, renk.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: m, radius: r)));
    }

    blob(Offset(s.width * (.78 + .05 * t), s.height * (.15 - .05 * t)), s.width * .55, Marka.mor.withValues(alpha: .7));
    blob(Offset(s.width * (.12 - .04 * t), s.height * (.85 + .04 * t)), s.width * .5, Marka.mavi.withValues(alpha: .5));
    blob(Offset(s.width * (.6 + .06 * t), s.height * .9), s.width * .35, Marka.gok.withValues(alpha: .28));

    final izgara = Paint()..color = Colors.white.withValues(alpha: .045);
    for (double x = 0; x < s.width; x += 22) {
      c.drawLine(Offset(x, 0), Offset(x, s.height * .85), izgara);
    }
    for (double y = 0; y < s.height * .85; y += 22) {
      c.drawLine(Offset(0, y), Offset(s.width, y), izgara..color = Colors.white.withValues(alpha: .045 * (1 - y / s.height)));
    }
  }

  @override
  bool shouldRepaint(_AuroraCizer o) => o.t != t;
}

/// Cam efektli koyu kart (üst alandaki kutular).
class Cam extends StatelessWidget {
  const Cam({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.radius = 24});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withValues(alpha: .11), Colors.white.withValues(alpha: .04)],
              ),
            ),
            child: child,
          ),
        ),
      );
}

/* ───────────────────────── Sayfa iskeleti ───────────────────────── */

/// İkincil sayfalar: lacivert başlık çubuğu + üstüne binen yuvarlak içerik.
class PaSayfa extends StatelessWidget {
  const PaSayfa({super.key, required this.baslik, required this.govde, this.altBaslik, this.geri = true, this.eylem, this.yenile});
  final String baslik;
  final String? altBaslik;
  final Widget govde;
  final bool geri;
  final Widget? eylem;
  final Future<void> Function()? yenile;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final ust = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion(
      value: durumCubugu,
      child: Scaffold(
        backgroundColor: r.zemin,
        body: Column(children: [
          Aurora(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, ust + 6, 16, 34),
              child: SizedBox(
                height: 52,
                child: Row(children: [
                  SizedBox(
                    width: 46,
                    child: geri && Navigator.of(context).canPop()
                        ? Basilir(
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle),
                              child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                            ),
                          )
                        : const PaMark(boyut: 38),
                  ),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(19, renk: Colors.white)),
                      if (altBaslik != null)
                        Text(altBaslik!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: .6))),
                    ]),
                  ),
                  SizedBox(width: 46, child: Align(alignment: Alignment.centerRight, child: eylem)),
                ]),
              ),
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: BoxDecoration(color: r.zemin, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                clipBehavior: Clip.antiAlias,
                child: yenile == null ? govde : RefreshIndicator(onRefresh: yenile!, color: Marka.mor, child: govde),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Sayfa gövdesi için kaydırılabilir liste (alt çubuk boşluğu dahil).
class Kaydir extends StatelessWidget {
  const Kaydir({super.key, required this.children, this.altBosluk = 120});
  final List<Widget> children;
  final double altBosluk;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 20, 16, altBosluk + MediaQuery.paddingOf(context).bottom),
        children: [
          for (var i = 0; i < children.length; i++) Belir(gecikme: math.min(i, 6) * 50, child: children[i]),
        ],
      );
}

/* ───────────────────────── Alttan pano ───────────────────────── */

Future<T?> panoAc<T>(BuildContext context, {String? baslik, String? alt, required Widget Function(BuildContext) icerik}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C09081E),
    builder: (ctx) {
      final r = ctx.pa;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .9),
          decoration: BoxDecoration(color: r.kart, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.paddingOf(ctx).bottom),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: r.kenar, borderRadius: BorderRadius.circular(9)))),
              const SizedBox(height: 14),
              if (baslik != null) Text(baslik, style: gosterim(21, renk: r.metin)),
              if (alt != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(alt, style: TextStyle(color: r.soluk, fontSize: 13.5))),
              if (baslik != null) const SizedBox(height: 16),
              icerik(ctx),
            ]),
          ),
        ),
      );
    },
  );
}

/* ───────────────────────── Bildirim baloncuğu (toast) ───────────────────────── */

enum BildirimTur { basari, hata, uyari, bilgi }

void bildir(String baslik, {String? mesaj, BildirimTur tur = BildirimTur.basari}) {
  final ov = _overlay;
  if (ov == null) return;
  late OverlayEntry e;
  e = OverlayEntry(builder: (_) => _Baloncuk(baslik: baslik, mesaj: mesaj, tur: tur, kapat: () => e.remove()));
  ov.insert(e);
  if (tur == BildirimTur.hata) titret(1);
}

OverlayState? _overlay;
void bildirimKatmani(OverlayState o) => _overlay = o;

class _Baloncuk extends StatefulWidget {
  const _Baloncuk({required this.baslik, this.mesaj, required this.tur, required this.kapat});
  final String baslik;
  final String? mesaj;
  final BildirimTur tur;
  final VoidCallback kapat;
  @override
  State<_Baloncuk> createState() => _BaloncukState();
}

class _BaloncukState extends State<_Baloncuk> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.tur == BildirimTur.hata ? 4500 : 3000), _git);
  }

  Future<void> _git() async {
    if (!mounted) return;
    await _c.reverse();
    widget.kapat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (renk, ikon) = switch (widget.tur) {
      BildirimTur.basari => (Marka.zumrut, Icons.check_circle_rounded),
      BildirimTur.hata => (Marka.gul, Icons.error_rounded),
      BildirimTur.uyari => (Marka.kehribar, Icons.warning_rounded),
      BildirimTur.bilgi => (Marka.mor, Icons.notifications_rounded),
    };
    final e = CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return Positioned(
      left: 14,
      right: 14,
      top: MediaQuery.paddingOf(context).top + 8,
      child: AnimatedBuilder(
        animation: e,
        builder: (_, child) => Transform.translate(offset: Offset(0, -90 * (1 - e.value)), child: Opacity(opacity: _c.value, child: child)),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _git,
            onVerticalDragEnd: (_) => _git(),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xF2141236),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: .1)),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14))],
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: renk.withValues(alpha: .18), borderRadius: BorderRadius.circular(12)),
                  child: Icon(ikon, color: renk, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.baslik, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if (widget.mesaj != null)
                      Text(widget.mesaj!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12.5)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/* ───────────────────────── Boş durum ───────────────────────── */

class BosDurum extends StatelessWidget {
  const BosDurum({super.key, required this.ikon, required this.baslik, this.aciklama, this.eylem});
  final IconData ikon;
  final String baslik;
  final String? aciklama;
  final Widget? eylem;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaKart(
      padding: const EdgeInsets.fromLTRB(24, 34, 24, 34),
      child: Column(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: .4, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: PaIkon(ikon, boyut: 72),
        ),
        const SizedBox(height: 14),
        Text(baslik, textAlign: TextAlign.center, style: gosterim(19, renk: r.metin)),
        if (aciklama != null) ...[
          const SizedBox(height: 6),
          Text(aciklama!, textAlign: TextAlign.center, style: TextStyle(color: r.soluk, fontSize: 13.5, height: 1.4)),
        ],
        if (eylem != null) ...[const SizedBox(height: 16), eylem!],
      ]),
    );
  }
}

/// Yükleme hatası için dostça boş durum (bağlantı yok / özellik henüz
/// sunucuda yok (404) / yetki yok) + "Tekrar dene".
class HataDurum extends StatelessWidget {
  const HataDurum({super.key, required this.hata, required this.onTekrar});
  final ApiHata hata;
  final VoidCallback onTekrar;
  @override
  Widget build(BuildContext context) {
    final (ikon, baslik, aciklama) = hata.baglantiYok
        ? (Icons.wifi_off_rounded, 'Bağlantı kurulamadı', hata.mesaj)
        : hata.kod == 404
            ? (Icons.hourglass_empty_rounded, 'Bu bölüm henüz hazır değil', 'Sunucu güncellemesi tamamlanınca burada görünecek.')
            : hata.yetkiYok
                ? (Icons.lock_rounded, 'Bu bölüm için yetkin yok', 'Yöneticinden yetki isteyebilirsin.')
                : (Icons.cloud_off_rounded, 'Yüklenemedi', hata.mesaj);
    return BosDurum(
      ikon: ikon,
      baslik: baslik,
      aciklama: aciklama,
      eylem: YumusakDugme(yazi: 'Tekrar dene', ikon: Icons.refresh_rounded, onTap: onTekrar),
    );
  }
}

/// Bölüm başlığı (büyük harf, silik).
class BolumBasligi extends StatelessWidget {
  const BolumBasligi(this.yazi, {super.key});
  final String yazi;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
        child: Text(yazi.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: context.pa.silik)),
      );
}

/// Liste satırı (profil menüsü vb.).
class Satir extends StatelessWidget {
  const Satir({super.key, required this.ikon, required this.baslik, this.alt, this.onTap, this.sag, this.ikonZemin, this.ikonRenk, this.grad = false, this.baslikRenk});
  final IconData ikon;
  final String baslik;
  final String? alt;
  final VoidCallback? onTap;
  final Widget? sag;
  final Color? ikonZemin;
  final Color? ikonRenk;
  final bool grad;
  final Color? baslikRenk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              titret();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          PaIkon(ikon, boyut: 42, zemin: ikonZemin, renk: ikonRenk, grad: grad),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(baslik, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: baslikRenk ?? r.metin)),
              if (alt != null) Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk)),
            ]),
          ),
          sag ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: r.silik) : const SizedBox()),
        ]),
      ),
    );
  }
}

/// Satırları kart içinde ayraçla dizer.
class SatirGrubu extends StatelessWidget {
  const SatirGrubu(this.satirlar, {super.key});
  final List<Widget> satirlar;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaKart(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(children: [
          for (var i = 0; i < satirlar.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: r.kenar),
            satirlar[i],
          ],
        ]),
      ),
    );
  }
}
