import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'gorevler.dart';

/// EKİBİM — yönetici modu. Yalnız `staff.view` / `staff.manage` /
/// `tasks.assign` yetkisi olanlar görür (Uyg.yonetici).
///
/// Kişiler sekmesi: durum sayaçları (dokununca süzer) + şubedeki personel
/// (durum noktası, giriş saati, çalışılan, gecikme). Görevler sekmesi: şube
/// görevleri (fotoğraflarıyla) + "Görev ver" formu (`tasks.assign`).
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
  late int _sekme = widget.ilkSekme;
  String? _suzgec;

  Map<String, dynamic>? _ekip;
  ApiHata? _ekipHata;
  List<Map<String, dynamic>>? _gorevler;
  List<Map<String, dynamic>> _personel = const [];
  ApiHata? _gorevHata;
  int _gorevSekme = 0; // 0 aktif, 1 tamamlanan

  Timer? _yokla;
  bool _onde = true;

  bool get _gorevVerebilir => Uyg.izin('tasks.assign');

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

  Future<void> _yenile({bool sessiz = false}) => Future.wait([_ekipYukle(sessiz), _gorevYukle(sessiz)]);

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
        _personel = l(r['personel']);
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
      eylem: _gorevVerebilir
          ? Basilir(
              onTap: _gorevVer,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle),
                child: const Icon(Icons.add_task_rounded, color: Colors.white, size: 22),
              ),
            )
          : null,
      govde: Kaydir(altBosluk: 40, children: [
        _Sekme(
          secili: _sekme,
          etiketler: ['Kişiler  ${_ekip == null ? '' : _i(_ozet, 'toplam')}', 'Görevler  ${_gorevler == null ? '' : _gorevler!.where((g) => g['status'] != 'done').length}'],
          onSec: (i) => setState(() => _sekme = i),
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(_sekme), child: _sekme == 0 ? _kisilerSekmesi() : _gorevlerSekmesi()),
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
            child: TextButton.icon(
              onPressed: () => setState(() => _suzgec = null),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Süzgeci kaldır'),
              style: TextButton.styleFrom(foregroundColor: context.pa.birincil, textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
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
      if (gi == null && vb != null) 'Vardiya ${_saat.format(vb)}${vs != null ? ' – ${_saat.format(vs)}' : ''}',
      if (gi == null && vb == null && durum != 'izinli') 'Bugün vardiya yok',
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
          kutu(_i(g, 'devam'), 'Sürüyor', r.birincilYumusak, r.birincil),
          const SizedBox(width: 8),
          kutu(_i(g, 'bugun_biten'), 'Bugün biten', Marka.zumrut.withValues(alpha: .14), r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857)),
        ]),
      ),
      if (_gorevVerebilir) ...[
        const SizedBox(height: 14),
        GradDugme(yazi: 'Görev ver', ikon: Icons.add_task_rounded, onTap: _gorevVer),
      ],
      const SizedBox(height: 14),
      _Sekme(
        secili: _gorevSekme,
        etiketler: ['Aktif  ${tum.where((t) => t['status'] != 'done').length}', 'Tamamlanan  ${tum.where((t) => t['status'] == 'done').length}'],
        onSec: (i) => setState(() => _gorevSekme = i),
      ),
      const SizedBox(height: 14),
      if (_gorevler == null)
        const Column(children: [Iskelet(yukseklik: 96, radius: 24), SizedBox(height: 12), Iskelet(yukseklik: 96, radius: 24)])
      else if (liste.isEmpty)
        BosDurum(
          ikon: Icons.assignment_turned_in_rounded,
          baslik: _gorevSekme == 0 ? 'Açık görev yok' : 'Henüz tamamlanan yok',
          aciklama: _gorevSekme == 0 && _gorevVerebilir ? '"Görev ver" ile ekibine görev atayabilirsin.' : null,
        )
      else
        for (var i = 0; i < liste.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Belir(
              key: ValueKey('yg${liste[i]['id']}${liste[i]['status']}'),
              gecikme: math.min(i, 6) * 50,
              child: GorevKarti(g: liste[i], atananGoster: true),
            ),
          ),
    ]);
  }

  Future<void> _gorevVer() async {
    if (!_gorevVerebilir) return;
    final verildi = await panoAc<bool>(
      context,
      baslik: 'Görev ver',
      alt: 'Atadığın kişiye bildirim gider.',
      icerik: (_) => _GorevFormu(personel: _personel),
    );
    if (verildi == true) {
      bildir('Görev verildi');
      setState(() {
        _sekme = 1;
        _gorevSekme = 0;
      });
      await _yenile(sessiz: true);
    }
  }
}

/* ───────────── Kayan sekme (Görevlerim ekranıyla aynı) ───────────── */

class _Sekme extends StatelessWidget {
  const _Sekme({required this.secili, required this.etiketler, required this.onSec});
  final int secili;
  final List<String> etiketler;
  final ValueChanged<int> onSec;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(18), border: Border.all(color: r.kenar), boxShadow: r.golge),
      child: Stack(children: [
        AnimatedAlign(
          alignment: secili == 0 ? Alignment.centerLeft : Alignment.centerRight,
          duration: const Duration(milliseconds: 500),
          curve: Curves.elasticOut,
          child: FractionallySizedBox(
            widthFactor: .5,
            child: Container(decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(14))),
          ),
        ),
        Row(children: [
          for (var i = 0; i < etiketler.length; i++)
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
                    child: Text(etiketler[i].trim()),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

/* ───────────── Görev ver formu (pano içi) ───────────── */

class _GorevFormu extends StatefulWidget {
  const _GorevFormu({required this.personel});
  final List<Map<String, dynamic>> personel;
  @override
  State<_GorevFormu> createState() => _GorevFormuState();
}

class _GorevFormuState extends State<_GorevFormu> {
  static const _oncelikler = [('low', 'Düşük'), ('normal', 'Normal'), ('high', 'Yüksek')];
  final _fmt = DateFormat('d MMMM y, EEEE HH:mm', 'tr_TR');
  final _baslik = TextEditingController();
  final _aciklama = TextEditingController();
  int? _atanan; // null = herkese açık
  String _oncelik = 'normal';
  DateTime? _bitis;
  bool _gonder = false;
  final _hatalar = <String, String>{};

  @override
  void dispose() {
    _baslik.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  String get _atananAd {
    if (_atanan == null) return 'Herkese açık';
    final k = widget.personel.firstWhere((p) => (p['id'] as num?)?.toInt() == _atanan, orElse: () => const {});
    return k['ad']?.toString() ?? 'Seçili kişi';
  }

  Future<void> _kisiSec() async {
    final sec = await panoAc<Object>(
      context,
      baslik: 'Kime verilsin?',
      icerik: (ctx) => SatirGrubu([
        Satir(
          ikon: Icons.groups_rounded,
          baslik: 'Herkese açık',
          alt: 'Şubede ilk üstlenen yapar',
          ikonZemin: const Color(0xFFE0F2FE),
          ikonRenk: const Color(0xFF0284C7),
          sag: _atanan == null ? Icon(Icons.check_rounded, color: ctx.pa.birincil) : null,
          onTap: () => Navigator.pop(ctx, 0),
        ),
        for (final p in widget.personel)
          Satir(
            ikon: Icons.person_rounded,
            baslik: p['ad']?.toString() ?? '',
            sag: (p['id'] as num?)?.toInt() == _atanan ? Icon(Icons.check_rounded, color: ctx.pa.birincil) : null,
            onTap: () => Navigator.pop(ctx, (p['id'] as num).toInt()),
          ),
      ]),
    );
    if (sec is int) setState(() => _atanan = sec == 0 ? null : sec);
  }

  Future<void> _bitisSec() async {
    final simdi = DateTime.now();
    final gun = await showDatePicker(
      context: context,
      locale: const Locale('tr', 'TR'),
      initialDate: _bitis ?? simdi,
      firstDate: DateTime(simdi.year, simdi.month, simdi.day),
      lastDate: DateTime(simdi.year + 1),
    );
    if (gun == null || !mounted) return;
    final saat = await showTimePicker(
      context: context,
      initialTime: _bitis != null ? TimeOfDay.fromDateTime(_bitis!) : const TimeOfDay(hour: 18, minute: 0),
    );
    if (!mounted) return;
    final s = saat ?? const TimeOfDay(hour: 23, minute: 59);
    setState(() {
      _bitis = DateTime(gun.year, gun.month, gun.day, s.hour, s.minute);
      _hatalar.remove('bitis');
    });
  }

  Future<void> _kaydet() async {
    _hatalar.clear();
    if (_baslik.text.trim().isEmpty) _hatalar['baslik'] = 'Görev başlığı gerekli.';
    if (_bitis != null && _bitis!.isBefore(DateTime.now())) _hatalar['bitis'] = 'Bitiş zamanı geçmişte olamaz.';
    if (_hatalar.isNotEmpty) {
      setState(() {});
      titret(1);
      return;
    }
    setState(() => _gonder = true);
    try {
      await Uyg.api.post('/api/v1/portal/yonetici/gorev', {
        'baslik': _baslik.text.trim(),
        if (_aciklama.text.trim().isNotEmpty) 'aciklama': _aciklama.text.trim(),
        'atanan_id': _atanan,
        'oncelik': _oncelik,
        if (_bitis != null) 'bitis': _bitis!.toUtc().toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      final h = e.govde?['errors'];
      if (h is Map) {
        h.forEach((k, v) => _hatalar[k.toString()] = v is List && v.isNotEmpty ? v.first.toString() : v.toString());
      } else {
        bildir('Görev verilemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _gonder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _baslik,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 160,
        decoration: InputDecoration(labelText: 'Görev başlığı', errorText: _hatalar['baslik'], counterText: ''),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _aciklama,
        textCapitalization: TextCapitalization.sentences,
        maxLines: 3,
        decoration: InputDecoration(labelText: 'Açıklama (isteğe bağlı)', errorText: _hatalar['aciklama'], alignLabelWithHint: true),
      ),
      const SizedBox(height: 12),
      _secimAlani(
        ikon: _atanan == null ? Icons.groups_rounded : Icons.person_rounded,
        etiket: 'Kime',
        deger: _atananAd,
        hata: _hatalar['atanan_id'],
        onTap: _kisiSec,
      ),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('Öncelik', style: TextStyle(color: r.soluk, fontWeight: FontWeight.w500, fontSize: 13)),
      ),
      Row(children: [
        for (var i = 0; i < _oncelikler.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Basilir(
              onTap: () => setState(() => _oncelik = _oncelikler[i].$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: _oncelik == _oncelikler[i].$1 ? Marka.grad : null,
                  color: _oncelik == _oncelikler[i].$1 ? null : r.ic,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_oncelikler[i].$2,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: _oncelik == _oncelikler[i].$1 ? Colors.white : r.soluk)),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      _secimAlani(
        ikon: Icons.event_rounded,
        etiket: 'Bitiş',
        deger: _bitis == null ? 'İsteğe bağlı' : _fmt.format(_bitis!),
        bos: _bitis == null,
        hata: _hatalar['bitis'],
        onTap: _bitisSec,
        temizle: _bitis == null ? null : () => setState(() => _bitis = null),
      ),
      const SizedBox(height: 18),
      GradDugme(yazi: 'Görevi ver', ikon: Icons.send_rounded, yukleniyor: _gonder, onTap: _kaydet),
    ]);
  }

  /// İzin formundaki tarih alanıyla aynı biçim.
  Widget _secimAlani({required IconData ikon, required String etiket, required String deger, required VoidCallback onTap, String? hata, bool bos = false, VoidCallback? temizle}) {
    final r = context.pa;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Basilir(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(16), border: hata != null ? Border.all(color: Marka.gul) : null),
          child: Row(children: [
            Icon(ikon, color: r.birincil, size: 20),
            const SizedBox(width: 10),
            Text(etiket, style: TextStyle(color: r.soluk, fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(deger,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: bos ? FontWeight.w500 : FontWeight.w700, color: bos ? r.silik : r.metin)),
            ),
            const SizedBox(width: 4),
            if (temizle != null)
              GestureDetector(onTap: temizle, child: Icon(Icons.close_rounded, color: r.silik, size: 20))
            else
              Icon(Icons.chevron_right_rounded, color: r.silik),
          ]),
        ),
      ),
      if (hata != null) Padding(padding: const EdgeInsets.only(left: 14, top: 4), child: Text(hata, style: const TextStyle(color: Marka.gul, fontSize: 12))),
    ]);
  }
}
