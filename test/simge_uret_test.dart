// Uygulama simgelerini YENİ Patron işaretinden (PatronMarkCizer) üretir.
// Elle çalıştırılır:  SIMGE_URET=1 flutter test test/simge_uret_test.dart
// (İsteğe bağlı LOGO_KOPYA=/yol/logo.png → 1024'lük önizleme kopyası.)
// Ortam değişkeni yoksa test hiçbir şey yapmadan geçer.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_patron/core/tema.dart';
import 'package:bambumpos_patron/ortak/ortak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _yaz(String yol, int px, {bool zemin = true, bool koseli = true, double olcek = 1, Color? dolgu}) async {
  final kayit = ui.PictureRecorder();
  final c = Canvas(kayit);
  final s = px.toDouble();
  if (dolgu != null) c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = dolgu);
  c.save();
  c.translate(s * (1 - olcek) / 2, s * (1 - olcek) / 2);
  PatronMarkCizer(zeminVar: zemin, koseli: koseli).paint(c, Size.square(s * olcek));
  c.restore();
  final img = await kayit.endRecording().toImage(px, px);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(yol)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

/// Tam kare (köşesiz) zeminli işaret: iOS ve maskeli web simgesi. Zemin
/// kenara kadar uzansın diye işaret kendi zemini olmadan ortalanır.
Future<void> _yazTamKare(String yol, int px, {double icOlcek = 1}) async {
  final kayit = ui.PictureRecorder();
  final c = Canvas(kayit);
  final s = px.toDouble();
  c.save();
  c.scale(s / 64);
  // zemin (köşesiz)
  PatronMarkCizer.ciz(c, koseli: false, kare: 0, rozet: 0, cubuk: 0);
  c.restore();
  c.save();
  c.translate(s * (1 - icOlcek) / 2, s * (1 - icOlcek) / 2);
  c.scale(s * icOlcek / 64);
  c.saveLayer(const Rect.fromLTWH(0, 0, 64, 64), Paint());
  PatronMarkCizer.ciz(c, zeminVar: false);
  c.restore();
  c.restore();
  // Ön plan "göz"ü delik bıraktı; altındaki zemin görünür → göze mor dolgu
  c.save();
  c.translate(s * (1 - icOlcek) / 2, s * (1 - icOlcek) / 2);
  c.scale(s * icOlcek / 64);
  c.translate(32, 32.5);
  c.scale(.86);
  c.translate(-33.4, -30.2);
  c.translate(32, 36);
  final badem = Path()
    ..moveTo(-6.5, 0)
    ..quadraticBezierTo(0, -6.2, 6.5, 0)
    ..quadraticBezierTo(0, 6.2, -6.5, 0)
    ..close();
  c.drawPath(badem, Paint()..color = Marka.mor);
  c.drawCircle(Offset.zero, 2.4, Paint()..color = Marka.gok);
  c.restore();
  final img = await kayit.endRecording().toImage(px, px);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  File(yol)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  final iste = Platform.environment['SIMGE_URET'] == '1';
  testWidgets('simgeleri üret', (t) async {
    if (!iste) return;
    await t.runAsync(() async {
      const res = 'android/app/src/main/res';
      // Android eski (köşeli kare) simge
      for (final (d, px) in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]) {
        await _yaz('$res/mipmap-$d/ic_launcher.png', px);
        // Uyarlanabilir ön plan (108 dp; xml %16 içe alır) — şeffaf, yalnız beyaz şekiller
        await _yaz('$res/drawable-$d/ic_launcher_foreground.png', px * 108 ~/ 48, zemin: false);
        // Açılış (launch_background) ortası: 96 dp işaret
        await _yaz('$res/drawable-$d/launch_logo.png', px * 2);
      }
      // iOS AppIcon: köşesiz tam kare (köşeyi sistem keser), alfa sonra kaldırılır
      final ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final cj = jsonDecode(File('$ios/Contents.json').readAsStringSync()) as Map;
      for (final g in (cj['images'] as List).cast<Map>()) {
        final boy = double.parse((g['size'] as String).split('x').first);
        final olc = int.parse((g['scale'] as String).replaceAll('x', ''));
        await _yazTamKare('$ios/${g['filename']}', (boy * olc).round());
      }
      // iOS açılış görseli (96 pt)
      for (final (ad, px) in [('LaunchImage.png', 96), ('LaunchImage@2x.png', 192), ('LaunchImage@3x.png', 288)]) {
        await _yaz('ios/Runner/Assets.xcassets/LaunchImage.imageset/$ad', px);
      }
      // Web
      await _yaz('web/icons/Icon-192.png', 192);
      await _yaz('web/icons/Icon-512.png', 512);
      await _yazTamKare('web/icons/Icon-maskable-192.png', 192, icOlcek: .8);
      await _yazTamKare('web/icons/Icon-maskable-512.png', 512, icOlcek: .8);
      await _yaz('web/favicon.png', 32);
      // Kaynaklar (flutter_launcher_icons yapılandırması bunları gösterir)
      await _yazTamKare('assets/simge/simge.png', 1024);
      await _yaz('assets/simge/on_plan.png', 1024, zemin: false);
      await _yaz('assets/simge/logo.png', 1024);
      final kopya = Platform.environment['LOGO_KOPYA'];
      if (kopya != null) await _yaz(kopya, 1024);
    });
  });
}
