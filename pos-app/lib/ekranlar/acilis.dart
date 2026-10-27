import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';

/// AÇILIŞ PERDESİ (2026-10-27).
///
/// Uygulama açılırken BamBumPOS işareti (QR biçimli logo) sahnede kurulur:
///   1. mor kare yaylanarak belirir,
///   2. üç QR hücresi ve sağ alttaki çubuklar sırayla "çizilir",
///   3. kareden bir tarama ışığı geçer, etrafında iki halka döner,
///   4. yazı harf harf yükselir, altta yükleme çubuğu akar.
/// Sunucu yanıtı gelip gösterim tamamlanınca perde büyüyerek açılır ve
/// alttaki ekran (aktivasyon / PIN / kasa) belirir. Sunucu yavaşsa halkalar
/// ve çubuk dönmeye devam eder; hızlıysa gösterim en az [enAz] sürer.
///
/// Tek AnimationController zinciri + CustomPainter: düşük güçlü tablette de
/// 60 fps (resim yok, gölge yok, bulanıklık yok).
class AcilisKatmani extends StatefulWidget {
  const AcilisKatmani({super.key, required this.hazir, required this.surum, required this.child});

  /// Açılış aşaması bitti mi (oturum denetlendi)?
  final bool hazir;
  final String surum;
  final Widget child;

  @override
  State<AcilisKatmani> createState() => _AcilisKatmaniState();
}

class _AcilisKatmaniState extends State<AcilisKatmani> with TickerProviderStateMixin {
  static const enAz = Duration(milliseconds: 1500);

  late final AnimationController _giris = AnimationController(vsync: this, duration: enAz);
  late final AnimationController _dongu = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _cikis = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _bitti = false;

  @override
  void initState() {
    super.initState();
    _dongu.repeat();
    _giris.forward().whenComplete(_denetle);
    _cikis.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        _dongu.stop();
        setState(() => _bitti = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Animasyonları azalt" açık cihazda perde hiç oynamaz.
    if (Hareket.kapali(context) && !_bitti) {
      _giris.value = 1;
      _denetle();
    }
  }

  @override
  void didUpdateWidget(AcilisKatmani eski) {
    super.didUpdateWidget(eski);
    _denetle();
  }

  void _denetle() {
    if (!widget.hazir || !_giris.isCompleted || _cikis.isAnimating || _cikis.isCompleted) return;
    if (Hareket.kapali(context)) {
      _cikis.value = 1;
    } else {
      _cikis.forward();
    }
  }

  @override
  void dispose() {
    _giris.dispose();
    _dongu.dispose();
    _cikis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bitti) return widget.child;
    return Stack(fit: StackFit.expand, children: [
      // Perde açılırken alttaki ekran hafifçe büyüyerek gelir.
      AnimatedBuilder(
        animation: _cikis,
        child: widget.child,
        builder: (_, child) {
          final t = Curves.easeOutCubic.transform(_cikis.value);
          return Transform.scale(scale: .94 + .06 * t, child: child);
        },
      ),
      IgnorePointer(
        ignoring: _cikis.value > .5,
        child: AnimatedBuilder(
          animation: _cikis,
          builder: (_, child) {
            final t = Curves.easeInCubic.transform(_cikis.value);
            return Opacity(opacity: 1 - t, child: Transform.scale(scale: 1 + .12 * t, child: child));
          },
          child: RepaintBoundary(child: _Sahne(giris: _giris, dongu: _dongu, surum: widget.surum, hazir: widget.hazir)),
        ),
      ),
    ]);
  }
}

class _Sahne extends StatelessWidget {
  const _Sahne({required this.giris, required this.dongu, required this.surum, required this.hazir});
  final Animation<double> giris;
  final Animation<double> dongu;
  final String surum;
  final bool hazir;

  static const _ust = Color(0xFF0E0B33);
  static const _orta = Color(0xFF221C78);
  static const _alt = Color(0xFF1D4ED8);

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_ust, _orta, _alt],
            stops: [0, .55, 1],
          ),
        ),
        child: LayoutBuilder(builder: (context, k) {
          final kisa = math.min(k.maxWidth, k.maxHeight);
          final logo = (kisa * .24).clamp(96.0, 168.0);

          return Stack(fit: StackFit.expand, children: [
            // Arka plan: yavaşça süzülen ışık noktaları + ızgara.
            CustomPaint(painter: _ZeminRessami(dongu: dongu, giris: giris)),
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox.square(
                  dimension: logo * 1.9,
                  child: CustomPaint(painter: _IsaretRessami(giris: giris, dongu: dongu)),
                ),
                SizedBox(height: logo * .1),
                _Yazi(giris: giris, boyut: (logo * .26).clamp(26.0, 40.0)),
                const SizedBox(height: 8),
                _Belir(
                  giris: giris,
                  bas: .78,
                  child: Text(
                    'Satış noktası · Masa · Mutfak · Kasa',
                    style: TextStyle(fontFamily: yaziTipi, color: Colors.white.withValues(alpha: .62), fontSize: 13.5, letterSpacing: .4),
                  ),
                ),
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 44 + MediaQuery.paddingOf(context).bottom,
              child: _Belir(
                giris: giris,
                bas: .84,
                child: Column(children: [
                  SizedBox(width: 168, height: 3, child: CustomPaint(painter: _CubukRessami(dongu: dongu))),
                  const SizedBox(height: 12),
                  Text(
                    hazir ? 'Hazır' : 'Bağlanıyor…',
                    style: TextStyle(fontFamily: yaziTipi, color: Colors.white.withValues(alpha: .7), fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text('Sürüm $surum',
                      style: TextStyle(fontFamily: yaziTipi, color: Colors.white.withValues(alpha: .38), fontSize: 11)),
                ]),
              ),
            ),
          ]);
        }),
      ),
    );
  }
}

/// Belli bir andan sonra aşağıdan süzülerek belirir.
class _Belir extends StatelessWidget {
  const _Belir({required this.giris, required this.bas, required this.child});
  final Animation<double> giris;
  final double bas;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: giris,
        child: child,
        builder: (_, child) {
          final t = Hareket.giris.transform(((giris.value - bas) / (1 - bas)).clamp(0.0, 1.0));
          return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child));
        },
      );
}

/// "BamBumPOS" — harfler sırayla yükselir; "POS" logo morunun açık tonunda.
class _Yazi extends StatelessWidget {
  const _Yazi({required this.giris, required this.boyut});
  final Animation<double> giris;
  final double boyut;

  static const _harfler = 'BamBumPOS';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: giris,
      builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _harfler.length; i++)
          Builder(builder: (_) {
            final bas = .52 + i * .035;
            final t = Hareket.giris.transform(((giris.value - bas) / .22).clamp(0.0, 1.0));
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, boyut * .55 * (1 - t)),
                child: Text(
                  _harfler[i],
                  style: TextStyle(
                    fontFamily: yaziTipi,
                    fontSize: boyut,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.3,
                    color: i >= 6 ? const Color(0xFFB9B2FF) : Colors.white,
                  ),
                ),
              ),
            );
          }),
      ]),
    );
  }
}

/// Logonun kendisi, 512'lik çizim ızgarasında (assets/simge/logo.png ile aynı ölçü).
class _IsaretRessami extends CustomPainter {
  _IsaretRessami({required this.giris, required this.dongu}) : super(repaint: Listenable.merge([giris, dongu]));
  final Animation<double> giris;
  final Animation<double> dongu;

  static double _ara(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final t = giris.value;
    final d = dongu.value;
    final m = size.center(Offset.zero);
    final kenar = size.width / 1.9; // logo karesi

    // ── Halkalar: logo etrafında zıt yönlerde dönen iki yay.
    final halka = Hareket.giris.transform(_ara(t, .12, .62));
    if (halka > 0) {
      final r1 = kenar * .86;
      final r2 = kenar * .94;
      final p1 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(colors: [
          const Color(0x00B9B2FF),
          const Color(0xCCB9B2FF),
          const Color(0x00B9B2FF),
        ], transform: GradientRotation(d * 2 * math.pi)).createShader(Rect.fromCircle(center: m, radius: r1));
      canvas.drawArc(Rect.fromCircle(center: m, radius: r1), d * 2 * math.pi, 2 * math.pi * .72 * halka, false, p1);

      final p2 = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF7DD3FC).withValues(alpha: .45 * halka);
      final bas2 = -d * 2 * math.pi; // tam tur: döngü başa sarınca sıçramaz
      for (var i = 0; i < 3; i++) {
        canvas.drawArc(Rect.fromCircle(center: m, radius: r2), bas2 + i * 2 * math.pi / 3, .9 * halka, false, p2);
      }
      // Yörüngedeki küçük nokta.
      final a = d * 2 * math.pi + 2 * math.pi * .72 * halka;
      canvas.drawCircle(m + Offset(math.cos(a), math.sin(a)) * r1, 3.2, Paint()..color = Colors.white.withValues(alpha: halka));
    }

    // ── Parıltı (nabız).
    final nabiz = .5 + .5 * math.sin(d * 2 * math.pi);
    final kare = Hareket.giris.transform(_ara(t, 0, .3));
    if (kare > 0) {
      canvas.drawCircle(
        m,
        kenar * (.75 + .06 * nabiz),
        Paint()
          ..shader = ui.Gradient.radial(m, kenar * .8, [
            const Color(0xFF5443D2).withValues(alpha: .55 * kare),
            const Color(0x005443D2),
          ]),
      );
    }

    // ── Mor kare: yaylanarak büyür, hafif dönüşle yerine oturur.
    final yay = Curves.easeOutBack.transform(_ara(t, 0, .32));
    if (yay <= 0) return;
    canvas.save();
    canvas.translate(m.dx, m.dy);
    canvas.rotate(-.18 * (1 - yay));
    final o = kenar / 512 * (.55 + .45 * yay);
    canvas.scale(o, o);
    canvas.translate(-256, -256);

    final kareRect = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 512, 512), const Radius.circular(72));
    canvas.drawRRect(kareRect, Paint()..color = const Color(0xFF5443D2).withValues(alpha: kare));

    // ── Hücreler ve çubuklar sırayla çizilir.
    final cizgi = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 38
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void hucre(double x, double y, double a, double b) {
      final p = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 19, y + 19, 94, 94), const Radius.circular(36)));
      _kismiCiz(canvas, p, Hareket.giris.transform(_ara(t, a, b)), cizgi);
    }

    hucre(100, 100, .22, .46);
    hucre(276, 100, .30, .54);
    hucre(100, 276, .38, .62);
    void cubuk(Offset p0, Offset p1, double a, double b, [double kalin = 38]) {
      final k = Hareket.giris.transform(_ara(t, a, b));
      if (k <= 0) return;
      canvas.drawLine(p0, Offset.lerp(p0, p1, k)!, cizgi..strokeWidth = kalin);
    }

    cubuk(const Offset(297, 299), const Offset(332, 299), .46, .58);
    cubuk(const Offset(346, 346), const Offset(346, 389), .52, .64);
    cubuk(const Offset(391, 299), const Offset(391, 389), .56, .70);

    // ── Tarama ışığı: kareyi yukarıdan aşağı süpürür.
    final tara = _ara(t, .66, .92);
    if (tara > 0 && tara < 1) {
      final y = -40 + 592 * Curves.easeInOutCubic.transform(tara);
      canvas.save();
      canvas.clipRRect(kareRect);
      canvas.drawRect(
        Rect.fromLTWH(0, y - 70, 512, 80),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, y - 70), Offset(0, y + 10), [
            const Color(0x00FFFFFF),
            const Color(0x55FFFFFF),
          ]),
      );
      canvas.drawRect(Rect.fromLTWH(0, y + 8, 512, 4), Paint()..color = const Color(0xCC7DD3FC));
      canvas.restore();
    }
    canvas.restore();
  }

  static void _kismiCiz(Canvas c, Path yol, double oran, Paint p) {
    if (oran <= 0) return;
    if (oran >= 1) {
      c.drawPath(yol, p);
      return;
    }
    for (final m in yol.computeMetrics()) {
      c.drawPath(m.extractPath(0, m.length * oran), p);
    }
  }

  @override
  bool shouldRepaint(covariant _IsaretRessami eski) => false;
}

final _saat = Stopwatch()..start();

/// Zemin: ince nokta ızgarası + yukarı süzülen ışık zerreleri.
class _ZeminRessami extends CustomPainter {
  _ZeminRessami({required this.dongu, required this.giris}) : super(repaint: dongu);
  final Animation<double> dongu;
  final Animation<double> giris;

  static final _zerreler = List.generate(26, (i) {
    final r = math.Random(i * 7919 + 13);
    return (x: r.nextDouble(), y: r.nextDouble(), hiz: .35 + r.nextDouble() * .65, boy: 1 + r.nextDouble() * 2.2, faz: r.nextDouble());
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = Curves.easeOut.transform(giris.value.clamp(0.0, 1.0));
    final d = dongu.value;

    // Nokta ızgarası (çok silik).
    final nokta = Paint()..color = Colors.white.withValues(alpha: .05 * g);
    const ara = 28.0;
    for (var x = ara / 2; x < size.width; x += ara) {
      for (var y = ara / 2; y < size.height; y += ara) {
        canvas.drawCircle(Offset(x, y), .9, nokta);
      }
    }

    // Işık zerreleri.
    for (final z in _zerreler) {
      // Konum duvar saatinden: döngü başa sarınca zerreler sıçramaz.
      final ilerle = (z.y - _saat.elapsedMilliseconds / 1000 * .045 * z.hiz) % 1.0;
      final p = Offset(z.x * size.width, ilerle * size.height);
      final parla = .25 + .35 * (.5 + .5 * math.sin((d + z.faz) * 2 * math.pi));
      canvas.drawCircle(p, z.boy, Paint()..color = Colors.white.withValues(alpha: parla * g));
    }
  }

  @override
  bool shouldRepaint(covariant _ZeminRessami eski) => false;
}

/// Yükleme çubuğu: koyu oluk içinde akan parlak bir şerit.
class _CubukRessami extends CustomPainter {
  _CubukRessami({required this.dongu}) : super(repaint: dongu);
  final Animation<double> dongu;

  @override
  void paint(Canvas canvas, Size size) {
    final oluk = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height));
    canvas.drawRRect(oluk, Paint()..color = Colors.white.withValues(alpha: .14));
    canvas.save();
    canvas.clipRRect(oluk);
    final t = Curves.easeInOutSine.transform((dongu.value * 2) % 1.0);
    final w = size.width * .42;
    final x = -w + (size.width + w) * t;
    canvas.drawRect(
      Rect.fromLTWH(x, 0, w, size.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset(x, 0), Offset(x + w, 0), const [
          Color(0x007DD3FC),
          Color(0xFFB9B2FF),
          Color(0x007DD3FC),
        ], const [0, .5, 1]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CubukRessami eski) => false;
}
