import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'giderler_ekrani.dart' show aralikEtiketi, isGunuAraligi;
import 'ortak.dart';

/// RAPORLAR (2026-10-27) — web /panel/raporlar'ın uygulama eşi.
///
/// İşletme bildirimi: "webde raporlar var, uygulamada yok". Veriler web ile
/// AYNI uçlardan (/api/v1/reports/{rapor}) gelir; hesap sunucudadır, istemci
/// yalnız gösterir. "Bugün" takvim günü değil işletmenin AÇIK İŞ GÜNÜdür
/// (/api/v1/reports/eod/durum). İzin: reports.view (sunucu ayrıca denetler).
///
/// Performans: rapor yalnız seçilince çekilir, sonuç dönem+rapor anahtarıyla
/// bellekte tutulur (sekmeler arasında gidip gelince yeniden istek yok);
/// listeler ListView.builder ile tembel çizilir. Grafikler tek CustomPainter.

String _tl(int m) => '${m < 0 ? '-' : ''}₺${para(m.abs(), simge: false)}';
String _sayi(Object? v) {
  final n = v is num ? v : num.tryParse('$v') ?? 0;
  if (n == n.roundToDouble()) {
    final s = n.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return '${n < 0 ? '-' : ''}$b';
  }
  return n.toStringAsFixed(1).replaceAll('.', ',');
}

String _yuzde(Object? v) {
  final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  return '%${n.toStringAsFixed(n.abs() >= 10 ? 0 : 1).replaceAll('.', ',')}';
}

List<Map<String, dynamic>> _liste(Object? v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
Map<String, dynamic> _harita(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// Sütun türü: para (kuruş), sayı, yüzde, metin, saat.
enum _Tur { para, sayi, yuzde, metin, saat }

class _Sutun {
  const _Sutun(this.anahtar, this.ad, [this.tur = _Tur.metin]);
  final String anahtar;
  final String ad;
  final _Tur tur;

  String yaz(Object? v) => switch (tur) {
        _Tur.para => _tl(tamSayi(v)),
        _Tur.sayi => _sayi(v),
        _Tur.yuzde => _yuzde(v),
        _Tur.saat => saatMetni(v?.toString()),
        _Tur.metin => (v == null || '$v'.isEmpty) ? '—' : '$v',
      };
}

/// Tablo raporu tanımı: hangi uç, satırlar hangi anahtarda, sütunlar.
class _Tablo {
  const _Tablo(this.uc, this.sutunlar, {this.grafik});
  final String uc;
  String get satirAnahtari => 'rows';
  final List<_Sutun> sutunlar;

  /// Yatay çubuk grafiği için (etiket sütunu, değer sütunu).
  final (String, String)? grafik;
}

class _Rapor {
  const _Rapor(this.anahtar, this.ad, this.ikon, {this.tablo});
  final String anahtar;
  final String ad;
  final IconData ikon;
  final _Tablo? tablo;
}

const _raporlar = <_Rapor>[
  _Rapor('ozet', 'Özet', Icons.dashboard_outlined),
  _Rapor('kategoriler', 'Kategoriler', Icons.category_outlined,
      tablo: _Tablo('sales-categories', [
        _Sutun('name', 'Kategori'),
        _Sutun('qty', 'Adet', _Tur.sayi),
        _Sutun('orders', 'Sipariş', _Tur.sayi),
        _Sutun('revenue_minor', 'Ciro', _Tur.para),
      ], grafik: ('name', 'revenue_minor'))),
  _Rapor('urunler', 'Ürünler', Icons.inventory_2_outlined,
      tablo: _Tablo('sales-products', [
        _Sutun('name', 'Ürün'),
        _Sutun('qty', 'Adet', _Tur.sayi),
        _Sutun('orders', 'Sipariş', _Tur.sayi),
        _Sutun('revenue_minor', 'Ciro', _Tur.para),
      ])),
  _Rapor('masalar', 'Masalar', Icons.table_restaurant_outlined,
      tablo: _Tablo('sales-tables', [
        _Sutun('name', 'Masa'),
        _Sutun('orders', 'Sipariş', _Tur.sayi),
        _Sutun('turns', 'Devir', _Tur.sayi),
        _Sutun('avg_minutes', 'Ort. süre (dk)', _Tur.sayi),
        _Sutun('revenue_minor', 'Ciro', _Tur.para),
      ], grafik: ('name', 'revenue_minor'))),
  _Rapor('odemeler', 'Ödemeler', Icons.payments_outlined,
      tablo: _Tablo('finance-payment-methods', [
        _Sutun('label', 'Yöntem'),
        _Sutun('count', 'İşlem', _Tur.sayi),
        _Sutun('share', 'Pay', _Tur.yuzde),
        _Sutun('amount_minor', 'Tutar', _Tur.para),
        _Sutun('tips_minor', 'Bahşiş', _Tur.para),
      ], grafik: ('label', 'amount_minor'))),
  _Rapor('indirimler', 'İndirim', Icons.percent_rounded,
      tablo: _Tablo('finance-discounts', [
        _Sutun('order_id', 'Adisyon', _Tur.metin),
        _Sutun('table', 'Masa'),
        _Sutun('date', 'Tarih'),
        _Sutun('items_total_minor', 'Ürünler', _Tur.para),
        _Sutun('discount_minor', 'İndirim', _Tur.para),
        _Sutun('iskonto_minor', 'İskonto', _Tur.para),
        _Sutun('total_minor', 'Toplam', _Tur.para),
        _Sutun('reason', 'Neden'),
        _Sutun('discount_by', 'Yapan'),
      ])),
  _Rapor('iptaller', 'İptaller', Icons.cancel_outlined,
      tablo: _Tablo('sales-cancellations', [
        _Sutun('name', 'Ürün'),
        _Sutun('table', 'Masa'),
        _Sutun('qty', 'Adet', _Tur.sayi),
        _Sutun('amount_minor', 'Tutar', _Tur.para),
        _Sutun('reason', 'Neden'),
        _Sutun('cancelled_by', 'İptal eden'),
        _Sutun('time', 'Saat'),
      ])),
  _Rapor('karlilik', 'Kârlılık', Icons.trending_up_rounded,
      tablo: _Tablo('product-profitability', [
        _Sutun('name', 'Ürün'),
        _Sutun('qty', 'Adet', _Tur.sayi),
        _Sutun('revenue_minor', 'Ciro', _Tur.para),
        _Sutun('cost_minor', 'Maliyet', _Tur.para),
        _Sutun('profit_minor', 'Brüt kâr', _Tur.para),
        _Sutun('margin', 'Marj', _Tur.yuzde),
      ])),
  _Rapor('personel', 'Personel', Icons.badge_outlined,
      tablo: _Tablo('staff-performance', [
        _Sutun('name', 'Personel'),
        _Sutun('orders', 'Adisyon', _Tur.sayi),
        _Sutun('items', 'Kalem', _Tur.sayi),
        _Sutun('sales_minor', 'Satış', _Tur.para),
        _Sutun('avg_basket_minor', 'Ort. sepet', _Tur.para),
        _Sutun('discount_minor', 'İndirim', _Tur.para),
        _Sutun('comp_minor', 'İkram', _Tur.para),
        _Sutun('cancelled', 'İptal', _Tur.sayi),
      ], grafik: ('name', 'sales_minor'))),
  _Rapor('kasa', 'Kasa oturumları', Icons.point_of_sale_outlined,
      tablo: _Tablo('finance-cash-sessions', [
        _Sutun('z_number', 'Z No'),
        _Sutun('register', 'Kasa'),
        _Sutun('opened_by', 'Açan'),
        _Sutun('opened_at', 'Açılış', _Tur.saat),
        _Sutun('closed_at', 'Kapanış', _Tur.saat),
        _Sutun('expected_minor', 'Beklenen', _Tur.para),
        _Sutun('counted_minor', 'Sayılan', _Tur.para),
        _Sutun('difference_minor', 'Fark', _Tur.para),
      ])),
];

const _hazirlar = [('bugun', 'Bugün'), ('dun', 'Dün'), ('hafta', '7 gün'), ('otuz', '30 gün'), ('ay', 'Bu ay'), ('ozel', 'Tarih seç')];

class RaporlarEkrani extends StatefulWidget {
  const RaporlarEkrani({super.key});

  @override
  State<RaporlarEkrani> createState() => _RaporlarEkraniState();
}

class _RaporlarEkraniState extends State<RaporlarEkrani> {
  late final Api _api = context.api;

  String _hazir = 'bugun';
  String _bugun = '';
  String? _dun;
  String _from = '';
  String _to = '';
  int _secili = 0;
  int _yon = 1;

  /// "dönem|rapor" → yanıt. Dönem değişince boşaltılır.
  final Map<String, Map<String, dynamic>> _bellek = {};
  final Set<String> _yukleniyor = {};
  final Map<String, String> _hatalar = {};

  @override
  void initState() {
    super.initState();
    final b = DateTime.now();
    _bugun = '${b.year}-${b.month.toString().padLeft(2, '0')}-${b.day.toString().padLeft(2, '0')}';
    _from = _to = _bugun;
    _isGunuOku();
  }

  Future<void> _isGunuOku() async {
    try {
      final d = _harita(await _api.get('/api/v1/reports/eod/durum'));
      final g = '${d['is_gunu'] ?? ''}';
      if (g.length >= 10) _bugun = g.substring(0, 10);
      final dun = _harita(d['son_kapanis'])['is_gunu'];
      _dun = dun == null ? null : '$dun'.substring(0, math.min(10, '$dun'.length));
    } on ApiHata {
      // takvim günüyle devam
    }
    if (!mounted) return;
    _hazirSec(_hazir);
  }

  void _hazirSec(String h) {
    if (h == 'ozel') {
      _ozelSec();
      return;
    }
    final a = isGunuAraligi(h, _bugun, _dun);
    if (a == null) return;
    setState(() {
      _hazir = h;
      _from = a.$1;
      _to = a.$2;
      _bellek.clear();
      _hatalar.clear();
    });
    _yukle();
  }

  Future<void> _ozelSec() async {
    DateTime ayir(String s) => DateTime.tryParse(s) ?? DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: ayir(_from), end: ayir(_to)),
      locale: const Locale('tr', 'TR'),
      helpText: 'Rapor dönemi',
      saveText: 'Uygula',
    );
    if (r == null || !mounted) return;
    String gun(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    setState(() {
      _hazir = 'ozel';
      _from = gun(r.start);
      _to = gun(r.end);
      _bellek.clear();
      _hatalar.clear();
    });
    _yukle();
  }

  String get _donem => '$_from|$_to';

  /// Seçili raporun ihtiyaç duyduğu uçlar.
  List<String> _uclar(_Rapor r) => r.tablo != null ? [r.tablo!.uc] : const ['sales-summary', 'sales-hourly', 'sales-daily', 'finance-payment-methods', 'sales-categories'];

  Future<void> _yukle({bool zorla = false}) async {
    final r = _raporlar[_secili];
    final donem = _donem;
    await Future.wait(_uclar(r).map((uc) async {
      final k = '$donem|$uc';
      if (!zorla && (_bellek.containsKey(k) || _yukleniyor.contains(k))) return;
      setState(() {
        _yukleniyor.add(k);
        _hatalar.remove(k);
      });
      try {
        final v = await _api.get('/api/v1/reports/$uc', sorgu: {'from': _from, 'to': _to});
        final veri = v is Map && v['data'] is Map ? _harita(v['data']) : _harita(v);
        if (mounted && donem == _donem) setState(() => _bellek[k] = veri);
      } on ApiHata catch (e) {
        if (mounted && donem == _donem) setState(() => _hatalar[k] = e.kod == 403 ? 'Bu raporu görme yetkiniz yok.' : e.mesaj);
      } finally {
        if (mounted) setState(() => _yukleniyor.remove(k));
      }
    }));
  }

  void _raporSec(int i) {
    if (i == _secili) return;
    setState(() {
      _yon = i > _secili ? 1 : -1;
      _secili = i;
    });
    _yukle();
  }

  Map<String, dynamic>? _veri(String uc) => _bellek['$_donem|$uc'];
  bool _bekliyor(String uc) => _yukleniyor.contains('$_donem|$uc');
  String? _hata(String uc) => _hatalar['$_donem|$uc'];

  /* ───────────────────────── görünüm ───────────────────────── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final dar = g < 700;
    final r = _raporlar[_secili];
    return ColoredBox(
      color: Kabuk.sunken,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13, color: Kabuk.ink),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(dar ? 12 : 18, 10, dar ? 12 : 18, 0),
            child: Row(children: [
              const Text('Raporlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.36)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(aralikEtiketi(_from, _to),
                    overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Kabuk.soft, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                tooltip: 'Yenile',
                onPressed: () => _yukle(zorla: true),
                icon: Icon(Icons.refresh_rounded, color: Kabuk.soft),
              ),
            ]),
          ),
          _cipSatiri(
            [for (final (k, e) in _hazirlar) (e, _hazir == k, () => _hazirSec(k), null)],
            dar,
          ),
          const SizedBox(height: 6),
          _cipSatiri(
            [for (var i = 0; i < _raporlar.length; i++) (_raporlar[i].ad, _secili == i, () => _raporSec(i), _raporlar[i].ikon)],
            dar,
            rapor: true,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: EkranGecisi(
              anahtar: r.anahtar,
              yon: _yon,
              child: RefreshIndicator(
                onRefresh: () => _yukle(zorla: true),
                child: r.tablo == null ? _ozet(dar) : _tablo(r.tablo!, dar),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _cipSatiri(List<(String, bool, VoidCallback, IconData?)> ogeler, bool dar, {bool rapor = false}) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: dar ? 12 : 18),
        itemCount: ogeler.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (ad, secili, bas, ikon) = ogeler[i];
          final renk = secili ? (rapor ? Kabuk.brand : Renk.marka) : Kabuk.ink;
          return Semantics(
            selected: secili,
            button: true,
            child: Material(
              color: secili ? renk : Renk.yuzey,
              borderRadius: koseYuvarlak,
              child: InkWell(
                borderRadius: koseYuvarlak,
                onTap: bas,
                child: AnimatedContainer(
                  duration: Hareket.kisa,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: secili ? renk : Kabuk.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (ikon != null) ...[Icon(ikon, size: 16, color: secili ? Colors.white : Kabuk.soft), const SizedBox(width: 6)],
                    Text(ad, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: secili ? Colors.white : Kabuk.ink)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _durum(String uc, Widget Function(Map<String, dynamic>) ciz) {
    final v = _veri(uc);
    final h = _hata(uc);
    if (v != null) return ciz(v);
    if (h != null) {
      return _bosKutu(Icons.error_outline_rounded, h, eylem: () => _yukle(zorla: true));
    }
    if (_bekliyor(uc)) {
      return const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)));
    }
    return const SizedBox(height: 40);
  }

  Widget _bosKutu(IconData ikon, String metin, {VoidCallback? eylem}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(children: [
          Icon(ikon, size: 34, color: Kabuk.soft),
          const SizedBox(height: 8),
          Text(metin, textAlign: TextAlign.center, style: TextStyle(color: Kabuk.soft, fontWeight: FontWeight.w600)),
          if (eylem != null) ...[const SizedBox(height: 10), TextButton(onPressed: eylem, child: const Text('Tekrar dene'))],
        ]),
      );

  Widget _kart({required Widget child, String? baslik, EdgeInsets? ic}) => Container(
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        padding: ic ?? const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (baslik != null) ...[Text(baslik, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), const SizedBox(height: 10)],
          child,
        ]),
      );

  /* ── ÖZET ── */

  Widget _ozet(bool dar) {
    final p = EdgeInsets.fromLTRB(dar ? 12 : 18, 0, dar ? 12 : 18, 24);
    return ListView(padding: p, physics: const AlwaysScrollableScrollPhysics(), children: [
      _durum('sales-summary', (v) {
        final c = _harita(v['current']);
        final o = _harita(v['previous']);
        final iptal = _harita(v['cancelled']);
        double? fark(String k) {
          final a = tamSayi(c[k]), b = tamSayi(o[k]);
          return b == 0 ? null : (a - b) / b * 100;
        }

        final kpi = [
          ('Ciro', _tl(tamSayi(c['revenue_minor'])), fark('revenue_minor'), Renk.basari),
          ('Adisyon', _sayi(c['orders']), fark('orders'), Kabuk.ink),
          ('Ortalama sepet', _tl(tamSayi(c['avg_basket_minor'])), fark('avg_basket_minor'), Kabuk.ink),
          ('Misafir', _sayi(c['guests']), fark('guests'), Kabuk.ink),
          ('İptal', '${_sayi(iptal['orders'])} · ${_tl(tamSayi(iptal['total_minor']))}', null, Kabuk.negative),
        ];
        return LayoutBuilder(builder: (context, k) {
          final sutun = k.maxWidth >= 900 ? 5 : (k.maxWidth >= 520 ? 3 : 2);
          final gen = (k.maxWidth - (sutun - 1) * 8) / sutun;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < kpi.length; i++)
              SizedBox(
                width: gen,
                child: Belirme(
                  sira: i,
                  child: _kart(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(kpi[i].$1, style: TextStyle(fontSize: 12, color: Kabuk.soft, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(kpi[i].$2, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kpi[i].$4)),
                      ),
                      const SizedBox(height: 2),
                      _farkYazisi(kpi[i].$3),
                    ]),
                  ),
                ),
              ),
          ]);
        });
      }),
      const SizedBox(height: 10),
      _durum('sales-hourly', (v) {
        final saatler = _liste(v['hours']);
        final dolu = saatler.where((s) => tamSayi(s['revenue_minor']) > 0).toList();
        if (dolu.isEmpty) return _kart(baslik: 'Saatlik ciro', child: _bosKutu(Icons.bar_chart_rounded, 'Bu dönemde kapanan adisyon yok.'));
        final bas = tamSayi(dolu.first['hour']), bit = tamSayi(dolu.last['hour']);
        final aralik = saatler.where((s) => tamSayi(s['hour']) >= bas && tamSayi(s['hour']) <= bit).toList();
        return _kart(
          baslik: 'Saatlik ciro',
          child: _Cubuklar(
            etiketler: [for (final s in aralik) tamSayi(s['hour']).toString().padLeft(2, '0')],
            degerler: [for (final s in aralik) tamSayi(s['revenue_minor'])],
            renk: Kabuk.brand,
          ),
        );
      }),
      if (_from != _to) ...[
        const SizedBox(height: 10),
        _durum('sales-daily', (v) {
          final gunler = _liste(v['days']);
          if (gunler.length < 2) return const SizedBox();
          return _kart(
            baslik: 'Günlük ciro',
            child: _Cubuklar(
              etiketler: [for (final d in gunler) '${d['date']}'.length >= 10 ? '${d['date']}'.substring(8, 10) : '${d['date']}'],
              degerler: [for (final d in gunler) tamSayi(d['revenue_minor'])],
              renk: Renk.vurgu,
            ),
          );
        }),
      ],
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, k) {
        final yan = k.maxWidth >= 760;
        final odeme = _durum('finance-payment-methods', (v) {
          final s = _liste(v['rows']);
          return _kart(
            baslik: 'Ödeme dağılımı',
            child: s.isEmpty
                ? _bosKutu(Icons.payments_outlined, 'Bu dönemde tahsilat yok.')
                : _YatayCubuklar(satirlar: [for (final x in s) ('${x['label']}', tamSayi(x['amount_minor']))]),
          );
        });
        final kat = _durum('sales-categories', (v) {
          final s = _liste(v['rows'])..sort((a, b) => tamSayi(b['revenue_minor']).compareTo(tamSayi(a['revenue_minor'])));
          return _kart(
            baslik: 'Kategoriler',
            child: s.isEmpty
                ? _bosKutu(Icons.category_outlined, 'Bu dönemde ürün satışı yok.')
                : _YatayCubuklar(satirlar: [for (final x in s.take(8)) ('${x['name']}', tamSayi(x['revenue_minor']))]),
          );
        });
        return yan
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: odeme), const SizedBox(width: 10), Expanded(child: kat)])
            : Column(children: [odeme, const SizedBox(height: 10), kat]);
      }),
    ]);
  }

  Widget _farkYazisi(double? f) {
    if (f == null) return Text('önceki dönem: —', style: TextStyle(fontSize: 11, color: Kabuk.soft));
    final arti = f >= 0;
    return Row(children: [
      Icon(arti ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: arti ? Kabuk.success : Kabuk.negative),
      Flexible(
        child: Text(' ${_yuzde(f.abs())} önceki döneme göre',
            overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: arti ? Kabuk.success : Kabuk.negative, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  /* ── TABLO RAPORLARI ── */

  Widget _tablo(_Tablo t, bool dar) {
    final p = EdgeInsets.fromLTRB(dar ? 12 : 18, 0, dar ? 12 : 18, 24);
    final v = _veri(t.uc);
    if (v == null) {
      return ListView(padding: p, physics: const AlwaysScrollableScrollPhysics(), children: [_durum(t.uc, (_) => const SizedBox())]);
    }
    final satirlar = _liste(v[t.satirAnahtari]);
    if (satirlar.isEmpty) {
      return ListView(padding: p, physics: const AlwaysScrollableScrollPhysics(), children: [
        _kart(child: _bosKutu(Icons.inbox_outlined, 'Bu dönemde kayıt yok.')),
      ]);
    }
    final ozet = _ozetSatiri(t, v);
    final paraSutunlari = t.sutunlar.where((s) => s.tur == _Tur.para).toList();
    final ust = <Widget>[
      if (ozet != null) ...[ozet, const SizedBox(height: 10)],
      if (t.grafik != null && satirlar.length > 1) ...[
        _kart(
          child: _YatayCubuklar(
            satirlar: [for (final s in (List.of(satirlar)..sort((a, b) => tamSayi(b[t.grafik!.$2]).compareTo(tamSayi(a[t.grafik!.$2])))).take(8)) ('${s[t.grafik!.$1] ?? '—'}', tamSayi(s[t.grafik!.$2]))],
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];

    if (!dar) {
      // Geniş ekran: gerçek tablo (yatay kaydırmalı).
      return ListView(padding: p, physics: const AlwaysScrollableScrollPhysics(), children: [
        ...ust,
        _kart(
          ic: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 38,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 52,
              columnSpacing: 22,
              headingTextStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Kabuk.soft, letterSpacing: .3),
              dataTextStyle: TextStyle(fontSize: 13, color: Kabuk.ink),
              columns: [for (final s in t.sutunlar) DataColumn(label: Text(s.ad.toUpperCase()), numeric: s.tur != _Tur.metin && s.tur != _Tur.saat)],
              rows: [
                for (final r in satirlar)
                  DataRow(cells: [for (final s in t.sutunlar) DataCell(Text(s.yaz(r[s.anahtar]), style: s.tur == _Tur.para ? const TextStyle(fontWeight: FontWeight.w700) : null))]),
                if (paraSutunlari.isNotEmpty)
                  DataRow(
                    color: WidgetStatePropertyAll(Kabuk.sunken),
                    cells: [
                      for (var i = 0; i < t.sutunlar.length; i++)
                        DataCell(Text(
                          i == 0 ? 'Toplam' : (t.sutunlar[i].tur == _Tur.para || (t.sutunlar[i].tur == _Tur.sayi && t.sutunlar[i].anahtar != 'avg_minutes') ? t.sutunlar[i].yaz(satirlar.fold<num>(0, (a, r) => a + (num.tryParse('${r[t.sutunlar[i].anahtar] ?? 0}') ?? 0))) : ''),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ]);
    }

    // Telefon: her satır bir kart; ilk sütun başlık, para sütunu sağda büyük.
    final anaPara = paraSutunlari.isNotEmpty ? paraSutunlari.last : null;
    final digerleri = t.sutunlar.skip(1).where((s) => s != anaPara).toList();
    return ListView.builder(
      padding: p,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: ust.length + satirlar.length,
      itemBuilder: (_, i) {
        if (i < ust.length) return ust[i];
        final r = satirlar[i - ust.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Belirme(
            sira: i - ust.length,
            child: _kart(
              ic: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(t.sutunlar.first.yaz(r[t.sutunlar.first.anahtar]),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  if (anaPara != null)
                    Text(anaPara.yaz(r[anaPara.anahtar]), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: tamSayi(r[anaPara.anahtar]) < 0 ? Kabuk.negative : Kabuk.ink)),
                ]),
                if (digerleri.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    for (final s in digerleri)
                      if (r[s.anahtar] != null && '${r[s.anahtar]}'.isNotEmpty)
                        Text.rich(TextSpan(children: [
                          TextSpan(text: '${s.ad} ', style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
                          TextSpan(text: s.yaz(r[s.anahtar]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ])),
                  ]),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  /// Bazı raporların üst özet rakamları.
  Widget? _ozetSatiri(_Tablo t, Map<String, dynamic> v) {
    final List<(String, String)> ogeler = switch (t.uc) {
      'finance-payment-methods' => [('Toplam tahsilat', _tl(tamSayi(v['total_minor'])))],
      'finance-discounts' => () {
          final s = _harita(v['summary']);
          return [
            ('Toplam indirim', _tl(tamSayi(s['combined_minor']))),
            ('İndirimli adisyon', '${_sayi(s['discounted_orders'])} / ${_sayi(s['orders_count'])}'),
            ('İndirim oranı', _yuzde(s['discount_rate'])),
          ];
        }(),
      'sales-cancellations' => [
          ('İptal edilen kalem', _sayi(v['kalem'])),
          ('İptal tutarı', _tl(tamSayi(v['tutar_minor']))),
          ('Serviste sonra', _tl(tamSayi(v['servis_sonrasi_tutar_minor']))),
        ],
      'product-profitability' => [
          if (v['median_margin'] != null) ('Ortanca marj', _yuzde(v['median_margin'])),
          ('Maliyeti girilmemiş', '${_sayi(v['missing_cost_count'])} ürün'),
        ],
      _ => const [],
    };
    if (ogeler.isEmpty) return null;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (ad, deger) in ogeler)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(ad, style: TextStyle(fontSize: 11.5, color: Kabuk.soft, fontWeight: FontWeight.w600)),
            Text(deger, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
    ]);
  }
}

/* ───────────────────────── grafikler ───────────────────────── */

/// Dikey çubuk grafiği (saatlik/günlük). Tek CustomPainter, girişte bir kez
/// büyüyerek çizilir (yalnız boyama; yerleşim değişmez).
class _Cubuklar extends StatelessWidget {
  const _Cubuklar({required this.etiketler, required this.degerler, required this.renk});
  final List<String> etiketler;
  final List<int> degerler;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    final enCok = degerler.fold<int>(0, math.max);
    final tepe = degerler.indexOf(enCok);
    return Semantics(
      label: 'Grafik. En yüksek: ${etiketler.isEmpty ? '' : etiketler[tepe]} ${_tl(enCok)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('En yüksek: ${etiketler.isEmpty ? '' : etiketler[tepe]} · ${_tl(enCok)}', style: TextStyle(fontSize: 11.5, color: Kabuk.soft, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: Hareket.kapali(context) ? 1 : 0, end: 1),
            duration: Hareket.uzun,
            curve: Hareket.giris,
            builder: (_, t, _) => CustomPaint(
              painter: _CubukRessami(degerler: degerler, etiketler: etiketler, renk: renk, tepe: tepe, t: t, cizgi: Kabuk.line, yazi: Kabuk.soft),
              size: Size.infinite,
            ),
          ),
        ),
      ]),
    );
  }
}

class _CubukRessami extends CustomPainter {
  _CubukRessami({required this.degerler, required this.etiketler, required this.renk, required this.tepe, required this.t, required this.cizgi, required this.yazi});
  final List<int> degerler;
  final List<String> etiketler;
  final Color renk;
  final int tepe;
  final double t;
  final Color cizgi;
  final Color yazi;

  @override
  void paint(Canvas c, Size s) {
    if (degerler.isEmpty) return;
    const alt = 18.0;
    final h = s.height - alt;
    final enCok = math.max(1, degerler.fold<int>(0, math.max));
    final n = degerler.length;
    final adim = s.width / n;
    final gen = math.max(3.0, math.min(28.0, adim * .62));
    final kalem = Paint()..color = cizgi..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = h - h * i / 3;
      c.drawLine(Offset(0, y), Offset(s.width, y), kalem);
    }
    final etiketAdim = math.max(1, (n / math.max(1, s.width / 34)).ceil());
    for (var i = 0; i < n; i++) {
      final oran = degerler[i] / enCok * t;
      final x = adim * i + (adim - gen) / 2;
      final yuk = math.max(degerler[i] > 0 ? 2.0 : 0.0, h * oran);
      final boya = Paint()..color = i == tepe ? renk : renk.withValues(alpha: .45);
      c.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x, h - yuk, gen, yuk), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)), boya);
      if (i % etiketAdim == 0) {
        final tp = TextPainter(text: TextSpan(text: etiketler[i], style: TextStyle(fontSize: 10, color: yazi)), textDirection: TextDirection.ltr)..layout();
        tp.paint(c, Offset(adim * i + adim / 2 - tp.width / 2, h + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_CubukRessami o) => o.t != t || o.degerler != degerler || o.renk != renk || o.cizgi != cizgi;
}

/// Yatay pay çubukları: ad · tutar · çubuk (en büyük = %100).
class _YatayCubuklar extends StatelessWidget {
  const _YatayCubuklar({required this.satirlar});
  final List<(String, int)> satirlar;

  static const _renkler = [Color(0xFF5443D2), Color(0xFF2563EB), Color(0xFF38BDF8), Color(0xFF15803D), Color(0xFFD97706), Color(0xFF94A3B8)];

  @override
  Widget build(BuildContext context) {
    final enCok = math.max(1, satirlar.fold<int>(0, (a, s) => math.max(a, s.$2)));
    final toplam = math.max(1, satirlar.fold<int>(0, (a, s) => a + s.$2));
    final kapali = Hareket.kapali(context);
    return Column(children: [
      for (var i = 0; i < satirlar.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(satirlar[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Text('${_yuzde(satirlar[i].$2 / toplam * 100)}  ', style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
              Text(_tl(satirlar[i].$2), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 7,
                color: Kabuk.sunken,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: kapali ? 1 : 0, end: satirlar[i].$2 / enCok),
                  duration: Hareket.uzun,
                  curve: Hareket.giris,
                  builder: (_, f, _) => FractionallySizedBox(widthFactor: f.clamp(0, 1), child: Container(color: _renkler[i % _renkler.length])),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}
