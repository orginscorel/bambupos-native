import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/canli.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/form.dart';
import '../ortak/ortak.dart';
import '../ortak/ust_serit.dart';

/// Vardiya dönemi rengi (sabah gök · öğle mavi · akşam mor · gece lacivert).
Color vardiyaRengi(DateTime bas) {
  final h = bas.hour;
  if (h >= 5 && h < 11) return Marka.gok;
  if (h >= 11 && h < 15) return Marka.mavi;
  if (h >= 15 && h < 22) return Marka.mor;
  return Marka.gece3;
}

String vardiyaDonemi(DateTime bas) {
  final h = bas.hour;
  if (h >= 5 && h < 11) return 'Sabah';
  if (h >= 11 && h < 15) return 'Öğle';
  if (h >= 15 && h < 22) return 'Akşam';
  return 'Gece';
}

/// Sunucudaki vardiya (schedule `shifts` öğesi) — saatler yerel.
class Vardiya {
  Vardiya(this.ham)
      : id = ham.i('id'),
        kisi = ham.i('user_id'),
        bas = DateTime.parse(ham.s('starts_at')).toLocal(),
        son = DateTime.parse(ham.s('ends_at')).toLocal();
  final Map<String, dynamic> ham;
  final int id;
  final int kisi;
  final DateTime bas;
  final DateTime son;
  String get ad => ham.m('user').s('name');
  String get pozisyon => ham.s('position', ham.m('user').s('position'));
  int get mola => ham.i('break_min');
  bool get seri => ham.s('repeat_group').isNotEmpty;
  int get netDk => son.difference(bas).inMinutes - mola;
  bool gunde(DateTime g) => bas.year == g.year && bas.month == g.month && bas.day == g.day;
}

/// VARDİYA PLANI: haftalık takvim (kişi × gün) + seçili günün listesi.
/// Uçlar: GET /api/v1/shifts/meta · GET /api/v1/shifts/schedule ·
/// POST /api/v1/shifts/shifts · PUT/DELETE /api/v1/shifts/shifts/{id}.
/// Yazma staff.manage ister (meta.can.manage); yoksa yalnız görüntüleme.
class VardiyaEkrani extends StatefulWidget {
  const VardiyaEkrani({super.key, this.gun});
  final DateTime? gun;
  @override
  State<VardiyaEkrani> createState() => _VardiyaEkraniState();
}

class _VardiyaEkraniState extends State<VardiyaEkrani> {
  late DateTime _secili = _gun(widget.gun ?? DateTime.now());
  late DateTime _hafta = haftaBasi(_secili);
  List<Vardiya>? _vardiyalar;
  List<Map<String, dynamic>> _izinler = const [];
  List<Map<String, dynamic>> _uyarilar = const [];
  ApiHata? _hata;
  bool _yukleniyor = false;
  bool _tumPersonel = false;
  int _istek = 0;

  static DateTime _gun(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    if (Canli.meta.value == null) Canli.metaTazele().then((_) => mounted ? setState(() {}) : null);
    _yukle();
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      // UTC gün sınırı kaymasın diye bir gün öncesi/sonrasıyla iste, yerelde süz.
      final r = await Uyg.api.get('/api/v1/shifts/schedule', sorgu: {
        'from': gunIso(_hafta.subtract(const Duration(days: 1))),
        'to': gunIso(_hafta.add(const Duration(days: 8))),
      });
      if (!mounted || no != _istek) return;
      final m = r is Map ? r : const {};
      setState(() {
        _vardiyalar = [for (final s in m.l('shifts')) if (DateTime.tryParse(s.s('starts_at')) != null) Vardiya(s)];
        _izinler = m.l('leaves');
        _uyarilar = m.l('warnings');
        _yukleniyor = false;
      });
    } on ApiHata catch (e) {
      if (!mounted || no != _istek) return;
      setState(() {
        _hata = e;
        _yukleniyor = false;
      });
    }
  }

  void _haftaKaydir(int h) {
    setState(() {
      _hafta = _hafta.add(Duration(days: 7 * h));
      _secili = _hafta.add(Duration(days: (_secili.weekday - 1)));
    });
    _yukle();
  }

  bool get _yonetir => Canli.meta.value?.m('can').b('manage') ?? false;

  Future<void> _ekle({int? kisi, DateTime? gun}) async {
    if (!_yonetir) {
      bildir('Yetkiniz yok', mesaj: 'Vardiya planlamak için "Personel yönet" yetkisi gerekir.', tur: BildirimTur.uyari);
      return;
    }
    final ok = await vardiyaFormuAc(context, kisi: kisi, gun: gun ?? _secili);
    if (ok == true) _yukle();
  }

  Future<void> _duzenle(Vardiya v) async {
    if (!_yonetir) return;
    final ok = await vardiyaFormuAc(context, vardiya: v);
    if (ok == true) _yukle();
  }

  List<Map<String, dynamic>> _kisiler(List<Vardiya> hafta) {
    final ids = hafta.map((v) => v.kisi).toSet();
    final meta = Canli.personel;
    final out = <Map<String, dynamic>>[
      for (final p in meta)
        if (_tumPersonel || ids.contains(p.i('id'))) p,
    ];
    // Meta'da olmayan (ör. pasif) ama vardiyası olanlar.
    for (final v in hafta) {
      if (!out.any((p) => p.i('id') == v.kisi)) out.add({'id': v.kisi, 'name': v.ad, 'position': v.pozisyon});
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final gunler = [for (var i = 0; i < 7; i++) _hafta.add(Duration(days: i))];
    final hafta = (_vardiyalar ?? const <Vardiya>[]).where((v) => !v.bas.isBefore(_hafta) && v.bas.isBefore(_hafta.add(const Duration(days: 7)))).toList();
    final gunVardiya = hafta.where((v) => v.gunde(_secili)).toList()..sort((a, b) => a.bas.compareTo(b.bas));
    final toplamDk = hafta.fold<int>(0, (a, v) => a + v.netDk);
    return Scaffold(
      floatingActionButton: _yonetir && _vardiyalar != null ? EylemDugmesi(ikon: Icons.more_time_rounded, yazi: 'Vardiya ekle', onTap: () => _ekle()) : null,
      body: PaSayfa(
        baslik: 'Vardiya planı',
        alt: '${Bicim.aralik(gunler.first, gunler.last)} · ${hafta.length} vardiya · ${Bicim.dakika(toplamDk)}',
        geri: true,
        yenile: _yukle,
        altBosluk: 100,
        sag: AnimatedOpacity(
          opacity: _yukleniyor ? 1 : 0,
          duration: Hareket.orta,
          child: const Padding(padding: EdgeInsets.all(10), child: Yukleyici(boyut: 18)),
        ),
        children: [
          _haftaSecici(gunler, hafta),
          const SizedBox(height: 12),
          if (_vardiyalar == null && _hata != null)
            PaKart(child: _hata!.kod == 404
                ? const BosDurum(baslik: 'Vardiya eklentisi kapalı', mesaj: 'Vardiya / Mesai eklentisi işletmenizde açık değil.', ikon: Icons.extension_off_rounded)
                : HataDurum(hata: _hata!, yenile: _yukle))
          else if (_vardiyalar == null) ...[
            const Iskelet(yukseklik: 220),
            const SizedBox(height: 12),
            const Iskelet(yukseklik: 140),
          ] else ...[
            if (_uyarilar.isNotEmpty) ...[
              Belirme(sira: 0, child: _uyariKarti()),
              const SizedBox(height: 12),
            ],
            Belirme(sira: 1, child: _gunKarti(gunVardiya)),
            const SizedBox(height: 12),
            Belirme(sira: 2, child: _matris(gunler, hafta)),
            const SizedBox(height: 12),
            BilgiNotu(_yonetir
                ? 'Eklediğiniz, değiştirdiğiniz ya da sildiğiniz vardiya personelin telefonuna sesli bildirimle gider.'
                : 'Vardiyaları görebilirsiniz; planlamak için "Personel yönet" yetkisi gerekir.'),
            const SizedBox(height: 8),
            Text('Renkler: sabah · öğle · akşam · gece', textAlign: TextAlign.center, style: TextStyle(color: r.silik, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }

  Widget _haftaSecici(List<DateTime> gunler, List<Vardiya> hafta) {
    final r = context.pa;
    final bugun = _gun(DateTime.now());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton.outlined(
          tooltip: 'Önceki hafta',
          style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), side: BorderSide(color: r.kenar)),
          onPressed: () => _haftaKaydir(-1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Column(children: [
            Text(_hafta == haftaBasi(bugun) ? 'Bu hafta' : _hafta.isAfter(bugun) ? 'İleri hafta' : 'Geçmiş hafta',
                style: TextStyle(color: r.silik, fontSize: 11.5, fontWeight: FontWeight.w600)),
            Text(Bicim.aralik(gunler.first, gunler.last), style: TextStyle(color: r.metin, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (_hafta != haftaBasi(bugun))
          TextButton(
            onPressed: () {
              setState(() {
                _secili = bugun;
                _hafta = haftaBasi(bugun);
              });
              _yukle();
            },
            child: const Text('Bugün'),
          ),
        IconButton.outlined(
          tooltip: 'Sonraki hafta',
          style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), side: BorderSide(color: r.kenar)),
          onPressed: () => _haftaKaydir(1),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: _gunKutusu(gunler[i], hafta.where((v) => v.gunde(gunler[i])).length, gunler[i] == bugun)),
        ],
      ]),
    ]);
  }

  Widget _gunKutusu(DateTime g, int adet, bool bugun) {
    final r = context.pa;
    final secili = g == _secili;
    final izinli = _izinler.where((l) {
      final a = Bicim.gunCoz(l.s('starts_on')), b = Bicim.gunCoz(l.s('ends_on'));
      return a != null && b != null && !g.isBefore(a) && !g.isAfter(b);
    }).length;
    return Semantics(
      selected: secili,
      button: true,
      label: '${Bicim.gunAdi(g)} ${g.day}, $adet vardiya${izinli > 0 ? ', $izinli izinli' : ''}',
      excludeSemantics: true,
      child: Basilir(
        onTap: () => setState(() => _secili = g),
        titresim: true,
        child: AnimatedContainer(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
          height: 72,
          decoration: BoxDecoration(
            gradient: secili ? Marka.grad : null,
            color: secili ? null : r.kart,
            borderRadius: Marka.yaricap,
            border: Border.all(color: secili ? Colors.transparent : bugun ? r.birincil : r.kenar, width: bugun && !secili ? 1.5 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(Bicim.gunKisa[g.weekday - 1], style: TextStyle(color: secili ? Colors.white70 : r.silik, fontSize: 11, fontWeight: FontWeight.w600)),
            Text('${g.day}', style: gosterim(18, renk: secili ? Colors.white : r.metin)),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < adet.clamp(0, 4); k++)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(color: secili ? Colors.white : r.birincil, borderRadius: BorderRadius.circular(1.5)),
                ),
              if (adet == 0) Text('—', style: TextStyle(color: secili ? Colors.white54 : r.silik, fontSize: 9, height: .8)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _uyariKarti() {
    final r = context.pa;
    return PaKart(
      renk: r.uyari.withValues(alpha: r.koyu ? .14 : .07),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, color: r.uyari),
          const SizedBox(width: 8),
          Text('Eksik personel', style: TextStyle(color: r.metin, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        for (final w in _uyarilar.take(5))
          Builder(builder: (_) {
            final g = Bicim.gunCoz(w.s('date'));
            return Text(
              '• ${g == null ? w.s('date') : '${Bicim.gunKisa[g.weekday - 1]} ${Bicim.gunAyKisa(g)}'}'
              '${w.s('position').isEmpty ? '' : ' · ${w.s('position')}'}: ${w.i('planned')}/${w.i('required')} kişi planlı',
              style: TextStyle(color: r.soluk, fontSize: 12.5, height: 1.5),
            );
          }),
      ]),
    );
  }

  Widget _gunKarti(List<Vardiya> liste) {
    final r = context.pa;
    final simdi = DateTime.now();
    final izinli = _izinler.where((l) {
      final a = Bicim.gunCoz(l.s('starts_on')), b = Bicim.gunCoz(l.s('ends_on'));
      return a != null && b != null && !_secili.isBefore(a) && !_secili.isAfter(b);
    }).toList();
    final planliIds = liste.map((v) => v.kisi).toSet();
    final bos = Canli.personel.where((p) => !planliIds.contains(p.i('id'))).toList();
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('${Bicim.gunAdi(_secili)}, ${Bicim.gunAy(_secili)}',
            ikon: Icons.today_rounded,
            alt: liste.isEmpty ? 'Planlı vardiya yok' : '${liste.length} vardiya · ${planliIds.length} kişi',
            sag: _yonetir ? IconButton(tooltip: 'Bu güne vardiya ekle', onPressed: () => _ekle(gun: _secili), icon: Icon(Icons.add_box_rounded, color: r.birincil)) : null),
        if (liste.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Icon(Icons.event_busy_rounded, size: 34, color: r.silik),
              const SizedBox(height: 6),
              Text('Bu gün için vardiya planlanmamış.', style: TextStyle(color: r.silik)),
              if (_yonetir) ...[
                const SizedBox(height: 8),
                YumusakDugme(onTap: () => _ekle(gun: _secili), ikon: Icons.add_rounded, yazi: 'Vardiya planla'),
              ],
            ]),
          ),
        for (final v in liste)
          Builder(builder: (_) {
            final suruyor = v.bas.isBefore(simdi) && v.son.isAfter(simdi);
            final bitti = v.son.isBefore(simdi);
            final c = vardiyaRengi(v.bas);
            return Semantics(
              container: true,
              label: '${v.ad}, ${Bicim.saat(v.bas)} ile ${Bicim.saat(v.son)} arası${suruyor ? ', sürüyor' : ''}',
              child: Basilir(
                onTap: _yonetir ? () => _duzenle(v) : null,
                olcek: .985,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                  decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap, border: Border.all(color: c.withValues(alpha: .35))),
                  child: Row(children: [
                    Container(width: 4, height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Avatar(v.ad, boyut: 36, nokta: suruyor ? r.arti : null),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(v.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(
                          [vardiyaDonemi(v.bas), if (v.pozisyon.isNotEmpty) v.pozisyon, if (v.mola > 0) '${v.mola} dk mola', if (v.seri) 'Tekrarlı'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: r.silik, fontSize: 12),
                        ),
                        if (v.ham.s('note').isNotEmpty)
                          Text(v.ham.s('note'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12, fontStyle: FontStyle.italic)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${Bicim.saat(v.bas)}–${Bicim.saat(v.son)}', style: gosterim(14.5, renk: r.metin, agirlik: FontWeight.w700)),
                      Text(suruyor ? 'Sürüyor' : bitti ? 'Bitti' : Bicim.dakika(v.netDk),
                          style: TextStyle(color: suruyor ? r.arti : r.silik, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ]),
                    if (_yonetir) Icon(Icons.chevron_right_rounded, color: r.silik),
                  ]),
                ),
              ),
            );
          }),
        if (izinli.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final l in izinli)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: r.uyari.withValues(alpha: .12), borderRadius: BorderRadius.circular(5)),
                child: Text('${l.m('user').s('name')} · izinli', style: TextStyle(color: r.uyari, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
        ],
        if (_yonetir && bos.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Hızlı ekle', style: TextStyle(color: r.silik, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in bos)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: Icon(Icons.add_rounded, size: 16, color: r.birincil),
                    label: Text(p.s('name').split(' ').first),
                    onPressed: () => _ekle(kisi: p.i('id'), gun: _secili),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _matris(List<DateTime> gunler, List<Vardiya> hafta) {
    final r = context.pa;
    final kisiler = _kisiler(hafta);
    final bugun = _gun(DateTime.now());
    return PaKart(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('Haftalık görünüm',
            ikon: Icons.view_week_rounded,
            alt: 'Kişi × gün · hücreye dokunun',
            sag: TextButton(onPressed: () => setState(() => _tumPersonel = !_tumPersonel), child: Text(_tumPersonel ? 'Planlılar' : 'Tümü'))),
        if (kisiler.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('Bu hafta kimseye vardiya planlanmamış.', textAlign: TextAlign.center, style: TextStyle(color: r.silik)),
          )
        else
          LayoutBuilder(builder: (_, k) {
            const adW = 78.0;
            final hw = (k.maxWidth - adW) / 7;
            return Column(children: [
              Row(children: [
                const SizedBox(width: adW),
                for (final g in gunler)
                  SizedBox(
                    width: hw,
                    child: Text(Bicim.gunKisa[g.weekday - 1],
                        textAlign: TextAlign.center,
                        style: TextStyle(color: g == _secili ? r.birincil : r.silik, fontSize: 11, fontWeight: g == bugun ? FontWeight.w800 : FontWeight.w600)),
                  ),
              ]),
              const SizedBox(height: 4),
              for (final p in kisiler)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(
                      width: adW,
                      child: Text(p.s('name').split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    for (final g in gunler)
                      SizedBox(
                        width: hw,
                        height: 34,
                        child: Padding(padding: const EdgeInsets.all(1.5), child: _hucre(p, g, hafta.where((v) => v.kisi == p.i('id') && v.gunde(g)).toList())),
                      ),
                  ]),
                ),
            ]);
          }),
      ]),
    );
  }

  Widget _hucre(Map<String, dynamic> p, DateTime g, List<Vardiya> vs) {
    final r = context.pa;
    if (vs.isEmpty) {
      return Basilir(
        onTap: _yonetir ? () => _ekle(kisi: p.i('id'), gun: g) : () => setState(() => _secili = g),
        etiket: '${p.s('name')}, ${Bicim.gunAdi(g)}: boş${_yonetir ? '. Vardiya ekle' : ''}',
        child: Container(
          decoration: BoxDecoration(color: g == _secili ? r.birincilYumusak : r.ic.withValues(alpha: .6), borderRadius: BorderRadius.circular(4)),
          child: _yonetir ? Icon(Icons.add_rounded, size: 14, color: r.silik.withValues(alpha: .5)) : null,
        ),
      );
    }
    final v = vs.first;
    final c = vardiyaRengi(v.bas);
    return Basilir(
      onTap: _yonetir ? () => _duzenle(v) : () => setState(() => _secili = g),
      etiket: '${v.ad}, ${Bicim.gunAdi(g)} ${Bicim.saat(v.bas)}–${Bicim.saat(v.son)}',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('${v.bas.hour.toString().padLeft(2, '0')}${vs.length > 1 ? '+' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ),
      ),
    );
  }
}

/* ───────────────────────── Vardiya formu ───────────────────────── */

/// Vardiya ekle/düzenle alt sayfası. true dönerse kayıt değişti.
Future<bool?> vardiyaFormuAc(BuildContext context, {Vardiya? vardiya, int? kisi, DateTime? gun}) async {
  if (Canli.meta.value == null) await Canli.metaTazele();
  if (!context.mounted) return null;
  return altSayfaAc<bool>(context, (_) => _VardiyaFormu(vardiya: vardiya, kisi: kisi, gun: gun));
}

class _Sablon {
  const _Sablon(this.ad, this.bas, this.son, this.ikon);
  final String ad;
  final TimeOfDay bas;
  final TimeOfDay son;
  final IconData ikon;
}

const _sablonlar = [
  _Sablon('Sabah', TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 16, minute: 0), Icons.wb_twilight_rounded),
  _Sablon('Tam gün', TimeOfDay(hour: 9, minute: 0), TimeOfDay(hour: 18, minute: 0), Icons.wb_sunny_rounded),
  _Sablon('Öğle', TimeOfDay(hour: 12, minute: 0), TimeOfDay(hour: 20, minute: 0), Icons.light_mode_rounded),
  _Sablon('Akşam', TimeOfDay(hour: 16, minute: 0), TimeOfDay(hour: 0, minute: 0), Icons.nights_stay_rounded),
  _Sablon('Gece', TimeOfDay(hour: 0, minute: 0), TimeOfDay(hour: 8, minute: 0), Icons.bedtime_rounded),
];

class _VardiyaFormu extends StatefulWidget {
  const _VardiyaFormu({this.vardiya, this.kisi, this.gun});
  final Vardiya? vardiya;
  final int? kisi;
  final DateTime? gun;
  @override
  State<_VardiyaFormu> createState() => _VardiyaFormuState();
}

class _VardiyaFormuState extends State<_VardiyaFormu> {
  late int? _kisi = widget.vardiya?.kisi ?? widget.kisi;
  late DateTime _gun = () {
    final d = widget.vardiya?.bas ?? widget.gun ?? DateTime.now();
    return DateTime(d.year, d.month, d.day);
  }();
  late TimeOfDay _bas = widget.vardiya == null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay.fromDateTime(widget.vardiya!.bas);
  late TimeOfDay _son = widget.vardiya == null ? const TimeOfDay(hour: 17, minute: 0) : TimeOfDay.fromDateTime(widget.vardiya!.son);
  late int _mola = widget.vardiya?.mola ?? (Canli.meta.value?.i('default_break_min') ?? 0);
  late final _not = TextEditingController(text: widget.vardiya?.ham.s('note') ?? '');
  int _tekrar = 0;
  bool _mesgul = false;
  String? _hata;

  bool get _duzenle => widget.vardiya != null;

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  (DateTime, DateTime) get _aralik {
    final a = DateTime(_gun.year, _gun.month, _gun.day, _bas.hour, _bas.minute);
    var b = DateTime(_gun.year, _gun.month, _gun.day, _son.hour, _son.minute);
    // Gece devri: bitiş ≤ başlangıç → ertesi gün.
    if (!b.isAfter(a)) b = b.add(const Duration(days: 1));
    return (a, b);
  }

  String get _kisiAdi {
    for (final p in Canli.personel) {
      if (p.i('id') == _kisi) return p.s('name');
    }
    return widget.vardiya?.ad ?? '';
  }

  Future<void> _kaydet({bool cakismaKabul = false}) async {
    if (_kisi == null) {
      setState(() => _hata = 'Vardiyayı kime vereceğinizi seçin.');
      return;
    }
    final (a, b) = _aralik;
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final govde = <String, dynamic>{
      'branch_id': 0, // sunucu geçerli şubeyi zorlar
      'user_id': _kisi,
      'starts_at': utcIso(a),
      'ends_at': utcIso(b),
      'break_min': _mola,
      'note': _not.text.trim().isEmpty ? null : _not.text.trim(),
      if (cakismaKabul) 'allow_overlap': true,
      if (!_duzenle && _tekrar > 0) 'repeat_weeks': _tekrar,
    };
    try {
      final r = _duzenle ? await Uyg.api.put('/api/v1/shifts/shifts/${widget.vardiya!.id}', govde) : await Uyg.api.post('/api/v1/shifts/shifts', govde);
      final atlanan = r is Map && r['skipped'] is List ? (r['skipped'] as List).length : 0;
      HapticFeedback.mediumImpact();
      bildir(_duzenle ? 'Vardiya güncellendi' : 'Vardiya planlandı',
          mesaj: '$_kisiAdi · ${Bicim.gunAyKisa(a)} ${Bicim.saat(a)}–${Bicim.saat(b)} · personele bildirim gitti'
              '${atlanan > 0 ? ' · $atlanan hafta atlandı (izin/çakışma)' : ''}');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() => _mesgul = false);
      if (e.kod == 422 && e.mesaj.contains('başka vardiyası') && !cakismaKabul) {
        final ok = await onayIste(context, baslik: 'Çakışan vardiya var', mesaj: '$_kisiAdi bu saatlerde başka bir vardiyada. Yine de eklensin mi?', evet: 'Yine de ekle');
        if (ok) return _kaydet(cakismaKabul: true);
        return;
      }
      if (e.yetkiYok) Canli.vardiyaYetki.value = Yetki.yok;
      setState(() => _hata = e.yetkiYok ? 'Vardiya planlama yetkiniz yok ("Personel yönet").' : e.mesaj);
    }
  }

  Future<void> _sil() async {
    final v = widget.vardiya!;
    var seri = false;
    if (v.seri) {
      final s = await pencereAc<String>(
        context: context,
        builder: (ctx) => SimpleDialog(title: const Text('Tekrarlı vardiya'), children: [
          SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('tek'), child: const Padding(padding: EdgeInsets.all(6), child: Text('Yalnız bu vardiyayı sil'))),
          SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop('seri'), child: const Padding(padding: EdgeInsets.all(6), child: Text('Bu ve sonraki tekrarları sil'))),
          SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(), child: const Padding(padding: EdgeInsets.all(6), child: Text('Vazgeç'))),
        ]),
      );
      if (s == null) return;
      seri = s == 'seri';
    } else {
      if (!mounted) return;
      final ok = await onayIste(context, baslik: 'Vardiya silinsin mi?', mesaj: '${v.ad} · ${Bicim.gunAyKisa(v.bas)} ${Bicim.saat(v.bas)}–${Bicim.saat(v.son)}. Personele iptal bildirimi gider.', evet: 'Sil', tehlikeli: true);
      if (!ok) return;
    }
    setState(() => _mesgul = true);
    try {
      await Uyg.api.sil('/api/v1/shifts/shifts/${v.id}', sorgu: seri ? const {'with_series': 1} : null);
      bildir('Vardiya silindi', mesaj: '${v.ad} · personele iptal bildirimi gitti');
      if (mounted) Navigator.of(context).pop(true);
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _mesgul = false;
        _hata = e.yetkiYok ? 'Vardiya silme yetkiniz yok.' : e.mesaj;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final (a, b) = _aralik;
    final brut = b.difference(a).inMinutes;
    final gece = b.day != a.day;
    final kisiler = Canli.personel;
    return AltSayfa(
      baslik: _duzenle ? 'Vardiyayı düzenle' : 'Vardiya planla',
      alt: _kisi == null ? 'Kişi, gün ve saat seçin' : '$_kisiAdi · ${Bicim.gunAdi(_gun)} ${Bicim.gunAy(_gun)}',
      ikon: Icons.more_time_rounded,
      dugmeler: Row(children: [
        if (_duzenle) ...[
          IconButton.outlined(
            tooltip: 'Sil',
            style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), minimumSize: const Size(50, 50), foregroundColor: r.eksi),
            onPressed: _mesgul ? null : _sil,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: KaydetDugmesi(yazi: _duzenle ? 'Kaydet' : 'Planla ve bildir', ikon: Icons.send_rounded, mesgul: _mesgul, onPressed: _kaydet)),
      ]),
      children: [
        if (!_duzenle || kisiler.isNotEmpty) ...[
          const AlanBasligi('KİŞİ'),
          if (kisiler.isEmpty)
            Text('Personel listesi alınamadı.', style: TextStyle(color: r.silik))
          else
            SizedBox(
              height: 78,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in kisiler)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Semantics(
                      selected: _kisi == p.i('id'),
                      child: Basilir(
                        onTap: () => setState(() => _kisi = p.i('id')),
                        etiket: p.s('name'),
                        child: AnimatedContainer(
                          duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
                          width: 70,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _kisi == p.i('id') ? r.birincilYumusak : Colors.transparent,
                            borderRadius: Marka.yaricap,
                            border: Border.all(color: _kisi == p.i('id') ? r.birincil : Colors.transparent, width: 1.5),
                          ),
                          child: Column(children: [
                            Avatar(p.s('name'), boyut: 38),
                            const SizedBox(height: 4),
                            Text(p.s('name').split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
        ],
        AlanBasligi('GÜN', sag: TextButton.icon(
          onPressed: () async {
            final g = await gunSec(context, _gun, ilkGun: DateTime.now().subtract(const Duration(days: 60)));
            if (g != null) setState(() => _gun = g);
          },
          icon: const Icon(Icons.edit_calendar_rounded, size: 18),
          label: Text('${Bicim.gunKisa[_gun.weekday - 1]} ${Bicim.gunAyKisa(_gun)}'),
        )),
        SizedBox(
          height: 46,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < 14; i++)
              Builder(builder: (_) {
                final n = DateTime.now();
                final g = DateTime(n.year, n.month, n.day + i);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SecimCipi(
                    yazi: i == 0 ? 'Bugün' : i == 1 ? 'Yarın' : '${Bicim.gunKisa[g.weekday - 1]} ${g.day}',
                    secili: g == _gun,
                    onTap: () => setState(() => _gun = g),
                  ),
                );
              }),
          ]),
        ),
        const AlanBasligi('HIZLI ŞABLON'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in _sablonlar)
            SecimCipi(
              yazi: s.ad,
              alt: '${saatYaz(s.bas)}–${saatYaz(s.son)}',
              ikon: s.ikon,
              secili: _bas == s.bas && _son == s.son,
              onTap: () => setState(() {
                _bas = s.bas;
                _son = s.son;
              }),
            ),
        ]),
        const AlanBasligi('SAAT'),
        Row(children: [
          Expanded(
            child: SaatKutusu(ad: 'Başlangıç', saat: _bas, onTap: () async {
              final t = await saatSec(context, _bas, baslik: 'Başlangıç');
              if (t != null) setState(() => _bas = t);
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SaatKutusu(ad: 'Bitiş', saat: _son, not: gece ? '+1 gün' : null, onTap: () async {
              final t = await saatSec(context, _son, baslik: 'Bitiş');
              if (t != null) setState(() => _son = t);
            }),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Süre ${Bicim.dakika(brut)}${_mola > 0 ? ' · net ${Bicim.dakika(brut - _mola)}' : ''}${brut > 24 * 60 ? ' · en çok 24 saat olabilir' : ''}',
          style: TextStyle(color: brut > 24 * 60 ? r.eksi : r.silik, fontSize: 12.5),
        ),
        const AlanBasligi('MOLA'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in const [0, 15, 30, 45, 60])
            SecimCipi(yazi: m == 0 ? 'Molasız' : '$m dk', secili: _mola == m, onTap: () => setState(() => _mola = m)),
        ]),
        if (!_duzenle) ...[
          const AlanBasligi('TEKRAR'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (t, ad) in const [(0, 'Tek sefer'), (1, '2 hafta'), (3, '4 hafta'), (7, '8 hafta')])
              SecimCipi(yazi: ad, alt: t == 0 ? null : 'her ${Bicim.gunKisa[_gun.weekday - 1]}', secili: _tekrar == t, onTap: () => setState(() => _tekrar = t)),
          ]),
        ],
        const AlanBasligi('NOT'),
        TextField(controller: _not, maxLength: 255, decoration: const InputDecoration(hintText: 'Örn. Teras açılışı, kasa sorumlusu')),
        const SizedBox(height: 4),
        const BilgiNotu('Kaydedince personelin telefonuna sesli "yeni vardiya" bildirimi gider.'),
        if (_hata != null) ...[
          const SizedBox(height: 10),
          BilgiNotu(_hata!, ikon: Icons.error_outline_rounded, renk: r.eksi),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
