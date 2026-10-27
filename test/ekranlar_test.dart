import 'package:bambumpos_patron/core/api.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:bambumpos_patron/core/durum.dart';
import 'package:bambumpos_patron/core/icgoru.dart';
import 'package:bambumpos_patron/ekranlar/acilis.dart';
import 'package:bambumpos_patron/ekranlar/eslesme.dart';
import 'package:bambumpos_patron/ekranlar/ozet.dart';
import 'package:bambumpos_patron/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_api.dart';

Future<void> _kur(HttpClientAdapter adapter) async {
  SharedPreferences.setMockInitialValues({});
  await Uyg.kur(p: await SharedPreferences.getInstance(), hazirApi: Api.bellekte(adapter));
}


Map<String, dynamic> ornekOzet() => {
      'data': {
        'range': {'from': '2026-10-27', 'to': '2026-10-27', 'branch_id': 1, 'timezone': 'Europe/Istanbul'},
        'sales': {
          'revenue_minor': 1845000,
          'orders': 64,
          'avg_basket_minor': 28828,
          'cancelled_orders': 2,
          'prev': {'revenue_minor': 1650000, 'orders': 60, 'avg_basket_minor': 27500},
          'delta_pct': {'revenue': 11.8, 'orders': 6.7, 'avg_basket': 4.8},
        },
        'by_day': [
          {'date': '2026-10-27', 'revenue_minor': 1845000, 'orders': 64},
        ],
        'by_hour': [for (var h = 0; h < 24; h++) {'hour': h, 'revenue_minor': h > 10 && h < 23 ? (h * 13000) : 0, 'orders': h > 10 && h < 23 ? h : 0}],
        'by_weekday': [for (var d = 0; d < 7; d++) {'weekday': d, 'revenue_minor': 0, 'orders': 0}],
        'payment_mix': {
          'total_minor': 1700000,
          'rows': [
            {'method': 'cash', 'label': 'Nakit', 'count': 20, 'amount_minor': 700000, 'share': 41.2},
            {'method': 'card', 'label': 'Kart', 'count': 40, 'amount_minor': 1000000, 'share': 58.8},
          ],
        },
        'service_types': {'total_minor': 1845000, 'rows': []},
        'channel_mix': {'total_minor': 0, 'rows': []},
        'top_products': [
          {'name': 'Çay', 'qty': 140, 'revenue_minor': 210000},
          {'name': 'Nargile', 'qty': 22, 'revenue_minor': 660000},
        ],
        'top_categories': [
          {'name': 'İçecek', 'qty': 200, 'revenue_minor': 500000, 'products': []},
        ],
        'top_tables': [],
        'discounts': {'discount_minor': 20000, 'comp_minor': 15000, 'discount_orders': 2, 'comp_orders': 3, 'iskonto_minor': 0, 'iskonto_orders': 0},
        'open': {'open_orders': 5, 'open_amount_minor': 230000, 'open_tables': 4, 'receivables': {'count': 3, 'total_minor': 540000, 'enabled': true}},
        'staff': {'rows': [], 'commission_total_minor': 0, 'sales_total_minor': 0},
        'on_shift': [
          {'name': 'Ayşe Yılmaz', 'position': 'Garson', 'since': '2026-10-27T09:00:00+03:00', 'worked_minutes': 320},
        ],
        'upcoming_today': [],
        'inventory': {'critical': 1, 'low': 0, 'rows': []},
        'delivery': null,
        'operations': {
          'covers': 120,
          'revenue_per_guest_minor': 15375,
          'avg_service_min': 48,
          'table_turnover': 2.4,
          'qr_share': 10.0,
          'qr_orders': 6,
          'cancellation_rate': 3.0,
          'cancelled_orders': 2,
          'peak_hour': {'hour': 21, 'orders': 12},
          'best_day': null,
        },
        'debts': {'enabled': true, 'total_minor': 145000, 'count': 2, 'kisi': 2},
        'gelir_gider': {'gelir': {'toplam_minor': 1700000}, 'gider_toplam_minor': 300000, 'gider_adet': 3, 'kalan_minor': 1400000},
        'tahsilat': {'total_minor': 1700000, 'count': 60, 'adisyon_minor': 1650000, 'borc_minor': 50000, 'borc_count': 1, 'nakit_minor': 700000, 'kart_minor': 1000000, 'eft_minor': 0, 'diger_minor': 0},
        'kasa': {'beklenen_minor': 900000, 'devir_minor': 200000, 'acik_oturum': 1, 'kalemler': [], 'saglama_tamam': true},
        'top_debtors': {'enabled': true, 'rows': [{'id': 1, 'name': 'Mehmet Bey', 'phone': null, 'balance_minor': 300000}], 'total_minor': 540000, 'count': 3},
        'is_gunu': {'baslangic_saati': 6, 'gece_minor': 0},
        'open_items': {'qty': 0, 'amount_minor': 0, 'rows': []},
      },
    };

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('açılış ekranı çizilir ve yanıt beklerken bekler', (t) async {
    await _kur(BekleyenSunucu());
    await t.pumpWidget(const PatronUygulamasi(ana: AcilisEkrani()));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(AcilisEkrani), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text('PATRON'), findsOneWidget);
    expect(find.text('Bağlanılıyor…'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('açılış: oturum yoksa eşleme ekranına geçer', (t) async {
    final s = SahteSunucu({
      '/api/v1/notifications': (401, {'message': 'Unauthenticated.'}),
      '/api/v1/patron-eslesme/baslat': (200, {'kod': 'K7M2Q9', 'gizli': 'g', 'bitis': DateTime.now().add(const Duration(minutes: 10)).toIso8601String()}),
      '/api/v1/patron-eslesme/durum': (200, {'durum': 'bekliyor'}),
    });
    await _kur(s);
    await t.pumpWidget(const PatronUygulamasi(ana: AcilisEkrani()));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(EslesmeEkrani), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('eşleme ekranı: kod, QR ve sahip notu', (t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = SahteSunucu({
      '/api/v1/patron-eslesme/baslat': (200, {'kod': 'K7M2Q9', 'gizli': 'g', 'bitis': DateTime.now().add(const Duration(minutes: 10)).toIso8601String()}),
      '/api/v1/patron-eslesme/durum': (200, {'durum': 'bekliyor'}),
    });
    await _kur(s);
    await t.pumpWidget(const PatronUygulamasi(ana: EslesmeEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    for (final h in 'K7M2Q9'.split('')) {
      expect(find.text(h), findsWidgets);
    }
    expect(find.textContaining('yalnız işletme sahibi eşler'), findsOneWidget);
    expect(find.textContaining('eşlemesi bekleniyor'), findsOneWidget);
    expect(EslesmeEkrani.qrAdresi('K7M2Q9'), 'https://bambumpos.com/musteri/isletme/cihazlar?patronkod=K7M2Q9#patron-esle');
    await t.pump(const Duration(seconds: 4));
    expect(s.istekler.where((e) => e.endsWith('/durum')).length, greaterThanOrEqualTo(2));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('eşleme ekranı: 429 gelince bekler, istek yağdırmaz', (t) async {
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = SahteSunucu({
      '/api/v1/patron-eslesme/baslat': (429, {'message': 'Çok fazla istek. 20 sn sonra tekrar deneyin.'}),
    });
    await _kur(s);
    await t.pumpWidget(const PatronUygulamasi(ana: EslesmeEkrani()));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('sn sonra otomatik'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    expect(s.istekler.where((e) => e.endsWith('/baslat')).length, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('özet ekranı veriyle çizilir (telefon genişliği, büyük yazı)', (t) async {
    final s = SahteSunucu({
      '/api/v1/boss/overview': (200, ornekOzet()),
      '/api/v1/tasks': (200, {'tasks': [], 'staff': []}),
      '/api/v1/reports/ops-delayed': (200, {'data': {'rows': [{'id': 9, 'table': 'M4', 'age_minutes': 52, 'total_minor': 40000}]}}),
    });
    await _kur(s);
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 800), textScaler: TextScaler.linear(1.3)),
      child: const PatronUygulamasi(ana: OzetEkrani()),
    ));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(find.text('Özet'), findsOneWidget);
    expect(find.textContaining('Ciro düne göre'), findsOneWidget);
    expect(find.textContaining('45 dk+'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Kasa ve tahsilat'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Kasa ve tahsilat'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('durum akışı cümleleri', () {
    final l = durumAkisi(ornekOzet()['data'] as Map, kiyas: 'düne göre', geciken: const [
      {'age_minutes': 50},
      {'age_minutes': 70},
      {'age_minutes': 10},
    ]);
    final m = l.map((e) => e.metin).toList();
    expect(m, contains('Ciro düne göre %11,8 fazla.'));
    expect(m.any((e) => e.startsWith('2 açık adisyon 45 dk+')), isTrue);
    expect(m.any((e) => e.contains('En yoğun saat 21:00')), isTrue);
    expect(m.any((e) => e.contains('stok kalemi kritik')), isTrue);
  });
}
