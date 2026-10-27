import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// EKİP: şu an mesaide olanlar + bugün başlayacaklar (overview), bugünün
/// vardiya planı (/api/v1/shifts/schedule) ve görevler (/api/v1/tasks).
/// Bölümler birbirinden bağımsız yüklenir; yetki/eklenti yoksa o bölüm
/// açıklamayla gizlenir.
class EkipEkrani extends StatefulWidget {
  const EkipEkrani({super.key});
  @override
  State<EkipEkrani> createState() => _EkipEkraniState();
}

class _Bolum<T> {
  T? veri;
  ApiHata? hata;
  bool get yuklendi => veri != null || hata != null;
}

class _EkipEkraniState extends State<EkipEkrani> {
  final _mesai = _Bolum<Map<String, dynamic>>();
  final _vardiya = _Bolum<List<Map<String, dynamic>>>();
  final _gorev = _Bolum<List<Map<String, dynamic>>>();
  int _gorevSekme = 0; // 0 açık · 1 tamamlanan

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final gun = Bicim.iso(Uyg.isGunu);
    final n = DateTime.now();
    final takvim = Bicim.iso(DateTime(n.year, n.month, n.day));
    await Future.wait([
      _al(_mesai, () async => ((await Uyg.api.get('/api/v1/boss/overview', sorgu: const {'period': 'day'})) as Map).m('data')),
      _al(_vardiya, () async {
        final r = await Uyg.api.get('/api/v1/shifts/schedule', sorgu: {'from': gun.compareTo(takvim) < 0 ? gun : takvim, 'to': takvim});
        return (r as Map).l('shifts');
      }),
      _al(_gorev, () async => ((await Uyg.api.get('/api/v1/tasks')) as Map).l('tasks')),
    ]);
  }

  Future<void> _al<T>(_Bolum<T> b, Future<T> Function() f) async {
    try {
      final v = await f();
      if (!mounted) return;
      setState(() {
        b.veri = v;
        b.hata = null;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() => b.hata = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PaSayfa(
      baslik: 'Ekip',
      alt: 'Mesai, vardiya ve görevler',
      yenile: _yukle,
      children: [
        Belirme(sira: 0, child: _mesaiKarti()),
        const SizedBox(height: 14),
        Belirme(sira: 1, child: _vardiyaKarti()),
        const SizedBox(height: 14),
        Belirme(sira: 2, child: _gorevKarti()),
      ],
    );
  }

  Widget _bekle(_Bolum b, String baslik, IconData ikon) => PaKart(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BolumBasligi(baslik, ikon: ikon),
          if (b.hata != null)
            Text(_hataMetni(b.hata!), style: TextStyle(color: context.pa.silik))
          else
            const Iskelet(yukseklik: 60),
        ]),
      );

  String _hataMetni(ApiHata h) => h.yetkiYok
      ? 'Bu bölümü görme yetkiniz yok.'
      : h.kod == 404
          ? 'Bu özellik işletmenizde açık değil.'
          : h.mesaj;

  Widget _kisi(String ad, String? alt, {Widget? sag, Color? nokta}) {
    final r = context.pa;
    final harf = ad.trim().isEmpty ? '•' : ad.trim().split(RegExp(r'\s+')).take(2).map((e) => e.characters.first.toUpperCase()).join();
    return Semantics(
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: Marka.grad, borderRadius: Marka.yaricap),
              child: Text(harf, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            if (nokta != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(width: 12, height: 12, decoration: BoxDecoration(color: nokta, shape: BoxShape.circle, border: Border.all(color: r.kart, width: 2))),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ad, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 14)),
              if (alt != null && alt.isNotEmpty) Text(alt, style: TextStyle(color: r.silik, fontSize: 12.5)),
            ]),
          ),
          ?sag,
        ]),
      ),
    );
  }

  Widget _mesaiKarti() {
    final v = _mesai.veri;
    if (v == null) return _bekle(_mesai, 'Şu an mesaide', Icons.badge_rounded);
    final r = context.pa;
    final ms = v.l('on_shift');
    final sira = v.l('upcoming_today');
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('Şu an mesaide', ikon: Icons.badge_rounded, sag: Text('${ms.length} kişi', style: TextStyle(color: r.silik, fontWeight: FontWeight.w700))),
        if (ms.isEmpty) Text('Şu an mesaide kimse yok.', style: TextStyle(color: r.silik)),
        for (final p in ms)
          _kisi(
            p.s('name', '—'),
            [
              p.s('position'),
              if (DateTime.tryParse(p.s('since')) != null) 'Giriş ${Bicim.saat(DateTime.parse(p.s('since')))}',
            ].where((e) => e.isNotEmpty).join(' · '),
            nokta: r.arti,
            sag: Text(Bicim.dakika(p.i('worked_minutes')), style: TextStyle(color: r.metin, fontWeight: FontWeight.w700)),
          ),
        if (sira.isNotEmpty) ...[
          Divider(color: r.kenar, height: 22),
          Text('Bugün başlayacaklar', style: TextStyle(color: r.silik, fontWeight: FontWeight.w600, fontSize: 12.5)),
          for (final p in sira)
            _kisi(p.s('name', '—'), p.s('position'),
                sag: Text(DateTime.tryParse(p.s('start')) == null ? '' : Bicim.saat(DateTime.parse(p.s('start'))),
                    style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700))),
        ],
      ]),
    );
  }

  Widget _vardiyaKarti() {
    final v = _vardiya.veri;
    if (v == null) return _bekle(_vardiya, 'Bugünün vardiyaları', Icons.calendar_month_rounded);
    final r = context.pa;
    final simdi = DateTime.now();
    final gunBas = DateTime(simdi.year, simdi.month, simdi.day);
    final gunSon = gunBas.add(const Duration(days: 1));
    // Bugünle kesişen vardiyalar (dünden sarkan gece vardiyası dahil).
    final bugun = v.where((s) {
      final a = DateTime.tryParse(s.s('starts_at'))?.toLocal();
      if (a == null) return false;
      final b = DateTime.tryParse(s.s('ends_at'))?.toLocal() ?? a;
      return a.isBefore(gunSon) && !b.isBefore(gunBas);
    }).toList()
      ..sort((a, b) => a.s('starts_at').compareTo(b.s('starts_at')));
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('Bugünün vardiyaları', ikon: Icons.calendar_month_rounded, alt: Bicim.gunAy(simdi)),
        if (bugun.isEmpty) Text('Bugün için planlı vardiya yok.', style: TextStyle(color: r.silik)),
        for (final s in bugun)
          Builder(builder: (_) {
            final a = DateTime.parse(s.s('starts_at')).toLocal();
            final b = DateTime.tryParse(s.s('ends_at'))?.toLocal();
            final suruyor = a.isBefore(simdi) && (b?.isAfter(simdi) ?? false);
            final bitti = b != null && b.isBefore(simdi);
            return _kisi(
              s.m('user').s('name', '—'),
              [s.s('position', s.m('user').s('position')), if (s.s('note').isNotEmpty) s.s('note')].where((e) => e.isNotEmpty).join(' · '),
              nokta: suruyor ? r.arti : bitti ? r.silik : r.birincil,
              sag: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${Bicim.saat(a)}–${b == null ? '?' : Bicim.saat(b)}', style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13)),
                Text(suruyor ? 'Sürüyor' : bitti ? 'Bitti' : 'Planlı', style: TextStyle(color: suruyor ? r.arti : r.silik, fontSize: 11.5)),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _gorevKarti() {
    final v = _gorev.veri;
    if (v == null) return _bekle(_gorev, 'Görevler', Icons.checklist_rounded);
    final r = context.pa;
    final acik = v.where((t) => t.s('status') != 'done').toList();
    final biten = v.where((t) => t.s('status') == 'done').toList();
    final liste = _gorevSekme == 0 ? acik : biten;
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const BolumBasligi('Görevler', ikon: Icons.checklist_rounded),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), minimumSize: const Size(44, 44)),
          segments: [
            ButtonSegment(value: 0, label: Text('Açık (${acik.length})')),
            ButtonSegment(value: 1, label: Text('Tamamlanan (${biten.length})')),
          ],
          selected: {_gorevSekme},
          onSelectionChanged: (s) => setState(() => _gorevSekme = s.first),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
          transitionBuilder: asamaGecisi,
          child: Column(
            key: ValueKey(_gorevSekme),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (liste.isEmpty) BosDurum(baslik: _gorevSekme == 0 ? 'Açık görev yok' : 'Tamamlanan görev yok', ikon: Icons.task_alt_rounded),
              for (final t in liste.take(40)) _gorevSatiri(t, r),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _gorevSatiri(Map<String, dynamic> t, PaRenk r) {
    final due = DateTime.tryParse(t.s('due_at'))?.toLocal();
    final gecti = due != null && t.s('status') != 'done' && due.isBefore(DateTime.now());
    final (oncelik, oRenk) = switch (t.s('priority')) {
      'high' => ('Yüksek', r.eksi),
      'low' => ('Düşük', r.silik),
      _ => ('Normal', r.birincil),
    };
    final durum = switch (t.s('status')) {
      'in_progress' => 'Devam ediyor',
      'done' => 'Tamamlandı',
      _ => 'Açık',
    };
    return Semantics(
      container: true,
      label: '${t.s('title')}, $durum, öncelik $oncelik${due != null ? ', son tarih ${Bicim.tarihSaat(due)}' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              t.s('status') == 'done'
                  ? Icons.check_circle_rounded
                  : t.s('status') == 'in_progress'
                      ? Icons.timelapse_rounded
                      : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: t.s('status') == 'done' ? r.arti : oRenk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.s('title'), style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 14)),
              if (t.s('description').isNotEmpty)
                Text(t.s('description'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(
                [t.m('assigned_to').s('name', 'Atanmamış'), durum, if (t.s('priority') == 'high') 'Öncelik yüksek'].join(' · '),
                style: TextStyle(color: r.silik, fontSize: 12),
              ),
            ]),
          ),
          if (due != null)
            Text(gecti ? 'Gecikti\n${Bicim.tarihSaat(due)}' : Bicim.tarihSaat(due),
                textAlign: TextAlign.right, style: TextStyle(color: gecti ? r.eksi : r.silik, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
