import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/bildirim.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// SHIFT (sekme; eski adı "Vardiyam") — web Schedule.vue karşılığı.
///
/// Üstte sıradaki/süren Shift geri sayımı, "Benimle çalışanlar" (gün
/// seçmeli; GET /api/v1/portal/shift/ekip?tarih=), sonra Shift planı.
/// Üstte izin talepleri (oluştur / bekleyeni geri çek), altta yaklaşan
/// vardiyalar gün gün (bugün/yarın rozetli, sol renkli şerit). Vardiya
/// yoksa illüstrasyonlu "Shift bulunamadı!" boş durumu.
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
  Timer? _saatTik;

  // Benimle çalışanlar
  String _ekipTarih = _isoGun(DateTime.now());
  final _ekipOnbellek = <String, Map<String, dynamic>>{};
  ApiHata? _ekipHata;
  bool _ekipYukleniyor = false;
  List<Map<String, dynamic>> _ekipGunler = const [];

  @override
  void initState() {
    super.initState();
    _yenile();
    // Geri sayım kartı dakikada bir tazelensin
    _saatTik = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) setState(() {});
    });
  }

  @override
  void dispose() {
    _saatTik?.cancel();
    super.dispose();
  }

  Future<void> _yenile() {
    _ekipOnbellek.clear();
    return Future.wait([_vardiyaYukle(), _izinYukle(), _ekipYukle(_ekipTarih)]);
  }

  static String _isoGun(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _ekipYukle(String tarih) async {
    setState(() {
      _ekipTarih = tarih;
      _ekipHata = null;
      _ekipYukleniyor = !_ekipOnbellek.containsKey(tarih);
    });
    try {
      final r = await Uyg.api.get('/api/v1/portal/shift/ekip', sorgu: {'tarih': tarih});
      final m = r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _ekipOnbellek[tarih] = m;
        final g = ((m['gunler'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (g.isNotEmpty) _ekipGunler = g;
      });
    } on ApiHata catch (e) {
      if (!mounted || _ekipTarih != tarih) return;
      if (!_ekipOnbellek.containsKey(tarih)) setState(() => _ekipHata = e);
    } finally {
      if (mounted && _ekipTarih == tarih) setState(() => _ekipYukleniyor = false);
    }
  }

  Future<void> _vardiyaYukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/schedule') as Map;
      final ham = ((r['shifts'] as List?) ?? const []).whereType<Map>().toList();
      final l = ham.map(_Vardiya.new).toList()..sort((a, b) => a.bas.compareTo(b.bas));
      if (mounted) setState(() => _vardiyalar = l);
      // Sesli Shift hatırlatmalarını taze planla kur (Android; iOS'ta APNs).
      unawaited(BildirimMerkezi.hatirlatmaEsitle(vardiyalar: ham));
    } on ApiHata catch (e) {
      bildir('Shift planı yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
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
    if (_vardiyalar.isEmpty) return 'Planlı shift yok';
    final toplam = _vardiyalar.fold<int>(0, (a, v) => a + v.dakika);
    return '${_vardiyalar.length} shift · ${dakikaYaz(toplam)} planlı';
  }

  @override
  Widget build(BuildContext context) {
    final bekleyen = _izinler.where((i) => i.durum == 'pending').length;
    return PaSayfa(
      baslik: 'Shift',
      altBaslik: _altBaslik,
      geri: false,
      yenile: _yenile,
      govde: Kaydir(children: [
        if (!_yukleniyor && _siradaki != null) ...[_geriSayimKarti(_siradaki!), const SizedBox(height: 16)],
        PaSegment(
          secili: _sekme,
          ogeler: const ['Shift planım', 'İzinlerim'],
          sayilar: [_yukleniyor ? null : _vardiyalar.length, bekleyen > 0 ? bekleyen : null],
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

  /* ───────────── Sıradaki Shift geri sayımı ───────────── */

  _Vardiya? get _siradaki {
    final simdi = DateTime.now();
    for (final v in _vardiyalar) {
      if (v.bit.isAfter(simdi)) return v;
    }
    return null;
  }

  String _sureYaz(Duration d) {
    final dk = d.inMinutes;
    if (dk < 1) return 'şimdi';
    final g = dk ~/ 1440;
    final s = (dk % 1440) ~/ 60;
    final k = dk % 60;
    if (g > 0) return '$g gün${s > 0 ? ' $s sa' : ''}';
    if (s > 0) return '$s sa${k > 0 ? ' $k dk' : ''}';
    return '$k dk';
  }

  Widget _geriSayimKarti(_Vardiya v) {
    final simdi = DateTime.now();
    final suruyor = !simdi.isBefore(v.bas);
    final oran = suruyor ? (simdi.difference(v.bas).inSeconds / math.max(1, v.bit.difference(v.bas).inSeconds)).clamp(0.0, 1.0) : 0.0;
    final goreli = _goreli(v.bas);
    final gun = goreli ?? DateFormat('d MMMM EEEE', 'tr_TR').format(v.bas);
    final beyaz70 = Colors.white.withValues(alpha: .72);
    return PaKart(
      gradient: Marka.kart,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: suruyor ? Marka.zumrut.withValues(alpha: .22) : Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: suruyor ? const Color(0xFF6EE7B7) : Marka.gok)),
              const SizedBox(width: 6),
              Text(suruyor ? 'Shift sürüyor' : 'Sıradaki shift', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          const Spacer(),
          Text(gun, style: TextStyle(color: beyaz70, fontWeight: FontWeight.w600, fontSize: 12.5)),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_saatFmt.format(v.bas)} – ${_saatFmt.format(v.bit)}', style: gosterim(28, renk: Colors.white)),
              const SizedBox(height: 2),
              Text(
                [if (v.pozisyon?.isNotEmpty ?? false) v.pozisyon!, if (v.sube?.isNotEmpty ?? false) v.sube!, dakikaYaz(v.dakika)].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: beyaz70, fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(suruyor ? 'Bitişe' : 'Başlamasına', style: TextStyle(color: beyaz70, fontSize: 11.5, fontWeight: FontWeight.w600)),
            Text(_sureYaz((suruyor ? v.bit : v.bas).difference(simdi)), style: gosterim(20, renk: Colors.white)),
          ]),
        ]),
        if (suruyor) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(children: [
              Container(height: 6, color: Colors.white.withValues(alpha: .16)),
              FractionallySizedBox(
                widthFactor: oran,
                child: Container(height: 6, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Marka.gok, Color(0xFF6EE7B7)]))),
              ),
            ]),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.qr_code_scanner_rounded, size: 15, color: beyaz70),
            const SizedBox(width: 6),
            Expanded(child: Text('Girişte mesai QR\'ını okutmayı unutma.', style: TextStyle(color: beyaz70, fontSize: 12))),
          ]),
        ],
      ]),
    );
  }

  /* ───────────── Shift planı ───────────── */

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
    final gunler = _gunler.entries.toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _ekipBolumu(),
      _bolumBasi(Icons.event_note_rounded, 'Shift planım', _vardiyalar.isEmpty ? 'Önümüzdeki günler' : '${_vardiyalar.length} shift · ${gunler.length} gün'),
      if (_vardiyalar.isEmpty) const _VardiyaYok(),
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

  /* ───────────── Benimle çalışanlar ───────────── */

  Widget _bolumBasi(IconData ikon, String baslik, String? alt, {Widget? sag, double ust = 22}) {
    final r = context.pa;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, ust, 2, 12),
      child: Row(children: [
        PaIkon(ikon, boyut: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(baslik, style: gosterim(17.5, renk: r.metin)),
            if (alt != null) Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk, fontWeight: FontWeight.w500)),
          ]),
        ),
        ?sag,
      ]),
    );
  }

  /// Sunucu `gunler` vermediyse (yükleniyor / hata) yerelde 7 gün.
  List<Map<String, dynamic>> get _gunSecenekleri {
    if (_ekipGunler.isNotEmpty) return _ekipGunler;
    final bugun = DateTime.now();
    final kisa = DateFormat('EEE d', 'tr_TR');
    return [
      for (var i = 0; i < 7; i++)
        {'tarih': _isoGun(bugun.add(Duration(days: i))), 'etiket': i == 0 ? 'Bugün' : i == 1 ? 'Yarın' : kisa.format(bugun.add(Duration(days: i))), 'sayi': null},
    ];
  }

  Widget _ekipBolumu() {
    final veri = _ekipOnbellek[_ekipTarih];
    final ekip = ((veri?['ekip'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final bugunMu = _ekipTarih == _isoGun(DateTime.now());
    final gunAdi = veri?['gun_adi']?.toString();
    final alt = veri == null
        ? 'Aynı gün shifti olan ekip arkadaşların'
        : '${bugunMu ? 'Bugün' : (gunAdi ?? _ekipTarih)} · ${ekip.isEmpty ? 'kimse yok' : '${ekip.length} kişi'}';

    Widget govde;
    if (_ekipHata != null && veri == null) {
      govde = HataDurum(hata: _ekipHata!, onTekrar: () => _ekipYukle(_ekipTarih));
    } else if (veri == null) {
      govde = const Column(children: [Iskelet(yukseklik: 64, radius: 18), SizedBox(height: 8), Iskelet(yukseklik: 64, radius: 18)]);
    } else if (ekip.isEmpty) {
      govde = _ekipBos();
    } else {
      govde = _ekipListesi(veri, ekip, bugunMu);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _bolumBasi(Icons.groups_rounded, bugunMu ? 'Bugün benimle çalışanlar' : 'Benimle çalışanlar', alt, ust: 4,
          sag: _ekipYukleniyor && veri != null ? const SizedBox(width: 18, height: 18, child: Yukleyici(boyut: 18, renk: Marka.mor)) : null),
      _gunCipleri(),
      const SizedBox(height: 12),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: KeyedSubtree(key: ValueKey('$_ekipTarih${veri == null}${_ekipHata != null}'), child: govde),
      ),
    ]);
  }

  Widget _gunCipleri() {
    final r = context.pa;
    final gunler = _gunSecenekleri;
    return SizedBox(
      height: 66,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: gunler.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = gunler[i];
          final tarih = g['tarih']?.toString() ?? '';
          final secili = tarih == _ekipTarih;
          final sayi = (g['sayi'] as num?)?.toInt();
          final etiket = g['etiket']?.toString() ?? tarih;
          // "Sal 28" → üst satır gün adı, alt satır rakam; "Bugün" tek satır
          var parca = etiket.split(' ');
          if (parca.length == 1) parca = [etiket, '${DateTime.tryParse(tarih)?.day ?? ''}'];
          return Basilir(
            onTap: () {
              if (!secili) _ekipYukle(tarih);
            },
            olcek: .94,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              width: 64,
              decoration: BoxDecoration(
                gradient: secili ? Marka.grad : null,
                color: secili ? null : r.kart,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: secili ? Colors.white.withValues(alpha: .2) : r.kenar),
                boxShadow: secili
                    ? [BoxShadow(color: Marka.mor.withValues(alpha: .4), blurRadius: 14, offset: const Offset(0, 6), spreadRadius: -6)]
                    : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(parca.first, maxLines: 1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: secili ? Colors.white.withValues(alpha: .85) : r.soluk)),
                if (parca.length > 1)
                  Text(parca.sublist(1).join(' '), style: gosterim(17, renk: secili ? Colors.white : r.metin))
                else
                  const SizedBox(height: 2),
                const SizedBox(height: 3),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: secili ? Colors.white.withValues(alpha: .22) : (sayi ?? 0) > 0 ? r.birincilYumusak : r.ic,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(sayi == null ? '–' : '$sayi',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: secili ? Colors.white : (sayi ?? 0) > 0 ? r.birincil : r.silik)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _ekipBos() {
    final r = context.pa;
    return PaKart(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(children: [
        PaIkon(Icons.person_off_rounded, boyut: 46, zemin: r.ic, renk: r.silik),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bu gün seninle çalışan kimse yok', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: r.metin)),
            const SizedBox(height: 2),
            Text('Başka bir güne dokunarak ekibi görebilirsin.', style: TextStyle(fontSize: 12.5, color: r.soluk)),
          ]),
        ),
      ]),
    );
  }

  /// "09:00" ya da ISO tarih → o günün DateTime'ı.
  DateTime? _anCoz(Object? s, DateTime gun) {
    if (s == null) return null;
    final t = s.toString();
    if (t.contains('T') || t.length > 8) return DateTime.tryParse(t)?.toLocal();
    final p = t.split(':');
    if (p.length < 2) return null;
    final sa = int.tryParse(p[0]);
    final dk = int.tryParse(p[1]);
    if (sa == null || dk == null) return null;
    return DateTime(gun.year, gun.month, gun.day, sa, dk);
  }

  (DateTime, DateTime)? _aralik(Map m, DateTime gun) {
    final b = _anCoz(m['bas'], gun);
    var e = _anCoz(m['bit'], gun);
    if (b == null || e == null) return null;
    if (!e.isAfter(b)) e = e.add(const Duration(days: 1)); // gece devreden shift
    return (b, e);
  }

  Widget _ekipListesi(Map<String, dynamic> veri, List<Map<String, dynamic>> ekip, bool bugunMu) {
    final r = context.pa;
    final gun = DateTime.tryParse(veri['tarih']?.toString() ?? _ekipTarih) ?? DateTime.now();
    final ben = veri['ben'] is Map ? veri['ben'] as Map : null;
    final benAralik = ben == null ? null : _aralik(ben, gun);
    // Zaman çizelgesi penceresi: herkesin shiftini kapsar
    final araliklar = [?benAralik, for (final k in ekip) ?_aralik(k, gun)];
    DateTime? pBas, pBit;
    for (final a in araliklar) {
      if (pBas == null || a.$1.isBefore(pBas)) pBas = a.$1;
      if (pBit == null || a.$2.isAfter(pBit)) pBit = a.$2;
    }
    // Ortak süreye göre sırala (en çok çakışan üstte)
    final sirali = [...ekip]..sort((a, b) => ((b['ortak_dk'] as num?) ?? 0).compareTo((a['ortak_dk'] as num?) ?? 0));

    return PaKart(
      padding: const EdgeInsets.all(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (benAralik != null)
          Container(
            margin: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.person_pin_circle_rounded, size: 18, color: r.birincil),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Senin shiftin  ', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w500)),
                    TextSpan(text: '${_saatFmt.format(benAralik.$1)} – ${_saatFmt.format(benAralik.$2)}', style: TextStyle(color: r.metin, fontWeight: FontWeight.w700)),
                    if (ben?['pozisyon'] != null) TextSpan(text: '  · ${ben!['pozisyon']}', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w500)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
            ]),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Text('Bu gün senin shiftin yok; o gün çalışan ekip listelendi.', style: TextStyle(fontSize: 12, color: r.silik)),
          ),
        for (var i = 0; i < sirali.length; i++)
          Belir(
            key: ValueKey('ek$_ekipTarih${sirali[i]['id']}'),
            gecikme: math.min(i, 8) * 35,
            child: _ekipSatiri(sirali[i], gun, benAralik, pBas, pBit, bugunMu),
          ),
      ]),
    );
  }

  (String, Color) _ekipDurum(String? d) => switch (d) {
        'mesaide' => ('Mesaide', Marka.zumrut),
        'molada' => ('Molada', Marka.lavanta),
        'cikti' => ('Çıktı', const Color(0xFF64748B)),
        'gelmedi' => ('Gelmedi', Marka.gul),
        'bekliyor' => ('Bekleniyor', Marka.kehribar),
        _ => ('', const Color(0xFF94A3B8)),
      };

  Widget _ekipSatiri(Map<String, dynamic> k, DateTime gun, (DateTime, DateTime)? ben, DateTime? pBas, DateTime? pBit, bool bugunMu) {
    final r = context.pa;
    final ad = k['ad']?.toString() ?? '';
    final harf = ad.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2).map((e) => e.characters.first.toUpperCase()).join();
    final poz = k['pozisyon']?.toString();
    final aralik = _aralik(k, gun);
    final ortakDk = (k['ortak_dk'] as num?)?.toInt() ??
        (aralik != null && ben != null
            ? math.max(0, (aralik.$2.isBefore(ben.$2) ? aralik.$2 : ben.$2).difference(aralik.$1.isAfter(ben.$1) ? aralik.$1 : ben.$1).inMinutes)
            : 0);
    final (durumAd, durumRenk) = _ekipDurum(k['durum']?.toString());
    final canli = bugunMu && durumAd.isNotEmpty;
    final ortakYazi = ortakDk <= 0 ? 'ortak yok' : 'ortak ${ortakDk >= 60 ? '${ortakDk ~/ 60} sa${ortakDk % 60 > 0 ? ' ${ortakDk % 60} dk' : ''}' : '$ortakDk dk'}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14), border: Border.all(color: r.kenar)),
              child: Text(harf.isEmpty ? '•' : harf, style: gosterim(14.5, renk: r.birincil)),
            ),
            if (canli)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(width: 14, height: 14, decoration: BoxDecoration(color: durumRenk, shape: BoxShape.circle, border: Border.all(color: r.ic, width: 2.5))),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: r.metin)),
              Text(
                [if (poz != null && poz.isNotEmpty) poz, if (canli) durumAd].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: r.soluk),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(aralik == null ? '—' : '${_saatFmt.format(aralik.$1)}–${_saatFmt.format(aralik.$2)}', style: gosterim(14.5, agirlik: FontWeight.w700, renk: r.metin)),
            Text(ortakYazi,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: ortakDk > 0 ? (r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)) : r.silik)),
          ]),
        ]),
        if (aralik != null && pBas != null && pBit != null) ...[
          const SizedBox(height: 9),
          SizedBox(height: 8, child: CustomPaint(size: Size.infinite, painter: _CakismaCizer(r: r, pBas: pBas, pBit: pBit, o: aralik, ben: ben))),
        ],
      ]),
    );
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

/* ───────────── "Shift bulunamadı!" illüstrasyonu ───────────── */

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
        Text('Shift bulunamadı!', style: gosterim(22, renk: r.metin)),
        const SizedBox(height: 8),
        Text('Henüz planlanmış bir shiftin yok. Bu durumu yöneticine bildirebilirsin.',
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

/// Mini zaman çizelgesi: soluk iz = günün penceresi, mor bant = benim shiftim,
/// dolu çubuk = arkadaşın shifti, yeşil = ortak süre.
class _CakismaCizer extends CustomPainter {
  _CakismaCizer({required this.r, required this.pBas, required this.pBit, required this.o, required this.ben});
  final PaRenk r;
  final DateTime pBas;
  final DateTime pBit;
  final (DateTime, DateTime) o;
  final (DateTime, DateTime)? ben;

  @override
  void paint(Canvas c, Size s) {
    final top = math.max(1, pBit.difference(pBas).inMinutes);
    double x(DateTime t) => (t.difference(pBas).inMinutes / top).clamp(0.0, 1.0) * s.width;
    RRect rr(double a, double b, double h) => RRect.fromRectAndRadius(Rect.fromLTRB(a, (s.height - h) / 2, math.max(a + h, b), (s.height + h) / 2), Radius.circular(h / 2));
    c.drawRRect(rr(0, s.width, 4), Paint()..color = r.kenar);
    if (ben != null) c.drawRRect(rr(x(ben!.$1), x(ben!.$2), 8), Paint()..color = Marka.mor.withValues(alpha: r.koyu ? .35 : .18));
    c.drawRRect(rr(x(o.$1), x(o.$2), 4), Paint()..color = r.koyu ? const Color(0xFF8B93AB) : const Color(0xFF94A3B8));
    if (ben != null) {
      final a = o.$1.isAfter(ben!.$1) ? o.$1 : ben!.$1;
      final b = o.$2.isBefore(ben!.$2) ? o.$2 : ben!.$2;
      if (b.isAfter(a)) {
        c.drawRRect(rr(x(a), x(b), 4), Paint()..shader = const LinearGradient(colors: [Marka.zumrut, Color(0xFF34D399)]).createShader(Offset.zero & s));
      }
    }
  }

  @override
  bool shouldRepaint(_CakismaCizer e) => e.o != o || e.ben != ben || e.pBas != pBas || e.pBit != pBit || e.r != r;
}
