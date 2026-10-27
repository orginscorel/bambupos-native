import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/tema.dart';

/// Grafik noktası: kısa etiket (eksen), uzun etiket (seçilince), değer.
class Nokta {
  const Nokta(this.etiket, this.deger, {String? uzun}) : uzun = uzun ?? etiket;
  final String etiket;
  final String uzun;
  final double deger;
}

/// İlk çizimde 0→1 ilerleyen, "animasyonları azalt"ta doğrudan 1 olan değer.
class _Giris extends StatefulWidget {
  const _Giris({required this.anahtar, required this.builder});
  final Object anahtar;
  final Widget Function(double t) builder;
  static const sure = Duration(milliseconds: 250);
  @override
  State<_Giris> createState() => _GirisState();
}

class _GirisState extends State<_Giris> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: _Giris.sure);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Hareket.kapali(context)) {
      _c.value = 1;
    } else if (_c.value == 0) {
      _c.forward();
    }
  }

  @override
  void didUpdateWidget(_Giris o) {
    super.didUpdateWidget(o);
    if (o.anahtar != widget.anahtar && !Hareket.kapali(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, _) => widget.builder(Curves.easeOutCubic.transform(_c.value)));
}

/* ───────────────────────── Sütun grafiği ───────────────────────── */

/// Dikey sütunlar (saatlik satış, haftanın günleri …). Sütuna dokununca
/// üstte etiket + değer görünür. [yaz] değeri metne çevirir.
class SutunGrafik extends StatefulWidget {
  const SutunGrafik({super.key, required this.noktalar, required this.yaz, this.yukseklik = 170, this.vurgu, this.renk, this.ozet});
  final List<Nokta> noktalar;
  final String Function(double) yaz;
  final double yukseklik;

  /// Öne çıkarılan sütun (en yoğun saat gibi).
  final int? vurgu;
  final Color? renk;

  /// Ekran okuyucu için grafik özeti.
  final String? ozet;

  @override
  State<SutunGrafik> createState() => _SutunGrafikState();
}

class _SutunGrafikState extends State<SutunGrafik> {
  int? _secili;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final n = widget.noktalar;
    if (n.isEmpty) return SizedBox(height: widget.yukseklik);
    final enBuyuk = n.map((e) => e.deger).fold<double>(0, math.max);
    final sec = _secili ?? widget.vurgu;
    final secNokta = sec != null && sec < n.length ? n[sec] : null;
    return Semantics(
      label: widget.ozet,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: secNokta == null
                ? null
                : Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${secNokta.uzun}  ',
                          style: TextStyle(color: r.silik, fontSize: 12.5),
                        ),
                        TextSpan(
                          text: widget.yaz(secNokta.deger),
                          style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
          ),
          _Giris(
            anahtar: Object.hashAll(n.map((e) => e.deger)),
            builder: (t) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _dokun(d.localPosition.dx, context),
              onHorizontalDragUpdate: (d) => _dokun(d.localPosition.dx, context),
              child: CustomPaint(
                size: Size(double.infinity, widget.yukseklik),
                painter: _SutunCizer(
                  n: n,
                  enBuyuk: enBuyuk,
                  t: t,
                  secili: sec,
                  renk: widget.renk ?? r.birincil,
                  soluk: r.koyu ? const Color(0xFF3A3870) : const Color(0xFFD9DBF2),
                  eksen: r.silik,
                  cizgi: r.kenar,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _dokun(double x, BuildContext context) {
    final w = (context.size?.width ?? 1);
    final i = (x / w * widget.noktalar.length).floor().clamp(0, widget.noktalar.length - 1);
    if (i != _secili) setState(() => _secili = i);
  }
}

class _SutunCizer extends CustomPainter {
  _SutunCizer({
    required this.n,
    required this.enBuyuk,
    required this.t,
    required this.secili,
    required this.renk,
    required this.soluk,
    required this.eksen,
    required this.cizgi,
  });
  final List<Nokta> n;
  final double enBuyuk;
  final double t;
  final int? secili;
  final Color renk;
  final Color soluk;
  final Color eksen;
  final Color cizgi;

  @override
  void paint(Canvas c, Size s) {
    const altPay = 18.0;
    final h = s.height - altPay;
    final w = s.width / n.length;
    final bosluk = math.min(6.0, w * .28);
    final kalem = Paint()
      ..color = cizgi
      ..strokeWidth = 1;
    for (var k = 1; k <= 3; k++) {
      final y = h - h * k / 3;
      c.drawLine(Offset(0, y), Offset(s.width, y), kalem);
    }
    c.drawLine(Offset(0, h), Offset(s.width, h), kalem);

    // Etiket sıklığı: dar ekranda her N'de bir.
    final adim = math.max(1, (n.length * 30 / s.width).ceil());
    for (var i = 0; i < n.length; i++) {
      final oran = enBuyuk <= 0 ? 0.0 : n[i].deger / enBuyuk;
      // Kademeli yükselme: soldan sağa gecikmeli.
      final gec = (t * 1.4 - i / n.length * .4).clamp(0.0, 1.0);
      final boy = math.max(oran > 0 ? 2.0 : 0.0, h * oran * Curves.easeOutBack.transform(gec).clamp(0.0, 1.08));
      final x = i * w + bosluk / 2;
      final rect = Rect.fromLTWH(x, h - boy, w - bosluk, boy);
      final aktif = secili == null || secili == i;
      final p = Paint();
      if (aktif) {
        p.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [renk, Color.lerp(renk, Marka.mavi, .55)!],
        ).createShader(rect);
      } else {
        p.color = soluk;
      }
      c.drawRRect(RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), p);
      if (i % adim == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: n[i].etiket,
            style: TextStyle(fontSize: 10, color: eksen, fontFamily: 'Poppins'),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(i * w + w / 2 - tp.width / 2, h + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_SutunCizer o) => o.t != t || o.secili != secili || o.n != n || o.renk != renk;
}

/* ───────────────────────── Çizgi / alan grafiği ───────────────────────── */

class CizgiGrafik extends StatefulWidget {
  const CizgiGrafik({super.key, required this.noktalar, required this.yaz, this.yukseklik = 170, this.ozet});
  final List<Nokta> noktalar;
  final String Function(double) yaz;
  final double yukseklik;
  final String? ozet;
  @override
  State<CizgiGrafik> createState() => _CizgiGrafikState();
}

class _CizgiGrafikState extends State<CizgiGrafik> {
  int? _secili;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final n = widget.noktalar;
    if (n.length < 2) return SizedBox(height: widget.yukseklik);
    final sec = _secili ?? n.length - 1;
    return Semantics(
      label: widget.ozet,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${n[sec].uzun}  ',
                    style: TextStyle(color: r.silik, fontSize: 12.5),
                  ),
                  TextSpan(
                    text: widget.yaz(n[sec].deger),
                    style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          _Giris(
            anahtar: Object.hashAll(n.map((e) => e.deger)),
            builder: (t) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _dokun(d.localPosition.dx, context),
              onHorizontalDragUpdate: (d) => _dokun(d.localPosition.dx, context),
              child: CustomPaint(
                size: Size(double.infinity, widget.yukseklik),
                painter: _CizgiCizer(n: n, t: t, secili: sec, renk: r.birincil, eksen: r.silik, cizgi: r.kenar, zemin: r.kart),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _dokun(double x, BuildContext context) {
    final w = context.size?.width ?? 1;
    final i = (x / w * (widget.noktalar.length - 1)).round().clamp(0, widget.noktalar.length - 1);
    if (i != _secili) setState(() => _secili = i);
  }
}

class _CizgiCizer extends CustomPainter {
  _CizgiCizer({
    required this.n,
    required this.t,
    required this.secili,
    required this.renk,
    required this.eksen,
    required this.cizgi,
    required this.zemin,
  });
  final List<Nokta> n;
  final double t;
  final int secili;
  final Color renk;
  final Color eksen;
  final Color cizgi;
  final Color zemin;

  @override
  void paint(Canvas c, Size s) {
    const altPay = 18.0;
    const ustPay = 8.0;
    final h = s.height - altPay;
    final enBuyuk = math.max(1.0, n.map((e) => e.deger).fold<double>(0, math.max));
    final kalem = Paint()
      ..color = cizgi
      ..strokeWidth = 1;
    for (var k = 0; k <= 3; k++) {
      final y = ustPay + (h - ustPay) * k / 3;
      c.drawLine(Offset(0, y), Offset(s.width, y), kalem);
    }
    Offset nokta(int i) => Offset(s.width * i / (n.length - 1), ustPay + (h - ustPay) * (1 - n[i].deger / enBuyuk));
    // Yumuşak eğri (monoton kübik yaklaşımı).
    final yol = Path()..moveTo(nokta(0).dx, nokta(0).dy);
    for (var i = 1; i < n.length; i++) {
      final a = nokta(i - 1), b = nokta(i);
      final dx = (b.dx - a.dx) / 2;
      yol.cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
    }
    final metrik = yol.computeMetrics().first;
    final kismi = metrik.extractPath(0, metrik.length * t);
    // Alan dolgusu (çizginin ilerlediği yere kadar kırpılı)
    final alan = Path.from(yol)
      ..lineTo(s.width, h)
      ..lineTo(0, h)
      ..close();
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, s.width * t, s.height));
    c.drawPath(
      alan,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [renk.withValues(alpha: .28), renk.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, s.width, h)),
    );
    c.restore();
    c.drawPath(
      kismi,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(colors: [renk, Marka.mavi]).createShader(Offset.zero & s),
    );
    if (t >= .98) {
      final p = nokta(secili);
      c.drawLine(
        Offset(p.dx, ustPay),
        Offset(p.dx, h),
        Paint()
          ..color = renk.withValues(alpha: .35)
          ..strokeWidth = 1,
      );
      c.drawCircle(p, 6.5, Paint()..color = zemin);
      c.drawCircle(p, 4.5, Paint()..color = renk);
    }
    final adim = math.max(1, (n.length * 46 / s.width).ceil());
    for (var i = 0; i < n.length; i += adim) {
      final tp = TextPainter(
        text: TextSpan(
          text: n[i].etiket,
          style: TextStyle(fontSize: 10, color: eksen, fontFamily: 'Poppins'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = (s.width * i / (n.length - 1) - tp.width / 2).clamp(0.0, s.width - tp.width);
      tp.paint(c, Offset(x, h + 4));
    }
  }

  @override
  bool shouldRepaint(_CizgiCizer o) => o.t != t || o.secili != secili || o.n != n || o.renk != renk;
}

/* ───────────────────────── Halka (donut) ───────────────────────── */

class Dilim {
  const Dilim(this.etiket, this.deger, {this.alt});
  final String etiket;
  final double deger;
  final String? alt;
}

/// Halka grafik + yanında açıklama listesi. Ortada toplam yazar.
class HalkaGrafik extends StatelessWidget {
  const HalkaGrafik({super.key, required this.dilimler, required this.yaz, this.ortaBaslik = 'Toplam'});
  final List<Dilim> dilimler;
  final String Function(double) yaz;
  final String ortaBaslik;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final d = dilimler.where((e) => e.deger > 0).toList();
    final toplam = d.fold<double>(0, (a, b) => a + b.deger);
    final halka = SizedBox.square(
      dimension: 132,
      child: _Giris(
        anahtar: Object.hashAll(d.map((e) => e.deger)),
        builder: (t) => CustomPaint(
          painter: _HalkaCizer(d.map((e) => e.deger).toList(), t, r.ic),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(ortaBaslik, style: TextStyle(fontSize: 11, color: r.silik)),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Text(yaz(toplam), style: gosterim(15, renk: r.metin)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final aciklama = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < d.length; i++)
          Semantics(
            label: '${d[i].etiket}: ${yaz(d[i].deger)}, yüzde ${(d[i].deger * 100 / (toplam == 0 ? 1 : toplam)).round()}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: Marka.dizi[i % Marka.dizi.length], borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d[i].etiket,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: r.metin),
                    ),
                  ),
                  Text('%${(d[i].deger * 100 / (toplam == 0 ? 1 : toplam)).round()}', style: TextStyle(fontSize: 12, color: r.silik)),
                  const SizedBox(width: 8),
                  Text(
                    yaz(d[i].deger),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: r.metin),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (_, k) {
        if (k.maxWidth < 360) {
          return Column(children: [halka, const SizedBox(height: 14), aciklama]);
        }
        return Row(
          children: [
            halka,
            const SizedBox(width: 18),
            Expanded(child: aciklama),
          ],
        );
      },
    );
  }
}

class _HalkaCizer extends CustomPainter {
  _HalkaCizer(this.degerler, this.t, this.zemin);
  final List<double> degerler;
  final double t;
  final Color zemin;
  @override
  void paint(Canvas c, Size s) {
    final m = s.center(Offset.zero);
    final r = s.width / 2 - 9;
    final kutu = Rect.fromCircle(center: m, radius: r);
    c.drawCircle(
      m,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..color = zemin,
    );
    final toplam = degerler.fold<double>(0, (a, b) => a + b);
    if (toplam <= 0) return;
    var bas = -math.pi / 2;
    final tamTur = math.pi * 2 * t;
    for (var i = 0; i < degerler.length; i++) {
      final yay = degerler[i] / toplam * math.pi * 2;
      final ciz = math.min(yay, math.max(0.0, tamTur - (bas + math.pi / 2)));
      if (ciz > 0) {
        c.drawArc(
          kutu,
          bas + .015,
          math.max(0, ciz - .03),
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..color = Marka.dizi[i % Marka.dizi.length],
        );
      }
      bas += yay;
    }
  }

  @override
  bool shouldRepaint(_HalkaCizer o) => o.t != t || o.degerler != degerler;
}

/* ───────────────────────── Yatay çubuklu liste ───────────────────────── */

/// Sıralı liste satırı: ad + değer + altta orantılı çubuk (en çok satanlar).
class CubukSatir extends StatelessWidget {
  const CubukSatir({super.key, required this.sira, required this.ad, required this.deger, required this.oran, this.alt, this.renk});
  final int sira;
  final String ad;
  final String deger;
  final double oran;
  final String? alt;
  final Color? renk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Semantics(
      label: '$sira. $ad, $deger${alt != null ? ', $alt' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '$sira',
                    style: TextStyle(color: r.silik, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: Text(
                    ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
                if (alt != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(alt!, style: TextStyle(color: r.silik, fontSize: 12)),
                  ),
                Text(
                  deger,
                  style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: _Giris(
                anahtar: oran,
                builder: (t) => ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(height: 6, color: r.ic),
                      FractionallySizedBox(
                        widthFactor: (oran * t).clamp(0.0, 1.0),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(gradient: LinearGradient(colors: [renk ?? Marka.mor, Marka.mavi])),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ───────────────────────── Karşılaştırmalı çizgi ───────────────────────── */

/// İki dizi: [noktalar] (bu dönem, dolu alan + degrade çizgi) ve [kiyas]
/// (önceki dönem, kesikli soluk çizgi). Dokununca ikisini birden yazar.
class KarsilastirmaGrafik extends StatefulWidget {
  const KarsilastirmaGrafik({
    super.key,
    required this.noktalar,
    required this.kiyas,
    required this.yaz,
    this.yukseklik = 180,
    this.ad = 'Bugün',
    this.kiyasAdi = 'Dün',
    this.ozet,
    this.sonIndeks,
  });
  final List<Nokta> noktalar;
  final List<double> kiyas;
  final String Function(double) yaz;
  final double yukseklik;
  final String ad;
  final String kiyasAdi;
  final String? ozet;

  /// Bu dönemin çizgisi bu indekste biter (ör. şu anki saat).
  final int? sonIndeks;
  @override
  State<KarsilastirmaGrafik> createState() => _KarsilastirmaGrafikState();
}

class _KarsilastirmaGrafikState extends State<KarsilastirmaGrafik> {
  int? _secili;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final n = widget.noktalar;
    if (n.length < 2) return SizedBox(height: widget.yukseklik);
    final son = (widget.sonIndeks ?? n.length - 1).clamp(1, n.length - 1);
    final sec = (_secili ?? son).clamp(0, n.length - 1);
    final k = sec < widget.kiyas.length ? widget.kiyas[sec] : null;
    Widget lejant(Color c, String ad, {bool kesik = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(color: kesik ? c.withValues(alpha: .6) : c, borderRadius: BorderRadius.circular(1)),
        ),
        const SizedBox(width: 5),
        Text(ad, style: TextStyle(fontSize: 11.5, color: r.silik)),
      ],
    );
    return Semantics(
      label: widget.ozet,
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n[sec].uzun,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: r.silik, fontSize: 12),
                      ),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: sec <= son ? widget.yaz(n[sec].deger) : '—',
                              style: TextStyle(color: r.metin, fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            if (k != null)
                              TextSpan(
                                text: '   ${widget.kiyasAdi} ${widget.yaz(k)}',
                                style: TextStyle(color: r.silik, fontSize: 12.5),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [lejant(r.birincil, widget.ad), const SizedBox(height: 4), lejant(r.silik, widget.kiyasAdi, kesik: true)],
                ),
              ],
            ),
          ),
          _Giris(
            anahtar: Object.hashAll([...n.map((e) => e.deger), ...widget.kiyas]),
            builder: (t) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _dokun(d.localPosition.dx, context),
              onHorizontalDragUpdate: (d) => _dokun(d.localPosition.dx, context),
              child: CustomPaint(
                size: Size(double.infinity, widget.yukseklik),
                painter: _KiyasCizer(
                  n: n,
                  k: widget.kiyas,
                  son: son,
                  t: t,
                  secili: sec,
                  renk: r.birincil,
                  kiyasRenk: r.silik,
                  cizgi: r.kenar,
                  eksen: r.silik,
                  zemin: r.kart,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _dokun(double x, BuildContext context) {
    final w = context.size?.width ?? 1;
    final i = (x / w * (widget.noktalar.length - 1)).round().clamp(0, widget.noktalar.length - 1);
    if (i != _secili) setState(() => _secili = i);
  }
}

class _KiyasCizer extends CustomPainter {
  _KiyasCizer({
    required this.n,
    required this.k,
    required this.son,
    required this.t,
    required this.secili,
    required this.renk,
    required this.kiyasRenk,
    required this.cizgi,
    required this.eksen,
    required this.zemin,
  });
  final List<Nokta> n;
  final List<double> k;
  final int son;
  final double t;
  final int secili;
  final Color renk;
  final Color kiyasRenk;
  final Color cizgi;
  final Color eksen;
  final Color zemin;

  @override
  void paint(Canvas c, Size s) {
    const altPay = 18.0, ustPay = 6.0;
    final h = s.height - altPay;
    final enBuyuk = math.max(1.0, [...n.take(son + 1).map((e) => e.deger), ...k].fold<double>(0, math.max)) * 1.08;
    final kalem = Paint()
      ..color = cizgi
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = ustPay + (h - ustPay) * i / 3;
      c.drawLine(Offset(0, y), Offset(s.width, y), kalem);
    }
    double x(int i) => s.width * i / (n.length - 1);
    double y(double v) => ustPay + (h - ustPay) * (1 - v / enBuyuk);
    Path yol(List<double> d) {
      final p = Path()..moveTo(x(0), y(d[0]));
      for (var i = 1; i < d.length; i++) {
        final dx = (x(i) - x(i - 1)) / 2;
        p.cubicTo(x(i - 1) + dx, y(d[i - 1]), x(i) - dx, y(d[i]), x(i), y(d[i]));
      }
      return p;
    }

    // Kıyas (kesikli)
    if (k.length >= 2) {
      final kp = yol(k.take(n.length).toList());
      final kk = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = kiyasRenk.withValues(alpha: .6);
      for (final m in kp.computeMetrics()) {
        var d = 0.0;
        while (d < m.length * t) {
          c.drawPath(m.extractPath(d, math.min(d + 5, m.length * t)), kk);
          d += 9;
        }
      }
    }
    // Bu dönem (dolgu + çizgi) — yalnız [son]'a kadar
    final dd = n.take(son + 1).map((e) => e.deger).toList();
    if (dd.length >= 2) {
      final p = yol(dd);
      final alan = Path.from(p)
        ..lineTo(x(dd.length - 1), h)
        ..lineTo(0, h)
        ..close();
      c.save();
      c.clipRect(Rect.fromLTWH(0, 0, s.width * t, s.height));
      c.drawPath(
        alan,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [renk.withValues(alpha: .30), renk.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, s.width, h)),
      );
      c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [renk, Marka.mavi]).createShader(Offset.zero & s),
      );
      c.restore();
      if (t >= .98 && secili <= son) {
        final o = Offset(x(secili), y(dd[secili]));
        c.drawLine(
          Offset(o.dx, ustPay),
          Offset(o.dx, h),
          Paint()
            ..color = renk.withValues(alpha: .3)
            ..strokeWidth = 1,
        );
        c.drawCircle(o, 6.5, Paint()..color = zemin);
        c.drawCircle(o, 4.5, Paint()..color = renk);
      }
    }
    final adim = math.max(1, (n.length * 40 / s.width).ceil());
    for (var i = 0; i < n.length; i += adim) {
      final tp = TextPainter(
        text: TextSpan(
          text: n[i].etiket,
          style: TextStyle(fontSize: 10, color: eksen, fontFamily: 'Poppins'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset((x(i) - tp.width / 2).clamp(0.0, s.width - tp.width), h + 4));
    }
  }

  @override
  bool shouldRepaint(_KiyasCizer o) => o.t != t || o.secili != secili || o.n != n || o.k != k || o.renk != renk;
}

/* ───────────────────────── İlerleme halkası ───────────────────────── */

/// Hedefe ilerleme halkası: ortada yüzde, altında etiket.
class IlerlemeHalkasi extends StatelessWidget {
  const IlerlemeHalkasi({super.key, required this.oran, required this.etiket, this.boyut = 120, this.renk, this.kalinlik = 12, this.ortaYazi});
  final double oran;
  final String etiket;
  final double boyut;
  final Color? renk;
  final double kalinlik;
  final String? ortaYazi;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final y = (oran * 100).round();
    return Semantics(
      label: '$etiket: yüzde $y',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: boyut,
        child: _Giris(
          anahtar: oran,
          builder: (t) => CustomPaint(
            painter: _IlerlemeCizer(oran * t, renk ?? r.birincil, r.ic, kalinlik),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ortaYazi ?? '%$y', style: gosterim(boyut * .2, renk: r.metin)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: kalinlik + 6),
                    child: Text(
                      etiket,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(color: r.silik, fontSize: 10.5, height: 1.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IlerlemeCizer extends CustomPainter {
  _IlerlemeCizer(this.oran, this.renk, this.zemin, this.kalinlik);
  final double oran;
  final Color renk;
  final Color zemin;
  final double kalinlik;
  @override
  void paint(Canvas c, Size s) {
    final m = s.center(Offset.zero);
    final yr = s.width / 2 - kalinlik / 2;
    final kutu = Rect.fromCircle(center: m, radius: yr);
    c.drawCircle(
      m,
      yr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kalinlik
        ..color = zemin,
    );
    final o = oran.clamp(0.0, 1.0);
    if (o <= 0) return;
    c.drawArc(
      kutu,
      -math.pi / 2,
      math.pi * 2 * o,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kalinlik
        ..strokeCap = StrokeCap.butt
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [renk, Marka.mavi, Marka.gok, renk],
          stops: const [0, .5, .85, 1],
        ).createShader(kutu),
    );
    // Aşan kısım (oran > 1): ikinci tur ince şerit
    if (oran > 1) {
      c.drawArc(
        kutu.deflate(kalinlik * .3),
        -math.pi / 2,
        math.pi * 2 * (oran - 1).clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = kalinlik * .35
          ..color = Marka.zumrutAcik,
      );
    }
  }

  @override
  bool shouldRepaint(_IlerlemeCizer o) => o.oran != oran || o.renk != renk || o.zemin != zemin;
}

/* ───────────────────────── Mini çizgi (koyu zemin) ───────────────────────── */

/// Kapak kartındaki küçük çizgi: bu dönem beyaz-gök dolgulu, kıyas kesikli.
class MiniCizgi extends StatelessWidget {
  const MiniCizgi({super.key, required this.degerler, this.kiyas = const [], this.yukseklik = 56, this.son});
  final List<double> degerler;
  final List<double> kiyas;
  final double yukseklik;
  final int? son;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: _Giris(
      anahtar: Object.hashAll([...degerler, ...kiyas]),
      builder: (t) => CustomPaint(size: Size(double.infinity, yukseklik), painter: _MiniCizer(degerler, kiyas, t, son)),
    ),
  );
}

class _MiniCizer extends CustomPainter {
  _MiniCizer(this.d, this.k, this.t, this.son);
  final List<double> d;
  final List<double> k;
  final double t;
  final int? son;
  @override
  void paint(Canvas c, Size s) {
    final adet = math.max(d.length, k.length);
    if (adet < 2) return;
    final sonI = (son ?? d.length - 1).clamp(0, d.length - 1);
    final enBuyuk = math.max(1.0, [...d.take(sonI + 1), ...k].fold<double>(0, math.max)) * 1.1;
    double x(int i) => s.width * i / (adet - 1);
    double y(double v) => s.height - 2 - (s.height - 6) * v / enBuyuk;
    Path yol(List<double> v) {
      final p = Path()..moveTo(x(0), y(v[0]));
      for (var i = 1; i < v.length; i++) {
        final dx = (x(i) - x(i - 1)) / 2;
        p.cubicTo(x(i - 1) + dx, y(v[i - 1]), x(i) - dx, y(v[i]), x(i), y(v[i]));
      }
      return p;
    }

    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, s.width * t, s.height));
    if (k.length >= 2) {
      final kk = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withValues(alpha: .38);
      for (final m in yol(k).computeMetrics()) {
        for (var q = 0.0; q < m.length; q += 8) {
          c.drawPath(m.extractPath(q, math.min(q + 4, m.length)), kk);
        }
      }
    }
    final dd = d.take(sonI + 1).toList();
    if (dd.length >= 2) {
      final p = yol(dd);
      final alan = Path.from(p)
        ..lineTo(x(dd.length - 1), s.height)
        ..lineTo(0, s.height)
        ..close();
      c.drawPath(
        alan,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Marka.gok.withValues(alpha: .45), Marka.gok.withValues(alpha: 0)],
          ).createShader(Offset.zero & s),
      );
      c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Colors.white,
      );
      final o = Offset(x(dd.length - 1), y(dd.last));
      c.drawCircle(o, 5.5, Paint()..color = Marka.gok.withValues(alpha: .35));
      c.drawCircle(o, 3, Paint()..color = Colors.white);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_MiniCizer o) => o.t != t || o.d != d || o.k != k;
}
