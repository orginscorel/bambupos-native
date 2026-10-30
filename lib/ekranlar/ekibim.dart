import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import '../ortak/gorev_onay.dart';
import 'gorevler.dart';

/// EKİBİM — yönetici modu. Yalnız `staff.view` / `staff.manage` /
/// `tasks.assign` yetkisi olanlar görür (Uyg.yonetici).
///
/// Kişiler sekmesi: durum sayaçları (dokununca süzer) + şubedeki personel
/// (durum noktası, giriş saati, çalışılan, gecikme). Görevler sekmesi: şube
/// görevleri (fotoğraflarıyla) — SALT OKUNUR: görev atama konsolda/yönetimde
/// yapılır, Personel uygulaması yalnız görevin okunup yapıldığı yerdir.
/// Mesai QR konum kuralı (mesai noktası) yalnız web konsolundan ayarlanır.
/// Ekran açıkken 30 sn'de bir kendini yeniler.
class EkibimEkrani extends StatefulWidget {
  const EkibimEkrani({super.key, this.ilkSekme = 0});
  final int ilkSekme;
  @override
  State<EkibimEkrani> createState() => _EkibimEkraniState();
}

/// Personel durumu → (etiket, renk). Ana sayfa özet kartı da kullanır.
(String, Color) ekipDurumu(String? d) => switch (d) {
      'mesaide' => ('Mesaide', Marka.zumrut),
      'molada' => ('Molada', Marka.lavanta),
      'cikti' => ('Çıktı', const Color(0xFF64748B)),
      'izinli' => ('İzinli', Marka.mavi),
      'gec' => ('Geç', Marka.kehribar),
      _ => ('Gelmedi', Marka.gul),
    };

class _EkibimEkraniState extends State<EkibimEkrani> with WidgetsBindingObserver {
  final _saat = DateFormat('HH:mm', 'tr_TR');
  late int _sekme = widget.ilkSekme.clamp(0, 1);
  String? _suzgec;

  Map<String, dynamic>? _ekip;
  ApiHata? _ekipHata;
  List<Map<String, dynamic>>? _gorevler;
  ApiHata? _gorevHata;
  int _gorevSekme = 0; // 0 aktif, 1 tamamlanan
  /// Fotoğraflı onay: karar yetkisi (tasks.assign) + karar süren görev.
  bool _onayYetkisi = false;
  int _kararMesgul = 0;

  Timer? _yokla;
  bool _onde = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _yenile();
    _yokla = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || !_onde || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _yenile(sessiz: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yokla?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _onde = s == AppLifecycleState.resumed;
    if (_onde) _yenile(sessiz: true);
  }

  Future<void> _yenile({bool sessiz = false}) {
    return Future.wait([_ekipYukle(sessiz), _gorevYukle(sessiz)]);
  }

  Future<void> _ekipYukle([bool sessiz = false]) async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/yonetici/ekip');
      if (!mounted) return;
      setState(() {
        _ekip = Map<String, dynamic>.from(r as Map);
        _ekipHata = null;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (_ekip == null) {
        setState(() => _ekipHata = e);
      } else if (!sessiz) {
        bildir('Ekip yenilenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      }
    }
  }

  Future<void> _gorevYukle([bool sessiz = false]) async {
    try {
      final r = await Uyg.api.get('/api/v1/portal/yonetici/gorevler') as Map;
      List<Map<String, dynamic>> l(Object? x) => ((x as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        _gorevler = l(r['gorevler']);
        _onayYetkisi = r['onay_yetkisi'] == true;
        _gorevHata = null;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (_gorevler == null) {
        setState(() => _gorevHata = e);
      } else if (!sessiz) {
        bildir('Görevler yenilenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      }
    }
  }

  Map<String, dynamic> get _ozet => (_ekip?['ozet'] as Map?)?.cast<String, dynamic>() ?? const {};
  int _i(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;
  DateTime? _t(Object? s) => s == null ? null : DateTime.tryParse(s.toString())?.toLocal();

  List<Map<String, dynamic>> get _kisiler {
    const sira = {'mesaide': 0, 'molada': 1, 'gelmedi': 2, 'cikti': 3, 'izinli': 4};
    final l = ((_ekip?['kisiler'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((k) {
      if (_suzgec == null) return true;
      if (_suzgec == 'gec') return _i(k, 'gec_dk') > 0;
      return k['durum'] == _suzgec;
    }).toList();
    l.sort((a, b) {
      final s = (sira[a['durum']] ?? 9).compareTo(sira[b['durum']] ?? 9);
      return s != 0 ? s : (a['ad']?.toString() ?? '').compareTo(b['ad']?.toString() ?? '');
    });
    return l;
  }

  String get _altBaslik {
    if (_ekip == null) return 'Şubendeki personel';
    final m = _i(_ozet, 'mesaide') + _i(_ozet, 'molada');
    return '${_i(_ozet, 'toplam')} kişi · $m kişi şu an içeride';
  }

  @override
  Widget build(BuildContext context) {
    return PaSayfa(
      baslik: 'Ekibim',
      altBaslik: _altBaslik,
      yenile: _yenile,
      govde: Kaydir(altBosluk: 40, children: [
        PaSegment(
          secili: _sekme,
          ogeler: const ['Kişiler', 'Görevler'],
          sayilar: [_ekip == null ? null : _i(_ozet, 'toplam'), _gorevler?.where((g) => g['status'] != 'done').length],
          onSec: (i) => setState(() => _sekme = i),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(
            key: ValueKey(_sekme),
            child: _sekme == 1 ? _gorevlerSekmesi() : _kisilerSekmesi(),
          ),
        ),
      ]),
    );
  }

  /* ───────────── Kişiler ───────────── */

  Widget _kisilerSekmesi() {
    if (_ekip == null && _ekipHata != null) return HataDurum(hata: _ekipHata!, onTekrar: () => _ekipYukle());
    if (_ekip == null) {
      return const Column(children: [
        Iskelet(yukseklik: 150, radius: 24),
        SizedBox(height: 14),
        Iskelet(yukseklik: 260, radius: 24),
      ]);
    }
    final kisiler = _kisiler;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sayaclar(),
      Row(children: [
        Expanded(child: BolumBasligi(_suzgec == null ? 'Personel' : '${ekipDurumu(_suzgec).$1} · ${kisiler.length}')),
        if (_suzgec != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: PaMetinDugme(yazi: 'Süzgeci kaldır', ikon: Icons.close_rounded, kucuk: true, onTap: () => setState(() => _suzgec = null)),
          ),
      ]),
      if (kisiler.isEmpty)
        BosDurum(
          ikon: Icons.groups_rounded,
          baslik: _suzgec == null ? 'Şubende personel yok' : 'Bu durumda kimse yok',
          aciklama: _suzgec == null ? null : 'Başka bir sayaca dokunarak süzebilirsin.',
        )
      else
        PaKart(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            for (var i = 0; i < kisiler.length; i++)
              Belir(key: ValueKey('k${kisiler[i]['id']}$_suzgec'), gecikme: math.min(i, 8) * 35, child: _kisiSatiri(kisiler[i])),
          ]),
        ),
    ]);
  }

  Widget _sayaclar() {
    final r = context.pa;
    const anahtarlar = ['mesaide', 'molada', 'cikti', 'gelmedi', 'izinli', 'gec'];
    return PaKart(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(builder: (_, c) {
        final sutun = c.maxWidth > 560 ? 6 : 3;
        final gen = (c.maxWidth - 8 * (sutun - 1)) / sutun;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in anahtarlar)
            Builder(builder: (_) {
              final (etiket, renk) = ekipDurumu(k);
              final yazi = r.koyu ? Color.lerp(renk, Colors.white, .25)! : renk;
              final secili = _suzgec == k;
              return Basilir(
                onTap: () => setState(() => _suzgec = secili ? null : k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: gen,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: renk.withValues(alpha: secili ? .2 : .1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: secili ? renk : Colors.transparent, width: 1.5),
                  ),
                  child: Column(children: [
                    Sayac(deger: _i(_ozet, k), yaz: (v) => v.round().toString(), stil: gosterim(20, renk: yazi)),
                    Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: yazi)),
                  ]),
                ),
              );
            }),
        ]);
      }),
    );
  }

  Widget _kisiSatiri(Map<String, dynamic> k) {
    final r = context.pa;
    final durum = k['durum']?.toString();
    final (etiket, renk) = ekipDurumu(durum);
    final gi = _t(k['giris']);
    final co = _t(k['cikis']);
    final gec = _i(k, 'gec_dk');
    final calisilan = _i(k, 'calisilan_dk');
    final v = k['vardiya'] is Map ? k['vardiya'] as Map : null;
    final vb = _t(v?['bas']);
    final vs = _t(v?['bit']);
    final ad = k['ad']?.toString() ?? '';
    final harf = ad.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2).map((e) => e.characters.first.toUpperCase()).join();
    final pozisyon = k['pozisyon']?.toString();

    final bilgi = <String>[
      if (gi != null) 'Giriş ${_saat.format(gi)}${co != null ? ' – ${_saat.format(co)}' : ''}',
      if (gi == null && vb != null) 'Shift ${_saat.format(vb)}${vs != null ? ' – ${_saat.format(vs)}' : ''}',
      if (gi == null && vb == null && durum != 'izinli') 'Bugün shift yok',
      if (durum == 'izinli' && gi == null && vb == null) 'İzinli',
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(14)),
            child: Text(harf.isEmpty ? '•' : harf, style: gosterim(15, renk: r.birincil)),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: renk, shape: BoxShape.circle, border: Border.all(color: r.ic, width: 2.5)),
            ),
          ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: r.metin, fontSize: 14)),
            Text(
              [if (pozisyon != null && pozisyon.isNotEmpty) pozisyon, ...bilgi].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: r.soluk),
            ),
            if (gec > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.alarm_rounded, size: 12, color: Marka.gul),
                  const SizedBox(width: 3),
                  Text('${dakikaYaz(gec)} geç kaldı', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Marka.gul)),
                ]),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (calisilan > 0 || gi != null) Text(dakikaYaz(calisilan), style: gosterim(16, renk: r.metin)),
          Text(etiket, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: r.koyu ? Color.lerp(renk, Colors.white, .25) : renk)),
        ]),
      ]),
    );
  }

  /* ───────────── Görevler ───────────── */

  Future<void> _karar(Map<String, dynamic> g, bool onay) async {
    if (_kararMesgul != 0) return;
    final id = (g['id'] as num).toInt();
    if (onay) setState(() => _kararMesgul = id);
    final yeni = onay ? await gorevOnayla(id) : await gorevReddet(context, g);
    if (!mounted) return;
    setState(() {
      _kararMesgul = 0;
      final i = _gorevler?.indexWhere((t) => t['id'] == id) ?? -1;
      if (yeni != null && i >= 0) _gorevler![i] = yeni;
    });
    if (yeni != null) _gorevYukle(true);
  }

  Widget _gorevlerSekmesi() {
    final r = context.pa;
    if (_gorevler == null && _gorevHata != null) return HataDurum(hata: _gorevHata!, onTekrar: () => _gorevYukle());
    final g = (_ekip?['gorevler'] as Map?) ?? const {};
    Widget kutu(int deger, String etiket, Color zemin, Color renk) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: zemin, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Sayac(deger: deger, yaz: (v) => v.round().toString(), stil: gosterim(20, renk: renk)),
              Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk)),
            ]),
          ),
        );
    final tum = _gorevler ?? const <Map<String, dynamic>>[];
    const pr = {'urgent': 0, 'high': 1, 'normal': 2, 'low': 3};
    final liste = tum.where((t) => _gorevSekme == 0 ? t['status'] != 'done' : t['status'] == 'done').toList()
      ..sort((a, b) {
        // Onay bekleyenler en üstte.
        final o = (a['status'] == 'review' ? 0 : 1).compareTo(b['status'] == 'review' ? 0 : 1);
        if (o != 0) return o;
        if (_gorevSekme == 1) return (b['completed_at']?.toString() ?? '').compareTo(a['completed_at']?.toString() ?? '');
        final p = (pr[a['priority']] ?? 2).compareTo(pr[b['priority']] ?? 2);
        return p != 0 ? p : (a['due_at']?.toString() ?? '9').compareTo(b['due_at']?.toString() ?? '9');
      });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PaKart(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          kutu(_i(g, 'acik'), 'Bekleyen', r.ic, r.soluk),
          const SizedBox(width: 8),
          kutu(_i(g, 'devam') + _i(g, 'onay_bekleyen'), 'Sürüyor', r.birincilYumusak, r.birincil),
          const SizedBox(width: 8),
          kutu(_i(g, 'bugun_biten'), 'Bugün biten', Marka.zumrut.withValues(alpha: .14), r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
        ]),
      ),
      const SizedBox(height: 14),
      PaSegment(
        secili: _gorevSekme,
        ogeler: const ['Aktif', 'Tamamlanan'],
        sayilar: [tum.where((t) => t['status'] != 'done').length, tum.where((t) => t['status'] == 'done').length],
        onSec: (i) => setState(() => _gorevSekme = i),
      ),
      const SizedBox(height: 14),
      if (_gorevler == null)
        const Column(children: [Iskelet(yukseklik: 96, radius: 24), SizedBox(height: 12), Iskelet(yukseklik: 96, radius: 24)])
      else if (liste.isEmpty)
        BosDurum(
          ikon: Icons.assignment_turned_in_rounded,
          baslik: _gorevSekme == 0 ? 'Açık görev yok' : 'Henüz tamamlanan yok',
          aciklama: _gorevSekme == 0 ? 'Görevler yönetim panelinden atanır.' : null,
        )
      else
        for (var i = 0; i < liste.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Belir(
              key: ValueKey('yg${liste[i]['id']}${liste[i]['status']}'),
              gecikme: math.min(i, 6) * 50,
              child: GorevKarti(
                g: liste[i],
                atananGoster: true,
                mesgul: _kararMesgul == (liste[i]['id'] as num).toInt(),
                onOnayla: _onayYetkisi ? () => _karar(liste[i], true) : null,
                onReddet: _onayYetkisi ? () => _karar(liste[i], false) : null,
              ),
            ),
          ),
    ]);
  }
}
