// Açılış animasyonunun kareleri: GORUNTU_DIZINI=... flutter test test/acilis_kareleri_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bambumpos_personel/core/api.dart';
import 'package:bambumpos_personel/core/durum.dart';
import 'package:bambumpos_personel/core/tema.dart';
import 'package:bambumpos_personel/ekranlar/acilis.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _dizin = Platform.environment['GORUNTU_DIZINI'];

/// Hiç yanıt vermeyen sunucu: açılış "bekliyor" hâlinde kalır.
class _Bekleyen implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) => Completer<ResponseBody>().future;
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final poppins = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
    }
    final jakarta = FontLoader('Jakarta')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync())));
    await poppins.load();
    await jakarta.load();
  });
  testWidgets('açılış kareleri', (t) async {
    Uyg.api = Api.bellekte(_Bekleyen(), tabanUrl: 'https://personel.bambumpos.com');
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final sinir = GlobalKey();
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaKur(Brightness.light),
      home: RepaintBoundary(key: sinir, child: const AcilisEkrani()),
    ));
    var gecen = 0;
    for (final ms in [150, 350, 550, 750, 950, 1150, 1400, 1700, 2100, 2600]) {
      await t.pump(Duration(milliseconds: ms - gecen));
      gecen = ms;
      await t.runAsync(() async {
        final b = sinir.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        // ignore: avoid_print
        print('kare $ms');
        File('$_dizin/acilis-${ms.toString().padLeft(4, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }, skip: _dizin == null);
}
