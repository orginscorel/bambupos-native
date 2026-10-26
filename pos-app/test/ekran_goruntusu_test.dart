// Ekran görüntüsü üretici (CI'da çalışmaz): demo işletmesinden alınmış
// gerçek yanıtlarla ekranları çizip PNG yazar.
//   GORUNTU_DIZINI=/yol flutter test test/ekran_goruntusu_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_pos/app/tema.dart';
import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/durum.dart';
import 'package:bambumpos_pos/ekranlar/adisyon_ekrani.dart';
import 'package:bambumpos_pos/ekranlar/aktivasyon_ekrani.dart';
import 'package:bambumpos_pos/ekranlar/kabuk.dart';
import 'package:bambumpos_pos/ekranlar/ortak.dart';
import 'package:bambumpos_pos/ekranlar/pin_ekrani.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _dizin = Platform.environment['GORUNTU_DIZINI'];

String _veri(String ad) => File('test/veri/$ad.json').readAsStringSync();

class _SahteSunucu implements HttpClientAdapter {
  _SahteSunucu(this.oturum);
  final String oturum;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    final yol = o.uri.path;
    final govde = switch (yol) {
      '/api/v1/uygulama/oturum' => oturum,
      '/api/v1/orders/board' => _veri('pano'),
      '/api/v1/orders/catalog' => _veri('katalog'),
      '/api/v1/cihaz-aktivasyon/baslat' => '{"kod":"K7M3QP","gizli":"x","bitis":"${DateTime.now().add(const Duration(minutes: 29, seconds: 41)).toUtc().toIso8601String()}"}',
      '/api/v1/cihaz-aktivasyon/durum' => '{"durum":"bekliyor"}',
      _ when yol.startsWith('/api/v1/orders/') => _veri('adisyon'),
      _ => '{}',
    };
    return ResponseBody.fromString(govde, 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _fontlar() async {
  // Uygulamanın gömülü yazı tipi (web ile aynı): Poppins.
  final poppins = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
  }
  await poppins.load();
  // Material simgeleri Flutter SDK'nın kendi kopyasından.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path; // .../artifacts/engine/<platform>/flutter_tester
  final kok = Platform.environment['FLUTTER_FONTLARI'] ?? '$artifacts/material_fonts';
  final ikon = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('$kok/MaterialIcons-Regular.otf').readAsBytesSync())));
  await ikon.load();
}

Future<UygulamaDurumu> _durum({Map<String, dynamic>? oturumDegis}) async {
  SharedPreferences.setMockInitialValues({});
  final ham = (jsonDecode(_veri('oturum')) as Map).cast<String, dynamic>()..addAll(oturumDegis ?? {});
  final api = Api.bellekte(_SahteSunucu(jsonEncode(ham)));
  final d = UygulamaDurumu.test(api, await SharedPreferences.getInstance(), Directory.systemTemp.createTempSync('bbpos').path);
  return d;
}

Widget _uygulama(UygulamaDurumu d, Widget ekran) => DurumKapsami(
      durum: d,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: temaKur(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (_, c) => RepaintBoundary(key: _sinir, child: c),
        home: ekran,
      ),
    );

final _sinir = GlobalKey();

Future<void> _yaz(WidgetTester t, String ad) async {
  await t.runAsync(() async {
    final b = _sinir.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_dizin/$ad.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _boyut(WidgetTester t, Size s) async {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _bekle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // KOYU=1 → koyu tema görüntüleri.
  koyuTema.value = Platform.environment['KOYU'] == '1';
  if (_dizin != null) setUpAll(_fontlar);
  // Görsel önbelleği (cached_network_image) geçici klasör ister.
  setUp(() {
    final gecici = Directory.systemTemp.createTempSync('bbpos-onbellek').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => gecici);
  });

  const tablet = Size(1280, 800);
  const telefon = Size(412, 900);

  const dikey = Size(800, 1280);
  for (final (ad, boyut) in [('tablet', tablet), ('telefon', telefon), ('dikey', dikey)]) {
    testWidgets('aktivasyon $ad', (t) async {
      await _boyut(t, boyut);
      final d = await _durum();
      await t.pumpWidget(_uygulama(d, const AktivasyonEkrani()));
      await _bekle(t);
      await _yaz(t, '1-aktivasyon-$ad');
      await t.pumpWidget(const SizedBox());
    }, skip: _dizin == null);

    testWidgets('pin $ad', (t) async {
      await _boyut(t, boyut);
      final d = await _durum();
      await t.runAsync(d.oturumuYenile);
      await t.pumpWidget(_uygulama(d, const PinEkrani()));
      await _bekle(t);
      await _yaz(t, '2-pin-$ad');
      await t.pumpWidget(const SizedBox());
    }, skip: _dizin == null);

    for (final istasyon in ['order_entry', 'kasa']) {
      testWidgets('kabuk $istasyon $ad', (t) async {
        await _boyut(t, boyut);
        final ham = (jsonDecode(_veri('oturum')) as Map).cast<String, dynamic>();
        final cihaz = Map<String, dynamic>.from(ham['cihaz'] as Map)..['istasyon'] = istasyon;
        final d = await _durum(oturumDegis: {
          'cihaz': cihaz,
          'yetkiler': [...(ham['yetkiler'] as List), 'payments.take'],
        });
        await t.runAsync(d.oturumuYenile);
        await t.pumpWidget(_uygulama(d, const Kabuk()));
        await _bekle(t);
        await _yaz(t, '3-pano-$istasyon-$ad');
        if (istasyon == 'order_entry') {
          await t.tap(find.text('Ayşe Yıldız').last);
          await _bekle(t);
          expect(find.text('Personel değiştir'), findsOneWidget);
          await _yaz(t, '6-kisi-$ad');
          await t.tapAt(const Offset(5, 300));
          await _bekle(t);
          await t.tap(find.text('Tümü'));
          await _bekle(t);
          await _yaz(t, '8-tumu-$ad');
        }
        await t.pumpWidget(const SizedBox());
      }, skip: _dizin == null);
    }

    testWidgets('adisyon $ad', (t) async {
      await _boyut(t, boyut);
      final ham = (jsonDecode(_veri('oturum')) as Map).cast<String, dynamic>();
      final d = await _durum(oturumDegis: {
        'yetkiler': [...(ham['yetkiler'] as List), 'payments.take'],
      });
      await t.runAsync(d.oturumuYenile);
      await t.pumpWidget(_uygulama(d, const AdisyonEkrani(adisyonId: 300)));
      await _bekle(t);
      await _yaz(t, '4-adisyon-$ad');
      await t.pumpWidget(const SizedBox());
      d.ajan?.dispose();
      // Görsel önbelleğinin kendi zamanlayıcıları bitsin.
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump(const Duration(seconds: 30));
    }, skip: _dizin == null);
  }
}
