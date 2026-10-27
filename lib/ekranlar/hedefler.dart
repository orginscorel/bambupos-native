import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// HEDEFLERİM — bu ayın ilerlemesi (web: Portal/Goals.vue).
/// Genel ilerleme halkası + mesai/devam/görev/mola kartları + (prim planı
/// varsa) satış hedefi + "Bu ayın özeti" (raporlar, aynı sayfada açılır).
class HedeflerEkrani extends StatefulWidget {
  const HedeflerEkrani({super.key});
  @override
  State<HedeflerEkrani> createState() => _HedeflerEkraniState();
}

class _HedeflerEkraniState extends State<HedeflerEkrani> {
  Map<String, dynamic>? _h;
  Map<String, dynamic>? _prim;
  Map<String, dynamic>? _rapor;
  bool _yukleniyor = true;
  bool _ozetAcik = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final sonuc = await Future.wait<dynamic>([
        Uyg.api.get('/api/v1/portal/hedefler'),
        if (Uyg.eklenti('commission')) Uyg.api.get('/api/v1/portal/earnings', sorgu: {'period': 'month'}).catchError((_) => null),
        Uyg.api.get('/api/v1/portal/reports', sorgu: {'period': 'month'}).catchError((_) => null),
      ]);
      final h = Map<String, dynamic>.from(sonuc.first as Map);
      Map<String, dynamic>? prim;
      Map<String, dynamic>? rapor;
      if (Uyg.eklenti('commission')) {
        final p = sonuc[1];
        if (p is Map && p['scheme_name'] != null) prim = Map<String, dynamic>.from(p);
        if (sonuc[2] is Map) rapor = Map<String, dynamic>.from(sonuc[2] as Map);
      } else if (sonuc[1] is Map) {
        rapor = Map<String, dynamic>.from(sonuc[1] as Map);
      }
      if (!mounted) return;
      setState(() {
        _h = h;
        _prim = prim;
        _rapor = rapor;
      });
    } on ApiHata catch (e) {
      bildir('Hedefler yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

  List<_Hedef> get _kartlar {
    final h = _h;
    if (h == null) return const [];
    final m = (h['mesai'] as Map?) ?? const {};
    final d = (h['devam'] as Map?) ?? const {};
    final g = (h['gorev'] as Map?) ?? const {};
    final mo = (h['mola'] as Map?) ?? const {};
    final plan = _i(m['plan_min']);
    final cal = _i(m['calisilan_min']);
    final planGun = _i(d['plan_gun']);
    final calGun = _i(d['calisilan_gun']);
    final gT = _i(g['toplam']);
    final gTamam = _i(g['tamam']);
    final gecik = _i(g['geciken']);
    final hak = _i(mo['hak_dk']);
    final asim = _i(mo['asim_gun']);
    return [
      _Hedef('Mesai saati', dakikaYaz(cal), plan > 0 ? 'Plan ${dakikaYaz(plan)}' : 'Bu ay planlı shift yok',
          plan > 0 ? cal / plan : null, Icons.schedule_rounded, const [Color(0xFF38BDF8), Color(0xFF2563EB)]),
      _Hedef('Devam', '$calGun gün', planGun > 0 ? '$planGun planlı günün ${math.min(calGun, planGun)}’inde geldin' : 'Çalıştığın gün sayısı',
          planGun > 0 ? calGun / planGun : null, Icons.calendar_month_rounded, const [Color(0xFF34D399), Color(0xFF0D9488)]),
      _Hedef('Görevler', '$gTamam / $gT', gT > 0 ? 'Tamamlanan görev' : 'Bu ay görev atanmadı', gT > 0 ? gTamam / gT : null,
          Icons.assignment_turned_in_rounded, const [Color(0xFFA78BFA), Marka.mor],
          rozet: gecik > 0 ? ('$gecik gecikmiş', Marka.gul) : null),
      _Hedef('Mola disiplini', asim > 0 ? '$asim gün aşım' : 'Kusursuz', hak > 0 ? 'Günlük mola hakkın $hak dk' : 'Mola hakkı tanımlı değil',
          null, Icons.coffee_rounded, const [Color(0xFFFCD34D), Color(0xFFF97316)],
          rozet: asim > 0 ? null : ('Harika', Marka.zumrut)),
    ];
  }

  double get _genel {
    final ps = _kartlar.where((k) => k.p != null).map((k) => math.min(1.0, k.p!)).toList();
    final hedef = _i(_prim?['target_minor']);
    if (hedef > 0) ps.add(math.min(1.0, _i(_prim?['sales_minor']) / hedef));
    if (ps.isEmpty) return 0;
    return math.min(1.0, ps.reduce((a, b) => a + b) / ps.length);
  }

  @override
  Widget build(BuildContext context) {
    final ay = _h?['ay']?.toString();
    return PaSayfa(
      baslik: 'Hedeflerim',
      altBaslik: ay,
      yenile: _yukle,
      govde: Kaydir(children: [
        _genelKart(ay),
        const SizedBox(height: 16),
        if (_yukleniyor && _h == null)
          _iskeletIzgara()
        else ...[
          if (_prim != null) ...[_satisKarti(), const SizedBox(height: 12)],
          _izgara(),
        ],
        const SizedBox(height: 16),
        _ozetKarti(),
      ]),
    );
  }

  Widget _genelKart(String? ay) {
    final g = _genel;
    final kalan = _h?['kalan_gun'];
    final mesaj = g >= .9 ? 'Muhteşem gidiyorsun!' : g >= .5 ? 'Yolun yarısını geçtin' : 'Hedeflerine odaklan';
    return PaKart(
      gradient: Marka.kart,
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        SizedBox(
          width: 112,
          height: 112,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: g),
            duration: const Duration(milliseconds: 1400),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => CustomPaint(
              painter: _HalkaCizer(v, kalinlik: 11, arka: Colors.white.withValues(alpha: .12)),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('%${(v * 100).round()}', style: gosterim(25, renk: Colors.white)),
                  Text('GENEL', style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((ay ?? 'Bu ay').toUpperCase(),
                style: TextStyle(color: Marka.gok.withValues(alpha: .75), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
            const SizedBox(height: 4),
            Text(mesaj, style: gosterim(21, renk: Colors.white, satir: 1.15)),
            const SizedBox(height: 6),
            Text('Ayın bitmesine ${kalan ?? '—'} gün var.', style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 13)),
          ]),
        ),
      ]),
    );
  }

  Widget _iskeletIzgara() => GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .92,
        children: List.generate(4, (_) => const PaKart(child: Iskelet(yukseklik: double.infinity))),
      );

  Widget _izgara() {
    final k = _kartlar;
    return LayoutBuilder(builder: (_, c) {
      final w = (c.maxWidth - 12) / 2;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        for (var i = 0; i < k.length; i++) SizedBox(width: w, child: Belir(gecikme: 60 * i, child: _HedefKarti(k[i]))),
      ]);
    });
  }

  Widget _satisKarti() {
    final r = context.pa;
    final p = _prim!;
    final hedef = _i(p['target_minor']);
    final satis = _i(p['sales_minor']);
    final tuttu = p['target_met'] == true;
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _GradSimge(Icons.account_balance_wallet_rounded, const [Color(0xFFFCD34D), Color(0xFFF97316)]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Satış hedefi', style: gosterim(16, renk: r.metin)),
              Text(p['scheme_name']?.toString() ?? '', style: TextStyle(color: r.soluk, fontSize: 12)),
            ]),
          ),
          if (tuttu) _Rozet('Hedef tuttu 🎉', Marka.zumrut),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Sayac(deger: satis, yaz: paraYaz, stil: gosterim(24, renk: r.metin))),
          if (hedef > 0) Text('/ ${paraYaz(hedef)}', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        if (hedef > 0) ...[
          const SizedBox(height: 8),
          _Cubuk(satis / hedef, const [Color(0xFFFCD34D), Color(0xFFF97316)], yukseklik: 10),
        ],
      ]),
    );
  }

  Widget _ozetKarti() {
    final r = context.pa;
    return PaKart(
      padding: EdgeInsets.zero,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            titret();
            setState(() => _ozetAcik = !_ozetAcik);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const PaIkon(Icons.bar_chart_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Bu ayın özeti', style: gosterim(16, renk: r.metin)),
                  Text('Mesai, servis ve sipariş performansın', style: TextStyle(color: r.soluk, fontSize: 12)),
                ]),
              ),
              AnimatedRotation(
                turns: _ozetAcik ? .5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: r.silik),
              ),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _ozetAcik ? _ozetIcerik() : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }

  Widget _ozetIcerik() {
    final r = context.pa;
    final d = _rapor;
    if (d == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        child: Text('Rapor verisi alınamadı.', style: TextStyle(color: r.soluk)),
      );
    }
    final w = (d['worked'] as Map?) ?? const {};
    final o = (d['ops'] as Map?) ?? const {};
    final siparis = (d['orders'] as Map?) ?? const {};
    final ortTeslim = o['avg_delivery_min'];
    final kutular = <(String, String, IconData, Color)>[
      ('Toplam çalışma', dakikaYaz(_i(w['total_min'])), Icons.schedule_rounded, Marka.mavi),
      ('Çalışılan gün', '${_i(w['active_days'])}', Icons.event_available_rounded, Marka.zumrut),
      ('Günlük ortalama', dakikaYaz(_i(w['avg_daily_min'])), Icons.timelapse_rounded, Marka.gok),
      ('Mola', dakikaYaz(_i(w['break_min'])), Icons.coffee_rounded, Marka.lavanta),
      ('Alınan sipariş', '${_i(o['taken_count'])}', Icons.receipt_long_rounded, Marka.mor),
      ('Servis', '${_i(o['served_count'])}', Icons.room_service_rounded, Marka.zumrut),
      ('Hazırlanan', '${_i(o['prepared_count'])}', Icons.restaurant_rounded, Marka.kehribar),
      ('Ort. teslim', ortTeslim == null ? '—' : dakikaYaz(ortTeslim as num), Icons.timer_rounded, Marka.gul),
      if (siparis.isNotEmpty) ('Adisyon', '${_i(siparis['order_count'])}', Icons.point_of_sale_rounded, Marka.mavi),
    ];
    final gunler = ((w['by_day'] as List?) ?? const []).whereType<Map>().toList();
    final enCok = gunler.fold<int>(1, (a, g) => math.max(a, _i(g['worked_min'])));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Column(children: [
        Divider(color: r.kenar, height: 1),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, c) {
          final kw = (c.maxWidth - 16) / 3;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < kutular.length; i++)
              SizedBox(
                width: kw,
                child: Belir(
                  gecikme: 30 * i,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(kutular[i].$3, size: 17, color: kutular[i].$4),
                      const SizedBox(height: 6),
                      FittedBox(fit: BoxFit.scaleDown, child: Text(kutular[i].$2, style: gosterim(16, renk: r.metin))),
                      Text(kutular[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
        if (gunler.isNotEmpty) ...[
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Text('GÜNLÜK ÇALIŞMA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: r.silik))),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < gunler.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: _i(gunler[i]['worked_min']) / enCok),
                      duration: Duration(milliseconds: 700 + i * 15),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => FractionallySizedBox(
                        heightFactor: math.max(.04, v),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Marka.mor, Marka.gok]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _Hedef {
  const _Hedef(this.baslik, this.deger, this.alt, this.p, this.ikon, this.renkler, {this.rozet});
  final String baslik;
  final String deger;
  final String alt;
  final double? p;
  final IconData ikon;
  final List<Color> renkler;
  final (String, Color)? rozet;
}

class _HedefKarti extends StatelessWidget {
  const _HedefKarti(this.h);
  final _Hedef h;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _GradSimge(h.ikon, h.renkler),
          const Spacer(),
          if (h.rozet != null)
            _Rozet(h.rozet!.$1, h.rozet!.$2)
          else if (h.p != null)
            Text('%${(math.min(1.0, h.p!) * 100).round()}', style: gosterim(14, renk: r.birincil)),
        ]),
        const SizedBox(height: 12),
        Text(h.baslik, style: TextStyle(color: r.soluk, fontSize: 12, fontWeight: FontWeight.w600)),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(h.deger, style: gosterim(21, renk: r.metin))),
        if (h.p != null) ...[const SizedBox(height: 8), _Cubuk(h.p!, h.renkler)],
        const SizedBox(height: 8),
        Text(h.alt, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 11.5, height: 1.3)),
      ]),
    );
  }
}

class _GradSimge extends StatelessWidget {
  const _GradSimge(this.ikon, this.renkler);
  final IconData ikon;
  final List<Color> renkler;
  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: renkler),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: renkler.last.withValues(alpha: .45), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)],
        ),
        child: Icon(ikon, color: Colors.white, size: 20),
      );
}

class _Rozet extends StatelessWidget {
  const _Rozet(this.yazi, this.renk);
  final String yazi;
  final Color renk;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: renk.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
        child: Text(yazi, style: TextStyle(color: renk, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// Uzayarak dolan ilerleme çubuğu.
class _Cubuk extends StatelessWidget {
  const _Cubuk(this.oran, this.renkler, {this.yukseklik = 8});
  final double oran;
  final List<Color> renkler;
  final double yukseklik;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(
          height: yukseklik,
          color: context.pa.ic,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: oran.clamp(0, 1).toDouble()),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: v,
              child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: renkler), borderRadius: BorderRadius.circular(99))),
            ),
          ),
        ),
      );
}

/// Mor→gök geçişli dolan halka.
class _HalkaCizer extends CustomPainter {
  _HalkaCizer(this.oran, {this.kalinlik = 10, required this.arka});
  final double oran;
  final double kalinlik;
  final Color arka;
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromLTWH(kalinlik / 2, kalinlik / 2, s.width - kalinlik, s.height - kalinlik);
    c.drawArc(rect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik
      ..color = arka);
    if (oran <= 0) return;
    c.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * oran.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kalinlik
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [Color(0xFFA78BFA), Color(0xFF7DD3FC), Color(0xFFA78BFA)],
          transform: GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_HalkaCizer o) => o.oran != oran;
}
