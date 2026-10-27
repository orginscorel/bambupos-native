import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HAREKET DİLİ — POS uygulamasından (pos-app/lib/app/hareket.dart) alındı.
/// Patron uygulamasının bütün geçişleri buradan.
/// Kural: hızlı (150–300 ms), tek yönlü, abartısız. Kasada çalışan biri
/// animasyonu BEKLEMEZ — her geçiş dokunuşu hemen kabul eder.
abstract final class Hareket {
  static const kisa = Duration(milliseconds: 160);
  static const orta = Duration(milliseconds: 240);
  static const uzun = Duration(milliseconds: 320);

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
    final gir = CurvedAnimation(parent: animation, curve: Hareket.giris, reverseCurve: Hareket.cikis);
    final arka = CurvedAnimation(parent: secondaryAnimation, curve: Hareket.giris, reverseCurve: Hareket.cikis);

    return FadeTransition(
      opacity: gir,
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: .65).animate(arka),
        child: AnimatedBuilder(
          animation: Listenable.merge([gir, arka]),
          child: child,
          builder: (context, child) {
            final t = gir.value;
            final g = arka.value;
            return Transform.translate(
              offset: Offset(0, 24 * (1 - t)),
              child: Transform.scale(scale: (0.97 + .03 * t) * (1 - .03 * g), child: child),
            );
          },
        ),
      ),
    );
  }
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
  Timer? _zaman;

  @override
  void initState() {
    super.initState();
    // İlk 16 kart kademeli, sonrası birlikte: uzun listede bekleme olmasın.
    final gecikme = Duration(milliseconds: 22 * math.min(widget.sira, 16));
    // İptal edilebilir zamanlayıcı: kart görünmeden kapanırsa iz bırakmaz.
    _zaman = Timer(gecikme, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Hareket.kapali(context)) _c.value = 1;
  }

  @override
  void dispose() {
    _zaman?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Hareket.giris);
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - t.value)),
          child: Transform.scale(scale: .96 + .04 * t.value, child: child),
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
    return AnimatedSwitcher(
      duration: Hareket.orta,
      reverseDuration: Hareket.kisa,
      switchInCurve: Hareket.giris,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (simdiki, oncekiler) => Stack(fit: StackFit.expand, children: [...oncekiler, ?simdiki]),
      transitionBuilder: (cocuk, a) {
        final yeni = cocuk.key == ValueKey(anahtar);
        if (!yeni) return FadeTransition(opacity: a, child: IgnorePointer(child: cocuk));
        return FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: Offset(.035 * yon, 0), end: Offset.zero).animate(a),
            child: cocuk,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(anahtar), child: child),
    );
  }
}

/// AŞAMA GEÇİŞİ (açılış → aktivasyon → PIN → kasa): yeni aşama hafifçe
/// büyüyerek belirir, eskisi geri çekilerek söner.
Widget asamaGecisi(Widget child, Animation<double> a) {
  final e = CurvedAnimation(parent: a, curve: Hareket.giris);
  return FadeTransition(
    opacity: e,
    child: ScaleTransition(scale: Tween(begin: .97, end: 1.0).animate(e), child: child),
  );
}

/// BASILIR: dokununca hafifçe içe basılan kart/düğme hissi (titreşimle).
/// POS'takinin eşi; ek olarak [onTap] ve erişilebilirlik etiketi alır.
/// Dokunma alanı en az 44×44 px tutulur.
class Basilir extends StatefulWidget {
  const Basilir({super.key, required this.child, this.onTap, this.titresim = true, this.etiket, this.olcek = .965});
  final Widget child;
  final VoidCallback? onTap;
  final bool titresim;
  final String? etiket;
  final double olcek;

  @override
  State<Basilir> createState() => _BasilirState();
}

class _BasilirState extends State<Basilir> {
  bool _basili = false;

  void _ayarla(bool b) {
    if (_basili == b || widget.onTap == null) return;
    setState(() => _basili = b);
  }

  @override
  Widget build(BuildContext context) {
    final aktif = widget.onTap != null;
    return Semantics(
      button: aktif,
      label: widget.etiket,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: aktif ? (_) => _ayarla(true) : null,
          onTapUp: aktif ? (_) => _ayarla(false) : null,
          onTapCancel: aktif ? () => _ayarla(false) : null,
          onTap: aktif
              ? () {
                  if (widget.titresim) HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          child: AnimatedScale(
            scale: _basili && !Hareket.kapali(context) ? widget.olcek : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
