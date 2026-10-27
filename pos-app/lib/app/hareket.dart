import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HAREKET DİLİ (2026-10-27): uygulamanın bütün geçişleri buradan.
/// Kural: hızlı (140–240 ms), tek yönlü, abartısız. Kasada çalışan biri
/// animasyonu BEKLEMEZ — her geçiş dokunuşu hemen kabul eder.
///
/// BAŞARIM (2026-10-27, düşük güçlü Android tablet): geçişler yalnız
/// konum/ölçek + EN ÇOK BİR saydamlık katmanı kullanır. Saydamlık (Opacity /
/// FadeTransition) bütün ekranı ekran dışı bir katmana çizdirir; zayıf GPU'da
/// iki tam ekran katman aynı karede takılmaya yol açıyordu. Çıkan ekran artık
/// sönmez, yenisinin altında olduğu gibi durur; kararma = üstüne yarı saydam
/// siyah dikdörtgen (aynı görüntü, katmansız).
abstract final class Hareket {
  static const kisa = Duration(milliseconds: 140);
  static const orta = Duration(milliseconds: 200);
  static const uzun = Duration(milliseconds: 240);

  /// Material 3 "emphasized" eğrisinin hızlı çıkışlı eşi.
  static const giris = Cubic(0.05, 0.7, 0.1, 1.0);
  static const cikis = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Cihazda "animasyonları azalt" açıksa geçişler kapanır.
  static bool kapali(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// SAYFA GEÇİŞİ: yeni sayfa hafifçe büyüyerek ve yukarı kayarak belirir,
/// alttaki sayfa geri çekilip kararır. Android/Windows/macOS aynı görünür;
/// iOS'ta kenardan kaydırarak geri dönme için Cupertino geçişi korunur.
class PosSayfaGecisi extends PageTransitionsBuilder {
  const PosSayfaGecisi();

  @override
  Duration get transitionDuration => Hareket.uzun;

  @override
  Duration get reverseTransitionDuration => Hareket.orta;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (Hareket.kapali(context)) return child;
    return _SayfaGecisi(animation: animation, arka: secondaryAnimation, child: child);
  }
}

class _SayfaGecisi extends StatefulWidget {
  const _SayfaGecisi({required this.animation, required this.arka, required this.child});
  final Animation<double> animation;
  final Animation<double> arka;
  final Widget child;

  @override
  State<_SayfaGecisi> createState() => _SayfaGecisiState();
}

class _SayfaGecisiState extends State<_SayfaGecisi> {
  late CurvedAnimation _gir;
  late CurvedAnimation _arka;

  void _kur() {
    _gir = CurvedAnimation(parent: widget.animation, curve: Hareket.giris, reverseCurve: Hareket.cikis);
    _arka = CurvedAnimation(parent: widget.arka, curve: Hareket.giris, reverseCurve: Hareket.cikis);
  }

  @override
  void initState() {
    super.initState();
    _kur();
  }

  @override
  void didUpdateWidget(_SayfaGecisi eski) {
    super.didUpdateWidget(eski);
    if (eski.animation != widget.animation || eski.arka != widget.arka) {
      _gir.dispose();
      _arka.dispose();
      _kur();
    }
  }

  @override
  void dispose() {
    _gir.dispose();
    _arka.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _gir,
      child: AnimatedBuilder(
        animation: Listenable.merge([_gir, _arka]),
        // Alttaki sayfa %35 kararır: saydamlık katmanı yerine üstüne siyah örtü.
        child: CustomPaint(foregroundPainter: _Karartma(_arka), child: widget.child),
        builder: (context, child) {
          final t = _gir.value;
          final g = _arka.value;
          return Transform.translate(
            offset: Offset(0, 24 * (1 - t)),
            child: Transform.scale(scale: (0.97 + .03 * t) * (1 - .03 * g), child: child),
          );
        },
      ),
    );
  }
}

/// Opacity(.65) siyah zemin üstünde = %35 siyah örtü; ekran dışı katman yok.
class _Karartma extends CustomPainter {
  _Karartma(this.a) : super(repaint: a);
  final Animation<double> a;

  @override
  void paint(Canvas canvas, Size size) {
    final v = a.value.clamp(0.0, 1.0);
    if (v <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = Color.fromRGBO(0, 0, 0, .35 * v));
  }

  @override
  bool shouldRepaint(_Karartma eski) => eski.a != a;
}

PageTransitionsTheme posSayfaGecisleri() => const PageTransitionsTheme(builders: {
      TargetPlatform.android: PosSayfaGecisi(),
      TargetPlatform.windows: PosSayfaGecisi(),
      TargetPlatform.macOS: PosSayfaGecisi(),
      TargetPlatform.linux: PosSayfaGecisi(),
      TargetPlatform.fuchsia: PosSayfaGecisi(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    });

/// PENCERE: showDialog'un yerine. Pencere ortadan hafifçe büyüyerek ve
/// yumuşak bir yaylanmayla açılır, kapanırken hızla söner.
Future<T?> pencereAc<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(_PencereRotasi<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    themes: InheritedTheme.capture(from: context, to: Navigator.of(context, rootNavigator: true).context),
  ));
}

class _PencereRotasi<T> extends DialogRoute<T> {
  _PencereRotasi({
    required super.context,
    required super.builder,
    super.barrierDismissible,
    super.barrierColor,
    super.themes,
  }) : super(barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel);

  @override
  Duration get transitionDuration => Hareket.orta;

  @override
  Duration get reverseTransitionDuration => Hareket.kisa;

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (Hareket.kapali(context)) return child;
    final buyu = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    final son = CurvedAnimation(parent: animation, curve: Curves.easeOut, reverseCurve: Curves.easeIn);
    return FadeTransition(
      opacity: son,
      child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(buyu), child: child),
    );
  }
}

/// BELİRME: ızgaradaki kartlar (masalar, paket siparişler) ilk çizimde sırayla
/// aşağıdan yukarı süzülerek gelir. Yalnız İLK çizimde çalışır: pano her
/// yenilendiğinde kartlar yeniden zıplamaz.
class Belirme extends StatefulWidget {
  const Belirme({super.key, required this.sira, required this.child});
  final int sira;
  final Widget child;

  @override
  State<Belirme> createState() => _BelirmeState();
}

class _BelirmeState extends State<Belirme> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  late final CurvedAnimation _t = CurvedAnimation(parent: _c, curve: Hareket.giris);

  /// İlk ekranı dolduran kartlardan sonrası (kaydırınca gelenler) anında
  /// görünür: kaydırma sırasında kart başına saydamlık katmanı açılmaz.
  static const _enCokKademe = 24;

  @override
  void initState() {
    super.initState();
    if (widget.sira >= _enCokKademe) {
      _c.value = 1;
      return;
    }
    // İlk 16 kart kademeli, sonrası birlikte: uzun listede bekleme olmasın.
    final gecikme = Duration(milliseconds: 22 * math.min(widget.sira, 16));
    Future.delayed(gecikme, () {
      if (mounted && !_c.isCompleted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Hareket.kapali(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _t,
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - _t.value)),
          child: Transform.scale(scale: .96 + .04 * _t.value, child: child),
        ),
      ),
    );
  }
}

/// EKRAN GEÇİŞİ (alt şeritte sekme değişimi): yeni ekran seçilen yönden
/// kısa bir kaymayla gelir, eskisi aynı anda söner.
class EkranGecisi extends StatelessWidget {
  const EkranGecisi({super.key, required this.anahtar, required this.yon, required this.child});
  final Object anahtar;

  /// +1 sağdaki sekmeye, -1 soldakine geçiliyor.
  final int yon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Hareket.kapali(context)) return KeyedSubtree(key: ValueKey(anahtar), child: child);
    // Eski ekran sönmez: yenisi (tek saydamlık katmanı) onun üstünde belirir,
    // giriş bitince eskisi kaldırılır.
    return AnimatedSwitcher(
      duration: Hareket.orta,
      reverseDuration: Hareket.orta,
      switchInCurve: Hareket.giris,
      layoutBuilder: (simdiki, oncekiler) => Stack(fit: StackFit.expand, children: [...oncekiler, if (simdiki case final bbDeger?) bbDeger]),
      transitionBuilder: (cocuk, a) => _GirenCikan(
        animation: a,
        yeni: (a) => SlideTransition(
          position: Tween(begin: Offset(.035 * yon, 0), end: Offset.zero).animate(a),
          child: IgnorePointer(ignoring: false, child: cocuk),
        ),
        cikan: (a) => SlideTransition(position: const AlwaysStoppedAnimation(Offset.zero), child: IgnorePointer(child: cocuk)),
      ),
      child: KeyedSubtree(key: ValueKey(anahtar), child: child),
    );
  }
}

/// AŞAMA GEÇİŞİ (açılış → aktivasyon → PIN → kasa): yeni aşama hafifçe
/// büyüyerek belirir; eskisi altında olduğu gibi durur (tek saydamlık katmanı).
/// AnimatedSwitcher'ın reverseDuration'ı girişle aynı olmalı (main.dart).
Widget asamaGecisi(Widget child, Animation<double> a) => _GirenCikan(
      animation: a,
      yeni: (e) => ScaleTransition(scale: Tween(begin: .97, end: 1.0).animate(e), child: child),
      cikan: (_) => ScaleTransition(scale: const AlwaysStoppedAnimation(1.0), child: child),
    );

/// AnimatedSwitcher geçişi: GİREN ekran eğriyle söner/belirir, ÇIKAN ekran
/// (animasyon geri sararken) saydamlıksız, yerinde durur. İki dal aynı
/// widget türlerini kurar ki ekranın durumu (State) dal değişince kaybolmasın.
class _GirenCikan extends StatefulWidget {
  const _GirenCikan({required this.animation, required this.yeni, required this.cikan});
  final Animation<double> animation;
  final Widget Function(Animation<double> egri) yeni;
  final Widget Function(Animation<double> egri) cikan;

  @override
  State<_GirenCikan> createState() => _GirenCikanState();
}

class _GirenCikanState extends State<_GirenCikan> {
  late CurvedAnimation _e;

  /// Yalnız geri sarma = çıkış (yeni giren ilk karede "dismissed" olabilir).
  bool get _cikiyor => widget.animation.status == AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _e = CurvedAnimation(parent: widget.animation, curve: Hareket.giris);
    widget.animation.addStatusListener(_durum);
  }

  @override
  void didUpdateWidget(_GirenCikan eski) {
    super.didUpdateWidget(eski);
    if (eski.animation != widget.animation) {
      eski.animation.removeStatusListener(_durum);
      _e.dispose();
      _e = CurvedAnimation(parent: widget.animation, curve: Hareket.giris);
      widget.animation.addStatusListener(_durum);
    }
  }

  bool _sonCikis = false;
  void _durum(AnimationStatus s) {
    if ((s == AnimationStatus.reverse) != _sonCikis && mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_durum);
    _e.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cik = _sonCikis = _cikiyor;
    return FadeTransition(
      opacity: cik ? kAlwaysCompleteAnimation : _e,
      child: cik ? widget.cikan(_e) : widget.yeni(_e),
    );
  }
}

/// Dokununca hafifçe içe basılan kart/düğme hissi (titreşimle).
class Basilir extends StatefulWidget {
  const Basilir({super.key, required this.child, this.titresim = false});
  final Widget child;
  final bool titresim;

  @override
  State<Basilir> createState() => _BasilirState();
}

class _BasilirState extends State<Basilir> {
  bool _basili = false;

  void _ayarla(bool b) {
    if (_basili == b) return;
    if (b && widget.titresim) HapticFeedback.selectionClick();
    setState(() => _basili = b);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _ayarla(true),
        onPointerUp: (_) => _ayarla(false),
        onPointerCancel: (_) => _ayarla(false),
        child: AnimatedScale(
          scale: _basili ? .965 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}
