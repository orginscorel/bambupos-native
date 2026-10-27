import 'package:flutter/material.dart';

/// Rapor kataloğu — sunucudaki ReportRegistry'nin (app/Modules/Reports/
/// Support/ReportRegistry.php) satır döndüren raporlarının istemci eşi.
/// Sunucu kataloğu JSON olarak vermediği için burada tutulur; yeni rapor
/// eklenince buraya da eklenmeli. `satirlar` = yanıtta `data.<anahtar>`.
enum RaporGrup { satis, urun, finans, personel, operasyon, borc, stok }

extension RaporGrupX on RaporGrup {
  String get ad => switch (this) {
        RaporGrup.satis => 'Satış',
        RaporGrup.urun => 'Ürün',
        RaporGrup.finans => 'Finans',
        RaporGrup.personel => 'Personel',
        RaporGrup.operasyon => 'Operasyon',
        RaporGrup.borc => 'Borç / cari',
        RaporGrup.stok => 'Stok',
      };

  IconData get ikon => switch (this) {
        RaporGrup.satis => Icons.trending_up_rounded,
        RaporGrup.urun => Icons.restaurant_menu_rounded,
        RaporGrup.finans => Icons.account_balance_wallet_rounded,
        RaporGrup.personel => Icons.badge_rounded,
        RaporGrup.operasyon => Icons.timer_rounded,
        RaporGrup.borc => Icons.receipt_long_rounded,
        RaporGrup.stok => Icons.inventory_2_rounded,
      };
}

enum GrafikTur { yok, cizgi, sutun, siraliSutun }

class RaporTanim {
  const RaporTanim(this.anahtar, this.baslik, this.grup, this.satirlar, this.sutunlar,
      {this.aciklama, this.grafik = GrafikTur.siraliSutun, this.grafikEtiket, this.grafikDeger, this.kaynak});

  final String anahtar;
  final String baslik;
  final RaporGrup grup;
  final String satirlar;
  final Map<String, String> sutunlar;
  final String? aciklama;
  final GrafikTur grafik;

  /// Grafikte eksen etiketi olacak sütun (yoksa ilk metin sütunu).
  final String? grafikEtiket;

  /// Grafikte değer olacak sütun (yoksa ilk tutar sütunu).
  final String? grafikDeger;

  /// Özel kaynak: null = /api/v1/reports/{anahtar}. 'ozet-stok' = patron özetinin stok bölümü.
  final String? kaynak;
}

const raporlar = <RaporTanim>[
  // ── Satış
  RaporTanim('sales-daily', 'Günlük satış', RaporGrup.satis, 'days',
      {'date': 'Tarih', 'orders': 'Sipariş', 'revenue_minor': 'Ciro', 'avg_basket_minor': 'Ortalama sepet'},
      aciklama: 'Gün gün ciro ve sipariş', grafik: GrafikTur.cizgi, grafikEtiket: 'date', grafikDeger: 'revenue_minor'),
  RaporTanim('sales-hourly', 'Saatlik satış', RaporGrup.satis, 'hours', {'hour': 'Saat', 'orders': 'Sipariş', 'revenue_minor': 'Ciro'},
      aciklama: 'Yoğun saatler', grafik: GrafikTur.sutun, grafikEtiket: 'hour', grafikDeger: 'revenue_minor'),
  RaporTanim('sales-categories', 'Kategori satışları', RaporGrup.satis, 'rows',
      {'name': 'Kategori', 'qty': 'Adet', 'orders': 'Sipariş', 'revenue_minor': 'Ciro'}),
  RaporTanim('sales-tables', 'Masa satışları', RaporGrup.satis, 'rows',
      {'name': 'Masa', 'orders': 'Sipariş', 'turns': 'Devir', 'avg_minutes': 'Ort. süre (dk)', 'revenue_minor': 'Ciro'}),
  RaporTanim('sales-channels', 'Kanal satışları', RaporGrup.satis, 'rows',
      {'label': 'Kanal', 'orders': 'Sipariş', 'share': 'Pay', 'revenue_minor': 'Ciro'}),
  RaporTanim('sales-cancellations', 'İptal edilen kalemler', RaporGrup.satis, 'rows', {
    'time': 'Saat', 'order_id': 'Adisyon', 'table': 'Masa', 'name': 'Ürün', 'qty': 'Adet', 'amount_minor': 'Tutar',
    'cancelled_by': 'İptal eden', 'reason': 'Sebep', 'after_served': 'Servis sonrası',
  }, aciklama: 'Kim, neyi, neden iptal etti', grafikEtiket: 'name', grafikDeger: 'amount_minor'),
  RaporTanim('sales-open-items', 'Açık masalarda bekleyenler', RaporGrup.satis, 'rows',
      {'kategori': 'Kategori', 'name': 'Ürün', 'qty': 'Adet', 'orders': 'Adisyon', 'revenue_minor': 'Tutar'},
      aciklama: 'Hesabı kapanmamış masalardaki ürünler', grafikEtiket: 'name'),

  // ── Ürün
  RaporTanim('sales-products', 'Ürün satışları', RaporGrup.urun, 'rows', {'name': 'Ürün', 'qty': 'Adet', 'orders': 'Sipariş', 'revenue_minor': 'Ciro'}),
  RaporTanim('sales-category-products', 'Kategori → ürün', RaporGrup.urun, 'rows',
      {'kategori': 'Kategori', 'name': 'Ürün', 'qty': 'Adet', 'orders': 'Sipariş', 'revenue_minor': 'Ciro'}, grafikEtiket: 'name'),
  RaporTanim('sales-variants', 'Varyant satışları', RaporGrup.urun, 'rows', {'name': 'Ürün', 'variant': 'Varyant', 'qty': 'Adet', 'revenue_minor': 'Ciro'}),
  RaporTanim('product-profitability', 'Ürün kârlılığı', RaporGrup.urun, 'rows', {
    'name': 'Ürün', 'qty': 'Adet', 'revenue_minor': 'Ciro', 'net_minor': 'Net', 'cost_minor': 'Maliyet', 'profit_minor': 'Brüt kâr', 'margin': 'Marj',
  }, aciklama: 'Reçete maliyetine göre brüt kâr', grafikDeger: 'profit_minor'),

  // ── Finans
  RaporTanim('finance-collected', 'Tahsil edilen', RaporGrup.finans, 'rows',
      {'label': 'Yöntem', 'count': 'İşlem', 'share': 'Pay', 'amount_minor': 'Tutar'}, aciklama: 'Adisyon + borç tahsilatı'),
  RaporTanim('finance-payment-methods', 'Ödeme yöntemleri', RaporGrup.finans, 'rows',
      {'label': 'Yöntem', 'count': 'İşlem', 'share': 'Pay', 'amount_minor': 'Tutar', 'tips_minor': 'Bahşiş'}),
  RaporTanim('finance-discounts', 'İndirim ve iskonto', RaporGrup.finans, 'rows', {
    'order_id': 'Adisyon', 'date': 'Tarih', 'table': 'Masa', 'items_total_minor': 'Adisyon tutarı', 'discount_minor': 'İndirim',
    'iskonto_minor': 'İskonto', 'total_minor': 'Ödenecek', 'reason': 'Gerekçe', 'discount_by': 'İndirimi yapan', 'approved_by': 'Onaylayan',
  }, grafik: GrafikTur.yok),
  RaporTanim('finance-cash-sessions', 'Kasa oturumları', RaporGrup.finans, 'rows', {
    'z_number': 'Z no', 'register': 'Kasa', 'opened_by': 'Açan', 'opened_at': 'Açılış', 'closed_at': 'Kapanış',
    'expected_minor': 'Beklenen', 'counted_minor': 'Sayılan', 'difference_minor': 'Fark',
  }, grafik: GrafikTur.yok),
  RaporTanim('finance-vat', 'KDV dağılımı', RaporGrup.finans, 'rows',
      {'rate': 'KDV oranı', 'gross_minor': 'Brüt', 'vat_minor': 'KDV', 'net_minor': 'Net'}, grafikEtiket: 'rate'),
  RaporTanim('finance-open-accounts', 'Açık hesaplar', RaporGrup.finans, 'open_orders', {
    'id': 'Adisyon', 'table': 'Masa', 'customer': 'Müşteri', 'created_at': 'Açılış', 'total_minor': 'Tutar', 'paid_minor': 'Ödenen', 'balance_minor': 'Bakiye',
  }, grafik: GrafikTur.yok),

  // ── Personel
  RaporTanim('staff-performance', 'Personel performansı', RaporGrup.personel, 'rows', {
    'name': 'Personel', 'orders': 'Sipariş', 'items': 'Kalem', 'sales_minor': 'Satış', 'avg_basket_minor': 'Ort. sepet',
    'avg_service_minutes': 'Ort. servis (dk)', 'discount_minor': 'İndirim', 'comp_count': 'İkram', 'comp_minor': 'İkram değeri',
    'cancelled': 'İptal', 'cancel_rate': 'İptal oranı', 'requests_handled': 'Karşılanan talep',
  }, grafikDeger: 'sales_minor'),
  RaporTanim('ops-delivery-sla', 'Komi teslim süresi', RaporGrup.personel, 'rows', {
    'staff': 'Komi', 'item': 'Ürün', 'table': 'Masa', 'picked_up_at': 'Teslim alındı', 'served_at': 'Masaya verildi',
    'duration_minutes': 'Süre (dk)', 'status': 'Durum', 'breached': 'Süre aşımı',
  }, grafik: GrafikTur.yok),

  // ── Operasyon
  RaporTanim('ops-delayed', 'Geciken siparişler', RaporGrup.operasyon, 'rows',
      {'id': 'Adisyon', 'table': 'Masa', 'status_label': 'Durum', 'age_minutes': 'Yaş (dk)', 'total_minor': 'Tutar'},
      grafikEtiket: 'table', grafikDeger: 'age_minutes'),
  RaporTanim('ops-cancellations', 'İptal / ikram nedenleri', RaporGrup.operasyon, 'order_cancels',
      {'reason': 'Neden', 'count': 'Adet', 'value_minor': 'Değer'}),
  RaporTanim('ops-station-prep', 'İstasyon hazırlama süreleri', RaporGrup.operasyon, 'rows',
      {'station': 'İstasyon', 'items': 'Kalem', 'avg_minutes': 'Ortalama (dk)', 'max_minutes': 'En uzun (dk)'}, grafikDeger: 'avg_minutes'),
  RaporTanim('ops-service-requests', 'Servis talepleri', RaporGrup.operasyon, 'rows',
      {'label': 'Talep', 'total': 'Toplam', 'open': 'Açık', 'avg_response_minutes': 'Ort. yanıt (dk)'}, grafikDeger: 'total'),
  RaporTanim('ops-channel-usage', 'QR / kiosk kullanımı', RaporGrup.operasyon, 'channels', {'label': 'Kanal', 'orders': 'Sipariş', 'share': 'Pay'},
      grafikDeger: 'orders'),

  // ── Borç
  RaporTanim('ops-open-receivables', 'Açık borç hesapları', RaporGrup.borc, 'rows',
      {'name': 'Şahıs', 'phone': 'Telefon', 'balance_minor': 'Bakiye'}, aciklama: 'Kimin ne kadar borcu var'),
  RaporTanim('receivables-collections', 'Borç tahsilatları', RaporGrup.borc, 'rows', {
    'at': 'Tarih', 'name': 'Şahıs', 'method': 'Yöntem', 'amount_minor': 'Tahsilat', 'balance_after_minor': 'Kalan borç', 'staff': 'Alan', 'note': 'Not',
  }, grafikEtiket: 'name', grafikDeger: 'amount_minor'),
  RaporTanim('receivables-aging', 'Borç yaşlandırma', RaporGrup.borc, 'rows', {'label': 'Yaş', 'count': 'Borç kaydı', 'amount_minor': 'Tutar'},
      grafik: GrafikTur.sutun),

  // ── Stok (sunucuda ayrı stok raporu yok: patron özetinin stok bölümü)
  RaporTanim('stok-uyari', 'Kritik ve düşük stok', RaporGrup.stok, 'rows',
      {'name': 'Kalem', 'severity': 'Seviye', 'on_hand': 'Eldeki', 'threshold': 'Eşik', 'unit': 'Birim'},
      aciklama: 'Eşiğin altına düşen kalemler (anlık)', grafik: GrafikTur.yok, kaynak: 'ozet-stok'),
];

/* ───────────────────────── Sütun türleri ───────────────────────── */

enum SutunTur { metin, para, sayi, ortalama, yuzde, tarih, evetHayir }

const _toplanan = {'qty', 'orders', 'count', 'items', 'comp_count', 'cancelled', 'total', 'open', 'turns', 'requests_handled'};
const _yuzde = {'share', 'margin', 'cancel_rate', 'rate'};
const _tarih = {'date', 'opened_at', 'closed_at', 'created_at', 'at', 'picked_up_at', 'served_at', 'time'};
const _evetHayir = {'after_served', 'breached'};

SutunTur sutunTuru(String k) {
  if (_evetHayir.contains(k)) return SutunTur.evetHayir;
  if (k.endsWith('_minor')) return k.startsWith('avg_') ? SutunTur.ortalama : SutunTur.para;
  if (_yuzde.contains(k)) return SutunTur.yuzde;
  if (_tarih.contains(k)) return SutunTur.tarih;
  if (_toplanan.contains(k)) return SutunTur.sayi;
  if (k.startsWith('avg_') || k.endsWith('_minutes') || k == 'age_minutes') return SutunTur.ortalama;
  return SutunTur.metin;
}

/// Toplamı anlamlı mı? (Ortalama, yüzde, bakiye-sonrası, Z no toplanmaz.)
bool toplanirMi(String k) {
  final t = sutunTuru(k);
  if (t == SutunTur.para) return k != 'balance_after_minor' && k != 'expected_minor' && k != 'counted_minor';
  return t == SutunTur.sayi;
}
