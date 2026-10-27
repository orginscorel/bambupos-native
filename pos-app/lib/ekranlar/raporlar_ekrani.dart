import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'giderler_ekrani.dart' show aralikEtiketi, isGunuAraligi;
import 'gun_sonu_ekrani.dart' show GunSonuEkrani;
import 'ortak.dart';

/// RAPORLAR (1.2.15, 2026-10-27) — web /panel/raporlar ile AYNI yapı.
///
/// İşletme talebi: "raporların görünümü webdeki gibi olup karşılaştığımız ilk
/// veriler onun üzerinden gitsin ama uygulamalarda tasarım özgünleşebilir;
/// odakların hepsi raporlara girer girmez çıkması lazım".
///
/// Bu yüzden:
///   · Rapor listesi ve sırası webdeki gibi (Özet · Ciro · Ürünler · Kârlılık ·
///     Gün sonu · Tahsilat · Mutabakat · Borçlar · Döküm · İndirim · iptal ·
///     Servis · Personel). Varsayılan: Özet + Bugün (açık iş günü).
///   · ÖZET açılır açılmaz webdeki bütün odakları birlikte gösterir: on rakam
///     kutusu → saatlik/günlük ciro → kategori payı → ödeme tipi payı (halka) →
///     borca yazılanlar. Webde dar ekranda sekmeye saklanan tablolar burada
///     saklanmaz; telefonda alt alta, tablette yan yana durur.
///   · Diğer raporlar da web sekmesindeki kartları aynı sırayla, hepsi açık
///     gösterir.
///
/// Veri web ile AYNI uçlardan (/api/v1/reports/{rapor}); hesap sunucudadır,
/// istemci yalnız pay (satır/toplam) hesaplar. Her kart kendi ucunu bekler
/// (tek bir dönen çark yok), uçlar paralel çekilir ve "dönem|uç" anahtarıyla
/// bellekte tutulur — sekmeler arasında gidip gelince yeniden istek yok.
///
/// Başarım (zayıf Android tablet): bulanıklık yok, grafikler tek
/// CustomPainter + RepaintBoundary, uzun listeler ListView.builder ile
/// alt pencerede, kart başına saydamlık katmanı yalnız bölüm girişinde.

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

/// Sunucu yüzdeleri 0–100 aralığında verir.
String _yuzde(Object? v) {
  if (v == null) return '—';
  final n = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  return '%${n.toStringAsFixed(1).replaceAll('.', ',')}';
}

List<Map<String, dynamic>> _liste(Object? v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
Map<String, dynamic> _harita(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

String _gun(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

const _aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// "21 Tem" (web shortDay).
String _kisaGun(String iso) {
  final t = DateTime.tryParse(iso);
  return t == null ? iso : '${t.day} ${_aylar[t.month - 1]}';
}

/// Web viz paleti (viz.css): sabit sıra mavi → turuncu → deniz yeşili → sarı,
/// 4'ten sonrası "Diğer" grisi.
Color _seri(int i) {
  const acik = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100)];
  const koyu = [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500)];
  if (i >= 4) return const Color(0xFF898781);
  return koyuTema.value ? koyu[i] : acik[i];
}

/* ───────────────────────── tanımlar ───────────────────────── */

/// Web YAPRAKLAR sırası (Dışa aktar hariç: dosya indirme kasada yok).
const _sekmeler = <(String, String, IconData)>[
  ('ozet', 'Özet', Icons.dashboard_outlined),
  ('satis-ciro', 'Ciro', Icons.show_chart_rounded),
  ('satis-urun', 'Ürünler', Icons.inventory_2_outlined),
  ('satis-kar', 'Kârlılık', Icons.trending_up_rounded),
  ('gunsonu', 'Gün sonu', Icons.assignment_outlined),
  ('tahsilat', 'Tahsilat', Icons.payments_outlined),
  ('mutabakat', 'Mutabakat', Icons.compare_arrows_rounded),
  ('borclar', 'Borçlar', Icons.account_balance_wallet_outlined),
  ('adisyon-dokum', 'Döküm', Icons.receipt_long_outlined),
  ('indirim', 'İndirim · iptal', Icons.percent_rounded),
  ('servis', 'Servis', Icons.room_service_outlined),
  ('personel', 'Personel', Icons.badge_outlined),
];

/// Web hazır dönemleri (Index.vue presets) — aynı ad, aynı sıra.
const _hazirlar = [
  ('bugun', 'Bugün'),
  ('dun', 'Dün'),
  ('hafta', 'Son 7 gün'),
  ('otuz', 'Son 30 gün'),
  ('ay', 'Bu ay'),
  ('gecenay', 'Geçen ay'),
  ('ozel', 'Özel aralık'),
];

const _borcListesi = 'borca-yazilanlar';
const _dokum = 'adisyon-dokumu';

/// Sütun türü.
enum _Tur { para, sayi, yuzde, metin, saat, dk }

class _Sutun {
  const _Sutun(this.anahtar, this.ad, [this.tur = _Tur.metin, this.toplanir = false]);
  final String anahtar;
  final String ad;
  final _Tur tur;
  final bool toplanir;

  bool get sayisal => tur != _Tur.metin && tur != _Tur.saat;

  double get genislik => switch (tur) {
        _Tur.para => 86,
        _Tur.sayi || _Tur.yuzde || _Tur.dk => 56,
        _Tur.saat => 52,
        _Tur.metin => 120,
      };

  String yaz(Object? v) {
    if (v == null && tur != _Tur.metin) return '—';
    return switch (tur) {
      _Tur.para => _tl(tamSayi(v)),
      _Tur.sayi => _sayi(v),
      _Tur.yuzde => _yuzde(v),
      _Tur.dk => '${_sayi(v)} dk',
      _Tur.saat => '$v'.length > 8 ? saatMetni('$v') : '$v',
      _Tur.metin => (v == null || '$v'.isEmpty) ? '—' : (v is bool ? (v ? 'Evet' : '—') : '$v'),
    };
  }
}

class _Kpi {
  const _Kpi(this.ad, this.deger, {this.alt, this.ton, this.fark});
  final String ad;

  /// null = veri bekleniyor (iskelet).
  final String? deger;
  final String? alt;
  final Color? ton;

  /// Önceki döneme göre yüzde değişim; null = karşılaştırma yok.
  final double? fark;
}

class _Oran {
  const _Oran(this.ad, this.adet, this.tutar, this.pay, this.renk);
  final String ad;
  final int adet;
  final int tutar;
  final double pay;
  final Color renk;
}

/// Web oranlariKur: ilk [enFazla] satır ayrı, kalanı "Diğer (n)".
List<_Oran> _oranlar(List<(String, int, int)> satirlar, [int enFazla = 8]) {
  final toplam = satirlar.fold<int>(0, (a, r) => a + r.$3);
  final sirali = [...satirlar]..sort((x, y) => y.$3.compareTo(x.$3));
  final bas = sirali.take(enFazla).toList();
  final kalan = sirali.skip(enFazla).toList();
  final cikti = [for (var i = 0; i < bas.length; i++) _Oran(bas[i].$1, bas[i].$2, bas[i].$3, toplam > 0 ? bas[i].$3 / toplam : 0, _seri(i))];
  if (kalan.isNotEmpty) {
    final t = kalan.fold<int>(0, (a, r) => a + r.$3);
    cikti.add(_Oran('Diğer (${kalan.length})', kalan.fold<int>(0, (a, r) => a + r.$2), t, toplam > 0 ? t / toplam : 0, _seri(9)));
  }
  return cikti;
}

/// Ekrandaki bir kart: başlığı (iskelet için), beklediği uçlar ve çizimi.
class _Bolum {
  const _Bolum(this.baslik, this.uclar, this.ciz, {this.genis = false, this.iskelet = 140, this.tahmin});
  final String baslik;
  final List<String> uclar;

  /// null döndürürse kart gizlenir (ör. borç özelliği kapalı).
  final Widget? Function() ciz;
  final bool genis;
  final double iskelet;

  /// Izgarada sütun seçimi için tahmini yükseklik (en kısa sütuna yerleşir).
  final double Function()? tahmin;
}

/* ───────────────────────── ekran ───────────────────────── */

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

  /// "dönem|uç" → yanıt (data sarmalı açılmış). Dönemler arası da korunur.
  final Map<String, Map<String, dynamic>> _bellek = {};
  final Set<String> _yukleniyor = {};
  final Map<String, String> _hatalar = {};

  /// Dökümde açılan adisyonlar.
  final Set<int> _acikAdisyon = {};

  @override
  void initState() {
    super.initState();
    _bugun = _gun(DateTime.now());
    _from = _to = _bugun;
    // İş günü okunurken takvim günüyle hemen çekmeye başla: ilk ekran beklemez.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _yukle();
    });
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
      // takvim günüyle devam (web ile aynı)
    }
    if (!mounted || _hazir == 'ozel') return;
    final a = _aralik(_hazir);
    if (a != null && (a.$1 != _from || a.$2 != _to)) _hazirSec(_hazir);
  }

  (String, String)? _aralik(String h) {
    if (h == 'gecenay') {
      final b = DateTime.tryParse(_bugun) ?? DateTime.now();
      final ilk = DateTime(b.year, b.month - 1, 1);
      final son = DateTime(b.year, b.month, 0);
      return (_gun(ilk), _gun(son));
    }
    return isGunuAraligi(h, _bugun, _dun);
  }

  void _hazirSec(String h) {
    if (h == 'ozel') {
      _ozelSec();
      return;
    }
    final a = _aralik(h);
    if (a == null) return;
    setState(() {
      _hazir = h;
      _from = a.$1;
      _to = a.$2;
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
      saveText: 'Filtrele',
    );
    if (r == null || !mounted) return;
    setState(() {
      _hazir = 'ozel';
      _from = _gun(r.start);
      _to = _gun(r.end);
      _hatalar.clear();
    });
    _yukle();
  }

  String get _donem => '$_from|$_to';
  bool get _tekGun => _from == _to;
  String get _sekme => _sekmeler[_secili].$1;

  /// Sekmenin ihtiyaç duyduğu uçlar (web sekmesinin useReport listesi).
  List<String> _uclar(String s) => switch (s) {
        'ozet' => [
            'finance-summary',
            'sales-open-items',
            _tekGun ? 'sales-hourly' : 'sales-daily',
            'sales-categories',
            'finance-collected',
            'receivables-summary',
            _borcListesi,
          ],
        'satis-ciro' => ['sales-summary', 'receivables-summary', 'sales-hourly', if (!_tekGun) 'sales-daily', 'sales-channels', 'sales-service'],
        'satis-urun' => ['sales-open-items', 'sales-category-products', 'sales-products', 'sales-variants', 'sales-tables'],
        'satis-kar' => ['product-profitability'],
        'tahsilat' => ['finance-collected', 'finance-summary', 'finance-vat', 'finance-cash-sessions', 'finance-open-accounts'],
        'mutabakat' => ['finance-reconciliation'],
        'borclar' => ['receivables-summary', 'receivables-aging', 'receivables-collections', 'ops-open-receivables'],
        'adisyon-dokum' => [_dokum],
        'indirim' => ['finance-discounts', 'finance-summary', 'ops-cancellations', 'ops-eod-details'],
        'servis' => ['ops-delayed', 'ops-station-prep', 'ops-delivery-sla', 'ops-service-requests', 'ops-channel-usage'],
        'personel' => ['staff-performance'],
        _ => const [],
      };

  Future<void> _yukle({bool zorla = false}) async {
    final donem = _donem;
    final from = _from, to = _to;
    final istenen = _uclar(_sekme).where((uc) {
      final k = '$donem|$uc';
      return !_yukleniyor.contains(k) && (zorla || !_bellek.containsKey(k));
    }).toList();
    if (istenen.isEmpty) return;
    setState(() {
      for (final uc in istenen) {
        _yukleniyor.add('$donem|$uc');
        _hatalar.remove('$donem|$uc');
      }
    });
    await Future.wait(istenen.map((uc) async {
      final k = '$donem|$uc';
      Map<String, dynamic>? veri;
      String? hata;
      try {
        final yol = '/api/v1/reports/$uc';
        final v = await _api.get(yol, sorgu: {'from': from, 'to': to});
        // Rapor uçları {data: …} sarar; borca-yazilanlar ve döküm sarmaz.
        veri = v is Map && v['data'] is Map ? _harita(v['data']) : _harita(v);
      } on ApiHata catch (e) {
        if (uc == _borcListesi && (e.kod == 404 || e.kod == 403)) {
          veri = const {'enabled': false}; // cari özelliği kapalı: blok çizilmez
        } else {
          hata = e.kod == 403 ? 'Bu raporu görme yetkiniz yok.' : e.mesaj;
        }
      }
      if (!mounted) return;
      setState(() {
        _yukleniyor.remove(k);
        if (veri != null) _bellek[k] = veri;
        if (hata != null) _hatalar[k] = hata;
      });
    }));
  }

  void _sekmeSec(int i) {
    if (i == _secili) return;
    setState(() {
      _yon = i > _secili ? 1 : -1;
      _secili = i;
    });
    _yukle();
  }

  Map<String, dynamic>? _veri(String uc) => _bellek['$_donem|$uc'];
  Map<String, dynamic> _m(String uc) => _veri(uc) ?? const {};
  String? _hata(String uc) => _hatalar['$_donem|$uc'];

  /* ───────────────────────── görünüm ───────────────────────── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final dar = g < 700;
    final yan = dar ? 12.0 : 18.0;
    final gunSonu = _sekme == 'gunsonu';
    return ColoredBox(
      color: Kabuk.sunken,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13, color: Kabuk.ink),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(yan, 8, yan - 8, 0),
            child: Row(children: [
              const Text('Raporlar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.36)),
              const SizedBox(width: 10),
              Expanded(
                child: gunSonu
                    ? const SizedBox()
                    : Text(aralikEtiketi(_from, _to),
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Kabuk.soft, fontWeight: FontWeight.w600)),
              ),
              if (!gunSonu)
                IconButton(
                  tooltip: 'Yenile',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _yukle(zorla: true),
                  icon: Icon(Icons.refresh_rounded, color: Kabuk.soft),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          _sekmeSatiri(yan),
          if (!gunSonu) ...[const SizedBox(height: 6), _donemSatiri(yan)],
          const SizedBox(height: 10),
          Expanded(
            child: EkranGecisi(
              anahtar: _sekme,
              yon: _yon,
              child: gunSonu ? const GunSonuEkrani() : _govde(yan),
            ),
          ),
        ]),
      ),
    );
  }

  /// Rapor sekmeleri: alt çizgili şerit (kasadaki sekme dili).
  Widget _sekmeSatiri(double yan) => SizedBox(
        height: 40,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: yan - 4),
          itemCount: _sekmeler.length,
          itemBuilder: (_, i) {
            final (_, ad, ikon) = _sekmeler[i];
            final secili = i == _secili;
            final renk = secili ? Kabuk.brand : Kabuk.soft;
            return Semantics(
              selected: secili,
              button: true,
              child: InkWell(
                borderRadius: koseYuvarlak,
                onTap: () => _sekmeSec(i),
                child: AnimatedContainer(
                  duration: Hareket.kisa,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: secili ? Kabuk.brand : Colors.transparent, width: 2.5))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ikon, size: 17, color: renk),
                    const SizedBox(width: 6),
                    Text(ad, style: TextStyle(fontSize: 13.5, fontWeight: secili ? FontWeight.w800 : FontWeight.w600, color: secili ? Kabuk.ink : Kabuk.soft)),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  Widget _donemSatiri(double yan) => SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: yan),
          itemCount: _hazirlar.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) {
            final (k, ad) = _hazirlar[i];
            final secili = _hazir == k;
            return Material(
              color: secili ? Kabuk.ink : Renk.yuzey,
              borderRadius: koseYuvarlak,
              child: InkWell(
                borderRadius: koseYuvarlak,
                onTap: () => _hazirSec(k),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: secili ? Kabuk.ink : Kabuk.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (k == 'ozel') ...[Icon(Icons.date_range_rounded, size: 15, color: secili ? Kabuk.surface : Kabuk.soft), const SizedBox(width: 5)],
                    Text(ad, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: secili ? Kabuk.surface : Kabuk.ink)),
                  ]),
                ),
              ),
            );
          },
        ),
      );

  Widget _govde(double yan) {
    return RefreshIndicator(
      onRefresh: () => _yukle(zorla: true),
      child: LayoutBuilder(builder: (context, k) {
        final gen = k.maxWidth - yan * 2;
        final List<Widget> icerik;
        if (_sekme == 'adisyon-dokum') {
          return _dokumListesi(yan);
        }
        icerik = switch (_sekme) {
          'ozet' => _ozet(gen),
          'satis-ciro' => _ciro(gen),
          'satis-urun' => _urunler(gen),
          'satis-kar' => _karlilik(gen),
          'tahsilat' => _tahsilat(gen),
          'mutabakat' => _mutabakat(gen),
          'borclar' => _borclar(gen),
          'indirim' => _indirim(gen),
          'servis' => _servis(gen),
          'personel' => _personel(gen),
          _ => const [],
        };
        return ListView(
          padding: EdgeInsets.fromLTRB(yan, 0, yan, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: icerik,
        );
      }),
    );
  }

  /* ───────────────────────── yerleşim ───────────────────────── */

  int _sutunSayisi(double gen, {int enCok = 2}) => gen >= 1360 ? math.min(3, enCok) : (gen >= 860 ? math.min(2, enCok) : 1);

  /// Bölümleri ızgaraya dizer: geniş olanlar tam satır, kalanlar sütunlara
  /// sırayla dağılır (telefonda tek sütun).
  List<Widget> _diz(List<_Bolum> bolumler, double gen, {int enCok = 2, int ilkSira = 0}) {
    final cikti = <Widget>[];
    var kosu = <Widget>[];
    var kosuBoy = <double>[];
    var sira = ilkSira;

    void bosalt() {
      if (kosu.isEmpty) return;
      final sutun = math.min(_sutunSayisi(gen, enCok: enCok), kosu.length);
      if (sutun <= 1) {
        for (final w in kosu) {
          cikti.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: w));
        }
      } else {
        final kolonlar = List.generate(sutun, (_) => <Widget>[]);
        final boylar = List.filled(sutun, 0.0);
        for (var i = 0; i < kosu.length; i++) {
          var c = 0;
          for (var j = 1; j < sutun; j++) {
            if (boylar[j] < boylar[c]) c = j;
          }
          kolonlar[c].add(Padding(padding: const EdgeInsets.only(bottom: 10), child: kosu[i]));
          boylar[c] += kosuBoy[i] + 10;
        }
        cikti.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var c = 0; c < sutun; c++) ...[
            if (c > 0) const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kolonlar[c])),
          ],
        ]));
      }
      kosu = [];
      kosuBoy = [];
    }

    for (final b in bolumler) {
      final w = _bolumCiz(b);
      if (w == null) continue;
      final kart = Belirme(key: ValueKey('${b.baslik}|$_sekme'), sira: sira++, child: w);
      if (b.genis) {
        bosalt();
        cikti.add(Padding(padding: const EdgeInsets.only(bottom: 10), child: kart));
      } else {
        kosu.add(kart);
        kosuBoy.add(b.uclar.every((u) => _veri(u) != null) ? (b.tahmin?.call() ?? b.iskelet + 50) : b.iskelet + 50);
      }
    }
    bosalt();
    return cikti;
  }

  Widget? _bolumCiz(_Bolum b) {
    if (b.uclar.every((u) => _veri(u) != null)) return b.ciz();
    final hata = b.uclar.map(_hata).whereType<String>().firstOrNull;
    if (hata != null) {
      return _Kart(
        baslik: b.baslik,
        child: _BosKutu(Icons.error_outline_rounded, hata, eylem: () => _yukle(zorla: true)),
      );
    }
    return _Kart(baslik: b.baslik, child: _Iskelet(b.iskelet));
  }

  Widget _kpiler(List<_Kpi> ogeler, double gen, {required int dar, required int orta, required int genis}) {
    final sutun = gen >= 1400 ? genis : (gen >= 680 ? orta : dar);
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: _KpiIzgara(ogeler: ogeler, sutun: sutun, genislik: gen));
  }

  Widget _bosDonem(String baslik, String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _Kart(child: _BosKutu(Icons.insights_outlined, metin, baslik: baslik)),
      );

  /* ───────────────────────── ÖZET (web OzetTab) ───────────────────────── */

  List<Widget> _ozet(double gen) {
    final f = _veri('finance-summary');
    final acik = _veri('sales-open-items');
    final kat = _veri('sales-categories');
    final tah = _veri('finance-collected');
    int fi(String k) => tamSayi(f?[k]);

    final katSatir = _liste(kat?['rows']);
    final urunAdedi = katSatir.fold<int>(0, (a, r) => a + tamSayi(r['qty']));
    final indirim = fi('discount_total_minor');
    final iptalAdet = fi('cancelled_orders') + fi('refund_payments_count');
    final iptalTutar = fi('cancelled_minor') + fi('refund_payments_minor');
    final ortSepet = fi('orders') > 0 ? (fi('gross_minor') / fi('orders')).round() : 0;
    String? ff(String Function() yaz) => f == null ? null : yaz();

    final kutular = <_Kpi>[
      _Kpi('Açık masa tutarı', acik == null ? null : _tl(tamSayi(acik['amount_minor'])), alt: '${_sayi(acik?['qty'] ?? 0)} ürün masada bekliyor'),
      _Kpi('Toplam ürün adedi', kat == null ? null : _sayi(urunAdedi), alt: '${_sayi(katSatir.length)} kategori'),
      _Kpi('Toplam ürün tutarı', ff(() => _tl(fi('items_total_minor'))), alt: 'indirim ve ikram düşülmeden'),
      _Kpi('Ciro toplamı', ff(() => _tl(fi('gross_minor'))), alt: '${_sayi(fi('orders'))} adisyon · ort. ${_tl(ortSepet)}'),
      _Kpi('Ödeme adedi', ff(() => _sayi(fi('collected_count'))), alt: 'kasadan alınan ödeme sayısı'),
      _Kpi('Ödeme tutarı', ff(() => _tl(fi('collected_minor'))),
          alt: fi('tips_minor') > 0 ? '${_tl(fi('tips_minor'))} bahşiş dahil' : 'kasaya giren para', ton: Kabuk.success),
      _Kpi('İkram tutarı', ff(() => _tl(fi('comp_minor'))), alt: 'ücretsiz verilen ürünler', ton: fi('comp_minor') > 0 ? Kabuk.warning : null),
      _Kpi('İndirim tutarı', ff(() => _tl(indirim)),
          alt: fi('iskonto_minor') > 0 ? '${_tl(fi('iskonto_minor'))} kasa iskontosu dahil' : 'adisyon + satır indirimi',
          ton: indirim > 0 ? Kabuk.warning : null),
      _Kpi('İptal · iade adedi', ff(() => _sayi(iptalAdet)),
          alt: '${_sayi(fi('cancelled_orders'))} iptal · ${_sayi(fi('refund_payments_count'))} iade', ton: iptalAdet > 0 ? Kabuk.negative : null),
      _Kpi('İptal · iade tutarı', ff(() => _tl(iptalTutar)), alt: 'iptal adisyon + iade edilen ödeme', ton: iptalTutar > 0 ? Kabuk.negative : null),
    ];

    final hareketVar = fi('orders') > 0 || tamSayi(tah?['total_count']) > 0 || tamSayi(acik?['amount_minor']) > 0;
    final hepsiGeldi = f != null && tah != null && acik != null;

    final borc = _veri(_borcListesi);
    final borcVar = borc?['enabled'] == true && tamSayi(borc?['count']) > 0;

    return [
      _kpiler(kutular, gen, dar: 2, orta: 5, genis: 10),
      if (hepsiGeldi && !hareketVar)
        _bosDonem('Bu dönemde hareket yok', 'Seçilen dönemde kapanmış adisyon, tahsilat ya da açık masa bulunmuyor.')
      else
        ..._diz([
          _ciroBolumu(genis: true),
          _Bolum('Kategori payı', ['sales-categories'], () {
            final o = _oranlar([for (final r in katSatir) ('${r['name']}', tamSayi(r['qty']), tamSayi(r['revenue_minor']))]);
            return _Kart(
              baslik: 'Kategori payı',
              ek: '${_sayi(o.fold<int>(0, (a, r) => a + r.adet))} ürün',
              sag: _tl(o.fold<int>(0, (a, r) => a + r.tutar)),
              govdeBosluk: false,
              child: _OranTablosu(adBaslik: 'Kategori', satirlar: o, bos: 'Bu dönemde ürün satışı yok.'),
            );
          }, iskelet: 220, tahmin: () => 80.0 + 38 * math.min(9, katSatir.length)),
          _odemeBolumu('Ödeme tipi payı', 'finance-collected', 'rows', 'Bu dönemde tahsilat yok.'),
          _Bolum('Borca yazılanlar', [_borcListesi, 'receivables-summary'], () {
            if (!borcVar) return null;
            final ozet = _m('receivables-summary');
            final kisiler = _liste(borc!['kisiler']).take(10).toList();
            return _Kart(
              baslik: 'Borca yazılanlar',
              ek: '${_sayi(borc['count'])} adisyon · ${_sayi(borc['kisi'])} kişi',
              sag: _tl(tamSayi(borc['total_minor'])),
              govdeBosluk: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Tablo(
                  sutunlar: const [
                    _Sutun('name', 'Borca yazdıran'),
                    _Sutun('count', 'Adisyon', _Tur.sayi),
                    _Sutun('amount_minor', 'Yazılan', _Tur.para),
                    _Sutun('balance_minor', 'Bakiye', _Tur.para),
                  ],
                  satirlar: kisiler,
                  vurgu: (s, r) => s.anahtar == 'balance_minor' && tamSayi(r['balance_minor']) > 0 ? Kabuk.negative : null,
                ),
                if (ozet['available'] == true)
                  _Serit([
                    ('Tahsil', _tl(tamSayi(ozet['tahsil_minor'])), Kabuk.success),
                    ('İskonto', _tl(tamSayi(ozet['iskonto_minor'])), null),
                    ('Açık borç', _tl(tamSayi(ozet['acik_borc_sonu_minor'])), Kabuk.negative),
                  ]),
              ]),
            );
          }, iskelet: 200, tahmin: () => 120.0 + 35 * math.min(10, _liste(borc?['kisiler']).length)),
        ], gen, enCok: borcVar ? 3 : 2),
    ];
  }

  /// Saatlik (tek gün) / günlük (aralık) ciro sütunları — web ile aynı kural.
  _Bolum _ciroBolumu({bool genis = false}) {
    final uc = _tekGun ? 'sales-hourly' : 'sales-daily';
    return _Bolum(_tekGun ? 'Saatlik ciro' : 'Günlük ciro', [uc], () {
      final List<(String, String, int)> noktalar = _tekGun
          ? [
              for (final h in _liste(_m(uc)['hours']))
                (tamSayi(h['hour']).toString().padLeft(2, '0'), '${tamSayi(h['hour']).toString().padLeft(2, '0')}:00', tamSayi(h['revenue_minor'])),
            ]
          : [for (final d in _liste(_m(uc)['days'])) (_kisaGun('${d['date']}'), _kisaGun('${d['date']}'), tamSayi(d['revenue_minor']))];
      return _SutunKart(
        baslik: _tekGun ? 'Saatlik ciro' : 'Günlük ciro',
        birim: _tekGun ? 'saat' : 'gün',
        noktalar: noktalar,
        bicim: _tl,
        renk: Kabuk.brand,
        bos: 'Bu dönemde kapanan adisyon yok.',
      );
    }, genis: genis, iskelet: 150);
  }

  /// Ödeme yöntemi payı: halka + oran tablosu (web "Ödeme tipi payı").
  _Bolum _odemeBolumu(String baslik, String uc, String anahtar, String bos, {String adAlani = 'label', String adetAlani = 'count'}) {
    return _Bolum(baslik, [uc], () {
      final o = _oranlar([for (final r in _liste(_m(uc)[anahtar])) ('${r[adAlani]}', tamSayi(r[adetAlani]), tamSayi(r['amount_minor']))], 6);
      final adet = o.fold<int>(0, (a, r) => a + r.adet);
      return _Kart(
        baslik: baslik,
        ek: '${_sayi(adet)} işlem',
        sag: _tl(o.fold<int>(0, (a, r) => a + r.tutar)),
        govdeBosluk: false,
        child: o.isEmpty
            ? _BosKutu(Icons.payments_outlined, bos)
            : LayoutBuilder(builder: (context, k) {
                final halka = Padding(
                  padding: const EdgeInsets.all(12),
                  child: RepaintBoundary(
                    child: SizedBox.square(
                      dimension: 104,
                      child: CustomPaint(painter: _HalkaRessami(o, Kabuk.sunken, Kabuk.ink, Kabuk.soft, _sayi(adet))),
                    ),
                  ),
                );
                final tablo = _OranTablosu(adBaslik: 'Ödeme tipi', satirlar: o, bos: bos, nokta: true);
                return k.maxWidth >= 460
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [halka, Expanded(child: tablo)])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: halka), tablo]);
              }),
      );
    }, iskelet: 200, tahmin: () => 80.0 + 38 * math.min(7, _liste(_m(uc)[anahtar]).length));
  }

  /// Tablo kartı bölümü (diğer raporlar).
  _Bolum _tabloBolumu(
    String baslik,
    String uc,
    List<_Sutun> sutunlar, {
    String anahtar = 'rows',
    String bos = 'Bu dönemde kayıt yok.',
    bool genis = false,
    bool toplam = false,
    String? Function(Map<String, dynamic>)? ek,
    List<Map<String, dynamic>> Function(Map<String, dynamic>)? satirlar,
    Color? Function(_Sutun, Map<String, dynamic>)? vurgu,
  }) {
    return _Bolum(baslik, [uc], () {
      final v = _m(uc);
      final s = satirlar != null ? satirlar(v) : _liste(v[anahtar]);
      return _TabloKart(baslik: baslik, ek: ek?.call(v) ?? (s.isEmpty ? null : '${_sayi(s.length)} satır'), sutunlar: sutunlar, satirlar: s, bos: bos, toplam: toplam, vurgu: vurgu);
    }, genis: genis, iskelet: 180, tahmin: () {
      final v = _m(uc);
      final n = satirlar != null ? satirlar(v).length : _liste(v[anahtar]).length;
      return n == 0 ? 130.0 : 80.0 + 37 * math.min(12, n) + (toplam ? 37 : 0);
    });
  }

  /* ───────────────────────── CİRO (web SatisTab) ───────────────────────── */

  List<Widget> _ciro(double gen) {
    final s = _veri('sales-summary');
    final c = _harita(s?['current']), o = _harita(s?['previous']);
    final b = _veri('receivables-summary');
    double? fark(String k) {
      final a = tamSayi(c[k]), p = tamSayi(o[k]);
      return s == null || p == 0 ? null : ((a - p) / p * 1000).round() / 10;
    }

    final ciro = tamSayi(c['revenue_minor']);
    final yazilan = tamSayi(b?['yazilan_minor']);
    final kpi = <_Kpi>[
      _Kpi('Ciro — tahsil edilen', s == null || b == null ? null : _tl(ciro - yazilan), alt: 'ciro − borca yazılan', ton: Kabuk.success),
      _Kpi('Borca yazılan', b == null ? null : _tl(yazilan), alt: '${_sayi(b?['yazilan_adet'] ?? 0)} adisyon', ton: yazilan > 0 ? Kabuk.warning : null),
      _Kpi('Ciro toplamı', s == null ? null : _tl(ciro), fark: fark('revenue_minor')),
      _Kpi('Sipariş', s == null ? null : _sayi(c['orders']), fark: fark('orders')),
      _Kpi('Ortalama sepet', s == null ? null : _tl(tamSayi(c['avg_basket_minor'])), fark: fark('avg_basket_minor')),
      _Kpi('Kişi başı harcama', s == null ? null : (c['per_guest_minor'] == null ? '—' : _tl(tamSayi(c['per_guest_minor']))),
          alt: '${_sayi(c['guests'] ?? 0)} misafir'),
    ];
    if (s != null && tamSayi(c['orders']) == 0) {
      return [_kpiler(kpi, gen, dar: 2, orta: 3, genis: 6), _bosDonem('Bu dönemde satış yok', 'Seçilen dönemde kapanan adisyon bulunmuyor.')];
    }
    return [
      _kpiler(kpi, gen, dar: 2, orta: 3, genis: 6),
      ..._diz([
        _ciroBolumu(genis: true),
        if (!_tekGun)
          _Bolum('Yoğun saatler', ['sales-hourly'], () {
            return _SutunKart(
              baslik: 'Yoğun saatler',
              birim: 'saat',
              noktalar: [
                for (final h in _liste(_m('sales-hourly')['hours']))
                  (tamSayi(h['hour']).toString().padLeft(2, '0'), '${tamSayi(h['hour']).toString().padLeft(2, '0')}:00', tamSayi(h['orders'])),
              ],
              bicim: (v) => '${_sayi(v)} sipariş',
              renk: _seri(0),
              bos: 'Veri yok.',
            );
          }, iskelet: 150),
        _Bolum('Sipariş kanalı', ['sales-channels'], () {
          final v = _m('sales-channels');
          final o = _oranlar([for (final r in _liste(v['rows'])) ('${r['label']}', tamSayi(r['orders']), tamSayi(r['revenue_minor']))], 4);
          return _Kart(
            baslik: 'Sipariş kanalı',
            ek: 'kanal bazında ciro payı',
            sag: _tl(tamSayi(v['total_minor'])),
            govdeBosluk: false,
            child: _OranTablosu(adBaslik: 'Kanal', satirlar: o, bos: 'Veri yok.', nokta: true),
          );
        }),
        _Bolum('Masa hizmeti', ['sales-service'], () {
          final v = _m('sales-service');
          final m = _harita(v['masa']), mz = _harita(v['masasiz']);
          return _Kart(
            baslik: 'Masa hizmeti',
            ek: '${_sayi(v['masa_sayisi'] ?? 0)} aktif masa',
            child: _Satirlar([
              ('Hizmet verilen masa', _sayi(m['servis'] ?? 0), null),
              ('Farklı masa', _sayi(m['farkli_masa'] ?? 0), null),
              ('Ödenen', '${_sayi(m['odenen'] ?? 0)}${m['odeme_orani'] == null ? '' : ' · ${_yuzde(m['odeme_orani'])}'}', Kabuk.success),
              ('Borca yazılan', _sayi(m['borca_yazilan'] ?? 0), null),
              ('Açık', _sayi(m['acik'] ?? 0), null),
              ('Masa cirosu', _tl(tamSayi(m['ciro_minor'])), null),
              ('Misafir', _sayi(m['misafir'] ?? 0), null),
              ('Masa devri', v['devir'] == null ? '—' : '${_sayi(v['devir'])} kez', null),
              ('Masasız sipariş', '${_sayi(mz['servis'] ?? 0)} · ${_sayi(mz['odenen'] ?? 0)} ödendi', null),
            ]),
          );
        }),
      ], gen),
    ];
  }

  /* ───────────────────────── ÜRÜNLER (web UrunlerTab) ───────────────────────── */

  List<Widget> _urunler(double gen) {
    const urun = [_Sutun('name', 'Ürün'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('orders', 'Sipariş', _Tur.sayi), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)];
    return _diz([
      _tabloBolumu('Şu an açık masalarda bekleyen ürünler', 'sales-open-items',
          const [_Sutun('name', 'Ürün'), _Sutun('kategori', 'Kategori'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('revenue_minor', 'Tutar', _Tur.para, true)],
          bos: 'Açık masada bekleyen ürün yok.', ek: (v) => '${_sayi(v['qty'] ?? 0)} ürün · ${_tl(tamSayi(v['amount_minor']))}', toplam: true),
      _tabloBolumu('Kategori satışları', 'sales-category-products',
          const [_Sutun('kategori', 'Kategori'), _Sutun('name', 'Ürün'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)],
          bos: 'Bu dönemde ürün satışı yok.', toplam: true, genis: true),
      _tabloBolumu('En çok satan ürünler', 'sales-products', urun, anahtar: 'top_by_qty', bos: 'Bu dönemde ürün satışı yok.'),
      _tabloBolumu('En az satan ürünler', 'sales-products', urun, anahtar: 'least_by_qty', bos: 'Bu dönemde ürün satışı yok.'),
      _tabloBolumu('Varyant satışları', 'sales-variants',
          const [_Sutun('name', 'Ürün'), _Sutun('variant', 'Varyant'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)],
          bos: 'Bu dönemde varyantlı satış yok.'),
      _tabloBolumu('Masa satışları ve devir', 'sales-tables',
          const [_Sutun('name', 'Masa'), _Sutun('orders', 'Sipariş', _Tur.sayi, true), _Sutun('turns', 'Devir', _Tur.sayi), _Sutun('avg_minutes', 'Ort. süre', _Tur.dk), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)],
          bos: 'Bu dönemde masa satışı yok.', toplam: true),
    ], gen);
  }

  /* ───────────────────────── KÂRLILIK (web ProfitTab) ───────────────────────── */

  List<Widget> _karlilik(double gen) {
    final v = _veri('product-profitability');
    final satirlar = _liste(v?['rows']);
    final bilinen = satirlar.where((r) => r['has_cost'] == true).toList();
    final brut = bilinen.fold<int>(0, (a, r) => a + tamSayi(r['profit_minor']));
    Map<String, dynamic>? enKarli, enDusuk;
    for (final r in bilinen) {
      if (enKarli == null || tamSayi(r['profit_minor']) > tamSayi(enKarli['profit_minor'])) enKarli = r;
      if (r['margin'] != null && (enDusuk == null || (r['margin'] as num) < (enDusuk['margin'] as num))) enDusuk = r;
    }
    final ikram = _harita(v?['comp']);
    String? h(String Function() y) => v == null ? null : y();
    final kpi = <_Kpi>[
      _Kpi('Toplam brüt kâr', h(() => _tl(brut)), alt: 'maliyeti bilinen ürünler', ton: Kabuk.success),
      _Kpi('Medyan marj', h(() => _yuzde(v!['median_margin'])), alt: '${_sayi(v?['missing_cost_count'] ?? 0)} ürünün maliyeti yok'),
      _Kpi('En kârlı ürün', h(() => enKarli == null ? '—' : '${enKarli['name']}'), alt: enKarli == null ? null : _tl(tamSayi(enKarli['profit_minor']))),
      _Kpi('En düşük marjlı', h(() => enDusuk == null ? '—' : '${enDusuk['name']}'), alt: enDusuk == null ? null : _yuzde(enDusuk['margin']), ton: enDusuk == null ? null : Kabuk.warning),
      _Kpi('İkram adedi', h(() => _sayi(ikram['qty'] ?? 0))),
      _Kpi('İkram tutarı (bedelsiz)', h(() => _tl(tamSayi(ikram['value_minor']))), ton: Kabuk.warning),
      _Kpi('İkram maliyeti (stok)', h(() => _tl(tamSayi(ikram['cost_minor'])))),
      _Kpi('Net kâr (ikram sonrası)', h(() => _tl(brut - tamSayi(ikram['cost_minor']))), ton: Kabuk.success),
    ];
    if (v != null && satirlar.isEmpty) return [_bosDonem('Bu aralıkta satış yok', 'Seçilen dönemde satılan ürün bulunmuyor.')];
    const sut = [
      _Sutun('name', 'Ürün'),
      _Sutun('qty', 'Adet', _Tur.sayi),
      _Sutun('revenue_minor', 'Ciro', _Tur.para, true),
      _Sutun('cost_minor', 'Maliyet', _Tur.para, true),
      _Sutun('profit_minor', 'Brüt kâr', _Tur.para, true),
      _Sutun('margin', 'Marj', _Tur.yuzde),
    ];
    return [
      _kpiler(kpi, gen, dar: 2, orta: 4, genis: 8),
      ..._diz([
        _tabloBolumu('Çok satan ama düşük kârlı', 'product-profitability', sut,
            satirlar: (v) => _liste(v['rows']).where((r) => r['high_volume_low_margin'] == true).toList(), bos: 'Bu dönemde düşük kârlı çok satan ürün yok.'),
        _tabloBolumu('Ürün kârlılığı', 'product-profitability', sut, toplam: true, genis: true,
            vurgu: (s, r) => s.anahtar == 'profit_minor' && tamSayi(r['profit_minor']) < 0 ? Kabuk.negative : null),
      ], gen),
    ];
  }

  /* ───────────────────────── TAHSİLAT (web TahsilatTab) ───────────────────────── */

  List<Widget> _tahsilat(double gen) {
    final t = _veri('finance-collected');
    final f = _veri('finance-summary');
    final kpi = <_Kpi>[
      _Kpi('Tahsil edilen', t == null ? null : _tl(tamSayi(t['total_minor'])), alt: '${_sayi(t?['total_count'] ?? 0)} işlem', ton: Kabuk.success),
      _Kpi('Adisyon tahsilatı', t == null ? null : _tl(tamSayi(t['adisyon_minor'])), alt: '${_sayi(t?['adisyon_count'] ?? 0)} ödeme'),
      _Kpi('Borçtan tahsilat', t == null ? null : _tl(tamSayi(t['borc_minor'])), alt: '${_sayi(t?['borc_count'] ?? 0)} tahsilat'),
      _Kpi('İade', f == null ? null : _tl(tamSayi(f['refund_payments_minor'])),
          alt: '${_sayi(f?['refund_payments_count'] ?? 0)} iade', ton: tamSayi(f?['refund_payments_minor']) > 0 ? Kabuk.negative : null),
    ];
    return [
      _kpiler(kpi, gen, dar: 2, orta: 4, genis: 4),
      ..._diz([
        _odemeBolumu('Para neyle alındı', 'finance-collected', 'rows', 'Bu dönemde tahsilat yok.'),
        _Bolum('Satıştan nete iniş ve KDV', ['finance-summary', 'finance-vat'], () {
          final s = _m('finance-summary');
          int g(String k) => tamSayi(s[k]);
          return _Kart(
            baslik: 'Satıştan nete iniş ve KDV',
            govdeBosluk: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: _Satirlar([
                  ('Ürün toplamı', _tl(g('items_total_minor')), null),
                  ('İndirim', '-${_tl(g('discount_total_minor'))}', Kabuk.warning),
                  ('İkram', '-${_tl(g('comp_minor'))}', Kabuk.warning),
                  if (g('service_charge_minor') != 0) ('Servis ücreti', _tl(g('service_charge_minor')), null),
                  if (g('rounding_minor') != 0) ('Yuvarlama', _tl(g('rounding_minor')), null),
                  ('Ciro (KDV dahil)', _tl(g('gross_minor')), Kabuk.ink),
                  ('KDV', '-${_tl(g('vat_minor'))}', null),
                  ('Net satış (KDV hariç)', _tl(g('net_minor')), Kabuk.success),
                ]),
              ),
              _Tablo(
                sutunlar: const [_Sutun('rate', 'KDV oranı', _Tur.yuzde), _Sutun('gross_minor', 'Brüt', _Tur.para, true), _Sutun('vat_minor', 'KDV', _Tur.para, true), _Sutun('net_minor', 'Net', _Tur.para, true)],
                satirlar: _liste(_m('finance-vat')['rows']),
              ),
            ]),
          );
        }, iskelet: 260),
        _tabloBolumu('Kasa oturumları (Z) ve kasa farkı', 'finance-cash-sessions', const [
          _Sutun('z_number', 'Z No'),
          _Sutun('register', 'Kasa'),
          _Sutun('opened_by', 'Açan'),
          _Sutun('opened_at', 'Açılış', _Tur.saat),
          _Sutun('closed_at', 'Kapanış', _Tur.saat),
          _Sutun('expected_minor', 'Beklenen', _Tur.para),
          _Sutun('counted_minor', 'Sayılan', _Tur.para),
          _Sutun('difference_minor', 'Fark', _Tur.para, true),
        ], bos: 'Bu dönemde kasa oturumu yok.', genis: true, vurgu: (s, r) => s.anahtar == 'difference_minor' && tamSayi(r['difference_minor']) != 0 ? Kabuk.negative : null),
        _tabloBolumu('Bakiyesi kalan adisyonlar', 'finance-open-accounts', const [
          _Sutun('id', 'Adisyon'),
          _Sutun('table', 'Masa'),
          _Sutun('customer', 'Müşteri'),
          _Sutun('total_minor', 'Tutar', _Tur.para),
          _Sutun('paid_minor', 'Ödenen', _Tur.para),
          _Sutun('balance_minor', 'Bakiye', _Tur.para, true),
        ], anahtar: 'open_orders', bos: 'Bakiyesi kalan adisyon yok.', genis: true, toplam: true, ek: (v) {
          final h = _harita(v['on_account']);
          return tamSayi(h['count']) > 0 ? '${_sayi(h['count'])} cari adisyon · ${_tl(tamSayi(h['amount_minor']))}' : null;
        }),
      ], gen),
    ];
  }

  /* ───────────────────────── MUTABAKAT (web MutabakatTab) ───────────────────────── */

  List<Widget> _mutabakat(double gen) {
    final d = _veri('finance-reconciliation');
    int g(String k) => tamSayi(d?[k]);
    final kpi = <_Kpi>[
      _Kpi('Nakit (kasada olmalı)', d == null ? null : _tl(g('cash_minor')), alt: '${_sayi(g('cash_count'))} işlem', ton: Kabuk.success),
      _Kpi('POS / Kart', d == null ? null : _tl(g('pos_minor')), alt: '${_sayi(g('pos_count'))} işlem'),
      _Kpi('Diğer', d == null ? null : _tl(g('other_minor')), alt: '${_sayi(g('other_count'))} işlem'),
    ];
    if (d != null && g('payments_total_minor') == 0 && g('orders_closed_count') == 0) {
      return [_kpiler(kpi, gen, dar: 2, orta: 3, genis: 3), _bosDonem('Bu dönemde tahsilat yok', 'Mutabakat için kapanan adisyon ya da ödeme bulunmuyor.')];
    }
    final fark = g('difference_minor'), kasaFark = g('cash_sessions_difference_minor');
    return [
      _kpiler(kpi, gen, dar: 2, orta: 3, genis: 3),
      ..._diz([
        _Bolum('Ödeme defteri ↔ sistemdeki adisyon toplamı', ['finance-reconciliation'], () => _Kart(
              baslik: 'Ödeme defteri ↔ sistemdeki adisyon toplamı',
              child: _Satirlar([
                ('Kapanan adisyon', _sayi(g('orders_closed_count')), null),
                ('Adisyon toplamı', _tl(g('orders_total_minor')), null),
                ('Adisyonlara ödenen', _tl(g('orders_paid_minor')), null),
                ('Ödeme defteri toplamı', _tl(g('payments_total_minor')), null),
                ('Fark', fark == 0 ? 'Fark yok' : _tl(fark), fark == 0 ? Kabuk.success : Kabuk.negative),
              ]),
            )),
        _Bolum('Beklenen nakit ↔ sayılan nakit', ['finance-reconciliation'], () => _Kart(
              baslik: 'Beklenen nakit ↔ sayılan nakit',
              child: d?['has_cash_sessions'] != true
                  ? const _BosKutu(Icons.point_of_sale_outlined, 'Bu dönemde Z alınmış kasa oturumu yok.')
                  : _Satirlar([
                      ('Kapanan kasa oturumu', _sayi(g('cash_sessions_closed_count')), null),
                      ('Beklenen nakit', _tl(g('cash_sessions_expected_minor')), null),
                      ('Sayılan nakit', _tl(g('cash_sessions_counted_minor')), null),
                      ('Kasa farkı', kasaFark == 0 ? 'Fark yok' : _tl(kasaFark), kasaFark == 0 ? Kabuk.success : Kabuk.negative),
                    ]),
            )),
      ], gen),
    ];
  }

  /* ───────────────────────── BORÇLAR (web BorclarTab) ───────────────────────── */

  List<Widget> _borclar(double gen) {
    final o = _veri('receivables-summary');
    if (o != null && o['available'] != true) {
      return [_bosDonem('Borç (cari) kapalı', 'Bu işletmede borç hesabı (cari) kullanılmıyor.')];
    }
    int g(String k) => tamSayi(o?[k]);
    final net = g('net_degisim_minor');
    final kpi = <_Kpi>[
      _Kpi('Borca yazılan', o == null ? null : _tl(g('yazilan_minor')), alt: '${_sayi(g('yazilan_adet'))} adisyon · ${_sayi(g('yazilan_kisi'))} kişi', ton: Kabuk.warning),
      _Kpi('Borçtan tahsil edilen', o == null ? null : _tl(g('tahsil_minor')), alt: '${_sayi(g('tahsil_adet'))} tahsilat', ton: Kabuk.success),
      _Kpi('Borç iskontosu', o == null ? null : _tl(g('iskonto_minor')), alt: '${_sayi(g('iskonto_adet'))} kayıt'),
      _Kpi('Açık borç (dönem sonu)', o == null ? null : _tl(g('acik_borc_sonu_minor')),
          alt: net == 0 ? 'dönemde değişmedi' : (net > 0 ? '${_tl(net)} arttı' : '${_tl(-net)} azaldı'), ton: Kabuk.negative),
    ];
    return [
      _kpiler(kpi, gen, dar: 2, orta: 4, genis: 4),
      ..._diz([
        _odemeBolumu('Borç tahsilatı — ödeme yöntemi', 'receivables-summary', 'tahsil_yontemler', 'Bu dönemde borç tahsilatı yok.'),
        _tabloBolumu('Borç yaşlandırma', 'receivables-aging',
            const [_Sutun('label', 'Yaş'), _Sutun('count', 'Borç kaydı', _Tur.sayi, true), _Sutun('amount_minor', 'Tutar', _Tur.para, true)],
            toplam: true, bos: 'Açık borç yok.'),
        _tabloBolumu('Borç tahsilatları (döküm)', 'receivables-collections', const [
          _Sutun('at', 'Tarih', _Tur.saat),
          _Sutun('name', 'Şahıs'),
          _Sutun('method', 'Yöntem'),
          _Sutun('amount_minor', 'Tahsilat', _Tur.para, true),
          _Sutun('balance_after_minor', 'Kalan borç', _Tur.para),
          _Sutun('staff', 'Alan'),
        ], genis: true, toplam: true, bos: 'Bu dönemde borç tahsilatı yok.'),
        _tabloBolumu('Açık borcu olan şahıslar', 'ops-open-receivables',
            const [_Sutun('name', 'Şahıs'), _Sutun('phone', 'Telefon'), _Sutun('balance_minor', 'Bakiye', _Tur.para, true)],
            toplam: true, bos: 'Açık borcu olan şahıs yok.', vurgu: (s, r) => s.anahtar == 'balance_minor' ? Kabuk.negative : null),
      ], gen),
    ];
  }

  /* ───────────────────────── İNDİRİM · İPTAL (web IndirimIptalTab) ───────────────────────── */

  List<Widget> _indirim(double gen) {
    final d = _veri('finance-discounts');
    final s = _harita(d?['summary']);
    final f = _veri('finance-summary');
    final kpi = <_Kpi>[
      _Kpi('İndirim', d == null ? null : _tl(tamSayi(s['discount_total_minor']) + tamSayi(s['item_discount_minor'])),
          alt: '${_sayi(s['discounted_orders'] ?? 0)} / ${_sayi(s['orders_count'] ?? 0)} adisyon · ${_yuzde(s['discount_rate'] ?? 0)}', ton: Kabuk.warning),
      _Kpi('Kasa iskontosu', d == null ? null : _tl(tamSayi(s['iskonto_total_minor'])), alt: '${_sayi(s['iskonto_orders'] ?? 0)} adisyon'),
      _Kpi('İkram', f == null ? null : _tl(tamSayi(f['comp_minor'])), alt: 'ücretsiz verilen ürünler', ton: Kabuk.warning),
      _Kpi('İptal', f == null ? null : _tl(tamSayi(f['cancelled_minor'])), alt: '${_sayi(f?['cancelled_orders'] ?? 0)} adisyon', ton: Kabuk.negative),
    ];
    return [
      _kpiler(kpi, gen, dar: 2, orta: 4, genis: 4),
      ..._diz([
        _tabloBolumu('Nedenler', 'ops-cancellations', const [_Sutun('tur', 'Tür'), _Sutun('reason', 'Neden'), _Sutun('count', 'Adet', _Tur.sayi, true), _Sutun('value_minor', 'Değer', _Tur.para, true)],
            satirlar: (v) => [
                  for (final (a, t) in [('order_cancels', 'Adisyon iptali'), ('item_cancels', 'Ürün iptali'), ('comps', 'İkram')])
                    for (final r in _liste(v[a])) {...r, 'tur': t},
                ],
            bos: 'Bu dönemde iptal ya da ikram yok.'),
        _tabloBolumu('İndirimi kim yaptı, hangi gerekçeyle', 'finance-discounts',
            const [_Sutun('staff', 'Personel'), _Sutun('count', 'Adet', _Tur.sayi, true), _Sutun('amount_minor', 'Tutar', _Tur.para, true), _Sutun('max_minor', 'En büyük', _Tur.para)],
            anahtar: 'by_staff', bos: 'Bu dönemde indirim yok.', toplam: true),
        _tabloBolumu('İndirim gerekçeleri', 'finance-discounts',
            const [_Sutun('reason', 'Gerekçe'), _Sutun('count', 'Adet', _Tur.sayi, true), _Sutun('share', 'Pay', _Tur.yuzde), _Sutun('amount_minor', 'Tutar', _Tur.para, true)],
            anahtar: 'by_reason', bos: 'Bu dönemde indirim yok.'),
        _tabloBolumu('İndirim dökümü', 'finance-discounts', const [
          _Sutun('order_id', 'Adisyon'),
          _Sutun('table', 'Masa'),
          _Sutun('items_total_minor', 'Ürünler', _Tur.para),
          _Sutun('discount_minor', 'İndirim', _Tur.para, true),
          _Sutun('iskonto_minor', 'İskonto', _Tur.para, true),
          _Sutun('total_minor', 'Ödenecek', _Tur.para),
          _Sutun('reason', 'Gerekçe'),
          _Sutun('discount_by', 'Yapan'),
        ], genis: true, toplam: true, bos: 'Bu dönemde indirim yok.'),
        _tabloBolumu('İptal edilen adisyonlar', 'ops-eod-details', const [
          _Sutun('id', 'Adisyon'),
          _Sutun('table', 'Masa'),
          _Sutun('cancelled_at', 'Saat', _Tur.saat),
          _Sutun('total_minor', 'Tutar', _Tur.para, true),
          _Sutun('reason', 'Neden'),
          _Sutun('cancelled_by', 'İptal eden'),
        ], anahtar: 'cancelled_orders', toplam: true, bos: 'İptal edilen adisyon yok.'),
        _tabloBolumu('İptal ve ikram edilen ürünler', 'ops-eod-details', const [
          _Sutun('tur', 'Tür'),
          _Sutun('name', 'Ürün'),
          _Sutun('table', 'Masa'),
          _Sutun('qty', 'Adet', _Tur.sayi, true),
          _Sutun('amount_minor', 'Tutar', _Tur.para, true),
          _Sutun('reason', 'Neden'),
          _Sutun('by', 'Yapan'),
        ], satirlar: (v) => [
              for (final r in _liste(v['cancelled_items'])) {...r, 'tur': 'İptal'},
              for (final r in _liste(v['comps'])) {...r, 'tur': 'İkram'},
            ], toplam: true, bos: 'İptal ya da ikram edilen ürün yok.'),
      ], gen),
    ];
  }

  /* ───────────────────────── SERVİS (web OpsTab) ───────────────────────── */

  List<Widget> _servis(double gen) {
    final gec = _veri('ops-delayed');
    final ist = _veri('ops-station-prep');
    final sla = _veri('ops-delivery-sla');
    final tal = _veri('ops-service-requests');
    final yavas = _liste(ist?['rows']).fold<Map<String, dynamic>?>(null, (en, r) => en == null || tamSayi(r['avg_minutes']) > tamSayi(en['avg_minutes']) ? r : en);
    final acikTalep = _liste(tal?['rows']).fold<int>(0, (a, r) => a + tamSayi(r['open']));
    final gecSayi = _liste(gec?['rows']).length;
    final kpi = <_Kpi>[
      _Kpi('Şu an geciken', gec == null ? null : _sayi(gecSayi), alt: '${_sayi(gec?['threshold_minutes'] ?? 0)} dk üstü', ton: gecSayi > 0 ? Kabuk.negative : null),
      _Kpi('En yavaş istasyon', ist == null ? null : (yavas == null ? '—' : '${yavas['station']}'), alt: yavas == null ? null : 'ort. ${_sayi(yavas['avg_minutes'])} dk'),
      _Kpi('Komi SLA ihlali', sla == null ? null : _sayi(sla['breached_count'] ?? 0),
          alt: '${_yuzde(sla?['breach_rate'] ?? 0)} · hedef ${_sayi(sla?['target_minutes'] ?? 0)} dk', ton: tamSayi(sla?['breached_count']) > 0 ? Kabuk.warning : null),
      _Kpi('Yanıtlanmayan servis talebi', tal == null ? null : _sayi(acikTalep), ton: acikTalep > 0 ? Kabuk.negative : null),
    ];
    return [
      _kpiler(kpi, gen, dar: 2, orta: 4, genis: 4),
      ..._diz([
        _tabloBolumu('Şu an geciken siparişler', 'ops-delayed',
            const [_Sutun('id', 'Adisyon'), _Sutun('table', 'Masa'), _Sutun('status_label', 'Durum'), _Sutun('age_minutes', 'Yaş', _Tur.dk), _Sutun('total_minor', 'Tutar', _Tur.para)],
            bos: 'Geciken sipariş yok.'),
        _tabloBolumu('İstasyon hazırlama süreleri', 'ops-station-prep',
            const [_Sutun('station', 'İstasyon'), _Sutun('items', 'Kalem', _Tur.sayi), _Sutun('avg_minutes', 'Ortalama', _Tur.dk), _Sutun('max_minutes', 'En uzun', _Tur.dk)],
            bos: 'Bu dönemde hazırlık kaydı yok.'),
        _tabloBolumu('Servis talebine yanıt', 'ops-service-requests',
            const [_Sutun('label', 'Talep'), _Sutun('total', 'Toplam', _Tur.sayi, true), _Sutun('open', 'Açık', _Tur.sayi, true), _Sutun('avg_response_minutes', 'Ort. yanıt', _Tur.dk)],
            bos: 'Bu dönemde servis talebi yok.'),
        _tabloBolumu('Komi teslim SLA', 'ops-delivery-sla',
            const [_Sutun('name', 'Komi'), _Sutun('deliveries', 'Teslim', _Tur.sayi, true), _Sutun('breaches', 'İhlal', _Tur.sayi, true), _Sutun('breach_rate', 'Oran', _Tur.yuzde), _Sutun('avg_duration_minutes', 'Ort. süre', _Tur.dk)],
            anahtar: 'by_staff', bos: 'Bu dönemde komi teslimi yok.',
            ek: (v) => '${_sayi(v['total'] ?? 0)} teslim · ort. ${v['avg_duration_minutes'] == null ? '—' : '${_sayi(v['avg_duration_minutes'])} dk'}'),
        _tabloBolumu('QR / Kiosk kullanımı', 'ops-channel-usage',
            const [_Sutun('label', 'Kanal'), _Sutun('orders', 'Sipariş', _Tur.sayi, true), _Sutun('share', 'Pay', _Tur.yuzde)],
            anahtar: 'channels', bos: 'Bu dönemde QR okutulmadı.', ek: (v) => '${_sayi(v['orders_total'] ?? 0)} sipariş'),
      ], gen),
    ];
  }

  /* ───────────────────────── PERSONEL (web StaffTab) ───────────────────────── */

  List<Widget> _personel(double gen) => _diz([
        _Bolum('Personel performansı', ['staff-performance'], () {
          final s = _liste(_m('staff-performance')['rows']);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.length > 1)
              _Kart(
                baslik: 'Satış',
                ek: 'personel bazında',
                child: _YatayCubuklar(satirlar: [
                  for (final r in (List.of(s)..sort((a, b) => tamSayi(b['sales_minor']).compareTo(tamSayi(a['sales_minor'])))).take(8))
                    ('${r['name']}', tamSayi(r['sales_minor'])),
                ]),
              ),
            if (s.length > 1) const SizedBox(height: 10),
            _TabloKart(
              baslik: 'Personel performansı',
              sutunlar: const [
                _Sutun('name', 'Personel'),
                _Sutun('orders', 'Sipariş', _Tur.sayi, true),
                _Sutun('items', 'Kalem', _Tur.sayi, true),
                _Sutun('sales_minor', 'Satış', _Tur.para, true),
                _Sutun('avg_basket_minor', 'Ort. sepet', _Tur.para),
                _Sutun('avg_service_minutes', 'Ort. servis', _Tur.dk),
                _Sutun('discount_minor', 'İndirim', _Tur.para, true),
                _Sutun('comp_count', 'İkram', _Tur.sayi, true),
                _Sutun('comp_minor', 'İkram değeri', _Tur.para, true),
                _Sutun('cancelled', 'İptal', _Tur.sayi, true),
                _Sutun('cancel_rate', 'İptal oranı', _Tur.yuzde),
                _Sutun('requests_handled', 'Talep', _Tur.sayi, true),
              ],
              satirlar: s,
              toplam: true,
              bos: 'Bu dönemde personel satışı yok.',
            ),
          ]);
        }, genis: true, iskelet: 260),
      ], gen);

  /* ───────────────────────── DÖKÜM (web AdisyonDokumu) ───────────────────────── */

  Widget _dokumListesi(double yan) {
    final v = _veri(_dokum);
    final p = EdgeInsets.fromLTRB(yan, 0, yan, 28);
    if (v == null) {
      final h = _hata(_dokum);
      return ListView(padding: p, physics: const AlwaysScrollableScrollPhysics(), children: [
        _Kart(
          baslik: 'Adisyon dökümü',
          child: h != null ? _BosKutu(Icons.error_outline_rounded, h, eylem: () => _yukle(zorla: true)) : const _Iskelet(220),
        ),
      ]);
    }
    final satirlar = _liste(v['rows']);
    final toplam = satirlar.fold<int>(0, (a, r) => a + tamSayi(r['toplam_minor']));
    final ust = <Widget>[
      _kpiler([
        _Kpi('Adisyon', _sayi(satirlar.length), alt: v['kesildi'] == true ? 'liste kısaltıldı — dönemi daraltın' : 'dönemdeki tüm adisyonlar'),
        _Kpi('Toplam', _tl(toplam)),
      ], MediaQuery.sizeOf(context).width - yan * 2, dar: 2, orta: 2, genis: 2),
      if (satirlar.isEmpty) _bosDonem('Adisyon yok', 'Seçilen dönemde adisyon bulunmuyor.'),
    ];
    return ListView.builder(
      padding: p,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: ust.length + satirlar.length,
      itemBuilder: (_, i) {
        if (i < ust.length) return ust[i];
        final r = satirlar[i - ust.length];
        final id = tamSayi(r['id']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _AdisyonSatiri(
            r: r,
            acik: _acikAdisyon.contains(id),
            dokun: () => setState(() => _acikAdisyon.contains(id) ? _acikAdisyon.remove(id) : _acikAdisyon.add(id)),
          ),
        );
      },
    );
  }
}

/* ───────────────────────── ortak parçalar ───────────────────────── */

class _Kart extends StatelessWidget {
  const _Kart({required this.child, this.baslik, this.ek, this.sag, this.govdeBosluk = true});
  final Widget child;
  final String? baslik;
  final String? ek;
  final String? sag;
  final bool govdeBosluk;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (baslik != null)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
            child: Row(children: [
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: baslik, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: -.1)),
                    if (ek != null) TextSpan(text: '   $ek', style: TextStyle(fontSize: 11.5, color: Kabuk.soft, fontWeight: FontWeight.w500)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (sag != null) ...[
                const SizedBox(width: 8),
                Text(sag!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ]),
          ),
        if (govdeBosluk) Padding(padding: const EdgeInsets.all(12), child: child) else child,
      ]),
    );
  }
}

/// Veri gelene kadar kartın yerini tutan durağan iskelet (animasyonsuz:
/// zayıf cihazda sürekli boyama yok).
class _Iskelet extends StatelessWidget {
  const _Iskelet(this.yukseklik);
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    Widget cubuk(double oran, double h) => FractionallySizedBox(
          widthFactor: oran,
          alignment: Alignment.centerLeft,
          child: Container(height: h, decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(4))),
        );
    final satir = math.max(1, ((yukseklik - 40) / 26).floor());
    return SizedBox(
      height: yukseklik,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cubuk(.42, 14),
        const SizedBox(height: 14),
        for (var i = 0; i < satir; i++) ...[cubuk(i.isEven ? .92 : .74, 12), const SizedBox(height: 14)],
      ]),
    );
  }
}

class _BosKutu extends StatelessWidget {
  const _BosKutu(this.ikon, this.metin, {this.eylem, this.baslik});
  final IconData ikon;
  final String metin;
  final String? baslik;
  final VoidCallback? eylem;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(children: [
          Icon(ikon, size: 30, color: Kabuk.soft),
          const SizedBox(height: 8),
          if (baslik != null) ...[Text(baslik!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), const SizedBox(height: 4)],
          Text(metin, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Kabuk.soft, fontWeight: FontWeight.w600)),
          if (eylem != null) ...[const SizedBox(height: 8), TextButton(onPressed: eylem, child: const Text('Tekrar dene'))],
        ]),
      );
}

/// Rakam kutuları: sabit sütun sayısı (web: telefonda 2, ortada 5, genişte 10).
class _KpiIzgara extends StatelessWidget {
  const _KpiIzgara({required this.ogeler, required this.sutun, required this.genislik});
  final List<_Kpi> ogeler;
  final int sutun;
  final double genislik;

  @override
  Widget build(BuildContext context) {
    final n = math.max(1, math.min(sutun, ogeler.length));
    final gen = (genislik - (n - 1) * 8) / n;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final k in ogeler) SizedBox(width: gen, child: _KpiKutu(k)),
    ]);
  }
}

class _KpiKutu extends StatelessWidget {
  const _KpiKutu(this.k);
  final _Kpi k;

  @override
  Widget build(BuildContext context) {
    final ton = k.ton;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: Renk.yuzey,
        borderRadius: koseYuvarlak,
        border: Border.all(color: Kabuk.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (ton != null) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: ton, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 5)],
          Expanded(
            child: Text(k.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
          ),
        ]),
        const SizedBox(height: 3),
        SizedBox(
          height: 24,
          child: k.deger == null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Container(width: 76, height: 14, decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(4))),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(k.deger!,
                      style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w800, letterSpacing: -.3, color: ton ?? Kabuk.ink, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
        ),
        if (k.fark != null)
          _FarkYazisi(k.fark!)
        else
          Text(k.alt ?? ' ', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Kabuk.soft)),
      ]),
    );
  }
}

class _FarkYazisi extends StatelessWidget {
  const _FarkYazisi(this.f);
  final double f;

  @override
  Widget build(BuildContext context) {
    final arti = f >= 0;
    final renk = arti ? Kabuk.success : Kabuk.negative;
    return Row(children: [
      Icon(arti ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: renk),
      Flexible(
        child: Text(' ${_yuzde(f.abs())} önceki döneme göre',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: renk, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}

/// Etiket — değer satırları (köprü/özet listeleri).
class _Satirlar extends StatelessWidget {
  const _Satirlar(this.ogeler);
  final List<(String, String, Color?)> ogeler;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < ogeler.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: Kabuk.line))),
            child: Row(children: [
              Expanded(child: Text(ogeler[i].$1, style: TextStyle(fontSize: 12.5, color: Kabuk.soft, fontWeight: FontWeight.w600))),
              Text(ogeler[i].$2,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ogeler[i].$3 ?? Kabuk.ink, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
      ]);
}

/// Kart altı küçük şerit (web .rp-borc).
class _Serit extends StatelessWidget {
  const _Serit(this.ogeler);
  final List<(String, String, Color?)> ogeler;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
        decoration: BoxDecoration(color: Kabuk.sunken, border: Border(top: BorderSide(color: Kabuk.line))),
        child: Wrap(spacing: 16, runSpacing: 4, children: [
          for (final (ad, deger, renk) in ogeler)
            Text.rich(TextSpan(children: [
              TextSpan(text: '$ad  ', style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
              TextSpan(text: deger, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: renk ?? Kabuk.ink)),
            ])),
        ]),
      );
}

TextStyle _thStil() => TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Kabuk.soft);

/// Oran tablosu (web .rp-tbl): Oran (yüzde + pay çubuğu) · Ad · Adet · Tutar.
class _OranTablosu extends StatelessWidget {
  const _OranTablosu({required this.adBaslik, required this.satirlar, required this.bos, this.nokta = false});
  final String adBaslik;
  final List<_Oran> satirlar;
  final String bos;
  final bool nokta;

  @override
  Widget build(BuildContext context) {
    if (satirlar.isEmpty) return _BosKutu(Icons.inbox_outlined, bos);
    Widget satir({required Widget oran, required Widget ad, required Widget adet, required Widget tutar, bool ust = false}) => Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: ust ? 6 : 7),
          decoration: BoxDecoration(color: ust ? Kabuk.sunken : null, border: ust ? null : Border(top: BorderSide(color: Kabuk.line))),
          child: Row(children: [
            SizedBox(width: 62, child: oran),
            const SizedBox(width: 8),
            Expanded(child: ad),
            SizedBox(width: 50, child: Align(alignment: Alignment.centerRight, child: adet)),
            SizedBox(width: 100, child: Align(alignment: Alignment.centerRight, child: tutar)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      satir(
        ust: true,
        oran: Text('ORAN', style: _thStil()),
        ad: Text(adBaslik.toUpperCase(), style: _thStil()),
        adet: Text('ADET', style: _thStil()),
        tutar: Text('TUTAR', style: _thStil()),
      ),
      for (final r in satirlar)
        satir(
          oran: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(_yuzde(r.pay * 100), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 3),
            Container(
              height: 3,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                widthFactor: math.max(.02, r.pay.clamp(0.0, 1.0)),
                child: Container(decoration: BoxDecoration(color: r.renk, borderRadius: BorderRadius.circular(2))),
              ),
            ),
          ]),
          ad: Row(children: [
            if (nokta) ...[Container(width: 8, height: 8, decoration: BoxDecoration(color: r.renk, borderRadius: BorderRadius.circular(2))), const SizedBox(width: 6)],
            Expanded(child: Text(r.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
          ]),
          adet: Text(_sayi(r.adet), style: const TextStyle(fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()])),
          tutar: Text(_tl(r.tutar), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ),
    ]);
  }
}

/// Başlıklı tablo kartı: ilk [_onizleme] satır kartta, kalanı "Tümünü göster"
/// ile alt pencerede (ListView.builder — yüzlerce satır tek seferde çizilmez).
class _TabloKart extends StatelessWidget {
  const _TabloKart({required this.baslik, required this.sutunlar, required this.satirlar, this.ek, this.bos = 'Bu dönemde kayıt yok.', this.toplam = false, this.vurgu});
  final String baslik;
  final String? ek;
  final List<_Sutun> sutunlar;
  final List<Map<String, dynamic>> satirlar;
  final String bos;
  final bool toplam;
  final Color? Function(_Sutun, Map<String, dynamic>)? vurgu;

  static const _onizleme = 12;

  String? get _toplamMetni {
    final s = sutunlar.where((x) => x.toplanir && x.tur == _Tur.para).firstOrNull;
    if (s == null || satirlar.isEmpty) return null;
    return _tl(satirlar.fold<int>(0, (a, r) => a + tamSayi(r[s.anahtar])));
  }

  @override
  Widget build(BuildContext context) {
    final fazla = satirlar.length > _onizleme;
    return _Kart(
      baslik: baslik,
      ek: ek,
      sag: toplam ? _toplamMetni : null,
      govdeBosluk: false,
      child: satirlar.isEmpty
          ? _BosKutu(Icons.inbox_outlined, bos)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Tablo(sutunlar: sutunlar, satirlar: fazla ? satirlar.take(_onizleme).toList() : satirlar, toplamSatirlar: toplam ? satirlar : null, vurgu: vurgu),
              if (fazla)
                InkWell(
                  onTap: () => _tumu(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
                    alignment: Alignment.center,
                    child: Text('Tümünü göster (${_sayi(satirlar.length)})', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Kabuk.brand)),
                  ),
                ),
            ]),
    );
  }

  void _tumu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Renk.yuzey,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * .86,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text('$baslik · ${_sayi(satirlar.length)} satır', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Expanded(child: _Tablo(sutunlar: sutunlar, satirlar: satirlar, toplamSatirlar: toplam ? satirlar : null, vurgu: vurgu, kaydir: true)),
        ]),
      ),
    );
  }
}

/// Genel tablo: sütunlar sığarsa ilk sütun genişler; sığmazsa yatay kayar.
class _Tablo extends StatelessWidget {
  const _Tablo({required this.sutunlar, required this.satirlar, this.toplamSatirlar, this.vurgu, this.kaydir = false});
  final List<_Sutun> sutunlar;
  final List<Map<String, dynamic>> satirlar;

  /// Verilirse altta "Toplam" satırı (toplanır sütunlar).
  final List<Map<String, dynamic>>? toplamSatirlar;
  final Color? Function(_Sutun, Map<String, dynamic>)? vurgu;

  /// true: dikey ListView.builder (alt pencere).
  final bool kaydir;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, k) {
      const ic = 10.0;
      var gerek = sutunlar.fold<double>(0, (a, s) => a + s.genislik) + ic * 2;
      // Dar ekranda ilk (ad) sütunu 84 px'e kadar daralır: telefonda yatay
      // kaydırma yalnız gerçekten çok sütunlu tablolarda kalır.
      if (gerek > k.maxWidth && sutunlar.first.tur == _Tur.metin) {
        gerek -= math.min(sutunlar.first.genislik - 84, gerek - k.maxWidth);
      }
      final sigar = gerek <= k.maxWidth + .5;
      final ekstra = sigar ? k.maxWidth - gerek : 0.0;
      final ilk = gerek - ic * 2 - sutunlar.skip(1).fold<double>(0, (a, s) => a + s.genislik);
      final genislikler = [for (var i = 0; i < sutunlar.length; i++) (i == 0 ? ilk : sutunlar[i].genislik) + (i == 0 ? ekstra : 0)];
      final toplamGen = sigar ? k.maxWidth : gerek;

      Widget satir(List<Widget> hucreler, {Color? zemin, bool cizgi = true}) => Container(
            width: toplamGen,
            padding: const EdgeInsets.symmetric(horizontal: ic, vertical: 8),
            decoration: BoxDecoration(color: zemin, border: cizgi ? Border(top: BorderSide(color: Kabuk.line)) : null),
            child: Row(children: [
              for (var i = 0; i < sutunlar.length; i++)
                SizedBox(
                  width: genislikler[i],
                  child: Align(alignment: sutunlar[i].sayisal ? Alignment.centerRight : Alignment.centerLeft, child: hucreler[i]),
                ),
            ]),
          );

      final baslik = satir([
        for (var i = 0; i < sutunlar.length; i++)
          Padding(
            padding: EdgeInsets.only(right: i < sutunlar.length - 1 && !sutunlar[i].sayisal ? 8 : 0),
            child: Text(sutunlar[i].ad.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: _thStil()),
          ),
      ], zemin: Kabuk.sunken, cizgi: false);

      Widget veriSatiri(Map<String, dynamic> r) => satir([
            for (var i = 0; i < sutunlar.length; i++)
              Padding(
                padding: EdgeInsets.only(right: !sutunlar[i].sayisal ? 8 : 0),
                child: Text(
                  sutunlar[i].yaz(r[sutunlar[i].anahtar]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: i == 0 ? FontWeight.w600 : (sutunlar[i].tur == _Tur.para ? FontWeight.w700 : FontWeight.w500),
                    color: vurgu?.call(sutunlar[i], r) ?? Kabuk.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ]);

      final ts = toplamSatirlar;
      final toplamSatiri = ts == null || !sutunlar.any((s) => s.toplanir)
          ? null
          : satir([
              for (var i = 0; i < sutunlar.length; i++)
                Text(
                  i == 0
                      ? 'Toplam'
                      : sutunlar[i].toplanir
                          ? sutunlar[i].yaz(ts.fold<num>(0, (a, r) => a + (r[sutunlar[i].anahtar] is num ? r[sutunlar[i].anahtar] as num : 0)))
                          : '',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                ),
            ], zemin: Kabuk.sunken);

      Widget govde;
      if (kaydir) {
        govde = SizedBox(
          width: toplamGen,
          child: Column(children: [
            baslik,
            Expanded(
              child: ListView.builder(
                itemCount: satirlar.length,
                itemExtent: 37,
                itemBuilder: (_, i) => veriSatiri(satirlar[i]),
              ),
            ),
            ?toplamSatiri,
          ]),
        );
      } else {
        govde = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          baslik,
          for (final r in satirlar) veriSatiri(r),
          ?toplamSatiri,
        ]);
      }
      return sigar ? govde : SingleChildScrollView(scrollDirection: Axis.horizontal, child: govde);
    });
  }
}

/* ───────────────────────── grafikler ───────────────────────── */

/// Sütun grafiği kartı (web .rp-sutun): başlıkta en yoğun dilim ya da
/// dokunulan sütun + toplam. Dokununca sabitlenir, tekrar dokununca kalkar.
class _SutunKart extends StatefulWidget {
  const _SutunKart({required this.baslik, required this.birim, required this.noktalar, required this.bicim, required this.renk, required this.bos});
  final String baslik;
  final String birim;

  /// (eksen etiketi, başlık, değer)
  final List<(String, String, int)> noktalar;
  final String Function(int) bicim;
  final Color renk;
  final String bos;

  @override
  State<_SutunKart> createState() => _SutunKartState();
}

class _SutunKartState extends State<_SutunKart> {
  int? _vurgu;

  @override
  Widget build(BuildContext context) {
    final n = widget.noktalar;
    final degerler = [for (final x in n) x.$3];
    final toplam = degerler.fold<int>(0, (a, b) => a + b);
    final enCok = degerler.fold<int>(0, math.max);
    final tepe = enCok > 0 ? degerler.indexOf(enCok) : -1;
    final sec = _vurgu != null && _vurgu! < n.length ? _vurgu : null;
    final genis = MediaQuery.sizeOf(context).width >= 900;

    final ek = sec != null
        ? '${n[sec].$2} · ${widget.bicim(n[sec].$3)}'
        : (tepe >= 0 ? 'en yoğun ${widget.birim} ${n[tepe].$2} · ${widget.bicim(enCok)}' : null);
    return _Kart(
      baslik: widget.baslik,
      ek: ek,
      sag: widget.bicim(toplam),
      govdeBosluk: false,
      child: enCok <= 0
          ? Padding(padding: const EdgeInsets.all(12), child: Text(widget.bos, style: TextStyle(fontSize: 12, color: Kabuk.soft)))
          : Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
              child: SizedBox(
                height: genis ? 170 : 140,
                child: LayoutBuilder(builder: (context, k) {
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) {
                      final i = (d.localPosition.dx / (k.maxWidth / n.length)).floor().clamp(0, n.length - 1);
                      setState(() => _vurgu = _vurgu == i ? null : i);
                    },
                    child: RepaintBoundary(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: Hareket.kapali(context) ? 1 : 0, end: 1),
                        duration: Hareket.uzun,
                        curve: Hareket.giris,
                        builder: (_, t, _) => CustomPaint(
                          size: Size.infinite,
                          painter: _SutunRessami(
                            degerler: degerler,
                            etiketler: [for (final x in n) x.$1],
                            renk: widget.renk,
                            secili: sec ?? tepe,
                            t: t,
                            cizgi: Kabuk.line,
                            yazi: Kabuk.soft,
                            balon: sec == null ? null : widget.bicim(n[sec].$3),
                            balonZemin: Kabuk.ink,
                            balonYazi: Kabuk.surface,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
    );
  }
}

class _SutunRessami extends CustomPainter {
  _SutunRessami({
    required this.degerler,
    required this.etiketler,
    required this.renk,
    required this.secili,
    required this.t,
    required this.cizgi,
    required this.yazi,
    required this.balon,
    required this.balonZemin,
    required this.balonYazi,
  });
  final List<int> degerler;
  final List<String> etiketler;
  final Color renk;
  final int secili;
  final double t;
  final Color cizgi;
  final Color yazi;
  final String? balon;
  final Color balonZemin;
  final Color balonYazi;

  @override
  void paint(Canvas c, Size s) {
    if (degerler.isEmpty) return;
    const alt = 18.0, ust = 4.0;
    final h = s.height - alt - ust;
    final enCok = math.max(1, degerler.fold<int>(0, math.max));
    final n = degerler.length;
    final adim = s.width / n;
    final gen = math.max(3.0, math.min(26.0, adim * .66));
    final kalem = Paint()
      ..color = cizgi
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = ust + h - h * i / 2;
      c.drawLine(Offset(0, y), Offset(s.width, y), kalem);
    }
    final etiketAdim = math.max(1, (n / math.max(1, s.width / 30)).ceil());
    final soluk = Paint()..color = renk.withValues(alpha: .5);
    final tam = Paint()..color = renk;
    for (var i = 0; i < n; i++) {
      final oran = degerler[i] / enCok * t;
      final x = adim * i + (adim - gen) / 2;
      final yuk = math.max(degerler[i] > 0 ? 2.0 : 0.0, h * oran);
      c.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, ust + h - yuk, gen, yuk), topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        i == secili ? tam : soluk,
      );
      if (i % etiketAdim == 0) {
        final tp = TextPainter(text: TextSpan(text: etiketler[i], style: TextStyle(fontFamily: yaziTipi, fontSize: 10, color: yazi)), textDirection: TextDirection.ltr)..layout();
        tp.paint(c, Offset(adim * i + adim / 2 - tp.width / 2, ust + h + 4));
      }
    }
    // Dokunulan sütunun tutarı: sütunun üstünde kendi baloncuğu (web .ip).
    if (balon != null && secili >= 0 && secili < n) {
      final tp = TextPainter(
        text: TextSpan(text: balon, style: TextStyle(fontFamily: yaziTipi, fontSize: 11, fontWeight: FontWeight.w700, color: balonYazi)),
        textDirection: TextDirection.ltr,
      )..layout();
      final bw = tp.width + 12, bh = tp.height + 6;
      final ortaX = adim * secili + adim / 2;
      final yuk = math.max(2.0, h * degerler[secili] / enCok * t);
      final bx = (ortaX - bw / 2).clamp(0.0, s.width - bw);
      final by = math.max(0.0, ust + h - yuk - bh - 4);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(6)), Paint()..color = balonZemin);
      tp.paint(c, Offset(bx + 6, by + 3));
    }
  }

  @override
  bool shouldRepaint(_SutunRessami o) =>
      o.t != t || o.degerler != degerler || o.secili != secili || o.renk != renk || o.cizgi != cizgi || o.balon != balon;
}

/// Halka grafik (web .rp-halka): her dilim bir yay, ortada işlem sayısı.
class _HalkaRessami extends CustomPainter {
  _HalkaRessami(this.dilimler, this.iz, this.yazi, this.soluk, this.orta);
  final List<_Oran> dilimler;
  final Color iz;
  final Color yazi;
  final Color soluk;
  final String orta;

  @override
  void paint(Canvas c, Size s) {
    const kalinlik = 14.0;
    final r = Rect.fromCircle(center: s.center(Offset.zero), radius: s.shortestSide / 2 - kalinlik / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kalinlik;
    c.drawArc(r, 0, math.pi * 2, false, p..color = iz);
    var bas = -math.pi / 2;
    for (final d in dilimler) {
      if (d.pay <= 0) continue;
      final aci = d.pay * math.pi * 2;
      c.drawArc(r, bas, aci, false, p..color = d.renk);
      bas += aci;
    }
    final ust = TextPainter(text: TextSpan(text: orta, style: TextStyle(fontFamily: yaziTipi, fontSize: 17, fontWeight: FontWeight.w800, color: yazi)), textDirection: TextDirection.ltr)..layout();
    final alt = TextPainter(text: TextSpan(text: 'İŞLEM', style: TextStyle(fontFamily: yaziTipi, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: .6, color: soluk)), textDirection: TextDirection.ltr)
      ..layout();
    final m = s.center(Offset.zero);
    ust.paint(c, Offset(m.dx - ust.width / 2, m.dy - ust.height + 2));
    alt.paint(c, Offset(m.dx - alt.width / 2, m.dy + 2));
  }

  @override
  bool shouldRepaint(_HalkaRessami o) => o.dilimler != dilimler || o.iz != iz || o.orta != orta;
}

/// Yatay pay çubukları: ad · tutar · çubuk (en büyük = %100).
class _YatayCubuklar extends StatelessWidget {
  const _YatayCubuklar({required this.satirlar});
  final List<(String, int)> satirlar;

  @override
  Widget build(BuildContext context) {
    final enCok = math.max(1, satirlar.fold<int>(0, (a, s) => math.max(a, s.$2)));
    return Column(children: [
      for (var i = 0; i < satirlar.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: i == satirlar.length - 1 ? 0 : 9),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(satirlar[i].$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Text(_tl(satirlar[i].$2), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 4),
            Container(
              height: 6,
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(3)),
              child: FractionallySizedBox(
                widthFactor: (satirlar[i].$2 / enCok).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(color: _seri(i < 4 ? 0 : 4), borderRadius: BorderRadius.circular(3))),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Döküm satırı: adisyon başlığı; dokununca kalemler ve ödemeler açılır.
class _AdisyonSatiri extends StatelessWidget {
  const _AdisyonSatiri({required this.r, required this.acik, required this.dokun});
  final Map<String, dynamic> r;
  final bool acik;
  final VoidCallback dokun;

  @override
  Widget build(BuildContext context) {
    final iptal = '${r['durum']}' == 'cancelled';
    final kalemler = _liste(r['kalemler']);
    final odemeler = _liste(r['odemeler']);
    final saat = [r['acilis'], r['kapanis']].where((x) => x != null && '$x'.isNotEmpty).join(' – ');
    final etiket = <String>[
      if (tamSayi(r['indirim_minor']) > 0) 'İndirim ${_tl(tamSayi(r['indirim_minor']))}',
      if (tamSayi(r['iskonto_minor']) > 0) 'İskonto ${_tl(tamSayi(r['iskonto_minor']))}',
      if (tamSayi(r['ikram_minor']) > 0) 'İkram ${_tl(tamSayi(r['ikram_minor']))}',
      if (r['borc_minor'] != null && tamSayi(r['borc_minor']) > 0) 'Borç ${_tl(tamSayi(r['borc_minor']))}${r['borclu'] == null ? '' : ' · ${r['borclu']}'}',
    ];
    return Material(
      color: Renk.yuzey,
      borderRadius: koseYuvarlak,
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: dokun,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text('${r['baslik'] ?? 'Adisyon'}  ·  #${r['id']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              ),
              Text(_tl(tamSayi(r['toplam_minor'])),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: iptal ? Kabuk.negative : Kabuk.ink, decoration: iptal ? TextDecoration.lineThrough : null)),
              Icon(acik ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: Kabuk.soft),
            ]),
            const SizedBox(height: 3),
            Text(
              [r['durum_label'], saat, if (r['acan'] != null) r['acan'], '${kalemler.length} kalem'].where((x) => x != null && '$x'.isNotEmpty).join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: iptal ? Kabuk.negative : Kabuk.soft, fontWeight: FontWeight.w600),
            ),
            if (etiket.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(etiket.join('  ·  '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Kabuk.warning, fontWeight: FontWeight.w600)),
            ],
            if (acik) ...[
              const SizedBox(height: 8),
              for (final k in kalemler)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    SizedBox(width: 40, child: Text('${k['saat'] ?? ''}', style: TextStyle(fontSize: 11, color: Kabuk.soft))),
                    Expanded(
                      child: Text(
                        '${k['adet']} × ${k['ad']}${k['varyant'] == null ? '' : ' (${k['varyant']})'}${k['iptal'] == true ? ' — iptal' : ''}${k['ikram'] == true ? ' — ikram' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: k['iptal'] == true ? Kabuk.negative : Kabuk.ink,
                          decoration: k['iptal'] == true ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    Text(_tl(tamSayi(k['tutar_minor'])), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              if (odemeler.isNotEmpty) ...[
                Divider(height: 14, color: Kabuk.line),
                for (final o in odemeler)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      SizedBox(width: 40, child: Text('${o['saat'] ?? ''}', style: TextStyle(fontSize: 11, color: Kabuk.soft))),
                      Expanded(
                        child: Text('${o['yontem']}${o['kasiyer'] == null ? '' : ' · ${o['kasiyer']}'}',
                            style: TextStyle(fontSize: 12.5, color: Kabuk.success, fontWeight: FontWeight.w600)),
                      ),
                      Text(_tl(tamSayi(o['tutar_minor'])), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Kabuk.success)),
                    ]),
                  ),
              ],
              if (r['iptal_nedeni'] != null) Text('İptal nedeni: ${r['iptal_nedeni']}', style: TextStyle(fontSize: 11.5, color: Kabuk.negative)),
            ],
          ]),
        ),
      ),
    );
  }
}
