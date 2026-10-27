// Uygulama simgesini işaretten üretir (elle çalıştırılır):
//   flutter test tool/simge_uret_test.dart && dart run flutter_launcher_icons
// Çıktı: assets/simge/simge.png (1024, tam kare zemin) ve on_plan.png (1024,
// uyarlanabilir simge ön planı, şeffaf; güvenli alan içinde).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_patron/core/tema.dart';
import 'package:bambumpos_patron/ortak/ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _yaz(String yol, void Function(Canvas c) ciz) async {
  final kayit = ui.PictureRecorder();
  ciz(Canvas(kayit));
  final img = await kayit.endRecording().toImage(1024, 1024);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(yol).writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('simge üret', () async {
    await _yaz('assets/simge/simge.png', (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..shader = Marka.grad.createShader(const Rect.fromLTWH(0, 0, 1024, 1024)));
      c.scale(1024 / 64);
      PatronMarkCizer.ciz(c, zeminVar: false);
    });
    await _yaz('assets/simge/on_plan.png', (c) {
      // Uyarlanabilir simge: içerik ortadaki ~%62'lik güvenli alanda.
      c.translate(512, 512);
      c.scale(1024 / 96);
      c.translate(-32, -32);
      PatronMarkCizer.ciz(c, zeminVar: false);
    });
    await _yaz('assets/simge/logo.png', (c) {
      c.scale(1024 / 64);
      PatronMarkCizer.ciz(c);
    });
  });
}
