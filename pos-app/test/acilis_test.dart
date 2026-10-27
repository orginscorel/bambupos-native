// Açılış perdesi: en az süre dolmadan ve oturum hazır olmadan açılmaz,
// ikisi de olunca kalkar ve alttaki ekran dokunulabilir kalır.
//   GORUNTU_DIZINI=/yol flutter test test/acilis_test.dart  → kareleri PNG yazar.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bambumpos_pos/ekranlar/acilis.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _dizin = Platform.environment['GORUNTU_DIZINI'];
final _sinir = GlobalKey();

Widget _sahne(bool hazir) => MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (_, c) => RepaintBoundary(key: _sinir, child: c),
      home: AcilisKatmani(hazir: hazir, surum: '1.2.11', child: const Scaffold(body: Center(child: Text('ALTTAKI')))),
    );

void main() {
  testWidgets('perde süre + hazır olunca kalkar', (t) async {
    await t.pumpWidget(_sahne(true));
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('Bağlanıyor…'), findsNothing); // hazır → "Hazır"
    expect(find.text('Hazır'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 800)); // 1,6 sn: giriş bitti, çıkış başladı
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Hazır'), findsNothing);
    expect(find.text('ALTTAKI'), findsOneWidget);
  });

  testWidgets('oturum hazır değilse perde kalır', (t) async {
    await t.pumpWidget(_sahne(false));
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Bağlanıyor…'), findsOneWidget);
    await t.pumpWidget(_sahne(true));
    await t.pump(const Duration(milliseconds: 700));
    expect(find.text('Bağlanıyor…'), findsNothing);
    expect(find.text('Hazır'), findsNothing);
  });

  testWidgets('kareler', (t) async {
    if (_dizin == null) return;
    final p = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      p.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
    }
    await p.load();
    t.view.physicalSize = const Size(1280, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_sahne(false));
    var gecen = 0;
    for (final ms in [150, 350, 550, 750, 950, 1150, 1500, 2600]) {
      await t.pump(Duration(milliseconds: ms - gecen));
      gecen = ms;
      await t.runAsync(() async {
        final b = _sinir.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_dizin/acilis-${ms.toString().padLeft(4, '0')}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await t.pumpWidget(_sahne(true));
    await t.pump(const Duration(milliseconds: 260));
    await t.runAsync(() async {
      final b = _sinir.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await b.toImage(pixelRatio: 1)).toByteData(format: ui.ImageByteFormat.png);
      File('$_dizin/acilis-cikis.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    await t.pump(const Duration(seconds: 1));
  });
}
