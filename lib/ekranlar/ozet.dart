import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/icgoru.dart';
import '../core/tema.dart';
import '../ortak/donem.dart';
import '../ortak/grafik.dart';
import '../ortak/ortak.dart';
import '../core/canli.dart';
import '../ortak/ust_serit.dart';
import 'borclar.dart';
import 'gorevler.dart';
import 'kabuk.dart';
import 'rapor.dart';
import '../core/raporlar.dart';

/// ÖZET (patron panosu): GET /api/v1/boss/overview + bugün için
/// /api/v1/tasks (bugünkü görevler) ve /api/v1/reports/ops-delayed
/// (bekleyen adisyonlar). Yalnız overview zorunlu; diğerleri yetki/eklenti
/// yoksa sessizce düşer.
class OzetEkrani extends StatefulWidget {
  const OzetEkrani({super.key});

  /// Uygulamaya dönünce kabuk artırır → özet tazelenir.
  static final tazele = ValueNotifier<int>(0);

  @override
  State<OzetEkrani> createState() => _OzetEkraniState();
}

class _OzetEkraniState extends State<OzetEkrani> {
  Donem _donem = Donem.hazir(DonemTur.bugun);
  Map<String, dynamic>? _veri;
  List<Map<String, dynamic>>? _gorevler;
  List<Map<String, dynamic>>? _geciken;
  Object? _hata;
  bool _yukleniyor = false;
  int _istek = 0;
  Timer? _oto;

  /// Bugün seçiliyken kıyas verisi: dünün özeti (saatlik) ve son 7 gün
  /// (günlük). 10 dk'da bir yeter — her 60 sn'lik tazelemede istenmez.
  Map<String, dynamic>? _dun;
  Map<String, dynamic>? _yediGun;
  DateTime? _kiyasZamani;

  @override
  void initState() {
    super.initState();
    OzetEkrani.tazele.addListener(_yukle);
    _onbellektenCiz(_donem);
    _yukle();
    // Bugün seçiliyken ve sekme görünürken 60 sn'de bir sessizce tazele.
    _oto = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && _donem.tur == DonemTur.bugun && TickerMode.valuesOf(context).enabled) _yukle();
    });
  }

  @override
  void dispose() {
    OzetEkrani.tazele.removeListener(_yukle);
    _oto?.cancel();
    super.dispose();
  }

  /// Son bilinen yanıtları hemen çiz (sunucu yanıtı gelince yenilenir).
  void _onbellektenCiz(Donem donem) {
    final r = Api.sonYanit('/api/v1/boss/overview', sorgu: donem.ozetSorgu);
    _veri = r is Map ? r.m('data') : null;
    if (donem.tur != DonemTur.bugun) return;
    final g = Api.sonYanit('/api/v1/tasks');
    if (g is Map) _gorevler = g.l('tasks');
    final gc = Api.sonYanit('/api/v1/reports/ops-delayed', sorgu: const {'range': 'today'});
    if (gc is Map) _geciken = gc.m('data').l('rows');
    final ig = Uyg.isGunu;
    final dn = Api.sonYanit('/api/v1/boss/overview',
        sorgu: {'from': Bicim.iso(ig.subtract(const Duration(days: 1))), 'to': Bicim.iso(ig.subtract(const Duration(days: 1)))});
    if (dn is Map) _dun = dn.m('data');
    final yd = Api.sonYanit('/api/v1/boss/overview', sorgu: {'from': Bicim.iso(ig.subtract(const Duration(days: 6))), 'to': Bicim.iso(ig)});
    if (yd is Map) _yediGun = yd.m('data');
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    final donem = _donem;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    final bugun = donem.tur == DonemTur.bugun;
    Future<T?> sessiz<T>(Future<T> f) async {
      try {
        return await f;
      } on ApiHata {
        return null;
      }
    }

    try {
      final gorevF = bugun ? sessiz(Uyg.api.get('/api/v1/tasks')) : Future.value(null);
      final gecikenF = bugun ? sessiz(Uyg.api.get('/api/v1/reports/ops-delayed', sorgu: {'range': 'today'})) : Future.value(null);
      final kiyasGerek = bugun && (_kiyasZamani == null || DateTime.now().difference(_kiyasZamani!) > const Duration(minutes: 10));
      final ig = Uyg.isGunu;
      final dunF = kiyasGerek
          ? sessiz(
              Uyg.api.get(
                '/api/v1/boss/overview',
                sorgu: {'from': Bicim.iso(ig.subtract(const Duration(days: 1))), 'to': Bicim.iso(ig.subtract(const Duration(days: 1)))},
              ),
            )
          : Future.value(null);
      final yediF = kiyasGerek
          ? sessiz(Uyg.api.get('/api/v1/boss/overview', sorgu: {'from': Bicim.iso(ig.subtract(const Duration(days: 6))), 'to': Bicim.iso(ig)}))
          : Future.value(null);
      final r = await Uyg.api.get('/api/v1/boss/overview', sorgu: donem.ozetSorgu);
      final veri = (r is Map ? r.m('data') : <String, dynamic>{});
      if (bugun) {
        final f = veri.m('range').s('from');
        if (f.isNotEmpty) await Uyg.isGunuKaydet(f);
        Canli.ozetGeldi(veri);
      }
      // Ana rakamlar hemen; kıyas/görev istekleri arkadan gelir.
      if (mounted && no == _istek) setState(() => _veri = veri);
      final dn = await dunF;
      final yd = await yediF;
      if (dn is Map || yd is Map) {
        _kiyasZamani = DateTime.now();
        if (dn is Map) _dun = dn.m('data');
        if (yd is Map) _yediGun = yd.m('data');
      }
      final g = await gorevF;
      final gc = await gecikenF;
      if (!mounted || no != _istek) return;
      setState(() {
        _veri = veri;
        _gorevler = g is Map ? g.l('tasks') : null;
        _geciken = gc is Map ? gc.m('data').l('rows') : null;
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

  void _donemSec(Donem d) {
    if (d == _donem) return;
    setState(() {
      _donem = d;
      _onbellektenCiz(d);
    });
    _yukle();
  }

  String get _aralikYazi {
    final r = _veri?.m('range');
    final a = Bicim.gunCoz(r?.s('from'));
    final b = Bicim.gunCoz(r?.s('to'));
    if (a == null || b == null) return Bicim.aralik(_donem.bas, _donem.son);
    return Bicim.aralik(a, b);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final v = _veri;
    final ust = MediaQuery.paddingOf(context).top;
    final bugun = _donem.tur == DonemTur.bugun;
    final kap = _kapakVerisi(v, bugun);
    final liste = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        OzetKapak(
          ciro: v?.m('sales').i('revenue_minor'),
          donemAdi: _donem.ad,
          degisim: v?.m('sales').m('delta_pct').d('revenue'),
          altYazi: v == null ? null : kap.alt,
          cizgi: kap.cizgi,
          kiyas: kap.kiyas,
          cizgiSon: kap.son,
          cizgiEtiketleri: kap.etiket,
          yukleniyor: _yukleniyor && v != null,
          onProfil: () => Kabuk.sekme.value = 3,
          onEkip: () => Kabuk.sekme.value = 2,
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DonemSecici(secili: _donem, degisti: _donemSec),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('$_aralikYazi · aşağı çekerek yenileyin', style: TextStyle(color: r.silik, fontSize: 12)),
                  const SizedBox(height: 12),
                  if (v == null && _hata != null)
                    PaKart(
                      child: HataDurum(hata: _hata!, yenile: _yukle),
                    )
                  else if (v == null)
                    const _OzetIskelet()
                  else
                    ..._bolumler(context, v),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Üstte lacivert kapak → açık simgeler (her iki temada).
      value: durumStili(koyuUst: true, koyuTema: r.koyu),
      child: Scaffold(
        body: Stack(
          children: [
            RefreshIndicator(onRefresh: _yukle, color: r.birincil, edgeOffset: ust, child: liste),
            // Kaydırınca saat/şarj simgeleri içerikle çakışmasın: lacivert şerit.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: ust,
              child: const ColoredBox(color: Marka.gece),
            ),
          ],
        ),
      ),
    );
  }

  /// Kapak çizgisi: bugün → iş günü saatlerine göre BİRİKİMLİ ciro (dün
  /// kesikli); diğer dönemler → günlük ciro.
  ({List<double> cizgi, List<double> kiyas, int? son, (String, String) etiket, String? alt}) _kapakVerisi(Map<String, dynamic>? v, bool bugun) {
    if (v == null) return (cizgi: const [], kiyas: const [], son: null, etiket: ('', ''), alt: null);
    final s = v.m('sales');
    final onceki = s.m('prev').i('revenue_minor');
    if (bugun) {
      final bas = v.m('is_gunu').i('baslangic_saati');
      List<double> birikimli(Map<String, dynamic>? x) {
        if (x == null) return const [];
        final saat = {for (final h in x.l('by_hour')) h.i('hour'): h.i('revenue_minor').toDouble()};
        var t = 0.0;
        return [for (var k = 0; k < 24; k++) t += saat[(bas + k) % 24] ?? 0];
      }

      final b = birikimli(v);
      final d = birikimli(_dun);
      final simdi = (DateTime.now().hour - bas) % 24;
      final dunBuSaat = d.isEmpty ? null : d[simdi.clamp(0, 23)].round();
      final dunToplam = d.isEmpty ? onceki : d.last.round();
      return (
        cizgi: b,
        kiyas: d,
        son: simdi,
        etiket: ('${bas.toString().padLeft(2, '0')}:00', 'şimdi ${Bicim.saat(DateTime.now())}'),
        alt: dunBuSaat != null
            ? 'Dün bu saate kadar ${Bicim.para(dunBuSaat, tam: true)} · dün toplam ${Bicim.para(dunToplam, tam: true)}'
            : onceki > 0
            ? 'Önceki dönem ${Bicim.para(onceki, tam: true)}'
            : 'Önceki dönemde kıyaslanacak satış yok',
      );
    }
    final g = v.l('by_day');
    return (
      cizgi: [for (final x in g) x.i('revenue_minor').toDouble()],
      kiyas: const [],
      son: null,
      etiket: (
        g.isEmpty ? '' : Bicim.gunAyKisa(Bicim.gunCoz(g.first.s('date')) ?? DateTime.now()),
        g.isEmpty ? '' : Bicim.gunAyKisa(Bicim.gunCoz(g.last.s('date')) ?? DateTime.now()),
      ),
      alt: onceki > 0 ? 'Önceki dönem ${Bicim.para(onceki, tam: true)}' : 'Önceki dönemde kıyaslanacak satış yok',
    );
  }

  List<Widget> _bolumler(BuildContext context, Map<String, dynamic> v) {
    final bugun = _donem.tur == DonemTur.bugun;
    var sira = 0;
    Widget b(Widget w) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Belirme(sira: sira++, child: w),
    );
    final akis = durumAkisi(v, kiyas: _donem.kiyasAdi, bugun: bugun, geciken: _geciken);
    return [
      if (_hata != null)
        b(
          PaKart(
            renk: context.pa.eksi.withValues(alpha: .08),
            child: Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: context.pa.eksi),
                const SizedBox(width: 10),
                Expanded(child: Text('Güncellenemedi: ${_hata is ApiHata ? (_hata as ApiHata).mesaj : _hata}', style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
        ),
      b(_KpiIzgara(v: v)),
      b(_HedefKarti(v: v, dun: bugun ? _dun : null, donem: _donem)),
      if (akis.isNotEmpty) b(_DurumAkisi(akis)),
      if (bugun) ..._kiyasGrafikleri(v, b),
      if (bugun && _gorevler != null) b(_BugunGorevler(_gorevler!)),
      ..._grafikler(v, b, saatlikVar: bugun && _dun != null),
      ..._dagilimlar(v, b),
      ..._para(v, b),
      ..._ekipVeDiger(v, b, bugun),
    ];
  }

  /// Bugün: saatlik ciro (dün kesikli) + son 7 gün çubuğu.
  List<Widget> _kiyasGrafikleri(Map<String, dynamic> v, Widget Function(Widget) b) {
    final out = <Widget>[];
    final dun = _dun;
    if (dun != null) {
      final bas = v.m('is_gunu').i('baslangic_saati');
      Map<int, double> saat(Map<String, dynamic> x) => {for (final h in x.l('by_hour')) h.i('hour'): h.i('revenue_minor').toDouble()};
      final bs = saat(v), ds = saat(dun);
      final sira = [for (var k = 0; k < 24; k++) (bas + k) % 24];
      final simdi = (DateTime.now().hour - bas) % 24;
      final pk = v.m('operations').m('peak_hour');
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi(
                  'Saatlik ciro',
                  ikon: Icons.show_chart_rounded,
                  alt: pk.isEmpty ? 'Dünle karşılaştırmalı · dokunun' : 'En yoğun saat ${pk.i('hour').toString().padLeft(2, '0')}:00 · dokunun',
                ),
                KarsilastirmaGrafik(
                  noktalar: [
                    for (final h in sira)
                      Nokta(
                        h.toString().padLeft(2, '0'),
                        bs[h] ?? 0,
                        uzun: '${h.toString().padLeft(2, '0')}:00 – ${((h + 1) % 24).toString().padLeft(2, '0')}:00',
                      ),
                  ],
                  kiyas: [for (final h in sira) ds[h] ?? 0],
                  sonIndeks: simdi,
                  yaz: (d) => Bicim.para(d, tam: true),
                  ozet: 'Saatlik ciro, bugün ve dün karşılaştırması',
                ),
              ],
            ),
          ),
        ),
      );
    }
    final yedi = _yediGun?.l('by_day') ?? const [];
    if (yedi.length >= 2) {
      final ort = yedi.fold<int>(0, (a, g) => a + g.i('revenue_minor')) / yedi.length;
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi(
                  'Son 7 gün',
                  ikon: Icons.calendar_view_week_rounded,
                  alt: 'Günlük ortalama ${Bicim.para(ort, tam: true)}',
                  sag: _tumu('sales-daily'),
                ),
                SutunGrafik(
                  yukseklik: 150,
                  vurgu: yedi.length - 1,
                  noktalar: [
                    for (final g in yedi)
                      Nokta(
                        Bicim.gunCoz(g.s('date')) == null ? g.s('date') : Bicim.gunKisa[Bicim.gunCoz(g.s('date'))!.weekday - 1],
                        g.i('revenue_minor').toDouble(),
                        uzun: Bicim.gunCoz(g.s('date')) == null
                            ? g.s('date')
                            : '${Bicim.gunAy(Bicim.gunCoz(g.s('date'))!)} · ${g.i('orders')} adisyon',
                      ),
                  ],
                  yaz: (d) => Bicim.para(d, tam: true),
                  renk: Marka.mavi,
                  ozet: 'Son 7 günün günlük cirosu',
                ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _grafikler(Map<String, dynamic> v, Widget Function(Widget) b, {bool saatlikVar = false}) {
    final out = <Widget>[];
    final saatler = v.l('by_hour');
    final dolu = saatler.where((h) => h.i('revenue_minor') > 0 || h.i('orders') > 0).toList();
    if (dolu.isNotEmpty && !saatlikVar) {
      // Boş baştaki/sondaki saatleri at (okunurluk); arada boşlar kalır.
      final ilk = saatler.indexOf(dolu.first), son = saatler.indexOf(dolu.last);
      final dilim = saatler.sublist((ilk - 1).clamp(0, 23), (son + 2).clamp(0, 24));
      final pk = v.m('operations').m('peak_hour');
      final vurgu = pk.isEmpty ? null : dilim.indexWhere((h) => h.i('hour') == pk.i('hour'));
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BolumBasligi('Saatlik satış', ikon: Icons.schedule_rounded, alt: 'Sütuna dokunarak saati görün'),
                SutunGrafik(
                  noktalar: [
                    for (final h in dilim)
                      Nokta(
                        h.i('hour').toString().padLeft(2, '0'),
                        h.i('revenue_minor').toDouble(),
                        uzun: '${h.i('hour').toString().padLeft(2, '0')}:00 · ${h.i('orders')} adisyon',
                      ),
                  ],
                  yaz: (d) => Bicim.para(d, tam: true),
                  vurgu: vurgu == null || vurgu < 0 ? null : vurgu,
                  ozet: pk.isEmpty ? 'Saatlik satış grafiği' : 'Saatlik satış grafiği. En yoğun saat ${pk.i('hour')}:00.',
                ),
              ],
            ),
          ),
        ),
      );
    }
    final gunler = v.l('by_day');
    if (gunler.length > 1) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BolumBasligi('Günlük ciro', ikon: Icons.show_chart_rounded),
                CizgiGrafik(
                  noktalar: [
                    for (final g in gunler)
                      Nokta(
                        Bicim.gunCoz(g.s('date')) == null ? g.s('date') : Bicim.gunAyKisa(Bicim.gunCoz(g.s('date'))!),
                        g.i('revenue_minor').toDouble(),
                        uzun: Bicim.gunCoz(g.s('date')) == null
                            ? g.s('date')
                            : '${Bicim.gunAy(Bicim.gunCoz(g.s('date'))!)} · ${g.i('orders')} adisyon',
                      ),
                  ],
                  yaz: (d) => Bicim.para(d, tam: true),
                  ozet: 'Günlük ciro çizgi grafiği, ${gunler.length} gün',
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (gunler.length >= 7) {
      final hg = v.l('by_weekday');
      if (hg.length == 7) {
        out.add(
          b(
            PaKart(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BolumBasligi('Haftanın günleri', ikon: Icons.calendar_view_week_rounded),
                  SutunGrafik(
                    yukseklik: 140,
                    noktalar: [
                      for (final w in hg)
                        Nokta(
                          Bicim.gunKisa[w.i('weekday').clamp(0, 6)],
                          w.i('revenue_minor').toDouble(),
                          uzun: '${Bicim.gunKisa[w.i('weekday').clamp(0, 6)]} · ${w.i('orders')} adisyon',
                        ),
                    ],
                    yaz: (d) => Bicim.para(d, tam: true),
                    renk: Marka.mavi,
                    ozet: 'Haftanın günlerine göre ciro',
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return out;
  }

  List<Widget> _dagilimlar(Map<String, dynamic> v, Widget Function(Widget) b) {
    final out = <Widget>[];
    final pm = v.m('payment_mix');
    final pr = pm.l('rows').where((r) => r.i('amount_minor') > 0).toList();
    if (pr.isNotEmpty) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BolumBasligi('Ödeme yöntemleri', ikon: Icons.credit_card_rounded, alt: 'Adisyon + borç tahsilatı'),
                HalkaGrafik(
                  dilimler: [for (final r in pr) Dilim(r.s('label', r.s('method')), r.i('amount_minor').toDouble())],
                  yaz: (d) => Bicim.paraKisa(d),
                  ortaBaslik: 'Tahsilat',
                ),
              ],
            ),
          ),
        ),
      );
    }
    final st = v.m('service_types').l('rows').where((r) => r.i('revenue_minor') > 0).toList();
    if (st.length > 1) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BolumBasligi('Servis türü', ikon: Icons.room_service_rounded),
                for (var i = 0; i < st.length; i++)
                  CubukSatir(
                    sira: i + 1,
                    ad: st[i].s('label'),
                    deger: Bicim.para(st[i].i('revenue_minor'), tam: true),
                    alt: '${st[i].i('orders')} adisyon',
                    oran: (st[i].d('share') ?? 0) / 100,
                    renk: Marka.dizi[i % Marka.dizi.length],
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final tp = v.l('top_products');
    if (tp.isNotEmpty) {
      final enCok = tp.map((e) => e.i('qty')).fold<int>(1, (a, b) => a > b ? a : b);
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi('En çok satan ürünler', ikon: Icons.star_rounded, sag: _tumu('sales-products')),
                for (var i = 0; i < tp.length; i++)
                  CubukSatir(
                    sira: i + 1,
                    ad: tp[i].s('name'),
                    deger: '${Bicim.sayi(tp[i].i('qty'))} adet',
                    alt: Bicim.paraKisa(tp[i].i('revenue_minor')),
                    oran: tp[i].i('qty') / enCok,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final tk = v.l('top_categories');
    if (tk.isNotEmpty) {
      final enCok = tk.map((e) => e.i('revenue_minor')).fold<int>(1, (a, b) => a > b ? a : b);
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi('Kategoriler', ikon: Icons.category_rounded, sag: _tumu('sales-categories')),
                for (var i = 0; i < tk.length; i++)
                  CubukSatir(
                    sira: i + 1,
                    ad: tk[i].s('name'),
                    deger: Bicim.para(tk[i].i('revenue_minor'), tam: true),
                    alt: '${Bicim.sayi(tk[i].i('qty'))} adet',
                    oran: tk[i].i('revenue_minor') / enCok,
                    renk: Marka.mavi,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  Widget _tumu(String anahtar) => TextButton(
    onPressed: () {
      final t = raporlar.firstWhere((e) => e.anahtar == anahtar);
      git(context, RaporEkrani(tanim: t, donem: _donem));
    },
    child: const Text('Tümü'),
  );

  List<Widget> _para(Map<String, dynamic> v, Widget Function(Widget) b) {
    final r = context.pa;
    final out = <Widget>[];
    final th = v.m('tahsilat');
    final kasa = v.m('kasa');
    if (th.isNotEmpty || kasa.isNotEmpty) {
      Widget kalem(String ad, int kurus, {bool kalin = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                ad,
                style: TextStyle(color: kalin ? r.metin : r.soluk, fontWeight: kalin ? FontWeight.w700 : FontWeight.w500, fontSize: 13.5),
              ),
            ),
            Text(
              Bicim.para(kurus),
              style: TextStyle(color: r.metin, fontWeight: kalin ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5),
            ),
          ],
        ),
      );
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BolumBasligi('Kasa ve tahsilat', ikon: Icons.point_of_sale_rounded),
                if (th.isNotEmpty) ...[
                  kalem('Tahsil edilen', th.i('total_minor'), kalin: true),
                  if (th.i('nakit_minor') > 0) kalem('  Nakit', th.i('nakit_minor')),
                  if (th.i('kart_minor') > 0) kalem('  Kart', th.i('kart_minor')),
                  if (th.i('eft_minor') > 0) kalem('  Havale / EFT', th.i('eft_minor')),
                  if (th.i('diger_minor') > 0) kalem('  Diğer', th.i('diger_minor')),
                  if (th.i('borc_minor') > 0) kalem('Borçtan tahsilat (${th.i('borc_count')})', th.i('borc_minor')),
                ],
                if (kasa.isNotEmpty) ...[
                  Divider(color: r.kenar, height: 18),
                  kalem('Kasada olması gereken nakit', kasa.i('beklenen_minor'), kalin: true),
                  if (kasa.i('devir_minor') != 0) kalem('  Devir', kasa.i('devir_minor')),
                  for (final k in kasa.l('kalemler')) kalem('  ${k.s('label')}', k.i('amount_minor')),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        kasa['saglama_tamam'] == false ? Icons.error_rounded : Icons.check_circle_rounded,
                        size: 17,
                        color: kasa['saglama_tamam'] == false ? r.eksi : r.arti,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${kasa['saglama_tamam'] == false ? 'Sağlama tutmuyor' : 'Sağlama tamam'} · ${kasa.i('acik_oturum')} açık kasa oturumu',
                          style: TextStyle(fontSize: 12.5, color: r.silik),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final gg = v.m('gelir_gider');
    if (gg.isNotEmpty) {
      final gelir = gg.m('gelir').i('toplam_minor');
      final gider = gg.i('gider_toplam_minor');
      final kalan = gg.i('kalan_minor');
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BolumBasligi('Gelir − gider', ikon: Icons.account_balance_rounded),
                Row(
                  children: [
                    Expanded(
                      child: _MiniDeger(ad: 'Gelir', deger: gelir, renk: r.arti),
                    ),
                    Expanded(
                      child: _MiniDeger(ad: 'Gider (${gg.i('gider_adet')})', deger: gider, renk: r.eksi),
                    ),
                    Expanded(
                      child: _MiniDeger(ad: 'Kalan', deger: kalan, renk: kalan < 0 ? r.eksi : r.metin),
                    ),
                  ],
                ),
                if (gelir > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 8,
                      child: Row(
                        children: [
                          Expanded(
                            flex: (gider.clamp(0, gelir)).toInt() + 1,
                            child: Container(color: r.eksi.withValues(alpha: .7)),
                          ),
                          Expanded(
                            flex: (gelir - gider).clamp(0, gelir).toInt() + 1,
                            child: Container(color: r.arti.withValues(alpha: .7)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    final debts = v.m('debts');
    final td = v.m('top_debtors');
    final rec = v.m('open').m('receivables');
    if (debts.b('enabled') || td.b('enabled') || rec.b('enabled')) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi(
                  'Borç / cari',
                  ikon: Icons.receipt_long_rounded,
                  sag: TextButton(
                    onPressed: () => git(context, BorclarEkrani(donem: _donem)),
                    child: const Text('Liste'),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _MiniDeger(
                        ad: 'Dönemde borca yazılan',
                        deger: debts.i('total_minor'),
                        alt: '${debts.i('count')} kayıt · ${debts.i('kisi')} kişi',
                      ),
                    ),
                    Expanded(
                      child: _MiniDeger(ad: 'Toplam açık borç', deger: rec.i('total_minor'), alt: '${rec.i('count')} kişi'),
                    ),
                  ],
                ),
                if (td.l('rows').isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'En çok borçlular',
                    style: TextStyle(fontSize: 12.5, color: r.silik, fontWeight: FontWeight.w600),
                  ),
                  for (var i = 0; i < td.l('rows').length; i++)
                    CubukSatir(
                      sira: i + 1,
                      ad: td.l('rows')[i].s('name'),
                      deger: Bicim.para(td.l('rows')[i].i('balance_minor'), tam: true),
                      oran: td.l('rows')[i].i('balance_minor') / math.max(1, td.l('rows').first.i('balance_minor')),
                      renk: Marka.kehribar,
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _ekipVeDiger(Map<String, dynamic> v, Widget Function(Widget) b, bool bugun) {
    final r = context.pa;
    final out = <Widget>[];
    final ms = v.l('on_shift');
    if (bugun) {
      out.add(
        b(
          PaKart(
            onTap: () => Kabuk.sekme.value = 2,
            etiket: '${ms.length} kişi mesaide. Ekip sekmesini aç',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi(
                  'Şu an mesaide',
                  ikon: Icons.badge_rounded,
                  sag: Text(
                    '${ms.length} kişi',
                    style: TextStyle(color: r.silik, fontWeight: FontWeight.w600),
                  ),
                ),
                if (ms.isEmpty)
                  Text('Mesaide kimse yok.', style: TextStyle(color: r.silik))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final p in ms.take(12))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: r.arti, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  p.s('name', '—'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: r.metin),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(Bicim.dakika(p.i('worked_minutes')), style: TextStyle(fontSize: 12, color: r.silik)),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final oi = v.m('open_items');
    if (bugun && oi.l('rows').isNotEmpty) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi(
                  'Açık masalarda bekleyen',
                  ikon: Icons.table_restaurant_rounded,
                  alt: '${Bicim.sayi(oi.i('qty'))} ürün · ${Bicim.para(oi.i('amount_minor'), tam: true)} (satışa dahil değil)',
                ),
                for (final x in oi.l('rows'))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            x.s('name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: r.metin, fontSize: 13.5),
                          ),
                        ),
                        Text('${Bicim.sayi(x.i('qty'))} × ', style: TextStyle(color: r.silik, fontSize: 12.5)),
                        Text(
                          Bicim.para(x.i('revenue_minor'), tam: true),
                          style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final sf = v.m('staff').l('rows');
    if (sf.isNotEmpty) {
      final enCok = sf.map((e) => e.i('sales_minor')).fold<int>(1, (a, b) => a > b ? a : b);
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi('Personel satışları', ikon: Icons.leaderboard_rounded, sag: _tumu('staff-performance')),
                for (var i = 0; i < sf.length; i++)
                  CubukSatir(
                    sira: i + 1,
                    ad: sf[i].m('user').s('name', '—'),
                    deger: Bicim.para(sf[i].i('sales_minor'), tam: true),
                    alt: '${sf[i].i('order_count')} adisyon',
                    oran: sf[i].i('sales_minor') / enCok,
                    renk: Marka.lavanta,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final inv = v.m('inventory');
    if (inv.l('rows').isNotEmpty) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi('Stok uyarıları', ikon: Icons.inventory_2_rounded, alt: '${inv.i('critical')} kritik · ${inv.i('low')} düşük'),
                for (final x in inv.l('rows'))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (x.s('severity') == 'critical' ? r.eksi : r.uyari).withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            x.s('severity') == 'critical' ? 'Kritik' : 'Düşük',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: x.s('severity') == 'critical' ? r.eksi : r.uyari),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(x.s('name'), style: TextStyle(color: r.metin, fontSize: 13.5)),
                        ),
                        Text('${x.s('on_hand')} / ${x.s('threshold')} ${x.s('unit')}', style: TextStyle(color: r.silik, fontSize: 12.5)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final tes = v.m('delivery');
    if (tes.isNotEmpty && tes.i('total') > 0) {
      out.add(
        b(
          PaKart(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BolumBasligi('Paket teslimat', ikon: Icons.delivery_dining_rounded, alt: '${tes.i('total')} paket'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (ad, k) in const [
                      ('Bekliyor', 'pending'),
                      ('Atandı', 'assigned'),
                      ('Yolda', 'on_the_way'),
                      ('Teslim', 'delivered'),
                      ('Başarısız', 'failed'),
                    ])
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap),
                        child: Text(
                          '$ad: ${tes.i(k)}',
                          style: TextStyle(fontSize: 13, color: k == 'failed' && tes.i(k) > 0 ? r.eksi : r.metin, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    final ig = v.m('is_gunu');
    if (ig.i('baslangic_saati') > 0) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            'İş günü saat ${ig.i('baslangic_saati').toString().padLeft(2, '0')}:00\'da başlar; gece yarısından sonraki satışlar önceki güne yazılır'
            '${ig.i('gece_minor') > 0 ? ' (bu dönemde ${Bicim.para(ig.i('gece_minor'), tam: true)})' : ''}.',
            style: TextStyle(fontSize: 12, color: r.silik),
          ),
        ),
      );
    }
    return out;
  }
}

class _MiniDeger extends StatelessWidget {
  const _MiniDeger({required this.ad, required this.deger, this.renk, this.alt});
  final String ad;
  final int deger;
  final Color? renk;
  final String? alt;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ad, style: TextStyle(color: r.silik, fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SayacMetin(
              deger: deger,
              yaz: (n) => Bicim.para(n, tam: true),
              stil: gosterim(17, renk: renk ?? r.metin),
            ),
          ),
          if (alt != null) Text(alt!, style: TextStyle(color: r.silik, fontSize: 11.5)),
        ],
      ),
    );
  }
}

/* ───────────────────────── Hedef kartı ───────────────────────── */

/// Önceki döneme (bugün için: dünün TÜM günü) ulaşma halkası + hız ve
/// gün sonu tahmini. Tahmin yalnız dünün saatlik verisi varsa yazılır:
/// "dün bu saatte günün %X'i yapılmıştı" oranıyla bugünkü ciro büyütülür.
class _HedefKarti extends StatelessWidget {
  const _HedefKarti({required this.v, required this.dun, required this.donem});
  final Map<String, dynamic> v;
  final Map<String, dynamic>? dun;
  final Donem donem;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final s = v.m('sales');
    final ciro = s.i('revenue_minor');
    final bugun = donem.tur == DonemTur.bugun;
    final dunToplam = dun?.m('sales').i('revenue_minor');
    final hedef = (bugun && dunToplam != null && dunToplam > 0) ? dunToplam : s.m('prev').i('revenue_minor');
    final oran = hedef <= 0 ? 0.0 : ciro / hedef;
    int? tahmin;
    if (bugun && dun != null && dunToplam != null && dunToplam > 0) {
      final bas = v.m('is_gunu').i('baslangic_saati');
      final simdi = (DateTime.now().hour - bas) % 24;
      final saat = {for (final h in dun!.l('by_hour')) h.i('hour'): h.i('revenue_minor')};
      var t = 0;
      for (var k = 0; k <= simdi; k++) {
        t += saat[(bas + k) % 24] ?? 0;
      }
      final pay = t / dunToplam;
      if (pay > .08 && ciro > 0) tahmin = (ciro / pay).round();
    }
    final kalan = hedef - ciro;
    Widget satir(IconData ikon, String ad, String deger, {Color? renk}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(ikon, size: 16, color: renk ?? r.birincil),
          const SizedBox(width: 8),
          Expanded(
            child: Text(ad, style: TextStyle(color: r.soluk, fontSize: 12.5)),
          ),
          Text(
            deger,
            style: TextStyle(color: renk ?? r.metin, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
    return PaKart(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BolumBasligi(
            bugun ? 'Düne göre ilerleme' : 'Önceki döneme göre',
            ikon: Icons.flag_rounded,
            alt: hedef > 0 ? 'Kıyas: ${Bicim.para(hedef, tam: true)}' : 'Kıyaslanacak satış yok',
          ),
          Row(
            children: [
              IlerlemeHalkasi(oran: oran, etiket: bugun ? 'dünkü ciroya' : 'önceki döneme', boyut: 118),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    if (hedef > 0)
                      kalan > 0
                          ? satir(Icons.more_horiz_rounded, 'Kalan', Bicim.para(kalan, tam: true))
                          : satir(Icons.emoji_events_rounded, 'Aşıldı', '+${Bicim.para(-kalan, tam: true)}', renk: r.arti),
                    satir(Icons.receipt_rounded, 'Ortalama adisyon', Bicim.para(s.i('avg_basket_minor'), tam: true)),
                    if (tahmin != null) satir(Icons.auto_graph_rounded, 'Gün sonu tahmini', '≈ ${Bicim.paraKisa(tahmin)}', renk: Marka.mavi),
                    if (v.m('operations').i('covers') > 0) satir(Icons.people_alt_rounded, 'Kuver', Bicim.sayi(v.m('operations').i('covers'))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────── KPI ızgarası ───────────────────────── */

class _KpiIzgara extends StatelessWidget {
  const _KpiIzgara({required this.v});
  final Map<String, dynamic> v;

  @override
  Widget build(BuildContext context) {
    final s = v.m('sales');
    final d = s.m('delta_pct');
    final ops = v.m('operations');
    final ind = v.m('discounts');
    final acik = v.m('open');
    final verilen = ind.i('discount_minor') + ind.i('iskonto_minor') + ind.i('comp_minor');
    final kartlar = <_Kpi>[
      _Kpi(
        'Adisyon',
        s.i('orders'),
        Bicim.sayi,
        Icons.receipt_rounded,
        degisim: d.d('orders'),
        alt: ops.d('table_turnover') != null ? 'Masa devri ${Bicim.ondalik(ops.d('table_turnover'))}' : null,
      ),
      _Kpi('Ortalama adisyon', s.i('avg_basket_minor'), (n) => Bicim.para(n, tam: true), Icons.functions_rounded, degisim: d.d('avg_basket')),
      _Kpi(
        'Kuver',
        ops.i('covers'),
        Bicim.sayi,
        Icons.people_alt_rounded,
        alt: ops['revenue_per_guest_minor'] is num ? 'Kişi başı ${Bicim.para(ops.i('revenue_per_guest_minor'), tam: true)}' : null,
      ),
      _Kpi(
        'İptal',
        s.i('cancelled_orders'),
        Bicim.sayi,
        Icons.cancel_rounded,
        alt: ops.d('cancellation_rate') != null ? 'Oran ${Bicim.yuzde(ops.d('cancellation_rate'))}' : null,
        kotu: s.i('cancelled_orders') > 0,
      ),
      _Kpi(
        'İndirim + ikram',
        verilen,
        (n) => Bicim.para(n, tam: true),
        Icons.local_offer_rounded,
        alt: '${ind.i('discount_orders') + ind.i('iskonto_orders')} indirim · ${ind.i('comp_orders')} ikram',
      ),
      _Kpi(
        'Açık masa',
        acik.i('open_tables'),
        Bicim.sayi,
        Icons.table_restaurant_rounded,
        alt: '${acik.i('open_orders')} adisyon · ${Bicim.para(acik.i('open_amount_minor'), tam: true)}',
      ),
      if (ops.d('avg_service_min') != null) _Kpi('Ort. servis süresi', ops.i('avg_service_min'), (n) => Bicim.dakika(n), Icons.timer_rounded),
      if (ops.d('qr_share') != null && ops.i('qr_orders') > 0)
        _Kpi('QR sipariş', ops.i('qr_orders'), Bicim.sayi, Icons.qr_code_rounded, alt: 'Pay ${Bicim.yuzde(ops.d('qr_share'))}'),
    ];
    return LayoutBuilder(
      builder: (_, k) {
        final sutun = k.maxWidth >= 640
            ? 4
            : k.maxWidth >= 440
            ? 3
            : 2;
        const ara = 10.0;
        final w = (k.maxWidth - ara * (sutun - 1)) / sutun;
        return Wrap(
          spacing: ara,
          runSpacing: ara,
          children: [for (final x in kartlar) SizedBox(width: w, child: _KpiKart(x))],
        );
      },
    );
  }
}

class _Kpi {
  const _Kpi(this.ad, this.deger, this.yaz, this.ikon, {this.degisim, this.alt, this.kotu = false});
  final String ad;
  final num deger;
  final String Function(num) yaz;
  final IconData ikon;
  final double? degisim;
  final String? alt;
  final bool kotu;
}

class _KpiKart extends StatelessWidget {
  const _KpiKart(this.k);
  final _Kpi k;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Semantics(
      container: true,
      label: '${k.ad}: ${k.yaz(k.deger)}${k.alt != null ? ', ${k.alt}' : ''}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 104),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: r.kart,
          borderRadius: Marka.yaricap,
          border: Border.all(color: r.kenar),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(k.ikon, size: 17, color: k.kotu ? r.eksi : r.birincil),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    k.ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: r.soluk, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SayacMetin(
                      deger: k.deger,
                      yaz: k.yaz,
                      stil: gosterim(22, renk: r.metin),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                DegisimRozeti(k.degisim),
              ],
            ),
            if (k.alt != null) ...[
              const SizedBox(height: 4),
              Text(
                k.alt!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: r.silik, fontSize: 11.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/* ───────────────────────── Durum akışı ───────────────────────── */

class _DurumAkisi extends StatelessWidget {
  const _DurumAkisi(this.akis);
  final List<Icgoru> akis;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    Color renk(IcgoruTur t) => switch (t) {
      IcgoruTur.iyi => r.arti,
      IcgoruTur.kotu => r.eksi,
      IcgoruTur.uyari => r.uyari,
      IcgoruTur.bilgi => r.birincil,
    };
    return PaKart(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BolumBasligi('Durum akışı', ikon: Icons.bolt_rounded, alt: 'Verilerden çıkan kısa notlar'),
          for (var i = 0; i < akis.length; i++)
            Belirme(
              sira: i,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: renk(akis[i].tur).withValues(alpha: r.koyu ? .2 : .1),
                        borderRadius: Marka.yaricap,
                      ),
                      child: Icon(akis[i].ikon, size: 17, color: renk(akis[i].tur)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(akis[i].metin, style: TextStyle(color: r.metin, fontSize: 13.5, height: 1.35)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/* ───────────────────────── Bugün yapılacaklar ───────────────────────── */

class _BugunGorevler extends StatelessWidget {
  const _BugunGorevler(this.gorevler);
  final List<Map<String, dynamic>> gorevler;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final simdi = DateTime.now();
    final bugunSonu = DateTime(simdi.year, simdi.month, simdi.day, 23, 59, 59);
    final liste = gorevler.where((t) {
      if (t.s('status') == 'done') return false;
      final d = DateTime.tryParse(t.s('due_at'))?.toLocal();
      return d != null && !d.isAfter(bugunSonu);
    }).toList()..sort((a, b) => a.s('due_at').compareTo(b.s('due_at')));
    return PaKart(
      onTap: () => git(context, const GorevlerEkrani(suzgec: GorevSuzgec.bugun)),
      etiket: 'Bugün yapılacaklar, ${liste.length} görev. Görevleri aç',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BolumBasligi(
            'Bugün yapılacaklar',
            ikon: Icons.checklist_rounded,
            sag: Text(
              '${liste.length}',
              style: TextStyle(color: r.silik, fontWeight: FontWeight.w700),
            ),
          ),
          if (liste.isEmpty)
            Text('Bugün için bekleyen görev yok.', style: TextStyle(color: r.silik))
          else
            for (final t in liste.take(6))
              Builder(
                builder: (_) {
                  final d = DateTime.tryParse(t.s('due_at'))!.toLocal();
                  final gecti = d.isBefore(simdi);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(
                          t.s('status') == 'in_progress' ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: t.s('priority') == 'high' ? r.eksi : r.birincil,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.s('title'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                              Text(t.m('assigned_to').s('name', 'Atanmamış'), style: TextStyle(color: r.silik, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(
                          gecti ? 'Gecikti · ${Bicim.saat(d)}' : Bicim.saat(d),
                          style: TextStyle(color: gecti ? r.eksi : r.silik, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

/* ───────────────────────── Yükleme iskeleti ───────────────────────── */

class _OzetIskelet extends StatelessWidget {
  const _OzetIskelet();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Iskelet(yukseklik: 140),
      const SizedBox(height: 14),
      Row(
        children: const [
          Expanded(child: Iskelet(yukseklik: 100)),
          SizedBox(width: 10),
          Expanded(child: Iskelet(yukseklik: 100)),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: const [
          Expanded(child: Iskelet(yukseklik: 100)),
          SizedBox(width: 10),
          Expanded(child: Iskelet(yukseklik: 100)),
        ],
      ),
      const SizedBox(height: 14),
      const Iskelet(yukseklik: 200),
    ],
  );
}
