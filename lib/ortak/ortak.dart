import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/tema.dart';

/* ───────────────────────── Ön plan / hareket azaltma ───────────────────────── */

/// Uygulama ön planda mı? (tek yaşam döngüsü dinleyicisi; zamanlayıcılar ve
/// yoklamalar arka planda boşuna CPU/ağ harcamasın diye buna bakar.)
final ValueNotifier<bool> uygulamaOnde = () {
  final n = ValueNotifier<bool>(true);
  try {
    WidgetsBinding.instance.addObserver(_OnPlanGozcu(n));
  } catch (_) {
    // Bağlama henüz kurulmadıysa ön planda say.
  }
  return n;
}();

class _OnPlanGozcu with WidgetsBindingObserver {
  _OnPlanGozcu(this.n);
  final ValueNotifier<bool> n;
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) => n.value = s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
}

/// Sistem "hareketi azalt" açık mı?
bool hareketAzalt(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Bu ekran şu an görünür ve uygulama ön planda mı? (gizli sekmede /
/// arka planda zamanlayıcı yenilemesi yapılmasın.)
bool ekranGorunur(BuildContext context) => uygulamaOnde.value && TickerMode.valuesOf(context).enabled;

/// Hızlı sayfa geçişi: iOS kaydırması (geri kaydırma hareketi dahil) ama
/// 500 ms yerine 250 ms; "hareketi azalt" açıksa anında.
class HizliRota<T> extends CupertinoPageRoute<T> {
  HizliRota({required super.builder, super.settings});
  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);
  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      hareketAzalt(context) ? child : super.buildTransitions(context, animation, secondaryAnimation, child);
}

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

/* ───────────────────────── Düğmeler ───────────────────────── */

/// Basılı durumunu çocuğa veren dokunma algılayıcı (Basilir'in kardeşi):
/// ölçek + titreşim aynı, ek olarak `basili` ile gölge/zemin değişir.
class _BasmaKatmani extends StatefulWidget {
  const _BasmaKatmani({required this.builder, this.onTap, this.olcek = .97, this.soluk = true});
  final Widget Function(BuildContext, bool basili) builder;
  final VoidCallback? onTap;
  final double olcek;
  final bool soluk;
  @override
  State<_BasmaKatmani> createState() => _BasmaKatmaniState();
}

class _BasmaKatmaniState extends State<_BasmaKatmani> {
  bool _bas = false;
  void _ayarla(bool v) {
    if (_bas != v) setState(() => _bas = v);
  }

  @override
  Widget build(BuildContext context) {
    final aktif = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: aktif,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: aktif ? (_) => _ayarla(true) : null,
        onTapCancel: aktif ? () => _ayarla(false) : null,
        onTapUp: aktif ? (_) => _ayarla(false) : null,
        onTap: aktif
            ? () {
                titret();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _bas ? widget.olcek : 1,
          duration: Duration(milliseconds: _bas ? 90 : 320),
          curve: _bas ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: aktif || !widget.soluk ? 1 : .5,
            duration: const Duration(milliseconds: 200),
            child: widget.builder(context, _bas),
          ),
        ),
      ),
    );
  }
}

Color _gradOrta(Gradient g) => g.colors.length > 1 ? g.colors[g.colors.length ~/ 2] : g.colors.first;

/// Marka geçişli ANA düğme: üstte ince parlaklık, 1 px açık iç kenar,
/// renkli yumuşak ışıma (basınca içe çöker), ara sıra süzülen ışık şeridi.
class GradDugme extends StatefulWidget {
  const GradDugme({
    super.key,
    required this.yazi,
    this.ikon,
    this.onTap,
    this.yukleniyor = false,
    this.yukseklik = 54,
    this.gradient = Marka.grad,
    this.parilti = true,
    this.sonIkon,
  });
  final String yazi;
  final IconData? ikon;
  final VoidCallback? onTap;
  final bool yukleniyor;
  final double yukseklik;
  final Gradient gradient;
  /// Yavaş ışık süzülmesi (tek AnimationController, yalnız boyama).
  final bool parilti;
  /// Yazının sağındaki simge (ör. ok).
  final IconData? sonIkon;

  @override
  State<GradDugme> createState() => _GradDugmeState();
}

class _GradDugmeState extends State<GradDugme> with TickerProviderStateMixin {
  // Işık şeridi: 3,64 sn bekler, 1,56 sn süzülür (eski 5,2 sn döngüyle aynı
  // ritim). Beklerken ANİMASYON YOK → ekran boşta kare çizmez (pil). Eskiden
  // denetleyici sürekli dönüyordu; bekleme sırasında da saniyede 60 kare.
  static const _bekleme = Duration(milliseconds: 3640);
  static const _supurme = Duration(milliseconds: 1560);
  AnimationController? _c;
  Timer? _zaman;

  bool get _parlasin => widget.parilti && widget.onTap != null && !widget.yukleniyor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ayarla();
  }

  @override
  void didUpdateWidget(GradDugme o) {
    super.didUpdateWidget(o);
    _ayarla();
  }

  void _ayarla() {
    final iste = _parlasin && !hareketAzalt(context);
    if (iste && _c == null) {
      _c = AnimationController(vsync: this, duration: _supurme)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _planla();
        });
      _planla();
    } else if (!iste && _c != null) {
      _zaman?.cancel();
      _zaman = null;
      _c!.dispose();
      _c = null;
    }
  }

  void _planla() {
    _zaman?.cancel();
    _zaman = Timer(_bekleme, () {
      final c = _c;
      if (!mounted || c == null) return;
      // Gizli sekmede / arka planda süzülme yok; sonraki tura kalsın.
      if (!ekranGorunur(context)) return _planla();
      c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _zaman?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final isik = _gradOrta(widget.gradient);
    const rad = 18.0;
    return _BasmaKatmani(
      onTap: widget.yukleniyor ? null : widget.onTap,
      soluk: !widget.yukleniyor,
      builder: (_, basili) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        height: widget.yukseklik,
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: BorderRadius.circular(rad),
          boxShadow: [
            BoxShadow(
              color: isik.withValues(alpha: r.koyu ? .55 : .5),
              blurRadius: basili ? 12 : 26,
              offset: Offset(0, basili ? 5 : 12),
              spreadRadius: basili ? -8 : -10,
            ),
            BoxShadow(color: Marka.lacivert0.withValues(alpha: r.koyu ? .5 : .14), blurRadius: basili ? 2 : 4, offset: Offset(0, basili ? 1 : 2)),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(rad),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rad),
          child: Stack(fit: StackFit.expand, children: [
            // Üst parlaklık (cam hissi) + basınca hafif koyulaşma
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: basili
                      ? [Colors.black.withValues(alpha: .06), Colors.black.withValues(alpha: .12)]
                      : [Colors.white.withValues(alpha: .24), Colors.white.withValues(alpha: .04), Colors.black.withValues(alpha: .06)],
                  stops: basili ? null : const [0, .5, 1],
                ),
              ),
            ),
            if (_c != null)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _c!,
                  builder: (_, _) {
                    // Beklerken (denetleyici durgun) şerit görünmez; süzülürken soldan sağa.
                    final c = _c!;
                    final x = c.isAnimating ? -2.0 + c.value * 4.0 : -2.0;
                    return FractionalTranslation(
                      translation: Offset(x * .5, 0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: const Alignment(-1, -.4),
                            end: const Alignment(1, .4),
                            colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .2), Colors.white.withValues(alpha: 0)],
                            stops: const [.38, .5, .62],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Center(
              child: widget.yukleniyor
                  ? const Yukleyici(boyut: 24)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      // Dar yerlerde (iki düğme yan yana) kesilmek yerine hafifçe küçülür.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.ikon != null) ...[Icon(widget.ikon, color: Colors.white, size: 20), const SizedBox(width: 10)],
                        Text(widget.yazi,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15.5,
                                letterSpacing: .15,
                                shadows: [Shadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 1))],
                              )),
                        if (widget.sonIkon != null) ...[const SizedBox(width: 8), Icon(widget.sonIkon, color: Colors.white, size: 18)],
                      ]),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// İkincil düğme: marka tonlu yüzey + saç teli kenar; basınca zemin koyulaşır.
/// `zemin` doygun bir renk (ör. Marka.gul) ve `renk` beyaz verilirse dolu
/// tehlike/onay düğmesi gibi davranır.
class YumusakDugme extends StatelessWidget {
  const YumusakDugme({super.key, required this.yazi, this.ikon, this.onTap, this.renk, this.zemin, this.yukseklik = 50, this.yukleniyor = false});
  final String yazi;
  final IconData? ikon;
  final VoidCallback? onTap;
  final Color? renk;
  final Color? zemin;
  final double yukseklik;
  final bool yukleniyor;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final on = renk ?? r.birincil;
    final z = zemin ?? r.birincilYumusak;
    // Dolu (doygun zemin + açık yazı) mı?
    final dolu = on.computeLuminance() > .7 && z.computeLuminance() < .5 && z.a > .9;
    final kenar = dolu ? Colors.white.withValues(alpha: .18) : on.withValues(alpha: r.koyu ? .24 : .16);
    return _BasmaKatmani(
      onTap: yukleniyor ? null : onTap,
      soluk: !yukleniyor,
      builder: (_, basili) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: yukseklik,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: basili ? Color.alphaBlend(on.withValues(alpha: dolu ? .0 : .08), z) : z,
          gradient: dolu
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color.lerp(z, Colors.white, basili ? 0 : .1)!, Color.lerp(z, Colors.black, basili ? .14 : .06)!],
                )
              : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kenar),
          boxShadow: dolu && !basili ? [BoxShadow(color: z.withValues(alpha: .4), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -10)] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (yukleniyor)
            Yukleyici(boyut: 20, renk: on)
          else ...[
            if (ikon != null) ...[Icon(ikon, color: on, size: 19), const SizedBox(width: 8)],
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(yazi, maxLines: 1, style: TextStyle(color: on, fontWeight: FontWeight.w600, fontSize: 14.5, letterSpacing: .1)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Metin düğmesi ("Vazgeç", "Geçmiş" …). `kucuk` → başlık satırı içi
/// kompakt tonlu düğme; değilse tam boy (48) sade düğme.
class PaMetinDugme extends StatelessWidget {
  const PaMetinDugme({super.key, required this.yazi, this.onTap, this.ikon, this.renk, this.kucuk = false, this.sonIkon});
  final String yazi;
  final VoidCallback? onTap;
  final IconData? ikon;
  final IconData? sonIkon;
  final Color? renk;
  final bool kucuk;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final on = renk ?? (kucuk ? r.birincil : r.soluk);
    return _BasmaKatmani(
      onTap: onTap,
      olcek: .95,
      builder: (_, basili) => AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        height: kucuk ? 34 : 48,
        padding: EdgeInsets.symmetric(horizontal: kucuk ? 12 : 16),
        decoration: BoxDecoration(
          color: kucuk ? (basili ? on.withValues(alpha: .18) : on.withValues(alpha: r.koyu ? .14 : .09)) : (basili ? r.ic : Colors.transparent),
          borderRadius: BorderRadius.circular(kucuk ? 12 : 16),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          if (ikon != null) ...[Icon(ikon, size: kucuk ? 15 : 18, color: on), SizedBox(width: kucuk ? 5 : 8)],
          Text(yazi, style: TextStyle(color: on, fontWeight: FontWeight.w600, fontSize: kucuk ? 12.5 : 14.5)),
          if (sonIkon != null) ...[const SizedBox(width: 3), Icon(sonIkon, size: kucuk ? 16 : 18, color: on)],
        ]),
      ),
    );
  }
}

/// Kayan sekme seçici (Görevlerim, Shift, Ekibim aynı biçim): saç teli
/// kenarlı yüzey, ışımalı geçişli gösterge, isteğe bağlı sayı rozetleri.
class PaSegment extends StatelessWidget {
  const PaSegment({super.key, required this.secili, required this.ogeler, required this.onSec, this.sayilar, this.yukseklik = 52});
  final int secili;
  final List<String> ogeler;
  final List<int?>? sayilar;
  final ValueChanged<int> onSec;
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Container(
      height: yukseklik,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(18), border: Border.all(color: r.kenar), boxShadow: r.golge),
      child: LayoutBuilder(builder: (_, k) {
        final w = k.maxWidth / ogeler.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: w * secili,
            top: 0,
            bottom: 0,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: Marka.grad,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Marka.mor.withValues(alpha: .45), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)],
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: .18)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: .2), Colors.white.withValues(alpha: 0)],
                    stops: const [0, .6],
                  ),
                ),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < ogeler.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: secili == i,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (secili == i) return;
                      titret();
                      onSec(i);
                    },
                    child: Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(fontFamily: 'Poppins', fontWeight: secili == i ? FontWeight.w700 : FontWeight.w600, fontSize: 13.5, color: secili == i ? Colors.white : r.soluk),
                            child: Text(ogeler[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                        if (sayilar != null && i < sayilar!.length && sayilar![i] != null) ...[
                          const SizedBox(width: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: secili == i ? Colors.white.withValues(alpha: .22) : r.ic,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('${sayilar![i]}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: secili == i ? Colors.white : r.soluk, fontFeatures: const [FontFeature.tabularFigures()])),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (hareketAzalt(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _e.dispose();
    _c.dispose();
    super.dispose();
  }

  late final _e = CurvedAnimation(parent: _c, curve: const Cubic(.22, 1, .36, 1));

  @override
  Widget build(BuildContext context) {
    // FadeTransition + kayma: her karede alt ağaç yeniden kurulmaz, yalnız boyanır.
    return FadeTransition(
      opacity: _e,
      child: AnimatedBuilder(
        animation: _e,
        builder: (_, child) => Transform.translate(offset: Offset(0, widget.kayma * (1 - _e.value)), child: child),
        child: widget.child,
      ),
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

class _AuroraState extends State<Aurora> {
  // Işıklar 18 sn'de bir gidip gelir; hareket saniyede 1-2 px. Saniyede 60
  // kare yerine ~7 kare yeter (fark edilmez) → ekran boşta neredeyse hiç
  // çizim yapmaz. Gizli sekmede, arka planda ve "hareketi azalt"ta durur.
  static const _adim = Duration(milliseconds: 150);
  static const _yari = 18000; // ms
  final _t = ValueNotifier<double>(0);
  Timer? _zaman;
  int _gecen = 0;
  ValueListenable<TickerModeData>? _tickerMode;

  @override
  void initState() {
    super.initState();
    uygulamaOnde.addListener(_ayarla);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = TickerMode.getValuesNotifier(context);
    if (n != _tickerMode) {
      _tickerMode?.removeListener(_ayarla);
      _tickerMode = n..addListener(_ayarla);
    }
    _ayarla();
  }

  void _ayarla() {
    if (!mounted) return;
    final calis = uygulamaOnde.value && (_tickerMode?.value.enabled ?? true) && !hareketAzalt(context);
    if (calis && _zaman == null) {
      _zaman = Timer.periodic(_adim, (_) {
        _gecen = (_gecen + _adim.inMilliseconds) % (2 * _yari);
        final v = _gecen <= _yari ? _gecen / _yari : 2 - _gecen / _yari;
        _t.value = Curves.easeInOut.transform(v);
      });
    } else if (!calis && _zaman != null) {
      _zaman!.cancel();
      _zaman = null;
    }
  }

  @override
  void dispose() {
    _zaman?.cancel();
    _tickerMode?.removeListener(_ayarla);
    uygulamaOnde.removeListener(_ayarla);
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: Marka.hero),
        clipBehavior: Clip.hardEdge,
        child: Stack(children: [
          // Ayrı katman: ışıklar oynarken üstteki içerik yeniden boyanmaz.
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _AuroraCizer(_t)))),
          // İçerideki cam kutular (Cam) bulanıklığı TEK seferde paylaşsın.
          BackdropGroup(child: widget.child),
        ]),
      );
}

class _AuroraCizer extends CustomPainter {
  _AuroraCizer(this._t) : super(repaint: _t);
  final ValueListenable<double> _t;
  @override
  void paint(Canvas c, Size s) {
    final t = _t.value;
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
  bool shouldRepaint(_AuroraCizer o) => o._t != _t;
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
        // grouped: aynı Aurora içindeki tüm cam kutular arka planı tek
        // geçişte bulanıklaştırır (görünüm aynı, GPU işi çok daha az).
        child: BackdropFilter.grouped(
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
        builder: (_, child) => Transform.translate(offset: Offset(0, -90 * (1 - e.value)), child: child),
        child: FadeTransition(
          opacity: _c,
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
