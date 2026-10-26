import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// VARDİYAM (sekme) — web Schedule.vue karşılığı.
///
/// Üstte izin talepleri (oluştur / bekleyeni geri çek), altta yaklaşan
/// vardiyalar gün gün (bugün/yarın rozetli, sol renkli şerit). Vardiya
/// yoksa illüstrasyonlu "Vardiya bulunamadı!" boş durumu.
class VardiyamEkrani extends StatefulWidget {
  const VardiyamEkrani({super.key});
  @override
  State<VardiyamEkrani> createState() => _VardiyamEkraniState();
}

class _Vardiya {
  _Vardiya(Map m)
      : id = (m['id'] as num).toInt(),
        bas = DateTime.parse(m['starts_at'].toString()).toLocal(),
        bit = DateTime.parse(m['ends_at'].toString()).toLocal(),
        pozisyon = m['position']?.toString(),
        sube = m['branch_name']?.toString(),
        not = m['note']?.toString();
  final int id;
  final DateTime bas;
  final DateTime bit;
  final String? pozisyon;
  final String? sube;
  final String? not;
  int get dakika => bit.difference(bas).inMinutes;
}

class _Izin {
  _Izin(Map m)
      : id = (m['id'] as num).toInt(),
        tur = m['type']?.toString() ?? 'other',
        turAd = m['type_label']?.toString() ?? '',
        bas = DateTime.tryParse(m['starts_on'].toString()) ?? DateTime.now(),
        bit = DateTime.tryParse(m['ends_on'].toString()) ?? DateTime.now(),
        gun = (m['days'] as num?)?.toInt() ?? 1,
        neden = m['reason']?.toString() ?? '',
        durum = m['status']?.toString() ?? 'pending',
        durumAd = m['status_label']?.toString() ?? '';
  final int id;
  final String tur;
  final String turAd;
  final DateTime bas;
  final DateTime bit;
  final int gun;
  final String neden;
  final String durum;
  final String durumAd;
}

const _turlar = {'annual': 'Yıllık izin', 'sick': 'Rapor', 'unpaid': 'Ücretsiz izin', 'other': 'Diğer'};

class _VardiyamEkraniState extends State<VardiyamEkrani> {
  final _gunFmt = DateFormat('d MMMM EEEE', 'tr_TR');
  final _saatFmt = DateFormat('HH:mm', 'tr_TR');
  final _tarihFmt = DateFormat('d MMM y', 'tr_TR');

  bool _yukleniyor = true;
  bool _izinYukleniyor = true;
  List<_Vardiya> _vardiyalar = [];
  List<_Izin> _izinler = [];
  int _sekme = 0; // 0 vardiyalar, 1 izinler

  @override
  void initState() {
    super.initState();
    _yenile();
  }

  Future<void> _yenile() => Future.wait([_vardiyaYukle(), _izinYukle()]);

  Future<void> _vardiyaYukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/schedule') as Map;
      final l = ((r['shifts'] as List?) ?? const []).whereType<Map>().map(_Vardiya.new).toList()
        ..sort((a, b) => a.bas.compareTo(b.bas));
      if (mounted) setState(() => _vardiyalar = l);
    } on ApiHata catch (e) {
      bildir('Vardiyalar yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _izinYukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/leave-requests') as Map;
      final l = ((r['requests'] as List?) ?? const []).whereType<Map>().map(_Izin.new).toList();
      if (mounted) setState(() => _izinler = l);
    } on ApiHata {
      // Sessiz: bölüm boş görünür.
    } finally {
      if (mounted) setState(() => _izinYukleniyor = false);
    }
  }

  String _gunAnahtar(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Map<String, List<_Vardiya>> get _gunler {
    final m = <String, List<_Vardiya>>{};
    for (final v in _vardiyalar) {
      m.putIfAbsent(_gunAnahtar(v.bas), () => []).add(v);
    }
    return m;
  }

  String? _goreli(DateTime d) {
    final bugun = DateTime.now();
    final fark = DateTime(d.year, d.month, d.day).difference(DateTime(bugun.year, bugun.month, bugun.day)).inDays;
    if (fark == 0) return 'Bugün';
    if (fark == 1) return 'Yarın';
    return null;
  }

  Color _vurgu(int i) => const [Marka.mor, Marka.mavi, Marka.zumrut, Marka.lavanta, Marka.gok][i % 5];

  String get _altBaslik {
    if (_yukleniyor) return 'Yükleniyor…';
    if (_vardiyalar.isEmpty) return 'Planlı vardiya yok';
    final toplam = _vardiyalar.fold<int>(0, (a, v) => a + v.dakika);
    return '${_vardiyalar.length} vardiya · ${dakikaYaz(toplam)}';
  }

  @override
  Widget build(BuildContext context) {
    final bekleyen = _izinler.where((i) => i.durum == 'pending').length;
    return PaSayfa(
      baslik: 'Vardiyam',
      altBaslik: _altBaslik,
      geri: false,
      yenile: _yenile,
      govde: Kaydir(children: [
        _Segment(
          secili: _sekme,
          ogeler: ['Vardiyalar', bekleyen > 0 ? 'İzinlerim · $bekleyen' : 'İzinlerim'],
          onSec: (i) => setState(() => _sekme = i),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (c, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a), child: c),
          ),
          child: _sekme == 0 ? KeyedSubtree(key: const ValueKey(0), child: _vardiyaBolumu()) : KeyedSubtree(key: const ValueKey(1), child: _izinBolumu()),
        ),
      ]),
    );
  }

  /* ───────────── Vardiyalar ───────────── */

  Widget _vardiyaBolumu() {
    final r = context.pa;
    if (_yukleniyor) {
      return Column(children: [
        for (var i = 0; i < 3; i++) ...[
          const Iskelet(yukseklik: 14, genislik: 140),
          const SizedBox(height: 10),
          const Iskelet(yukseklik: 92, radius: 22),
          const SizedBox(height: 18),
        ],
      ]);
    }
    if (_vardiyalar.isEmpty) return const _VardiyaYok();

    final gunler = _gunler.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var gi = 0; gi < gunler.length; gi++)
        Belir(
          gecikme: math.min(gi, 6) * 60,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                child: Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: _vurgu(gi), shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_gunFmt.format(gunler[gi].value.first.bas), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: r.metin)),
                  ),
                  if (_goreli(gunler[gi].value.first.bas) case final g?)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: g == 'Bugün' ? Marka.zumrut.withValues(alpha: .15) : r.birincilYumusak,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(g, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g == 'Bugün' ? Marka.zumrut : r.birincil)),
                    ),
                ]),
              ),
              for (final v in gunler[gi].value) _vardiyaKarti(v, _vurgu(gi)),
            ]),
          ),
        ),
    ]);
  }

  Widget _vardiyaKarti(_Vardiya v, Color vurgu) {
    final r = context.pa;
    final simdi = DateTime.now();
    final suruyor = simdi.isAfter(v.bas) && simdi.isBefore(v.bit);
    final ilerleme = suruyor ? simdi.difference(v.bas).inSeconds / v.bit.difference(v.bas).inSeconds : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PaKart(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 6, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [vurgu, vurgu.withValues(alpha: .5)]))),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${_saatFmt.format(v.bas)} – ${_saatFmt.format(v.bit)}', style: gosterim(21, renk: r.metin)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(20)),
                        child: Text(dakikaYaz(v.dakika), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.soluk)),
                      ),
                    ]),
                    if (v.pozisyon != null || v.sube != null) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        if (v.pozisyon != null && v.pozisyon!.isNotEmpty) _bilgi(Icons.badge_rounded, v.pozisyon!),
                        if (v.sube != null && v.sube!.isNotEmpty) _bilgi(Icons.storefront_rounded, v.sube!),
                      ]),
                    ],
                    if (v.not != null && v.not!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(v.not!, style: TextStyle(fontSize: 12.5, color: r.soluk)),
                    ],
                    if (suruyor) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: ilerleme.clamp(0, 1)),
                          duration: const Duration(milliseconds: 1100),
                          curve: Curves.easeOutCubic,
                          builder: (_, d, _) => Stack(children: [
                            Container(height: 6, color: r.ic),
                            FractionallySizedBox(widthFactor: d, child: Container(height: 6, decoration: const BoxDecoration(gradient: Marka.grad))),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Sürüyor · bitişe ${dakikaYaz(v.bit.difference(simdi).inMinutes)}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Marka.zumrut)),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bilgi(IconData i, String t) {
    final r = context.pa;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 14, color: r.silik),
      const SizedBox(width: 4),
      Text(t, style: TextStyle(fontSize: 12.5, color: r.soluk, fontWeight: FontWeight.w500)),
    ]);
  }

  /* ───────────── İzinler ───────────── */

  Widget _izinBolumu() {
    final r = context.pa;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaKart(
        gradient: Marka.kart,
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(15)),
            child: const Icon(Icons.beach_access_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('İzin / rapor talebi', style: gosterim(16.5, renk: Colors.white)),
              Text('Yöneticin onaylayınca bildirim alırsın.', style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 12.5)),
            ]),
          ),
          Basilir(
            onTap: _izinFormu,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: const Row(children: [
                Icon(Icons.add_rounded, color: Marka.lacivert1, size: 18),
                SizedBox(width: 4),
                Text('Yeni', style: TextStyle(color: Marka.lacivert1, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (_izinYukleniyor)
        for (var i = 0; i < 2; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: Iskelet(yukseklik: 84, radius: 22))
      else if (_izinler.isEmpty)
        BosDurum(
          ikon: Icons.event_available_rounded,
          baslik: 'Henüz izin talebin yok',
          aciklama: 'Yıllık izin, rapor ya da ücretsiz izin için yeni talep oluştur.',
          eylem: YumusakDugme(yazi: 'Talep oluştur', ikon: Icons.add_rounded, onTap: _izinFormu),
        )
      else
        for (var i = 0; i < _izinler.length; i++) Belir(gecikme: math.min(i, 6) * 50, child: _izinKarti(_izinler[i])),
      if (!_izinYukleniyor && _izinler.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Bekleyen talebi sola kaydırarak ya da dokunarak geri çekebilirsin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: r.silik))),
    ]);
  }

  (Color, Color, IconData) _durumRenk(String d) => switch (d) {
        'approved' => (Marka.zumrut.withValues(alpha: .15), Marka.zumrut, Icons.check_circle_rounded),
        'rejected' => (Marka.gul.withValues(alpha: .13), Marka.gul, Icons.cancel_rounded),
        'cancelled' => (context.pa.ic, context.pa.silik, Icons.remove_circle_rounded),
        _ => (Marka.kehribar.withValues(alpha: .16), const Color(0xFFB45309), Icons.schedule_rounded),
      };

  Widget _izinKarti(_Izin i) {
    final r = context.pa;
    final (zemin, renk, ikon) = _durumRenk(i.durum);
    final kart = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PaKart(
        onTap: i.durum == 'pending' ? () => _izinIptal(i) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PaIkon(i.tur == 'sick' ? Icons.medical_services_rounded : Icons.beach_access_rounded, boyut: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(i.turAd.isEmpty ? (_turlar[i.tur] ?? i.tur) : i.turAd, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: r.metin))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ikon, size: 13, color: renk),
                    const SizedBox(width: 4),
                    Text(i.durumAd.isEmpty ? i.durum : i.durumAd, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: renk)),
                  ]),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '${_tarihFmt.format(i.bas)}${i.bit != i.bas ? ' – ${_tarihFmt.format(i.bit)}' : ''} · ${i.gun} gün',
                style: TextStyle(fontSize: 12.5, color: r.soluk, fontWeight: FontWeight.w500),
              ),
              if (i.neden.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(i.neden, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: r.silik)),
              ],
            ]),
          ),
        ]),
      ),
    );
    if (i.durum != 'pending') return kart;
    return Dismissible(
      key: ValueKey('izin${i.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _izinIptal(i);
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .14), borderRadius: BorderRadius.circular(24)),
        child: const Icon(Icons.undo_rounded, color: Marka.gul),
      ),
      child: kart,
    );
  }

  Future<void> _izinIptal(_Izin i) async {
    final onay = await panoAc<bool>(
      context,
      baslik: 'Talep geri çekilsin mi?',
      alt: '${_turlar[i.tur] ?? i.turAd} · ${_tarihFmt.format(i.bas)}',
      icerik: (ctx) => Row(children: [
        Expanded(child: YumusakDugme(yazi: 'Vazgeç', onTap: () => Navigator.pop(ctx, false), zemin: ctx.pa.ic, renk: ctx.pa.metin)),
        const SizedBox(width: 10),
        Expanded(child: YumusakDugme(yazi: 'Geri çek', ikon: Icons.undo_rounded, onTap: () => Navigator.pop(ctx, true), zemin: Marka.gul, renk: Colors.white)),
      ]),
    );
    if (onay != true) return;
    try {
      await Uyg.api.post('/api/v1/portal/leave-requests/${i.id}/cancel');
      bildir('Talep geri çekildi');
      await _izinYukle();
    } on ApiHata catch (e) {
      bildir('Geri çekilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    }
  }

  Future<void> _izinFormu() async {
    final eklendi = await panoAc<bool>(context, baslik: 'Yeni izin talebi', alt: 'Yöneticin onayladığında bildirim alırsın.', icerik: (_) => const _IzinFormu());
    if (eklendi == true) {
      bildir('İzin talebi oluşturuldu', mesaj: 'Onay bekliyor');
      setState(() => _izinYukleniyor = true);
      await _izinYukle();
    }
  }
}

/* ───────────── İzin formu (pano içi) ───────────── */

class _IzinFormu extends StatefulWidget {
  const _IzinFormu();
  @override
  State<_IzinFormu> createState() => _IzinFormuState();
}

class _IzinFormuState extends State<_IzinFormu> {
  final _fmt = DateFormat('d MMMM y, EEEE', 'tr_TR');
  String _tur = 'annual';
  DateTime? _bas;
  DateTime? _bit;
  final _neden = TextEditingController();
  bool _gonder = false;
  final _hatalar = <String, String>{};

  @override
  void dispose() {
    _neden.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _tarihSec(bool bas) async {
    final simdi = DateTime.now();
    final sec = await showDatePicker(
      context: context,
      locale: const Locale('tr', 'TR'),
      initialDate: (bas ? _bas : (_bit ?? _bas)) ?? simdi,
      firstDate: DateTime(simdi.year - 1),
      lastDate: DateTime(simdi.year + 2),
    );
    if (sec == null) return;
    setState(() {
      if (bas) {
        _bas = sec;
        if (_bit == null || _bit!.isBefore(sec)) _bit = sec;
      } else {
        _bit = sec;
      }
      _hatalar.remove(bas ? 'starts_on' : 'ends_on');
    });
  }

  Future<void> _kaydet() async {
    _hatalar.clear();
    if (_bas == null) _hatalar['starts_on'] = 'Başlangıç tarihi gerekli.';
    if (_bit == null) _hatalar['ends_on'] = 'Bitiş tarihi gerekli.';
    if (_bas != null && _bit != null && _bit!.isBefore(_bas!)) _hatalar['ends_on'] = 'Bitiş başlangıçtan önce olamaz.';
    if (_neden.text.trim().isEmpty) _hatalar['reason'] = 'Mazeret girmelisin.';
    if (_hatalar.isNotEmpty) {
      setState(() {});
      titret(1);
      return;
    }
    setState(() => _gonder = true);
    try {
      await Uyg.api.post('/api/v1/portal/leave-requests', {'type': _tur, 'starts_on': _iso(_bas!), 'ends_on': _iso(_bit!), 'reason': _neden.text.trim()});
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      final h = e.govde?['errors'];
      if (h is Map) {
        h.forEach((k, v) => _hatalar[k.toString()] = v is List && v.isNotEmpty ? v.first.toString() : v.toString());
      } else {
        bildir('Talep gönderilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _gonder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final gun = (_bas != null && _bit != null) ? _bit!.difference(_bas!).inDays + 1 : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _turlar.entries)
          Basilir(
            onTap: () => setState(() => _tur = e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: _tur == e.key ? Marka.grad : null,
                color: _tur == e.key ? null : r.ic,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(e.value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: _tur == e.key ? Colors.white : r.soluk)),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      _tarihAlani('Başlangıç', _bas, () => _tarihSec(true), _hatalar['starts_on']),
      const SizedBox(height: 10),
      _tarihAlani('Bitiş', _bit, () => _tarihSec(false), _hatalar['ends_on']),
      if (gun != null && gun > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text('Toplam $gun gün', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      const SizedBox(height: 14),
      TextField(
        controller: _neden,
        maxLines: 3,
        maxLength: 500,
        decoration: InputDecoration(labelText: 'Mazeret / açıklama', errorText: _hatalar['reason'], alignLabelWithHint: true),
      ),
      const SizedBox(height: 8),
      GradDugme(yazi: 'Talebi gönder', ikon: Icons.send_rounded, yukleniyor: _gonder, onTap: _kaydet),
    ]);
  }

  Widget _tarihAlani(String etiket, DateTime? d, VoidCallback onTap, String? hata) {
    final r = context.pa;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Basilir(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16), border: hata != null ? Border.all(color: Marka.gul) : null),
          child: Row(children: [
            Icon(Icons.event_rounded, color: r.birincil, size: 20),
            const SizedBox(width: 10),
            Text(etiket, style: TextStyle(color: r.soluk, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(d == null ? 'Seç' : _fmt.format(d), style: TextStyle(fontWeight: FontWeight.w700, color: d == null ? r.silik : r.metin)),
          ]),
        ),
      ),
      if (hata != null) Padding(padding: const EdgeInsets.only(top: 4, left: 6), child: Text(hata, style: const TextStyle(color: Marka.gul, fontSize: 12))),
    ]);
  }
}

/* ───────────── Kayan segment ───────────── */

class _Segment extends StatelessWidget {
  const _Segment({required this.secili, required this.ogeler, required this.onSec});
  final int secili;
  final List<String> ogeler;
  final ValueChanged<int> onSec;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(18), border: Border.all(color: r.kenar), boxShadow: r.golge),
      child: LayoutBuilder(builder: (_, k) {
        final w = k.maxWidth / ogeler.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 480),
            curve: Curves.elasticOut,
            left: w * secili,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(14))),
          ),
          Row(children: [
            for (var i = 0; i < ogeler.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    titret();
                    onSec(i);
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 250),
                      style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 14, color: secili == i ? Colors.white : r.soluk),
                      child: Text(ogeler[i]),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

/* ───────────── "Vardiya bulunamadı!" illüstrasyonu ───────────── */

class _VardiyaYok extends StatefulWidget {
  const _VardiyaYok();
  @override
  State<_VardiyaYok> createState() => _VardiyaYokState();
}

class _VardiyaYokState extends State<_VardiyaYok> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PaKart(
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 34),
      child: Column(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: const Cubic(.22, 1, .36, 1),
          builder: (_, g, _) => AnimatedBuilder(
            animation: _c,
            builder: (_, _) => CustomPaint(size: const Size(240, 140), painter: _KartCizer(r, g, _c.value)),
          ),
        ),
        const SizedBox(height: 14),
        Text('Vardiya bulunamadı!', style: gosterim(22, renk: r.metin)),
        const SizedBox(height: 8),
        Text('Henüz planlanmış bir vardiyan yok. Bu durumu yöneticine bildirebilirsin.',
            textAlign: TextAlign.center, style: TextStyle(color: r.soluk, fontSize: 14, height: 1.45, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _KartCizer extends CustomPainter {
  _KartCizer(this.r, this.giris, this.yanip);
  final PaRenk r;
  final double giris;
  final double yanip;

  @override
  void paint(Canvas c, Size s) {
    final sx = s.width / 260;
    final sy = s.height / 150;
    c.save();
    c.scale(sx, sy);
    // Eğik kart (alttan süzülerek)
    c.save();
    c.translate(0, 18 * (1 - giris));
    c.translate(130, 75);
    c.rotate(-5 * math.pi / 180);
    c.translate(-130, -75);
    final kart = RRect.fromRectAndRadius(const Rect.fromLTWH(45, 35, 170, 80), const Radius.circular(12));
    c.drawRRect(kart, Paint()..color = r.ic.withValues(alpha: giris));
    c.drawRRect(kart, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = r.kenar.withValues(alpha: giris));
    void cubuk(double x, double y, double w, Color renk, [double h = 6]) =>
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(h / 2)), Paint()..color = renk.withValues(alpha: renk.a * giris));
    cubuk(60, 48, 34, r.kenar);
    cubuk(170, 48, 30, r.kenar);
    cubuk(60, 62, 26, r.kenar);
    cubuk(60, 76, 10, const Color(0xFFEF4444), 5);
    cubuk(72, 76, 74, r.metin, 5);
    cubuk(148, 76, 14, r.kenar, 5);
    cubuk(164, 76, 6, const Color(0xFFB45309), 5);
    cubuk(172, 76, 14, const Color(0xFFEAB308), 5);
    cubuk(188, 76, 14, const Color(0xFF9333EA), 5);
    cubuk(60, 90, 22, r.kenar);
    cubuk(176, 92, 22, r.kenar);
    c.restore();

    // Yanıp sönen işaretler (marka moru)
    final p = Paint()
      ..color = Marka.mor.withValues(alpha: (.35 + .65 * yanip) * giris)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawLine(const Offset(38, 10), const Offset(42, 34), p);
    c.drawCircle(const Offset(43, 42), 2.5, Paint()..color = p.color);
    c.drawPath(Path()..moveTo(18, 92)..relativeLineTo(14, -4)..relativeLineTo(-10, 8)..relativeLineTo(14, -2)..relativeLineTo(-12, 10), p);
    c.drawPath(Path()..moveTo(226, 28)..relativeLineTo(-14, 6)..relativeLineTo(12, 2)..relativeLineTo(-14, 8), p);
    c.drawPath(Path()..moveTo(222, 52)..relativeLineTo(16, 4)..relativeLineTo(-10, 6)..relativeLineTo(12, 6), p);
    c.restore();
  }

  @override
  bool shouldRepaint(_KartCizer o) => o.giris != giris || o.yanip != yanip || o.r != r;
}
