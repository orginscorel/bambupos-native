// Ekran görüntüleri (elle): GORUNTU_DIZINI=/tmp/x flutter test test/ekran_goruntusu_test.dart
// GORUNTU_DIZINI yoksa test hiçbir şey yapmadan geçer.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_patron/core/api.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:bambumpos_patron/core/durum.dart';
import 'package:bambumpos_patron/core/tema.dart';
import 'package:bambumpos_patron/ekranlar/acilis.dart';
import 'package:bambumpos_patron/ekranlar/eslesme.dart';
import 'package:bambumpos_patron/ekranlar/ozet.dart';
import 'package:bambumpos_patron/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ekranlar_test.dart' as ornek;
import 'sahte_api.dart';

final _dizin = Platform.environment['GORUNTU_DIZINI'];

Future<void> _cek(WidgetTester t, GlobalKey k, String ad) => t.runAsync(() async {
      final b = k.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$_dizin/$ad.png').writeAsBytesSync(png!.buffer.asUint8List());
    });

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final poppins = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
    }
    await poppins.load();
    await (FontLoader('Jakarta')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync())))).load();
  });

  Future<void> sahne(WidgetTester t, Widget ana, HttpClientAdapter s, Size boy, {Brightness? tema}) async {
    SharedPreferences.setMockInitialValues({'ad': 'Bora Gök'});
    await Uyg.kur(p: await SharedPreferences.getInstance(), hazirApi: Api.bellekte(s));
    if (tema == Brightness.dark) temaKipi.value = ThemeMode.dark;
    t.view.physicalSize = boy;
    t.view.devicePixelRatio = 1;
  }

  testWidgets('görüntüler', (t) async {
    if (_dizin == null) return;
    addTearDown(t.view.reset);
    final k = GlobalKey();
    // Açılış kareleri
    await sahne(t, const AcilisEkrani(), BekleyenSunucu(), const Size(390, 844));
    await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: AcilisEkrani())));
    var gecen = 0;
    for (final ms in [200, 500, 800, 1100, 1400, 1800]) {
      await t.pump(Duration(milliseconds: ms - gecen));
      gecen = ms;
      await _cek(t, k, 'acilis-$ms');
    }
    await t.pumpWidget(const SizedBox());
    // Eşleme
    await sahne(t, const EslesmeEkrani(), SahteSunucu({
      '/api/v1/patron-eslesme/baslat': (200, {'kod': 'K7M2Q9', 'gizli': 'g', 'bitis': DateTime.now().add(const Duration(minutes: 10)).toIso8601String()}),
      '/api/v1/patron-eslesme/durum': (200, {'durum': 'bekliyor'}),
    }), const Size(390, 1250));
    await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: EslesmeEkrani())));
    await t.pump();
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await _cek(t, k, 'eslesme');
    await t.pumpWidget(const SizedBox());
    // Özet (açık + koyu)
    for (final tm in [Brightness.light, Brightness.dark]) {
      await sahne(t, const OzetEkrani(), SahteSunucu({
        '/api/v1/boss/overview': (200, ornek.ornekOzet()),
        '/api/v1/tasks': (200, {'tasks': [{'id': 1, 'title': 'Depo sayımı', 'status': 'open', 'priority': 'high', 'due_at': DateTime.now().add(const Duration(hours: 2)).toIso8601String(), 'assigned_to': {'id': 1, 'name': 'Ali Kaya'}}], 'staff': []}),
        '/api/v1/reports/ops-delayed': (200, {'data': {'rows': [{'id': 9, 'table': 'M4', 'age_minutes': 52, 'total_minor': 40000}]}}),
      }), const Size(390, 4200), tema: tm);
      await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: OzetEkrani())));
      await t.pump();
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await _cek(t, k, 'ozet-${tm.name}');
      await t.pumpWidget(const SizedBox());
      temaKipi.value = ThemeMode.system;
    }
  });
}

