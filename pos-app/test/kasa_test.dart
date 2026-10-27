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
    return ResponseBody.fromString(y.$2, y.$1, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

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
    '/api/v1/discount-presets': (200, jsonEncode({'presets': [{'id': 1, 'name': 'Öğrenci', 'value_label': '%10'}]})),
  };
}

Future<(UygulamaDurumu, _Sunucu)> _kur(WidgetTester t, {required bool manuel}) async {
  // Test yazı tipi (Ahem) her harfi kare çizer; dar kartlardaki taşma
  // uyarıları gerçek cihazda yoktur — bu testin konusu değil.
  final onceki = FlutterError.onError;
  FlutterError.onError = (e) {
    if (e.exceptionAsString().contains('overflowed')) return;
    onceki?.call(e);
  };
  addTearDown(() => FlutterError.onError = onceki);
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  final ham = (jsonDecode(_veri('oturum')) as Map).cast<String, dynamic>();
  ham['yetkiler'] = [...(ham['yetkiler'] as List), 'payments.take', 'orders.discount', 'orders.view'];
  ham['eklentiler'] = {...(ham['eklentiler'] as Map), 'manuel_iskonto': manuel};
  final sunucu = _Sunucu({..._kasaYanitlari(), '/api/v1/uygulama/oturum': (200, jsonEncode(ham))});
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

Future<void> _ode(WidgetTester t) async {
  await t.ensureVisible(find.text('Nakit').first);
  await t.pump();
  await t.tap(find.text('Nakit').first);
  await t.pump();
  await t.ensureVisible(find.textContaining('ödemesini al'));
  await t.pump();
  await t.tap(find.textContaining('ödemesini al'));
  await _bekle(t);
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
}
