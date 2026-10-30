import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/canli.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/dugme.dart';
import '../ortak/ortak.dart';
import '../ortak/ust_serit.dart';
import 'gorevler.dart';
import 'kabuk.dart';
import 'mesai.dart';
import 'vardiya.dart';

/// EKİP merkezi: canlı sayaçlar, hızlı bağlantılar (vardiya, mesai,
/// görevler, talepler), şu an mesaide olanlar (vardiya ilerlemesiyle),
/// bugünün vardiya zaman çizelgesi ve açık görevler.
/// Uçlar: overview (Canli.ozet), /api/v1/shifts/schedule (bugün),
/// /api/v1/tasks (Canli.gorevler), talepler (Canli.bekleyen*).
class EkipEkrani extends StatefulWidget {
  const EkipEkrani({super.key});
  @override
  State<EkipEkrani> createState() => _EkipEkraniState();
}

class _EkipEkraniState extends State<EkipEkrani> {
  List<Vardiya>? _bugun;
  ApiHata? _vardiyaHata;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final n = DateTime.now();
    final g = DateTime(n.year, n.month, n.day);
    await Future.wait([
      Canli.tazele(zorla: true),
      () async {
        try {
          final r = await Uyg.api.get('/api/v1/shifts/schedule', sorgu: {'from': gunIso(g.subtract(const Duration(days: 1))), 'to': gunIso(g.add(const Duration(days: 1)))});
          final l = [for (final s in (r is Map ? r.l('shifts') : const <Map<String, dynamic>>[])) if (DateTime.tryParse(s.s('starts_at')) != null) Vardiya(s)];
          final son = g.add(const Duration(days: 1));
          if (mounted) {
            setState(() {
              _bugun = l.where((v) => v.bas.isBefore(son) && v.son.isAfter(g)).toList()..sort((a, b) => a.bas.compareTo(b.bas));
              _vardiyaHata = null;
            });
          }
        } on ApiHata catch (e) {
          if (mounted) setState(() => _vardiyaHata = e);
        }
      }(),
    ]);
  }

  void _ac(Widget s) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => s)).then((_) => _yukle());

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Canli.ozet, Canli.gorevler, Canli.bekleyenIzin, Canli.bekleyenTakas]),
      builder: (context, _) {
        final v = Canli.ozet.value;
        final ms = v?.l('on_shift') ?? const <Map<String, dynamic>>[];
        final bekleyen = Canli.bekleyenIzin.value + Canli.bekleyenTakas.value;
        final gorev = Canli.gorevler.value;
        final acikGorev = (gorev ?? const []).where((t) => t.s('status') != 'done').length;
        var sira = 0;
        Widget b(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Belirme(sira: sira++, child: w));
        return PaSayfa(
          baslik: 'Ekip',
          alt: '${ms.length} kişi mesaide · ${_bugun?.length ?? '–'} vardiya bugün',
          yenile: _yukle,
          altBosluk: 90,
          sag: UstEylemler(profil: () => Kabuk.sekme.value = 3),
          children: [
            b(_sayaclar(ms.length, _bugun?.length, bekleyen, Canli.gecikenGorev)),
            b(_baglantilar(bekleyen, acikGorev)),
            b(_mesaideKarti(v, ms)),
            b(_zamanCizelgesi()),
            b(_gorevKarti(gorev)),
          ],
        );
      },
    );
  }

  Widget _sayaclar(int mesaide, int? vardiya, int bekleyen, int geciken) {
    final r = context.pa;
    Widget kutu(String ad, int? n, IconData ikon, Color c, {VoidCallback? onTap, String? alt}) => Expanded(
          child: Basilir(
            onTap: onTap,
            etiket: '$ad: ${n ?? 'yükleniyor'}',
            child: Container(
              height: 92,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: r.kart,
                borderRadius: Marka.yaricap,
                border: Border.all(color: r.kenar),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.withValues(alpha: r.koyu ? .2 : .08), r.kart]),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(ikon, size: 18, color: c),
                n == null ? const Iskelet(yukseklik: 22, genislik: 30) : SayacMetin(deger: n, yaz: (x) => Bicim.sayi(x), stil: gosterim(22, renk: r.metin)),
                Text(alt ?? ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11)),
              ]),
            ),
          ),
        );
    return Row(children: [
      kutu('Mesaide', Canli.ozet.value == null ? null : mesaide, Icons.login_rounded, r.arti),
      const SizedBox(width: 8),
      kutu('Vardiya', vardiya, Icons.event_note_rounded, Marka.mavi, onTap: () => _ac(const VardiyaEkrani())),
      const SizedBox(width: 8),
      kutu('Talep', bekleyen, Icons.inbox_rounded, bekleyen > 0 ? Marka.gul : r.silik, onTap: () => _ac(const MesaiEkrani(sekme: 1)), alt: 'Talep'),
      const SizedBox(width: 8),
      kutu('Geciken', geciken, Icons.alarm_rounded, geciken > 0 ? r.eksi : r.silik, onTap: () => _ac(const GorevlerEkrani(suzgec: GorevSuzgec.geciken)), alt: 'Geciken'),
    ]);
  }

  Widget _baglantilar(int bekleyen, int acikGorev) {
    final r = context.pa;
    Widget dugme(IconData ikon, String ad, String alt, Color c, VoidCallback onTap, {int rozet = 0}) => Basilir(
          onTap: onTap,
          etiket: '$ad. $alt',
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [c, Color.lerp(c, Marka.mavi, .5)!]), borderRadius: Marka.yaricap),
                child: Icon(ikon, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13.5)),
                  Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11.5)),
                ]),
              ),
              Rozet(rozet),
            ]),
          ),
        );
    return LayoutBuilder(builder: (_, k) {
      final w = (k.maxWidth - 10) / 2;
      return Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(width: w, child: dugme(Icons.calendar_view_week_rounded, 'Vardiya planı', 'Haftalık takvim', Marka.mor, () => _ac(const VardiyaEkrani()))),
        SizedBox(width: w, child: dugme(Icons.fact_check_rounded, 'Mesai', 'Giriş, geç, mola', Marka.zumrut, () => _ac(const MesaiEkrani()))),
        SizedBox(
          width: w,
          child: Canli.onayBekleyenGorev > 0
              ? dugme(Icons.checklist_rounded, 'Görevler', '${Canli.onayBekleyenGorev} onay bekliyor', Marka.mavi,
                  () => _ac(const GorevlerEkrani(suzgec: GorevSuzgec.onay)), rozet: Canli.onayBekleyenGorev)
              : dugme(Icons.checklist_rounded, 'Görevler', '$acikGorev açık görev', Marka.mavi, () => _ac(const GorevlerEkrani())),
        ),
        SizedBox(width: w, child: dugme(Icons.inbox_rounded, 'Talepler', 'İzin, değişim', Marka.kehribar, () => _ac(const MesaiEkrani(sekme: 1)), rozet: bekleyen)),
      ]);
    });
  }

  Widget _mesaideKarti(Map<String, dynamic>? v, List<Map<String, dynamic>> ms) {
    final r = context.pa;
    if (v == null) return const PaKart(child: Iskelet(yukseklik: 120));
    final sira = v.l('upcoming_today');
    final simdi = DateTime.now();
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('Şu an mesaide', ikon: Icons.badge_rounded, alt: ms.isEmpty ? 'İçeride kimse yok' : 'Vardiya ilerlemesiyle',
            sag: Text('${ms.length} kişi', style: TextStyle(color: r.arti, fontWeight: FontWeight.w800))),
        if (ms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Personel QR ya da mesai ekranından giriş yapınca burada görünür.', style: TextStyle(color: r.silik, fontSize: 13)),
          ),
        for (final p in ms)
          Builder(builder: (_) {
            final v = _bugun?.where((x) => x.ad == p.s('name')).firstOrNull;
            final oran = v == null ? null : (simdi.difference(v.bas).inMinutes / math.max(1, v.son.difference(v.bas).inMinutes)).clamp(0.0, 1.0);
            final gir = DateTime.tryParse(p.s('since'));
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Avatar(p.s('name', '—'), boyut: 38, nokta: r.arti),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(p.s('name', '—'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 14))),
                      Text(Bicim.dakika(p.i('worked_minutes')), style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                    Text(
                      [p.s('position'), if (gir != null) 'Giriş ${Bicim.saat(gir)}', if (v != null) 'Çıkış ${Bicim.saat(v.son)}'].where((e) => e.isNotEmpty).join(' · '),
                      style: TextStyle(color: r.silik, fontSize: 12),
                    ),
                    if (oran != null) ...[
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: Stack(children: [
                          Container(height: 4, color: r.ic),
                          FractionallySizedBox(widthFactor: oran, child: Container(height: 4, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Marka.zumrutAcik, Marka.gok])))),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ]),
            );
          }),
        if (sira.isNotEmpty) ...[
          Divider(color: r.kenar, height: 22),
          Text('Bugün gelecekler', style: TextStyle(color: r.silik, fontWeight: FontWeight.w600, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in sira)
              Container(
                padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
                decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Avatar(p.s('name'), boyut: 26),
                  const SizedBox(width: 6),
                  Text(p.s('name').split(' ').first, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 12.5)),
                  const SizedBox(width: 6),
                  Text(DateTime.tryParse(p.s('start')) == null ? '' : Bicim.saat(DateTime.parse(p.s('start'))),
                      style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }

  /// Bugünün vardiyaları: yatay zaman çizelgesi (kişi başı çubuk + "şimdi").
  Widget _zamanCizelgesi() {
    final r = context.pa;
    final l = _bugun;
    if (l == null) {
      if (_vardiyaHata != null) {
        return PaKart(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const BolumBasligi('Bugünün vardiyaları', ikon: Icons.timeline_rounded),
            Text(_vardiyaHata!.kod == 404 ? 'Vardiya / Mesai eklentisi işletmenizde açık değil.' : _vardiyaHata!.yetkiYok ? 'Vardiyaları görme yetkiniz yok.' : _vardiyaHata!.mesaj,
                style: TextStyle(color: r.silik)),
          ]),
        );
      }
      return const PaKart(child: Iskelet(yukseklik: 140));
    }
    final n = DateTime.now();
    final g = DateTime(n.year, n.month, n.day);
    var basSaat = 24, sonSaat = 0;
    for (final v in l) {
      basSaat = math.min(basSaat, v.bas.isBefore(g) ? 0 : v.bas.hour);
      sonSaat = math.max(sonSaat, v.son.day != g.day ? 24 : v.son.hour + (v.son.minute > 0 ? 1 : 0));
    }
    if (l.isEmpty) {
      basSaat = 8;
      sonSaat = 24;
    }
    basSaat = math.min(basSaat, n.hour);
    sonSaat = math.max(sonSaat, n.hour + 1).clamp(basSaat + 4, 24);
    final aralik = (sonSaat - basSaat) * 60.0;
    double oran(DateTime t) => ((t.isBefore(g) ? 0 : t.difference(g).inMinutes) - basSaat * 60).clamp(0, aralik) / aralik;
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('Bugünün vardiyaları', ikon: Icons.timeline_rounded, alt: l.isEmpty ? 'Planlı vardiya yok' : '${l.length} vardiya · çubuğa dokunun',
            sag: TextButton(onPressed: () => _ac(const VardiyaEkrani()), child: const Text('Plan'))),
        if (l.isEmpty)
          Column(children: [
            Text('Bugün için vardiya planlanmamış.', style: TextStyle(color: r.silik)),
            const SizedBox(height: 8),
            YumusakDugme(onTap: () => vardiyaFormuAc(context).then((ok) => ok == true ? _yukle() : null), ikon: Icons.add_rounded, yazi: 'Vardiya planla'),
          ])
        else
          LayoutBuilder(builder: (_, k) {
            const adW = 70.0;
            final w = k.maxWidth - adW;
            final simdiX = adW + w * oran(n);
            final adim = (sonSaat - basSaat) > 12 ? 4 : 2;
            return Stack(children: [
              Column(children: [
                for (final v in l)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      SizedBox(width: adW, child: Text(v.ad.split(' ').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontSize: 12.5, fontWeight: FontWeight.w600))),
                      SizedBox(
                        width: w,
                        height: 26,
                        child: Stack(children: [
                          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(4)))),
                          Positioned(
                            left: w * oran(v.bas),
                            width: math.max(18, w * (oran(v.son) - oran(v.bas))),
                            top: 0,
                            bottom: 0,
                            child: Tooltip(
                              message: '${v.ad} · ${Bicim.saat(v.bas)}–${Bicim.saat(v.son)}',
                              child: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 5),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [vardiyaRengi(v.bas), Color.lerp(vardiyaRengi(v.bas), Marka.mavi, .4)!]),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('${Bicim.saat(v.bas)}–${Bicim.saat(v.son)}',
                                    maxLines: 1, overflow: TextOverflow.clip, softWrap: false, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                const SizedBox(height: 4),
                Row(children: [
                  const SizedBox(width: adW),
                  SizedBox(
                    width: w,
                    height: 14,
                    child: Stack(children: [
                      for (var h = basSaat; h <= sonSaat; h += adim)
                        Positioned(
                          left: (w * (h - basSaat) / (sonSaat - basSaat) - 12).clamp(0.0, w - 24),
                          child: SizedBox(width: 24, child: Text((h % 24).toString().padLeft(2, '0'), textAlign: TextAlign.center, style: TextStyle(color: r.silik, fontSize: 10))),
                        ),
                    ]),
                  ),
                ]),
              ]),
              // Şimdi çizgisi
              Positioned(
                left: simdiX - 1,
                top: 0,
                bottom: 16,
                child: IgnorePointer(child: Container(width: 2, decoration: BoxDecoration(color: r.eksi, borderRadius: BorderRadius.circular(1)))),
              ),
            ]);
          }),
      ]),
    );
  }

  Widget _gorevKarti(List<Map<String, dynamic>>? gorev) {
    final r = context.pa;
    if (gorev == null) {
      return PaKart(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const BolumBasligi('Açık görevler', ikon: Icons.checklist_rounded),
          if (Canli.gorevYetki.value == Yetki.yok)
            Text('Görevleri görme yetkiniz yok.', style: TextStyle(color: r.silik))
          else if (Canli.gorevYetki.value == Yetki.kapali)
            Text('Görev özelliği işletmenizde açık değil.', style: TextStyle(color: r.silik))
          else
            const Iskelet(yukseklik: 60),
        ]),
      );
    }
    final acik = gorev.where((t) => t.s('status') != 'done').toList();
    final biten = gorev.length - acik.length;
    final oran = gorev.isEmpty ? 0.0 : biten / gorev.length;
    return PaKart(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BolumBasligi('Açık görevler', ikon: Icons.checklist_rounded, alt: '$biten/${gorev.length} tamamlandı',
            sag: TextButton(onPressed: () => _ac(const GorevlerEkrani()), child: const Text('Tümü'))),
        if (gorev.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(children: [
              Container(height: 6, color: r.ic),
              AnimatedFractionallySizedBox(
                duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
                widthFactor: oran,
                child: Container(height: 6, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Marka.zumrutAcik, Marka.mavi]))),
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        if (acik.isEmpty)
          Column(children: [
            Text(gorev.isEmpty ? 'Henüz görev yok. Ekibe iş atayın.' : 'Tüm görevler tamamlandı.', style: TextStyle(color: r.silik)),
            if (Canli.gorevYetki.value != Yetki.yok) ...[
              const SizedBox(height: 8),
              YumusakDugme(onTap: () => _ac(const GorevFormu()), ikon: Icons.add_task_rounded, yazi: 'Görev oluştur'),
            ],
          ])
        else
          for (final t in acik.take(4))
            Padding(padding: const EdgeInsets.only(bottom: 8), child: GorevKarti(t: t, onTap: () => _ac(const GorevlerEkrani()))),
      ]),
    );
  }
}
