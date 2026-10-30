// Kasa: kısmi adet seçimiyle ödeme (items alanı), eski sunucuya geri
// düşüş ve indirim penceresinin manuel iskonto eklentisine göre açılışı.
import 'dart:convert';
import 'dart:io';

import 'package:bambumpos_pos/app/tema.dart';
import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/bicim.dart';
import 'package:bambumpos_pos/core/durum.dart';
import 'package:bambumpos_pos/core/modeller.dart';
import 'package:bambumpos_pos/ekranlar/adisyon_ekrani.dart';
import 'package:bambumpos_pos/ekranlar/kasa_ekrani.dart';
import 'package:bambumpos_pos/ekranlar/kasa_pencereleri.dart';
import 'package:bambumpos_pos/ekranlar/ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _veri(String ad) => File('test/veri/$ad.json').readAsStringSync();

class _Sunucu implements HttpClientAdapter {
  _Sunucu(this.yanitlar);

  /// 'GET /yol' ya da '/yol' → (durum, gövde).
  final Map<String, (int, String)> yanitlar;
  final istekler = <(String, String, Map<String, dynamic>?)>[];

  /// Ödeme ucu: her çağrıda sıradaki yanıt (boşsa başarılı).
  final odemeYanitlari = <(int, String)>[];

  /// 'POST /yol' → sıradaki yanıtlar (bitince [yanitlar]'a düşer).
  final sirali = <String, List<(int, String)>>{};

  /// Yol → ETag: istek aynı If-None-Match ile gelirse 304 döner.
  final etaglar = <String, String>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? govdeAkisi, Future<void>? _) async {
    final yol = o.uri.path;
    Map<String, dynamic>? govde;
    if (o.data is Map) govde = (o.data as Map).cast<String, dynamic>();
    if (o.data is String && (o.data as String).isNotEmpty) govde = (jsonDecode(o.data as String) as Map).cast<String, dynamic>();
    istekler.add((o.method, yol, govde));
    var y = yanitlar['${o.method} $yol'] ?? yanitlar[yol];
    if (o.method == 'POST' && yol.endsWith('/payments')) {
      y = odemeYanitlari.isNotEmpty
          ? odemeYanitlari.removeAt(0)
          : (201, jsonEncode({'payment': {'status': 'succeeded', 'amount_minor': govde?['amount_minor'], 'method_label': 'Nakit', 'change_minor': 0}}));
    }
    final sira = sirali['${o.method} $yol'];
    if (sira != null && sira.isNotEmpty) y = sira.removeAt(0);
    y ??= (200, '{}');
    final etag = etaglar[yol];
    if (o.method == 'GET' && etag != null) {
      if (o.headers['If-None-Match'] == etag) return ResponseBody.fromString('', 304, headers: {'etag': [etag]});
      return ResponseBody.fromString(y.$2, y.$1, headers: {
        Headers.contentTypeHeader: ['application/json'],
        'etag': [etag],
      });
    }
    return ResponseBody.fromString(y.$2, y.$1, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _adisyon(Map<String, (int, String)> y) => ((jsonDecode(y['/api/v1/orders/300']!.$2) as Map)['order'] as Map).cast<String, dynamic>();

Map<String, (int, String)> _kasaYanitlari() {
  final o = ((jsonDecode(_veri('adisyon')) as Map)['order'] as Map).cast<String, dynamic>();
  final ornek = (o['items'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).firstWhere((k) => k['id'] == 815);
  Map<String, dynamic> kalem(int id, String ad, int adet, int birim, {List<Map<String, dynamic>> dokum = const []}) => {
        ...ornek,
        'id': id,
        'name': ad,
        'qty': adet,
        'pending_qty': 0,
        'unit_price_minor': birim,
        'options_price_minor': 0,
        'line_total_minor': adet * birim,
        'is_settled': false,
        'options': const [],
        'dokum': dokum,
      };
  // Çay: sunucu dökümü (2 adet 19:40 Muhammet Ali Yeni, 2 adet 20:05 Ayşe
  // Yıldız). Tost: döküm yok — saat/kişi bilgisiz adetlere düşer.
  o['items'] = [
    kalem(901, 'Çay', 4, 2500, dokum: [
      {'saat': '2026-10-27T16:40:00+00:00', 'kisi': 'Muhammet Ali Yeni', 'adet': 2, 'devir': false},
      {'saat': '2026-10-27T17:05:00+00:00', 'kisi': 'Ayşe Yıldız', 'adet': 2, 'devir': false},
    ]),
    kalem(902, 'Kaşarlı Tost', 2, 9000),
  ];
  o
    ..['items_total_minor'] = 28000
    ..['total_minor'] = 28000
    ..['paid_minor'] = 0
    ..['remaining_minor'] = 28000;
  final ozet = Map<String, dynamic>.from(o)..remove('items')..remove('events');
  return {
    '/api/v1/payments/pending-orders': (200, jsonEncode({'orders': [ozet]})),
    '/api/v1/orders/300': (200, jsonEncode({'order': o})),
    'GET /api/v1/orders/300/payments': (200, jsonEncode({'order': ozet, 'payments': []})),
    '/api/v1/orders/catalog': (200, _veri('katalog')),
    '/api/v1/discount-presets': (200, jsonEncode({'presets': [{'id': 1, 'name': 'Öğrenci', 'value_label': '%10'}]})),
  };
}

Future<(UygulamaDurumu, _Sunucu)> _kur(WidgetTester t,
    {required bool manuel, Map<String, (int, String)> ek = const {}, Size boyut = const Size(1280, 800), Widget? ekran, List<String> ekYetki = const []}) async {
  // Test yazı tipi (Ahem) her harfi kare çizer; dar kartlardaki taşma
  // uyarıları gerçek cihazda yoktur — bu testin konusu değil.
  final onceki = FlutterError.onError;
  FlutterError.onError = (e) {
    if (e.exceptionAsString().contains('overflowed')) return;
    onceki?.call(e);
  };
  addTearDown(() => FlutterError.onError = onceki);
  t.view.physicalSize = boyut;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final ham = (jsonDecode(_veri('oturum')) as Map).cast<String, dynamic>();
  ham['yetkiler'] = [...(ham['yetkiler'] as List), 'payments.take', 'orders.discount', 'orders.view', 'orders.update', ...ekYetki];
  ham['eklentiler'] = {...(ham['eklentiler'] as Map), 'manuel_iskonto': manuel};
  final sunucu = _Sunucu({..._kasaYanitlari(), '/api/v1/uygulama/oturum': (200, jsonEncode(ham)), ...ek});
  final d = UygulamaDurumu.test(Api.bellekte(sunucu), await SharedPreferences.getInstance(), Directory.systemTemp.createTempSync('bbpos').path);
  await t.runAsync(d.oturumuYenile);
  await t.pumpWidget(DurumKapsami(
    durum: d,
    child: MaterialApp(
      theme: temaKur(),
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: ekran ?? const KasaEkrani()),
    ),
  ));
  await _bekle(t);
  if (ekran != null) return (d, sunucu);
  await t.tap(find.text('Bahçe 2').first);
  await _bekle(t);
  return (d, sunucu);
}

Future<void> _bekle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _bitir(WidgetTester t, UygulamaDurumu d) async {
  await t.pumpWidget(const SizedBox());
  d.ajan?.dispose();
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pump(const Duration(seconds: 30));
}

Future<void> _ikiCaySecVeOde(WidgetTester t) async {
  await t.tap(find.text('Çay'));
  await t.pump();
  // Her adet ayrı kart: saat · ürün · siparişi giren · birim fiyat.
  expect(find.text('Muhammet Ali Yeni'), findsNWidgets(2));
  expect(find.text('Ayşe Yıldız'), findsNWidgets(2));
  expect(find.text('Ödenecek adetleri seçin'), findsNothing);
  await t.tap(find.byKey(const ValueKey('kasa-birim-901-0')));
  await t.pump();
  await t.tap(find.byKey(const ValueKey('kasa-birim-901-2')));
  await t.pump();
  expect(find.text('2 / 4 adet seçili'), findsOneWidget);
  await _ode(t);
}

Future<void> _ode(WidgetTester t, {String yontem = 'Nakit', String dugme = 'ödemesini al'}) async {
  await t.ensureVisible(find.text(yontem).first);
  await t.pump();
  await t.tap(find.text(yontem).first);
  await t.pump();
  await t.ensureVisible(find.textContaining(dugme));
  await t.pump();
  await t.tap(find.textContaining(dugme));
  await _bekle(t);
}

Map<String, (int, String)> _posYaniti(Map<String, dynamic> g) => {'/api/v1/payments/terminal-status': (200, jsonEncode(g))};

/// Kalem notu: Çay 2 adet gönderilmedi (notlu), Tost 2'nin 1'i gönderildi,
/// Kahve tamamen gönderildi (notlu).
Map<String, (int, String)> _notYanitlari({String? cayNotu = 'az şekerli'}) {
  final y = _kasaYanitlari();
  final o = _adisyon(y);
  final ks = (o['items'] as List).cast<Map<String, dynamic>>();
  ks[0]
    ..['qty'] = 2
    ..['pending_qty'] = 2
    ..['status'] = 'placed'
    ..['note'] = cayNotu
    ..['dokum'] = const [];
  ks[1]
    ..['pending_qty'] = 1
    ..['status'] = 'placed'
    ..['note'] = null;
  ks.add({...ks[1], 'id': 903, 'name': 'Filtre Kahve', 'qty': 1, 'pending_qty': 0, 'status': 'sent_to_station', 'note': 'laktosuz süt'});
  o['is_open'] = true;
  o['version'] = 7;
  return {...y, '/api/v1/orders/300': (200, jsonEncode({'order': o}))};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    koyuTema.value = false;
    final gecici = Directory.systemTemp.createTempSync('bbpos-onbellek').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => gecici);
  });

  test('manuel iskonto eklentisi okunur (eklentiler / ozellikler / düz alan)', () {
    expect(Oturum({}).manuelIskonto, isFalse);
    expect(Oturum({'eklentiler': {'manuel_iskonto': true}}).manuelIskonto, isTrue);
    expect(Oturum({'eklentiler': {'manuel_iskonto': false}, 'ozellikler': ['manuel_iskonto']}).manuelIskonto, isFalse);
    expect(Oturum({'eklentiler': {'tips': true}, 'ozellikler': ['manuel_iskonto']}).manuelIskonto, isTrue);
    expect(Oturum({'ozellikler': {'manuel_iskonto': true}}).manuelIskonto, isTrue);
    expect(Oturum({'manuel_iskonto': true}).manuelIskonto, isTrue);
  });

  testWidgets('4 çaydan 2si seçilir; ödeme items {id, qty} ile gider', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    await _ikiCaySecVeOde(t);
    final odeme = s.istekler.where((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).toList();
    expect(odeme, hasLength(1));
    final g = odeme.single.$3!;
    expect(g['amount_minor'], 5000);
    expect(g['items'], [
      {'id': 901, 'qty': 2},
    ]);
    expect(g.containsKey('item_ids'), isFalse);
    // Başarıdan sonra adisyon yeniden yüklenir.
    final sonra = s.istekler.skipWhile((r) => !(r.$1 == 'POST' && r.$2.endsWith('/payments'))).skip(1);
    expect(sonra.any((r) => r.$1 == 'GET' && r.$2 == '/api/v1/orders/300'), isTrue);
    await _bitir(t, d);
  });

  testWidgets('eski sunucu items reddederse kısmi seçim item_ids ile GÖNDERİLMEZ', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    s.odemeYanitlari.add((422, jsonEncode({'message': 'The items field is prohibited.', 'errors': {'items': ['x']}})));
    await _ikiCaySecVeOde(t);
    final odeme = s.istekler.where((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).toList();
    expect(odeme, hasLength(1));
    expect(find.textContaining('kısmi ödemeyi henüz desteklemiyor'), findsOneWidget);
    await _bitir(t, d);
  });

  testWidgets('eski sunucu: satırın tamamı seçiliyse item_ids ile yeniden denenir', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    s.odemeYanitlari.add((422, jsonEncode({'message': 'Geçersiz', 'errors': {'items.0.qty': ['x']}})));
    await t.tap(find.byKey(const ValueKey('kasa-kutu-901')));
    await t.pump();
    await _ode(t);
    final odeme = s.istekler.where((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).toList();
    expect(odeme, hasLength(2));
    expect(odeme.last.$3!['item_ids'], [901]);
    expect(odeme.last.$3!.containsKey('items'), isFalse);
    expect(odeme.last.$3!['amount_minor'], 10000);
    await _bitir(t, d);
  });

  testWidgets('409: başka cihaz ödedi — açık mesaj ve yenileme', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    s.odemeYanitlari.add((409, jsonEncode({'message': 'Adisyon başka bir işlemle değişti.'})));
    await _ikiCaySecVeOde(t);
    expect(find.text('Adisyon değişti'), findsOneWidget);
    expect(find.text('2 / 4 adet seçili'), findsNothing); // seçim temizlendi
    await _bitir(t, d);
  });

  for (final manuel in [false, true]) {
    testWidgets('indirim penceresi hazır sekmeyle açılır (manuel=$manuel)', (t) async {
      final (d, _) = await _kur(t, manuel: manuel);
      await t.tap(find.byKey(const ValueKey('kasa-iskonto')));
      await _bekle(t);
      expect(find.text('Öğrenci'), findsOneWidget);
      expect(find.byKey(const ValueKey('indirim-sekme-1')), manuel ? findsOneWidget : findsNothing);
      expect(find.text('Hesabı şu tutara indir'), findsNothing);
      if (manuel) {
        await t.tap(find.byKey(const ValueKey('indirim-sekme-1')));
        await t.pump();
        expect(find.text('Hesabı şu tutara indir'), findsOneWidget);
        expect(find.text('Tutar yaz'), findsOneWidget);
      }
      await _bitir(t, d);
    });
  }

  testWidgets('araç çubuğu: Hesap · İndirim · Ürün ekle yan yana; ayrı indirim şeridi yok', (t) async {
    final (d, _) = await _kur(t, manuel: false);
    // Aynı araç satırında sırayla: Düzelt, Hesap, İndirim, Ürün ekle.
    final hesap = t.getCenter(find.byKey(const ValueKey('kasa-hesap')));
    final indirim = t.getCenter(find.byKey(const ValueKey('kasa-iskonto')));
    final urun = t.getCenter(find.byKey(const ValueKey('kasa-urun-ekle')));
    expect(indirim.dy, hesap.dy);
    expect(urun.dy, hesap.dy);
    expect(indirim.dx, greaterThan(hesap.dx));
    expect(urun.dx, greaterThan(indirim.dx));
    expect(find.text('İndirim'), findsOneWidget);
    expect(find.text('Ürün ekle'), findsOneWidget);
    expect(find.text('İndirim / İskonto'), findsNothing);
    expect(find.text('Adisyona ürün ekle'), findsNothing); // eski liste düğmesi kalktı
    await _bitir(t, d);
  });

  testWidgets('telefonda araç çubuğu tek satırda kalır', (t) async {
    final (d, _) = await _kur(t, manuel: false, boyut: const Size(360, 800));
    expect(find.text('İndirim'), findsOneWidget);
    expect(find.text('Ürün ekle'), findsOneWidget);
    // Tek satır: bütün araçlar aynı yükseklikte.
    final y = t.getCenter(find.byKey(const ValueKey('kasa-hesap'))).dy;
    expect(t.getCenter(find.byKey(const ValueKey('kasa-urun-ekle'))).dy, y);
    await _bitir(t, d);
  });

  testWidgets('uygulanmış indirim düğmede ve kaldırılabilir satırda görünür', (t) async {
    final y = _kasaYanitlari();
    final o = _adisyon(y)
      ..['discount_minor'] = 2800
      ..['discount_reason'] = 'Öğrenci'
      ..['discount_percent'] = 10;
    final (d, s) = await _kur(t, manuel: false, ek: {'/api/v1/orders/300': (200, jsonEncode({'order': o}))});
    expect(find.byTooltip('Uygulanan: −28,00 ₺'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kasa-indirim-satiri')), matching: find.text('−28,00 ₺')), findsOneWidget);
    expect(find.byKey(const ValueKey('kasa-indirim-satiri')), findsOneWidget);
    await t.tap(find.descendant(of: find.byKey(const ValueKey('kasa-indirim-satiri')), matching: find.byIcon(Icons.close_rounded)));
    await _bekle(t);
    expect(s.istekler.any((r) => r.$1 == 'DELETE' && r.$2 == '/api/v1/orders/300/discount'), isTrue);
    await _bitir(t, d);
  });

  testWidgets('Ürün ekle penceresi: görselli liste, kategori sekmeleri, arama', (t) async {
    final (d, _) = await _kur(t, manuel: false);
    await t.tap(find.byKey(const ValueKey('kasa-urun-ekle')));
    // Katalog ilk açılışta diskten/sunucudan gelir (sonra bellekte kalır).
    for (var i = 0; i < 20 && find.text('Adisyona ürün ekle').evaluate().isEmpty; i++) {
      await _bekle(t);
    }
    expect(find.text('Adisyona ürün ekle'), findsOneWidget);
    expect(find.text('Tümü'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
    await t.tap(find.text('Tümü'));
    await t.pump();
    expect(find.text('Cheesecake'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('urun-ara')), 'köfte');
    await t.pump(const Duration(milliseconds: 250));
    expect(find.text('Izgara Köfte'), findsOneWidget);
    expect(find.text('Cheesecake'), findsNothing);
    await t.tap(find.byTooltip('Kapat'));
    await _bekle(t);
    await _bitir(t, d);
  });

  testWidgets('kart POS: manuel_cihazlar yoksa eski simülasyon metni, pos_cihaz_id gitmez', (t) async {
    final (d, s) = await _kur(t, manuel: false, ek: _posYaniti({'simulated': true, 'online': false, 'provider_label': 'Simülasyon'}));
    await t.ensureVisible(find.text('Kredi kartı').first);
    await t.tap(find.text('Kredi kartı').first);
    await t.pump();
    expect(find.textContaining('test/simülasyon amaçlıdır'), findsOneWidget);
    await _ode(t, yontem: 'Kredi kartı', dugme: 'Manuel onayla (POS bağlı değil)');
    final g = s.istekler.lastWhere((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).$3!;
    expect(g.containsKey('pos_cihaz_id'), isFalse);
    await _bitir(t, d);
  });

  testWidgets('kart POS: konsoldaki manuel cihazlar — bilgi kutusu, seçici, pos_cihaz_id', (t) async {
    final (d, s) = await _kur(t, manuel: false, ek: _posYaniti({
      'simulated': true,
      'online': false,
      'provider_label': 'Simülasyon',
      'manuel_cihazlar': [
        {'id': 7, 'ad': 'Garanti POS', 'banka': 'Garanti BBVA', 'terminal_no': '10293'},
        {'id': 9, 'ad': 'Ziraat POS', 'banka': 'Ziraat', 'terminal_no': '55'},
      ],
    }));
    await t.ensureVisible(find.text('Kredi kartı').first);
    await t.tap(find.text('Kredi kartı').first);
    await t.pump();
    expect(find.textContaining('test/simülasyon'), findsNothing);
    expect(find.textContaining('cihazında okutun', findRichText: true), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('kasa-pos-cihaz-9')));
    await t.tap(find.byKey(const ValueKey('kasa-pos-cihaz-9')));
    await t.pump();
    await _ode(t, yontem: 'Kredi kartı', dugme: 'Kartla ödendi — onayla');
    final g = s.istekler.lastWhere((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).$3!;
    expect(g['pos_cihaz_id'], 9);
    expect(g['method'], 'credit_card');
    await _bitir(t, d);
  });

  testWidgets('canlı: başka cihazda eklenen kalem görünür; seçim ödenmemiş adede kırpılır', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    s.etaglar['/api/v1/orders/300'] = '"v1"';
    // 4 çaydan 3'ü seçilir.
    await t.tap(find.text('Çay'));
    await t.pump();
    for (final i in [0, 1, 2]) {
      await t.tap(find.byKey(ValueKey('kasa-birim-901-$i')));
      await t.pump();
    }
    expect(find.text('3 / 4 adet seçili'), findsOneWidget);
    // Değişmedi (304): hiçbir şey olmaz.
    await t.pump(const Duration(seconds: 3));
    await _bekle(t);
    expect(find.text('3 / 4 adet seçili'), findsOneWidget);
    expect(find.text('Adisyon güncellendi'), findsNothing);
    final once = s.istekler.where((r) => r.$2 == '/api/v1/orders/300').length;
    expect(once, greaterThan(1));
    // Başka cihaz: 2 çay ödendi (unpaid_qty 2) ve 1 su eklendi.
    final o = _adisyon(s.yanitlar);
    final kalemler = (o['items'] as List).cast<Map<String, dynamic>>();
    kalemler.first['unpaid_qty'] = 2;
    kalemler.add({...kalemler.last, 'id': 950, 'name': 'Soda', 'qty': 1, 'line_total_minor': 3000, 'unit_price_minor': 3000});
    s.yanitlar['/api/v1/orders/300'] = (200, jsonEncode({'order': o}));
    s.etaglar['/api/v1/orders/300'] = '"v2"';
    await t.pump(const Duration(seconds: 3));
    await _bekle(t);
    await t.scrollUntilVisible(find.text('Soda'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Soda'), findsOneWidget);
    // 3 seçim → 2'ye kırpıldı; ilk 2 adet artık ödendi görünür, seçilemez.
    expect(find.text('2 adet ödendi · 2 seçili'), findsOneWidget);
    expect(t.widget<InkWell>(find.byKey(const ValueKey('kasa-birim-901-0'))).onTap, isNull);
    expect(t.widget<InkWell>(find.byKey(const ValueKey('kasa-birim-901-1'))).onTap, isNull);
    expect(t.widget<InkWell>(find.byKey(const ValueKey('kasa-birim-901-3'))).onTap, isNotNull);
    expect(find.text('Adisyon güncellendi'), findsOneWidget);
    await _bitir(t, d);
  });

  testWidgets('başlık kutusu: kısmi seçimi tamamlar, sonra tamamını bırakır', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    await t.tap(find.text('Çay'));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('kasa-birim-901-1')));
    await t.pump();
    expect(find.text('1 / 4 adet seçili'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kasa-kutu-901')));
    await t.pump();
    expect(find.text('1 / 4 adet seçili'), findsNothing);
    expect(find.textContaining('4 adet'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('kasa-kutu-901')));
    await t.pump();
    expect(find.textContaining('adet seçili'), findsNothing);
    // Yeniden tamamı → ödeme qty 4.
    await t.tap(find.byKey(const ValueKey('kasa-kutu-901')));
    await t.pump();
    await _ode(t);
    final g = s.istekler.where((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).single.$3!;
    expect(g['items'], [
      {'id': 901, 'qty': 4},
    ]);
    expect(g['amount_minor'], 10000);
    await _bitir(t, d);
  });

  testWidgets('döküm yoksa adetler saat/kişi bilgisiz kart olarak açılır', (t) async {
    final (d, s) = await _kur(t, manuel: false);
    await t.tap(find.text('Kaşarlı Tost'));
    await t.pump();
    expect(find.byKey(const ValueKey('kasa-birim-902-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('kasa-birim-902-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('kasa-birim-902-2')), findsNothing);
    expect(find.text('—'), findsNWidgets(4)); // saat + kişi, iki adet
    await t.tap(find.byKey(const ValueKey('kasa-birim-902-1')));
    await t.pump();
    await _ode(t);
    final g = s.istekler.where((r) => r.$1 == 'POST' && r.$2.endsWith('/payments')).single.$3!;
    expect(g['items'], [
      {'id': 902, 'qty': 1},
    ]);
    expect(g['amount_minor'], 9000);
    await _bitir(t, d);
  });

  testWidgets('adisyon: çok adetli satır adet kartlarıyla açılır, seçim adet sayısıdır (± / 1-2-3 kutusu yok)', (t) async {
    final (d, _) = await _kur(t, manuel: false, boyut: const Size(1280, 1800), ekran: const AdisyonEkrani(adisyonId: 300));
    final satir = find.text('4× Çay', findRichText: true).first;
    await t.ensureVisible(satir);
    await t.tap(satir);
    await t.pump();
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('adisyon-birim-901-$i')), findsOneWidget);
    }
    expect(find.text('Muhammet Ali Yeni'), findsNWidgets(2));
    expect(find.byTooltip('Seçili adedi artır'), findsNothing);
    await t.ensureVisible(find.byKey(const ValueKey('adisyon-birim-901-0')));
    await t.tap(find.byKey(const ValueKey('adisyon-birim-901-0')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('adisyon-birim-901-3')));
    await t.pump();
    expect(find.textContaining('2 adet seçili'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('adisyon-birim-901-3')));
    await t.pump();
    expect(find.textContaining('1 adet seçili'), findsOneWidget);
    await _bitir(t, d);
  });

  testWidgets('adisyon: 3 nokta → Tüm ürünleri seç hepsini tikler, Seçimi kaldır bırakır', (t) async {
    final (d, _) = await _kur(t, manuel: false, boyut: const Size(1280, 1800), ekran: const AdisyonEkrani(adisyonId: 300), ek: _notYanitlari());
    // Çay 2 + Kaşarlı Tost 2 + Filtre Kahve 1 = 5 adet, 3 ürün.
    expect(find.textContaining('adet seçili'), findsNothing);
    await t.tap(find.byTooltip('Diğer işlemler'));
    await _bekle(t);
    expect(find.text('Tüm ürünleri seç'), findsOneWidget);
    await t.tap(find.text('Tüm ürünleri seç'));
    await _bekle(t);
    expect(find.textContaining('5 adet seçili · 3 üründen'), findsOneWidget);
    // Hepsi seçiliyken menü seçimi kaldırmayı önerir.
    await t.tap(find.byTooltip('Diğer işlemler'));
    await _bekle(t);
    expect(find.text('Tüm ürünleri seç'), findsNothing);
    await t.tap(find.text('Seçimi kaldır'));
    await _bekle(t);
    expect(find.textContaining('adet seçili'), findsNothing);
    await _bitir(t, d);
  });

  group('kalem notu', () {
    Future<(UygulamaDurumu, _Sunucu)> ac(WidgetTester t, {Map<String, (int, String)>? y}) =>
        _kur(t, manuel: false, boyut: const Size(1280, 1800), ekran: const AdisyonEkrani(adisyonId: 300), ek: y ?? _notYanitlari());

    testWidgets('not görünür; düğme yalnız gönderilmemiş adet varken', (t) async {
      final (d, _) = await ac(t);
      expect(find.text('Not: az şekerli'), findsOneWidget);
      expect(find.text('Not: laktosuz süt'), findsOneWidget);
      expect(find.byKey(const ValueKey('kalem-not-901')), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Notu düzenle'), findsOneWidget);
      expect(find.byKey(const ValueKey('kalem-not-902')), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Not ekle'), findsOneWidget);
      // Kahve tamamen gönderildi: salt okunur.
      expect(find.byKey(const ValueKey('kalem-not-903')), findsNothing);
      await _bitir(t, d);
    });

    testWidgets('Kaydet → PATCH {note, expected_version}', (t) async {
      final (d, s) = await ac(t);
      await t.ensureVisible(find.byKey(const ValueKey('kalem-not-902')));
      await t.tap(find.byKey(const ValueKey('kalem-not-902')));
      await t.pumpAndSettle();
      expect(find.text('Not yalnız gönderilmemiş 1 adede uygulanır'), findsOneWidget);
      expect(find.text('Notu sil'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('kalem-notu-alan')), '  mantar eklemeyin ');
      await t.pump();
      await t.tap(find.text('Kaydet'));
      await _bekle(t);
      final r = s.istekler.lastWhere((r) => r.$2.endsWith('/note'));
      expect(r.$1, 'PATCH');
      expect(r.$2, '/api/v1/orders/300/items/902/note');
      expect(r.$3, {'note': 'mantar eklemeyin', 'expected_version': 7});
      await _bitir(t, d);
    });

    testWidgets('ekran klavyesi: açılışta seçili değil, dokununca açılır, yazar', (t) async {
      final (d, s) = await ac(t);
      await t.ensureVisible(find.byKey(const ValueKey('kalem-not-902')));
      await t.tap(find.byKey(const ValueKey('kalem-not-902')));
      await t.pumpAndSettle();
      final alan = find.descendant(of: find.byKey(const ValueKey('kalem-notu-alan')), matching: find.byType(EditableText));
      expect(t.widget<EditableText>(alan).focusNode.hasFocus, isFalse);
      expect(find.text('Ekran klavyesi'), findsNothing);
      await t.tap(alan);
      await t.pumpAndSettle();
      expect(find.text('Ekran klavyesi'), findsOneWidget);
      for (final h in ['l', 'a', 'k', 't', 'o', 'z']) {
        await t.tap(find.text(h).last);
        await t.pump();
      }
      await t.tap(find.text('Tamam'));
      await t.pumpAndSettle();
      expect(find.text('Ekran klavyesi'), findsNothing);
      await t.tap(find.text('Kaydet'));
      await _bekle(t);
      final r = s.istekler.lastWhere((r) => r.$2.endsWith('/note'));
      expect(r.$3, {'note': 'laktoz', 'expected_version': 7});
      await _bitir(t, d);
    });

    testWidgets('Notu sil → note: null', (t) async {
      final (d, s) = await ac(t);
      await t.ensureVisible(find.byKey(const ValueKey('kalem-not-901')));
      await t.tap(find.byKey(const ValueKey('kalem-not-901')));
      await t.pumpAndSettle();
      expect(find.text('az şekerli'), findsOneWidget); // alan dolu gelir
      await t.tap(find.text('Notu sil'));
      await _bekle(t);
      final r = s.istekler.lastWhere((r) => r.$2.endsWith('/note'));
      expect(r.$2, '/api/v1/orders/300/items/901/note');
      expect(r.$3!.containsKey('note'), isTrue);
      expect(r.$3!['note'], isNull);
      await _bitir(t, d);
    });

    testWidgets('422: sunucu mesajı gösterilir', (t) async {
      final (d, _) = await ac(t, y: {
        ..._notYanitlari(),
        'PATCH /api/v1/orders/300/items/901/note': (422, jsonEncode({
          'message': 'x',
          'errors': {'note': ['Hazırlığa gönderilen kaleme not eklenemez.']},
        })),
      });
      await t.ensureVisible(find.byKey(const ValueKey('kalem-not-901')));
      await t.tap(find.byKey(const ValueKey('kalem-not-901')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('kalem-notu-alan')), 'az pişmiş');
      await t.pump();
      await t.tap(find.text('Kaydet'));
      await _bekle(t);
      expect(find.text('Hazırlığa gönderilen kaleme not eklenemez.'), findsOneWidget);
      await _bitir(t, d);
    });

    testWidgets('Kasa: not satırda salt okunur görünür', (t) async {
      final (d, _) = await _kur(t, manuel: false, ek: _notYanitlari());
      expect(find.text('Not: az şekerli'), findsWidgets);
      expect(find.text('Not ekle'), findsNothing);
      await _bitir(t, d);
    });
  });

  group('kasa: seçimden ikram', () {
    Map<String, (int, String)> yanit({bool cayIkram = false, bool tostOdendi = false}) {
      final y = _kasaYanitlari();
      final o = _adisyon(y);
      o['is_open'] = true;
      o['version'] = 9;
      final ks = (o['items'] as List).cast<Map<String, dynamic>>();
      if (cayIkram) {
        ks[0]
          ..['is_comp'] = true
          ..['comp_reason'] = 'Geç servis';
      }
      if (tostOdendi) ks[1]['is_settled'] = true;
      return {...y, '/api/v1/orders/300': (200, jsonEncode({'order': o}))};
    }

    /// Tüm kalemler ikram: toplam 0, kalan 0, adisyon hâlâ AÇIK.
    Map<String, (int, String)> sifirYanit() {
      final y = _kasaYanitlari();
      final o = _adisyon(y);
      for (final k in (o['items'] as List).cast<Map<String, dynamic>>()) {
        k
          ..['is_comp'] = true
          ..['comp_reason'] = 'Geç servis'
          ..['line_total_minor'] = 0;
      }
      o
        ..['is_open'] = true
        ..['version'] = 12
        ..['comp_total_minor'] = 28000
        ..['total_minor'] = 0
        ..['paid_minor'] = 0
        ..['remaining_minor'] = 0;
      final ozet = Map<String, dynamic>.from(o)
        ..remove('items')
        ..remove('events');
      return {
        ...y,
        '/api/v1/payments/pending-orders': (200, jsonEncode({'orders': [ozet]})),
        '/api/v1/orders/300': (200, jsonEncode({'order': o})),
        'GET /api/v1/orders/300/payments': (200, jsonEncode({'order': ozet, 'payments': []})),
        'POST /api/v1/orders/300/sifir-kapat': (200, jsonEncode({'order': {...ozet, 'is_open': false, 'status': 'paid', 'version': 13}})),
      };
    }

    final menu = find.byKey(const ValueKey('kasa-secim-menu'));
    final onayliyorum = find.byKey(const ValueKey('ikram-onayliyorum'));
    Finder hazir(String ad) => find.byKey(ValueKey('ikram-hazir-$ad'));
    List<(String, String, Map<String, dynamic>?)> compIstekleri(_Sunucu s) => s.istekler.where((r) => r.$1 == 'POST' && r.$2.endsWith('/comp')).toList();

    /// ⋮ → İkram et → onay penceresi.
    Future<void> menudenIkram(WidgetTester t) async {
      await t.ensureVisible(menu);
      await t.pump();
      await t.tap(menu);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kasa-secim-ikram')));
      await t.pumpAndSettle();
    }

    Future<void> ikisiniSec(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('kasa-kutu-901')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kasa-kutu-902')));
      await t.pump();
    }

    Future<void> ikisiniSecVeIkramEt(WidgetTester t, {String neden = 'Ürün geç geldi'}) async {
      await ikisiniSec(t);
      await menudenIkram(t);
      await t.tap(hazir(neden));
      await t.pump();
      await t.tap(onayliyorum);
      await _bekle(t);
    }

    testWidgets('seçim şeridinde ayrı "İkram et" düğmesi yok; ⋮ menüsünde, adet sayısıyla', (t) async {
      final (d, _) = await _kur(t, manuel: false, ek: yanit());
      expect(menu, findsNothing); // seçim yokken şerit yok
      await ikisiniSec(t);
      expect(menu, findsOneWidget);
      expect(find.text('Tutara yaz'), findsOneWidget);
      expect(find.text('Temizle'), findsOneWidget);
      expect(find.text('İkram et (6)'), findsNothing); // menü kapalıyken görünmez
      await t.tap(menu);
      await t.pumpAndSettle();
      expect(find.text('İkram et (6)'), findsOneWidget);
      expect(t.widget<PopupMenuItem<String>>(find.byKey(const ValueKey('kasa-secim-ikram'))).enabled, isTrue);
      await _bitir(t, d);
    });

    testWidgets('⋮ → İkram et: pencere ürünleri, tutarları ve toplamı listeler', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await ikisiniSec(t);
      await menudenIkram(t);
      expect(find.text('İkram onayı'), findsOneWidget);
      expect(find.text('Bu ürünleri ikram etmek istediğinizden emin misiniz?'), findsOneWidget);
      expect(find.textContaining('4× Çay', findRichText: true), findsWidgets);
      expect(find.textContaining('2× Kaşarlı Tost', findRichText: true), findsWidgets);
      expect(find.text('2 kalem · 6 adet ikram edilecek'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('ikram-toplam'))).data, para(28000));
      // Hazır açıklamalar + Diğer.
      for (final a in [...ikramHazirAciklamalar, 'Diğer']) {
        expect(hazir(a), findsOneWidget);
      }
      // Pencere açılınca hiçbir şey gitmez.
      expect(compIstekleri(s), isEmpty);
      await _bitir(t, d);
    });

    testWidgets('Onaylamıyorum → POST yok, pencere kapanır, seçim kalır', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await ikisiniSec(t);
      await menudenIkram(t);
      await t.tap(hazir('Müşteri memnuniyeti'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('ikram-onaylamiyorum')));
      await _bekle(t);
      expect(find.text('İkram onayı'), findsNothing);
      expect(compIstekleri(s), isEmpty);
      expect(menu, findsOneWidget); // seçim yerinde
      expect(find.textContaining('6 adet', findRichText: true), findsWidgets);
      await _bitir(t, d);
    });

    testWidgets('dışarı dokunuş da Onaylamıyorum gibi: POST yok', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await ikisiniSec(t);
      await menudenIkram(t);
      await t.tap(hazir('Müşteri memnuniyeti'));
      await t.pump();
      await t.tapAt(const Offset(5, 5));
      await _bekle(t);
      expect(find.text('İkram onayı'), findsNothing);
      expect(compIstekleri(s), isEmpty);
      expect(menu, findsOneWidget);
      await _bitir(t, d);
    });

    testWidgets('açıklamasız / 3 karakterden kısa açıklamayla Onaylıyorum kapalı', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await ikisiniSec(t);
      await menudenIkram(t);
      expect(t.widget<FilledButton>(onayliyorum).onPressed, isNull);
      await t.tap(onayliyorum, warnIfMissed: false);
      await _bekle(t);
      expect(compIstekleri(s), isEmpty);
      final alan = find.descendant(of: find.byKey(const ValueKey('ikram-aciklama')), matching: find.byType(TextField));
      await t.enterText(alan, 'ab');
      await t.pump();
      expect(t.widget<FilledButton>(onayliyorum).onPressed, isNull);
      expect(find.text('Açıklama en az 3 karakter olmalı.'), findsOneWidget);
      await t.enterText(alan, '   ');
      await t.pump();
      expect(t.widget<FilledButton>(onayliyorum).onPressed, isNull);
      expect(find.text('İkram onayı'), findsOneWidget);
      expect(compIstekleri(s), isEmpty);
      await _bitir(t, d);
    });

    testWidgets('elle yazılan açıklama gider; hazır seçilip düzenlenebilir', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await t.tap(find.byKey(const ValueKey('kasa-kutu-902')));
      await t.pump();
      await menudenIkram(t);
      await t.tap(hazir('İşletme ikramı'));
      await t.pump();
      final alan = find.descendant(of: find.byKey(const ValueKey('ikram-aciklama')), matching: find.byType(TextField));
      expect(t.widget<TextField>(alan).controller!.text, 'İşletme ikramı');
      await t.enterText(alan, 'İşletme ikramı - doğum günü');
      await t.pump();
      await t.tap(onayliyorum);
      await _bekle(t);
      expect(compIstekleri(s).single.$3, {'reason': 'İşletme ikramı - doğum günü', 'expected_version': 9, 'qty': 2});
      await _bitir(t, d);
    });

    testWidgets('kısmi adet: 4 çaydan 2si → hazır açıklama → POST comp {reason, expected_version, qty: 2}', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await t.tap(find.text('Çay'));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kasa-birim-901-0')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('kasa-birim-901-2')));
      await t.pump();
      await menudenIkram(t);
      expect(find.textContaining('2× Çay', findRichText: true), findsWidgets);
      expect(find.text('2 adet adisyonda ücretli kalır'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('ikram-toplam'))).data, para(5000));
      await t.tap(hazir('Müşteri ürünü tüketmedi'));
      await t.pump();
      await t.tap(onayliyorum);
      await t.tap(onayliyorum, warnIfMissed: false); // çift dokunuş ikinci istek atmaz
      await _bekle(t);
      final r = s.istekler.where((r) => r.$1 == 'POST' && r.$2 == '/api/v1/orders/300/items/901/comp').toList();
      expect(r, hasLength(1));
      expect(r.single.$3, {'reason': 'Müşteri ürünü tüketmedi', 'expected_version': 9, 'qty': 2});
      // Başarıdan sonra pencere kapanır, seçim temizlenir.
      expect(find.text('İkram onayı'), findsNothing);
      expect(menu, findsNothing);
      await _bitir(t, d);
    });

    testWidgets('satırın tamamı seçiliyse de qty açıkça gider', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      await t.tap(find.byKey(const ValueKey('kasa-kutu-902')));
      await t.pump();
      await menudenIkram(t);
      expect(find.textContaining('adisyonda ücretli kalır'), findsNothing);
      await t.tap(hazir('Müşteri ürünü iade etti'));
      await t.pump();
      await t.tap(onayliyorum);
      await _bekle(t);
      final r = s.istekler.where((r) => r.$1 == 'POST' && r.$2 == '/api/v1/orders/300/items/902/comp').single;
      expect(r.$3, {'reason': 'Müşteri ürünü iade etti', 'expected_version': 9, 'qty': 2});
      await _bitir(t, d);
    });

    testWidgets('ikram edilmiş satırda İkramı kaldır → DELETE comp {expected_version}', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit(cayIkram: true));
      expect(find.text('İkram · Geç servis'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('kasa-ikram-kaldir-901')));
      await _bekle(t);
      final r = s.istekler.where((r) => r.$1 == 'DELETE' && r.$2 == '/api/v1/orders/300/items/901/comp').single;
      expect(r.$3, {'expected_version': 9});
      await _bitir(t, d);
    });

    testWidgets('çok satır: tek açıklama, satır başına bir POST SIRAYLA; sonraki çağrı önceki yanıtın sürümüyle', (t) async {
      final y = yanit();
      final o = _adisyon(y);
      Map<String, dynamic> sonrasi(int surum, Set<int> ikramlar) => {
            ...o,
            'version': surum,
            'items': [
              for (final k in (o['items'] as List).cast<Map<String, dynamic>>())
                ikramlar.contains(k['id']) ? {...k, 'is_comp': true, 'comp_reason': 'Geç servis'} : k,
            ],
          };
      final (d, s) = await _kur(t, manuel: false, ek: {
        ...y,
        'POST /api/v1/orders/300/items/901/comp': (200, jsonEncode({'order': sonrasi(10, {901})})),
        'POST /api/v1/orders/300/items/902/comp': (200, jsonEncode({'order': sonrasi(11, {901, 902})})),
      });
      await ikisiniSecVeIkramEt(t);
      final comp = compIstekleri(s);
      expect(comp.map((r) => r.$2), ['/api/v1/orders/300/items/901/comp', '/api/v1/orders/300/items/902/comp']);
      expect(comp[0].$3, {'reason': 'Ürün geç geldi', 'expected_version': 9, 'qty': 4});
      expect(comp[1].$3, {'reason': 'Ürün geç geldi', 'expected_version': 10, 'qty': 2});
      // Yanıttaki adisyon ekrana basılır: ödemeler / detay yeniden sorulmaz;
      // liste bir kez tazelenir.
      final sonra = s.istekler.skipWhile((r) => !(r.$1 == 'POST' && r.$2.endsWith('/comp'))).toList();
      expect(sonra.where((r) => r.$1 == 'GET' && r.$2.startsWith('/api/v1/orders/300')), isEmpty);
      expect(sonra.where((r) => r.$1 == 'GET' && r.$2 == '/api/v1/payments/pending-orders'), hasLength(1));
      expect(find.text('İkram · Geç servis'), findsNWidgets(2));
      expect(find.text('İkram onayı'), findsNothing);
      expect(menu, findsNothing);
      await _bitir(t, d);
    });

    testWidgets('çok satır: ikincisi reddedilirse durur, kaçının işlendiği söylenir, seçim temizlenir', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: {
        ...yanit(),
        'POST /api/v1/orders/300/items/902/comp': (422, jsonEncode({'message': 'Ödenmiş kalem ikram edilemez.'})),
      });
      await ikisiniSecVeIkramEt(t);
      expect(compIstekleri(s), hasLength(2));
      expect(find.textContaining('Ödenmiş kalem ikram edilemez. (1 / 2 kalem ikram edildi'), findsOneWidget);
      expect(find.text('İkram onayı'), findsNothing);
      expect(menu, findsNothing);
      final sonra = s.istekler.skipWhile((r) => !(r.$1 == 'POST' && r.$2.endsWith('/902/comp'))).skip(1);
      expect(sonra.any((r) => r.$1 == 'GET' && r.$2 == '/api/v1/orders/300'), isTrue);
      await _bitir(t, d);
    });

    testWidgets('409 (hiçbiri işlenmedi): pencere açık kalır, hata içinde; yeniden onay güncel sürümle gider', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      s.sirali['POST /api/v1/orders/300/items/902/comp'] = [
        (409, jsonEncode({'message': 'Adisyon değişti.'})),
      ];
      await t.tap(find.byKey(const ValueKey('kasa-kutu-902')));
      await t.pump();
      await menudenIkram(t);
      await t.tap(hazir('Yanlış sipariş'));
      await t.pump();
      await t.tap(onayliyorum);
      await _bekle(t);
      expect(find.text('İkram onayı'), findsOneWidget);
      expect(find.byKey(const ValueKey('ikram-hata')), findsOneWidget);
      expect(find.textContaining('başka bir cihazda değişti'), findsOneWidget);
      expect(t.widget<FilledButton>(onayliyorum).onPressed, isNotNull);
      // Sunucuda sürüm ilerledi; ikinci deneme yeni sürümle.
      final y2 = yanit();
      final o2 = _adisyon(y2)
        ..['is_open'] = true
        ..['version'] = 14;
      s.yanitlar['/api/v1/orders/300'] = (200, jsonEncode({'order': o2}));
      s.sirali['POST /api/v1/orders/300/items/902/comp'] = [(422, jsonEncode({'message': 'Açıklama geçersiz.'}))];
      await t.tap(onayliyorum);
      await _bekle(t);
      expect(find.text('Açıklama geçersiz.'), findsOneWidget);
      expect(find.text('İkram onayı'), findsOneWidget);
      await t.tap(onayliyorum);
      await _bekle(t);
      final r = s.istekler.where((r) => r.$1 == 'POST' && r.$2 == '/api/v1/orders/300/items/902/comp').toList();
      expect(r, hasLength(3));
      expect(r[0].$3?['expected_version'], 9);
      expect(r[2].$3, {'reason': 'Yanlış sipariş', 'expected_version': 14, 'qty': 2});
      expect(find.text('İkram onayı'), findsNothing);
      await _bitir(t, d);
    });

    testWidgets('düzelt kipindeki İkram yap da aynı onay penceresini açar', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit(), ekYetki: const ['orders.comp']);
      await t.tap(find.byKey(const ValueKey('kasa-duzelt')));
      await t.pump();
      await t.tap(find.text('İkram yap').first);
      await t.pumpAndSettle();
      expect(find.text('İkram onayı'), findsOneWidget);
      await t.tap(hazir('Personel / sahip ikramı'));
      await t.pump();
      await t.tap(onayliyorum);
      await _bekle(t);
      expect(compIstekleri(s).single.$3, {'reason': 'Personel / sahip ikramı', 'expected_version': 9, 'qty': 4});
      await _bitir(t, d);
    });

    test('yetki reddi: 403 ya da 422 errors.operator', () {
      expect(personelYetkiReddi(ApiHata(403, 'x')), isTrue);
      expect(personelYetkiReddi(ApiHata(422, 'x', {'errors': {'operator': ['y']}})), isTrue);
      expect(personelYetkiReddi(ApiHata(422, 'x', {'errors': {'reason': ['y']}})), isFalse);
      expect(personelYetkiReddi(ApiHata(409, 'x')), isFalse);
    });

    testWidgets('aktif personelin ikram yetkisi yoksa PIN sorulur, istek PIN ile yinelenir', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: yanit());
      s.sirali['POST /api/v1/orders/300/items/902/comp'] = [
        (422, jsonEncode({'message': 'Aktif personelin bu işlem için yetkisi yok.', 'errors': {'operator': ['Aktif personelin bu işlem için yetkisi yok.']}})),
      ];
      await t.tap(find.byKey(const ValueKey('kasa-kutu-902')));
      await t.pump();
      await menudenIkram(t);
      await t.tap(hazir('Müşteri memnuniyeti'));
      await t.pump();
      await t.tap(onayliyorum);
      await _bekle(t);
      expect(find.text('Personel PIN'), findsOneWidget);
      await t.enterText(find.descendant(of: find.widgetWithText(AlertDialog, 'Personel PIN'), matching: find.byType(TextField)), '1234');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Onayla'));
      await _bekle(t);
      final r = s.istekler.where((r) => r.$1 == 'POST' && r.$2 == '/api/v1/orders/300/items/902/comp').toList();
      expect(r, hasLength(2));
      expect(r.first.$3, {'reason': 'Müşteri memnuniyeti', 'expected_version': 9, 'qty': 2});
      expect(r.last.$3, {'reason': 'Müşteri memnuniyeti', 'expected_version': 9, 'qty': 2, 'pin': '1234', 'staff_code': null});
      await _bitir(t, d);
    });

    testWidgets('Düzelt: ödenmiş satırda düzeltme çubuğu (adet / Değiştir / Çıkar / İkram) yok', (t) async {
      final (d, _) = await _kur(t, manuel: false, ek: yanit(tostOdendi: true));
      await t.tap(find.byKey(const ValueKey('kasa-duzelt')));
      await t.pump();
      expect(find.text('Değiştir'), findsOneWidget); // yalnız ödenmemiş Çay
      await _bitir(t, d);
    });

    testWidgets('tümü ikram (0 ₺) açık adisyon: "Adisyonu kapat (0 ₺)" → sifir-kapat', (t) async {
      final (d, s) = await _kur(t, manuel: false, ek: sifirYanit());
      expect(find.text('Adisyon tamamen ödendi'), findsNothing);
      expect(find.textContaining('tahsil edildi'), findsNothing);
      final dugme = find.byKey(const ValueKey('kasa-sifir-kapat'));
      expect(dugme, findsOneWidget);
      expect(find.text('Adisyonu kapat (0 ₺)'), findsOneWidget);
      await t.ensureVisible(dugme);
      await t.pump();
      await t.tap(dugme);
      await t.tap(dugme, warnIfMissed: false); // çift dokunuş ikinci istek atmaz
      await _bekle(t);
      final r = s.istekler.where((r) => r.$1 == 'POST' && r.$2 == '/api/v1/orders/300/sifir-kapat').toList();
      expect(r, hasLength(1));
      expect(r.single.$3, {'expected_version': 12});
      expect(dugme, findsNothing);
      expect(find.text('Adisyon kapatıldı'), findsWidgets);
      expect(find.text('Tüm kalemler ikram — tahsilat yapılmadı.'), findsOneWidget);
      await _bitir(t, d);
    });
  });

  group('kasada açık ödeme yöntemleri', () {
    tearDown(() => acikKasaYontemleri = null);

    test('bilgi yoksa hepsi listelenir', () {
      acikKasaYontemleri = null;
      expect(kasadaGorunenYontemler.length, kasaYontemleri.length);
    });

    test('kapatılan yöntem listelenmez, sıra korunur', () {
      acikKasaYontemleri = {'cash', 'credit_card', 'meal_card'};
      expect(kasadaGorunenYontemler.map((y) => y.$1).toList(), ['cash', 'credit_card', 'meal_card']);
    });
  });
}
