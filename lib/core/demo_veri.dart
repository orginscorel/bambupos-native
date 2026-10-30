import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'bicim.dart';
import 'raporlar.dart';

/// DEMO kipi: `--dart-define=DEMO=1`. Eşleme/oturum atlanır, bütün uçlar
/// bu SENTETİK veriyle yanıtlanır (gerçek kişi/işletme verisi YOK).
/// Oluştur/düzenle/sil eylemleri bellekte çalışır; uygulama kapanınca sıfırlanır.
const demoKipi = String.fromEnvironment('DEMO') == '1';

const demoPatronAdi = 'Deniz Akın';

/// Kurgusal bir kafe: "Martı Kahve · Moda (Demo)".
class DemoSunucu implements HttpClientAdapter {
  DemoSunucu({DateTime? simdi, this.gecikme = const Duration(milliseconds: 180)}) : _sabitAn = simdi {
    _kur();
  }

  final DateTime? _sabitAn;
  final Duration gecikme;
  DateTime get _an => _sabitAn ?? DateTime.now();
  final _rnd = math.Random(7);
  int _sira = 1000;

  static const personel = [
    (1, 'Ayşe Yılmaz', 'Barista'),
    (2, 'Mert Kaya', 'Garson'),
    (3, 'Elif Demir', 'Garson'),
    (4, 'Can Öztürk', 'Mutfak'),
    (5, 'Zeynep Arslan', 'Kasa'),
    (6, 'Burak Şahin', 'Garson'),
    (7, 'Selin Koç', 'Barista'),
    (8, 'Emre Aydın', 'Mutfak'),
  ];

  late List<Map<String, dynamic>> _gorevler;
  late List<Map<String, dynamic>> _vardiyalar;
  late List<Map<String, dynamic>> _izinler;
  late List<Map<String, dynamic>> _takaslar;
  late List<Map<String, dynamic>> _bildirimler;
  late List<Map<String, dynamic>> _kayitlar;

  Map<String, dynamic> _kisi(int id) {
    final p = personel.firstWhere((e) => e.$1 == id, orElse: () => personel.first);
    return {'id': p.$1, 'name': p.$2, 'position': p.$3};
  }

  DateTime get _bugun => DateTime(_an.year, _an.month, _an.day);
  String _utc(DateTime d) => d.toUtc().toIso8601String();

  void _kur() {
    final g = _bugun;
    DateTime at(int gun, int saat, [int dk = 0]) => DateTime(g.year, g.month, g.day + gun, saat, dk);
    _gorevler = [
      _gorev('Espresso makinesi kireç temizliği', 'Haftalık bakım; filtreleri de değiştir.', 1, 'high', at(0, _an.hour - 1), 'open'),
      _gorev('Teras masalarını hazırla', 'Minderler + şemsiyeler', 2, 'normal', at(0, 17), 'in_progress'),
      _gorev('Süt ve şurup sayımı', null, 7, 'normal', at(0, 20), 'open'),
      _gorev('Haftalık tedarikçi siparişi', 'Kahve çekirdeği 6 kg, yulaf sütü 2 koli', 5, 'high', at(1, 11), 'open'),
      _gorev('Vitrin tatlılarını yenile', null, 4, 'low', at(1, 9), 'open'),
      _gorev('Kasa raporunu kontrol et', null, 5, 'normal', at(-1, 23), 'done'),
      _gorev('Menü panosunu güncelle', 'Kış içecekleri eklenecek', null, 'low', null, 'open'),
      // Fotoğraflı onay (2026-10-30): personel bitirip onaya gönderdi.
      {
        ..._gorev('Bar tezgahını temizle', 'Raflar dahil', 3, 'normal', at(0, 16), 'review'),
        'onay_destekli': true,
        'onay': {'durum': 'pending', 'bekliyor': true, 'gonderim': _utc(_an.subtract(const Duration(minutes: 12))), 'not': 'Tezgah ve raflar silindi', 'inceleyen': null, 'inceleme': null, 'gerekce': null},
      },
    ];
    _vardiyalar = [];
    final hb = g.subtract(Duration(days: g.weekday - 1));
    for (var d = -1; d < 14; d++) {
      final gun = hb.add(Duration(days: d));
      for (final p in personel) {
        if ((p.$1 + d) % 7 == 0) continue; // haftalık izin günü
        final sabah = (p.$1 + d) % 2 == 0;
        final bas = DateTime(gun.year, gun.month, gun.day, sabah ? 8 : 15, p.$1 == 4 && sabah ? 30 : 0);
        _vardiyalar.add({
          'id': ++_sira,
          'branch_id': 1,
          'user_id': p.$1,
          'user': _kisi(p.$1),
          'position': p.$3,
          'starts_at': _utc(bas),
          'ends_at': _utc(bas.add(const Duration(hours: 8))),
          'break_min': 30,
          'note': p.$1 == 5 && sabah ? 'Kasa açılışı' : null,
          'repeat_group': p.$1 == 1 ? 'seri-1' : null,
        });
      }
    }
    _izinler = [
      {'id': 1, 'user': _kisi(3), 'type': 'annual', 'starts_on': Bicim.iso(at(3, 0)), 'ends_on': Bicim.iso(at(5, 0)), 'reason': 'Aile ziyareti', 'status': 'pending', 'created_at': _utc(at(0, 9, 12))},
      {'id': 2, 'user': _kisi(8), 'type': 'sick', 'starts_on': Bicim.iso(at(1, 0)), 'ends_on': Bicim.iso(at(1, 0)), 'reason': 'Doktor randevusu', 'status': 'pending', 'created_at': _utc(at(0, 10, 40))},
    ];
    final sw = _vardiyalar.firstWhere((v) => v['user_id'] == 6 && DateTime.parse(v['starts_at'] as String).isAfter(_an));
    _takaslar = [
      {'id': 1, 'shift': {...sw}, 'requested_by': _kisi(6), 'target_user': _kisi(2), 'reason': 'Sınavım var, Mert devralabilir', 'status': 'pending', 'created_at': _utc(at(0, 8, 5))},
    ];
    _bildirimler = [
      {'id': 31, 'title': 'Yeni izin talebi', 'body': 'Elif Demir · Yıllık izin · 3 gün', 'read': false, 'created_at': _utc(at(0, 9, 12))},
      {'id': 30, 'title': 'Stok kritik', 'body': 'Yulaf sütü 2 litrenin altına düştü', 'read': false, 'created_at': _utc(at(0, 8, 47))},
      {'id': 29, 'title': 'Gün sonu alındı', 'body': 'Dün ₺21.480 ciro, 168 adisyon', 'read': true, 'created_at': _utc(at(-1, 23, 58))},
    ];
    _kayitlar = [];
    for (final v in _vardiyalar) {
      final bas = DateTime.parse(v['starts_at'] as String).toLocal();
      if (!(bas.year == g.year && bas.month == g.month && bas.day == g.day) || bas.isAfter(_an)) continue;
      final id = v['user_id'] as int;
      if (id == 6) continue; // gelmedi
      final gec = id == 2 ? 14 : (id * 3) % 5;
      final giris = bas.add(Duration(minutes: gec));
      final son = DateTime.parse(v['ends_at'] as String).toLocal();
      final cikti = son.isBefore(_an);
      _kayitlar.add({
        'id': ++_sira,
        'user': _kisi(id),
        'clock_in_at': _utc(giris),
        'clock_out_at': cikti ? _utc(son.add(const Duration(minutes: 4))) : null,
        'method_in': 'qr',
        'break_total_min': cikti ? 30 : 0,
        'worked_min': (cikti ? son : _an).difference(giris).inMinutes - (cikti ? 30 : 0),
        'late_min': gec > 5 ? gec : 0,
        'overtime_min': 0,
        'status': cikti ? 'closed' : 'open',
        'approved_at': null,
        'edit_reason': null,
        '_vardiya': v,
      });
    }
  }

  Map<String, dynamic> _gorev(String b, String? a, int? kisi, String o, DateTime? son, String st) => {
        'id': ++_sira,
        'title': b,
        'description': a,
        'priority': o,
        'status': st,
        'due_at': son == null ? null : _utc(son),
        'branch_id': 1,
        'herkese_acik': kisi == null,
        'assigned_to': kisi == null ? null : _kisi(kisi),
        'created_by': {'id': 99, 'name': demoPatronAdi},
        'created_at': _utc(_an.subtract(const Duration(hours: 20))),
        'completed_at': st == 'done' ? _utc(_an.subtract(const Duration(hours: 10))) : null,
      };

  /* ───────── Satış verisi ───────── */

  /// Saat başı ciro (kuruş) — kafe eğrisi; gün tohumuyla hafif değişir.
  int _saatCiro(DateTime gun, int h) {
    const egri = [0, 0, 0, 0, 0, 0, 0, 2, 6, 9, 8, 7, 9, 11, 10, 8, 9, 11, 13, 14, 12, 9, 5, 2];
    final tohum = (gun.day * 31 + gun.month * 7 + h * 13) % 17;
    final hafta = gun.weekday >= 6 ? 1.3 : 1.0;
    return (egri[h] * 15500 * hafta * (0.85 + tohum / 50)).round();
  }

  List<Map<String, dynamic>> _saatler(DateTime gun, {int? kadar}) => [
        for (var h = 0; h < 24; h++)
          {
            'hour': h,
            'revenue_minor': kadar != null && h > kadar ? 0 : _saatCiro(gun, h),
            'orders': kadar != null && h > kadar ? 0 : (_saatCiro(gun, h) / 12800).round(),
          },
      ];

  int _gunCiro(DateTime gun, {int? kadar}) => _saatler(gun, kadar: kadar).fold(0, (a, h) => a + (h['revenue_minor'] as int));

  Map<String, dynamic> _ozet(DateTime a, DateTime b) {
    final bugunMu = b == _bugun;
    final kadar = bugunMu ? _an.hour : null;
    final gunler = <DateTime>[for (var d = a; !d.isAfter(b); d = d.add(const Duration(days: 1))) d];
    final ciro = gunler.fold<int>(0, (t, g) => t + _gunCiro(g, kadar: g == _bugun ? kadar : null));
    final uzun = gunler.length;
    final oa = a.subtract(Duration(days: uzun));
    final onceki = [for (var i = 0; i < uzun; i++) oa.add(Duration(days: i))].fold<int>(0, (t, g) => t + _gunCiro(g, kadar: bugunMu && g == oa.add(Duration(days: uzun - 1)) ? kadar : null));
    final adisyon = (ciro / 12800).round();
    final saat = <int, int>{};
    for (final g in gunler) {
      for (final h in _saatler(g, kadar: g == _bugun ? kadar : null)) {
        saat[h['hour'] as int] = (saat[h['hour'] as int] ?? 0) + (h['revenue_minor'] as int);
      }
    }
    double? yz(num x, num y) => y <= 0 ? null : double.parse(((x - y) * 100 / y).toStringAsFixed(1));
    final pk = saat.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    final mesaide = _kayitlar.where((k) => k['clock_out_at'] == null).map((k) {
      final g = DateTime.parse(k['clock_in_at'] as String).toLocal();
      return {...k['user'] as Map, 'since': k['clock_in_at'], 'worked_minutes': _an.difference(g).inMinutes};
    }).toList();
    final gelecek = _vardiyalar.where((v) {
      final s = DateTime.parse(v['starts_at'] as String).toLocal();
      return s.isAfter(_an) && s.day == _an.day;
    }).map((v) => {...v['user'] as Map, 'start': v['starts_at']}).toList();
    final nakit = (ciro * .34).round(), kart = (ciro * .58).round(), yemek = ciro - nakit - kart;
    return {
      'range': {'from': Bicim.iso(a), 'to': Bicim.iso(b), 'branch_id': 1, 'timezone': 'Europe/Istanbul'},
      'sales': {
        'revenue_minor': ciro,
        'orders': adisyon,
        'avg_basket_minor': adisyon == 0 ? 0 : (ciro / adisyon).round(),
        'cancelled_orders': uzun > 1 ? uzun * 2 : 1,
        'prev': {'revenue_minor': onceki, 'orders': (onceki / 12800).round(), 'avg_basket_minor': 12650},
        'delta_pct': {'revenue': yz(ciro, bugunMu && uzun == 1 ? _gunCiro(a.subtract(const Duration(days: 1)), kadar: kadar) : onceki), 'orders': 4.2, 'avg_basket': 1.6},
      },
      'by_day': [for (final g in gunler) {'date': Bicim.iso(g), 'revenue_minor': _gunCiro(g, kadar: g == _bugun ? kadar : null), 'orders': (_gunCiro(g) / 12800).round()}],
      'by_hour': [for (var h = 0; h < 24; h++) {'hour': h, 'revenue_minor': saat[h] ?? 0, 'orders': ((saat[h] ?? 0) / 12800).round()}],
      'by_weekday': [for (var d = 0; d < 7; d++) {'weekday': d, 'revenue_minor': gunler.where((g) => g.weekday - 1 == d).fold<int>(0, (t, g) => t + _gunCiro(g)), 'orders': 0}],
      'payment_mix': {
        'total_minor': ciro,
        'rows': [
          {'method': 'card', 'label': 'Kredi kartı', 'amount_minor': kart, 'count': (adisyon * .6).round(), 'share': 58},
          {'method': 'cash', 'label': 'Nakit', 'amount_minor': nakit, 'count': (adisyon * .33).round(), 'share': 34},
          {'method': 'meal', 'label': 'Yemek kartı', 'amount_minor': yemek, 'count': (adisyon * .07).round(), 'share': 8},
        ],
      },
      'service_types': {
        'total_minor': ciro,
        'rows': [
          {'label': 'Masada', 'revenue_minor': (ciro * .71).round(), 'orders': (adisyon * .7).round(), 'share': 71},
          {'label': 'Al-götür', 'revenue_minor': (ciro * .21).round(), 'orders': (adisyon * .24).round(), 'share': 21},
          {'label': 'Paket', 'revenue_minor': (ciro * .08).round(), 'orders': (adisyon * .06).round(), 'share': 8},
        ],
      },
      'top_products': [
        {'name': 'Latte', 'qty': (adisyon * .42).round(), 'revenue_minor': (ciro * .19).round()},
        {'name': 'Türk kahvesi', 'qty': (adisyon * .31).round(), 'revenue_minor': (ciro * .11).round()},
        {'name': 'San Sebastian', 'qty': (adisyon * .18).round(), 'revenue_minor': (ciro * .14).round()},
        {'name': 'Filtre kahve', 'qty': (adisyon * .16).round(), 'revenue_minor': (ciro * .07).round()},
        {'name': 'Avokadolu tost', 'qty': (adisyon * .12).round(), 'revenue_minor': (ciro * .09).round()},
      ],
      'top_categories': [
        {'name': 'Sıcak kahveler', 'qty': (adisyon * .9).round(), 'revenue_minor': (ciro * .41).round()},
        {'name': 'Tatlılar', 'qty': (adisyon * .3).round(), 'revenue_minor': (ciro * .22).round()},
        {'name': 'Kahvaltı & tost', 'qty': (adisyon * .2).round(), 'revenue_minor': (ciro * .19).round()},
        {'name': 'Soğuk içecekler', 'qty': (adisyon * .25).round(), 'revenue_minor': (ciro * .18).round()},
      ],
      'discounts': {'discount_minor': (ciro * .02).round(), 'comp_minor': (ciro * .01).round(), 'discount_orders': 4, 'comp_orders': 2, 'iskonto_minor': 0, 'iskonto_orders': 0},
      'open': {'open_orders': 7, 'open_amount_minor': 184500, 'open_tables': 6, 'receivables': {'count': 4, 'total_minor': 612000, 'enabled': true}},
      'staff': {
        'rows': [
          for (final (i, p) in [(0, 2), (1, 3), (2, 6), (3, 1)].map((e) => (e.$1, e.$2)))
            {'user': _kisi(p), 'sales_minor': (ciro * (.31 - i * .06)).round(), 'order_count': (adisyon * (.31 - i * .06)).round()},
        ],
      },
      'on_shift': bugunMu ? mesaide : [],
      'upcoming_today': bugunMu ? gelecek : [],
      'inventory': {
        'critical': 1,
        'low': 2,
        'rows': [
          {'name': 'Yulaf sütü', 'severity': 'critical', 'on_hand': '1,5', 'threshold': '4', 'unit': 'lt'},
          {'name': 'Espresso çekirdeği', 'severity': 'low', 'on_hand': '2,2', 'threshold': '3', 'unit': 'kg'},
          {'name': 'Karton bardak (12oz)', 'severity': 'low', 'on_hand': '140', 'threshold': '200', 'unit': 'adet'},
        ],
      },
      'delivery': null,
      'operations': {
        'covers': (adisyon * 1.7).round(),
        'revenue_per_guest_minor': adisyon == 0 ? 0 : (ciro / (adisyon * 1.7)).round(),
        'avg_service_min': 38,
        'table_turnover': 3.1,
        'qr_share': 18.0,
        'qr_orders': (adisyon * .18).round(),
        'cancellation_rate': 1.2,
        'cancelled_orders': 1,
        'peak_hour': {'hour': pk, 'orders': ((saat[pk] ?? 0) / 12800).round()},
      },
      'debts': {'enabled': true, 'total_minor': 86000, 'count': 3, 'kisi': 3},
      'gelir_gider': {'gelir': {'toplam_minor': ciro}, 'gider_toplam_minor': (ciro * .18).round(), 'gider_adet': 3, 'kalan_minor': (ciro * .82).round()},
      'tahsilat': {'total_minor': ciro, 'count': adisyon, 'nakit_minor': nakit, 'kart_minor': kart, 'eft_minor': 0, 'diger_minor': yemek, 'borc_minor': 24000, 'borc_count': 1},
      'kasa': {'beklenen_minor': nakit + 150000, 'devir_minor': 150000, 'acik_oturum': 1, 'kalemler': [], 'saglama_tamam': true},
      'top_debtors': {
        'enabled': true,
        'rows': [
          {'id': 1, 'name': 'Ofis — Yazılım Ekibi', 'balance_minor': 342000},
          {'id': 2, 'name': 'Komşu Kuaför', 'balance_minor': 158000},
          {'id': 3, 'name': 'Kemal Bey', 'balance_minor': 112000},
        ],
      },
      'is_gunu': {'baslangic_saati': 6, 'gece_minor': 0},
      'open_items': {
        'qty': 11,
        'amount_minor': 184500,
        'rows': [
          {'name': 'Latte', 'qty': 4, 'revenue_minor': 46000},
          {'name': 'Cheesecake', 'qty': 3, 'revenue_minor': 54000},
          {'name': 'Menemen', 'qty': 2, 'revenue_minor': 39000},
        ],
      },
    };
  }

  /* ───────── İstek yönlendirme ───────── */

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (gecikme > Duration.zero) await Future<void>.delayed(gecikme);
    final (kod, govde) = _yanit(o.method, o.path, o.queryParameters, o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{});
    return ResponseBody.fromString(govde == null ? '' : jsonEncode(govde), kod, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}

  DateTime? _gun(Object? s) => s == null ? null : Bicim.gunCoz(s.toString());

  (int, Object?) _yanit(String m, String yol, Map<String, dynamic> q, Map<String, dynamic> b) {
    final p = yol.replaceFirst(RegExp(r'^https?://[^/]+'), '').split('?').first;
    final seg = p.split('/').where((e) => e.isNotEmpty).toList();
    int? id(int i) => seg.length > i ? int.tryParse(seg[i]) : null;
    final ig = _bugun;

    if (p.contains('surum.json')) return (404, {'message': 'Demo'});
    if (p == '/api/v1/notifications') {
      return (200, {'items': _bildirimler, 'unread_count': _bildirimler.where((n) => n['read'] != true).length});
    }
    if (p.startsWith('/api/v1/notifications/')) {
      for (final n in _bildirimler) {
        if (p.endsWith('read-all') || n['id'] == id(3)) n['read'] = true;
      }
      return (200, {'ok': true});
    }
    if (p == '/api/v1/boss/overview') {
      final per = q['period']?.toString();
      DateTime a = ig, z = ig;
      if (per == 'week') a = ig.subtract(Duration(days: ig.weekday - 1));
      if (per == 'month') a = DateTime(ig.year, ig.month, 1);
      if (q['from'] != null) {
        a = _gun(q['from']) ?? ig;
        z = _gun(q['to']) ?? a;
      }
      return (200, {'data': _ozet(a, z)});
    }
    if (p == '/api/v1/reports/ops-delayed') {
      return (200, {'data': {'rows': [{'id': 1, 'table': 'Teras 3', 'age_minutes': 52, 'total_minor': 46000}]}});
    }
    if (p == '/api/v1/reports/borca-yazilanlar') {
      return (200, {
        'rows': [
          {'name': 'Ofis — Yazılım Ekibi', 'amount_minor': 48000, 'created_at': _utc(_an.subtract(const Duration(hours: 3))), 'kaynak': 'Adisyon M7', 'performed_by': 'Mert Kaya', 'reason': 'Ay sonu ödeme'},
          {'name': 'Kemal Bey', 'amount_minor': 38000, 'created_at': _utc(_an.subtract(const Duration(hours: 5))), 'kaynak': 'Adisyon M2', 'performed_by': 'Zeynep Arslan', 'reason': ''},
        ],
        'kisiler': [
          {'receivable_id': 1, 'name': 'Ofis — Yazılım Ekibi', 'balance_minor': 342000, 'amount_minor': 48000, 'count': 1},
          {'receivable_id': 3, 'name': 'Kemal Bey', 'balance_minor': 112000, 'amount_minor': 38000, 'count': 1},
        ],
        'enabled': true,
        'total_minor': 86000,
        'count': 2,
        'kisi': 2,
      });
    }
    if (p.startsWith('/api/v1/reports/')) {
      final v = _ozetRaporu(seg.last, q);
      return (200, v != null ? {'data': v} : _rapor(seg.last));
    }

    /* Görevler */
    if (p == '/api/v1/tasks' && m == 'GET') {
      return (200, {'tasks': _gorevler, 'staff': [for (final x in personel) _kisi(x.$1)]});
    }
    if (p == '/api/v1/tasks' && m == 'POST') {
      final kisi = b['assigned_to_id'] as int?;
      final t = _gorev(b['title'].toString(), b['description']?.toString(), kisi, b['priority']?.toString() ?? 'normal',
          b['due_at'] == null ? null : DateTime.parse(b['due_at'].toString()).toLocal(), 'open');
      _gorevler.insert(0, t);
      return (201, {'task': t});
    }
    if (seg.length == 5 && seg[2] == 'tasks' && m == 'POST' && (seg[4] == 'onayla' || seg[4] == 'reddet')) {
      final t = _gorevler.where((x) => x['id'] == id(3)).firstOrNull;
      if (t == null) return (404, {'message': 'Görev bulunamadı'});
      if (t['status'] != 'review') return (422, {'message': 'Bu görev onay beklemiyor.'});
      final onay = seg[4] == 'onayla';
      t['status'] = onay ? 'done' : 'in_progress';
      t['completed_at'] = onay ? _utc(_an) : null;
      t['onay'] = {
        ...(t['onay'] as Map? ?? const {}),
        'durum': onay ? 'approved' : 'rejected',
        'bekliyor': false,
        'inceleyen': {'id': 99, 'name': demoPatronAdi},
        'inceleme': _utc(_an),
        'gerekce': onay ? null : b['gerekce'],
      };
      return (200, {'task': t});
    }
    if (seg.length == 4 && seg[2] == 'tasks') {
      final t = _gorevler.where((x) => x['id'] == id(3)).firstOrNull;
      if (t == null) return (404, {'message': 'Görev bulunamadı'});
      if (m == 'DELETE') {
        _gorevler.remove(t);
        return (204, null);
      }
      t.addAll(b);
      if (b['status'] == 'done') t['completed_at'] = _utc(_an);
      return (200, {'task': t});
    }

    /* Vardiya */
    if (p == '/api/v1/shifts/meta') {
      return (200, {
        'staff': [for (final x in personel) _kisi(x.$1)],
        'branches': [{'id': 1, 'name': 'Martı Kahve · Moda (Demo)'}],
        'positions': ['Barista', 'Garson', 'Mutfak', 'Kasa'],
        'default_break_min': 30,
        'can': {'view_all': true, 'manage': true},
      });
    }
    if (p == '/api/v1/shifts/schedule') {
      final a = _gun(q['from']) ?? ig, z = _gun(q['to']) ?? ig.add(const Duration(days: 7));
      return (200, {
        'shifts': _vardiyalar.where((v) {
          final s = DateTime.parse(v['starts_at'] as String).toLocal();
          return !s.isBefore(a) && s.isBefore(z.add(const Duration(days: 1)));
        }).toList(),
        'leaves': _izinler.where((l) => l['status'] == 'approved').toList(),
        'warnings': [
          {'date': Bicim.iso(ig.add(const Duration(days: 2))), 'branch_id': 1, 'position': 'Barista', 'required': 2, 'planned': 1},
        ],
      });
    }
    if (p == '/api/v1/shifts/shifts' && m == 'POST') {
      final out = <Map<String, dynamic>>[];
      final hafta = (b['repeat_weeks'] as int?) ?? 0;
      for (var w = 0; w <= hafta; w++) {
        final s = {
          'id': ++_sira,
          'branch_id': 1,
          'user_id': b['user_id'],
          'user': _kisi(b['user_id'] as int),
          'position': _kisi(b['user_id'] as int)['position'],
          'starts_at': _utc(DateTime.parse(b['starts_at'].toString()).add(Duration(days: 7 * w))),
          'ends_at': _utc(DateTime.parse(b['ends_at'].toString()).add(Duration(days: 7 * w))),
          'break_min': b['break_min'] ?? 0,
          'note': b['note'],
          'repeat_group': hafta > 0 ? 'seri-$_sira' : null,
        };
        _vardiyalar.add(s);
        out.add(s);
      }
      return (201, {'shifts': out, 'skipped': []});
    }
    if (seg.length == 5 && seg[2] == 'shifts' && seg[3] == 'shifts') {
      final v = _vardiyalar.where((x) => x['id'] == id(4)).firstOrNull;
      if (v == null) return (404, {'message': 'Vardiya bulunamadı'});
      if (m == 'DELETE') {
        _vardiyalar.remove(v);
        return (204, null);
      }
      for (final k in ['user_id', 'starts_at', 'ends_at', 'break_min', 'note']) {
        if (b.containsKey(k)) v[k] = b[k];
      }
      v['user'] = _kisi(v['user_id'] as int);
      return (200, {'shift': v});
    }
    if (p == '/api/v1/shifts/day-board') {
      final g = _gun(q['gun']) ?? ig;
      final satir = <Map<String, dynamic>>[];
      for (final x in personel) {
        final v = _vardiyalar.where((s) {
          final d = DateTime.parse(s['starts_at'] as String).toLocal();
          return s['user_id'] == x.$1 && d.year == g.year && d.month == g.month && d.day == g.day;
        }).firstOrNull;
        final k = g == ig ? _kayitlar.where((e) => (e['user'] as Map)['id'] == x.$1).firstOrNull : null;
        if (v == null && k == null) continue;
        final vb = v == null ? null : DateTime.parse(v['starts_at'] as String).toLocal();
        final izinli = _izinler.any((l) => l['status'] == 'approved' && (l['user'] as Map)['id'] == x.$1 && !g.isBefore(_gun(l['starts_on'])!) && !g.isAfter(_gun(l['ends_on'])!));
        final durum = k != null
            ? (k['clock_out_at'] == null ? 'calisiyor' : 'cikti')
            : izinli
                ? 'izinli'
                : (vb != null && vb.isAfter(_an) ? 'bekliyor' : 'gelmedi');
        satir.add({
          'user': _kisi(x.$1),
          'vardiya': v == null ? null : {'id': v['id'], 'starts_at': v['starts_at'], 'ends_at': v['ends_at'], 'break_min': v['break_min'], 'position': v['position']},
          'giris': k?['clock_in_at'],
          'cikis': k?['clock_out_at'],
          'mola_dk': k?['break_total_min'] ?? 0,
          'calisilan_dk': k == null ? 0 : (k['clock_out_at'] == null ? _an.difference(DateTime.parse(k['clock_in_at'] as String)).inMinutes : k['worked_min']),
          'devam': k != null && k['clock_out_at'] == null,
          'gec_dk': k?['late_min'] ?? 0,
          'dakiklik': k == null ? null : ((k['late_min'] as int) > 0 ? 'gec' : 'zamaninda'),
          'durum': durum,
          'izin_adi': izinli ? 'Yıllık izin' : null,
        });
      }
      int say(bool Function(Map<String, dynamic>) f) => satir.where(f).length;
      return (200, {
        'gun': Bicim.iso(g),
        'simdi': _utc(_an),
        'tolerans_dk': 5,
        'satirlar': satir,
        'ozet': {
          'kisi': satir.length,
          'vardiyali': say((s) => s['vardiya'] != null),
          'calisan': say((s) => s['durum'] == 'calisiyor'),
          'gec': say((s) => s['dakiklik'] == 'gec'),
          'gelmedi': say((s) => s['durum'] == 'gelmedi'),
          'izinli': say((s) => s['durum'] == 'izinli'),
          'calisilan_dk': satir.fold<int>(0, (a, s) => a + (s['calisilan_dk'] as int)),
        },
      });
    }
    if (p == '/api/v1/shifts/time-entries') {
      final u = int.tryParse('${q['user_id']}');
      return (200, {'data': [for (final k in _kayitlar) if (u == null || (k['user'] as Map)['id'] == u) Map.of(k)..remove('_vardiya')], 'total': _kayitlar.length});
    }
    if (seg.length >= 5 && seg[3] == 'time-entries') {
      final k = _kayitlar.where((x) => x['id'] == id(4)).firstOrNull;
      if (k == null) return (404, {'message': 'Kayıt bulunamadı'});
      if (seg.length == 6) {
        if (k['clock_out_at'] == null) return (422, {'message': 'Açık kayıt onaylanamaz; önce çıkış yapılmalı.'});
        k['approved_at'] = _utc(_an);
      } else {
        k.addAll({...b}..remove('reason'));
        k['edit_reason'] = b['reason'];
        if (k['clock_out_at'] != null) {
          k['status'] = 'closed';
          k['worked_min'] = DateTime.parse(k['clock_out_at'] as String).difference(DateTime.parse(k['clock_in_at'] as String)).inMinutes - ((k['break_total_min'] as int?) ?? 0);
        }
      }
      return (200, {'entry': k});
    }
    if (p == '/api/v1/shifts/attendance-summary') {
      return (200, {
        'summary': [
          for (final x in personel)
            {
              'user': _kisi(x.$1),
              'days_worked': 3 + x.$1 % 3,
              'worked_min': (3 + x.$1 % 3) * 450 + x.$1 * 13,
              'break_min': 90,
              'overtime_min': x.$1 == 2 ? 75 : (x.$1 == 7 ? 40 : 0),
              'missing_min': x.$1 == 6 ? 480 : 0,
              'late_count': x.$1 == 2 ? 2 : (x.$1 == 4 ? 1 : 0),
              'late_min': x.$1 == 2 ? 26 : 0,
              'early_leave_count': 0,
              'planned_shifts': 5,
              'leave_days': 0,
              'auto_absent_days': x.$1 == 6 ? 1 : 0,
            },
        ],
      });
    }
    if (p == '/api/v1/shifts/leave-requests' && m == 'GET') {
      final st = q['status']?.toString();
      final l = _izinler.where((x) => st == null || x['status'] == st).toList();
      return (200, {'data': l, 'total': l.length});
    }
    if (p == '/api/v1/shifts/leave-requests' && m == 'POST') {
      final l = {
        'id': ++_sira,
        'user': _kisi(b['user_id'] as int),
        'type': b['type'],
        'starts_on': b['starts_on'],
        'ends_on': b['ends_on'],
        'reason': b['reason'],
        'status': 'approved',
        'created_at': _utc(_an),
      };
      _izinler.add(l);
      return (201, {'leave': l});
    }
    if (p == '/api/v1/shifts/swap-requests') {
      final st = q['status']?.toString();
      final l = _takaslar.where((x) => st == null || x['status'] == st).toList();
      return (200, {'data': l, 'total': l.length});
    }
    if (seg.length == 6 && (seg[3] == 'leave-requests' || seg[3] == 'swap-requests')) {
      final liste = seg[3] == 'leave-requests' ? _izinler : _takaslar;
      final x = liste.where((e) => e['id'] == id(4)).firstOrNull;
      if (x == null) return (404, {'message': 'Talep bulunamadı'});
      x['status'] = seg[5] == 'approve' ? 'approved' : 'rejected';
      if (seg[3] == 'swap-requests' && seg[5] == 'approve') {
        final hedef = (b['target_user_id'] as int?) ?? (x['target_user'] as Map?)?['id'] as int?;
        final v = _vardiyalar.where((s) => s['id'] == (x['shift'] as Map)['id']).firstOrNull;
        if (v != null && hedef != null) {
          v['user_id'] = hedef;
          v['user'] = _kisi(hedef);
        }
      }
      return (200, {'ok': true});
    }
    return (404, {'message': 'Demo: bu bölüm örnek veride yok.'});
  }

  /// Rapor katalogundaki sütunlara göre örnek satırlar.

  /// Raporlar › Özet uçları (web OzetTab ile aynı biçim), dönem patron özetinden türetilir.
  Map<String, dynamic>? _ozetRaporu(String k, Map<String, dynamic> q) {
    const anahtarlar = {'finance-summary', 'sales-open-items', 'sales-categories', 'finance-collected', 'sales-daily', 'sales-hourly', 'receivables-summary'};
    if (!anahtarlar.contains(k)) return null;
    final ig = _bugun;
    DateTime a = ig, z = ig;
    switch (q['range']?.toString()) {
      case 'yesterday':
        a = z = ig.subtract(const Duration(days: 1));
      case 'month':
        a = DateTime(ig.year, ig.month, 1);
      default:
        if (q['from'] != null) {
          a = _gun(q['from']) ?? ig;
          z = _gun(q['to']) ?? a;
        }
    }
    final o = _ozet(a, z);
    final s = o['sales'] as Map<String, dynamic>;
    final ciro = s['revenue_minor'] as int, adet = s['orders'] as int;
    final odeme = (o['payment_mix'] as Map)['rows'] as List;
    switch (k) {
      case 'finance-summary':
        final indirim = (ciro * .02).round(), ikram = (ciro * .01).round();
        return {
          'orders': adet, 'gross_minor': ciro, 'net_minor': (ciro / 1.1).round(), 'vat_minor': ciro - (ciro / 1.1).round(),
          'items_total_minor': ciro + indirim + ikram, 'order_discount_minor': indirim, 'iskonto_minor': 0, 'item_discount_minor': 0,
          'discount_total_minor': indirim, 'comp_minor': ikram, 'service_charge_minor': 0, 'cancelled_orders': adet > 0 ? 1 : 0,
          'cancelled_minor': adet > 0 ? 11500 : 0, 'collected_count': adet, 'collected_minor': ciro + 24000, 'tips_minor': (ciro * .015).round(),
          'refund_payments_count': 0, 'refund_payments_minor': 0,
        };
      case 'sales-open-items':
        return (o['open_items'] as Map).cast<String, dynamic>();
      case 'sales-categories':
        return {
          'rows': [
            for (final c in o['top_categories'] as List) {'name': c['name'], 'qty': c['qty'], 'orders': (c['qty'] as int) ~/ 2, 'revenue_minor': c['revenue_minor']},
          ],
        };
      case 'finance-collected':
        final rows = [
          for (final r in odeme) {'key': r['method'], 'label': r['label'], 'count': r['count'], 'amount_minor': r['amount_minor'], 'share': r['share']},
          {'key': 'borc', 'label': 'Borçtan tahsilat', 'count': 1, 'amount_minor': 24000, 'share': 1},
        ];
        return {'total_minor': ciro + 24000, 'total_count': adet + 1, 'borc_minor': 24000, 'tips_minor': 0, 'rows': rows};
      case 'sales-daily':
        return {'days': o['by_day']};
      case 'sales-hourly':
        return {'hours': o['by_hour']};
      case 'receivables-summary':
        return {
          'available': true, 'yazilan_minor': 86000, 'yazilan_adet': 2, 'tahsil_minor': 24000, 'iskonto_minor': 0,
          'acik_borc_sonu_minor': 612000, 'net_degisim_minor': 62000,
        };
    }
    return null;
  }

  Map<String, dynamic> _rapor(String anahtar) {
    final t = raporlar.where((e) => e.anahtar == anahtar).firstOrNull;
    if (t == null) return {'data': {'rows': []}};
    final adlar = ['Latte', 'Türk kahvesi', 'San Sebastian', 'Filtre kahve', 'Avokadolu tost', 'Limonata', 'Menemen', 'Cheesecake'];
    final satir = <Map<String, dynamic>>[];
    for (var i = 0; i < 8; i++) {
      final r = <String, dynamic>{};
      for (final k in t.sutunlar.keys) {
        r[k] = switch (sutunTuru(k)) {
          SutunTur.para || SutunTur.ortalama => (90000 - i * 8500 + _rnd.nextInt(4000)),
          SutunTur.sayi => 60 - i * 6 + _rnd.nextInt(5),
          SutunTur.yuzde => double.parse((24 - i * 2.5).toStringAsFixed(1)),
          SutunTur.tarih => k == 'date' ? Bicim.iso(_bugun.subtract(Duration(days: 7 - i))) : _utc(_an.subtract(Duration(hours: i * 3))),
          SutunTur.evetHayir => i.isEven,
          SutunTur.metin => k == 'hour' ? 9 + i : (k.contains('user') || k.contains('staff') || k == 'waiter' ? personel[i % 8].$2 : adlar[i]),
        };
      }
      satir.add(r);
    }
    return {
      'data': {t.satirlar: satir, 'available': true},
      'filters': {'from': Bicim.iso(_bugun), 'to': Bicim.iso(_bugun)},
    };
  }
}
