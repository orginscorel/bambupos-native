// Ekran görüntüleri (elle): GORUNTU_DIZINI=/tmp/x flutter test test/ekran_goruntusu_test.dart
// GORUNTU_DIZINI yoksa test hiçbir şey yapmadan geçer. Veri: SENTETİK demo
// sunucusu (lib/core/demo_veri.dart) — gerçek işletme verisi yok.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_patron/core/api.dart';
import 'package:bambumpos_patron/core/canli.dart';
import 'package:bambumpos_patron/core/demo_veri.dart';
import 'package:bambumpos_patron/core/durum.dart';
import 'package:bambumpos_patron/core/tema.dart';
import 'package:bambumpos_patron/ekranlar/acilis.dart';
import 'package:bambumpos_patron/ekranlar/eslesme.dart';
import 'package:bambumpos_patron/ekranlar/gorevler.dart';
import 'package:bambumpos_patron/ekranlar/kabuk.dart';
import 'package:bambumpos_patron/ekranlar/mesai.dart';
import 'package:bambumpos_patron/ekranlar/raporlar.dart';
import 'package:bambumpos_patron/ekranlar/vardiya.dart';
import 'package:bambumpos_patron/main.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final simge = File('/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (simge.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(simge.readAsBytesSync())))).load();
    }
  });

  Future<void> sahne(WidgetTester t, HttpClientAdapter s, Size boy, {Brightness? tema}) async {
    SharedPreferences.setMockInitialValues({'ad': demoPatronAdi});
    Canli.sifirla();
    await Uyg.kur(p: await SharedPreferences.getInstance(), hazirApi: Api.bellekte(s));
    temaKipi.value = tema == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    t.view.physicalSize = boy;
    t.view.devicePixelRatio = 1;
    // Telefon çentiği / durum çubuğu payı
    t.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  }

  Future<void> bekle(WidgetTester t, [int adim = 30]) async {
    await t.pump();
    for (var i = 0; i < adim; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('görüntüler', (t) async {
    if (_dizin == null) return;
    addTearDown(t.view.reset);
    final k = GlobalKey();
    const telefon = Size(390, 844);

    // Açılış + eşleme (değişmedi; kıyas için)
    await sahne(t, BekleyenSunucu(), telefon);
    await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: AcilisEkrani())));
    await t.pump(const Duration(milliseconds: 120));
    await _cek(t, k, 'acilis-0');
    await t.pump(const Duration(milliseconds: 500));
    await _cek(t, k, 'acilis-1');
    await t.pump(const Duration(milliseconds: 900));
    await _cek(t, k, 'acilis');
    await t.pumpWidget(const SizedBox());
    await sahne(t, SahteSunucu({
      '/api/v1/patron-eslesme/baslat': (200, {'kod': 'K7M2Q9', 'gizli': 'g', 'bitis': DateTime.now().add(const Duration(minutes: 10)).toIso8601String()}),
      '/api/v1/patron-eslesme/durum': (200, {'durum': 'bekliyor'}),
    }), telefon);
    await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: EslesmeEkrani())));
    await bekle(t, 20);
    await _cek(t, k, 'eslesme');
    await t.pumpWidget(const SizedBox());

    for (final tm in [Brightness.light, Brightness.dark]) {
      final ad = tm.name;
      // Kabuk: Özet (ilk ekran + uzun), Raporlar, Ekip, Daha fazla, Oluştur sayfası
      for (final boy in [telefon, const Size(390, 3600)]) {
        await sahne(t, DemoSunucu(gecikme: Duration.zero), boy, tema: tm);
        await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: Kabuk())));
        await bekle(t, 40);
        await _cek(t, k, boy == telefon ? 'ozet-$ad' : 'ozet-uzun-$ad');
        if (boy == telefon) {
          for (final (i, sekme) in [(1, 'raporlar'), (2, 'ekip'), (3, 'dahafazla')]) {
            Kabuk.sekme.value = i;
            await bekle(t, 20);
            await _cek(t, k, '$sekme-$ad');
          }
          Kabuk.sekme.value = 0;
          await bekle(t, 5);
          await t.tap(find.text('Oluştur'));
          await bekle(t, 10);
          await _cek(t, k, 'olustur-$ad');
        }
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 4));
      }
      // Ekip (uzun)
      await sahne(t, DemoSunucu(gecikme: Duration.zero), const Size(390, 1900), tema: tm);
      await t.pumpWidget(RepaintBoundary(key: k, child: const PatronUygulamasi(ana: Kabuk())));
      await bekle(t, 10);
      Kabuk.sekme.value = 2;
      await bekle(t, 30);
      await _cek(t, k, 'ekip-uzun-$ad');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 4));

      // İç ekranlar
      final icler = <(String, Widget, Size)>[
        ('raporlar-uzun', const RaporlarEkrani(), const Size(390, 1500)),
        ('gorevler', const GorevlerEkrani(), telefon),
        ('gorev-formu', const GorevFormu(), const Size(390, 1100)),
        ('vardiya', const VardiyaEkrani(), const Size(390, 1500)),
        ('mesai', const MesaiEkrani(), const Size(390, 1100)),
        ('talepler', const MesaiEkrani(sekme: 1), telefon),
        ('mesai-hafta', const MesaiEkrani(sekme: 2), const Size(390, 1300)),
      ];
      for (final (isim, ekran, boy) in icler) {
        await sahne(t, DemoSunucu(gecikme: Duration.zero), boy, tema: tm);
        await t.pumpWidget(RepaintBoundary(key: k, child: PatronUygulamasi(ana: ekran)));
        await bekle(t, 25);
        await _cek(t, k, '$isim-$ad');
        if (isim == 'vardiya') {
          await t.tap(find.text('Vardiya ekle').last);
          await bekle(t, 10);
          await _cek(t, k, 'vardiya-formu-$ad');
        }
        await t.pumpWidget(const SizedBox());
      }
      temaKipi.value = ThemeMode.system;
    }
  });
}
