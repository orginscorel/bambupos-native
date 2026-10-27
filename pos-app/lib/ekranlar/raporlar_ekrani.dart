import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'giderler_ekrani.dart' show isGunuAraligi;
import 'gun_sonu_ekrani.dart' show GunSonuEkrani;
import 'ortak.dart';

/// RAPORLAR (1.2.16, 2026-10-27) — işletmenin verdiği REFERANS düzeni
/// (personelin alıştığı Kardo POS › Raporlar ekranı), bizim renk/yazı/8 px
/// köşe dilimizle; web paneli de aynı düzene geçiyor.
///
/// Sayfa tek kart:
///   · Başlık satırı: "Raporlar" + yanında "Rapor ▾" (diğer raporlar, gruplu
///     liste) · sağda Başlangıç / Bitiş tarih-saat kutuları (varsayılan: açık
///     iş günü, işletme günü saatinden ertesi gün aynı saate), Filtrele,
///     Yazdır. Tarihler Filtrele ile uygulanır; hazır dönemler (Bugün, Dün,
///     Son 7 gün…) tarih penceresinin içinde, tek dokunuşta uygular.
///   · Özet: on kutu (referanstaki dokuz + bizim "Borca Yazılan"), altında yan
///     yana iki sade tablo (Kategori · Ödeme Tipi: Oran | Ad | Adet | Fiyat),
///     dönemde borca yazılan varsa altında "Borca Yazdıranlar". Grafik YOK
///     (saatlik ciro "Ciro" raporunda). Geniş ekranda sayfa kaymaz, tablolar
///     kendi içinde kayar; telefonda kutular 2'li, tablolar alt alta.
///   · Yazdır: Özet'i kasa yazıcısına sade fiş olarak yollar
///     (/api/v1/print/receipt — kasa ekranındaki fişlerle aynı yol).
///   · Diğer raporlar aynı uçlar ve kartlarla, aynı sade tablo diliyle.
///
/// Veri web ile AYNI uçlardan (/api/v1/reports/{rapor}); elle saat seçilirse
/// window_from/window_to da gider. Uçlar paralel çekilir, dönem anahtarıyla
/// bellekte tutulur; her bölüm kendi iskeletini gösterir. Grafikler tek
/// CustomPainter + RepaintBoundary; uzun listeler ListView.builder;
/// bulanıklık yok.

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

/// Web belirteçleri (pos-kabuk.css .sy + app.css --ui-*). Kabuk'ta olmayanlar.
abstract final class _W {
  static bool get _k => koyuTema.value;

  /// --ui-text-muted (text-muted): StatTile etiketi, tablo başlığı.
  static Color get muted => _k ? const Color(0xFFC2CBDA) : const Color(0xFF475569);

  /// --ui-text-subtle (text-subtle) = --soft.
  static Color get subtle => Kabuk.soft;

  /// RaporKart / StatTile zemini (bg-raised).
  static Color get raised => Renk.yuzey;

  /// viz.css ızgara ve eksen çizgileri.
  static Color get grid => _k ? const Color(0xFF2C2C2A) : const Color(0xFFE7E5E4);
  static Color get axis => _k ? const Color(0xFF383835) : const Color(0xFFD6D3D1);
}

/// Web viz paleti (viz.css): sabit sıra mavi → turuncu → deniz yeşili → sarı,
/// 4'ten sonrası "Diğer" grisi.
Color _seri(int i) {
  const acik = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A), Color(0xFFEDA100)];
  const koyu = [Color(0xFF3987E5), Color(0xFFD95926), Color(0xFF199E70), Color(0xFFC98500)];
  if (i >= 4) return const Color(0xFF898781);
  return koyuTema.value ? koyu[i] : acik[i];
}

const _tabular = [FontFeature.tabularFigures()];

/* ───────────────────────── tanımlar ───────────────────────── */

/// Web YAPRAKLAR (Index.vue): (anahtar, grup, ad). Dışa aktar yok — dosya
/// indirme kasada yok.
const _yapraklar = <(String, String, String)>[
  ('ozet', 'Özet', 'Özet'),
  ('satis-ciro', 'Satış', 'Ciro'),
  ('satis-urun', 'Satış', 'Ürünler'),
  ('satis-kar', 'Satış', 'Kârlılık'),
  ('gunsonu', 'Kasa', 'Gün sonu'),
  ('tahsilat', 'Kasa', 'Tahsilat'),
  ('mutabakat', 'Kasa', 'Mutabakat'),
  ('borclar', 'Borçlar', 'Borçlar'),
  ('adisyon-dokum', 'Adisyonlar', 'Döküm'),
  ('indirim', 'Adisyonlar', 'İndirim · iptal'),
  ('servis', 'Operasyon', 'Servis'),
  ('personel', 'Operasyon', 'Personel'),
];

/// Web presets (Index.vue) — aynı ad, aynı sıra.
const _hazirlar = <(String, String)>[
  ('bugun', 'Bugün'),
  ('dun', 'Dün'),
  ('hafta', 'Son 7 gün'),
  ('otuz', 'Son 30 gün'),
  ('ay', 'Bu ay'),
  ('gecenay', 'Geçen ay'),
  ('ozel', 'Özel aralık'),
];

/// RaporKart başlığı → (web simgesi, açıklama satırı). Web sekmelerindeki
/// `note` metinleri birebir.
const _kartlar = <String, (IconData, String)>{
  'Saatlik ciro': (Icons.bar_chart_rounded, 'Seçili günde saat saat kapanan adisyonların toplamı.'),
  'Günlük ciro': (Icons.bar_chart_rounded, 'Gün gün kapanan adisyonların toplamı; eğilimi buradan okursunuz.'),
  'Yoğun saatler': (Icons.schedule_rounded, 'Saat başına sipariş adedi — vardiya ve mutfak planı için.'),
  'Sipariş kanalı': (Icons.shopping_cart_outlined, 'Ciro hangi kanaldan geldi: masa, QR, paket, gel-al.'),
  'Masa hizmeti': (Icons.people_outline_rounded, 'Kaç masa grubu ağırlandı, kaçının ödemesi alındı, kaçı borca yazıldı.'),
  'Şu an açık masalarda bekleyen ürünler': (
    Icons.schedule_rounded,
    'Hesabı kapanmadığı için satış rakamlarına DAHİL DEĞİL; adisyon kapanınca listeye girer. Anlık bilgidir, dönem filtresinden etkilenmez.',
  ),
  'Kategori satışları': (Icons.sell_outlined, 'Hangi kategori ne kadar sattı ve içindeki ürünler.'),
  'En çok satan ürünler': (Icons.shopping_cart_outlined, 'Adete göre sıralı.'),
  'En az satan ürünler': (Icons.inventory_2_outlined, 'Bu dönemde satılmış ama az satmış kalemler; hiç satılmayanlar menü katalogundan izlenir.'),
  'Varyant satışları': (Icons.list_rounded, 'Aynı ürünün hangi varyantı (boy, şeker, ekstra) satıldı.'),
  'Masa satışları ve devir': (Icons.content_paste_rounded, 'Masa başına adisyon, devir ve ortalama oturma süresi.'),
  'İkram maliyeti': (Icons.inventory_2_outlined, 'İkram gelir getirmez ama stok tüketir; net kârdan düşülür.'),
  'Çok satan ama düşük kârlı': (Icons.warning_amber_rounded, 'Ciroyu taşıyan ama marjı düşük ürünler — fiyat/porsiyon gözden geçirilmeli.'),
  'Ürün kârlılığı': (Icons.bar_chart_rounded, 'Satış fiyatı ile reçete/stok maliyeti arasındaki fark; maliyeti girilmemiş ürünler hesaba katılmaz.'),
  'Para neyle alındı': (Icons.account_balance_wallet_outlined, 'Adisyon ödemeleri ve borç tahsilatı birlikte; yüzdeler kasaya giren toplam üzerinden.'),
  'Satıştan nete iniş ve KDV': (Icons.percent_rounded, 'Kalem toplamından net satışa kadar her kesinti; KDV oranlarına göre dağılım.'),
  'Kasa oturumları (Z) ve kasa farkı': (Icons.storefront_outlined, 'Her oturumda beklenen ve sayılan nakit; fark varsa kim açmıştı.'),
  'Bakiyesi kalan adisyonlar': (Icons.content_paste_rounded, 'Kısmen ödenmiş ya da hiç ödenmemiş adisyonlar; şahıs borçları Borçlar raporundadır.'),
  'Ödeme defteri ↔ sistemdeki adisyon toplamı': (Icons.check_circle_outline_rounded, 'İki defter aynı parayı iki yerden sayar; tutmaları gerekir.'),
  'Beklenen nakit ↔ sayılan nakit': (Icons.storefront_outlined, 'Kapanan (Z alınmış) kasa oturumlarının sayımı.'),
  'Borç tahsilatı — ödeme yöntemi': (Icons.account_balance_wallet_outlined, 'Borçtan gelen para neyle alındı: nakit, kart, havale.'),
  'Borç yaşlandırma': (Icons.schedule_rounded, 'Kalan bakiye ne kadar eskidi; tahsilat en eski borçtan düşer.'),
  'Borç tahsilatları (döküm)': (Icons.receipt_outlined, 'Kim, ne zaman, neyle, ne kadar ödedi; kalan borcu ne oldu.'),
  'Açık borcu olan şahıslar': (Icons.people_outline_rounded, 'Güncel bakiyeler (dönemden bağımsız); en yüksek 10 borç.'),
  'Nedenler': (Icons.sticky_note_2_outlined, 'Aynı dönemde iptal ve ikramların gerekçeye göre toplamı.'),
  'İndirimi kim yaptı, hangi gerekçeyle': (Icons.people_outline_rounded, 'Gerekçe ve personel dağılımı; sızıntı buradan görünür.'),
  'İndirim dökümü': (Icons.sell_outlined, 'Adisyon adisyon: ne kadar indirildi, kim yaptı, kim onayladı.'),
  'İptal edilen adisyonlar': (Icons.cancel_outlined, 'Kim iptal etti, neden etti, adisyonda ne vardı.'),
  'İptal ve ikram edilen ürünler': (Icons.inventory_2_outlined, 'Kalem kalem: saat, adisyon, kim yaptı, hangi sebeple.'),
  'Şu an geciken siparişler': (Icons.schedule_rounded, 'Anlık liste; seçili döneme değil ŞU ANA bakar.'),
  'İstasyon hazırlama süreleri': (Icons.soup_kitchen_outlined, "Kalem 'hazır' işaretlenene kadar geçen süre."),
  'Servis talebine yanıt': (Icons.notifications_none_rounded, 'Masadan gelen çağrı/hesap/su talepleri ve yanıt süresi.'),
  'Komi teslim SLA': (Icons.local_shipping_outlined, 'Mutfaktan alınan ürün masaya kaç dakikada gitti.'),
  'QR / Kiosk kullanımı': (Icons.qr_code_2_rounded, 'Müşterinin kendi telefonundan verdiği sipariş ve QR okutma sayısı.'),
  'Personel performansı': (Icons.people_outline_rounded, 'Kapanan adisyonlar personele göre: kaç adisyon, ne kadar ciro, ortalama sepet.'),
  'Adisyon dökümü': (Icons.receipt_long_outlined, 'Her adisyon: saatleri, kalemleri, ödemeleri, taşıma ve düzeltmeler.'),
};

const _borcListesi = 'borca-yazilanlar';
const _dokum = 'adisyon-dokumu';

/// Sütun türü (web ReportTable format).
enum _Tur { para, sayi, yuzde, metin, saat, dk }

class _Sutun {
  const _Sutun(this.anahtar, this.ad, [this.tur = _Tur.metin, this.toplanir = false]);
  final String anahtar;
  final String ad;
  final _Tur tur;
  final bool toplanir;

  bool get sayisal => tur != _Tur.metin && tur != _Tur.saat;

  double get genislik => switch (tur) {
        _Tur.para => 96,
        _Tur.sayi || _Tur.yuzde || _Tur.dk => 66,
        _Tur.saat => 62,
        _Tur.metin => 130,
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

/// StatTile (web components/StatTile.vue).
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

/// Ekrandaki bir kart: başlığı (iskelet için), beklediği uçlar ve çizimi.
class _Bolum {
  const _Bolum(this.baslik, this.uclar, this.ciz, {this.genis = true, this.iskelet = 140});
  final String baslik;
  final List<String> uclar;

  /// null döndürürse kart gizlenir (ör. borç özelliği kapalı).
  final Widget? Function() ciz;

  /// true: tam genişlik. false: web `grid xl:grid-cols-2` içindeki kart —
  /// ≥1280 px'te bir sonraki yarım kartla yan yana.
  final bool genis;
  final double iskelet;
}

/* ───────────────────────── ekran ───────────────────────── */

class RaporlarEkrani extends StatefulWidget {
  const RaporlarEkrani({super.key});

  @override
  State<RaporlarEkrani> createState() => _RaporlarEkraniState();
}

class _RaporlarEkraniState extends State<RaporlarEkrani> {
  late final Api _api = context.api;

  /// Seçili hazır dönem ('ozel' = elle girilen saatli aralık).
  String _hazir = 'bugun';
  String _bugun = '';
  String? _dun;

  /// İşletme gününün başladığı saat (eod/durum gun_baslangic_saati).
  int _gunSaati = 0;

  /// Rapora GİDEN pencere (yalnız Filtrele / hazır dönemle değişir).
  late DateTime _bas;
  late DateTime _bit;

  /// Kutulardaki taslak pencere (Filtrele'ye basılana kadar rapora gitmez).
  late DateTime _tBas;
  late DateTime _tBit;

  /// true: pencere saatleri elle seçildi → window_from/window_to gönderilir.
  /// Hazır dönemde sunucu pencereyi kendisi kurar (gün sonu kapanışına göre).
  bool _pencereli = false;

  String _aktif = 'ozet';
  int _yon = 1;

  bool _basiliyor = false;

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
    _pencereKur(_bugun, _bugun);
    // İş günü okunurken takvim günüyle hemen çekmeye başla: ilk ekran beklemez.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _yukle();
    });
    _isGunuOku();
  }

  /// İş günü aralığı → saatli pencere: from günü SS:00 → (to + 1 gün) SS:00.
  void _pencereKur(String from, String to) {
    final f = DateTime.tryParse(from) ?? DateTime.now();
    final t = DateTime.tryParse(to) ?? f;
    _bas = _tBas = DateTime(f.year, f.month, f.day, _gunSaati);
    _bit = _tBit = DateTime(t.year, t.month, t.day + 1, _gunSaati);
    _pencereli = false;
  }

  Future<void> _isGunuOku() async {
    try {
      final d = _harita(await _api.get('/api/v1/reports/eod/durum'));
      final g = '${d['is_gunu'] ?? ''}';
      if (g.length >= 10) _bugun = g.substring(0, 10);
      _gunSaati = tamSayi(d['gun_baslangic_saati']).clamp(0, 23);
      final dun = _harita(d['son_kapanis'])['is_gunu'];
      _dun = dun == null ? null : '$dun'.substring(0, math.min(10, '$dun'.length));
    } on ApiHata {
      // takvim günüyle devam (web ile aynı)
    }
    if (!mounted || _hazir == 'ozel') return;
    final a = _aralik(_hazir);
    if (a == null) return;
    final eski = _donem;
    setState(() => _pencereKur(a.$1, a.$2));
    if (_donem != eski) _yukle();
  }

  (String, String)? _aralik(String h) {
    if (h == 'gecenay') {
      final b = DateTime.tryParse(_bugun) ?? DateTime.now();
      return (_gun(DateTime(b.year, b.month - 1, 1)), _gun(DateTime(b.year, b.month, 0)));
    }
    return isGunuAraligi(h, _bugun, _dun);
  }

  /// Hazır dönem tek dokunuşta uygular (aynı döneme yeniden basmak yeniler).
  void _hazirSec(String h) {
    final a = _aralik(h);
    if (a == null) return;
    final eski = _donem;
    setState(() {
      _hazir = h;
      _pencereKur(a.$1, a.$2);
      _hatalar.clear();
    });
    _yukle(zorla: _donem == eski);
  }

  bool get _aralikTers => !_tBit.isAfter(_tBas);

  /// Filtrele: taslak pencere rapora gider.
  void _filtrele() {
    if (_aralikTers) return;
    final eski = _donem;
    setState(() {
      final degisti = _tBas != _bas || _tBit != _bit;
      _bas = _tBas;
      _bit = _tBit;
      if (degisti) {
        _hazir = 'ozel';
        _pencereli = true;
      }
      _hatalar.clear();
    });
    _yukle(zorla: _donem == eski);
  }

  /// İş günü: pencere başlangıç saatinden önceki an bir önceki güne yazılır.
  String _isGunuOf(DateTime t) => _gun(t.subtract(Duration(hours: _gunSaati)));
  String get _from => _isGunuOf(_bas);
  String get _to => _isGunuOf(_bit.subtract(const Duration(minutes: 1)));
  String _pencereYazi(DateTime t) => '${_gun(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Map<String, String> get _sorgu => {
        'from': _from,
        'to': _to,
        if (_pencereli) 'window_from': _pencereYazi(_bas),
        if (_pencereli) 'window_to': _pencereYazi(_bit),
      };

  String get _donem => _pencereli ? '${_pencereYazi(_bas)}|${_pencereYazi(_bit)}' : '$_from|$_to';
  bool get _tekGun => _from == _to;

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
    final sorgu = _sorgu;
    final istenen = _uclar(_aktif).where((uc) {
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
        final v = await _api.get('/api/v1/reports/$uc', sorgu: sorgu);
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

  void _raporSec(String k) {
    if (k == _aktif) return;
    final eski = _yapraklar.indexWhere((y) => y.$1 == _aktif);
    final yeni = _yapraklar.indexWhere((y) => y.$1 == k);
    setState(() {
      _yon = yeni > eski ? 1 : -1;
      _aktif = k;
    });
    _yukle();
  }

  Map<String, dynamic>? _veri(String uc) => _bellek['$_donem|$uc'];
  Map<String, dynamic> _m(String uc) => _veri(uc) ?? const {};
  String? _hata(String uc) => _hatalar['$_donem|$uc'];

  /* ───────────────────────── sayfa kartı + başlık satırı ───────────────────────── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final tel = g < 700;
    final dis = tel ? 8.0 : 16.0;
    final ic = tel ? 12.0 : 20.0;
    return ColoredBox(
      color: Kabuk.surface,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 13, color: Kabuk.ink, height: 1.4),
        child: Padding(
          padding: EdgeInsets.all(dis),
          // TEK SAYFA KARTI (referans): başlık satırı, ince ayraç, rapor.
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak),
            padding: EdgeInsets.fromLTRB(ic, tel ? 10 : 14, ic, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _baslikSatiri(g),
              Container(height: 1, color: Kabuk.line),
              SizedBox(height: tel ? 10 : 14),
              Expanded(
                child: EkranGecisi(
                  anahtar: _aktif,
                  yon: _yon,
                  child: switch (_aktif) {
                    'gunsonu' => const GunSonuEkrani(gomulu: true),
                    'ozet' => _ozet(g),
                    'adisyon-dokum' => _dokumListesi(g),
                    _ => _govde(g),
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Raporlar [Rapor ▾] ……… [Başlangıç] [Bitiş] [Filtrele] [Yazdır]
  Widget _baslikSatiri(double g) {
    final tel = g < 700;
    final h = tel ? 36.0 : 38.0;
    final filtre = _aktif != 'gunsonu';
    final ozet = _aktif == 'ozet';
    final rapor = _yapraklar.firstWhere((y) => y.$1 == _aktif).$3;

    final sol = [
      Text('Raporlar', style: TextStyle(fontSize: tel ? 15 : 16, fontWeight: FontWeight.w700, color: Kabuk.ink)),
      const SizedBox(width: 10),
      Flexible(child: _SecimKutusu(metin: rapor, yukseklik: h, enAz: 0, onTap: _raporAc)),
    ];
    final bas = _TarihKutusu(metin: _kutuZamani(_tBas), ipucu: 'Başlangıç', yukseklik: h, onTap: _donemPenceresi);
    final bit = _TarihKutusu(metin: _kutuZamani(_tBit), ipucu: 'Bitiş', yukseklik: h, onTap: _donemPenceresi);
    final yazdir = _Dugme(metin: tel ? null : 'Yazdır', ipucu: 'Yazdır', ikon: Icons.print_outlined, yukseklik: h, onTap: _basiliyor ? null : _yazdir);
    const ara = SizedBox(width: 6);

    if (!tel) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          ...sol,
          const SizedBox(width: 12),
          const Spacer(),
          if (filtre) ...[
            bas,
            ara,
            bit,
            ara,
            _Dugme(metin: 'Filtrele', ikon: Icons.search_rounded, yukseklik: h, onTap: _aralikTers ? null : _filtrele),
          ],
          if (ozet) ...[ara, yazdir],
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [...sol, const Spacer(), if (ozet) ...[ara, yazdir]]),
        if (filtre) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: bas),
            ara,
            Expanded(child: bit),
            ara,
            _Dugme(metin: g >= 440 ? 'Filtrele' : null, ipucu: 'Filtrele', ikon: Icons.search_rounded, yukseklik: h, onTap: _aralikTers ? null : _filtrele),
          ]),
        ],
      ]),
    );
  }

  /// "27.10.2026 07:00"
  String _kutuZamani(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Tarih kutusu: hazır dönemler (tek dokunuşta uygular) + başlangıç/bitiş
  /// tarih ve saat seçimi (Filtrele ile uygulanır). Telefonda alt pencere,
  /// tablette ortada pencere.
  Future<void> _donemPenceresi() async {
    final tel = MediaQuery.sizeOf(context).width < 700;
    String gunYazi(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
    String saatYazi(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    Widget icerik(BuildContext c, StateSetter yenile) {
      Future<void> tarih(bool basMi) async {
        final simdi = basMi ? _tBas : _tBit;
        final t = await showDatePicker(
          context: c,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 2)),
          initialDate: simdi,
          locale: const Locale('tr', 'TR'),
          helpText: basMi ? 'Başlangıç' : 'Bitiş',
        );
        if (t == null) return;
        final yeni = DateTime(t.year, t.month, t.day, simdi.hour, simdi.minute);
        setState(() => basMi ? _tBas = yeni : _tBit = yeni);
        yenile(() {});
      }

      Future<void> saat(bool basMi) async {
        final simdi = basMi ? _tBas : _tBit;
        final t = await showTimePicker(
          context: c,
          initialTime: TimeOfDay(hour: simdi.hour, minute: simdi.minute),
          helpText: basMi ? 'Başlangıç saati' : 'Bitiş saati',
          builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
        );
        if (t == null) return;
        final yeni = DateTime(simdi.year, simdi.month, simdi.day, t.hour, t.minute);
        setState(() => basMi ? _tBas = yeni : _tBit = yeni);
        yenile(() {});
      }

      Widget satir(String ad, bool basMi) {
        final t = basMi ? _tBas : _tBit;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 82, child: Text(ad, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Kabuk.soft))),
            Expanded(child: _TarihKutusu(metin: gunYazi(t), ipucu: ad, yukseklik: 42, onTap: () => tarih(basMi))),
            const SizedBox(width: 6),
            SizedBox(width: 96, child: _TarihKutusu(metin: saatYazi(t), ipucu: '$ad saati', ikon: Icons.schedule_rounded, yukseklik: 42, onTap: () => saat(basMi))),
          ]),
        );
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(16, tel ? 0 : 16, 16, 16 + MediaQuery.paddingOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Tarih aralığı', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (k, ad) in _hazirlar.where((x) => x.$1 != 'ozel'))
              _Dugme(
                metin: ad,
                yukseklik: 40,
                secili: _hazir == k,
                onTap: () {
                  Navigator.pop(c);
                  _hazirSec(k);
                },
              ),
          ]),
          const SizedBox(height: 16),
          satir('Başlangıç', true),
          satir('Bitiş', false),
          if (_aralikTers)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Bitiş, başlangıçtan sonra olmalı.', style: TextStyle(fontSize: 12, color: Kabuk.negative)),
            ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _Dugme(metin: 'Kapat', yukseklik: 40, onTap: () => Navigator.pop(c)),
            const SizedBox(width: 6),
            _Dugme(
              metin: 'Filtrele',
              ikon: Icons.search_rounded,
              yukseklik: 40,
              ana: true,
              onTap: _aralikTers
                  ? null
                  : () {
                      Navigator.pop(c);
                      _filtrele();
                    },
            ),
          ]),
        ]),
      );
    }

    if (tel) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Kabuk.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
        builder: (c) => StatefulBuilder(builder: icerik),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          backgroundColor: Kabuk.surface,
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: StatefulBuilder(builder: icerik)),
        ),
      );
    }
  }

  Future<void> _raporAc() async {
    final s = await _secimAc('Rapor', [for (final (k, grup, ad) in _yapraklar) (grup, k, ad)], _aktif);
    if (s != null) _raporSec(s);
  }

  /// Rapor listesi (gruplu) alt pencerede.
  Future<String?> _secimAc(String baslik, List<(String?, String, String)> ogeler, String secili) async {
    final tel = MediaQuery.sizeOf(context).width < 700;
    final gruplar = <(String?, List<(String, String)>)>[];
    for (final (grup, k, ad) in ogeler) {
      if (gruplar.isEmpty || gruplar.last.$1 != grup) gruplar.add((grup, []));
      gruplar.last.$2.add((k, ad));
    }
    Widget grupBasligi(String g) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Text(g, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
        );
    Widget satir(String k, String ad, VoidCallback dokun, {required bool grupIci}) {
      final sec = k == secili;
      return InkWell(
        onTap: dokun,
        child: Container(
          height: tel ? 48 : 40,
          padding: EdgeInsets.only(left: grupIci ? 22 : 14, right: 14),
          color: sec ? Kabuk.sunken : null,
          child: Row(children: [
            Expanded(child: Text(ad, style: TextStyle(fontSize: tel ? 14.5 : 13.5, fontWeight: sec ? FontWeight.w700 : FontWeight.w500, color: Kabuk.ink))),
            if (sec) Icon(Icons.check_rounded, size: 18, color: Kabuk.brand),
          ]),
        ),
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Kabuk.surface,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
      builder: (c) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(baslik, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, padding: EdgeInsets.only(bottom: 12 + MediaQuery.paddingOf(c).bottom), children: [
              for (final (g, liste) in gruplar) ...[
                if (g != null) grupBasligi(g),
                for (final (k, ad) in liste) satir(k, ad, () => Navigator.pop(c, k), grupIci: g != null),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  /// YAZDIR: Özet'i (kutular + iki tablo + borca yazdıranlar) kasa
  /// yazıcısına sade fiş olarak gönderir — /api/v1/print/receipt, kasa
  /// ekranının fişleriyle aynı yol (sunucu ESC/POS'a çevirir, ajan basar).
  Future<void> _yazdir() async {
    final t = _ozetVerisi();
    if (t == null) {
      context.bildir2('Rapor henüz yüklenmedi', 'Rakamlar gelince tekrar deneyin.', hata: true);
      return;
    }
    setState(() => _basiliyor = true);
    try {
      final r = _harita(await _api.get('/api/v1/print/targets'));
      final yazicilar = _liste(r['printers']);
      final vars = _harita(r['defaults'])['cashier'];
      final id = vars != null ? tamSayi(vars) : (yazicilar.isNotEmpty ? tamSayi(yazicilar.first['id']) : null);
      if (id == null) {
        if (mounted) context.bildir2('Yazıcı yok', 'İşletme Yönetimi › Yazıcılar bölümünden bir kasa yazıcısı ekleyin.', hata: true);
        return;
      }
      final fis = {
        'title': 'RAPOR · ÖZET',
        'time': '${_kutuZamani(_bas)} → ${_kutuZamani(_bit)}',
        'lines': [
          for (final s in t.kategoriler.take(120)) {'name': '${s.ad} · ${_sayi(s.adet)} Adet · ${_oran(s.pay)}', 'amount': _tl(s.tutar)},
        ],
        'totals': [
          for (final (ad, deger) in t.kutular) {'label': ad, 'value': deger},
        ],
        'payments': [
          for (final s in t.odemeler) {'label': '${s.ad} · ${_sayi(s.adet)} Adet · ${_oran(s.pay)}', 'value': _tl(s.tutar)},
        ],
        'footer': [
          if (t.borclular.isNotEmpty) 'Borca yazdıranlar:',
          for (final b in t.borclular.take(8)) '${b.ad}: ${_sayi(b.adet)} adisyon ${_tl(b.tutar)}',
        ],
      };
      await _api.post('/api/v1/print/receipt', {'printer_id': id, 'title': 'Rapor özeti', 'receipt': fis});
      final ad = yazicilar.where((y) => tamSayi(y['id']) == id).map((y) => '${y['name']}').firstOrNull ?? 'Kasa yazıcısı';
      if (mounted) context.bildir2('Rapor yazıcıya gönderildi', ad);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Yazdırılamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _basiliyor = false);
    }
  }

  /* ───────────────────────── gövde (diğer raporlar) ───────────────────────── */

  Widget _govde(double g) {
    final icerik = switch (_aktif) {
      'satis-ciro' => _ciro(g),
      'satis-urun' => _urunler(g),
      'satis-kar' => _karlilik(g),
      'tahsilat' => _tahsilat(g),
      'mutabakat' => _mutabakat(g),
      'borclar' => _borclar(g),
      'indirim' => _indirim(g),
      'servis' => _servis(g),
      'personel' => _personel(g),
      _ => const <Widget>[],
    };
    return RefreshIndicator(
      onRefresh: () => _yukle(zorla: true),
      child: ListView(
        padding: EdgeInsets.only(bottom: g >= 1024 ? 14 : 12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: icerik,
      ),
    );
  }

  /// Web sekmesi `flex flex-col gap-3` + `grid xl:grid-cols-2`: tam genişlik
  /// kartlar alt alta; yarım kartlar ≥1280 px'te ikişer yan yana.
  List<Widget> _diz(List<_Bolum> bolumler, double g, {int ilkSira = 0}) {
    final cikti = <Widget>[];
    final ciftli = g >= 1280;
    Widget? bekleyen;
    var sira = ilkSira;
    void ekle(Widget w) => cikti.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: w));
    void bosalt() {
      if (bekleyen != null) ekle(bekleyen!);
      bekleyen = null;
    }

    for (final b in bolumler) {
      final w = _bolumCiz(b);
      if (w == null) continue;
      final kart = Belirme(key: ValueKey('${b.baslik}|$_aktif'), sira: sira++, child: w);
      if (b.genis || !ciftli) {
        bosalt();
        ekle(kart);
      } else if (bekleyen == null) {
        bekleyen = kart;
      } else {
        ekle(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: bekleyen!), const SizedBox(width: 12), Expanded(child: kart)]));
        bekleyen = null;
      }
    }
    bosalt();
    return cikti;
  }

  Widget? _bolumCiz(_Bolum b) {
    if (b.uclar.every((u) => _veri(u) != null)) return b.ciz();
    final hata = b.uclar.map(_hata).whereType<String>().firstOrNull;
    if (hata != null) {
      return _Kart(baslik: b.baslik, child: _BosKutu(Icons.error_outline_rounded, hata, eylem: () => _yukle(zorla: true)));
    }
    return _Kart(baslik: b.baslik, child: _Iskelet(b.iskelet));
  }

  /// StatTile ızgarası: web `grid grid-cols-2 gap-2.5 xl:grid-cols-N`.
  Widget _kpiler(List<_Kpi> ogeler, double g, {int dar = 2, int? sm, int? lg, required int xl}) {
    final sutun = g >= 1280 ? xl : (lg != null && g >= 1024 ? lg : (sm != null && g >= 640 ? sm : dar));
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: _Izgara(sutun: sutun, bosluk: 10, children: [for (final k in ogeler) _StatKutu(k)]));
  }

  Widget _bosDonem(String baslik, String metin) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _Kart(child: _BosKutu(Icons.insights_outlined, metin, baslik: baslik)),
      );

  /* ───────────────────────── ÖZET (referans düzeni) ───────────────────────── */

  /// Özet uçlarından ekrana ve fişe giden tek veri; uçlar gelmeden null.
  _OzetVeri? _ozetVerisi() {
    final f = _veri('finance-summary');
    final acik = _veri('sales-open-items');
    final kat = _veri('sales-categories');
    final tah = _veri('finance-collected');
    if (f == null || acik == null || kat == null || tah == null) return null;
    final borc = _veri(_borcListesi);
    int fi(String k) => tamSayi(f[k]);

    List<_Pay> paylar(List<(String, int, int)> s) {
      final toplam = s.fold<int>(0, (a, r) => a + r.$3);
      return [for (final r in s) _Pay(r.$1, r.$2, r.$3, toplam > 0 ? r.$3 / toplam : 0)]..sort((a, b) => b.tutar.compareTo(a.tutar));
    }

    final kategoriler = paylar([for (final r in _liste(kat['rows'])) ('${r['name']}', tamSayi(r['qty']), tamSayi(r['revenue_minor']))]);
    final odemeler = paylar([for (final r in _liste(tah['rows'])) ('${r['label']}', tamSayi(r['count']), tamSayi(r['amount_minor']))]);
    final borcAcik = borc?['enabled'] == true;
    final borclular = !borcAcik
        ? const <_Pay>[]
        : [for (final k in _liste(borc!['kisiler'])) _Pay('${k['name']}', tamSayi(k['count']), tamSayi(k['amount_minor']), 0)];

    return _OzetVeri(
      kutular: [
        ('Açık Masa Tutarı', _tl(tamSayi(acik['amount_minor']))),
        ('Toplam Ürün Adedi', '${_sayi(kategoriler.fold<int>(0, (a, r) => a + r.adet))} Adet'),
        ('Toplam Ürün Tutarı', _tl(fi('items_total_minor'))),
        ('İkram Tutarı', _tl(fi('comp_minor'))),
        ('İptal - İade Adedi', '${_sayi(fi('cancelled_orders') + fi('refund_payments_count'))} Adet'),
        ('İptal - İade Tutarı', _tl(fi('cancelled_minor') + fi('refund_payments_minor'))),
        ('İndirim Tutarı', _tl(fi('discount_total_minor'))),
        ('Ödeme Adedi', '${_sayi(fi('collected_count'))} Adet'),
        ('Ödeme Tutarı', _tl(fi('collected_minor'))),
        // BİZİM EKİMİZ: onuncu kutu (referansın boş yuvası).
        ('Borca Yazılan', '${_tl(borcAcik ? tamSayi(borc!['total_minor']) : 0)} · ${_sayi(borcAcik ? borc!['count'] ?? 0 : 0)} adisyon'),
      ],
      kategoriler: kategoriler,
      odemeler: odemeler,
      borclular: borclular,
    );
  }

  static const _kutuAdlari = [
    'Açık Masa Tutarı', 'Toplam Ürün Adedi', 'Toplam Ürün Tutarı', 'İkram Tutarı', 'İptal - İade Adedi',
    'İptal - İade Tutarı', 'İndirim Tutarı', 'Ödeme Adedi', 'Ödeme Tutarı', 'Borca Yazılan',
  ];

  Widget _ozet(double g) {
    final v = _ozetVerisi();
    final hata = _hata('finance-summary') ?? _hata('finance-collected') ?? _hata('sales-categories') ?? _hata('sales-open-items');
    final genis = g >= 700;

    final kutular = _Izgara(sutun: genis ? 5 : 2, bosluk: 10, children: [
      if (v != null)
        for (final (ad, deger) in v.kutular) _Kutucuk(ad: ad, deger: deger)
      else
        for (final ad in _kutuAdlari) _Kutucuk(ad: ad, deger: null),
    ]);

    List<List<String>> satirlar(List<_Pay> l) => [for (final s in l) [_oran(s.pay), s.ad, '${_sayi(s.adet)} Adet', _tl(s.tutar)]];
    final borcVar = v != null && v.borclular.isNotEmpty;
    final agirlik = genis ? null : const [5, 7, 5, 7];

    Widget kategori(bool kaydir) => _DuzTablo(
          basliklar: const ['Oran', 'Kategori', 'Adet', 'Fiyat'],
          satirlar: v == null ? null : satirlar(v.kategoriler),
          kaydir: kaydir,
          agirlik: agirlik,
        );
    Widget odeme(bool kaydir) => _DuzTablo(
          basliklar: const ['Oran', 'Ödeme Tipi', 'Adet', 'Fiyat'],
          satirlar: v == null ? null : satirlar(v.odemeler),
          kaydir: kaydir,
          agirlik: agirlik,
        );
    Widget borc(bool kaydir) => _DuzTablo(
          baslik: 'Borca Yazdıranlar',
          basliklar: const ['Kişi', 'Adisyon', 'Tutar'],
          satirlar: [for (final b in v!.borclular) [b.ad, '${_sayi(b.adet)} adisyon', _tl(b.tutar)]],
          kaydir: kaydir,
          agirlik: genis ? null : const [3, 2, 2],
        );
    final kutu = BoxDecoration(color: Kabuk.surface, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line));

    return LayoutBuilder(builder: (context, k) {
      final alt = genis ? 20.0 : 12.0;
      // Geniş ve yeterince uzun ekranda sayfa KAYMAZ (referans): tablolar
      // kalan yüksekliği eşit paylaşır, satırlar kendi içinde kayar.
      if (genis && k.maxHeight >= 460) {
        final borcBoy = borcVar ? math.min(k.maxHeight * .28, 44.0 + 41 + 45.0 * v.borclular.length) : 0.0;
        return Padding(
          padding: EdgeInsets.only(bottom: alt),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (hata != null) ...[_HataSeridi(hata, () => _yukle(zorla: true)), const SizedBox(height: 10)],
            kutular,
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: kutu,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: kategori(true)),
                  Container(width: 1, color: Kabuk.line),
                  Expanded(child: odeme(true)),
                ]),
              ),
            ),
            if (borcVar) ...[
              const SizedBox(height: 10),
              SizedBox(height: borcBoy, child: Container(clipBehavior: Clip.antiAlias, decoration: kutu, child: borc(true))),
            ],
          ]),
        );
      }
      // Telefon (ya da kısa ekran): sayfa kayar, tablolar alt alta.
      final tablolar = genis
          ? Container(
              clipBehavior: Clip.antiAlias,
              decoration: kutu,
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: kategori(false)),
                  Container(width: 1, color: Kabuk.line),
                  Expanded(child: odeme(false)),
                ]),
              ),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(clipBehavior: Clip.antiAlias, decoration: kutu, child: kategori(false)),
              const SizedBox(height: 10),
              Container(clipBehavior: Clip.antiAlias, decoration: kutu, child: odeme(false)),
            ]);
      return RefreshIndicator(
        onRefresh: () => _yukle(zorla: true),
        child: ListView(
          padding: EdgeInsets.only(bottom: alt),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (hata != null) ...[_HataSeridi(hata, () => _yukle(zorla: true)), const SizedBox(height: 10)],
            kutular,
            const SizedBox(height: 10),
            tablolar,
            if (borcVar) ...[const SizedBox(height: 10), Container(clipBehavior: Clip.antiAlias, decoration: kutu, child: borc(false))],
          ],
        ),
      );
    });
  }

  /* ───────────────────────── CİRO (web SatisTab) ───────────────────────── */

  List<Widget> _ciro(double g) {
    final s = _veri('sales-summary');
    final c = _harita(s?['current']), o = _harita(s?['previous']);
    final b = _veri('receivables-summary');
    double? fark(String k) {
      final a = tamSayi(c[k]), p = tamSayi(o[k]);
      return s == null || p == 0 ? null : ((a - p) / p * 1000).round() / 10;
    }

    final ciro = tamSayi(c['revenue_minor']);
    final yazilan = tamSayi(b?['yazilan_minor']);
    final acikBorc = tamSayi(b?['acik_borc_sonu_minor']);
    final kpi = <_Kpi>[
      _Kpi('Ciro — tahsil edilen', s == null || b == null ? null : _tl(ciro - yazilan), alt: 'kapanan adisyonların parası kasaya giren kısmı', ton: Kabuk.success),
      _Kpi('Borca yazılan', b == null ? null : _tl(yazilan), alt: '${_sayi(b?['yazilan_adet'] ?? 0)} adisyon · satıldı, parası ALINMADI', ton: Kabuk.warning),
      _Kpi('Ciro toplamı', s == null ? null : _tl(ciro), fark: fark('revenue_minor'), alt: 'tahsil edilen + borca yazılan'),
      _Kpi('Sipariş', s == null ? null : _sayi(c['orders']), fark: fark('orders')),
      _Kpi('Ortalama sepet', s == null ? null : _tl(tamSayi(c['avg_basket_minor'])), fark: fark('avg_basket_minor')),
      _Kpi('Kişi başı harcama', s == null ? null : (c['per_guest_minor'] == null ? '—' : _tl(tamSayi(c['per_guest_minor']))),
          alt: c['per_guest_minor'] == null ? 'misafir sayısı girilmemiş' : '${_sayi(c['guests'] ?? 0)} misafir girildi'),
    ];
    final ust = <Widget>[
      _kpiler(kpi, g, xl: 3),
      if (b?['available'] == true && (yazilan > 0 || acikBorc > 0))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _BilgiSeridi([
            if (yazilan > 0) ...[
              const TextSpan(text: 'Bu dönemde '),
              TextSpan(text: _tl(yazilan), style: TextStyle(fontWeight: FontWeight.w700, color: Kabuk.ink)),
              const TextSpan(text: ' borca yazıldı: ciro toplamına dahildir, kasaya girmemiştir. '),
            ],
            if (acikBorc > 0) ...[
              const TextSpan(text: 'Dönem sonunda '),
              TextSpan(text: _tl(acikBorc), style: TextStyle(fontWeight: FontWeight.w700, color: Kabuk.negative)),
              const TextSpan(text: ' açık borç hâlâ tahsil edilmemiş. '),
            ],
            TextSpan(text: 'Ayrıntı: Borçlar raporu.', style: TextStyle(color: _W.subtle)),
          ]),
        ),
    ];
    if (s != null && tamSayi(c['orders']) == 0) {
      return [...ust, _bosDonem('Bu dönemde satış yok', 'Seçilen dönemde kapanmış adisyon bulunmuyor. Dönemi genişletmeyi deneyin.')];
    }
    final saatler = _liste(_m('sales-hourly')['hours']);
    return [
      ...ust,
      ..._diz([
        _Bolum(_tekGun ? 'Saatlik ciro' : 'Günlük ciro', [_tekGun ? 'sales-hourly' : 'sales-daily'], () {
          final uc = _tekGun ? 'sales-hourly' : 'sales-daily';
          final noktalar = _tekGun
              ? [for (final h in _liste(_m(uc)['hours'])) (tamSayi(h['hour']).toString().padLeft(2, '0'), tamSayi(h['revenue_minor']))]
              : [for (final d in _liste(_m(uc)['days'])) (_kisaGun('${d['date']}'), tamSayi(d['revenue_minor']))];
          return _Kart(
            baslik: _tekGun ? 'Saatlik ciro' : 'Günlük ciro',
            child: noktalar.isEmpty
                ? const _BosKutu(Icons.bar_chart_rounded, 'Bu dönemde ciro hesaplanamadı.', baslik: 'Veri yok')
                : _KolonGrafik(noktalar: noktalar, para: true, etiketAdimi: _tekGun ? 2 : 0),
          );
        }, iskelet: 180),
        if (!_tekGun)
          _Bolum('Yoğun saatler', ['sales-hourly'], () {
            final yogun = (List.of(saatler)..sort((a, b) => tamSayi(b['orders']).compareTo(tamSayi(a['orders'])))).where((h) => tamSayi(h['orders']) > 0).take(3);
            return _Kart(
              baslik: 'Yoğun saatler',
              child: saatler.isEmpty
                  ? const _BosKutu(Icons.schedule_rounded, 'Bu dönemde saatlik dağılım yok.', baslik: 'Veri yok')
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _KolonGrafik(noktalar: [for (final h in saatler) (tamSayi(h['hour']).toString().padLeft(2, '0'), tamSayi(h['orders']))], etiketAdimi: 3),
                      if (yogun.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(height: 1, color: Kabuk.line),
                        const SizedBox(height: 12),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final h in yogun)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(6), border: Border.all(color: Kabuk.line)),
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: '${tamSayi(h['hour']).toString().padLeft(2, '0')}:00', style: TextStyle(fontWeight: FontWeight.w700, color: Kabuk.ink)),
                                TextSpan(text: ' · ${_sayi(h['orders'])} sipariş'),
                              ]), style: TextStyle(fontSize: 11, color: _W.muted)),
                            ),
                        ]),
                      ],
                    ]),
            );
          }, genis: false, iskelet: 180),
        _Bolum('Sipariş kanalı', ['sales-channels'], () {
          final satir = _liste(_m('sales-channels')['rows']);
          return _Kart(
            baslik: 'Sipariş kanalı',
            child: satir.isEmpty
                ? const _BosKutu(Icons.shopping_cart_outlined, 'Bu dönemde kanal verisi yok.', baslik: 'Veri yok')
                : _YiginCubuk(dilimler: [for (var i = 0; i < satir.length; i++) ('${satir[i]['label']}', tamSayi(satir[i]['revenue_minor']), i)]),
          );
        }, genis: _tekGun, iskelet: 90),
        _Bolum('Masa hizmeti', ['sales-service'], () {
          final v = _m('sales-service');
          final m = _harita(v['masa']), mz = _harita(v['masasiz']);
          if (tamSayi(m['servis']) + tamSayi(mz['servis']) == 0) return null;
          return _Kart(
            baslik: 'Masa hizmeti',
            ozet: '${_sayi(m['servis'] ?? 0)} masa grubu',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _DegerIzgara(sutun: g >= 640 ? 3 : 2, ogeler: [
                ('Hizmet verilen masa', _sayi(m['servis'] ?? 0), '${_sayi(v['masa_sayisi'] ?? 0)} aktif masa'),
                ('Farklı masa', _sayi(m['farkli_masa'] ?? 0), null),
                ('Ödenen', _sayi(m['odenen'] ?? 0), m['odeme_orani'] == null ? null : _yuzde(m['odeme_orani'])),
                ('Borca yazılan', _sayi(m['borca_yazilan'] ?? 0), null),
                ('Açık', _sayi(m['acik'] ?? 0), null),
                ('Masa cirosu', _tl(tamSayi(m['ciro_minor'])), null),
                ('Masa devri', v['devir'] == null ? '—' : '${_sayi(v['devir'])} kez', null),
                ('Masasız sipariş', _sayi(mz['servis'] ?? 0), '${_sayi(mz['odenen'] ?? 0)} ödendi'),
              ]),
              if (tamSayi(m['misafir']) > 0) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: Kabuk.line),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Misafir sayısı girilen adisyonlarda toplam '),
                    TextSpan(text: '${_sayi(m['misafir'])} kişi', style: TextStyle(fontWeight: FontWeight.w600, color: Kabuk.ink)),
                    const TextSpan(text: ' ağırlandı.'),
                  ]),
                  style: TextStyle(fontSize: 12, color: _W.muted),
                ),
              ],
            ]),
          );
        }, iskelet: 120),
      ], g),
    ];
  }

  /// Tablo kartı bölümü (web RaporKart flush + ReportTable).
  _Bolum _tabloBolumu(
    String baslik,
    String uc,
    List<_Sutun> sutunlar, {
    String anahtar = 'rows',
    String bos = 'Bu dönemde kayıt yok.',
    bool genis = true,
    bool toplam = false,
    String? Function(Map<String, dynamic>)? ozet,
    List<Map<String, dynamic>> Function(Map<String, dynamic>)? satirlar,
    Color? Function(_Sutun, Map<String, dynamic>)? vurgu,
    bool gizleBossa = false,
  }) {
    return _Bolum(baslik, [uc], () {
      final v = _m(uc);
      final s = satirlar != null ? satirlar(v) : _liste(v[anahtar]);
      if (gizleBossa && s.isEmpty) return null;
      return _TabloKart(baslik: baslik, ozet: ozet?.call(v), sutunlar: sutunlar, satirlar: s, bos: bos, toplam: toplam, vurgu: vurgu);
    }, genis: genis, iskelet: 180);
  }

  /* ───────────────────────── ÜRÜNLER (web UrunlerTab) ───────────────────────── */

  List<Widget> _urunler(double g) {
    const urun = [_Sutun('name', 'Ürün'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('orders', 'Sipariş', _Tur.sayi), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)];
    return _diz([
      _tabloBolumu('Şu an açık masalarda bekleyen ürünler', 'sales-open-items',
          const [_Sutun('name', 'Ürün'), _Sutun('kategori', 'Kategori'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('revenue_minor', 'Tutar', _Tur.para, true)],
          ozet: (v) => '${_sayi(v['qty'] ?? 0)} adet · ${_tl(tamSayi(v['amount_minor']))}', gizleBossa: true),
      _tabloBolumu('Kategori satışları', 'sales-category-products',
          const [_Sutun('kategori', 'Kategori'), _Sutun('name', 'Ürün'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)],
          bos: 'Bu dönemde ürün satışı yok.', genis: false),
      _tabloBolumu('En çok satan ürünler', 'sales-products', urun, anahtar: 'top_by_qty', bos: 'Bu dönemde ürün satışı yok.', genis: false),
      _tabloBolumu('En az satan ürünler', 'sales-products', urun, anahtar: 'least_by_qty', bos: 'Bu dönemde ürün satışı yok.'),
      _tabloBolumu('Varyant satışları', 'sales-variants',
          const [_Sutun('name', 'Ürün'), _Sutun('variant', 'Varyant'), _Sutun('qty', 'Adet', _Tur.sayi, true), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)],
          bos: 'Bu dönemde varyantlı satış yok.', ozet: (v) => '${_sayi(_liste(v['rows']).length)} satır'),
      _tabloBolumu('Masa satışları ve devir', 'sales-tables',
          const [_Sutun('name', 'Masa'), _Sutun('orders', 'Sipariş', _Tur.sayi, true), _Sutun('turns', 'Devir', _Tur.sayi), _Sutun('avg_minutes', 'Ort. süre', _Tur.dk), _Sutun('revenue_minor', 'Ciro', _Tur.para, true)],
          bos: 'Bu dönemde masa satışı yok.'),
    ], g);
  }

  /* ───────────────────────── KÂRLILIK (web ProfitTab) ───────────────────────── */

  List<Widget> _karlilik(double g) {
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
      _Kpi('Toplam brüt kâr (maliyeti bilinenler)', h(() => _tl(brut)), ton: Kabuk.success),
      _Kpi('Medyan marj', h(() => _yuzde(v!['median_margin'])), alt: '${_sayi(v?['missing_cost_count'] ?? 0)} ürünün maliyeti yok'),
      _Kpi('En kârlı ürün', h(() => enKarli == null ? '—' : '${enKarli['name']}'), alt: enKarli == null ? null : _tl(tamSayi(enKarli['profit_minor']))),
      _Kpi('En düşük marjlı', h(() => enDusuk == null ? '—' : '${enDusuk['name']}'), alt: enDusuk == null ? null : _yuzde(enDusuk['margin']), ton: enDusuk == null ? null : Kabuk.warning),
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
      _kpiler(kpi, g, xl: 4),
      ..._diz([
        _Bolum('İkram maliyeti', ['product-profitability'], () {
          if (tamSayi(ikram['qty']) == 0 && tamSayi(ikram['value_minor']) == 0) return null;
          return _Kart(
            baslik: 'İkram maliyeti',
            child: _Izgara(sutun: g >= 1280 ? 4 : 2, bosluk: 12, children: [
              _StatKutu(_Kpi('İkram adedi', _sayi(ikram['qty'] ?? 0))),
              _StatKutu(_Kpi('İkram tutarı (bedelsiz)', _tl(tamSayi(ikram['value_minor'])), ton: Kabuk.warning)),
              _StatKutu(_Kpi('İkram maliyeti (stok)', _tl(tamSayi(ikram['cost_minor'])))),
              _StatKutu(_Kpi('Net kâr (ikram sonrası)', _tl(brut - tamSayi(ikram['cost_minor'])), ton: Kabuk.success)),
            ]),
          );
        }),
        _tabloBolumu('Çok satan ama düşük kârlı', 'product-profitability', sut,
            satirlar: (v) => _liste(v['rows']).where((r) => r['high_volume_low_margin'] == true).toList(), gizleBossa: true),
        _tabloBolumu('Ürün kârlılığı', 'product-profitability', sut,
            vurgu: (s, r) => s.anahtar == 'profit_minor' && tamSayi(r['profit_minor']) < 0 ? Kabuk.negative : null),
      ], g),
    ];
  }

  /* ───────────────────────── TAHSİLAT (web TahsilatTab) ───────────────────────── */

  List<Widget> _tahsilat(double g) {
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
      _kpiler(kpi, g, xl: 4),
      ..._diz([
        _odemeKarti('Para neyle alındı', 'finance-collected', 'rows', 'Bu dönemde tahsilat yok', 'Kasadan ödeme alındığında yöntem kırılımı burada görünür.',
            alt: (v) => 'Bahşiş ${_tl(tamSayi(v['tips_minor']))} — tahsilat toplamına dahil değildir.', ozet: (v) => _tl(tamSayi(v['total_minor']))),
        _Bolum('Satıştan nete iniş ve KDV', ['finance-summary', 'finance-vat'], () {
          final s = _m('finance-summary');
          int gs(String k) => tamSayi(s[k]);
          final kopru = Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: _Satirlar([
              ('Ürün toplamı', _tl(gs('items_total_minor')), null),
              ('İndirim', '-${_tl(gs('discount_total_minor'))}', Kabuk.warning),
              ('İkram', '-${_tl(gs('comp_minor'))}', Kabuk.warning),
              if (gs('service_charge_minor') != 0) ('Servis ücreti', _tl(gs('service_charge_minor')), null),
              if (gs('rounding_minor') != 0) ('Yuvarlama', _tl(gs('rounding_minor')), null),
              ('Ciro (KDV dahil)', _tl(gs('gross_minor')), Kabuk.ink),
              ('KDV', '-${_tl(gs('vat_minor'))}', null),
              ('Net satış (KDV hariç)', _tl(gs('net_minor')), Kabuk.success),
            ]),
          );
          final kdv = _Tablo(
            sutunlar: const [_Sutun('rate', 'KDV oranı', _Tur.yuzde), _Sutun('gross_minor', 'Brüt', _Tur.para, true), _Sutun('vat_minor', 'KDV', _Tur.para, true), _Sutun('net_minor', 'Net', _Tur.para, true)],
            satirlar: _liste(_m('finance-vat')['rows']),
          );
          return _Kart(
            baslik: 'Satıştan nete iniş ve KDV',
            govdeBosluk: false,
            // Web: lg:grid-cols-2 lg:divide-x.
            child: g >= 1024
                ? IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: kopru),
                      Container(width: 1, color: Kabuk.line),
                      Expanded(child: kdv),
                    ]),
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [kopru, Container(height: 1, color: Kabuk.line), kdv]),
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
        ], bos: 'Bu dönemde kasa oturumu yok.', ozet: (v) => '${_sayi(_liste(v['rows']).length)} oturum',
            vurgu: (s, r) => s.anahtar == 'difference_minor' && tamSayi(r['difference_minor']) != 0 ? Kabuk.negative : null),
        _tabloBolumu('Bakiyesi kalan adisyonlar', 'finance-open-accounts', const [
          _Sutun('id', 'Adisyon'),
          _Sutun('table', 'Masa'),
          _Sutun('customer', 'Müşteri'),
          _Sutun('total_minor', 'Tutar', _Tur.para),
          _Sutun('paid_minor', 'Ödenen', _Tur.para),
          _Sutun('balance_minor', 'Bakiye', _Tur.para, true),
        ], anahtar: 'open_orders', bos: 'Bakiyesi kalan adisyon yok.', toplam: true, ozet: (v) => '${_sayi(_liste(v['open_orders']).length)} adisyon'),
      ], g),
    ];
  }

  /// Web "Para neyle alındı" / "Borç tahsilatı — ödeme yöntemi": yığın çubuk
  /// (ChartStackedBar) + lejant + ReportTable.
  _Bolum _odemeKarti(String baslik, String uc, String anahtar, String bosBaslik, String bos,
      {String Function(Map<String, dynamic>)? alt, String Function(Map<String, dynamic>)? ozet, bool genis = true}) {
    return _Bolum(baslik, [uc], () {
      final v = _m(uc);
      final satir = _liste(v[anahtar]).where((r) => tamSayi(r['amount_minor']) > 0).toList();
      final toplam = satir.fold<int>(0, (a, r) => a + tamSayi(r['amount_minor']));
      return _Kart(
        baslik: baslik,
        ozet: ozet?.call(v),
        alt: alt?.call(v),
        child: satir.isEmpty
            ? _BosKutu(Icons.account_balance_wallet_outlined, bos, baslik: bosBaslik)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _YiginCubuk(dilimler: [for (var i = 0; i < satir.length; i++) ('${satir[i]['label']}', tamSayi(satir[i]['amount_minor']), i)]),
                const SizedBox(height: 12),
                _Tablo(
                  sutunlar: const [_Sutun('label', 'Yöntem'), _Sutun('count', 'İşlem', _Tur.sayi), _Sutun('pay', 'Pay (%)', _Tur.sayi), _Sutun('amount_minor', 'Tutar', _Tur.para)],
                  satirlar: [
                    for (final r in satir) {...r, 'pay': r['share'] ?? (toplam > 0 ? (tamSayi(r['amount_minor']) * 1000 / toplam).round() / 10 : 0)},
                  ],
                ),
              ]),
      );
    }, genis: genis, iskelet: 200);
  }

  /* ───────────────────────── MUTABAKAT (web MutabakatTab) ───────────────────────── */

  List<Widget> _mutabakat(double g) {
    final d = _veri('finance-reconciliation');
    int gd(String k) => tamSayi(d?[k]);
    final kpi = <_Kpi>[
      _Kpi('Nakit (kasada olmalı)', d == null ? null : _tl(gd('cash_minor')), alt: '${_sayi(gd('cash_count'))} işlem'),
      _Kpi('POS / Kart', d == null ? null : _tl(gd('pos_minor')), alt: '${_sayi(gd('pos_count'))} işlem'),
      _Kpi('Diğer', d == null ? null : _tl(gd('other_minor')), alt: '${_sayi(gd('other_count'))} işlem · yemek kartı, havale, QR, online'),
    ];
    if (d != null && gd('payments_total_minor') == 0 && gd('orders_closed_count') == 0) {
      return [_kpiler(kpi, g, dar: 1, sm: 3, xl: 3), _bosDonem('Bu dönemde tahsilat yok', 'Mutabakat için kapanan adisyon ya da ödeme bulunmuyor.')];
    }
    final fark = gd('difference_minor'), kasaFark = gd('cash_sessions_difference_minor');
    return [
      _kpiler(kpi, g, dar: 1, sm: 3, xl: 3),
      ..._diz([
        _Bolum('Ödeme defteri ↔ sistemdeki adisyon toplamı', ['finance-reconciliation'], () => _Kart(
              baslik: 'Ödeme defteri ↔ sistemdeki adisyon toplamı',
              govdeBosluk: false,
              alt: 'Ödeme defteri ödeme ANINA, sistem toplamı adisyonun KAPANIŞ anına göre hesaplanır — dönem sınırındaki birkaç kuruşluk fark normaldir. '
                  'Sürekli/büyük fark gerçek tutarsızlıktır.',
              child: _UcluHucre(genis: g >= 640, ogeler: [
                ('Ödeme defteri', _tl(gd('payments_total_minor')), 'nakit + POS + diğer', null, null),
                ('Sistemdeki adisyonlar', _tl(gd('orders_paid_minor')), 'kapanan ${_sayi(gd('orders_closed_count'))} adisyon', null, null),
                (
                  'Fark',
                  _tl(fark.abs()),
                  null,
                  fark == 0 ? Kabuk.success : Kabuk.negative,
                  fark == 0 ? 'Tutuyor' : (fark > 0 ? 'Defter fazla' : 'Sistem fazla'),
                ),
              ]),
            )),
        _Bolum('Beklenen nakit ↔ sayılan nakit', ['finance-reconciliation'], () => _Kart(
              baslik: 'Beklenen nakit ↔ sayılan nakit',
              govdeBosluk: d?['has_cash_sessions'] != true,
              child: d?['has_cash_sessions'] != true
                  ? const _BosKutu(Icons.storefront_outlined, 'Bu dönemde Z alınmış kasa oturumu yok.')
                  : _UcluHucre(genis: g >= 640, ogeler: [
                      ('Beklenen nakit', _tl(gd('cash_sessions_expected_minor')), '${_sayi(gd('cash_sessions_closed_count'))} kapanan oturum', null, null),
                      ('Sayılan nakit', _tl(gd('cash_sessions_counted_minor')), null, null, null),
                      ('Kasa farkı', _tl(kasaFark.abs()), null, kasaFark == 0 ? Kabuk.success : Kabuk.negative, kasaFark == 0 ? 'Tutuyor' : (kasaFark > 0 ? 'Fazla' : 'Eksik')),
                    ]),
            )),
      ], g),
    ];
  }

  /* ───────────────────────── BORÇLAR (web BorclarTab) ───────────────────────── */

  List<Widget> _borclar(double g) {
    final o = _veri('receivables-summary');
    if (o != null && o['available'] != true) {
      return [_bosDonem('Borç (cari) kapalı', 'Bu işletmede borç hesabı (cari) kullanılmıyor.')];
    }
    int go(String k) => tamSayi(o?[k]);
    final net = go('net_degisim_minor');
    final kpi = <_Kpi>[
      _Kpi('Borca yazılan', o == null ? null : _tl(go('yazilan_minor')), alt: '${_sayi(go('yazilan_adet'))} adisyon · ${_sayi(go('yazilan_kisi'))} kişi', ton: Kabuk.warning),
      _Kpi('Borçtan tahsil edilen', o == null ? null : _tl(go('tahsil_minor')), alt: '${_sayi(go('tahsil_adet'))} tahsilat', ton: Kabuk.success),
      _Kpi('Borç iskontosu', o == null ? null : _tl(go('iskonto_minor')), alt: '${_sayi(go('iskonto_adet'))} kayıt'),
      _Kpi('Açık borç (dönem sonu)', o == null ? null : _tl(go('acik_borc_sonu_minor')),
          alt: net == 0 ? 'dönemde değişmedi' : (net > 0 ? '${_tl(net)} arttı' : '${_tl(-net)} azaldı'), ton: Kabuk.negative),
    ];
    return [
      _kpiler(kpi, g, lg: 4, xl: 4),
      ..._diz([
        _odemeKarti('Borç tahsilatı — ödeme yöntemi', 'receivables-summary', 'tahsil_yontemler', 'Bu dönemde borç tahsilatı yok',
            'Borçtan tahsilat alındığında yöntem kırılımı burada görünür.', ozet: (v) => _tl(tamSayi(v['tahsil_minor'])), genis: false),
        _tabloBolumu('Borç yaşlandırma', 'receivables-aging',
            const [_Sutun('label', 'Yaş'), _Sutun('count', 'Borç kaydı', _Tur.sayi, true), _Sutun('amount_minor', 'Tutar', _Tur.para, true)],
            toplam: true, bos: 'Açık borç yok.', genis: false),
        _tabloBolumu('Borç tahsilatları (döküm)', 'receivables-collections', const [
          _Sutun('at', 'Tarih', _Tur.saat),
          _Sutun('name', 'Şahıs'),
          _Sutun('method', 'Yöntem'),
          _Sutun('amount_minor', 'Tahsilat', _Tur.para, true),
          _Sutun('balance_after_minor', 'Kalan borç', _Tur.para),
          _Sutun('staff', 'Alan'),
        ], toplam: true, bos: 'Bu dönemde borç tahsilatı yok.'),
        _tabloBolumu('Açık borcu olan şahıslar', 'ops-open-receivables',
            const [_Sutun('name', 'Şahıs'), _Sutun('phone', 'Telefon'), _Sutun('balance_minor', 'Bakiye', _Tur.para, true)],
            toplam: true, bos: 'Açık borcu olan şahıs yok.', vurgu: (s, r) => s.anahtar == 'balance_minor' ? Kabuk.negative : null),
      ], g),
    ];
  }

  /* ───────────────────────── İNDİRİM · İPTAL (web IndirimIptalTab) ───────────────────────── */

  List<Widget> _indirim(double g) {
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
      _kpiler(kpi, g, xl: 4),
      ..._diz([
        _tabloBolumu('Nedenler', 'ops-cancellations', const [_Sutun('tur', 'Tür'), _Sutun('reason', 'Neden'), _Sutun('count', 'Adet', _Tur.sayi, true), _Sutun('value_minor', 'Değer', _Tur.para, true)],
            satirlar: (v) => [
                  for (final (a, t) in [('order_cancels', 'Adisyon iptali'), ('item_cancels', 'Ürün iptali'), ('comps', 'İkram')])
                    for (final r in _liste(v[a])) {...r, 'tur': t},
                ],
            bos: 'Bu dönemde iptal ya da ikram yok.'),
        _Bolum('İndirimi kim yaptı, hangi gerekçeyle', ['finance-discounts'], () {
          final v = _m('finance-discounts');
          final kim = _Tablo(
            sutunlar: const [_Sutun('staff', 'Personel'), _Sutun('count', 'Adet', _Tur.sayi), _Sutun('amount_minor', 'Tutar', _Tur.para), _Sutun('max_minor', 'En büyük', _Tur.para)],
            satirlar: _liste(v['by_staff']),
          );
          final neden = _Tablo(
            sutunlar: const [_Sutun('reason', 'Gerekçe'), _Sutun('count', 'Adet', _Tur.sayi), _Sutun('share', 'Pay', _Tur.yuzde), _Sutun('amount_minor', 'Tutar', _Tur.para)],
            satirlar: _liste(v['by_reason']),
          );
          final bos = _liste(v['by_staff']).isEmpty && _liste(v['by_reason']).isEmpty;
          return _Kart(
            baslik: 'İndirimi kim yaptı, hangi gerekçeyle',
            govdeBosluk: bos,
            child: bos
                ? const _BosKutu(Icons.sell_outlined, 'Bu dönemde indirim yok.')
                : g >= 1024
                    ? IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: kim), Container(width: 1, color: Kabuk.line), Expanded(child: neden)]),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [kim, Container(height: 1, color: Kabuk.line), neden]),
          );
        }, iskelet: 160),
        _tabloBolumu('İndirim dökümü', 'finance-discounts', const [
          _Sutun('order_id', 'Adisyon'),
          _Sutun('table', 'Masa'),
          _Sutun('items_total_minor', 'Ürünler', _Tur.para),
          _Sutun('discount_minor', 'İndirim', _Tur.para, true),
          _Sutun('iskonto_minor', 'İskonto', _Tur.para, true),
          _Sutun('total_minor', 'Ödenecek', _Tur.para),
          _Sutun('reason', 'Gerekçe'),
          _Sutun('discount_by', 'Yapan'),
        ], toplam: true, bos: 'Bu dönemde indirim yok.', ozet: (v) => '${_sayi(_liste(v['rows']).length)} satır'),
        _tabloBolumu('İptal edilen adisyonlar', 'ops-eod-details', const [
          _Sutun('id', 'Adisyon'),
          _Sutun('table', 'Masa'),
          _Sutun('cancelled_at', 'Saat', _Tur.saat),
          _Sutun('total_minor', 'Tutar', _Tur.para, true),
          _Sutun('reason', 'Neden'),
          _Sutun('cancelled_by', 'İptal eden'),
        ], anahtar: 'cancelled_orders', toplam: true, bos: 'İptal edilen adisyon yok.', ozet: (v) => '${_sayi(_liste(v['cancelled_orders']).length)} adisyon'),
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
      ], g),
    ];
  }

  /* ───────────────────────── SERVİS (web OpsTab) ───────────────────────── */

  List<Widget> _servis(double g) {
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
      _kpiler(kpi, g, xl: 4),
      ..._diz([
        _tabloBolumu('Şu an geciken siparişler', 'ops-delayed',
            const [_Sutun('id', 'Adisyon'), _Sutun('table', 'Masa'), _Sutun('status_label', 'Durum'), _Sutun('age_minutes', 'Yaş', _Tur.dk), _Sutun('total_minor', 'Tutar', _Tur.para)],
            bos: 'Geciken sipariş yok.'),
        _tabloBolumu('İstasyon hazırlama süreleri', 'ops-station-prep',
            const [_Sutun('station', 'İstasyon'), _Sutun('items', 'Kalem', _Tur.sayi), _Sutun('avg_minutes', 'Ortalama', _Tur.dk), _Sutun('max_minutes', 'En uzun', _Tur.dk)],
            bos: 'Bu dönemde hazırlık kaydı yok.', genis: false),
        _tabloBolumu('Servis talebine yanıt', 'ops-service-requests',
            const [_Sutun('label', 'Talep'), _Sutun('total', 'Toplam', _Tur.sayi, true), _Sutun('open', 'Açık', _Tur.sayi, true), _Sutun('avg_response_minutes', 'Ort. yanıt', _Tur.dk)],
            bos: 'Bu dönemde servis talebi yok.', genis: false),
        _tabloBolumu('Komi teslim SLA', 'ops-delivery-sla',
            const [_Sutun('name', 'Komi'), _Sutun('deliveries', 'Teslim', _Tur.sayi, true), _Sutun('breaches', 'İhlal', _Tur.sayi, true), _Sutun('breach_rate', 'Oran', _Tur.yuzde), _Sutun('avg_duration_minutes', 'Ort. süre', _Tur.dk)],
            anahtar: 'by_staff', bos: 'Bu dönemde komi teslimi yok.', ozet: (v) => '${_sayi(v['total'] ?? 0)} teslim'),
        _tabloBolumu('QR / Kiosk kullanımı', 'ops-channel-usage',
            const [_Sutun('label', 'Kanal'), _Sutun('orders', 'Sipariş', _Tur.sayi, true), _Sutun('share', 'Pay', _Tur.yuzde)],
            anahtar: 'channels', bos: 'Bu dönemde QR okutulmadı.', ozet: (v) => '${_sayi(v['orders_total'] ?? 0)} sipariş'),
      ], g),
    ];
  }

  /* ───────────────────────── PERSONEL (web StaffTab) ───────────────────────── */

  List<Widget> _personel(double g) => _diz([
        _tabloBolumu('Personel performansı', 'staff-performance', const [
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
        ], toplam: true, bos: 'Bu dönemde personel satışı yok.'),
      ], g);

  /* ───────────────────────── DÖKÜM (web AdisyonDokumu) ───────────────────────── */

  Widget _dokumListesi(double g) {
    final v = _veri(_dokum);
    final p = EdgeInsets.only(bottom: g >= 1024 ? 14 : 12);
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
      ], g, xl: 2),
      if (satirlar.isEmpty) _bosDonem('Adisyon yok', 'Seçilen dönemde adisyon bulunmuyor.'),
    ];
    return RefreshIndicator(
      onRefresh: () => _yukle(zorla: true),
      child: ListView.builder(
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
      ),
    );
  }
}

/* ───────────────────────── başlık satırı parçaları ───────────────────────── */

/// Web .rx-sec select: 32 px kutu (dokunmatikte 36–38), sağda aşağı ok.
class _SecimKutusu extends StatelessWidget {
  const _SecimKutusu({required this.metin, required this.yukseklik, required this.enAz, required this.onTap});
  final String metin;
  final double yukseklik;
  final double enAz;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Kabuk.surface,
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: onTap,
          child: Container(
            height: yukseklik,
            constraints: BoxConstraints(minWidth: enAz),
            padding: const EdgeInsets.only(left: 11, right: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(metin, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Kabuk.ink)),
              ),
              const SizedBox(width: 10),
              Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Kabuk.soft),
            ]),
          ),
        ),
      );
}

/// Tarih-saat kutusu: "27.10.2026 07:00" + takvim simgesi.
class _TarihKutusu extends StatelessWidget {
  const _TarihKutusu({required this.metin, required this.ipucu, required this.yukseklik, required this.onTap, this.ikon = Icons.calendar_today_outlined});
  final String metin;
  final String ipucu;
  final double yukseklik;
  final VoidCallback onTap;
  final IconData ikon;

  @override
  Widget build(BuildContext context) => Semantics(
        label: ipucu,
        button: true,
        child: Material(
          color: Kabuk.surface,
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
          child: InkWell(
            borderRadius: koseYuvarlak,
            onTap: onTap,
            child: Container(
              height: yukseklik,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(metin,
                      maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Kabuk.ink, fontFeatures: _tabular)),
                ),
                const SizedBox(width: 8),
                Icon(ikon, size: 15, color: Kabuk.ink),
              ]),
            ),
          ),
        ),
      );
}

/// Düğme: çerçeveli (Filtrele / Yazdır); [ana] marka dolgulu, [secili] gri
/// dolgulu (hazır dönem). [metin] null ise yalnız simge.
class _Dugme extends StatelessWidget {
  const _Dugme({required this.yukseklik, required this.onTap, this.metin, this.ikon, this.ipucu, this.ana = false, this.secili = false});
  final String? metin;
  final IconData? ikon;
  final String? ipucu;
  final double yukseklik;
  final VoidCallback? onTap;
  final bool ana;
  final bool secili;

  @override
  Widget build(BuildContext context) {
    final renk = ana ? Colors.white : Kabuk.ink;
    final w = Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: ana ? Kabuk.brand : (secili ? Kabuk.sunken : Kabuk.surface),
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: ana ? Kabuk.brand : (secili ? Kabuk.ink : Kabuk.line))),
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: onTap,
          child: Container(
            height: yukseklik,
            constraints: BoxConstraints(minWidth: yukseklik),
            padding: EdgeInsets.symmetric(horizontal: metin == null ? (yukseklik - 17) / 2 : 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (ikon != null) Icon(ikon, size: 17, color: renk),
              if (ikon != null && metin != null) const SizedBox(width: 6),
              if (metin != null) Text(metin!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: renk)),
            ]),
          ),
        ),
      ),
    );
    return ipucu == null || metin != null ? w : Tooltip(message: ipucu!, child: w);
  }
}

/* ───────────────────────── Özet parçaları (referans) ───────────────────────── */

class _Pay {
  const _Pay(this.ad, this.adet, this.tutar, this.pay);
  final String ad;
  final int adet;
  final int tutar;
  final double pay;
}

class _OzetVeri {
  const _OzetVeri({required this.kutular, required this.kategoriler, required this.odemeler, required this.borclular});
  final List<(String, String)> kutular;
  final List<_Pay> kategoriler;
  final List<_Pay> odemeler;
  final List<_Pay> borclular;
}

/// Oran: "%26,20".
String _oran(double p) => '%${(p * 100).toStringAsFixed(2).replaceAll('.', ',')}';

/// Eşit sütunlu ızgara (CSS grid repeat(n, 1fr)): satır içi kutular aynı boy.
class _Izgara extends StatelessWidget {
  const _Izgara({required this.sutun, required this.bosluk, required this.children});
  final int sutun;
  final double bosluk;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final n = math.max(1, sutun);
    final satir = (children.length / n).ceil();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var s = 0; s < satir; s++) ...[
        if (s > 0) SizedBox(height: bosluk),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var c = 0; c < n; c++) ...[
              if (c > 0) SizedBox(width: bosluk),
              Expanded(child: s * n + c < children.length ? children[s * n + c] : const SizedBox()),
            ],
          ]),
        ),
      ],
    ]);
  }
}

/// Referans kutusu: 1. satır kalın etiket, 2. satır gri değer. Renk/nokta yok.
class _Kutucuk extends StatelessWidget {
  const _Kutucuk({required this.ad, required this.deger});
  final String ad;

  /// null = yükleniyor.
  final String? deger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: Kabuk.surface, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: Kabuk.ink)),
          const SizedBox(height: 2),
          if (deger == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Container(width: 80, height: 13, decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak)),
            )
          else
            Text(deger!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.4, color: Kabuk.soft, fontFeatures: _tabular)),
        ]),
      );
}

/// Kırmızı kenarlı hata şeridi.
class _HataSeridi extends StatelessWidget {
  const _HataSeridi(this.metin, this.tekrar);
  final String metin;
  final VoidCallback tekrar;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Kabuk.surface, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 3, color: Kabuk.negative),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Text(metin, style: TextStyle(fontWeight: FontWeight.w700, color: Kabuk.negative)),
              ),
            ),
            TextButton(onPressed: tekrar, child: const Text('Tekrar dene')),
          ]),
        ),
      );
}

/// Referans tablosu: sade başlık satırı (kalın), ince satır ayraçları, eşit
/// sütunlar, sola yaslı. Çubuk/halka/"Diğer" yok. [kaydir]: satırlar
/// ListView.builder ile kutunun içinde kayar.
class _DuzTablo extends StatelessWidget {
  const _DuzTablo({required this.basliklar, required this.satirlar, this.baslik, this.kaydir = false, this.agirlik});
  final String? baslik;
  final List<String> basliklar;

  /// null = yükleniyor.
  final List<List<String>>? satirlar;
  final bool kaydir;

  /// Sütun ağırlıkları (null = eşit, referanstaki gibi). Telefonda ad
  /// sütunu genişler.
  final List<int>? agirlik;
  static const bos = 'Bu dönemde kayıt yok';

  static const _satirBoy = 45.0;

  @override
  Widget build(BuildContext context) {
    Widget satir(List<String> h, {bool ust = false}) => Container(
          height: ust ? 41 : _satirBoy,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
          child: Row(children: [
            for (var i = 0; i < h.length; i++)
              Expanded(
                flex: agirlik?[i] ?? 1,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(h[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: ust ? FontWeight.w600 : FontWeight.w400, color: Kabuk.ink, fontFeatures: _tabular)),
                ),
              ),
          ]),
        );
    final s = satirlar;
    final Widget govde;
    if (s == null) {
      govde = const Padding(padding: EdgeInsets.fromLTRB(14, 14, 14, 0), child: _Iskelet(110));
    } else if (s.isEmpty) {
      govde = Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
        child: Text(bos, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Kabuk.soft)),
      );
    } else if (kaydir) {
      govde = ListView.builder(padding: EdgeInsets.zero, itemExtent: _satirBoy, itemCount: s.length, itemBuilder: (_, i) => satir(s[i]));
    } else {
      govde = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final r in s) satir(r)]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: kaydir ? MainAxisSize.max : MainAxisSize.min, children: [
      if (baslik != null)
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
          child: Text(baslik!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
      satir(basliklar, ust: true),
      if (kaydir) Expanded(child: govde) else govde,
    ]);
  }
}

/* ───────────────────────── diğer raporlar (RaporKart / StatTile / ReportTable) ───────────────────────── */

/// Web RaporKart: simge 16 subtle · başlık 13,5/800 · açıklama 11,5 muted ·
/// sağda özet 14/800; gövde üst çizgili, 12 px dolgu (flush: dolgusuz);
/// alt not gri zeminde 11,5 muted.
class _Kart extends StatelessWidget {
  const _Kart({required this.child, this.baslik, this.ozet, this.alt, this.govdeBosluk = true});
  final Widget child;
  final String? baslik;
  final String? ozet;
  final String? alt;
  final bool govdeBosluk;

  @override
  Widget build(BuildContext context) {
    final bilgi = baslik == null ? null : _kartlar[baslik];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: _W.raised, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (baslik != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (bilgi != null) ...[
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(bilgi.$1, size: 16, color: _W.subtle)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(baslik!, style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w800, letterSpacing: -.135, color: Kabuk.ink)),
                  if (bilgi != null) ...[
                    const SizedBox(height: 2),
                    Text(bilgi.$2, style: TextStyle(fontSize: 11.5, height: 1.375, color: _W.muted)),
                  ],
                ]),
              ),
              if (ozet != null) ...[
                const SizedBox(width: 12),
                Text(ozet!, style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w800, color: Kabuk.ink, fontFeatures: _tabular)),
              ],
            ]),
          ),
        Container(
          decoration: baslik == null ? null : BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
          padding: govdeBosluk ? const EdgeInsets.all(12) : EdgeInsets.zero,
          child: child,
        ),
        if (alt != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Kabuk.sunken, border: Border(top: BorderSide(color: Kabuk.line))),
            child: Text(alt!, style: TextStyle(fontSize: 11.5, height: 1.625, color: _W.muted)),
          ),
      ]),
    );
  }
}

/// Web StatTile: px 12 · py 10, etiket 11,5/700 muted (sarar), rakam 19/800
/// tonlu, kıyas 11/600, ipucu 11 subtle.
class _StatKutu extends StatelessWidget {
  const _StatKutu(this.k);
  final _Kpi k;

  @override
  Widget build(BuildContext context) {
    final f = k.fark;
    final farkRenk = f == null || f == 0 ? _W.muted : (f > 0 ? Kabuk.success : Kabuk.negative);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _W.raised, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.ad, style: TextStyle(fontSize: 11.5, height: 1.25, fontWeight: FontWeight.w700, color: _W.muted)),
        const SizedBox(height: 2),
        if (k.deger == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(width: 96, height: 16, decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak)),
          )
        else
          Text(k.deger!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w800, letterSpacing: -.38, color: k.ton ?? Kabuk.ink, fontFeatures: _tabular)),
        if (f != null) ...[
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${f > 0 ? '+' : ''}${f.toStringAsFixed(1).replaceAll('.', ',')}% ', style: TextStyle(fontWeight: FontWeight.w600, color: farkRenk)),
              TextSpan(text: 'önceki döneme göre', style: TextStyle(color: _W.subtle)),
            ]),
            style: const TextStyle(fontSize: 11),
          ),
        ],
        if (k.alt != null) ...[
          const SizedBox(height: 2),
          Text(k.alt!, style: TextStyle(fontSize: 11, height: 1.375, color: _W.subtle)),
        ],
      ]),
    );
  }
}

/// Veri gelene kadar kartın yerini tutan durağan iskelet.
class _Iskelet extends StatelessWidget {
  const _Iskelet(this.yukseklik);
  final double yukseklik;

  @override
  Widget build(BuildContext context) {
    Widget cubuk(double oran, double h) => FractionallySizedBox(
          widthFactor: oran,
          alignment: Alignment.centerLeft,
          child: Container(height: h, decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak)),
        );
    final satir = math.max(1, ((yukseklik - 28) / 26).floor());
    return SizedBox(
      height: yukseklik,
      child: ClipRect(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cubuk(.42, 14),
          const SizedBox(height: 14),
          for (var i = 0; i < satir; i++) ...[cubuk(i.isEven ? .92 : .74, 12), const SizedBox(height: 14)],
        ]),
      ),
    );
  }
}

/// Web EmptyState: simge kutusu + başlık + açıklama.
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
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak),
            child: Icon(ikon, size: 20, color: Kabuk.soft),
          ),
          const SizedBox(height: 10),
          if (baslik != null) ...[Text(baslik!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), const SizedBox(height: 4)],
          Text(metin, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Kabuk.soft)),
          if (eylem != null) ...[const SizedBox(height: 8), TextButton(onPressed: eylem, child: const Text('Tekrar dene'))],
        ]),
      );
}

/// Web SatisTab borç notu: gri zeminli ince bilgi şeridi.
class _BilgiSeridi extends StatelessWidget {
  const _BilgiSeridi(this.metin);
  final List<InlineSpan> metin;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.info_outline_rounded, size: 13, color: _W.subtle)),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(children: metin), style: TextStyle(fontSize: 12, color: _W.muted))),
        ]),
      );
}

/// Web `<dl class="grid grid-cols-2 sm:grid-cols-3">`: büyük harf etiket +
/// 18 px rakam + not.
class _DegerIzgara extends StatelessWidget {
  const _DegerIzgara({required this.sutun, required this.ogeler});
  final int sutun;
  final List<(String, String, String?)> ogeler;

  @override
  Widget build(BuildContext context) => _Izgara(sutun: sutun, bosluk: 12, children: [
        for (final (ad, deger, not) in ogeler)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ad.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .3, color: _W.muted)),
            Text(deger, style: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w700, fontFeatures: _tabular)),
            if (not != null) Text(not, style: TextStyle(fontSize: 11, color: _W.subtle)),
          ]),
      ]);
}

/// Web Mutabakat: üç hücreli, çizgiyle bölünmüş özet (sm:grid-cols-3).
class _UcluHucre extends StatelessWidget {
  const _UcluHucre({required this.genis, required this.ogeler});
  final bool genis;

  /// (etiket, rakam, not, rakam rengi, rozet)
  final List<(String, String, String?, Color?, String?)> ogeler;

  @override
  Widget build(BuildContext context) {
    Widget hucre((String, String, String?, Color?, String?) o) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.$1.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .3, color: _W.muted)),
            const SizedBox(height: 4),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
              Text(o.$2, style: TextStyle(fontSize: 20, height: 1.4, fontWeight: FontWeight.w800, color: o.$4 ?? Kabuk.ink, fontFeatures: _tabular)),
              if (o.$5 != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: (o.$4 ?? Kabuk.soft).withOpacity(.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(o.$5!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: o.$4 ?? Kabuk.soft)),
                ),
            ]),
            if (o.$3 != null) Text(o.$3!, style: TextStyle(fontSize: 11, color: _W.subtle)),
          ]),
        );
    if (!genis) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < ogeler.length; i++) ...[if (i > 0) Container(height: 1, color: Kabuk.line), hucre(ogeler[i])],
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < ogeler.length; i++) ...[if (i > 0) Container(width: 1, color: Kabuk.line), Expanded(child: hucre(ogeler[i]))],
      ]),
    );
  }
}

/// Etiket — değer satırları (köprü listeleri).
class _Satirlar extends StatelessWidget {
  const _Satirlar(this.ogeler);
  final List<(String, String, Color?)> ogeler;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < ogeler.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: Kabuk.line))),
            child: Row(children: [
              Expanded(child: Text(ogeler[i].$1, style: TextStyle(fontSize: 12.5, color: _W.muted))),
              Text(ogeler[i].$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ogeler[i].$3 ?? Kabuk.ink, fontFeatures: _tabular)),
            ]),
          ),
      ]);
}

TextStyle _thStil() => TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Kabuk.ink);

/// RaporKart (flush) + ReportTable: ilk 12 satır kartta, kalanı "Tümünü
/// göster" ile alt pencerede (ListView.builder).
class _TabloKart extends StatelessWidget {
  const _TabloKart({required this.baslik, required this.sutunlar, required this.satirlar, this.ozet, this.bos = 'Bu dönemde kayıt yok.', this.toplam = false, this.vurgu});
  final String baslik;
  final String? ozet;
  final List<_Sutun> sutunlar;
  final List<Map<String, dynamic>> satirlar;
  final String bos;
  final bool toplam;
  final Color? Function(_Sutun, Map<String, dynamic>)? vurgu;

  static const _onizleme = 12;

  @override
  Widget build(BuildContext context) {
    final fazla = satirlar.length > _onizleme;
    return _Kart(
      baslik: baslik,
      ozet: ozet,
      govdeBosluk: false,
      child: satirlar.isEmpty
          ? _BosKutu(_kartlar[baslik]?.$1 ?? Icons.inbox_outlined, bos, baslik: 'Veri yok')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Tablo(sutunlar: sutunlar, satirlar: fazla ? satirlar.take(_onizleme).toList() : satirlar, toplamSatirlar: toplam ? satirlar : null, vurgu: vurgu),
              if (fazla)
                InkWell(
                  onTap: () => _tumu(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
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
      backgroundColor: _W.raised,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
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

/// Sade tablo (Özet'teki referans tablosuyla aynı dil): kalın başlık
/// satırı, 13 px satırlar, ince alt çizgi.
/// Sütunlar sığarsa ilk sütun genişler; sığmazsa yatay kayar.
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
      const ic = 14.0;
      var gerek = sutunlar.fold<double>(0, (a, s) => a + s.genislik) + ic * 2;
      if (gerek > k.maxWidth && sutunlar.first.tur == _Tur.metin) {
        gerek -= math.min(sutunlar.first.genislik - 90, gerek - k.maxWidth);
      }
      final sigar = gerek <= k.maxWidth + .5;
      final ekstra = sigar ? k.maxWidth - gerek : 0.0;
      final ilk = gerek - ic * 2 - sutunlar.skip(1).fold<double>(0, (a, s) => a + s.genislik);
      final genislikler = [for (var i = 0; i < sutunlar.length; i++) (i == 0 ? ilk : sutunlar[i].genislik) + (i == 0 ? ekstra : 0)];
      final toplamGen = sigar ? k.maxWidth : gerek;

      Widget satir(List<Widget> hucreler, {Color? zemin, bool cizgi = true}) => Container(
            width: toplamGen,
            padding: const EdgeInsets.symmetric(horizontal: ic, vertical: 12),
            decoration: BoxDecoration(color: zemin, border: cizgi ? Border(bottom: BorderSide(color: Kabuk.line)) : null),
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
            padding: EdgeInsets.only(right: !sutunlar[i].sayisal ? 8 : 0),
            child: Text(sutunlar[i].ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: _thStil()),
          ),
      ]);

      Widget veriSatiri(Map<String, dynamic> r, {bool son = false}) => satir([
            for (var i = 0; i < sutunlar.length; i++)
              Padding(
                padding: EdgeInsets.only(right: !sutunlar[i].sayisal ? 8 : 0),
                child: Text(
                  sutunlar[i].yaz(r[sutunlar[i].anahtar]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: vurgu?.call(sutunlar[i], r) ?? Kabuk.ink,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
          ], cizgi: !son);

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
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Kabuk.ink, fontFeatures: _tabular),
                ),
            ], zemin: Kabuk.sunken, cizgi: false);
      final ust = toplamSatiri == null ? null : Container(decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))), child: toplamSatiri);

      Widget govde;
      if (kaydir) {
        govde = SizedBox(
          width: toplamGen,
          child: Column(children: [
            baslik,
            Expanded(
              child: ListView.builder(
                itemCount: satirlar.length,
                itemExtent: 45,
                itemBuilder: (_, i) => veriSatiri(satirlar[i]),
              ),
            ),
            if (ust case final bbDeger?) bbDeger,
          ]),
        );
      } else {
        govde = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          baslik,
          for (var i = 0; i < satirlar.length; i++) veriSatiri(satirlar[i], son: i == satirlar.length - 1),
          if (ust case final bbDeger?) bbDeger,
        ]);
      }
      return sigar ? govde : SingleChildScrollView(scrollDirection: Axis.horizontal, child: govde);
    });
  }
}

/* ───────────────────────── grafikler (ChartColumn / ChartStackedBar) ───────────────────────── */

/// Web ChartColumn: 640×200 görünüm kutusu (genişliğe ölçeklenir), sol
/// eksende 0 · yarı · tavan (1/2/5×10ⁿ), kılcal ızgara, viz-1 mavi sütunlar
/// (üstte 4 px yuvarlak), yalnız zirvenin üstünde değer; dokununca diğerleri
/// soluklaşır ve baloncuk çıkar.
class _KolonGrafik extends StatefulWidget {
  const _KolonGrafik({required this.noktalar, this.para = false, this.etiketAdimi = 0});
  final List<(String, int)> noktalar;
  final bool para;
  final int etiketAdimi;

  @override
  State<_KolonGrafik> createState() => _KolonGrafikState();
}

class _KolonGrafikState extends State<_KolonGrafik> {
  int? _vurgu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, k) {
      final olcek = k.maxWidth / 640;
      final boy = (200 * olcek).clamp(130.0, 260.0);
      final n = widget.noktalar.length;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final sol = 44 * olcek, sag = 8 * olcek;
          final band = (k.maxWidth - sol - sag) / math.max(1, n);
          final i = ((d.localPosition.dx - sol) / band).floor();
          setState(() => _vurgu = (i < 0 || i >= n || _vurgu == i) ? null : i);
        },
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size(k.maxWidth, boy),
            painter: _KolonRessami(
              noktalar: widget.noktalar,
              para: widget.para,
              etiketAdimi: widget.etiketAdimi,
              olcek: olcek,
              vurgu: _vurgu,
              renk: _seri(0),
              izgara: _W.grid,
              eksen: _W.axis,
              soluk: _W.subtle,
              orta: _W.muted,
              ink: Kabuk.ink,
              zemin: _W.raised,
              cizgi: Kabuk.line,
            ),
          ),
        ),
      );
    });
  }
}

class _KolonRessami extends CustomPainter {
  _KolonRessami({
    required this.noktalar,
    required this.para,
    required this.etiketAdimi,
    required this.olcek,
    required this.vurgu,
    required this.renk,
    required this.izgara,
    required this.eksen,
    required this.soluk,
    required this.orta,
    required this.ink,
    required this.zemin,
    required this.cizgi,
  });
  final List<(String, int)> noktalar;
  final bool para;
  final int etiketAdimi;
  final double olcek;
  final int? vurgu;
  final Color renk, izgara, eksen, soluk, orta, ink, zemin, cizgi;

  String _kisa(num v) {
    final d = para ? v / 100 : v;
    if (d >= 1e6) return '${(d / 1e6).toStringAsFixed(d >= 1e7 ? 0 : 1).replaceAll('.', ',').replaceAll(',0', '')} Mn';
    if (d >= 1e3) return '${(d / 1e3).toStringAsFixed(d >= 1e4 ? 0 : 1).replaceAll('.', ',').replaceAll(',0', '')} B';
    return _sayi(d.round());
  }

  String _tam(int v) => para ? _tl(v) : _sayi(v);

  TextPainter _yazi(String s, double boy, Color r, {FontWeight w = FontWeight.w400}) =>
      TextPainter(text: TextSpan(text: s, style: TextStyle(fontFamily: yaziTipi, fontSize: boy, fontWeight: w, color: r)), textDirection: TextDirection.ltr)..layout();

  @override
  void paint(Canvas c, Size s) {
    final n = noktalar.length;
    if (n == 0) return;
    // Yazılar ekranda en az okunur boyda kalır (SVG ölçeklenince küçülüyordu).
    final double yb = math.max(10.0, 10 * math.min(olcek, 1.2));
    final double sol = math.max(40.0, 44 * olcek), sag = 8 * olcek, ust = 14.0 + yb * .4, alt = yb + 12;
    final plotW = s.width - sol - sag, plotH = s.height - ust - alt;
    final enCok = noktalar.fold<int>(0, (a, p) => math.max(a, p.$2));
    var tavan = 1.0;
    if (enCok > 0) {
      final us = math.pow(10, (math.log(enCok) / math.ln10).floor()).toDouble();
      tavan = [1, 2, 5, 10].map((m) => m * us).firstWhere((v) => v >= enCok, orElse: () => 10 * us);
    }
    for (final t in [0.0, tavan / 2, tavan]) {
      final y = ust + plotH - t / tavan * plotH;
      c.drawLine(Offset(sol, y), Offset(s.width - sag, y), Paint()
        ..color = t == 0 ? eksen : izgara
        ..strokeWidth = 1);
      final tp = _yazi(_kisa(t), yb, soluk);
      tp.paint(c, Offset(sol - 6 - tp.width, y - tp.height / 2));
    }
    final band = plotW / n;
    final double bw = math.min(24 * math.max(1.0, olcek * .8), math.max(3.0, band - 4));
    final adim = etiketAdimi > 0 ? etiketAdimi : math.max(1, (n / 8).ceil());
    var tepe = -1;
    for (var i = 0, en = 0; i < n; i++) {
      if (noktalar[i].$2 > en) {
        en = noktalar[i].$2;
        tepe = i;
      }
    }
    for (var i = 0; i < n; i++) {
      final v = noktalar[i].$2;
      final x = sol + i * band + (band - bw) / 2;
      final h = v / tavan * plotH;
      if (h > 0) {
        final double r = math.min(4.0, math.min(bw / 2, h));
        c.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, ust + plotH - h, bw, h), topLeft: Radius.circular(r), topRight: Radius.circular(r)),
          Paint()..color = renk.withOpacity(vurgu == null || vurgu == i ? 1 : .45),
        );
      }
      if (i % adim == 0) {
        final tp = _yazi(noktalar[i].$1, yb, soluk);
        tp.paint(c, Offset(x + bw / 2 - tp.width / 2, s.height - 6 - tp.height));
      }
    }
    if (tepe >= 0 && vurgu == null) {
      final tp = _yazi(_tam(noktalar[tepe].$2), yb, orta, w: FontWeight.w600);
      final x = sol + tepe * band + band / 2;
      final y = ust + plotH - noktalar[tepe].$2 / tavan * plotH - 5 - tp.height;
      tp.paint(c, Offset((x - tp.width / 2).clamp(0.0, s.width - tp.width), y));
    }
    final v = vurgu;
    if (v != null && v < n) {
      final ust1 = _yazi(_tam(noktalar[v].$2), 12, ink, w: FontWeight.w600);
      final alt1 = _yazi(noktalar[v].$1, 12, soluk);
      final double bw2 = math.max(ust1.width, alt1.width) + 20, bh = ust1.height + alt1.height + 12;
      final x = sol + v * band + band / 2;
      final double bx = (x - bw2 / 2).clamp(0.0, math.max(0.0, s.width - bw2));
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(bx, 0, bw2, bh), const Radius.circular(6));
      c.drawRRect(rr, Paint()..color = zemin);
      c.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..color = cizgi);
      ust1.paint(c, Offset(bx + 10, 6));
      alt1.paint(c, Offset(bx + 10, 6 + ust1.height));
    }
  }

  @override
  bool shouldRepaint(_KolonRessami o) => o.noktalar != noktalar || o.vurgu != vurgu || o.olcek != olcek || o.renk != renk || o.izgara != izgara;
}

/// Web ChartStackedBar: 28 px şerit (20 px çubuk, 3 px yuvarlak, 2 px
/// aralık) + lejant (renk kutusu · ad · tutar · (%pay)).
class _YiginCubuk extends StatefulWidget {
  const _YiginCubuk({required this.dilimler});

  /// (ad, değer, renk sırası)
  final List<(String, int, int)> dilimler;

  @override
  State<_YiginCubuk> createState() => _YiginCubukState();
}

class _YiginCubukState extends State<_YiginCubuk> {
  int? _vurgu;

  @override
  Widget build(BuildContext context) {
    final d = widget.dilimler;
    final toplam = d.fold<int>(0, (a, x) => a + x.$2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, k) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (t) {
            if (toplam <= 0) return;
            final w = k.maxWidth - 2.0 * (d.length - 1);
            var x = 0.0;
            for (var i = 0; i < d.length; i++) {
              final bw = d[i].$2 / toplam * w;
              if (t.localPosition.dx <= x + bw + 1) {
                setState(() => _vurgu = _vurgu == i ? null : i);
                return;
              }
              x += bw + 2;
            }
          },
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(k.maxWidth, 28),
              painter: _YiginRessami([for (final x in d) (x.$2, _seri(x.$3))], toplam, _vurgu),
            ),
          ),
        );
      }),
      if (_vurgu != null && _vurgu! < d.length)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: _tl(d[_vurgu!].$2), style: TextStyle(fontWeight: FontWeight.w600, color: Kabuk.ink)),
            TextSpan(text: '  ${d[_vurgu!].$1}', style: TextStyle(color: _W.subtle)),
          ]), style: const TextStyle(fontSize: 12)),
        ),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final (ad, deger, sira) in d)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _seri(sira), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text.rich(TextSpan(children: [
              TextSpan(text: '$ad ', style: TextStyle(color: _W.muted)),
              TextSpan(text: _tl(deger), style: TextStyle(fontWeight: FontWeight.w600, color: Kabuk.ink)),
              if (toplam > 0) TextSpan(text: ' (%${(deger * 100 / toplam).toStringAsFixed(1).replaceAll('.', ',')})', style: TextStyle(color: _W.subtle)),
            ]), style: const TextStyle(fontSize: 12)),
          ]),
      ]),
    ]);
  }
}

class _YiginRessami extends CustomPainter {
  _YiginRessami(this.dilimler, this.toplam, this.vurgu);
  final List<(int, Color)> dilimler;
  final int toplam;
  final int? vurgu;

  @override
  void paint(Canvas c, Size s) {
    if (toplam <= 0) return;
    final w = s.width - 2.0 * (dilimler.length - 1);
    var x = 0.0;
    for (var i = 0; i < dilimler.length; i++) {
      final bw = math.max(1.0, dilimler[i].$1 / toplam * w);
      c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, 4, bw, s.height - 8), const Radius.circular(3)),
        Paint()..color = dilimler[i].$2.withOpacity(vurgu == null || vurgu == i ? 1 : .45),
      );
      x += bw + 2;
    }
  }

  @override
  bool shouldRepaint(_YiginRessami o) => o.dilimler != dilimler || o.toplam != toplam || o.vurgu != vurgu;
}

/* ───────────────────────── döküm ───────────────────────── */

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
      color: _W.raised,
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
