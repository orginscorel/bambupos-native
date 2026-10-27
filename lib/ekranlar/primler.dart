import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/guncelleme.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'davet.dart';
import 'kabuk.dart';

/// PRİMLERİM — kişinin prim kazancı (web: Portal/Earnings.vue).
/// Dönem seçici, sayaçlı tutar kartı, hedef çubuğu, satış/sipariş/mesai;
/// prim planı yoksa illüstrasyonlu boş durum.
class PrimlerEkrani extends StatefulWidget {
  const PrimlerEkrani({super.key});
  @override
  State<PrimlerEkrani> createState() => _PrimlerEkraniState();
}

class _PrimlerEkraniState extends State<PrimlerEkrani> {
  static const _donemler = [('day', 'Bugün'), ('week', 'Bu hafta'), ('month', 'Bu ay')];
  int _donem = 2;
  Map<String, dynamic>? _veri;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    if (!Uyg.eklenti('commission')) {
      setState(() {
        _veri = const {'enabled': false};
        _yukleniyor = false;
      });
      return;
    }
    setState(() => _yukleniyor = true);
    try {
      final r = await Uyg.api.get('/api/v1/portal/earnings', sorgu: {'period': _donemler[_donem].$1});
      if (!mounted) return;
      setState(() => _veri = Map<String, dynamic>.from(r as Map));
    } on ApiHata catch (e) {
      if (e.kod == 404) {
        setState(() => _veri = const {'enabled': false});
      } else {
        bildir('Primler yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  bool get _var => _veri?['enabled'] == true && _veri?['scheme_name'] != null;
  int _i(String k) => (_veri?[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return PaSayfa(
      baslik: 'Primlerim',
      yenile: _yukle,
      govde: Kaydir(children: [
        _segment(),
        const SizedBox(height: 16),
        if (_yukleniyor && _veri == null)
          const PaKart(child: Iskelet(yukseklik: 180))
        else if (_var) ...[
          _tutarKarti(),
          const SizedBox(height: 14),
          _ozet(),
        ] else
          _bos(),
        if (!Guncelleme.magazaKurulumu) ...[
          const SizedBox(height: 16),
          PaKart(
            onTap: () => git(context, const DavetEkrani()),
            child: Row(children: [
              const PaIkon(Icons.auto_awesome_rounded, grad: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Davet et, kazan', style: gosterim(16, renk: context.pa.metin)),
                  Text('İşletme öner, abonelik gelirinden pay al', style: TextStyle(color: context.pa.soluk, fontSize: 12)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.pa.silik),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _segment() {
    final r = context.pa;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(18), border: Border.all(color: r.kenar), boxShadow: r.golge),
      child: LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth / 3;
        return Stack(fit: StackFit.expand, children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            left: w * _donem,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(14))),
          ),
          Row(children: [
            for (var i = 0; i < 3; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_donem == i) return;
                    titret();
                    setState(() => _donem = i);
                    _yukle();
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13.5, color: _donem == i ? Colors.white : r.soluk),
                      child: Text(_donemler[i].$2),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }

  Widget _tutarKarti() {
    final hedef = _i('target_minor');
    final oran = hedef > 0 ? math.min(1.0, _i('sales_minor') / hedef) : null;
    return PaKart(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Marka.lacivert1, Color(0xFF3B2FA8), Marka.mor]),
      padding: const EdgeInsets.all(20),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          right: -18,
          top: -18,
          child: Icon(Icons.monetization_on_outlined, size: 140, color: Colors.white.withValues(alpha: .08)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((_veri?['scheme_name']?.toString() ?? '').toUpperCase(),
              style: TextStyle(color: const Color(0xFFC7D2FE).withValues(alpha: .85), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Sayac(deger: _i('commission_minor'), yaz: paraYaz, stil: gosterim(38, renk: Colors.white, satir: 1)),
          const SizedBox(height: 4),
          Text('kazanılan prim', style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 13.5)),
          if (oran != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: Container(
                height: 10,
                color: Colors.white.withValues(alpha: .15),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: oran),
                  duration: const Duration(milliseconds: 1100),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: v,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: const LinearGradient(colors: [Color(0xFF7DD3FC), Color(0xFFC4B5FD)]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text('Hedef %${(oran * 100).round()}', style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12)),
              const Spacer(),
              Text(paraYaz(hedef), style: gosterim(12.5, agirlik: FontWeight.w600, renk: Colors.white70)),
            ]),
          ],
          if (_veri?['target_met'] == true) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: Marka.zumrut.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: const Color(0xFF6EE7B7).withValues(alpha: .35)),
              ),
              child: const Text('Hedef tuttu 🎉', style: TextStyle(color: Color(0xFFA7F3D0), fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _ozet() {
    final r = context.pa;
    final kutular = [
      ('Satış', paraYaz(_i('sales_minor')), Icons.trending_up_rounded),
      ('Sipariş', '${_i('order_count')}', Icons.receipt_long_rounded),
      ('Mesai', dakikaYaz(_i('worked_min')), Icons.schedule_rounded),
    ];
    return Row(children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Belir(
            gecikme: 60 * i,
            child: PaKart(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: Column(children: [
                Icon(kutular[i].$3, color: r.birincil, size: 20),
                const SizedBox(height: 6),
                FittedBox(fit: BoxFit.scaleDown, child: Text(kutular[i].$2, style: gosterim(16.5, renk: r.metin))),
                Text(kutular[i].$1, style: TextStyle(color: r.soluk, fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _bos() {
    final r = context.pa;
    return PaKart(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
      child: Column(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutBack,
          builder: (_, v, _) => CustomPaint(size: const Size(150, 110), painter: _CuzdanCizer(v, r)),
        ),
        const SizedBox(height: 12),
        Text('Prim planın yok', style: gosterim(20, renk: r.metin)),
        const SizedBox(height: 6),
        Text(
          'Yöneticin sana bir prim planı tanımladığında kazancın ve hedefin burada anlık görünür.',
          textAlign: TextAlign.center,
          style: TextStyle(color: r.soluk, fontSize: 13.5, height: 1.4),
        ),
      ]),
    );
  }
}

/// Boş durum illüstrasyonu: cüzdan + kıvılcımlar.
class _CuzdanCizer extends CustomPainter {
  _CuzdanCizer(this.t, this.r);
  final double t;
  final PaRenk r;
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 120;
    c.scale(k);
    c.drawOval(const Rect.fromLTWH(22, 82, 76, 12), Paint()..color = r.ic);
    c.save();
    c.translate(0, 14 * (1 - t));
    final govde = RRect.fromRectAndRadius(const Rect.fromLTWH(28, 30, 64, 44), const Radius.circular(12));
    c.drawRRect(govde, Paint()..color = r.birincilYumusak);
    c.drawRect(const Rect.fromLTWH(28, 40, 64, 9), Paint()..color = r.birincil.withValues(alpha: .25));
    c.drawCircle(const Offset(78, 60), 6, Paint()..color = r.birincil);
    c.restore();
    final p = Paint()..color = Marka.kehribar.withValues(alpha: t.clamp(0, 1));
    c.drawCircle(const Offset(30, 18), 5 * t, p);
    c.drawCircle(const Offset(92, 20), 3.5 * t, p);
    c.drawCircle(const Offset(100, 40), 2.5 * t, p);
  }

  @override
  bool shouldRepaint(_CuzdanCizer o) => o.t != t || o.r != r;
}
