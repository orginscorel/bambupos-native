// Kasa: kısmi adet seçimiyle ödeme (items alanı), eski sunucuya geri
// düşüş ve indirim penceresinin manuel iskonto eklentisine göre açılışı.
import 'dart:convert';
import 'dart:io';

import 'package:bambumpos_pos/app/tema.dart';
import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/durum.dart';
import 'package:bambumpos_pos/core/modeller.dart';
import 'package:bambumpos_pos/ekranlar/kasa_ekrani.dart';
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
  Map<String, dynamic> kalem(int id, String ad, int adet, int birim) => {
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
      };
  o['items'] = [kalem(901, 'Çay', 4, 2500), kalem(902, 'Kaşarlı Tost', 2, 9000)];
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

Future<(UygulamaDurumu, _Sunucu)> _kur(WidgetTester t, {required bool manuel, Map<String, (int, String)> ek = const {}, Size boyut = const Size(1280, 800)}) async {
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
  ham['yetkiler'] = [...(ham['yetkiler'] as List), 'payments.take', 'orders.discount', 'orders.view', 'orders.update'];
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
      home: const Scaffold(body: KasaEkrani()),
    ),
  ));
  await _bekle(t);
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
  await t.tap(find.byKey(const ValueKey('kasa-birim-901-0')));
  await t.pump();
  await t.tap(find.byKey(const ValueKey('kasa-birim-901-2')));
  await t.pump();
  expect(find.text('2/4'), findsOneWidget);
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
    expect(find.text('2/4'), findsNothing); // seçim temizlendi
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
    expect(find.text('3/4'), findsOneWidget);
    // Değişmedi (304): hiçbir şey olmaz.
    await t.pump(const Duration(seconds: 3));
    await _bekle(t);
    expect(find.text('3/4'), findsOneWidget);
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
    expect(find.text('2/4'), findsOneWidget); // 3 seçim → 2'ye kırpıldı
    expect(find.text('Adisyon güncellendi'), findsOneWidget);
    await _bitir(t, d);
  });
}
