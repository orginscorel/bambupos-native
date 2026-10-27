import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/raporlar.dart';
import '../core/tema.dart';
import '../ortak/donem.dart';
import '../ortak/grafik.dart';
import '../ortak/ortak.dart';

/// Hücre değerini sütun türüne göre yazar (₺, %, tarih, Evet/Hayır …).
String hucreYaz(String k, Object? v) {
  if (v == null || (v is String && v.isEmpty)) return '—';
  if (k == 'hour') return '${(v is num ? v.round() : int.tryParse('$v') ?? 0).toString().padLeft(2, '0')}:00';
  num? n() => v is num ? v : num.tryParse('$v');
  switch (sutunTuru(k)) {
    case SutunTur.para:
      return Bicim.para(n());
    case SutunTur.sayi:
      return Bicim.sayi(n());
    case SutunTur.ortalama:
      return k.endsWith('_minor') ? Bicim.para(n()) : Bicim.ondalik(n());
    case SutunTur.yuzde:
      return Bicim.yuzde(n());
    case SutunTur.evetHayir:
      return v == true || v == 1 || v == '1' ? 'Evet' : 'Hayır';
    case SutunTur.tarih:
      final s = '$v';
      if (s.length == 10) {
        final g = Bicim.gunCoz(s);
        return g == null ? s : Bicim.gunAy(g);
      }
      final d = DateTime.tryParse(s);
      return d == null ? s : Bicim.tarihSaat(d);
    case SutunTur.metin:
      return '$v';
  }
}

class RaporEkrani extends StatefulWidget {
  const RaporEkrani({super.key, required this.tanim, required this.donem, this.gomulu = false});
  final RaporTanim tanim;
  final Donem donem;

  /// Raporlar sekmesinin içinde (web paneldeki gibi başlık satırının altında)
  /// çizilir: kendi sayfası, geri düğmesi ve dönem seçicisi yok; dönem üstten gelir.
  final bool gomulu;
  @override
  State<RaporEkrani> createState() => _RaporEkraniState();
}

class _RaporEkraniState extends State<RaporEkrani> {
  late Donem _donem = widget.donem;
  List<Map<String, dynamic>>? _satirlar;
  Map<String, dynamic>? _filtre;
  Object? _hata;
  bool _yukleniyor = false;
  bool _tablo = false;
  String _ara = '';
  int _istek = 0;
  bool _kapali = false;

  RaporTanim get t => widget.tanim;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(RaporEkrani eski) {
    super.didUpdateWidget(eski);
    if (eski.donem != widget.donem || eski.tanim.anahtar != widget.tanim.anahtar) {
      _donem = widget.donem;
      _satirlar = null;
      _ara = '';
      _yukle();
    }
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      List<Map<String, dynamic>> satir;
      Map<String, dynamic>? filtre;
      var kapali = false;
      if (t.kaynak == 'ozet-stok') {
        final r = await Uyg.api.get('/api/v1/boss/overview', sorgu: const {'period': 'day'});
        final inv = (r as Map).m('data')['inventory'];
        kapali = inv == null;
        satir = inv is Map ? inv.l('rows') : const [];
      } else {
        final r = await Uyg.api.get('/api/v1/reports/${t.anahtar}', sorgu: _donem.raporSorgu, zamanAsimi: const Duration(seconds: 60));
        final m = r is Map ? r : const {};
        final data = m.m('data');
        kapali = data['available'] == false;
        satir = data.l(t.satirlar);
        filtre = m.m('filters');
      }
      if (!mounted || no != _istek) return;
      setState(() {
        _satirlar = satir;
        _filtre = filtre;
        _kapali = kapali;
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

  String get _etiketSutunu =>
      t.grafikEtiket ?? t.sutunlar.keys.firstWhere((k) => sutunTuru(k) == SutunTur.metin || sutunTuru(k) == SutunTur.tarih, orElse: () => t.sutunlar.keys.first);

  String? get _degerSutunu =>
      t.grafikDeger ??
      t.sutunlar.keys.where((k) => sutunTuru(k) == SutunTur.para).firstOrNull ??
      t.sutunlar.keys.where((k) => sutunTuru(k) == SutunTur.sayi).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final a = Bicim.gunCoz(_filtre?.s('from'));
    final b = Bicim.gunCoz(_filtre?.s('to'));
    final alt = t.kaynak != null ? 'Anlık durum' : (a != null && b != null ? Bicim.aralik(a, b) : _donem.ad);
    final s = _satirlar;
    final govde = <Widget>[
      if (s == null && _hata != null)
        PaKart(child: HataDurum(hata: _hata!, yenile: _yukle))
      else if (s == null)
        const Column(children: [Iskelet(yukseklik: 80), SizedBox(height: 12), Iskelet(yukseklik: 180), SizedBox(height: 12), Iskelet(yukseklik: 260)])
      else if (_kapali)
        const PaKart(child: BosDurum(baslik: 'Bu bölüm işletmenizde açık değil', ikon: Icons.extension_off_rounded))
      else if (s.isEmpty)
        const PaKart(child: BosDurum(baslik: 'Bu dönemde kayıt yok', mesaj: 'Başka bir tarih aralığı seçmeyi deneyin.'))
      else
        ..._icerik(context, s),
    ];
    if (widget.gomulu) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (t.aciklama != null || t.kaynak != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(t.kaynak != null ? '${t.aciklama ?? ''} · anlık durum, dönemden bağımsız' : t.aciklama!,
                style: TextStyle(color: context.pa.silik, fontSize: 12.5)),
          ),
        ...govde,
      ]);
    }
    return PaSayfa(
      baslik: t.baslik,
      alt: alt,
      geri: true,
      yenile: _yukle,
      altBosluk: 40,
      sag: AnimatedOpacity(
        opacity: _yukleniyor && s != null ? 1 : 0,
        duration: Hareket.orta,
        child: const Padding(padding: EdgeInsets.all(8), child: Yukleyici(boyut: 20)),
      ),
      children: [
        if (t.kaynak == null) ...[
          DonemSecici(
            secili: _donem,
            degisti: (d) {
              setState(() => _donem = d);
              _yukle();
            },
          ),
          const SizedBox(height: 14),
        ],
        ...govde,
      ],
    );
  }

  List<Widget> _icerik(BuildContext context, List<Map<String, dynamic>> s) {
    final r = context.pa;
    final toplamlar = t.sutunlar.keys.where(toplanirMi).take(4).toList();
    final q = _ara.trim().toLowerCase();
    final suzulmus = q.isEmpty ? s : s.where((row) => row.values.any((v) => '$v'.toLowerCase().contains(q))).toList();
    var sira = 0;
    Widget b(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Belirme(sira: sira++, child: w));
    return [
      if (toplamlar.isNotEmpty)
        b(LayoutBuilder(builder: (_, k) {
          final sutun = k.maxWidth >= 560 ? 4 : 2;
          final w = (k.maxWidth - 10 * (sutun - 1)) / sutun;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            _OzetKutu(w: w, ad: 'Kayıt', deger: s.length, yaz: Bicim.sayi),
            for (final c in toplamlar.take(sutun == 4 ? 3 : 3))
              _OzetKutu(
                w: w,
                ad: t.sutunlar[c]!,
                deger: s.fold<num>(0, (a, row) => a + (row[c] is num ? row[c] as num : num.tryParse('${row[c]}') ?? 0)),
                yaz: (n) => sutunTuru(c) == SutunTur.para ? Bicim.para(n, tam: true) : Bicim.sayi(n),
              ),
          ]);
        })),
      if (_grafik(s) case final g?) b(PaKart(child: g)),
      b(Row(children: [
        Expanded(
          child: s.length > 8
              ? TextField(
                  onChanged: (v) => setState(() => _ara = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Satırlarda ara', isDense: true),
                )
              : Text('${s.length} satır', style: TextStyle(color: r.silik, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), minimumSize: const Size(44, 44)),
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.view_agenda_rounded), tooltip: 'Liste görünümü'),
            ButtonSegment(value: true, icon: Icon(Icons.table_chart_rounded), tooltip: 'Tablo görünümü'),
          ],
          selected: {_tablo},
          onSelectionChanged: (v) => setState(() => _tablo = v.first),
        ),
      ])),
      // Görünüm değişimi: yeni görünüm hafifçe büyüyerek belirir (asamaGecisi).
      AnimatedSwitcher(
        duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
        transitionBuilder: asamaGecisi,
        layoutBuilder: (simdiki, oncekiler) => Stack(alignment: Alignment.topCenter, children: [...oncekiler, ?simdiki]),
        child: KeyedSubtree(
          key: ValueKey(_tablo),
          child: _tablo ? _Tablo(t: t, satirlar: suzulmus) : _Liste(t: t, satirlar: suzulmus, etiket: _etiketSutunu, deger: _degerSutunu),
        ),
      ),
    ];
  }

  Widget? _grafik(List<Map<String, dynamic>> s) {
    final dk = _degerSutunu;
    if (t.grafik == GrafikTur.yok || dk == null || s.length < 2) return null;
    final ek = _etiketSutunu;
    double deger(Map row) => (row[dk] is num ? row[dk] as num : num.tryParse('${row[dk]}') ?? 0).toDouble();
    String yaz(double d) => sutunTuru(dk) == SutunTur.para || dk.endsWith('_minor') ? Bicim.para(d, tam: true) : Bicim.ondalik(d);
    String etiket(Map row) {
      final v = row[ek];
      if (ek == 'date') {
        final g = Bicim.gunCoz('$v');
        return g == null ? '$v' : Bicim.gunAyKisa(g);
      }
      if (ek == 'hour') return (v is num ? v.round() : int.tryParse('$v') ?? 0).toString().padLeft(2, '0');
      return hucreYaz(ek, v);
    }

    final baslik = BolumBasligi(t.sutunlar[dk] ?? 'Değer', ikon: Icons.insights_rounded);
    switch (t.grafik) {
      case GrafikTur.cizgi:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          baslik,
          CizgiGrafik(noktalar: [for (final row in s) Nokta(etiket(row), deger(row))], yaz: yaz, ozet: '${t.baslik} çizgi grafiği'),
        ]);
      case GrafikTur.sutun:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          baslik,
          SutunGrafik(noktalar: [for (final row in s) Nokta(etiket(row), deger(row))], yaz: yaz, ozet: '${t.baslik} sütun grafiği'),
        ]);
      case GrafikTur.siraliSutun:
        final sirali = [...s]..sort((a, b) => deger(b).compareTo(deger(a)));
        final ilk = sirali.take(8).toList();
        final enCok = ilk.isEmpty ? 1.0 : (deger(ilk.first) == 0 ? 1.0 : deger(ilk.first));
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          BolumBasligi('En yüksek ${ilk.length} · ${t.sutunlar[dk]}', ikon: Icons.leaderboard_rounded),
          for (var i = 0; i < ilk.length; i++)
            CubukSatir(sira: i + 1, ad: hucreYaz(ek, ilk[i][ek]), deger: yaz(deger(ilk[i])), oran: deger(ilk[i]) / enCok, renk: Marka.dizi[i % 3]),
        ]);
      case GrafikTur.yok:
        return null;
    }
  }
}

class _OzetKutu extends StatelessWidget {
  const _OzetKutu({required this.w, required this.ad, required this.deger, required this.yaz});
  final double w;
  final String ad;
  final num deger;
  final String Function(num) yaz;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return SizedBox(
      width: w,
      child: Semantics(
        container: true,
        label: 'Toplam $ad: ${yaz(deger)}',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SayacMetin(deger: deger, yaz: yaz, stil: gosterim(18, renk: r.metin)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Liste görünümü: her satır bir kart — başlık + ana değer + diğer sütunlar.
class _Liste extends StatelessWidget {
  const _Liste({required this.t, required this.satirlar, required this.etiket, required this.deger});
  final RaporTanim t;
  final List<Map<String, dynamic>> satirlar;
  final String etiket;
  final String? deger;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final digerleri = t.sutunlar.keys.where((k) => k != etiket && k != deger).toList();
    return Column(children: [
      for (var i = 0; i < satirlar.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Belirme(
            sira: i,
            child: Semantics(
              container: true,
              label: [for (final k in t.sutunlar.keys) '${t.sutunlar[k]}: ${hucreYaz(k, satirlar[i][k])}'].join(', '),
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(hucreYaz(etiket, satirlar[i][etiket]),
                          style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    if (deger != null)
                      Text(hucreYaz(deger!, satirlar[i][deger]), style: gosterim(15, renk: r.metin)),
                  ]),
                  if (digerleri.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      for (final k in digerleri)
                        if (satirlar[i][k] != null && '${satirlar[i][k]}'.isNotEmpty)
                          Text.rich(TextSpan(children: [
                            TextSpan(text: '${t.sutunlar[k]}: ', style: TextStyle(color: r.silik, fontSize: 12.5)),
                            TextSpan(text: hucreYaz(k, satirlar[i][k]), style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ])),
                    ]),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Tablo görünümü: yatay kaydırmalı, başlık satırlı; altta toplam satırı.
class _Tablo extends StatelessWidget {
  const _Tablo({required this.t, required this.satirlar});
  final RaporTanim t;
  final List<Map<String, dynamic>> satirlar;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final k = t.sutunlar.keys.toList();
    bool sayisal(String c) => sutunTuru(c) != SutunTur.metin && sutunTuru(c) != SutunTur.tarih && sutunTuru(c) != SutunTur.evetHayir;
    Widget hucre(String s, {bool kalin = false, bool sag = false, Color? renk}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Text(s,
              textAlign: sag ? TextAlign.right : TextAlign.left,
              style: TextStyle(fontSize: 12.5, fontWeight: kalin ? FontWeight.w700 : FontWeight.w500, color: renk ?? r.metin, fontFeatures: const [FontFeature.tabularFigures()])),
        );
    final toplamVar = k.any(toplanirMi);
    return Container(
      decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder(horizontalInside: BorderSide(color: r.kenar)),
          children: [
            TableRow(
              decoration: BoxDecoration(color: r.ic),
              children: [for (final c in k) hucre(t.sutunlar[c]!, kalin: true, sag: sayisal(c), renk: r.soluk)],
            ),
            for (final row in satirlar) TableRow(children: [for (final c in k) hucre(hucreYaz(c, row[c]), sag: sayisal(c))]),
            if (toplamVar)
              TableRow(
                decoration: BoxDecoration(color: r.birincilYumusak),
                children: [
                  for (var i = 0; i < k.length; i++)
                    toplanirMi(k[i])
                        ? hucre(hucreYaz(k[i], satirlar.fold<num>(0, (a, row) => a + (row[k[i]] is num ? row[k[i]] as num : num.tryParse('${row[k[i]]}') ?? 0))),
                            kalin: true, sag: true)
                        : hucre(i == 0 ? 'Toplam' : '', kalin: true),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
