import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/tema.dart';
import 'ortak.dart';

/// DÜĞMELER — personel uygulamasının (lib/ortak/ortak.dart) düğmeleriyle
/// BİREBİR aynı görünüm: gradyan, yükseklik, köşe (18 / 16 / 12), gölge,
/// basma efekti (ölçek + içe çöken ışıma + koyulaşma), ara sıra ışık süzülmesi.
/// Kullanıcı talebi (2026-10-27): "düğmeler personeldeki gibi olsun".

/// Basılı durumunu çocuğa veren dokunma algılayıcı (personelle aynı ritim).
class _BasmaKatmani extends StatefulWidget {
  const _BasmaKatmani({required this.builder, this.onTap, this.olcek = .97, this.soluk = true, this.etiket});
  final Widget Function(BuildContext, bool basili) builder;
  final VoidCallback? onTap;
  final double olcek;
  final bool soluk;
  final String? etiket;
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
    final kapali = Hareket.kapali(context);
    return Semantics(
      button: true,
      enabled: aktif,
      label: widget.etiket,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: aktif ? (_) => _ayarla(true) : null,
        onTapCancel: aktif ? () => _ayarla(false) : null,
        onTapUp: aktif ? (_) => _ayarla(false) : null,
        onTap: aktif
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: _bas && !kapali ? widget.olcek : 1,
          duration: Duration(milliseconds: _bas ? 90 : 240),
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
  final bool parilti;
  final IconData? sonIkon;

  @override
  State<GradDugme> createState() => _GradDugmeState();
}

class _GradDugmeState extends State<GradDugme> with TickerProviderStateMixin {
  // Işık şeridi: 3,64 sn bekler, 1,56 sn süzülür; beklerken kare çizilmez (pil).
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
    final iste = _parlasin && !Hareket.kapali(context);
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
      if (!TickerMode.valuesOf(context).enabled) return _planla();
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
            BoxShadow(color: Marka.gece.withValues(alpha: r.koyu ? .5 : .14), blurRadius: basili ? 2 : 4, offset: Offset(0, basili ? 1 : 2)),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(rad),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rad),
          child: Stack(fit: StackFit.expand, children: [
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
                  ? const Yukleyici(boyut: 24, renk: Colors.white)
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
/// `zemin` doygun bir renk ve `renk` beyaz verilirse dolu onay/tehlike düğmesi olur.
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

/// Metin düğmesi ("Vazgeç", "Tümü" …). `kucuk` → başlık satırı içi kompakt
/// tonlu düğme; değilse tam boy (48) sade düğme.
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

/// Sayfanın sağ altındaki ana eylem düğmesi — GradDugme görünümü, içerik genişliğinde.
class EylemDugmesi extends StatelessWidget {
  const EylemDugmesi({super.key, required this.ikon, required this.yazi, required this.onTap});
  final IconData ikon;
  final String yazi;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    const rad = 18.0;
    return _BasmaKatmani(
      onTap: onTap,
      etiket: yazi,
      builder: (_, basili) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: Marka.grad,
          borderRadius: BorderRadius.circular(rad),
          boxShadow: [
            BoxShadow(color: Marka.mor.withValues(alpha: r.koyu ? .55 : .5), blurRadius: basili ? 12 : 26, offset: Offset(0, basili ? 5 : 12), spreadRadius: basili ? -8 : -10),
            BoxShadow(color: Marka.gece.withValues(alpha: r.koyu ? .5 : .14), blurRadius: basili ? 2 : 4, offset: Offset(0, basili ? 1 : 2)),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(rad),
          border: Border.all(color: Colors.white.withValues(alpha: .2)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: basili
                ? [Colors.black.withValues(alpha: .06), Colors.black.withValues(alpha: .12)]
                : [Colors.white.withValues(alpha: .20), Colors.white.withValues(alpha: .03), Colors.black.withValues(alpha: .06)],
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, color: Colors.white, size: 21),
          const SizedBox(width: 10),
          Text(yazi,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                letterSpacing: .15,
                shadows: [Shadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 1))],
              )),
        ]),
      ),
    );
  }
}
