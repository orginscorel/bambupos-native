import 'package:bambumpos_personel/core/durum.dart';
import 'package:bambumpos_personel/core/konum.dart';
import 'package:bambumpos_personel/core/tema.dart';
import 'package:bambumpos_personel/ekranlar/konum_kapisi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var durum = KonumDurum.izinYok;

  Future<void> kur(WidgetTester t, Map<String, dynamic>? mesaiKonum) async {
    Uyg.hesap.value = {'ad': 'Ayşe Kaya', 'isletme': 'Çamlık', 'mesai_konum': ?mesaiKonum};
    KonumKapisi.denetci = () async => durum;
    KonumKapisi.etkin.value = true;
    await t.pumpWidget(MaterialApp(
      theme: temaKur(Brightness.light),
      home: const Stack(children: [Scaffold(body: Text('ALT')), KonumKapisi()]),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  tearDown(() {
    KonumKapisi.etkin.value = false;
    Uyg.hesap.value = null;
  });

  testWidgets('kural yoksa (eski sunucu) kapı görünmez', (t) async {
    await kur(t, null);
    expect(find.text('Konum izni gerekli'), findsNothing);
  });

  testWidgets('kural kapalıysa kapı görünmez', (t) async {
    await kur(t, {'zorunlu': false, 'yaricap_m': 150});
    expect(find.text('Konum izni gerekli'), findsNothing);
  });

  testWidgets('kural açık + izin yok → kapı; izin gelince kapanır', (t) async {
    durum = KonumDurum.izinYok;
    await kur(t, {'zorunlu': true, 'yaricap_m': 150});
    expect(find.text('Konum izni gerekli'), findsOneWidget);
    expect(find.text('Konum iznini ver'), findsOneWidget);

    durum = KonumDurum.tamam;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Konum izni gerekli'), findsNothing);
  });

  testWidgets('kural açık + izin var → kapı yok; konsolda kural kapanınca da yok', (t) async {
    durum = KonumDurum.tamam;
    await kur(t, {'zorunlu': true});
    expect(find.text('Konum izni gerekli'), findsNothing);

    durum = KonumDurum.kaliciRed;
    Uyg.hesap.value = {...?Uyg.hesap.value}; // yeniden denetim
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Ayarlardan izin ver'), findsOneWidget);

    Uyg.hesap.value = {...?Uyg.hesap.value, 'mesai_konum': {'zorunlu': false}};
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Konum izni gerekli'), findsNothing);
  });
}
