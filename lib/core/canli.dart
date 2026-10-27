import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'bicim.dart';
import 'durum.dart';

/// Ekip uçlarının yetki durumu. Sunucu 403/404 dönünce ilgili eylem gizlenir.
enum Yetki { bilinmiyor, var_, yok, kapali }

/// CANLI DURUM: üst şerit, alt çubuk rozetleri ve hızlı eylemler için
/// paylaşılan hafif veri. Uygulama öndeyken 60 sn'de bir tazelenir.
///
/// Çağrılan uçlar (hepsi patron host'unda açık — HandleBossHost::ALLOWED):
///   GET /api/v1/boss/overview?period=day          → ciro, açık masa, mesaide
///   GET /api/v1/shifts/meta                       → şube adı, personel, yetki
///   GET /api/v1/shifts/leave-requests?status=pending → bekleyen izin
///   GET /api/v1/shifts/swap-requests?status=pending  → bekleyen değişim
///   GET /api/v1/tasks                             → geciken görev, atama listesi
///
/// Her uç ayrı düşer: biri 403/404 dönerse diğerleri çalışmaya devam eder.
class Canli {
  Canli._();

  /// Bugünkü patron özeti (overview period=day `data`).
  static final ozet = ValueNotifier<Map<String, dynamic>?>(null);

  /// shifts/meta yanıtı (personel, şube, can).
  static final meta = ValueNotifier<Map<String, dynamic>?>(null);

  /// Bekleyen talepler (izin + değişim).
  static final bekleyenIzin = ValueNotifier<int>(0);
  static final bekleyenTakas = ValueNotifier<int>(0);

  /// Görevler (tasks index `tasks`) ve atanabilir personel (`staff`).
  static final gorevler = ValueNotifier<List<Map<String, dynamic>>?>(null);
  static final gorevPersonel = ValueNotifier<List<Map<String, dynamic>>>(const []);

  static final gorevYetki = ValueNotifier<Yetki>(Yetki.bilinmiyor);
  static final vardiyaYetki = ValueNotifier<Yetki>(Yetki.bilinmiyor);

  /// Son başarılı tazeleme zamanı (üst şeritte "14:32 güncellendi").
  static final sonGuncelleme = ValueNotifier<DateTime?>(null);

  /// Ekip sekmesi rozeti: bekleyen talepler + geciken görevler.
  static final ekipRozet = ValueNotifier<int>(0);

  static Timer? _zaman;
  static bool _mesgul = false;
  static DateTime? _metaZamani;

  static void basla() {
    _onbellektenDoldur();
    unawaited(tazele());
    _zaman?.cancel();
    _zaman = Timer.periodic(const Duration(seconds: 60), (_) => tazele());
  }

  /// Soğuk açılışta şerit/rozetler boş kalmasın: son bilinen yanıtlar.
  static void _onbellektenDoldur() {
    final o = Api.sonYanit('/api/v1/boss/overview', sorgu: const {'period': 'day'});
    if (ozet.value == null && o is Map) ozet.value = o.m('data');
    final m = Api.sonYanit('/api/v1/shifts/meta');
    if (meta.value == null && m is Map) meta.value = Map<String, dynamic>.from(m);
    final g = Api.sonYanit('/api/v1/tasks');
    if (gorevler.value == null && g is Map) {
      gorevler.value = g.l('tasks');
      gorevPersonel.value = g.l('staff');
    }
    _rozet();
  }

  static void durdur() {
    _zaman?.cancel();
    _zaman = null;
  }

  @visibleForTesting
  static void sifirla() {
    durdur();
    ozet.value = null;
    meta.value = null;
    bekleyenIzin.value = 0;
    bekleyenTakas.value = 0;
    gorevler.value = null;
    gorevPersonel.value = const [];
    gorevYetki.value = Yetki.bilinmiyor;
    vardiyaYetki.value = Yetki.bilinmiyor;
    sonGuncelleme.value = null;
    ekipRozet.value = 0;
    _metaZamani = null;
    _mesgul = false;
  }

  static Yetki _yetkiCoz(ApiHata e) => e.yetkiYok ? Yetki.yok : (e.kod == 404 ? Yetki.kapali : Yetki.bilinmiyor);

  /// Özet ekranı kendi "bugün" yanıtını buraya da yazar (çift istek olmasın).
  static void ozetGeldi(Map<String, dynamic> v) {
    ozet.value = v;
    sonGuncelleme.value = DateTime.now();
  }

  static Future<void> tazele({bool zorla = false}) async {
    if (_mesgul) return;
    _mesgul = true;
    try {
      final isler = <Future<void>>[
        _ozet(zorla),
        _talepler(),
        gorevleriTazele(),
      ];
      // Meta (personel listesi) 10 dk'da bir yeter.
      if (zorla || _metaZamani == null || DateTime.now().difference(_metaZamani!) > const Duration(minutes: 10)) {
        isler.add(metaTazele());
      }
      await Future.wait(isler);
      _rozet();
    } finally {
      _mesgul = false;
    }
  }

  static Future<void> _ozet(bool zorla) async {
    // Özet ekranı az önce tazelediyse tekrar isteme.
    final s = sonGuncelleme.value;
    if (!zorla && s != null && DateTime.now().difference(s) < const Duration(seconds: 45)) return;
    try {
      final r = await Uyg.api.get('/api/v1/boss/overview', sorgu: const {'period': 'day'});
      if (r is Map) ozetGeldi(r.m('data'));
    } on ApiHata {
      // Sessiz: şerit son bilinen değeri gösterir.
    }
  }

  static Future<void> metaTazele() async {
    try {
      final r = await Uyg.api.get('/api/v1/shifts/meta');
      if (r is Map) {
        meta.value = Map<String, dynamic>.from(r);
        vardiyaYetki.value = r.m('can').b('manage') ? Yetki.var_ : Yetki.yok;
        _metaZamani = DateTime.now();
      }
    } on ApiHata catch (e) {
      final y = _yetkiCoz(e);
      if (y != Yetki.bilinmiyor) vardiyaYetki.value = y;
    }
  }

  static Future<void> _talepler() async {
    Future<int?> say(String yol) async {
      try {
        final r = await Uyg.api.get(yol, sorgu: const {'status': 'pending'});
        if (r is Map) return r.i('total') > 0 ? r.i('total') : r.l('data').length;
      } on ApiHata {
        return null;
      }
      return null;
    }

    final s = await Future.wait([say('/api/v1/shifts/leave-requests'), say('/api/v1/shifts/swap-requests')]);
    if (s[0] != null) bekleyenIzin.value = s[0]!;
    if (s[1] != null) bekleyenTakas.value = s[1]!;
  }

  static Future<void> gorevleriTazele() async {
    try {
      final r = await Uyg.api.get('/api/v1/tasks');
      if (r is Map) {
        gorevler.value = r.l('tasks');
        gorevPersonel.value = r.l('staff');
        // Liste geldi = en az tasks.view. Yazma yetkisi ilk POST'ta netleşir.
        if (gorevYetki.value == Yetki.bilinmiyor || gorevYetki.value == Yetki.kapali) gorevYetki.value = Yetki.var_;
      }
    } on ApiHata catch (e) {
      final y = _yetkiCoz(e);
      if (y != Yetki.bilinmiyor) gorevYetki.value = y;
    }
    _rozet();
  }

  /// Geciken (son tarihi geçmiş, bitmemiş) görev sayısı.
  static int get gecikenGorev {
    final simdi = DateTime.now();
    return (gorevler.value ?? const []).where((t) {
      if (t.s('status') == 'done') return false;
      final d = DateTime.tryParse(t.s('due_at'));
      return d != null && d.isBefore(simdi);
    }).length;
  }

  static void _rozet() => ekipRozet.value = bekleyenIzin.value + bekleyenTakas.value + gecikenGorev;

  /// Şube adı (shifts/meta `branches` — yalnız geçerli şube döner).
  static String get subeAdi {
    final b = meta.value?.l('branches') ?? const [];
    return b.isEmpty ? '' : b.first.s('name');
  }

  /// Vardiya planlanabilecek personel (meta.staff).
  static List<Map<String, dynamic>> get personel => meta.value?.l('staff') ?? const [];
}

/// Personel adı → baş harfler ("Ayşe Yılmaz" → "AY").
String basHarf(String ad) {
  final p = ad.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2).toList();
  if (p.isEmpty) return '•';
  return p.map((e) => String.fromCharCode(e.runes.first).toUpperCase()).join();
}

/// Sunucu UTC saklar: yerel saati UTC ISO-8601'e çevirir ("…T06:00:00.000Z").
/// Web panelinin gönderdiği "Y-m-d H:i" (bölgesiz) biçimi sunucuda UTC
/// sayıldığından KULLANILMAZ; uygulama her zaman açık UTC gönderir.
String utcIso(DateTime yerel) => yerel.toUtc().toIso8601String();

/// Pazartesi 00:00 (yerel).
DateTime haftaBasi(DateTime d) {
  final g = DateTime(d.year, d.month, d.day);
  return g.subtract(Duration(days: g.weekday - 1));
}

String gunIso(DateTime d) => Bicim.iso(d);
