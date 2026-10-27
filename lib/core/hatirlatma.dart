import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Yalnız son 10 yılın kuralları: tüm veritabanının ~1/6'sı (daha küçük uygulama,
// ilk hatırlatma kurulumunda ana iş parçacığında çok daha kısa ayrıştırma).
import 'package:timezone/data/latest_10y.dart' as tzveri;
import 'package:timezone/timezone.dart' as tz;

import '../ortak/ortak.dart';
import 'api.dart';

/// MESAİ HATIRLATMALARI (2026-10-27) — sesli + titreşimli, telefonda zamanlanır.
///
/// Android'de FCM yok (bildirimler yoklamayla gelir) → tam saatinde çalması
/// için her Shift'e 4 yerel alarm kurulur: başlangıçtan 10 dk önce, başlangıçta,
/// bitişten 10 dk önce, bitişte. Dokununca QR okutma ekranı açılır.
///
/// Sunucu aynı 4 hatırlatmayı AYNI başlıklarla bildirim listesine de yazar
/// (iOS'ta APNs ile gelir). Çift uyarı olmasın diye:
///   • iOS'ta yerel zamanlama YAPILMAZ (APNs güvenilir);
///   • Android'de yoklama bu başlıkları sistem bildirimi/baloncuk olarak
///     yeniden göstermez (yerel alarm zaten çaldı), listede yine durur.
class MesaiHatirlatma {
  MesaiHatirlatma._();

  static const kanalId = 'mesai_hatirlatma';
  static const tercihAnahtari = 'mesai_hatirlatma_acik';
  static const _idAnahtari = 'mesai_hatirlatma_idleri';
  static const _imzaAnahtari = 'mesai_hatirlatma_imza';
  /// Bu süreçte en son kurulan planın imzası (ön plan).
  static String? _sonImza;
  static const _konumAdi = 'Europe/Istanbul';
  static const _ileri = Duration(days: 7);

  static const baslikBasliyor10 = 'Mesain 10 dakika sonra başlıyor';
  static const baslikBasladi = 'Mesain başladı — QR\'ı okut';
  static const baslikBitiyor10 = 'Mesain 10 dakika sonra bitiyor';
  static const baslikBitti = 'Mesain bitti — çıkış QR\'ını okut';
  static const basliklar = {baslikBasliyor10, baslikBasladi, baslikBitiyor10, baslikBitti};

  /// Sunucudan gelen bildirim bu hatırlatmalardan biri mi?
  static bool baslikMi(Object? t) => t != null && basliklar.contains(t.toString().trim());

  /// Ayar (Bildirimler ekranı): varsayılan AÇIK.
  static final acik = ValueNotifier<bool>(true);

  /// Test/ekran görüntüsü için platform zorlaması.
  @visibleForTesting
  static bool? androidZorla;

  /// Yerel zamanlama yalnız Android'de (iOS'ta APNs zaten çalar).
  static bool get yerelZamanlama => androidZorla ?? (!kIsWeb && Platform.isAndroid);

  static final kanal = AndroidNotificationChannel(
    kanalId,
    'Mesai hatırlatmaları',
    description: 'Shift başlangıç ve bitişinde sesli + titreşimli QR hatırlatması',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 600, 250, 600, 250, 900]),
  );

  static NotificationDetails get _ayrinti => NotificationDetails(
        android: AndroidNotificationDetails(
          kanal.id,
          kanal.name,
          channelDescription: kanal.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          vibrationPattern: kanal.vibrationPattern,
          fullScreenIntent: false,
          category: AndroidNotificationCategory.reminder,
          visibility: NotificationVisibility.public,
          color: const Color(0xFF5443D2),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      );

  static bool _tzHazir = false;
  static tz.Location get _konum {
    if (!_tzHazir) {
      tzveri.initializeTimeZones();
      _tzHazir = true;
    }
    return tz.getLocation(_konumAdi);
  }

  static Future<void> tercihOku(SharedPreferences p) async => acik.value = p.getBool(tercihAnahtari) ?? true;

  /// Ayarı değiştirir; kapatınca kurulu hatırlatmalar hemen silinir.
  static Future<void> ayarla(bool v, {required FlutterLocalNotificationsPlugin eklenti, required SharedPreferences p, required Api api}) async {
    acik.value = v;
    await p.setBool(tercihAnahtari, v);
    await esitle(eklenti: eklenti, p: p, api: api);
  }

  /// Shift listesinden (GET /api/v1/portal/schedule → shifts) önümüzdeki
  /// 7 günün GELECEKTEKİ hatırlatma anları.
  static List<HatirlatmaAni> anlar(List<Map> vardiyalar, DateTime simdi) {
    // Arka plan isolate'inde tr_TR yerel verisi yüklü değil → elle biçimle.
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final out = <HatirlatmaAni>[];
    for (final v in vardiyalar) {
      final bas = DateTime.tryParse(v['starts_at']?.toString() ?? '')?.toLocal();
      final bit = DateTime.tryParse(v['ends_at']?.toString() ?? '')?.toLocal();
      if (bas == null || bit == null || !bit.isAfter(bas)) continue;
      if (bas.isAfter(simdi.add(_ileri)) || bit.isBefore(simdi)) continue;
      final kimlik = (v['id'] as num?)?.toInt() ?? bas.millisecondsSinceEpoch ~/ 60000;
      final b = hm(bas);
      final s = hm(bit);
      final adaylar = [
        (bas.subtract(const Duration(minutes: 10)), baslikBasliyor10, 'Shift $b başlıyor. Girişte mesai QR\'ını okutmayı unutma.'),
        (bas, baslikBasladi, 'Shift saati geldi ($b). Mesaiye başlamak için mesai QR\'ını okut.'),
        (bit.subtract(const Duration(minutes: 10)), baslikBitiyor10, 'Shift $s bitiyor. Çıkışta mesai QR\'ını okutmayı unutma.'),
        (bit, baslikBitti, 'Shift saati doldu ($s). Mesaiyi bitirmek için mesai QR\'ını okut.'),
      ];
      for (var k = 0; k < adaylar.length; k++) {
        final a = adaylar[k];
        if (!a.$1.isAfter(simdi)) continue;
        // Deterministik kimlik: sunucu bildirim kimlikleriyle çakışmayan aralık.
        out.add(HatirlatmaAni(1700000000 + (kimlik * 4 + k) % 100000000, a.$1, a.$2, a.$3));
      }
    }
    out.sort((a, b) => a.zaman.compareTo(b.zaman));
    return out;
  }

  static Future<void>? _suren;

  /// Kurulu hatırlatmaları silip baştan kurar. `vardiyalar` verilmezse
  /// /api/v1/portal/schedule'dan çeker. Uygulama açılışı, öne gelme, Shift
  /// ekranı yüklemesi ve Android arka plan görevi çağırır.
  static Future<void> esitle({
    required FlutterLocalNotificationsPlugin eklenti,
    required SharedPreferences p,
    Api? api,
    List<Map>? vardiyalar,
    bool onPlan = true,
  }) {
    // Aynı anda iki eşitleme (açılış + Shift ekranı) birbirini ezmesin.
    final once = _suren ?? Future<void>.value();
    final f = once.then((_) => _esitle(eklenti, p, api, vardiyalar, onPlan)).catchError((_) {});
    _suren = f;
    return f;
  }

  static Future<void> _esitle(FlutterLocalNotificationsPlugin eklenti, SharedPreferences p, Api? api, List<Map>? vardiyalar, bool onPlan) async {
    if (!yerelZamanlama) return;
    try {
      await p.reload(); // arka plan görevi de yazar
    } catch (_) {}
    acik.value = p.getBool(tercihAnahtari) ?? true;

    List<HatirlatmaAni> liste = const [];
    if (acik.value) {
      var l = vardiyalar;
      if (l == null && api != null) {
        try {
          final r = await api.get('/api/v1/portal/schedule') as Map;
          l = ((r['shifts'] as List?) ?? const []).whereType<Map>().toList();
        } on ApiHata {
          return; // Ağ yok: eldeki kurulu alarmlar kalsın.
        }
      }
      if (l == null) return;
      liste = anlar(l, DateTime.now());
    }

    // Plan değişmediyse alarmları silip yeniden kurma (her açılış/dönüşte 28
    // platform çağrısı). Ön planda sürecin İLK eşitlemesi her zaman kurar
    // (zorla durdurma alarmları silmiş olabilir); arka plan görevi kayıtlı imzaya bakar.
    final imza = '${acik.value}|${liste.map((a) => '${a.id}@${a.zaman.millisecondsSinceEpoch}').join(',')}';
    final kayitli = p.getString(_imzaAnahtari);
    if (kayitli == imza && (!onPlan || _sonImza == imza)) {
      if (onPlan) _onPlanKur(liste);
      return;
    }

    final android = eklenti.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // Eskileri sil
    final eski = (p.getStringList(_idAnahtari) ?? const []).map(int.tryParse).whereType<int>();
    for (final id in eski) {
      try {
        await eklenti.cancel(id: id);
      } catch (_) {}
    }
    if (onPlan) _onPlanKur(liste);
    if (liste.isEmpty) {
      await p.setStringList(_idAnahtari, const []);
      await _imzaKaydet(p, imza, onPlan);
      return;
    }

    await android?.createNotificationChannel(kanal);
    var kip = AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      if (await android?.canScheduleExactNotifications() ?? false) kip = AndroidScheduleMode.exactAllowWhileIdle;
    } catch (_) {}

    final konum = _konum;
    final kurulan = <String>[];
    for (final a in liste) {
      try {
        await eklenti.zonedSchedule(
          id: a.id,
          title: a.baslik,
          body: a.govde,
          scheduledDate: tz.TZDateTime.from(a.zaman, konum),
          notificationDetails: _ayrinti,
          androidScheduleMode: kip,
          payload: '/qr-okut',
        );
        kurulan.add('${a.id}');
      } catch (_) {
        // Tek alarm kurulamazsa diğerleri kurulsun.
      }
    }
    await p.setStringList(_idAnahtari, kurulan);
    // Hepsi kurulduysa imzayı sakla (eksik kaldıysa sonraki eşitleme yeniden dener).
    if (kurulan.length == liste.length) await _imzaKaydet(p, imza, onPlan);
  }

  static Future<void> _imzaKaydet(SharedPreferences p, String imza, bool onPlan) async {
    if (onPlan) _sonImza = imza;
    await p.setString(_imzaAnahtari, imza);
  }

  /* ───────── Uygulama açıkken: titreşim + baloncuk ───────── */

  static final _zamanlayicilar = <Timer>[];

  static void _onPlanKur(List<HatirlatmaAni> liste) {
    for (final t in _zamanlayicilar) {
      t.cancel();
    }
    _zamanlayicilar.clear();
    final simdi = DateTime.now();
    for (final a in liste) {
      final kalan = a.zaman.difference(simdi);
      if (kalan > const Duration(hours: 24)) break;
      _zamanlayicilar.add(Timer(kalan, () {
        if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
        uyar(a.baslik, a.govde);
      }));
    }
  }

  /// Ön planda hatırlatma: iki güçlü titreşim + üstte baloncuk.
  static void uyar(String baslik, String? govde) {
    HapticFeedback.heavyImpact();
    Future<void>.delayed(const Duration(milliseconds: 220), HapticFeedback.heavyImpact);
    bildir(baslik, mesaj: govde, tur: BildirimTur.uyari);
  }
}

class HatirlatmaAni {
  const HatirlatmaAni(this.id, this.zaman, this.baslik, this.govde);
  final int id;
  final DateTime zaman;
  final String baslik;
  final String govde;
}
