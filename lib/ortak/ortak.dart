import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dugme.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/tema.dart';

/* ───────────────────────── Bildirim (snackbar) ───────────────────────── */

final mesajci = GlobalKey<ScaffoldMessengerState>();

enum BildirimTur { basari, hata, uyari, bilgi }

void bildir(String baslik, {String? mesaj, BildirimTur tur = BildirimTur.basari}) {
  final m = mesajci.currentState;
  if (m == null) return;
  final (ikon, renk) = switch (tur) {
    BildirimTur.basari => (Icons.check_circle_rounded, Marka.zumrutAcik),
    BildirimTur.hata => (Icons.error_rounded, Marka.gulAcik),
    BildirimTur.uyari => (Icons.warning_rounded, Marka.kehribarAcik),
    BildirimTur.bilgi => (Icons.notifications_rounded, Marka.gok),
  };
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: Marka.murekkep,
      content: Row(children: [
        Icon(ikon, color: renk, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (mesaj != null && mesaj.isNotEmpty)
              Text(mesaj, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
      ]),
    ));
}

/* ───────────────────────── Marka işareti ───────────────────────── */

/// PATRON İŞARETİ (2026-10-27, yeni): yükselen üç tepeli TAÇ — tepeler soldan
/// sağa yükselen bir grafik gibi dizilir (patronun "işler nasıl gidiyor"
/// sorusu), ortada işletmeyi gözeten GÖZ boşluğu, en yüksek tepede gök
/// mavisi mücevher. Zemin mor→mavi marka geçişi. POS (QR) ve personel
/// işaretlerinden ayrışır. 64×64 koordinat düzleminde çizer.
///
/// Açılış animasyonu payları (0..1): [kare] taç parçaları aşağıdan gelip
/// birleşir · [rozet] mücevher yerine oturur · [cubuk] taban şeridi uzar.
class PatronMarkCizer extends CustomPainter {
  const PatronMarkCizer({this.zeminVar = true, this.cubuk = 1, this.kare = 1, this.rozet = 1, this.koseli = true});

  /// false: yalnız beyaz şekiller (uyarlanabilir simgenin ön planı).
  final bool zeminVar;

  /// false: zemin tam kare (iOS simgesi; köşeyi sistem keser).
  final bool koseli;
  final double kare;
  final double rozet;
  final double cubuk;

  // Taç gövdesi üç parça (vadilerden bölünür) — birleşince tek şekil.
  static const _sol = [Offset(14, 43), Offset(14, 28), Offset(25, 35.5), Offset(25, 43)];
  static const _orta = [Offset(25, 43), Offset(25, 35.5), Offset(32, 20), Offset(39, 31), Offset(39, 43)];
  static const _sag = [Offset(39, 43), Offset(39, 31), Offset(48.5, 15.5), Offset(48.5, 43)];
  static const _tum = [Offset(14, 43), Offset(14, 28), Offset(25, 35.5), Offset(32, 20), Offset(39, 31), Offset(48.5, 15.5), Offset(48.5, 43)];

  static Path _yol(List<Offset> n) {
    final p = Path()..moveTo(n.first.dx, n.first.dy);
    for (final o in n.skip(1)) {
      p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  static void ciz(Canvas c, {bool zeminVar = true, bool koseli = true, double kare = 1, double rozet = 1, double cubuk = 1}) {
    const alan = Rect.fromLTWH(0, 0, 64, 64);
    if (zeminVar) {
      final rr = RRect.fromRectAndRadius(alan, Radius.circular(koseli ? 14 : 0));
      c.drawRRect(
          rr,
          Paint()
            ..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Marka.morAcik, Marka.mor, Marka.mavi])
                .createShader(alan));
      // Üstte ince parlaklık + sağ altta gök ışığı (derinlik; bulanıklık yok)
      c.drawRRect(
          rr,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [Colors.white.withValues(alpha: .16), Colors.white.withValues(alpha: 0)],
            ).createShader(alan));
      c.drawRRect(
          rr,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(.9, .9),
              radius: .9,
              colors: [Marka.gok.withValues(alpha: .35), Marka.gok.withValues(alpha: 0)],
            ).createShader(alan));
    }
    // Şekiller zeminin optik ortasına (ağırlık sağdaki mücevherde) hafif küçültülerek oturur.
    c.save();
    c.translate(32, 32.5);
    c.scale(.86);
    c.translate(-33.4, -30.2);
    final beyaz = Paint()..color = Colors.white;
    final yumusat = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    // ── Taç: üç parça aşağıdan sırayla yükselip birleşir
    if (kare > 0) {
      if (kare >= 1) {
        final g = _yol(_tum);
        c.drawPath(g, beyaz);
        c.drawPath(g, yumusat);
      } else {
        for (final (i, parca) in [_sol, _orta, _sag].indexed) {
          final p = Curves.easeOutBack.transform(((kare - i * .18) / .64).clamp(0.0, 1.0));
          if (p <= 0) continue;
          c.save();
          c.translate(0, 22 * (1 - p));
          final y = _yol(parca);
          final boya = Paint()..color = Colors.white.withValues(alpha: p.clamp(0.0, 1.0));
          c.drawPath(y, boya);
          c.drawPath(
              y,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..strokeJoin = StrokeJoin.round
                ..color = boya.color);
          c.restore();
        }
      }
      // Göz: ortada marka renginde badem + gök bebek (işletmeyi gözeten patron)
      final g = ((kare - .55) / .45).clamp(0.0, 1.0);
      if (g > 0) {
        c.save();
        c.translate(32, 36);
        c.scale(1, g);
        final badem = Path()
          ..moveTo(-6.5, 0)
          ..quadraticBezierTo(0, -6.2, 6.5, 0)
          ..quadraticBezierTo(0, 6.2, -6.5, 0)
          ..close();
        c.drawPath(badem, Paint()..color = zeminVar ? Marka.mor : Colors.transparent);
        if (!zeminVar) {
          // ön plan katmanında göz "delik" olarak açılır
          c.drawPath(badem, Paint()..blendMode = BlendMode.clear);
        }
        c.drawCircle(Offset.zero, 2.4, Paint()..color = zeminVar ? Marka.gok : Colors.white);
        c.restore();
      }
      // Sol ve orta tepede küçük inciler
      final inci = ((kare - .7) / .3).clamp(0.0, 1.0);
      if (inci > 0) {
        c.drawCircle(const Offset(14, 28), 2.9 * inci, beyaz);
        c.drawCircle(const Offset(32, 20), 3.1 * inci, beyaz);
      }
    }

    // ── Taban şeridi: ortadan iki yana uzar
    if (cubuk > 0) {
      final w = 36.0 * Curves.easeOutCubic.transform(cubuk.clamp(0.0, 1.0));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(31.25, 49.5), width: w, height: 5.6), const Radius.circular(2.8)), beyaz);
    }

    // ── En yüksek tepede gök mavisi mücevher
    if (rozet > 0) {
      c.save();
      c.translate(48.5, 15.5);
      c.scale(rozet);
      c.drawCircle(Offset.zero, 5.2, Paint()..color = Marka.gok);
      c.drawCircle(Offset.zero, 5.2, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = Colors.white);
      c.drawCircle(const Offset(-1.5, -1.5), 1.3, Paint()..color = Colors.white.withValues(alpha: .85));
      c.restore();
    }
    c.restore();
  }

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 64, s.height / 64);
    if (!zeminVar) c.saveLayer(const Rect.fromLTWH(0, 0, 64, 64), Paint());
    ciz(c, zeminVar: zeminVar, koseli: koseli, kare: kare, rozet: rozet, cubuk: cubuk);
    if (!zeminVar) c.restore();
    c.restore();
  }

  @override
  bool shouldRepaint(PatronMarkCizer o) => o.kare != kare || o.rozet != rozet || o.cubuk != cubuk || o.zeminVar != zeminVar || o.koseli != koseli;
}

class PaMark extends StatelessWidget {
  const PaMark({super.key, this.boyut = 40});
  final double boyut;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CustomPaint(size: Size.square(boyut), painter: const PatronMarkCizer()));
}

/* ───────────────────────── Kart / başlık / satır ───────────────────────── */

class PaKart extends StatelessWidget {
  const PaKart({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.etiket, this.renk});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String? etiket;
  final Color? renk;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final kutu = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: renk ?? r.kart,
        borderRadius: Marka.yaricap,
        border: Border.all(color: r.kenar),
      ),
      child: child,
    );
    if (onTap == null) return etiket == null ? kutu : Semantics(label: etiket, container: true, child: kutu);
    return Basilir(onTap: onTap, etiket: etiket, child: kutu);
  }
}

class BolumBasligi extends StatelessWidget {
  const BolumBasligi(this.baslik, {super.key, this.alt, this.sag, this.ikon});
  final String baslik;
  final String? alt;
  final Widget? sag;
  final IconData? ikon;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (ikon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: Marka.yaricap),
            child: Icon(ikon, size: 17, color: r.birincil),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(header: true, child: Text(baslik, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: r.metin))),
            if (alt != null) Text(alt!, style: TextStyle(fontSize: 12.5, color: r.silik)),
          ]),
        ),
        ?sag,
      ]),
    );
  }
}

class Satir extends StatelessWidget {
  const Satir({super.key, required this.baslik, this.alt, this.ikon, this.sag, this.onTap, this.ikonRenk});
  final String baslik;
  final String? alt;
  final IconData? ikon;
  final Widget? sag;
  final VoidCallback? onTap;
  final Color? ikonRenk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final icerik = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        if (ikon != null) ...[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: (ikonRenk ?? r.birincil).withValues(alpha: r.koyu ? .22 : .1), borderRadius: Marka.yaricap),
            child: Icon(ikon, size: 20, color: ikonRenk ?? r.birincil),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: r.metin)),
            if (alt != null) Text(alt!, style: TextStyle(fontSize: 12.5, color: r.silik)),
          ]),
        ),
        if (sag != null) sag! else if (onTap != null) Icon(Icons.chevron_right_rounded, color: r.silik),
      ]),
    );
    return onTap == null ? Semantics(container: true, child: icerik) : Basilir(onTap: onTap, etiket: baslik, olcek: .98, child: icerik);
  }
}

/// Satırları tek kartta çizgiyle ayırır.
class SatirGrubu extends StatelessWidget {
  const SatirGrubu(this.satirlar, {super.key});
  final List<Widget> satirlar;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Container(
      decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < satirlar.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: r.kenar, indent: 14, endIndent: 14),
          satirlar[i],
        ],
      ]),
    );
  }
}

/* ───────────────────────── Sayı / rozet ───────────────────────── */

/// Sayıyı önceki değerinden yenisine sayarak yazar. "Animasyonları azalt"
/// açıksa doğrudan son değeri yazar. Ekran okuyucu son değeri okur.
class SayacMetin extends StatefulWidget {
  const SayacMetin({super.key, required this.deger, required this.yaz, this.stil, this.sure = const Duration(milliseconds: 250)});
  final num deger;
  final String Function(num) yaz;
  final TextStyle? stil;
  final Duration sure;
  @override
  State<SayacMetin> createState() => _SayacMetinState();
}

class _SayacMetinState extends State<SayacMetin> {
  double _bas = 0;

  @override
  void didUpdateWidget(SayacMetin o) {
    super.didUpdateWidget(o);
    if (o.deger != widget.deger) _bas = o.deger.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final son = widget.yaz(widget.deger);
    if (Hareket.kapali(context)) return Text(son, style: widget.stil, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Semantics(
      label: son,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        key: ValueKey(widget.deger),
        tween: Tween(begin: _bas, end: widget.deger.toDouble()),
        duration: widget.sure,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text(
          v == widget.deger.toDouble() ? son : widget.yaz(widget.deger is int ? v.round() : v),
          style: widget.stil,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Önceki döneme göre değişim rozeti: ▲ %12,4 (yeşil) / ▼ %3 (kırmızı).
class DegisimRozeti extends StatelessWidget {
  const DegisimRozeti(this.yuzde, {super.key, this.tersi = false, this.koyuZemin = false});
  final double? yuzde;

  /// true: artış kötüdür (iptal, indirim).
  final bool tersi;
  final bool koyuZemin;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final y = yuzde;
    if (y == null) return const SizedBox.shrink();
    final iyi = tersi ? y < 0 : y > 0;
    final notr = y == 0;
    final renk = notr
        ? (koyuZemin ? Colors.white70 : r.silik)
        : iyi
            ? (koyuZemin ? Marka.zumrutAcik : r.arti)
            : (koyuZemin ? Marka.gulAcik : r.eksi);
    final metin = '%${y.abs().toStringAsFixed(y.abs() >= 10 ? 0 : 1).replaceAll('.', ',')}';
    final ok = y > 0 ? Icons.arrow_upward_rounded : y < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded;
    return Semantics(
      label: notr ? 'Değişim yok' : (y > 0 ? 'Yüzde ${y.abs()} artış' : 'Yüzde ${y.abs()} düşüş'),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: renk.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ok, size: 12, color: renk),
          const SizedBox(width: 2),
          Text(metin, style: TextStyle(color: renk, fontWeight: FontWeight.w700, fontSize: 11.5)),
        ]),
      ),
    );
  }
}

/* ───────────────────────── Yükleme / boş / hata ───────────────────────── */

class Yukleyici extends StatelessWidget {
  const Yukleyici({super.key, this.boyut = 28, this.renk});
  final double boyut;
  final Color? renk;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Yükleniyor',
        child: SizedBox.square(
          dimension: boyut,
          child: CircularProgressIndicator(strokeWidth: 3, strokeCap: StrokeCap.round, color: renk ?? context.pa.birincil),
        ),
      );
}

/// Yüklenirken ışıltılı gri kutu.
class Iskelet extends StatefulWidget {
  const Iskelet({super.key, this.yukseklik = 16, this.genislik});
  final double yukseklik;
  final double? genislik;
  @override
  State<Iskelet> createState() => _IskeletState();
}

class _IskeletState extends State<Iskelet> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Hareket.kapali(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          height: widget.yukseklik,
          width: widget.genislik,
          decoration: BoxDecoration(
            borderRadius: Marka.yaricap,
            gradient: LinearGradient(
              begin: Alignment(-1.5 + 3 * _c.value, 0),
              end: Alignment(-0.5 + 3 * _c.value, 0),
              colors: [r.ic, r.koyu ? r.kenar : Colors.white, r.ic],
            ),
          ),
        ),
      ),
    );
  }
}

class BosDurum extends StatelessWidget {
  const BosDurum({super.key, required this.baslik, this.mesaj, this.ikon = Icons.inbox_rounded});
  final String baslik;
  final String? mesaj;
  final IconData ikon;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        Icon(ikon, size: 40, color: r.silik),
        const SizedBox(height: 10),
        Text(baslik, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700, color: r.metin)),
        if (mesaj != null) ...[
          const SizedBox(height: 4),
          Text(mesaj!, textAlign: TextAlign.center, style: TextStyle(color: r.silik, fontSize: 13)),
        ],
      ]),
    );
  }
}

class HataDurum extends StatelessWidget {
  const HataDurum({super.key, required this.hata, required this.yenile});
  final Object hata;
  final VoidCallback yenile;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final h = hata;
    final mesaj = h is ApiHata ? h.mesaj : 'Beklenmeyen bir sorun oluştu.';
    final ikon = h is ApiHata && h.baglantiYok
        ? Icons.wifi_off_rounded
        : h is ApiHata && h.yetkiYok
            ? Icons.lock_rounded
            : Icons.error_outline_rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(children: [
        Icon(ikon, size: 40, color: r.eksi),
        const SizedBox(height: 10),
        Text(mesaj, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: r.metin)),
        const SizedBox(height: 14),
        YumusakDugme(onTap: yenile, ikon: Icons.refresh_rounded, yazi: 'Tekrar dene'),
      ]),
    );
  }
}

/* ───────────────────────── Sayfa iskeleti ───────────────────────── */

/// Sekme/sayfa gövdesi: büyük başlık + aşağı çekip yenileme + tablette
/// ortalanmış en çok 760 px genişlik.
class PaSayfa extends StatelessWidget {
  const PaSayfa({super.key, required this.baslik, this.alt, required this.children, this.yenile, this.sag, this.geri = false, this.altBosluk = 24});
  final String baslik;
  final String? alt;
  final List<Widget> children;
  final Future<void> Function()? yenile;
  final Widget? sag;
  final bool geri;
  final double altBosluk;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final ust = MediaQuery.paddingOf(context).top;
    final liste = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(0, ust + 8, 0, altBosluk),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  if (geri)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        tooltip: 'Geri',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.arrow_back_rounded, color: r.metin),
                      ),
                    ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Semantics(header: true, child: Text(baslik, style: gosterim(geri ? 22 : 26, renk: r.metin))),
                      if (alt != null) Text(alt!, style: TextStyle(color: r.silik, fontSize: 13)),
                    ]),
                  ),
                  ?sag,
                ]),
                const SizedBox(height: 14),
                ...children,
              ]),
            ),
          ),
        ),
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.durumCubugu(),
      child: Scaffold(
        body: Stack(children: [
          yenile == null ? liste : RefreshIndicator(onRefresh: yenile!, color: r.birincil, edgeOffset: ust, child: liste),
          // Durum çubuğu şeridi: içerik kayarken saat/şarj simgelerinin
          // altına yazı girmesin (opak zemin, bulanıklık yok).
          Positioned(top: 0, left: 0, right: 0, height: ust, child: ColoredBox(color: r.zemin)),
        ]),
      ),
    );
  }
}

/* ───────────────────────── Gece zemin ───────────────────────── */

/// Lacivert zemin + yavaşça yer değiştiren mor/mavi ışık lekeleri
/// (eşleme ekranı). Animasyonları azalt açıksa durağandır.
class GeceZemin extends StatefulWidget {
  const GeceZemin({super.key, required this.child});
  final Widget child;
  @override
  State<GeceZemin> createState() => _GeceZeminState();
}

class _GeceZeminState extends State<GeceZemin> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Hareket.kapali(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: Marka.gece),
        child: CustomPaint(
          painter: _IsikCizer(_c),
          child: widget.child,
        ),
      );
}

class _IsikCizer extends CustomPainter {
  _IsikCizer(this.a) : super(repaint: a);
  final Animation<double> a;
  @override
  void paint(Canvas c, Size s) {
    final t = a.value * math.pi * 2;
    void leke(Offset m, double r, Color renk) => c.drawCircle(
        m,
        r,
        Paint()
          ..shader = RadialGradient(colors: [renk, renk.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: m, radius: r)));
    leke(Offset(s.width * (.15 + .1 * math.sin(t)), s.height * (.12 + .05 * math.cos(t))), s.width * .8, Marka.mor.withValues(alpha: .42));
    leke(Offset(s.width * (.95 - .1 * math.cos(t)), s.height * (.55 + .08 * math.sin(t))), s.width * .7, Marka.mavi.withValues(alpha: .30));
    leke(Offset(s.width * (.4 + .12 * math.cos(t * 2)), s.height * (1.0 - .04 * math.sin(t))), s.width * .6, Marka.gok.withValues(alpha: .14));
  }

  @override
  bool shouldRepaint(_IsikCizer o) => false;
}
