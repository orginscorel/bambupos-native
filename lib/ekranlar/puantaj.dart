import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// PUANTAJIM — aylık puantaj ve tahmini bordro.
///
/// Ay seçici (önceki/sonraki), çalışılan/planlanan ilerlemesi + özet kutular
/// (fazla mesai, geç kalma, eksik, mola, izin), ücret tanımlıysa tahmini
/// kazanç kartı, izinler ve gün gün liste. GET /api/v1/portal/puantaj?ay=YYYY-MM
class PuantajEkrani extends StatefulWidget {
  const PuantajEkrani({super.key});
  @override
  State<PuantajEkrani> createState() => _PuantajEkraniState();
}

class _PuantajEkraniState extends State<PuantajEkrani> {
  final _saat = DateFormat('HH:mm', 'tr_TR');
  final _gunAd = DateFormat('EEEE', 'tr_TR');
  final _gunAy = DateFormat('d MMMM', 'tr_TR');
  final _kisa = DateFormat('d MMM', 'tr_TR');

  String? _ay; // null = sunucu bu ayı verir
  Map<String, dynamic>? _veri;
  ApiHata? _hata;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await Uyg.api.get('/api/v1/portal/puantaj', sorgu: {'ay': ?_ay});
      if (!mounted) return;
      setState(() {
        _veri = Map<String, dynamic>.from(r as Map);
        _ay = _veri?['ay']?.toString() ?? _ay;
        _hata = null;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() => _hata = e);
      if (_veri != null) bildir('Puantaj yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _ayaGit(String? ay) {
    if (ay == null || _yukleniyor) return;
    _ay = ay;
    _yukle();
  }

  Map<String, dynamic> get _toplam => (_veri?['toplam'] as Map?)?.cast<String, dynamic>() ?? const {};
  int _i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
  DateTime? _t(Object? s) => s == null ? null : DateTime.tryParse(s.toString())?.toLocal();

  List<Map<String, dynamic>> get _gunler =>
      ((_veri?['gunler'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        ..sort((a, b) => (b['tarih']?.toString() ?? '').compareTo(a['tarih']?.toString() ?? ''));

  List<Map<String, dynamic>> get _izinler => ((_veri?['izinler'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  @override
  Widget build(BuildContext context) {
    final ilk = _yukleniyor && _veri == null;
    return PaSayfa(
      baslik: 'Puantajım',
      altBaslik: _veri?['ay_adi']?.toString() ?? 'Aylık çalışma özeti',
      yenile: _yukle,
      govde: Kaydir(altBosluk: 40, children: [
        if (_veri != null || ilk) ...[
          _aySecici(),
          const SizedBox(height: 14),
        ],
        if (ilk) ...[
          const Iskelet(yukseklik: 190, radius: 24),
          const SizedBox(height: 14),
          const Iskelet(yukseklik: 120, radius: 24),
          const SizedBox(height: 14),
          const Iskelet(yukseklik: 72, radius: 18),
        ] else if (_veri == null && _hata != null)
          HataDurum(hata: _hata!, onTekrar: _yukle)
        else ...[
          _ozetKarti(),
          if (_veri?['kazanc'] is Map) ...[
            const SizedBox(height: 14),
            _kazancKarti(Map<String, dynamic>.from(_veri!['kazanc'] as Map)),
          ],
          if (_izinler.isNotEmpty) ...[
            const BolumBasligi('İzinler'),
            _izinListe(),
          ],
          const BolumBasligi('Gün gün'),
          _gunListe(),
        ],
      ]),
    );
  }

  /* ───────────── Ay seçici ───────────── */

  Widget _aySecici() {
    final r = context.pa;
    final onceki = _veri?['onceki_ay']?.toString();
    final sonraki = _veri?['sonraki_ay']?.toString();
    Widget ok(IconData i, String? ay) => Basilir(
          onTap: ay == null || _yukleniyor ? null : () => _ayaGit(ay),
          child: PaIkon(i, boyut: 42, ikonBoyut: 26),
        );
    return PaKart(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        ok(Icons.chevron_left_rounded, onceki),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(key: ValueKey(_veri?['ay']), children: [
              Text(_veri?['ay_adi']?.toString() ?? '…', style: gosterim(17, renk: r.metin)),
              Text(
                _veri == null ? 'Yükleniyor' : '${_i(_toplam, 'gun')} gün çalışıldı',
                style: TextStyle(fontSize: 12, color: r.soluk),
              ),
            ]),
          ),
        ),
        _yukleniyor && _veri != null
            ? SizedBox(width: 42, height: 42, child: Center(child: Yukleyici(boyut: 20, renk: r.birincil)))
            : ok(Icons.chevron_right_rounded, sonraki),
      ]),
    );
  }

  /* ───────────── Özet ───────────── */

  Widget _ozetKarti() {
    final r = context.pa;
    final t = _toplam;
    final calisilan = _i(t, 'calisilan_dk');
    final plan = _i(t, 'planlanan_dk');
    final oran = plan > 0 ? math.min(1.0, calisilan / plan) : null;
    final gecGun = _i(t, 'gec_gun');
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ÇALIŞILAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: r.silik)),
              const SizedBox(height: 2),
              Sayac(deger: calisilan, yaz: dakikaYaz, stil: gosterim(30, renk: r.metin, satir: 1.1)),
            ]),
          ),
          if (plan > 0)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Planlanan', style: TextStyle(fontSize: 11.5, color: r.soluk)),
              Text(dakikaYaz(plan), style: gosterim(16, renk: r.soluk)),
            ]),
        ]),
        if (oran != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 10,
              color: r.ic,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: oran),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v,
                  child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), gradient: Marka.grad)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Planın %${(calisilan * 100 / plan).round()}\'i tamamlandı', style: TextStyle(fontSize: 12, color: r.soluk)),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(builder: (_, c) {
          final kutular = [
            _kutu('Fazla mesai', dakikaYaz(_i(t, 'fazla_mesai_dk')), Marka.zumrut),
            _kutu('Geç kalma', gecGun > 0 ? '$gecGun gün' : '—', Marka.gul, alt: gecGun > 0 ? dakikaYaz(_i(t, 'gec_dk')) : null),
            _kutu('Eksik', dakikaYaz(_i(t, 'eksik_dk')), Marka.kehribar),
            _kutu('Mola', dakikaYaz(_i(t, 'mola_dk')), Marka.mor),
            _kutu('İzin', '${_i(t, 'izin_gun')} gün', Marka.mavi),
            _kutu('Çalışılan gün', '${_i(t, 'gun')}', const Color(0xFF0284C7)),
          ];
          final sutun = c.maxWidth > 560 ? 6 : 3;
          final gen = (c.maxWidth - 8 * (sutun - 1)) / sutun;
          return Wrap(spacing: 8, runSpacing: 8, children: [for (final k in kutular) SizedBox(width: gen, child: k)]);
        }),
      ]),
    );
  }

  /// Mesaim ekranındaki renkli kutularla aynı biçim.
  Widget _kutu(String etiket, String deger, Color renk, {String? alt}) {
    final r = context.pa;
    final yazi = r.koyu ? Color.lerp(renk, Colors.white, .25)! : renk;
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(color: renk.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text(alt == null ? deger : '$deger · $alt', style: gosterim(16, renk: yazi))),
        const SizedBox(height: 2),
        Text(etiket, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: yazi.withValues(alpha: .85), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  /* ───────────── Tahmini kazanç ───────────── */

  Widget _kazancKarti(Map<String, dynamic> k) {
    final saatlik = k['tur'] == 'hourly';
    final bitmeyenAy = _veri?['sonraki_ay'] == null;
    Widget satir(String et, String deger) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Text(et, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 13.5)),
            const Spacer(),
            Text(deger, style: gosterim(15, agirlik: FontWeight.w700, renk: Colors.white)),
          ]),
        );
    return PaKart(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Marka.lacivert1, Color(0xFF3B2FA8), Marka.mor]),
      padding: const EdgeInsets.all(20),
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          right: -18,
          top: -18,
          child: Icon(Icons.payments_outlined, size: 130, color: Colors.white.withValues(alpha: .08)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bitmeyenAy ? 'TAHMİNİ KAZANÇ · BU AY' : 'TAHMİNİ KAZANÇ',
              style: TextStyle(color: const Color(0xFFC7D2FE).withValues(alpha: .85), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          const SizedBox(height: 10),
          Sayac(deger: _i(k, 'toplam_minor'), yaz: paraYaz, stil: gosterim(34, renk: Colors.white, satir: 1)),
          const SizedBox(height: 6),
          if (saatlik)
            satir('Saatlik ücret', '${paraYaz(_i(k, 'ucret_minor'))} / saat')
          else
            satir('Aylık maaş', paraYaz(_i(k, 'ucret_minor'))),
          satir(saatlik ? 'Çalışılan süre karşılığı' : 'Bu aya düşen maaş', paraYaz(_i(k, 'maas_minor'))),
          satir('Prim', paraYaz(_i(k, 'prim_minor'))),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Divider(height: 1, color: Colors.white.withValues(alpha: .15)),
          ),
          satir('Toplam', paraYaz(_i(k, 'toplam_minor'))),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 14, color: Colors.white.withValues(alpha: .55)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Tahminidir; kesin tutar kesintilerle birlikte bordroda belirlenir.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 11.5, height: 1.35)),
            ),
          ]),
        ]),
      ]),
    );
  }

  /* ───────────── İzinler ───────────── */

  Widget _izinListe() {
    final r = context.pa;
    return PaKart(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        for (final i in _izinler)
          Builder(builder: (_) {
            final bas = DateTime.tryParse(i['bas']?.toString() ?? '');
            final bit = DateTime.tryParse(i['bit']?.toString() ?? '');
            final ayni = bas != null && bit != null && bas == bit;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                const PaIkon(Icons.beach_access_rounded, boyut: 36, zemin: Color(0xFFDBEAFE), renk: Marka.mavi),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i['tur']?.toString() ?? 'İzin', style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontSize: 13.5)),
                    Text(
                      bas == null ? '—' : ayni || bit == null ? _gunAy.format(bas) : '${_kisa.format(bas)} – ${_kisa.format(bit)}',
                      style: TextStyle(fontSize: 12, color: r.soluk),
                    ),
                  ]),
                ),
                Text('${_i(i, 'gun')} gün', style: gosterim(15, renk: r.metin)),
              ]),
            );
          }),
      ]),
    );
  }

  /* ───────────── Gün gün ───────────── */

  Widget _gunListe() {
    final r = context.pa;
    final l = _gunler;
    if (l.isEmpty) {
      return const BosDurum(ikon: Icons.event_note_rounded, baslik: 'Bu ay mesai kaydı yok', aciklama: 'QR ile mesaiye başladığında günlerin burada listelenir.');
    }
    return PaKart(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        for (var i = 0; i < l.length; i++)
          Belir(
            key: ValueKey('${_veri?['ay']}-${l[i]['tarih']}'),
            gecikme: math.min(i, 8) * 40,
            child: _gunSatiri(r, l[i]),
          ),
      ]),
    );
  }

  Widget _gunSatiri(PaRenk r, Map<String, dynamic> h) {
    final g = DateTime.tryParse(h['tarih']?.toString() ?? '') ?? DateTime.now();
    final gi = _t(h['giris']);
    final co = _t(h['cikis']);
    final acik = h['acik'] == true || (gi != null && co == null);
    final plan = _i(h, 'planlanan_dk');
    final gec = _i(h, 'gec_dk');
    final fazla = _i(h, 'fazla_mesai_dk');
    final eksik = _i(h, 'eksik_dk');
    final mola = _i(h, 'mola_dk');
    final gun = _gunAd.format(g);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
          width: 44,
          height: 48,
          decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${g.day}', style: gosterim(17, renk: r.metin, satir: 1)),
            Text(DateFormat('MMM', 'tr_TR').format(g), style: TextStyle(fontSize: 10.5, color: r.silik, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gun[0].toUpperCase() + gun.substring(1), style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontSize: 14)),
            Text('${gi == null ? '—' : _saat.format(gi)}${co != null ? ' – ${_saat.format(co)}' : acik ? ' – …' : ''}',
                style: TextStyle(fontSize: 12, color: r.soluk)),
            if (gec > 0 || fazla > 0 || eksik > 0 || mola > 0)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(spacing: 6, runSpacing: 4, children: [
                  if (gec > 0) _rozet(Icons.alarm_rounded, '${dakikaYaz(gec)} geç', Marka.gul),
                  if (fazla > 0) _rozet(Icons.add_circle_outline_rounded, '+${dakikaYaz(fazla)}', Marka.zumrut),
                  if (eksik > 0) _rozet(Icons.remove_circle_outline_rounded, '-${dakikaYaz(eksik)}', Marka.kehribar),
                  if (mola > 0) _rozet(Icons.coffee_rounded, dakikaYaz(mola), Marka.mor),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(dakikaYaz(_i(h, 'calisilan_dk')), style: gosterim(17, renk: r.metin)),
          Text(acik ? 'sürüyor' : plan > 0 ? '/ ${dakikaYaz(plan)}' : 'çalışma',
              style: TextStyle(fontSize: 11, color: acik ? Marka.zumrut : r.silik, fontWeight: acik ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ]),
    );
  }

  /// Mesaim geçmiş listesindeki rozetlerle aynı.
  Widget _rozet(IconData i, String t, Color renk) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 11, color: renk),
          const SizedBox(width: 3),
          Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
        ]),
      );
}
