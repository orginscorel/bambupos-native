import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'eslesme.dart';
import 'kabuk.dart';

/// Açılış: marka animasyonu + oturum kontrolü.
/// Oturum varsa kabuğa, yoksa telefon eşleme ekranına geçer.
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key});
  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> with TickerProviderStateMixin {
  /// Giriş koreografisi (tek seferlik): parçacıklar → işaret → tarama → rozet → parıltı.
  late final _giris = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..forward();
  /// Beklerken dönen mesai saati yayı.
  late final _saat = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
  /// Çıkış: işaret büyür, ekran ortadan açılır.
  late final _cikis = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  String? _hata;

  @override
  void initState() {
    super.initState();
    Uyg.api.oturumDustu = oturumDustu;
    _basla();
  }

  Future<void> _basla() async {
    setState(() => _hata = null);
    bool var_;
    try {
      var_ = await Uyg.hesapYukle();
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
      return;
    }
    // Koreografi bitmeden geçme (en az ~1,9 sn); hesap daha geç gelirse saat yayı döner.
    if (_giris.isAnimating) await _giris.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    await _cikis.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 750),
      pageBuilder: (_, _, _) => var_ ? const Kabuk() : const EslesmeEkrani(),
      transitionsBuilder: (_, a, _, child) => ClipPath(
        clipper: _DaireAcilim(Curves.easeInOutCubic.transform(a.value)),
        child: child,
      ),
    ));
  }

  @override
  void dispose() {
    _giris.dispose();
    _saat.dispose();
    _cikis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: durumCubugu,
      child: Scaffold(
        backgroundColor: Marka.lacivert0,
        body: Aurora(
          child: Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_giris, _saat, _cikis]),
              builder: (_, _) {
                final c = Curves.easeInCubic.transform(_cikis.value);
                return Opacity(
                  opacity: 1 - c,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Transform.scale(
                      scale: 1 + .35 * c,
                      child: SizedBox(
                        width: 260,
                        height: 260,
                        child: CustomPaint(
                          painter: _AcilisCizer(t: _giris.value, saat: _saat.value, bekliyor: _hata == null),
                        ),
                      ),
                    ),
                    _Yazi(t: _giris.value),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 92,
                      child: _hata == null
                          ? Opacity(
                              opacity: _ara(_giris.value, .85, 1),
                              child: Text('Hazırlanıyor…', style: TextStyle(color: Colors.white.withValues(alpha: .5), fontSize: 12.5, letterSpacing: .4)),
                            )
                          : Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Column(children: [
                                Text(_hata!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 14),
                                YumusakDugme(yazi: 'Tekrar dene', ikon: Icons.refresh_rounded, onTap: _basla, zemin: Colors.white.withValues(alpha: .12), renk: Colors.white),
                              ]),
                            ),
                    ),
                  ]),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// [a,b] aralığını 0..1'e çevirir (dışı kırpılır).
double _ara(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

/// "BamBumPOS" harf harf yükselir, "PERSONEL" aralığı açılarak belirir.
class _Yazi extends StatelessWidget {
  const _Yazi({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    const kelime = 'BamBumPOS';
    final p = Curves.easeOutCubic.transform(_ara(t, .78, 1));
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < kelime.length; i++)
          Builder(builder: (_) {
            final h = Curves.easeOutBack.transform(_ara(t, .62 + i * .022, .8 + i * .022));
            return Opacity(
              opacity: h.clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, 16 * (1 - h)), child: Text(kelime[i], style: gosterim(28, renk: Colors.white))),
            );
          }),
      ]),
      const SizedBox(height: 2),
      Opacity(
        opacity: p,
        child: Text('PERSONEL', style: TextStyle(color: Marka.gok.withValues(alpha: .8), letterSpacing: 1 + 4.5 * p, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

/// Açılış sahnesi — tek ressam:
///  0.00–0.42  dört yandan QR modülleri uçup üç bulucu karenin çevresine dizilir
///  0.30–0.55  mor-mavi zemin arkadan açılır, modüller çizgiye dönüşür
///  0.48–0.72  gök mavisi tarama ışını yukarıdan aşağı geçer
///  0.60–0.82  kişi rozeti yaylanarak yerine oturur
///  0.80–1.00  çapraz parıltı; ardından mesai saati yayı dönmeye başlar
class _AcilisCizer extends CustomPainter {
  _AcilisCizer({required this.t, required this.saat, required this.bekliyor});
  final double t;
  final double saat;
  final bool bekliyor;

  static final List<({Offset hedef, Offset kaynak, double gecikme, double donus})> _modul = () {
    final r = math.Random(11);
    final l = <({Offset hedef, Offset kaynak, double gecikme, double donus})>[];
    for (final o in const [Offset(14, 14), Offset(35, 14), Offset(14, 35)]) {
      for (var i = 0; i < 8; i++) {
        // Bulucu karenin çevresinde 8 nokta (köşeler + kenar ortaları)
        final x = [0.0, 6.0, 12.0, 12.0, 12.0, 6.0, 0.0, 0.0][i];
        final y = [0.0, 0.0, 0.0, 6.0, 12.0, 12.0, 12.0, 6.0][i];
        final aci = r.nextDouble() * math.pi * 2;
        final uzak = 70 + r.nextDouble() * 60;
        l.add((
          hedef: o + Offset(x, y),
          kaynak: const Offset(32, 32) + Offset(math.cos(aci), math.sin(aci)) * uzak,
          gecikme: r.nextDouble() * .16,
          donus: (r.nextDouble() - .5) * 6,
        ));
      }
    }
    return l;
  }();

  @override
  void paint(Canvas c, Size s) {
    final k = 120 / 64; // işaret 120 px
    final merkez = s.center(Offset.zero);
    c.save();
    c.translate(merkez.dx - 60, merkez.dy - 60);
    c.scale(k);
    final kutu = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(16));

    // Arka hale
    final hale = _ara(t, .3, .7);
    if (hale > 0) {
      c.drawCircle(const Offset(32, 32), 44 + 6 * hale,
          Paint()..shader = RadialGradient(colors: [Marka.mor.withValues(alpha: .45 * hale), Marka.mor.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: const Offset(32, 32), radius: 52)));
    }

    // Zemin: merkezden açılan yuvarlatılmış kare
    final z = Curves.easeOutBack.transform(_ara(t, .3, .55));
    if (z > 0) {
      c.save();
      c.translate(32, 32);
      c.scale(z);
      c.translate(-32, -32);
      c.drawRRect(kutu, Paint()..shader = Marka.grad.createShader(const Rect.fromLTWH(0, 0, 64, 64)));
      c.restore();
    }

    // Uçan modüller → bulucu kareler
    final cizgi = _ara(t, .42, .56);
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.6
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: cizgi);
    if (cizgi > 0) {
      for (final o in const [Offset(14, 14), Offset(35, 14), Offset(14, 35)]) {
        c.drawRRect(RRect.fromRectAndRadius(o & const Size(12, 12), const Radius.circular(3)), kalem);
      }
    }
    if (cizgi < 1) {
      for (final m in _modul) {
        final u = Curves.easeOutCubic.transform(_ara(t, m.gecikme, m.gecikme + .3));
        if (u <= 0) continue;
        final p = Offset.lerp(m.kaynak, m.hedef, u)!;
        c.save();
        c.translate(p.dx, p.dy);
        c.rotate(m.donus * (1 - u));
        final boy = 3.6 + 2.4 * (1 - u);
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: boy, height: boy), const Radius.circular(1)),
          Paint()..color = Color.lerp(Marka.gok, Colors.white, u)!.withValues(alpha: u.clamp(0, 1) * (1 - cizgi)),
        );
        c.restore();
      }
    }

    // Kişi rozeti
    final rz = Curves.elasticOut.transform(_ara(t, .6, .86));
    if (rz > 0) {
      c.save();
      c.translate(45, 45);
      c.scale(rz);
      c.drawCircle(Offset.zero, 11, Paint()..color = Marka.gok);
      c.drawCircle(Offset.zero, 11, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white);
      c.drawCircle(const Offset(0, -3), 3.2, Paint()..color = Colors.white);
      c.drawPath(Path()..addArc(const Rect.fromLTWH(-5.5, 0, 11, 11), math.pi, math.pi), Paint()..color = Colors.white);
      c.restore();
    }

    // Tarama ışını (işaretin içine kırpılı)
    final tr = _ara(t, .48, .72);
    if (tr > 0 && tr < 1) {
      final y = -6 + 76 * Curves.easeInOutSine.transform(tr);
      c.save();
      c.clipRRect(kutu.inflate(3));
      c.drawRect(Rect.fromLTWH(-4, y - 10, 72, 10),
          Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Marka.gok.withValues(alpha: 0), Marka.gok.withValues(alpha: .35)]).createShader(Rect.fromLTWH(0, y - 10, 64, 10)));
      c.drawRect(Rect.fromLTWH(-4, y - .8, 72, 1.6), Paint()..color = const Color(0xFFE0F2FE));
      c.restore();
    }

    // Çapraz parıltı
    final pr = _ara(t, .8, 1);
    if (pr > 0 && pr < 1) {
      c.save();
      c.clipRRect(kutu);
      final x = -40 + 150 * Curves.easeInOutCubic.transform(pr);
      c.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + 14, 0)
          ..lineTo(x - 10, 64)
          ..lineTo(x - 24, 64)
          ..close(),
        Paint()..color = Colors.white.withValues(alpha: .28),
      );
      c.restore();
    }
    c.restore();

    // Mesai saati: 12 çentik + dönen yay (giriş bitince, beklerken)
    final sb = _ara(t, .82, 1);
    if (sb > 0 && bekliyor) {
      const r = 104.0;
      for (var i = 0; i < 12; i++) {
        final a = i / 12 * math.pi * 2 - math.pi / 2;
        final gecikme = _ara(sb, i / 24, i / 24 + .5);
        final uzun = i % 3 == 0 ? 7.0 : 4.0;
        final d = Offset(math.cos(a), math.sin(a));
        c.drawLine(merkez + d * (r - uzun), merkez + d * r,
            Paint()
              ..strokeWidth = i % 3 == 0 ? 2.4 : 1.6
              ..strokeCap = StrokeCap.round
              ..color = Colors.white.withValues(alpha: (i % 3 == 0 ? .55 : .25) * gecikme));
      }
      final bas = saat * math.pi * 2 - math.pi / 2;
      final yay = Rect.fromCircle(center: merkez, radius: r + 9);
      c.drawArc(
        yay,
        bas - 1.6,
        1.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0,
            endAngle: math.pi * 2,
            transform: GradientRotation(bas - 1.6),
            colors: [Marka.lavanta.withValues(alpha: 0), Marka.gok.withValues(alpha: sb), Marka.gok.withValues(alpha: sb)],
            stops: const [0, .25, 1],
          ).createShader(yay),
      );
      final uc = merkez + Offset(math.cos(bas), math.sin(bas)) * (r + 9);
      c.drawCircle(uc, 7, Paint()..color = Marka.gok.withValues(alpha: .25 * sb));
      c.drawCircle(uc, 3.6, Paint()..color = Colors.white.withValues(alpha: sb));
    }
  }

  @override
  bool shouldRepaint(_AcilisCizer o) => o.t != t || o.saat != saat || o.bekliyor != bekliyor;
}

/// Sonraki ekran ortadan büyüyen daireyle açılır.
class _DaireAcilim extends CustomClipper<Path> {
  _DaireAcilim(this.v);
  final double v;
  @override
  Path getClip(Size s) {
    final r = math.sqrt(s.width * s.width + s.height * s.height) / 2 * v;
    return Path()..addOval(Rect.fromCircle(center: s.center(Offset.zero), radius: math.max(r, .1)));
  }

  @override
  bool shouldReclip(_DaireAcilim o) => o.v != v;
}

/// Oturum düştüğünde (401) her yerden eşleme ekranına dön.
void oturumDustu() {
  final nav = Uyg.navigator.currentState;
  if (nav == null || Uyg.hesap.value == null) return;
  Uyg.hesap.value = null;
  nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const EslesmeEkrani()), (_) => false);
  bildir('Oturum kapandı', mesaj: 'Telefonu yeniden eşle ya da parolayla gir.', tur: BildirimTur.uyari);
}
