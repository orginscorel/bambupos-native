// Görev, vardiya, mesai, kabuk (alt menü + Oluştur) — SENTETİK veriyle.
import 'package:bambumpos_patron/core/api.dart';
import 'package:bambumpos_patron/core/canli.dart';
import 'package:bambumpos_patron/core/demo_veri.dart';
import 'package:bambumpos_patron/core/durum.dart';
import 'package:bambumpos_patron/ekranlar/gorevler.dart';
import 'package:bambumpos_patron/ekranlar/kabuk.dart';
import 'package:bambumpos_patron/ekranlar/mesai.dart';
import 'package:bambumpos_patron/ekranlar/raporlar.dart';
import 'package:bambumpos_patron/ekranlar/vardiya.dart';
import 'package:bambumpos_patron/main.dart';
import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sahte_api.dart';

Future<void> _kur(WidgetTester t, HttpClientAdapter a, {Size boy = const Size(390, 1400)}) async {
  SharedPreferences.setMockInitialValues({'ad': 'Deniz Akın'});
  Canli.sifirla();
  await Uyg.kur(p: await SharedPreferences.getInstance(), hazirApi: Api.bellekte(a));
  t.view.physicalSize = boy;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _bekle(WidgetTester t, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

const _personel = [
  {'id': 1, 'name': 'Ayşe Yılmaz', 'position': 'Barista'},
  {'id': 2, 'name': 'Mert Kaya', 'position': 'Garson'},
];

Map<String, dynamic> _meta({bool yonet = true}) => {
      'staff': _personel,
      'branches': [{'id': 1, 'name': 'Deneme Şube'}],
      'positions': ['Barista'],
      'default_break_min': 0,
      'can': {'view_all': true, 'manage': yonet},
    };

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('kabuk: 5 yuvalı alt menü, rozet ve Oluştur sayfası', (t) async {
    await _kur(t, DemoSunucu(gecikme: Duration.zero), boy: const Size(390, 844));
    await t.pumpWidget(const PatronUygulamasi(ana: Kabuk()));
    await _bekle(t, 20);
    for (final ad in ['Özet', 'Raporlar', 'Oluştur', 'Ekip', 'Daha fazla']) {
      expect(find.text(ad), findsWidgets);
    }
    // Demo: 2 izin + 1 değişim bekliyor → Ekip rozeti en az 3
    expect(Canli.ekipRozet.value, greaterThanOrEqualTo(3));
    expect(find.text('MARTI KAHVE · MODA (DEMO)'), findsOneWidget);
    await t.tap(find.text('Oluştur'));
    await _bekle(t, 5);
    expect(find.text('Görev oluştur'), findsOneWidget);
    expect(find.text('Vardiya planla'), findsOneWidget);
    expect(find.text('İzin / rapor gir'), findsOneWidget);
    expect(find.textContaining('onay bekliyor'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 4));
  });

  testWidgets('görev formu: kişi seçip atar, son tarih UTC gider', (t) async {
    final s = SahteSunucu({
      'GET /api/v1/tasks': (200, {'tasks': [], 'staff': _personel}),
      'POST /api/v1/tasks': (201, {'task': {'id': 9, 'title': 'Depo sayımı'}}),
    });
    await _kur(t, s);
    await t.pumpWidget(const PatronUygulamasi(ana: GorevFormu()));
    await _bekle(t);
    await t.enterText(find.byType(TextField).first, 'Depo sayımı');
    await t.tap(find.text('Mert Kaya'));
    await t.tap(find.text('Yüksek'));
    await t.pump();
    await t.tap(find.text('Görevi ata'));
    await _bekle(t);
    final g = s.govdeler['POST /api/v1/tasks'] as Map;
    expect(g['title'], 'Depo sayımı');
    expect(g['assigned_to_id'], 2);
    expect(g['priority'], 'high');
    expect((g['due_at'] as String).endsWith('Z'), isTrue, reason: 'sunucu UTC saklar');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('görev formu: 403 → kibar yetki mesajı, eylem kilitlenir', (t) async {
    final s = SahteSunucu({
      'GET /api/v1/tasks': (200, {'tasks': [], 'staff': _personel}),
      'POST /api/v1/tasks': (403, {'message': 'This action is unauthorized.'}),
    });
    await _kur(t, s);
    await t.pumpWidget(const PatronUygulamasi(ana: GorevFormu()));
    await _bekle(t);
    await t.enterText(find.byType(TextField).first, 'Kasa kontrolü');
    await t.tap(find.text('Ayşe Yılmaz'));
    await t.tap(find.text('Görevi ata'));
    await _bekle(t);
    expect(find.textContaining('Görev atama yetkiniz yok'), findsOneWidget);
    expect(Canli.gorevYetki.value, Yetki.yok);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('görevler: süzgeç ve tamamla (PUT status=done)', (t) async {
    final s = SahteSunucu({
      'GET /api/v1/tasks': (200, {
        'tasks': [
          {'id': 5, 'title': 'Teras temizliği', 'status': 'open', 'priority': 'normal', 'due_at': DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String(), 'assigned_to': _personel[0]},
          {'id': 6, 'title': 'Kasa sayımı', 'status': 'done', 'priority': 'low', 'assigned_to': _personel[1]},
        ],
        'staff': _personel,
      }),
      'PUT /api/v1/tasks/5': (200, {'task': {'id': 5, 'title': 'Teras temizliği', 'status': 'done', 'priority': 'normal', 'assigned_to': _personel[0]}}),
    });
    await _kur(t, s);
    await t.pumpWidget(const PatronUygulamasi(ana: GorevlerEkrani()));
    await _bekle(t);
    expect(find.text('Teras temizliği'), findsOneWidget);
    expect(find.text('Kasa sayımı'), findsNothing); // açık süzgeci
    expect(find.textContaining('Gecikti'), findsWidgets);
    await t.tap(find.byTooltip('Tamamlandı işaretle'));
    await _bekle(t);
    expect((s.govdeler['PUT /api/v1/tasks/5'] as Map)['status'], 'done');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('vardiya: şablonla planlar, UTC gönderir, bildirim notu görünür', (t) async {
    final s = SahteSunucu({
      '/api/v1/shifts/meta': (200, _meta()),
      '/api/v1/shifts/schedule': (200, {'shifts': [], 'leaves': [], 'warnings': []}),
      'POST /api/v1/shifts/shifts': (201, {'shifts': [], 'skipped': []}),
    });
    await _kur(t, s, boy: const Size(390, 1600));
    await t.pumpWidget(const PatronUygulamasi(ana: VardiyaEkrani()));
    await _bekle(t);
    expect(find.textContaining('sesli bildirimle gider'), findsOneWidget);
    await t.tap(find.text('Vardiya ekle').last);
    await _bekle(t, 5);
    await t.tap(find.text('Mert').last);
    await t.tap(find.text('Sabah'));
    await t.pump();
    await t.tap(find.text('Planla ve bildir'));
    await _bekle(t);
    final g = s.govdeler['POST /api/v1/shifts/shifts'] as Map;
    expect(g['user_id'], 2);
    final bas = DateTime.parse(g['starts_at'] as String);
    expect((g['starts_at'] as String).endsWith('Z'), isTrue);
    expect(bas.toLocal().hour, 8);
    expect(DateTime.parse(g['ends_at'] as String).difference(bas).inHours, 8);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('vardiya: yetki yoksa ekleme gizli', (t) async {
    final s = SahteSunucu({
      '/api/v1/shifts/meta': (200, _meta(yonet: false)),
      '/api/v1/shifts/schedule': (200, {'shifts': [], 'leaves': [], 'warnings': []}),
    });
    await _kur(t, s);
    await t.pumpWidget(const PatronUygulamasi(ana: VardiyaEkrani()));
    await _bekle(t);
    expect(find.text('Vardiya ekle'), findsNothing);
    expect(find.textContaining('"Personel yönet" yetkisi gerekir'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('mesai: bekleyen izni onaylar', (t) async {
    final s = SahteSunucu({
      'GET /api/v1/shifts/leave-requests': (200, {
        'data': [
          {'id': 3, 'user': _personel[0], 'type': 'annual', 'starts_on': '2026-11-02', 'ends_on': '2026-11-03', 'reason': 'Tatil', 'status': 'pending'},
        ],
        'total': 1,
      }),
      'GET /api/v1/shifts/swap-requests': (200, {'data': [], 'total': 0}),
      'POST /api/v1/shifts/leave-requests/3/approve': (200, {'leave': {}}),
    });
    await _kur(t, s);
    await t.pumpWidget(const PatronUygulamasi(ana: MesaiEkrani(sekme: 1)));
    await _bekle(t);
    expect(find.text('Yıllık izin'), findsOneWidget);
    await t.tap(find.text('Onayla'));
    await _bekle(t);
    expect(s.istekler, contains('POST /api/v1/shifts/leave-requests/3/approve'));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('mesai: gün tablosu durumları', (t) async {
    await _kur(t, DemoSunucu(gecikme: Duration.zero));
    await t.pumpWidget(const PatronUygulamasi(ana: MesaiEkrani()));
    await _bekle(t);
    expect(find.text('Çalışıyor'), findsWidgets);
    expect(find.text('Geç kalan'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('raporlar: web düzeni — girişte Özet, Rapor ▾ ile aynı yerde rapor', (t) async {
    await _kur(t, DemoSunucu(gecikme: Duration.zero), boy: const Size(390, 2200));
    await t.pumpWidget(const PatronUygulamasi(ana: RaporlarEkrani()));
    await _bekle(t);
    for (final k in ['Açık Masa Tutarı', 'Toplam Ürün Adedi', 'İptal - İade Tutarı', 'Ödeme Tutarı', 'Borca Yazılan']) {
      expect(find.text(k), findsOneWidget);
    }
    expect(find.text('Kategori'), findsOneWidget);
    expect(find.text('Ödeme Tipi'), findsOneWidget);
    expect(find.text('Borca Yazdıranlar'), findsOneWidget);
    expect(find.text('Sıcak kahveler'), findsOneWidget);
    // Özet'te grafik yok (web referansı)
    expect(find.byType(CustomPaint).evaluate().where((e) => e.widget.runtimeType.toString() == 'SutunGrafik'), isEmpty);
    await t.tap(find.byKey(const Key('rapor-kutusu')));
    await _bekle(t, 5);
    await t.tap(find.text('Günlük satış'));
    await _bekle(t);
    expect(find.text('Açık Masa Tutarı'), findsNothing);
    expect(find.textContaining('Günlük satış'), findsWidgets);
    // Dönem: Özel aralık → tarih kutuları + Filtrele
    await t.tap(find.byKey(const Key('donem-kutusu')));
    await _bekle(t, 5);
    await t.tap(find.text('Özel aralık'));
    await _bekle(t, 5);
    expect(find.text('Filtrele'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('utcIso yerel saati UTC yazar', () {
    final d = DateTime(2026, 10, 27, 9);
    expect(utcIso(d), d.toUtc().toIso8601String());
    expect(utcIso(d).endsWith('Z'), isTrue);
  });
}
