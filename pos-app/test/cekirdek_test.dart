import 'package:bambumpos_pos/core/bicim.dart';
import 'package:bambumpos_pos/core/modeller.dart';
import 'package:bambumpos_pos/ekranlar/kabuk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('para biçimi', () {
    expect(para(0), '0,00 ₺');
    expect(para(5), '0,05 ₺');
    expect(para(123450), '1.234,50 ₺');
    expect(para(100000000), '1.000.000,00 ₺');
    expect(para(-2500), '-25,00 ₺');
  });

  test('süre metni', () {
    expect(sureMetni(5), '5 dk');
    expect(sureMetni(60), '1 sa');
    expect(sureMetni(135), '2 sa 15 dk');
    // Web ile aynı: gün yerine saat ("1269 sa 50 dk").
    expect(sureMetni(1440 * 3 + 10), '72 sa 10 dk');
  });

  test('Türkçe arama anahtarı', () {
    expect(aramaAnahtari('İSKENDER'), aramaAnahtari('iskender'));
    expect(aramaAnahtari('Çay'), 'cay');
    expect(aramaAnahtari('IĞDIR'), 'igdir');
  });

  test('katalog: alt kategori ürünleri üstte de listelenir, boş kategori gizlenir', () {
    final k = Katalog({
      'categories': [
        {'id': 1, 'parent_id': null, 'name': 'İçecek'},
        {'id': 2, 'parent_id': 1, 'name': 'Sıcak'},
        {'id': 3, 'parent_id': null, 'name': 'Boş'},
      ],
      'products': [
        {'id': 10, 'category_id': 2, 'name': 'Çay', 'price_minor': 2000, 'eklenme_adedi': 5, 'variants': [], 'option_groups': []},
        {'id': 11, 'category_id': 1, 'name': 'Ayran', 'price_minor': 3000, 'eklenme_adedi': 0, 'variants': [], 'option_groups': []},
      ],
    });
    expect(k.doluKategoriler.map((c) => c.id), [1]);
    expect(k.kategoriUrunleri(1).map((u) => u.id).toSet(), {10, 11});
    expect(k.sikKullanilan.map((u) => u.id), [10]);
  });

  test('varyantlı ürün varsayılan fiyatı ve seçim gereksinimi', () {
    final u = Urun({
      'id': 1,
      'name': 'Kahve',
      'price_minor': 5000,
      'variants': [
        {'id': 1, 'name': 'Küçük', 'price_minor': 5000, 'is_default': false},
        {'id': 2, 'name': 'Büyük', 'price_minor': 7000, 'is_default': true},
      ],
      'option_groups': [],
    });
    expect(u.gorunenFiyat, 7000);
    expect(u.secimGerekir, isTrue);
  });

  Oturum oturum(String istasyon, List<String> yetkiler, {bool para = true}) => Oturum({
        'cihaz': {'id': 1, 'ad': 'Tablet', 'istasyon': istasyon, 'para': para},
        'isletme': {'ad': 'Test'},
        'operator': {'id': 5, 'name': 'Ali'},
        'yetkiler': yetkiler,
        'eklentiler': {'shifts': false},
      });

  test('cihaz ana ekranı belirler, kişi ek ekranları açar (web izin/eklenti kuralları)', () {
    expect(ekranlariHesapla(oturum('order_entry', ['orders.view'])), [PosEkrani.siparis, PosEkrani.gecmis]);
    expect(ekranlariHesapla(oturum('kasa', ['orders.view', 'payments.take'])),
        [PosEkrani.kasa, PosEkrani.siparis, PosEkrani.gecmis]);
    // Mutfak cihazına müdür girerse sipariş ve servis de açılır; para görmeyen cihazda kasa yok.
    expect(ekranlariHesapla(oturum('kitchen', ['kds.view', 'orders.view', 'kds.deliver', 'payments.take'], para: false)),
        [PosEkrani.mutfak, PosEkrani.siparis, PosEkrani.gecmis, PosEkrani.barista, PosEkrani.nargile, PosEkrani.komi]);
    expect(ekranlariHesapla(oturum('komi', ['kds.deliver', 'payments.take'], para: false)), [PosEkrani.komi]);
  });

  test('kapalı eklentinin ekranı açılmaz', () {
    final o = Oturum({
      'cihaz': {'id': 1, 'istasyon': 'order_entry', 'para': true},
      'operator': {'id': 5, 'name': 'Ali'},
      'yetkiler': ['orders.view', 'receivables.view', 'delivery.view'],
      'eklentiler': {'receivables': false, 'delivery': true},
    });
    // Mesai / mola QR herkese açık (yetki aranmaz), yalnız vardiya eklentisine bağlı.
    expect(ekranlariHesapla(o), [PosEkrani.siparis, PosEkrani.gecmis, PosEkrani.teslimat, PosEkrani.mesaiQr]);
    expect(cekmeceEkranlari(o), contains(PosEkrani.mesaiQr));
  });

  test('pano: açık adisyonlar tekilleşir', () {
    final a = {'id': 7, 'is_open': true, 'remaining_minor': 1000};
    final p = Pano({
      'tables': [
        {'id': 1, 'name': 'M1', 'area_name': 'Bahçe', 'area_sort': 2, 'orders': [a]},
        {'id': 2, 'name': 'M2', 'area_name': 'Salon', 'area_sort': 1, 'orders': []},
      ],
      'channel_orders': [a],
    });
    expect(p.alanlar, ['Salon', 'Bahçe']);
    expect(p.acikAdisyonlar.length, 1);
  });
}
