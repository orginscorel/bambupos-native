import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'kabuk.dart';
import 'puantaj.dart';
import 'qr_okut.dart';

/// MESAİM — web Shift.vue karşılığı.
///
/// Durum kartı (mesai/mola, canlı süre, vardiya bitişine kalan), YALNIZ QR
/// ile işlem kartı (QR'sız başlat/bitir YOK — sunucu da reddeder),
/// bugünkü molalar ve son 14 mesai kaydı.
class MesaimEkrani extends StatefulWidget {
  const MesaimEkrani({super.key});
  @override
  State<MesaimEkrani> createState() => _MesaimEkraniState();
}

class _MesaimEkraniState extends State<MesaimEkrani> {
  final _saat = DateFormat('HH:mm', 'tr_TR');
  final _gunAd = DateFormat('EEEE', 'tr_TR');
  final _gunAy = DateFormat('d MMMM', 'tr_TR');

  Map<String, dynamic>? _durum;
  List<Map<String, dynamic>> _gecmis = [];
  bool _yukleniyor = true;
  DateTime _simdi = DateTime.now();
  Timer? _tik;
  Timer? _yokla;

  @override
  void initState() {
    super.initState();
    _yenile();
    _tik = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _simdi = DateTime.now()));
    _yokla = Timer.periodic(const Duration(seconds: 60), (_) => _durumYukle());
    Uyg.mesaiDegisti.addListener(_durumYukle);
  }

  @override
  void dispose() {
    _tik?.cancel();
    _yokla?.cancel();
    Uyg.mesaiDegisti.removeListener(_durumYukle);
    super.dispose();
  }

  Future<void> _yenile() async {
    await Future.wait([_durumYukle(), _gecmisYukle()]);
    if (mounted) setState(() => _yukleniyor = false);
  }

  Future<void> _durumYukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/state');
      if (mounted) setState(() => _durum = Map<String, dynamic>.from(r as Map));
    } on ApiHata catch (e) {
      if (_durum == null) bildir('Mesai durumu alınamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    }
  }

  Future<void> _gecmisYukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/history') as Map;
      final l = ((r['entries'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).take(14).toList();
      if (mounted) setState(() => _gecmis = l);
    } on ApiHata {
      // Süsleyici bölüm — sessiz.
    }
  }

  bool get _calisiyor => _durum?['status'] == 'working';
  bool get _molada => _durum?['on_break'] == true;
  bool get _tuvalet => _molada && _durum?['break_kind'] == 'toilet';
  Map<String, dynamic>? get _kayit => _durum?['entry'] is Map ? Map<String, dynamic>.from(_durum!['entry'] as Map) : null;

  DateTime? _t(Object? s) => s == null ? null : DateTime.tryParse(s.toString())?.toLocal();

  int get _canliCalisma {
    final e = _kayit;
    if (e == null) return 0;
    final taban = (e['worked_min'] as num?)?.toInt() ?? 0;
    if (_molada) return taban;
    final sunucu = _t(_durum?['server_now']);
    final fark = sunucu == null ? 0 : _simdi.difference(sunucu).inSeconds / 60;
    return (taban + math.max(0, fark)).round();
  }

  int? get _kalanDk {
    final v = _durum?['today_shift'];
    if (!_calisiyor || v is! Map) return null;
    final bit = _t(v['ends_at']);
    return bit?.difference(_simdi).inMinutes;
  }

  String? get _vardiyaYazi {
    final v = _durum?['today_shift'];
    if (v is! Map) return null;
    final a = _t(v['starts_at']);
    final b = _t(v['ends_at']);
    if (a == null || b == null) return null;
    return '${_saat.format(a)} – ${_saat.format(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final alt = _vardiyaYazi != null ? 'Bugünkü vardiya: $_vardiyaYazi' : DateFormat('d MMMM EEEE', 'tr_TR').format(_simdi);
    return PaSayfa(
      baslik: 'Mesaim',
      altBaslik: alt,
      yenile: _yenile,
      govde: Kaydir(altBosluk: 40, children: [
        if (_yukleniyor) ...[
          const Iskelet(yukseklik: 170, radius: 24),
          const SizedBox(height: 14),
          const Iskelet(yukseklik: 80, radius: 22),
        ] else ...[
          _durumKarti(),
          const SizedBox(height: 14),
          _qrKarti(),
          const SizedBox(height: 14),
          SatirGrubu([
            Satir(
              ikon: Icons.receipt_long_rounded,
              baslik: 'Puantaj ve bordrom',
              alt: 'Aylık özet, fazla mesai, tahmini kazanç',
              ikonZemin: const Color(0xFFE0F2FE),
              ikonRenk: const Color(0xFF0284C7),
              onTap: () => git(context, const PuantajEkrani()),
            ),
          ]),
          if (((_kayit?['breaks'] as List?) ?? const []).isNotEmpty) ...[
            const BolumBasligi('Bugünkü molalarım'),
            _molalar(),
          ],
          const BolumBasligi('Mesai geçmişi'),
          _gecmisListe(),
        ],
      ]),
    );
  }

  Widget _durumKarti() {
    final r = context.pa;
    final (renk, ikon, baslik) = !_calisiyor
        ? (r.silik, Icons.schedule_rounded, 'Mesaide değilsin')
        : _tuvalet
            ? (Marka.lavanta, Icons.water_drop_rounded, 'Kısa moladasın')
            : _molada
                ? (Marka.lavanta, Icons.coffee_rounded, 'Moladasın')
                : (Marka.zumrut, Icons.check_circle_rounded, 'Mesaidesin');
    final e = _kayit;
    final giris = _t(e?['clock_in_at']);
    final kalan = _kalanDk;
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .5, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: renk.withValues(alpha: .15), borderRadius: BorderRadius.circular(18)),
              child: Icon(ikon, color: renk, size: 28),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(baslik, style: gosterim(19, renk: r.metin)),
              const SizedBox(height: 2),
              Text(
                _calisiyor && giris != null ? 'Giriş ${_saat.format(giris)} · fiili ${dakikaYaz(_canliCalisma)}' : 'Mesaiye başlamak için QR okut.',
                style: TextStyle(color: r.soluk, fontSize: 13),
              ),
            ]),
          ),
        ]),
        if (kalan != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: (kalan > 0 ? Marka.mavi : Marka.gul).withValues(alpha: .12), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(Icons.timer_rounded, size: 18, color: kalan > 0 ? Marka.mavi : Marka.gul),
              const SizedBox(width: 8),
              Text(kalan > 0 ? 'Bitişe ${dakikaYaz(kalan)} kaldı' : 'Vardiya süresi doldu',
                  style: TextStyle(fontWeight: FontWeight.w700, color: kalan > 0 ? Marka.mavi : Marka.gul)),
            ]),
          ),
        ],
        if (_calisiyor && e != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            _kutu('Fiili çalışma', _canliCalisma, Marka.mavi),
            const SizedBox(width: 8),
            _kutu('Mola', (e['break_total_min'] as num?)?.toInt() ?? 0, Marka.mor),
            const SizedBox(width: 8),
            _kutu('Kısa mola', (e['toilet_total_min'] as num?)?.toInt() ?? 0, Marka.zumrut),
          ]),
        ],
      ]),
    );
  }

  Widget _kutu(String etiket, int dk, Color renk) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(color: renk.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Sayac(deger: dk, yaz: (v) => dakikaYaz(v), stil: gosterim(17, renk: renk)),
            const SizedBox(height: 2),
            Text(etiket, style: TextStyle(fontSize: 11, color: renk.withValues(alpha: .85), fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _qrKarti() {
    final yazi = !_calisiyor ? 'Mesaiye başlamak için QR okut' : _molada ? 'Moladan dönmek için QR okut' : 'Mola / çıkış için QR okut';
    return PaKart(
      gradient: Marka.kart,
      onTap: () async {
        await git(context, const QrOkutEkrani());
        _yenile();
      },
      child: Row(children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(16)),
          child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(yazi, style: gosterim(16, renk: Colors.white)),
            const SizedBox(height: 2),
            Text('Mesai ve mola işlemleri işletmedeki QR ile yapılır.', style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 12)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: .7)),
      ]),
    );
  }

  Widget _molalar() {
    final r = context.pa;
    final l = ((_kayit?['breaks'] as List?) ?? const []).whereType<Map>().toList();
    return PaKart(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        for (final b in l)
          Builder(builder: (_) {
            final tuv = b['kind'] == 'toilet';
            final bas = _t(b['started_at']);
            final bit = _t(b['ended_at']);
            final renk = tuv ? Marka.zumrut : Marka.mor;
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: renk.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                  child: Icon(tuv ? Icons.water_drop_rounded : Icons.coffee_rounded, color: renk, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b['kind_label']?.toString() ?? (tuv ? 'Kısa mola' : 'Mola'), style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontSize: 13.5)),
                    Text('${bas == null ? '—' : _saat.format(bas)}${bit != null ? ' – ${_saat.format(bit)}' : ''}', style: TextStyle(fontSize: 12, color: r.soluk)),
                  ]),
                ),
                if (bit != null && bas != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: renk.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
                    child: Text(dakikaYaz(bit.difference(bas).inMinutes), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: renk)),
                  )
                else
                  const _Suruyor(),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _gecmisListe() {
    final r = context.pa;
    if (_gecmis.isEmpty) {
      return const BosDurum(ikon: Icons.history_rounded, baslik: 'Henüz mesai kaydı yok', aciklama: 'QR ile mesaiye başladığında kayıtların burada görünür.');
    }
    return PaKart(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        for (var i = 0; i < _gecmis.length; i++)
          Belir(
            gecikme: math.min(i, 8) * 40,
            child: Builder(builder: (_) {
              final h = _gecmis[i];
              final g = DateTime.tryParse(h['date']?.toString() ?? '') ?? _simdi;
              final gi = _t(h['clock_in_at']);
              final co = _t(h['clock_out_at']);
              final mola = (h['break_min'] as num?)?.toInt() ?? 0;
              final tuv = (h['toilet_min'] as num?)?.toInt() ?? 0;
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
                      Text(_gunAd.format(g)[0].toUpperCase() + _gunAd.format(g).substring(1), style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontSize: 14)),
                      Text('${_gunAy.format(g)} · ${gi == null ? '—' : _saat.format(gi)}${co != null ? ' – ${_saat.format(co)}' : ''}',
                          style: TextStyle(fontSize: 12, color: r.soluk)),
                      if (mola > 0 || tuv > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Wrap(spacing: 6, children: [
                            if (mola > 0) _rozet(Icons.coffee_rounded, dakikaYaz(mola), Marka.mor),
                            if (tuv > 0) _rozet(Icons.water_drop_rounded, dakikaYaz(tuv), Marka.zumrut),
                          ]),
                        ),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(dakikaYaz((h['worked_min'] as num?)?.toInt() ?? 0), style: gosterim(17, renk: r.metin)),
                    if (co == null) const _Suruyor() else Text('çalışma', style: TextStyle(fontSize: 11, color: r.silik)),
                  ]),
                ]),
              );
            }),
          ),
      ]),
    );
  }

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

class _Suruyor extends StatefulWidget {
  const _Suruyor();
  @override
  State<_Suruyor> createState() => _SuruyorState();
}

class _SuruyorState extends State<_Suruyor> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Marka.zumrut.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          FadeTransition(
            opacity: Tween(begin: .3, end: 1.0).animate(_c),
            child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Marka.zumrut, shape: BoxShape.circle)),
          ),
          const SizedBox(width: 5),
          const Text('sürüyor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Marka.zumrut)),
        ]),
      );
}
