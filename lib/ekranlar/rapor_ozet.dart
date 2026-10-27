import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../app/hareket.dart';
import '../ortak/donem.dart';

/// RAPORLAR › ÖZET — web paneldeki /panel/raporlar Özet görünümünün
/// (resources/js/Pages/Panel/Reports/tabs/OzetTab.vue, 2026-10-27 referans
/// düzeni) BİREBİR eşi. POS uygulaması da aynı tanımla çizer.
///
///   1) 10 sade rakam kutusu — sıra SABİT: Açık Masa Tutarı, Toplam Ürün
///      Adedi, Toplam Ürün Tutarı, İkram Tutarı, İptal - İade Adedi, İptal -
///      İade Tutarı, İndirim Tutarı, Ödeme Adedi, Ödeme Tutarı, Borca Yazılan.
///      Kutu = kalın etiket + soluk değer; renk/simge/alt açıklama YOK.
///   2) Tek kapta iki tablo: "Oran | Kategori | Adet | Fiyat" ve
///      "Oran | Ödeme Tipi | Adet | Fiyat" — tüm satırlar, tutara göre sıralı.
///   3) Dönemde borca yazılan varsa "Borca Yazdıranlar" tablosu.
/// Grafik YOK (saatlik/günlük ciro: Satış raporları). Uçlar: finance-summary ·
/// sales-open-items · sales-categories · finance-collected · borca-yazilanlar.
class RaporOzeti extends StatefulWidget {
  const RaporOzeti({super.key, required this.donem});
  final Donem donem;
  @override
  State<RaporOzeti> createState() => _RaporOzetiState();
}

class _RaporOzetiState extends State<RaporOzeti> {
  final Map<String, Map<String, dynamic>?> _v = {};
  Object? _hata;
  bool _yukleniyor = true;
  int _istek = 0;

  static const _uclar = ['finance-summary', 'sales-open-items', 'sales-categories', 'finance-collected'];

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void didUpdateWidget(RaporOzeti eski) {
    super.didUpdateWidget(eski);
    if (eski.donem != widget.donem) _yukle();
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    final d = widget.donem;
    Object? ilkHata;
    Future<Map<String, dynamic>?> cek(String k) async {
      try {
        final r = await Uyg.api.get('/api/v1/reports/$k', sorgu: d.raporSorgu, zamanAsimi: const Duration(seconds: 60));
        return r is Map ? r.m('data') : null;
      } on ApiHata catch (e) {
        ilkHata ??= e;
        return null;
      }
    }

    // Bu uç veriyi `data` sarmalı olmadan döner; cari kapalıysa 404 → sıfır.
    Future<Map<String, dynamic>?> borc() async {
      try {
        final r = await Uyg.api.get('/api/v1/reports/borca-yazilanlar', sorgu: {'from': Bicim.iso(d.bas), 'to': Bicim.iso(d.son)});
        return r is Map ? Map<String, dynamic>.from(r) : null;
      } on ApiHata {
        return null;
      }
    }

    final sonuc = await Future.wait([..._uclar.map(cek), borc()]);
    if (!mounted || no != _istek) return;
    setState(() {
      for (var i = 0; i < _uclar.length; i++) {
        _v[_uclar[i]] = sonuc[i];
      }
      _v['borca'] = sonuc.last;
      _hata = ilkHata;
      _yukleniyor = false;
    });
  }

  static String _adet(int n) => '${Bicim.sayi(n)} Adet';

  /// "%26,20" — referanstaki biçim.
  static String _oran(double p) => '%${(p * 100).toStringAsFixed(2).replaceAll('.', ',')}';

  List<(String, int, int, double)> _oranla(List<(String, int, int)> satirlar) {
    final toplam = satirlar.fold<int>(0, (a, x) => a + x.$3);
    final s = [...satirlar]..sort((a, b) => b.$3.compareTo(a.$3));
    return [for (final x in s) (x.$1, x.$2, x.$3, toplam > 0 ? x.$3 / toplam : 0.0)];
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final f = _v['finance-summary'];
    final ilk = _yukleniyor && f == null;
    final fs = f ?? const <String, dynamic>{};
    final acik = _v['sales-open-items'] ?? const {};
    final kat = _v['sales-categories'] ?? const {};
    final tah = _v['finance-collected'] ?? const {};
    final borca = _v['borca'];
    final borcVar = borca != null && borca['enabled'] != false && borca.i('count') > 0;

    final kutular = <(String, String)>[
      ('Açık Masa Tutarı', Bicim.para(acik.i('amount_minor'))),
      ('Toplam Ürün Adedi', _adet(kat.l('rows').fold<int>(0, (a, x) => a + x.i('qty')))),
      ('Toplam Ürün Tutarı', Bicim.para(fs.i('items_total_minor'))),
      ('İkram Tutarı', Bicim.para(fs.i('comp_minor'))),
      ('İptal - İade Adedi', _adet(fs.i('cancelled_orders') + fs.i('refund_payments_count'))),
      ('İptal - İade Tutarı', Bicim.para(fs.i('cancelled_minor') + fs.i('refund_payments_minor'))),
      ('İndirim Tutarı', Bicim.para(fs.i('discount_total_minor'))),
      ('Ödeme Adedi', _adet(fs.i('collected_count'))),
      ('Ödeme Tutarı', Bicim.para(fs.i('collected_minor'))),
      ('Borca Yazılan', '${Bicim.para(borca?.i('total_minor') ?? 0)} · ${Bicim.sayi(borca?.i('count') ?? 0)} adisyon'),
    ];
    final kategori = _oranla([for (final x in kat.l('rows')) (x.s('name'), x.i('qty'), x.i('revenue_minor'))]);
    final odeme = _oranla([for (final x in tah.l('rows')) (x.s('label'), x.i('count'), x.i('amount_minor'))]);

    var sira = 0;
    Widget b(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Belirme(sira: sira++, child: w));
    return AnimatedOpacity(
      opacity: _yukleniyor && !ilk ? .55 : 1,
      duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_hata != null)
          b(Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: r.kart,
              borderRadius: Marka.yaricap,
              border: Border(left: BorderSide(color: r.eksi, width: 3), top: BorderSide(color: r.kenar), right: BorderSide(color: r.kenar), bottom: BorderSide(color: r.kenar)),
            ),
            child: Row(children: [
              Expanded(child: Text(_hata is ApiHata ? (_hata as ApiHata).mesaj : 'Rapor yüklenemedi.', style: TextStyle(color: r.eksi, fontWeight: FontWeight.w700))),
              TextButton(onPressed: _yukle, child: const Text('Yenile')),
            ]),
          )),
        // ═══ RAKAM KUTULARI (telefonda 2'li, genişte 5'li) ═══
        b(LayoutBuilder(builder: (_, k) {
          final sutun = k.maxWidth >= 600 ? 5 : 2;
          final w = (k.maxWidth - 8 * (sutun - 1)) / sutun;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (ad, deger) in kutular)
              Semantics(
                label: '$ad: ${ilk ? 'yükleniyor' : deger}',
                excludeSemantics: true,
                child: Container(
                  width: w,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(ilk ? '—' : deger,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: r.soluk, fontSize: 13.5, fontFeatures: const [FontFeature.tabularFigures()])),
                  ]),
                ),
              ),
          ]);
        })),
        // ═══ ORAN TABLOLARI (tek kap; genişte yan yana, telefonda alt alta) ═══
        b(_Kap(
          child: LayoutBuilder(builder: (_, k) {
            final kt = _Tablo(basliklar: const ['Oran', 'Kategori', 'Adet', 'Fiyat'], satirlar: [for (final x in kategori) [_oran(x.$4), x.$1, _adet(x.$2), Bicim.para(x.$3)]]);
            final od = _Tablo(basliklar: const ['Oran', 'Ödeme Tipi', 'Adet', 'Fiyat'], satirlar: [for (final x in odeme) [_oran(x.$4), x.$1, _adet(x.$2), Bicim.para(x.$3)]]);
            if (k.maxWidth >= 600) {
              return IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: kt),
                  VerticalDivider(width: 1, thickness: 1, color: r.kenar),
                  Expanded(child: od),
                ]),
              );
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [kt, Divider(height: 1, thickness: 1, color: r.kenar), od]);
          }),
        )),
        // ═══ BORCA YAZDIRANLAR (yalnız dönemde varsa) ═══
        if (borcVar)
          b(_Kap(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: r.kenar))),
                child: Semantics(header: true, child: Text('Borca Yazdıranlar', style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13.5))),
              ),
              _Tablo(
                basliklar: const ['Kişi', 'Adisyon', 'Tutar'],
                oranVar: false,
                satirlar: [for (final x in borca.l('kisiler')) [x.s('name'), Bicim.sayi(x.i('count')), Bicim.para(x.i('amount_minor'))]],
              ),
            ]),
          )),
      ]),
    );
  }
}

class _Kap extends StatelessWidget {
  const _Kap({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: context.pa.kart, borderRadius: Marka.yaricap, border: Border.all(color: context.pa.kenar)),
        child: child,
      );
}

/// Sade tablo: başlık satırı + saç teli çizgili satırlar (web .oz-tbl).
/// [oranVar]: ilk sütun "Oran" (dar), ikinci ad (geniş), kalanlar sağa yaslı.
class _Tablo extends StatelessWidget {
  const _Tablo({required this.basliklar, required this.satirlar, this.oranVar = true});
  final List<String> basliklar;
  final List<List<String>> satirlar;
  final bool oranVar;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final adSutunu = oranVar ? 1 : 0;
    Widget satir(List<String> h, {bool baslik = false, bool son = false}) {
      final stil = TextStyle(
        color: r.metin,
        fontSize: 13,
        fontWeight: baslik ? FontWeight.w600 : FontWeight.w400,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(border: son ? null : Border(bottom: BorderSide(color: r.kenar))),
        child: Row(children: [
          for (var i = 0; i < h.length; i++)
            if (i == adSutunu)
              Expanded(child: Padding(padding: const EdgeInsets.only(right: 8), child: Text(h[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: stil)))
            else
              SizedBox(
                width: oranVar && i == 0 ? 62 : (i == h.length - 1 ? 96 : 68),
                child: Text(h[i], maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: i == 0 && oranVar ? TextAlign.left : TextAlign.right, style: stil),
              ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      satir(basliklar, baslik: true),
      if (satirlar.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text('Bu dönemde kayıt yok', textAlign: TextAlign.center, style: TextStyle(color: r.silik, fontSize: 13)),
        )
      else
        for (final (i, s) in satirlar.indexed) satir(s, son: i == satirlar.length - 1),
    ]);
  }
}
