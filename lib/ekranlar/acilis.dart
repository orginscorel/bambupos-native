import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'eslesme.dart';
import 'kabuk.dart';

/// AÇILIŞ: marka koreografisi + oturum denetimi.
///
///  0.00–0.30  gece zemininde ışıklar açılır, parçacıklar yükselir
///  0.00–0.15  yerel açılış ekranındaki ortalı işaret söner (kesintisiz geçiş)
///  0.05–0.35  işaret yaylanarak büyür; taç parçaları aşağıdan gelip birleşir,
///             göz açılır, taban şeridi uzar
///  0.35–0.75  altında yedi sütunlu grafik kademeli yükselir
///  0.45–0.72  gök mavisi rozet yerine oturur, içindeki çubuklar yükselir
///  0.60–0.90  sütun tepelerinden geçen çizgi çizilir, ucunda ışıklı nokta
///  0.55–0.85  "BamBumPOS" harf harf, "PATRON" aralığı açılarak gelir
///  sonrası    oturum yanıtı gelene dek nokta nabız atar, parçacıklar süzülür
///
/// En az ~1,6 sn sürer; "animasyonları azalt" açıksa son kare durağan çizilir
/// ve yanıt gelir gelmez geçilir.
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key});
  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> with TickerProviderStateMixin {
  late final _giris = AnimationController(vsync: this, duration: const Duration(milliseconds: 1650));
  late final _dongu = AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));
  late final _cikis = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  String? _hata;
  bool _basladi = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_basladi) return;
    _basladi = true;
    if (Hareket.kapali(context)) {
      _giris.value = 1;
    } else {
      _giris.forward();
      _dongu.repeat();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _basla());
  }

  Future<void> _basla() async {
    if (_hata != null) setState(() => _hata = null);
    bool var_;
    try {
      var_ = await Uyg.oturumVarMi();
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
      return;
    }
    if (_giris.isAnimating) await _giris.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    final azalt = Hareket.kapali(context);
    if (!azalt) await _cikis.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: Duration(milliseconds: azalt ? 0 : 700),
      pageBuilder: (_, _, _) => var_ ? const Kabuk() : const EslesmeEkrani(),
      transitionsBuilder: (_, a, _, child) => ClipPath(clipper: _DaireAcilim(Curves.easeInOutCubic.transform(a.value)), child: child),
    ));
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
    return AnnotatedRegion(
      value: durumCubuguAcikSimge,
      child: Scaffold(
        backgroundColor: Marka.gece,
        body: Semantics(
          label: 'BamBumPOS Patron açılıyor',
          child: AnimatedBuilder(
            animation: Listenable.merge([_giris, _dongu, _cikis]),
            builder: (context, _) {
              final t = _giris.value;
              final c = Curves.easeInCubic.transform(_cikis.value);
              return Stack(fit: StackFit.expand, children: [
                CustomPaint(painter: AcilisZeminCizer(t: t, d: _dongu.value)),
                // Yerel açılış ekranıyla (Android/iOS) aynı yerde, aynı boyda
                // işaret: ilk karede birebir örtüşür, sonra söner.
                if (t < .16)
                  Center(
                    child: Opacity(
                      opacity: 1 - _ara(t, .02, .16),
                      child: Transform.scale(scale: 1 - .25 * _ara(t, .02, .16), child: const PaMark(boyut: 96)),
                    ),
                  ),
                Opacity(
                  opacity: 1 - c,
                  child: Transform.scale(
                    scale: 1 + .18 * c,
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(width: 300, height: 300, child: CustomPaint(painter: AcilisSahneCizer(t: t, d: _dongu.value))),
                          _Yazi(t: t),
                          const SizedBox(height: 22),
                          SizedBox(height: 96, child: _hata == null ? _Hazirlik(t: t) : _hataKutusu()),
                        ]),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _hataKutusu() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(children: [
          Text(_hata!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _basla,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Tekrar dene'),
          ),
        ]),
      );
}

double _ara(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

class _Yazi extends StatelessWidget {
  const _Yazi({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    const kelime = 'BamBumPOS';
    final p = Curves.easeOutCubic.transform(_ara(t, .7, .95));
    return ExcludeSemantics(
      child: Column(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < kelime.length; i++)
            Builder(builder: (_) {
              final h = Curves.easeOutBack.transform(_ara(t, .55 + i * .025, .72 + i * .025));
              return Opacity(
                opacity: h.clamp(0.0, 1.0),
                child: Transform.translate(offset: Offset(0, 14 * (1 - h)), child: Text(kelime[i], style: gosterim(30, renk: Colors.white))),
              );
            }),
        ]),
        const SizedBox(height: 2),
        Opacity(
          opacity: p,
          child: Text('PATRON', style: TextStyle(color: Marka.gok.withValues(alpha: .9), letterSpacing: 1 + 6 * p, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// "Hazırlanıyor %87" — koreografiyle birlikte sayar; yanıt beklenirken
/// "Bağlanılıyor…" yazar (uydurma rakam göstermez).
class _Hazirlik extends StatelessWidget {
  const _Hazirlik({required this.t});
  final double t;
  @override
  Widget build(BuildContext context) {
    final yuzde = (Curves.easeInOutCubic.transform(_ara(t, .3, 1)) * 100).round();
    final g = _ara(t, .5, .75);
    return Opacity(
      opacity: g,
      child: Column(children: [
        Text(yuzde < 100 ? 'Hazırlanıyor  %$yuzde' : 'Bağlanılıyor…',
            style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 12.5, letterSpacing: .4, fontFeatures: const [FontFeature.tabularFigures()])),
        const SizedBox(height: 10),
        SizedBox(
          width: 140,
          height: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(children: [
              Container(color: Colors.white.withValues(alpha: .1)),
              FractionallySizedBox(
                widthFactor: yuzde / 100,
                child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Marka.mor, Marka.mavi, Marka.gok]))),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// Tam ekran zemin: iki renkli ışık + yükselen parçacıklar + ince ızgara.
class AcilisZeminCizer extends CustomPainter {
  AcilisZeminCizer({required this.t, required this.d});
  final double t;
  final double d;

  static final List<({double x, double y, double hiz, double boy, double faz, int renk})> _parca = () {
    final r = math.Random(27);
    return List.generate(46, (i) => (x: r.nextDouble(), y: r.nextDouble(), hiz: .25 + r.nextDouble() * .75, boy: .8 + r.nextDouble() * 2.2, faz: r.nextDouble(), renk: r.nextInt(3)));
  }();

  @override
  void paint(Canvas c, Size s) {
    final a = _ara(t, 0, .3);
    void isik(Offset m, double r, Color renk) => c.drawCircle(
        m, r, Paint()..shader = RadialGradient(colors: [renk, renk.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: m, radius: r)));
    final dt = d * math.pi * 2;
    isik(Offset(s.width * (.2 + .05 * math.sin(dt)), s.height * .28), s.shortestSide * .9, Marka.mor.withValues(alpha: .45 * a));
    isik(Offset(s.width * (.85 - .05 * math.cos(dt)), s.height * .78), s.shortestSide * .8, Marka.mavi.withValues(alpha: .32 * a));

    // İnce ızgara (veri hissi), merkezden kenarlara söner
    final g = _ara(t, .15, .5);
    if (g > 0) {
      final kalem = Paint()..strokeWidth = 1;
      const aralik = 36.0;
      final m = s.center(Offset.zero);
      for (var x = (s.width / 2) % aralik; x < s.width; x += aralik) {
        final u = 1 - ((x - m.dx).abs() / (s.width / 2)).clamp(0.0, 1.0);
        kalem.color = Colors.white.withValues(alpha: .035 * g * u);
        c.drawLine(Offset(x, 0), Offset(x, s.height), kalem);
      }
      for (var y = (s.height / 2) % aralik; y < s.height; y += aralik) {
        final u = 1 - ((y - m.dy).abs() / (s.height / 2)).clamp(0.0, 1.0);
        kalem.color = Colors.white.withValues(alpha: .035 * g * u);
        c.drawLine(Offset(0, y), Offset(s.width, y), kalem);
      }
    }

    // Yükselen parçacıklar
    const renkler = [Marka.gok, Marka.lavanta, Colors.white];
    for (final p in _parca) {
      final y = ((p.y - d * p.hiz * 1.5 - t * .15) % 1.0) * s.height;
      final x = p.x * s.width + math.sin((d * 2 + p.faz) * math.pi * 2) * 8;
      final parla = (.35 + .65 * (.5 + .5 * math.sin((d * 3 + p.faz) * math.pi * 2))) * a;
      c.drawCircle(Offset(x, y), p.boy, Paint()..color = renkler[p.renk].withValues(alpha: .5 * parla));
    }
  }

  @override
  bool shouldRepaint(AcilisZeminCizer o) => o.t != t || o.d != d;
}

/// 300×300 sahne: üstte işaret, altta yükselen grafik ve çizgi.
class AcilisSahneCizer extends CustomPainter {
  AcilisSahneCizer({required this.t, required this.d});
  final double t;
  final double d;

  static const _sutun = [.38, .55, .46, .7, .62, .86, 1.0];

  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2;

    // ── İşaret (112 px), üst bölüm
    const boy = 112.0;
    final mu = Offset(cx, 78);
    final hale = _ara(t, .1, .5);
    if (hale > 0) {
      final nabiz = .5 + .5 * math.sin(d * math.pi * 2 * 3);
      c.drawCircle(mu, 86 + 6 * nabiz * hale,
          Paint()..shader = RadialGradient(colors: [Marka.mor.withValues(alpha: .5 * hale), Marka.mor.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: mu, radius: 92)));
    }
    final olcek = Curves.easeOutBack.transform(_ara(t, .05, .35));
    if (olcek > 0) {
      c.save();
      c.translate(mu.dx, mu.dy);
      c.scale(olcek * boy / 64);
      c.translate(-32, -32);
      PatronMarkCizer.ciz(
        c,
        kare: _ara(t, .08, .52),
        rozet: Curves.elasticOut.transform(_ara(t, .45, .78)),
        cubuk: _ara(t, .4, .62),
      );
      // Çapraz parıltı
      final pr = _ara(t, .78, .98);
      if (pr > 0 && pr < 1) {
        c.clipRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 64, 64), const Radius.circular(14)));
        final x = -40 + 150 * Curves.easeInOutCubic.transform(pr);
        c.drawPath(
            Path()
              ..moveTo(x, 0)
              ..lineTo(x + 14, 0)
              ..lineTo(x - 10, 64)
              ..lineTo(x - 24, 64)
              ..close(),
            Paint()..color = Colors.white.withValues(alpha: .25));
      }
      c.restore();
    }

    // ── Grafik paneli, alt bölüm
    final panel = Rect.fromLTWH(cx - 120, 168, 240, 112);
    final pg = _ara(t, .3, .5);
    if (pg > 0) {
      final taban = Paint()
        ..color = Colors.white.withValues(alpha: .18 * pg)
        ..strokeWidth = 1.2;
      c.drawLine(panel.bottomLeft, panel.bottomLeft + Offset(panel.width * Curves.easeOutCubic.transform(pg), 0), taban);
      for (var k = 1; k <= 2; k++) {
        final y = panel.bottom - panel.height * k / 3;
        _kesikCizgi(c, Offset(panel.left, y), panel.width * pg, Colors.white.withValues(alpha: .07 * pg));
      }
    }
    const n = 7;
    final w = panel.width / n;
    final tepeler = <Offset>[];
    for (var i = 0; i < n; i++) {
      final p = Curves.easeOutBack.transform(_ara(t, .35 + i * .045, .6 + i * .045));
      final nefes = t >= 1 ? .03 * math.sin((d * 4 + i / n) * math.pi * 2) : 0.0;
      final h = panel.height * .82 * (_sutun[i] + nefes) * p;
      final r = Rect.fromLTWH(panel.left + i * w + w * .2, panel.bottom - h, w * .6, h);
      tepeler.add(Offset(r.center.dx, panel.bottom - panel.height * .82 * (_sutun[i] + nefes) - 10));
      if (h <= 0) continue;
      c.drawRRect(
        RRect.fromRectAndCorners(r, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(Marka.morAcik, Marka.gok, i / (n - 1))!, Marka.mor.withValues(alpha: .25)],
          ).createShader(r),
      );
    }

    // Çizgi: sütun tepelerinden geçer, ucunda ışıklı nokta
    final lc = Curves.easeInOutCubic.transform(_ara(t, .6, .9));
    if (lc > 0) {
      final yol = Path()..moveTo(tepeler.first.dx, tepeler.first.dy);
      for (var i = 1; i < tepeler.length; i++) {
        final a = tepeler[i - 1], b = tepeler[i];
        final dx = (b.dx - a.dx) / 2;
        yol.cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
      }
      final m = yol.computeMetrics().first;
      final kismi = m.extractPath(0, m.length * lc);
      c.drawPath(
          kismi,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..strokeCap = StrokeCap.round
            ..color = Marka.gok.withValues(alpha: .16));
      c.drawPath(
          kismi,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round
            ..color = const Color(0xFFE0F2FE));
      final uc = m.getTangentForOffset(m.length * lc)?.position;
      if (uc != null) {
        final nabiz = t >= 1 ? .5 + .5 * math.sin(d * math.pi * 2 * 4) : 0.0;
        c.drawCircle(uc, 9 + 5 * nabiz, Paint()..color = Marka.gok.withValues(alpha: .22 * (1 - .5 * nabiz)));
        c.drawCircle(uc, 4.2, Paint()..color = Colors.white);
      }
    }
  }

  void _kesikCizgi(Canvas c, Offset bas, double uzunluk, Color renk) {
    final p = Paint()
      ..color = renk
      ..strokeWidth = 1;
    for (var x = 0.0; x < uzunluk; x += 8) {
      c.drawLine(bas + Offset(x, 0), bas + Offset(math.min(x + 4, uzunluk), 0), p);
    }
  }

  @override
  bool shouldRepaint(AcilisSahneCizer o) => o.t != t || o.d != d;
}

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
void oturumDustu(ApiHata hata) {
  final nav = Uyg.navigator.currentState;
  if (nav == null || !Uyg.oturumlu) return;
  Uyg.oturumlu = false;
  Uyg.api.cerezleriSil();
  nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const EslesmeEkrani()), (_) => false);
  bildir(
    hata.eslesmeKaldirildi ? 'Eşleme kaldırıldı' : 'Oturum kapandı',
    mesaj: hata.eslesmeKaldirildi ? 'İşletme sahibi bu telefonun eşlemesini kaldırdı. Yeniden eşlemek için yeni kodu kullanın.' : 'Telefonu yeniden eşleyin.',
    tur: BildirimTur.uyari,
  );
}
