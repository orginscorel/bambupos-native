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
  const _Giris({required this.anahtar, required this.builder, this.sure = const Duration(milliseconds: 900)});
  final Object anahtar;
  final Widget Function(double t) builder;
  final Duration sure;
  @override
  State<_Giris> createState() => _GirisState();
}

class _GirisState extends State<_Giris> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.sure);

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
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (_, _) => widget.builder(Curves.easeOutCubic.transform(_c.value)));
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 22,
          child: secNokta == null
              ? null
              : Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${secNokta.uzun}  ', style: TextStyle(color: r.silik, fontSize: 12.5)),
                    TextSpan(text: widget.yaz(secNokta.deger), style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
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
      ]),
    );
  }

  void _dokun(double x, BuildContext context) {
    final w = (context.size?.width ?? 1);
    final i = (x / w * widget.noktalar.length).floor().clamp(0, widget.noktalar.length - 1);
    if (i != _secili) setState(() => _secili = i);
  }
}

class _SutunCizer extends CustomPainter {
  _SutunCizer({required this.n, required this.enBuyuk, required this.t, required this.secili, required this.renk, required this.soluk, required this.eksen, required this.cizgi});
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
        p.shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [renk, Color.lerp(renk, Marka.mavi, .55)!])
            .createShader(rect);
      } else {
        p.color = soluk;
      }
      c.drawRRect(RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), p);
      if (i % adim == 0) {
        final tp = TextPainter(
          text: TextSpan(text: n[i].etiket, style: TextStyle(fontSize: 10, color: eksen, fontFamily: 'Poppins')),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 22,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${n[sec].uzun}  ', style: TextStyle(color: r.silik, fontSize: 12.5)),
            TextSpan(text: widget.yaz(n[sec].deger), style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13)),
          ])),
        ),
        _Giris(
          anahtar: Object.hashAll(n.map((e) => e.deger)),
          sure: const Duration(milliseconds: 1100),
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
      ]),
    );
  }

  void _dokun(double x, BuildContext context) {
    final w = context.size?.width ?? 1;
    final i = (x / w * (widget.noktalar.length - 1)).round().clamp(0, widget.noktalar.length - 1);
    if (i != _secili) setState(() => _secili = i);
  }
}

class _CizgiCizer extends CustomPainter {
  _CizgiCizer({required this.n, required this.t, required this.secili, required this.renk, required this.eksen, required this.cizgi, required this.zemin});
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
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [renk.withValues(alpha: .28), renk.withValues(alpha: 0)])
              .createShader(Rect.fromLTWH(0, 0, s.width, h)));
    c.restore();
    c.drawPath(
        kismi,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(colors: [renk, Marka.mavi]).createShader(Offset.zero & s));
    if (t >= .98) {
      final p = nokta(secili);
      c.drawLine(Offset(p.dx, ustPay), Offset(p.dx, h), Paint()..color = renk.withValues(alpha: .35)..strokeWidth = 1);
      c.drawCircle(p, 6.5, Paint()..color = zemin);
      c.drawCircle(p, 4.5, Paint()..color = renk);
    }
    final adim = math.max(1, (n.length * 46 / s.width).ceil());
    for (var i = 0; i < n.length; i += adim) {
      final tp = TextPainter(
        text: TextSpan(text: n[i].etiket, style: TextStyle(fontSize: 10, color: eksen, fontFamily: 'Poppins')),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(ortaBaslik, style: TextStyle(fontSize: 11, color: r.silik)),
              FittedBox(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text(yaz(toplam), style: gosterim(15, renk: r.metin)))),
            ]),
          ),
        ),
      ),
    );
    final aciklama = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < d.length; i++)
        Semantics(
          label: '${d[i].etiket}: ${yaz(d[i].deger)}, yüzde ${(d[i].deger * 100 / (toplam == 0 ? 1 : toplam)).round()}',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: Marka.dizi[i % Marka.dizi.length], borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Expanded(child: Text(d[i].etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: r.metin))),
              Text('%${(d[i].deger * 100 / (toplam == 0 ? 1 : toplam)).round()}', style: TextStyle(fontSize: 12, color: r.silik)),
              const SizedBox(width: 8),
              Text(yaz(d[i].deger), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: r.metin)),
            ]),
          ),
        ),
    ]);
    return LayoutBuilder(builder: (_, k) {
      if (k.maxWidth < 360) {
        return Column(children: [halka, const SizedBox(height: 14), aciklama]);
      }
      return Row(children: [halka, const SizedBox(width: 18), Expanded(child: aciklama)]);
    });
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
    c.drawCircle(m, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 16..color = zemin);
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 22, child: Text('$sira', style: TextStyle(color: r.silik, fontWeight: FontWeight.w700, fontSize: 12.5))),
            Expanded(child: Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5))),
            if (alt != null) Padding(padding: const EdgeInsets.only(right: 10), child: Text(alt!, style: TextStyle(color: r.silik, fontSize: 12))),
            Text(deger, style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: _Giris(
              anahtar: oran,
              builder: (t) => ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(height: 6, color: r.ic),
                  FractionallySizedBox(
                    widthFactor: (oran * t).clamp(0.0, 1.0),
                    child: Container(height: 6, decoration: BoxDecoration(gradient: LinearGradient(colors: [renk ?? Marka.mor, Marka.mavi]))),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
