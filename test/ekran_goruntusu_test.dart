// Ekran görüntüsü üretici (CI'da çalışmaz): sahte ama gerçekçi yanıtlarla
// ekranları telefon/tablet boyutunda çizip PNG yazar.
//   GORUNTU_DIZINI=/yol [KOYU=1] flutter test test/ekran_goruntusu_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_personel/core/api.dart';
import 'package:bambumpos_personel/core/durum.dart';
import 'package:bambumpos_personel/core/tema.dart';
import 'package:bambumpos_personel/ekranlar/ana_sayfa.dart';
import 'package:bambumpos_personel/ekranlar/bildirimler.dart';
import 'package:bambumpos_personel/ekranlar/davet.dart';
import 'package:bambumpos_personel/ekranlar/destek.dart';
import 'package:bambumpos_personel/ekranlar/eslesme.dart';
import 'package:bambumpos_personel/ekranlar/gorevler.dart';
import 'package:bambumpos_personel/ekranlar/hedefler.dart';
import 'package:bambumpos_personel/ekranlar/mesaim.dart';
import 'package:bambumpos_personel/ekranlar/primler.dart';
import 'package:bambumpos_personel/ekranlar/profil.dart';
import 'package:bambumpos_personel/ekranlar/vardiyam.dart';
import 'package:bambumpos_personel/ortak/ortak.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _dizin = Platform.environment['GORUNTU_DIZINI'];
final _simdi = DateTime.now();
String _iso(Duration d) => _simdi.add(d).toUtc().toIso8601String();
String _gun(int g) {
  final d = _simdi.add(Duration(days: g));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _yanit(String yol, String sorgu) {
  switch (yol) {
    case '/api/v1/portal/hesap':
      return {
        'id': 57, 'ad': 'Muhammet Ali Yeni', 'pin_var': true, 'izinler': ['tasks.view'], 'eklentiler': {'commission': true, 'shifts': true},
        'telefon': '5551234567', 'eposta': 'muhammet@ornek.com', 'personel_kodu': 'P-104', 'pozisyon': 'Kasiyer', 'departman': 'Salon',
        'ise_giris': '2025-04-03', 'isletme': 'Çamlık Sosyal Tesisleri', 'sube': 'Merkez Şube', 'roller': ['Kasiyer'],
      };
    case '/api/v1/portal/state':
      return {
        'status': 'working', 'on_break': false, 'break_kind': null, 'break_started_at': null,
        'entry': {'id': 1, 'clock_in_at': _iso(const Duration(hours: -4, minutes: -12)), 'worked_min': 228, 'break_total_min': 18, 'toilet_total_min': 4,
          'breaks': [
            {'kind': 'break', 'kind_label': 'Mola', 'started_at': _iso(const Duration(hours: -2)), 'ended_at': _iso(const Duration(hours: -1, minutes: -46))},
            {'kind': 'toilet', 'kind_label': 'Tuvalet', 'started_at': _iso(const Duration(minutes: -50)), 'ended_at': _iso(const Duration(minutes: -46))},
          ]},
        'today_shift': {'starts_at': _iso(const Duration(hours: -4, minutes: -20)), 'ends_at': _iso(const Duration(hours: 3, minutes: 40)), 'position': 'Kasa'},
        'break_allowance_min': 30, 'break_count': 2, 'break_used_min': 18, 'server_now': _iso(Duration.zero),
      };
    case '/api/v1/portal/tasks':
      return {
        'tasks': [
          {'id': 1, 'title': 'Teras masalarını hazırla', 'description': 'Akşam rezervasyonları için 6 masa.', 'priority': 'high', 'status': 'open', 'due_at': _iso(const Duration(hours: 2)), 'created_by': {'id': 2, 'name': 'Mehmet Buğra Usal'}, 'herkese_acik': false, 'created_at': _iso(const Duration(hours: -3)), 'completed_at': null},
          {'id': 2, 'title': 'Kasa raporunu kontrol et', 'description': null, 'priority': 'normal', 'status': 'in_progress', 'due_at': _iso(const Duration(hours: 5)), 'created_by': {'id': 2, 'name': 'Mehmet Buğra Usal'}, 'herkese_acik': false, 'created_at': _iso(const Duration(hours: -5)), 'completed_at': null},
          {'id': 3, 'title': 'Peçete ve pipet stoğu', 'description': 'Depodan bar tezgahına taşı.', 'priority': 'low', 'status': 'open', 'due_at': null, 'created_by': null, 'herkese_acik': true, 'created_at': _iso(const Duration(hours: -1)), 'completed_at': null},
          {'id': 4, 'title': 'Menü panosunu sil', 'description': null, 'priority': 'normal', 'status': 'done', 'due_at': null, 'created_by': null, 'herkese_acik': false, 'created_at': _iso(const Duration(days: -1)), 'completed_at': _iso(const Duration(hours: -20))},
        ],
        'counts': {'open': 2, 'in_progress': 1, 'done': 1},
      };
    case '/api/v1/portal/reports':
      final ay = sorgu.contains('month');
      return {
        'period': ay ? 'month' : 'day', 'role_label': 'Kasiyer', 'position': 'Kasiyer',
        'worked': {'total_min': ay ? 7420 : 228, 'planned_min': ay ? 8400 : 480, 'active_days': ay ? 19 : 1, 'avg_daily_min': 390, 'break_min': 340, 'toilet_min': 60, 'total_sessions': 20, 'multi_session_days': 1,
          'by_day': [for (var i = 6; i >= 0; i--) {'date': _gun(-i), 'worked_min': 300 + (i * 37) % 180, 'break_min': 25, 'sessions': 1}]},
        'ops': {'prepared_count': ay ? 312 : 14, 'taken_count': ay ? 862 : 41, 'served_count': ay ? 798 : 37, 'delivered_count': 0, 'avg_pickup_min': 3, 'avg_delivery_min': ay ? 6 : 5, 'avg_delay_min': null, 'delay_count': 2, 'delay_threshold_min': 15,
          'by_day': [for (var i = 6; i >= 0; i--) {'date': _gun(-i), 'prepared': 10 + i, 'taken': 30 + i * 3, 'served': 28 + i * 2}]},
        'orders': {'order_count': ay ? 640 : 31, 'avg_service_min': 7},
      };
    case '/api/v1/portal/history':
      return {
        'entries': [
          for (var i = 0; i < 7; i++)
            {'id': 100 + i, 'date': _gun(-i), 'clock_in_at': _iso(Duration(days: -i, hours: -4)), 'clock_out_at': i == 0 ? null : _iso(Duration(days: -i, hours: 3)), 'worked_min': i == 0 ? 228 : 360 + (i * 41) % 150, 'break_min': 20, 'toilet_min': 5, 'status': i == 0 ? 'open' : 'closed'},
        ],
      };
    case '/api/v1/portal/earnings':
      return {'enabled': true, 'period': 'month', 'sales_minor': 18450000, 'order_count': 640, 'commission_minor': 368900, 'target_minor': 25000000, 'target_met': false, 'worked_min': 7420, 'scheme_name': 'Kasa satış primi %2'};
    case '/api/v1/portal/hedefler':
      return {'ay': 'Ekim 2026', 'kalan_gun': 5, 'mesai': {'plan_min': 8400, 'calisilan_min': 7420}, 'devam': {'plan_gun': 20, 'plan_gun_ay': 22, 'calisilan_gun': 19}, 'gorev': {'toplam': 14, 'tamam': 11, 'geciken': 1}, 'mola': {'hak_dk': 30, 'asim_gun': 0}};
    case '/api/v1/portal/davet':
      return {
        'durum': 'active', 'kurallar': {'oran_yuzde': 15, 'ay': 12, 'cerez_gun': 60, 'min_odeme_minor': 50000}, 'kod': 'MAY7K2', 'iban_maskeli': 'TR12 •••• 4421',
        'link': 'https://bambumpos.com/?ref=MAY7K2', 'kisa_link': 'https://bambumpos.com/r/MAY7K2',
        'istatistik': {'clicks': 48, 'referrals': 3, 'active': 2, 'pending': 1, 'earned_minor': 124500, 'balance_minor': 62500, 'paid_minor': 62000, 'conversion': 6.3},
        'davetler': [
          {'ad': 'Kuzey Kahve', 'durum': 'active', 'tarih': _iso(const Duration(days: -40))},
          {'ad': 'Lale Pastanesi', 'durum': 'active', 'tarih': _iso(const Duration(days: -18))},
          {'ad': 'Mavi Balık', 'durum': 'pending', 'tarih': _iso(const Duration(days: -2))},
        ],
        'hakedisler': [
          {'tutar_minor': 22500, 'durum': 'approved', 'donem': '2026-10', 'tarih': _iso(const Duration(days: -3))},
          {'tutar_minor': 40000, 'durum': 'pending', 'donem': '2026-10', 'tarih': _iso(const Duration(days: -1))},
        ],
        'odemeler': [{'tutar_minor': 62000, 'durum': 'paid', 'tarih': _iso(const Duration(days: -12))}],
        'bekleyen_odeme': null,
      };
    case '/api/v1/portal/destek':
      return {
        'yoneticiler': [
          {'ad': 'Mehmet Buğra Usal', 'rol': 'Sahip', 'telefon': '5065411851', 'ayni_sube': true},
          {'ad': 'Tuğba Yumuşakkaya', 'rol': 'Şube Müdürü', 'telefon': null, 'ayni_sube': true},
        ],
        'eposta': 'destek@bambumpos.com',
      };
    case '/api/v1/portal/schedule':
      List<Map<String, dynamic>> v(int g, int bas, int son, String poz) => [
            {'id': g + 10, 'starts_at': _simdi.add(Duration(days: g)).copyWith(hour: bas, minute: 0).toUtc().toIso8601String(), 'ends_at': _simdi.add(Duration(days: g)).copyWith(hour: son, minute: 0).toUtc().toIso8601String(), 'position': poz, 'branch_name': 'Merkez Şube', 'note': null},
          ];
      final gunler = [(0, 9, 17, 'Kasa'), (1, 9, 17, 'Kasa'), (2, 14, 23, 'Salon'), (4, 9, 17, 'Kasa')];
      return {
        'shifts': [for (final g in gunler) ...v(g.$1, g.$2, g.$3, g.$4)],
        'grouped_by_day': [for (final g in gunler) {'date': _gun(g.$1), 'label': g.$1 == 0 ? 'Bugün' : g.$1 == 1 ? 'Yarın' : _gun(g.$1), 'items': v(g.$1, g.$2, g.$3, g.$4)}],
      };
    case '/api/v1/portal/leave-requests':
      return {
        'requests': [
          {'id': 1, 'type': 'annual', 'type_label': 'Yıllık izin', 'starts_on': _gun(9), 'ends_on': _gun(11), 'days': 3, 'reason': 'Aile ziyareti', 'status': 'pending', 'status_label': 'Bekliyor', 'created_at': _iso(const Duration(days: -1)), 'decided_at': null},
          {'id': 2, 'type': 'sick', 'type_label': 'Hastalık', 'starts_on': _gun(-20), 'ends_on': _gun(-20), 'days': 1, 'reason': 'Rapor', 'status': 'approved', 'status_label': 'Onaylandı', 'created_at': _iso(const Duration(days: -21)), 'decided_at': _iso(const Duration(days: -20))},
        ],
      };
    case '/api/v1/notifications':
      return {
        'unread_count': 2,
        'items': [
          {'id': 9, 'type': 'task_assigned', 'title': 'Yeni görev: Teras masalarını hazırla', 'body': 'Mehmet Buğra Usal sana bir görev atadı.', 'icon': 'clipboard', 'url': '/gorevlerim', 'read': false, 'created_at': _iso(const Duration(minutes: -12))},
          {'id': 8, 'type': 'shift_reminder', 'title': 'Vardiyan 30 dk sonra başlıyor', 'body': 'Bugün 14:00 – 23:00 · Salon', 'icon': 'calendar', 'url': '/takvim', 'read': false, 'created_at': _iso(const Duration(hours: -3))},
          {'id': 7, 'type': 'leave_decided', 'title': 'İzin talebin onaylandı', 'body': 'Hastalık · 1 gün', 'icon': 'check', 'url': '/takvim', 'read': true, 'created_at': _iso(const Duration(days: -1, hours: -2))},
        ],
      };
    case '/api/v1/auth/sessions':
      return {'sessions': [{'id': 'a', 'device': 'BamBumPOS Personel · iPhone', 'ip': '88.1.2.3', 'last_active_at': _iso(Duration.zero), 'is_current': true}]};
    case '/api/v1/personel-eslesme/baslat':
      return {'kod': 'K7M4QX', 'gizli': 'x', 'bitis': _iso(const Duration(minutes: 29, seconds: 41))};
    case '/api/v1/personel-eslesme/durum':
      return {'durum': 'bekliyor'};
    default:
      return {};
  }
}

class _SahteSunucu implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async =>
      ResponseBody.fromString(jsonEncode(_yanit(o.uri.path, o.uri.query)), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
  @override
  void close({bool force = false}) {}
}

Future<void> _fontlar() async {
  final poppins = FontLoader('Poppins');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    poppins.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Poppins-$w.ttf').readAsBytesSync())));
  }
  await poppins.load();
  final jakarta = FontLoader('Jakarta')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/PlusJakartaSans.ttf').readAsBytesSync())));
  await jakarta.load();
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final kok = Platform.environment['FLUTTER_FONTLARI'] ?? '$artifacts/material_fonts';
  final ikon = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(File('$kok/MaterialIcons-Regular.otf').readAsBytesSync())));
  await ikon.load();
}

final _sinir = GlobalKey();

Widget _uygulama(Widget ekran) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: temaKur(Brightness.light),
      darkTheme: temaKur(Brightness.dark),
      themeMode: Platform.environment['KOYU'] == '1' ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (_, c) => RepaintBoundary(
        key: _sinir,
        child: Overlay(initialEntries: [
          OverlayEntry(builder: (ctx) {
            bildirimKatmani(Overlay.of(ctx));
            return c!;
          }),
        ]),
      ),
      home: ekran,
    );

Future<void> _yaz(WidgetTester t, String ad) async {
  await t.runAsync(() async {
    final b = _sinir.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_dizin/$ad${Platform.environment['KOYU'] == '1' ? '-koyu' : ''}.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _bekle(WidgetTester t, [int tur = 30]) async {
  for (var i = 0; i < tur; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_dizin != null) await _fontlar();
    await initializeDateFormatting('tr_TR');
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'BamBumPOS Personel', packageName: 'com.bambumpos.personel', version: '1.0.0', buildNumber: '1', buildSignature: '', installerStore: null);
    Uyg.tercih = await SharedPreferences.getInstance();
    Uyg.api = Api.bellekte(_SahteSunucu(), tabanUrl: 'https://personel.bambumpos.com');
    Uyg.hesap.value = Map<String, dynamic>.from(_yanit('/api/v1/portal/hesap', ''));
    final gecici = Directory.systemTemp.createTempSync('bbp').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => gecici);
  });

  final boyutlar = {'telefon': const Size(400, 860), 'tablet': const Size(820, 1180)};
  final ekranlar = <String, Widget Function()>{
    '01-eslesme': () => const EslesmeEkrani(),
    '02-ana': () => const AnaSayfa(),
    '03-gorevler': () => const GorevlerEkrani(),
    '04-vardiyam': () => const VardiyamEkrani(),
    '05-profil': () => const ProfilEkrani(),
    '06-mesaim': () => const MesaimEkrani(),
    '07-hedefler': () => const HedeflerEkrani(),
    '08-primler': () => const PrimlerEkrani(),
    '09-davet': () => const DavetEkrani(),
    '10-bildirimler': () => const BildirimlerEkrani(),
    '11-destek': () => const DestekEkrani(),
  };
  final secilen = Platform.environment['EKRAN'];

  for (final b in boyutlar.entries) {
    for (final e in ekranlar.entries) {
      if (secilen != null && !e.key.contains(secilen)) continue;
      testWidgets('${e.key} ${b.key}', (t) async {
        t.view.physicalSize = b.value;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(_uygulama(e.value()));
        await _bekle(t);
        await _yaz(t, '${e.key}-${b.key}');
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      }, skip: _dizin == null);
    }
  }
}
