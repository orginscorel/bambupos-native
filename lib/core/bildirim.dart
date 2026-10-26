import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../ortak/ortak.dart';
import 'api.dart';
import 'durum.dart';

/// BİLDİRİM MERKEZİ (Firebase'siz, 2026-10-27).
///
///  • Uygulama açıkken 20 sn'de bir /api/v1/notifications yoklanır; yeni
///    okunmamışlar üstte baloncuk (toast) + titreşim olarak gösterilir.
///  • Arka planda (Android WorkManager / iOS Background Fetch) ~15 dk'da bir
///    yoklanır; yeni olanlar SİSTEM bildirimi olarak düşer.
///  • iOS: APNs cihaz jetonu sunucuya kaydedilir → uygulama kapalıyken de
///    anlık bildirim (sunucu doğrudan APNs'e gönderir).
class BildirimMerkezi {
  static final _yerel = FlutterLocalNotificationsPlugin();
  static final okunmamis = ValueNotifier<int>(0);
  static final liste = ValueNotifier<List<Map<String, dynamic>>>(const []);
  static Timer? _zamanlayici;
  static void Function(String url)? acildi;

  static const _kanal = AndroidNotificationChannel(
    'personel',
    'Personel bildirimleri',
    description: 'Görev, vardiya, izin ve mesai bildirimleri',
    importance: Importance.high,
  );
  static const _apns = MethodChannel('bambumpos/apns');

  static Future<void> kur() async {
    await _yerel.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      ),
      onDidReceiveNotificationResponse: (r) {
        final url = r.payload;
        if (url != null && url.isNotEmpty) acildi?.call(url);
      },
    );
    await _yerel
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_kanal);

    // Arka plan yoklaması YALNIZ Android: iOS'ta BGTaskScheduler işleyicisi uygulama
    // açılışı bitmeden kaydedilmezse iOS uygulamayı kapatıyordu (try/catch yakalayamaz).
    // iPhone'a bildirim zaten APNs ile anlık gelir; yoklamaya gerek yok.
    if (Platform.isAndroid) {
      try {
        await Workmanager().initialize(arkaPlanGorevi);
        await Workmanager().registerPeriodicTask(
          'bildirim-yokla',
          'bildirim-yokla',
          frequency: const Duration(minutes: 15),
          constraints: Constraints(networkType: NetworkType.connected),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
      } catch (_) {
        // Arka plan görevi kurulamazsa ön plan yoklaması yine çalışır.
      }
    }
  }

  /// Oturum açıldıktan sonra: izin iste, yoklamayı başlat, iOS jetonunu kaydet.
  static Future<void> basla() async {
    await izinIste();
    await yokla(ilk: true);
    _zamanlayici?.cancel();
    _zamanlayici = Timer.periodic(const Duration(seconds: 20), (_) => yokla());
    unawaited(_apnsKaydet());
  }

  static void durdur() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
  }

  static Future<bool> izinIste() async {
    if (Platform.isAndroid) {
      return await _yerel
              .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (Platform.isIOS) {
      return await _yerel
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  static Future<void> yokla({bool ilk = false}) async {
    try {
      final r = await Uyg.api.get('/api/v1/notifications') as Map;
      final items = ((r['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      okunmamis.value = (r['unread_count'] as num?)?.toInt() ?? 0;
      liste.value = items;

      final p = Uyg.tercih;
      final sonId = p.getInt('son_bildirim_id') ?? 0;
      final yeniler = items.where((n) => (n['id'] as num).toInt() > sonId && n['read'] != true).toList();
      if (items.isNotEmpty) await p.setInt('son_bildirim_id', items.map((n) => (n['id'] as num).toInt()).reduce((a, b) => a > b ? a : b));
      if (!ilk && sonId > 0) {
        for (final n in yeniler.take(3)) {
          bildir(n['title']?.toString() ?? 'Bildirim', mesaj: n['body']?.toString(), tur: BildirimTur.bilgi);
          HapticFeedback.mediumImpact();
        }
      }
    } on ApiHata {
      // Sessiz: sonraki turda.
    }
  }

  static Future<void> okundu(int id) async {
    try {
      await Uyg.api.post('/api/v1/notifications/$id/read');
    } on ApiHata {
      return;
    }
    await yokla(ilk: true);
  }

  static Future<void> hepsiOkundu() async {
    try {
      await Uyg.api.post('/api/v1/notifications/read-all');
    } on ApiHata {
      return;
    }
    await yokla(ilk: true);
  }

  static Future<void> _apnsKaydet() async {
    if (!Platform.isIOS) return;
    try {
      final jeton = await _apns.invokeMethod<String>('jeton');
      if (jeton == null || jeton.isEmpty) return;
      await Uyg.api.post('/api/v1/portal/cihaz-jetonu', {'platform': 'ios', 'jeton': jeton});
    } catch (_) {
      // APNs izni yok / simülatör.
    }
  }

  static Future<void> sistemBildirimi(int id, String baslik, String? govde, String? url) => _yerel.show(
        id: id,
        title: baslik,
        body: govde,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(_kanal.id, _kanal.name,
              channelDescription: _kanal.description, importance: Importance.high, priority: Priority.high, color: const Color(0xFF5443D2)),
          iOS: const DarwinNotificationDetails(presentSound: true, presentBadge: true),
        ),
        payload: url,
      );
}

/// Arka plan görevi (ayrı isolate): yeni bildirimleri sistem bildirimi yapar.
@pragma('vm:entry-point')
void arkaPlanGorevi() {
  Workmanager().executeTask((_, _) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final p = await SharedPreferences.getInstance();
      final api = await Api.kur(kullaniciAjani: 'BamBumPOS-Personel/1.0 (arka plan)');
      final r = await api.get('/api/v1/notifications') as Map;
      final items = ((r['items'] as List?) ?? const []).whereType<Map>().toList();
      final sonId = p.getInt('son_bildirim_id') ?? 0;
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      var enBuyuk = sonId;
      for (final n in items) {
        final id = (n['id'] as num).toInt();
        if (id > enBuyuk) enBuyuk = id;
        if (id <= sonId || n['read'] == true || sonId == 0) continue;
        await plugin.show(
          id: id,
          title: n['title']?.toString() ?? 'Bildirim',
          body: n['body']?.toString(),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails('personel', 'Personel bildirimleri', importance: Importance.high, priority: Priority.high, color: Color(0xFF5443D2)),
            iOS: DarwinNotificationDetails(presentSound: true),
          ),
          payload: n['url']?.toString(),
        );
      }
      await p.setInt('son_bildirim_id', enBuyuk);
    } catch (_) {
      // Oturum yok / ağ yok: sessiz.
    }
    return true;
  });
}
