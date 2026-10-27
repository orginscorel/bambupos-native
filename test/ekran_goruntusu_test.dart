// Ekran görüntüsü üretici (CI'da çalışmaz): sahte ama gerçekçi yanıtlarla
// ekranları telefon/tablet boyutunda çizip PNG yazar.
//   GORUNTU_DIZINI=/yol [KOYU=1] flutter test test/ekran_goruntusu_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bambumpos_personel/core/api.dart';
import 'package:bambumpos_personel/core/durum.dart';
import 'package:bambumpos_personel/core/guncelleme.dart';
import 'package:bambumpos_personel/core/hatirlatma.dart';
import 'package:bambumpos_personel/core/konum.dart';
import 'package:bambumpos_personel/core/tema.dart';
import 'package:bambumpos_personel/ekranlar/ana_sayfa.dart';
import 'package:bambumpos_personel/ekranlar/bildirimler.dart';
import 'package:bambumpos_personel/ekranlar/davet.dart';
import 'package:bambumpos_personel/ekranlar/destek.dart';
import 'package:bambumpos_personel/ekranlar/ekibim.dart';
import 'package:bambumpos_personel/ekranlar/eslesme.dart';
import 'package:bambumpos_personel/ekranlar/gorevler.dart';
import 'package:bambumpos_personel/ekranlar/hedefler.dart';
import 'package:bambumpos_personel/ekranlar/kabuk.dart';
import 'package:bambumpos_personel/ekranlar/konum_kapisi.dart';
import 'package:bambumpos_personel/ekranlar/mesaim.dart';
import 'package:bambumpos_personel/ekranlar/primler.dart';
import 'package:bambumpos_personel/ekranlar/profil.dart';
import 'package:bambumpos_personel/ekranlar/puantaj.dart';
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
        'id': 57, 'ad': 'Muhammet Ali Yeni', 'pin_var': true, 'izinler': ['tasks.view', 'staff.view', 'staff.manage', 'tasks.assign'], 'eklentiler': {'commission': true, 'shifts': true},
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
          {'id': 2, 'title': 'Kasa raporunu kontrol et', 'description': null, 'priority': 'normal', 'status': 'in_progress', 'due_at': _iso(const Duration(hours: 5)), 'created_by': {'id': 2, 'name': 'Mehmet Buğra Usal'}, 'herkese_acik': false, 'created_at': _iso(const Duration(hours: -5)), 'completed_at': null,
            'fotolar': [{'ad': 'a.jpg', 'url': '/api/v1/portal/tasks/2/foto/a.jpg'}, {'ad': 'b.jpg', 'url': '/api/v1/portal/tasks/2/foto/b.jpg'}]},
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
    case '/api/v1/portal/puantaj':
      final gecmisAy = sorgu.contains('ay=2026-09');
      return {
        'ay': gecmisAy ? '2026-09' : '2026-10', 'ay_adi': gecmisAy ? 'Eylül 2026' : 'Ekim 2026', 'onceki_ay': gecmisAy ? '2026-08' : '2026-09', 'sonraki_ay': gecmisAy ? '2026-10' : null,
        'gunler': [
          for (var i = 0; i < 8; i++)
            {
              'tarih': _gun(-i), 'giris': _iso(Duration(days: -i, hours: -4, minutes: i == 2 ? -0 : -12)), 'cikis': i == 0 ? null : _iso(Duration(days: -i, hours: 4)),
              'calisilan_dk': i == 0 ? 228 : [480, 452, 515, 470, 480, 390, 505][i - 1], 'planlanan_dk': 480,
              'fazla_mesai_dk': i == 3 ? 35 : i == 7 ? 25 : 0, 'gec_dk': i == 2 ? 14 : i == 6 ? 6 : 0, 'eksik_dk': i == 2 ? 28 : i == 6 ? 90 : 0,
              'mola_dk': 25 + i * 2, 'acik': i == 0,
            },
        ],
        'izinler': [{'tur': 'Yıllık izin', 'bas': _gun(-14), 'bit': _gun(-12), 'gun': 3}],
        'toplam': {'gun': 19, 'calisilan_dk': 8790, 'planlanan_dk': 9120, 'fazla_mesai_dk': 160, 'gec_gun': 2, 'gec_dk': 20, 'eksik_dk': 490, 'mola_dk': 540, 'izin_gun': 3},
        'kazanc': {'tur': 'monthly', 'ucret_minor': 2800000, 'maas_minor': 2698000, 'prim_minor': 368900, 'toplam_minor': 3066900, 'tahmini': true},
      };
    case '/api/v1/portal/yonetici/ekip':
      Map<String, dynamic> k(int id, String ad, String poz, String durum, {int? giris, int dk = 0, int gec = 0, bool cikti = false, bool vardiya = true}) => {
            'id': id, 'ad': ad, 'pozisyon': poz, 'durum': durum,
            'giris': giris == null ? null : _iso(Duration(minutes: -giris)), 'cikis': cikti ? _iso(const Duration(minutes: -20)) : null,
            'calisilan_dk': dk, 'gec_dk': gec,
            'vardiya': vardiya ? {'bas': _simdi.copyWith(hour: 9, minute: 0).toUtc().toIso8601String(), 'bit': _simdi.copyWith(hour: 17, minute: 0).toUtc().toIso8601String()} : null,
          };
      return {
        'ozet': {'toplam': 8, 'mesaide': 4, 'molada': 1, 'cikti': 1, 'gelmedi': 1, 'izinli': 1, 'gec': 2},
        'kisiler': [
          k(11, 'Ayşe Kaya', 'Kasiyer', 'mesaide', giris: 252, dk: 228),
          k(12, 'Burak Demir', 'Garson', 'mesaide', giris: 230, dk: 205, gec: 14),
          k(13, 'Cansu Yıldız', 'Barista', 'molada', giris: 300, dk: 262),
          k(14, 'Deniz Aksoy', 'Aşçı', 'mesaide', giris: 180, dk: 171, gec: 6),
          k(15, 'Elif Şahin', 'Garson', 'mesaide', giris: 120, dk: 118),
          k(16, 'Furkan Çelik', 'Komi', 'cikti', giris: 520, dk: 478, cikti: true),
          k(17, 'Gizem Arslan', 'Garson', 'gelmedi'),
          k(18, 'Hakan Öztürk', 'Kasiyer', 'izinli', vardiya: false),
        ],
        'gorevler': {'acik': 3, 'devam': 2, 'bugun_biten': 4},
      };
    case '/api/v1/portal/yonetici/gorevler':
      return {
        'gorevler': [
          {'id': 21, 'title': 'Teras masalarını hazırla', 'description': 'Akşam rezervasyonları için 6 masa.', 'priority': 'high', 'status': 'in_progress', 'due_at': _iso(const Duration(hours: 2)), 'assigned_to': {'id': 12, 'name': 'Burak Demir', 'position': 'Garson'}, 'created_by': {'id': 2, 'name': 'Mehmet Buğra Usal'}, 'herkese_acik': false, 'completed_at': null,
            'fotolar': [{'ad': 'a.jpg', 'url': '/api/v1/portal/tasks/21/foto/a.jpg'}]},
          {'id': 22, 'title': 'Peçete ve pipet stoğu', 'description': null, 'priority': 'low', 'status': 'open', 'due_at': null, 'assigned_to': null, 'created_by': null, 'herkese_acik': true, 'completed_at': null},
          {'id': 23, 'title': 'Kasa raporunu kontrol et', 'description': null, 'priority': 'normal', 'status': 'open', 'due_at': _iso(const Duration(hours: 5)), 'assigned_to': {'id': 11, 'name': 'Ayşe Kaya', 'position': 'Kasiyer'}, 'created_by': null, 'herkese_acik': false, 'completed_at': null},
          {'id': 24, 'title': 'Menü panosunu sil', 'description': null, 'priority': 'normal', 'status': 'done', 'due_at': null, 'assigned_to': {'id': 15, 'name': 'Elif Şahin', 'position': 'Garson'}, 'created_by': null, 'herkese_acik': false, 'completed_at': _iso(const Duration(hours: -2)),
            'fotolar': [{'ad': 'a.jpg', 'url': '/api/v1/portal/tasks/24/foto/a.jpg'}, {'ad': 'b.jpg', 'url': '/api/v1/portal/tasks/24/foto/b.jpg'}, {'ad': 'c.jpg', 'url': '/api/v1/portal/tasks/24/foto/c.jpg'}]},
        ],
      };
    case '/api/v1/portal/shift/ekip':
      final t = RegExp(r'tarih=([0-9-]+)').firstMatch(sorgu)?.group(1) ?? _gun(0);
      final bos = Platform.environment['EKIP_BOS'] == '1' || t == _gun(3);
      const adlar = ['Ayşe Kaya', 'Burak Demir', 'Cansu Yıldız', 'Deniz Aksoy', 'Elif Şahin'];
      return {
        'tarih': t, 'gun_adi': t == _gun(0) ? 'Bugün' : t,
        'ben': {'bas': '09:00', 'bit': '17:00', 'pozisyon': 'Kasa'},
        'ekip': bos
            ? []
            : [
                {'id': 11, 'ad': adlar[0], 'pozisyon': 'Kasiyer', 'bas': '08:00', 'bit': '16:00', 'durum': 'mesaide', 'ortak_dk': 420},
                {'id': 12, 'ad': adlar[1], 'pozisyon': 'Garson', 'bas': '12:00', 'bit': '22:00', 'durum': 'molada', 'ortak_dk': 300},
                {'id': 13, 'ad': adlar[2], 'pozisyon': 'Barista', 'bas': '09:00', 'bit': '17:00', 'durum': 'mesaide', 'ortak_dk': 480},
                {'id': 14, 'ad': adlar[3], 'pozisyon': 'Aşçı', 'bas': '16:00', 'bit': '00:00', 'durum': 'bekliyor', 'ortak_dk': 60},
                {'id': 15, 'ad': adlar[4], 'pozisyon': 'Komi', 'bas': '07:00', 'bit': '11:00', 'durum': 'cikti', 'ortak_dk': 120},
              ],
        'gunler': [
          for (var i = 0; i < 7; i++)
            {'tarih': _gun(i), 'etiket': i == 0 ? 'Bugün' : i == 1 ? 'Yarın' : '${['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'][_simdi.add(Duration(days: i)).weekday - 1]} ${_simdi.add(Duration(days: i)).day}', 'sayi': i == 3 ? 0 : [5, 4, 6, 0, 3, 7, 2][i]},
        ],
      };
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
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    // Görev fotoğrafları: oturumlu görsel → örnek PNG baytları
    if (o.uri.path.contains('/foto/')) {
      return ResponseBody.fromBytes(File('assets/simge/simge.png').readAsBytesSync(), 200, headers: {Headers.contentTypeHeader: ['image/png']});
    }
    if (Platform.environment['YOK404'] == '1' && (o.uri.path.contains('/puantaj') || o.uri.path.contains('/yonetici/') || o.uri.path.contains('/shift/'))) {
      return ResponseBody.fromString('{"message":""}', 404, headers: {Headers.contentTypeHeader: ['application/json']});
    }
    return ResponseBody.fromString(jsonEncode(_yanit(o.uri.path, o.uri.query)), 200, headers: {
        Headers.contentTypeHeader: ['application/json'],
      });
  }

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
    MesaiHatirlatma.androidZorla = null;
    KonumKapisi.etkin.value = false;
    KonumIzleyici.denetci = () async => KonumDurum.tamam;
    KonumIzleyici.durum.value = null;
    KonumIzleyici.canli.value = null;
    PackageInfo.setMockInitialValues(appName: 'BamBumPOS Personel', packageName: 'com.bambumpos.personel', version: '1.0.0', buildNumber: '1', buildSignature: '', installerStore: null);
    Uyg.tercih = await SharedPreferences.getInstance();
    Uyg.api = Api.bellekte(_SahteSunucu(), tabanUrl: 'https://personel.bambumpos.com');
    Uyg.hesap.value = Map<String, dynamic>.from(_yanit('/api/v1/portal/hesap', ''));
    final gecici = Directory.systemTemp.createTempSync('bbp').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => gecici);
  });

  // UZUN=1 → sayfanın tamamı (kaydırmadan) tek görüntüde
  final boyutlar = Platform.environment['UZUN'] == '1'
      ? {'uzun': const Size(400, 1900)}
      : {'telefon': const Size(400, 860), 'tablet': const Size(820, 1180)};
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
    '10-bildirimler': () {
      MesaiHatirlatma.androidZorla = true; // Android'deki hatırlatma anahtarı görünsün
      return const BildirimlerEkrani();
    },
    '11-destek': () => const DestekEkrani(),
    '12-puantaj': () => const PuantajEkrani(),
    '13-ekibim': () => const EkibimEkrani(),
    '14-ekibim-gorevler': () => const EkibimEkrani(ilkSekme: 1),
    '16-konum-panosu': () => const _PanoGosterici(_PanoTur.konum),
    '17-uzak-panosu': () => const _PanoGosterici(_PanoTur.uzak),
    '18-dugmeler': () => const _DugmeVitrini(),
  };
  // ALT MENÜ (kabuk) — sayfa + menü birlikte; iPhone ana ekran çizgisi payı (34) ile.
  Widget menulu(Widget sayfa, int sekme) => Scaffold(
        extendBody: true,
        body: sayfa,
        bottomNavigationBar: PaAltCubuk(secili: sekme, onSec: (_) {}, onQr: () {}),
      );
  ekranlar['00-menu-ana'] = () => menulu(const AnaSayfa(), 0);
  ekranlar['00-menu-gorevler'] = () => menulu(const GorevlerEkrani(), 1);
  ekranlar['00-menu-profil'] = () => menulu(const ProfilEkrani(), 3);
  // Güncelleme kartı: alt menünün üstünde
  ekranlar['00-menu-guncelleme'] = () {
    Guncelleme.bulunan.value = const GuncellemeBilgi('1.0.6', 'https://x', 'Uygulama içi güncelleme yenilendi: alt menünün üstünde kart çıkar.');
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        const AnaSayfa(),
        Positioned(left: 12, right: 12, bottom: PaAltCubuk.yukseklik + 34 + 14, child: const GuncellemeKarti()),
      ]),
      bottomNavigationBar: PaAltCubuk(secili: 0, onSec: (_) {}, onQr: () {}),
    );
  };
  // KONUM KAPISI: konsolda konum kuralı açık, izin yok → tüm sayfaların üstünde.
  Widget kapili(KonumDurum d) {
    Uyg.hesap.value = {...?Uyg.hesap.value, 'mesai_konum': {'zorunlu': true, 'yaricap_m': 150}};
    KonumKapisi.denetci = () async => d;
    KonumKapisi.etkin.value = true;
    return Stack(fit: StackFit.expand, children: [menulu(const AnaSayfa(), 0), const KonumKapisi()]);
  }
  ekranlar['19-konum-zorunlu'] = () => kapili(KonumDurum.izinYok);
  ekranlar['19-konum-zorunlu-ayar'] = () => kapili(KonumDurum.kaliciRed);
  ekranlar['19-konum-zorunlu-servis'] = () => kapili(KonumDurum.servisKapali);
  // KONUM DURUMU (görünür): ana sayfa satırı + Profil satırı her durumda.
  Widget durumlu(KonumDurum d, Widget ekran, {bool kural = true}) {
    if (kural) Uyg.hesap.value = {...?Uyg.hesap.value, 'mesai_konum': {'zorunlu': true, 'yaricap_m': 150}};
    KonumIzleyici.denetci = () async => d;
    return ekran;
  }
  for (final d in {'tamam': KonumDurum.tamam, 'izinyok': KonumDurum.izinYok, 'servis': KonumDurum.servisKapali, 'kalici': KonumDurum.kaliciRed}.entries) {
    ekranlar['20-konum-ana-${d.key}'] = () => durumlu(d.value, const AnaSayfa());
    ekranlar['21-konum-profil-${d.key}'] = () => durumlu(d.value, const ProfilEkrani());
  }
  ekranlar['20-konum-ana-kuralsiz'] = () => durumlu(KonumDurum.tamam, const AnaSayfa(), kural: false);
  // CANLI KONUM ŞERİDİ (kabuğun üstünde, tüm sekmeler): dışarıda / içeride / içeride-küçülmüş.
  Widget seritli(double mesafe, Widget sayfa, int sekme) {
    Uyg.hesap.value = {...?Uyg.hesap.value, 'mesai_konum': {'zorunlu': true, 'yaricap_m': 150, 'lat': 40.6680979, 'lng': 36.5677891}};
    KonumIzleyici.denetci = () async => KonumDurum.tamam;
    KonumIzleyici.durum.value = KonumDurum.tamam;
    KonumIzleyici.canli.value = KonumCanli.hesapla(mesafe: mesafe, dogruluk: 12, yaricap: 150);
    return Scaffold(
      extendBody: true,
      body: KonumSeridiKatmani(child: sayfa),
      bottomNavigationBar: PaAltCubuk(secili: sekme, onSec: (_) {}, onQr: () {}),
    );
  }
  ekranlar['23-serit-disarida'] = () => seritli(320, const AnaSayfa(), 0);
  ekranlar['23-serit-disarida-gorevler'] = () => seritli(1840, const GorevlerEkrani(), 1);
  ekranlar['23-serit-icerde'] = () => seritli(40, const AnaSayfa(), 0);
  ekranlar['23-serit-icerde-kucuk'] = () => seritli(40, const AnaSayfa(), 0);
  ekranlar['24-qr-uyari'] = () {
    KonumIzleyici.canli.value = KonumCanli.hesapla(mesafe: 320, dogruluk: 12, yaricap: 150);
    return const Material(
      color: Color(0xFF222222),
      child: Stack(children: [Positioned(left: 16, right: 16, top: 110, child: KonumQrUyarisi())]),
    );
  };
  // QR kapısı: izin yokken okutucu yerine izin panosu (kural kapalı → "Şimdilik geç").
  ekranlar['22-qr-kapisi'] = () => durumlu(KonumDurum.izinYok, const _PanoGosterici(_PanoTur.qrKapisi), kural: false);
  ekranlar['22-qr-kapisi-zorunlu'] = () => durumlu(KonumDurum.izinYok, const _PanoGosterici(_PanoTur.qrKapisi));
  ekranlar['22-qr-kapisi-servis'] = () => durumlu(KonumDurum.servisKapali, const _PanoGosterici(_PanoTur.qrKapisi));
  final secilen = Platform.environment['EKRAN'];

  for (final b in boyutlar.entries) {
    for (final e in ekranlar.entries) {
      if (secilen != null && !e.key.contains(secilen)) continue;
      testWidgets('${e.key} ${b.key}', (t) async {
        t.view.physicalSize = b.value;
        t.view.devicePixelRatio = 1;
        if (e.key.startsWith('00-menu')) {
          t.view.padding = const FakeViewPadding(bottom: 34);
          t.view.viewPadding = const FakeViewPadding(bottom: 34);
        }
        if (e.key.startsWith('19-konum') || e.key.startsWith('23-serit') || e.key.startsWith('24-')) {
          t.view.padding = const FakeViewPadding(top: 44, bottom: 34);
          t.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
        }
        addTearDown(t.view.reset);
        await t.pumpWidget(_uygulama(e.value()));
        await _bekle(t);
        if (e.key.endsWith('-kucuk')) await _bekle(t, 60); // 4 sn sonra küçülür
        // Konum satırı sayfanın aşağısında: oraya kaydır.
        if (e.key.startsWith('20-konum-ana') || e.key.startsWith('21-konum-profil')) {
          final kaydirilan = find.byType(Scrollable).first;
          await t.drag(kaydirilan, Offset(0, e.key.startsWith('20') ? -560 : -700));
          await _bekle(t, 12);
        }
        await _yaz(t, '${e.key}-${b.key}');
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 5));
      }, skip: _dizin == null);
    }
  }
}

enum _PanoTur { konum, uzak, qrKapisi }

/// Konum panolarını ekran görüntüsü için açar.
class _PanoGosterici extends StatefulWidget {
  const _PanoGosterici(this.tur);
  final _PanoTur tur;
  @override
  State<_PanoGosterici> createState() => _PanoGostericiState();
}

class _PanoGostericiState extends State<_PanoGosterici> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.tur == _PanoTur.qrKapisi) {
        qrOncesiKonum(context);
      } else if (widget.tur == _PanoTur.konum) {
        konumPanosu(context, KonumDurum.izinYok, sunucuMesaji: 'Bu işletmede mesai QR\'ı için konum doğrulaması zorunlu.');
      } else {
        uzakPanosu(context, mesafe: 420, yaricap: 150);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Container(color: Colors.black87);
}

/// Ortak düğmelerin vitrini (açık/koyu karşılaştırma).
class _DugmeVitrini extends StatefulWidget {
  const _DugmeVitrini();
  @override
  State<_DugmeVitrini> createState() => _DugmeVitriniState();
}

class _DugmeVitriniState extends State<_DugmeVitrini> {
  int _s = 0;
  @override
  Widget build(BuildContext context) => PaSayfa(
        baslik: 'Düğmeler',
        geri: false,
        govde: Kaydir(altBosluk: 20, children: [
          const GradDugme(yazi: 'Mesaiye başla', ikon: Icons.play_arrow_rounded, onTap: _bos),
          const SizedBox(height: 12),
          const GradDugme(yazi: 'Kaydediliyor', yukleniyor: true, onTap: _bos),
          const SizedBox(height: 12),
          const GradDugme(yazi: 'Pasif', ikon: Icons.lock_rounded),
          const SizedBox(height: 12),
          const YumusakDugme(yazi: 'Tekrar dene', ikon: Icons.refresh_rounded, onTap: _bos),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: YumusakDugme(yazi: 'Vazgeç', onTap: _bos, zemin: context.pa.ic, renk: context.pa.metin)),
            const SizedBox(width: 10),
            const Expanded(child: YumusakDugme(yazi: 'Geri çek', ikon: Icons.undo_rounded, onTap: _bos, zemin: Marka.gul, renk: Colors.white)),
          ]),
          const SizedBox(height: 12),
          const PaMetinDugme(yazi: 'Vazgeç', onTap: _bos),
          const SizedBox(height: 8),
          const Row(children: [PaMetinDugme(yazi: 'Geçmiş', kucuk: true, sonIkon: Icons.chevron_right_rounded, onTap: _bos), SizedBox(width: 8), PaMetinDugme(yazi: 'Süzgeci kaldır', ikon: Icons.close_rounded, kucuk: true, onTap: _bos)]),
          const SizedBox(height: 16),
          PaSegment(secili: _s, ogeler: const ['Kişiler', 'Görevler', 'Arşiv'], sayilar: const [8, 3, null], onSec: (i) => setState(() => _s = i)),
          const SizedBox(height: 16),
          HataDurum(hata: ApiHata(null, 'Sunucuya ulaşılamıyor. İnternet bağlantısını kontrol edin.'), onTekrar: _bos),
        ]),
      );
}

void _bos() {}
