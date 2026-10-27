// Gün sonu ekranı (raporlar dili): başlık satırı, dönem bilgisi, rakam
// kutuları, tablolar ve düğmeler; telefon/tablet/masaüstünde taşmasız.
import 'dart:convert';
import 'dart:io';

import 'package:bambumpos_pos/app/tema.dart';
import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/durum.dart';
import 'package:bambumpos_pos/core/modeller.dart';
import 'package:bambumpos_pos/ekranlar/gun_sonu_ekrani.dart';
import 'package:bambumpos_pos/ekranlar/ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _ozet = {
  'orders': 42,
  'orders_opened': 45,
  'orders_closed': 40,
  'revenue_minor': 1250000,
  'debt_transferred_balance_minor': 50000,
  'debt_transferred_count': 2,
  'collected_minor': 1230000,
  'collected_count': 51,
  'collected_debt_minor': 30000,
  'collected_debt_count': 2,
  'collected_payments_minor': 1200000,
  'cash_drawer_minor': -12000,
  'cash_drawer_devir_minor': 10000,
  'cash_drawer_items': [
    {'label': 'Nakit satış', 'amount_minor': 400000},
  ],
  'avg_basket_minor': 29762,
  'guests': 60,
  'per_guest_minor': 20833,
  'open_table_minor': 8000,
  'open_table_orders': 1,
  'discount_total_minor': 4000,
  'comp_minor': 2500,
  'comp_count': 1,
  'comp_cost_minor': 900,
  'cancelled_orders': 0,
  'refunded_minor': 0,
  'refund_payments_count': 0,
  'open_receivables_available': true,
  'open_receivables_total_minor': 151000,
  'open_receivables_count': 4,
  'collection_methods': [
    {'label': 'Nakit', 'count': 20, 'amount_minor': 430000},
    {'label': 'Kredi kartı', 'count': 31, 'amount_minor': 800000},
  ],
  'collection_breakdown': {
    'rows': [
      {'label': 'Nakit', 'count': 20, 'amount_minor': 430000, 'share': 34.96},
      {'label': 'Kredi kartı', 'count': 31, 'amount_minor': 800000, 'share': 65.04},
    ],
    'total_minor': 1230000,
    'total_count': 51,
    'order_minor': 1200000,
    'order_count': 49,
    'debt_collected_minor': 30000,
    'debt_collected_count': 2,
    'debt_transferred_minor': 50000,
    'debt_transferred_count': 2,
    'lines': [
      {'kind': 'base', 'label': 'Ciro', 'amount_minor': 1250000, 'count': 42},
      {'kind': 'minus', 'label': 'Borca yazılan', 'amount_minor': -50000, 'count': 2},
      {'kind': 'equals', 'label': 'Adisyon tahsilatı olmalı', 'amount_minor': 1200000},
      {'kind': 'info', 'label': 'Eski borç tahsilatı', 'amount_minor': 30000, 'note': 'ciro dışı'},
      {'kind': 'ok', 'label': 'Fark', 'amount_minor': 0},
    ],
  },
};

class _Sunucu implements HttpClientAdapter {
  final istekler = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    final yol = o.uri.path;
    istekler.add('${o.method} $yol');
    final govde = switch (yol) {
      '/api/v1/print/targets' => jsonEncode({
          'printers': [
            {'id': 1, 'name': 'Kasa', 'station_label': 'Kasa'},
            {'id': 2, 'name': 'Bar', 'station_label': 'Bar'},
          ],
          'defaults': {'cashier': 1},
        }),
      '/api/v1/reports/eod/durum' => jsonEncode({
          'gun_baslangic_saati': 6,
          'aralik': {'etiket': '27.10 06:00 → şu an', 'baslangic_iso': '2026-10-27T06:00:00+03:00'},
          'acik_adisyon': 2,
          'acik_adisyon_kalan_minor': 8000,
          'acik_kasa_oturumu': 1,
          'kapanisa_hazir': false,
          'son_kapanis': {'kapanis': '27.10 02:10'},
          'gecmis': [
            {'id': 9, 'is_gunu': '2026-10-26', 'saat': '23:59', 'tur': 'gun', 'baslangic': '26.10 06:00', 'bitis': '26.10 23:59', 'baslangic_iso': '2026-10-26T06:00:00', 'bitis_iso': '2026-10-26T23:59:00', 'tahsilat_minor': 900000},
          ],
          'is_gunleri': [
            {'is_gunu': '2026-10-26', 'kapanis_sayisi': 1, 'tahsilat_minor': 900000, 'kapanis_idleri': [9], 'baslangic': '26.10 06:00', 'bitis': '26.10 23:59'},
          ],
        }),
      '/api/v1/reports/ops-eod' => jsonEncode({'data': _ozet}),
      '/api/v1/reports/sales-hourly' => jsonEncode({
          'data': {
            'hours': [
              {'hour': 2, 'orders': 1, 'revenue_minor': 20000},
              {'hour': 12, 'orders': 20, 'revenue_minor': 600000},
              {'hour': 19, 'orders': 21, 'revenue_minor': 630000},
            ],
          },
        }),
      '/api/v1/reports/receivables-collections' => jsonEncode({
          'data': {
            'rows': [
              {'at': '27.10 14:02', 'name': 'Ahmet Yılmaz', 'method': 'Nakit', 'amount_minor': 20000, 'balance_after_minor': 0, 'staff': 'Ayşe'},
              {'at': '27.10 18:40', 'name': 'Mehmet Kaya', 'method': 'Kart', 'amount_minor': 10000, 'balance_after_minor': 45000, 'staff': 'Ali'},
            ],
          },
        }),
      _ => '{}',
    };
    return ResponseBody.fromString(govde, 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<(UygulamaDurumu, _Sunucu)> _durum() async {
  SharedPreferences.setMockInitialValues({});
  final sunucu = _Sunucu();
  final d = UygulamaDurumu.test(Api.bellekte(sunucu), await SharedPreferences.getInstance(), Directory.systemTemp.createTempSync('bbpos').path);
  d.oturum = Oturum((jsonDecode(File('test/veri/oturum.json').readAsStringSync()) as Map).cast<String, dynamic>());
  return (d, sunucu);
}

Widget _uygulama(UygulamaDurumu d) => DurumKapsami(
      durum: d,
      child: MaterialApp(
        theme: temaKur(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: GunSonuEkrani()),
      ),
    );

Future<void> _bekle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Gerçek yazı tipi (Poppins): test yazı tipi Ahem her harfi kare çizip
  // sabit genişlikli pencerelerde sahte taşma üretir.
  setUpAll(() async {
    final poppins = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
    }
    await poppins.load();
  });

  for (final (ad, boyut, koyu) in [
    ('telefon', const Size(400, 2600), false),
    ('tablet', const Size(800, 2200), false),
    ('masaüstü koyu', const Size(1280, 1800), true),
  ]) {
    testWidgets('gün sonu $ad: bölümler, kutular, tablolar, düğmeler', (t) async {
      t.view.physicalSize = boyut;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      koyuTema.value = koyu;
      addTearDown(() => koyuTema.value = false);
      final (d, sunucu) = await _durum();
      await t.pumpWidget(_uygulama(d));
      await _bekle(t);

      // API çağrıları değişmedi.
      for (final u in ['/api/v1/print/targets', '/api/v1/reports/eod/durum', '/api/v1/reports/ops-eod', '/api/v1/reports/sales-hourly', '/api/v1/reports/receivables-collections']) {
        expect(sunucu.istekler, contains('GET $u'));
      }

      // 1. başlık satırı + düğmeler
      expect(find.text('Gün sonu'), findsOneWidget);
      for (final m in ['Gün sonu raporu al', 'Önceki kapanış', 'Fiş önizleme', 'Dışa aktar']) {
        expect(find.text(m), findsWidgets, reason: m);
      }
      expect(find.text('Kasa · Kasa'), findsOneWidget); // birden çok yazıcı → seçici

      // 2. dönem bilgisi
      expect(find.textContaining('Gün takvimle değil kasa kapanışıyla biter'), findsOneWidget);
      expect(find.textContaining('2 masa açık', findRichText: true), findsOneWidget);

      // 3. rakam kutuları (15'i de)
      for (final k in [
        'Ciro — tahsil edilen', 'Borca yazılan', 'Ciro toplamı', 'Kasaya giren toplam', 'Kasadaki nakit', 'Açılan adisyon', 'Kapanan adisyon',
        'Ortalama sepet', 'Kişi başı', 'Açık masa', 'İndirim', 'İkram', 'İptal', 'İade', 'Açık borç',
      ]) {
        expect(find.text(k), findsOneWidget, reason: k);
      }

      // 4–7. tablolar
      for (final b in ['Tahsilat — Ödeme Yöntemi', 'Ciro ↔ Tahsilat', 'Borçtan Tahsil Edilenler', 'Saat Bazlı Satış']) {
        expect(find.text(b), findsOneWidget, reason: b);
      }
      for (final b in ['Oran', 'Ödeme Tipi', 'Kalem', 'Şahıs', 'Kalan Borcu', 'TOPLAM TAHSİL EDİLEN', 'Adisyon tahsilatı', 'Tahsil edilen eski borç', 'TAMAM', '%34,96']) {
        expect(find.text(b), findsWidgets, reason: b);
      }
      expect(find.textContaining('BORCA YAZILAN', findRichText: true), findsOneWidget);
      expect(find.text('Ahmet Yılmaz'), findsOneWidget);
      expect(find.textContaining('En yoğun saat', findRichText: true), findsOneWidget);
      expect(t.takeException(), isNull);

      // Onay penceresi açılıyor (işleyiş aynı).
      await t.tap(find.text('Gün sonu raporu al').first);
      await _bekle(t);
      expect(find.text('Kasa kapandı mı?'), findsOneWidget);
      expect(find.text('Sadece ara rapor'), findsOneWidget);
      await t.tap(find.text('Vazgeç'));
      await _bekle(t);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
