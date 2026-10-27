import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../ortak/ortak.dart';
import 'api.dart';
import 'durum.dart';
import 'hatirlatma.dart';

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
  /// Vardiya planlandı/değişti/iptal bildirimi geldi → Shift ekranı hemen tazelenir.
  static final vardiyaDegisti = ValueNotifier<int>(0);
  static bool _apnsKayitli = false;
  static final liste = ValueNotifier<List<Map<String, dynamic>>>(const []);
  static Timer? _zamanlayici;
  static void Function(String url)? acildi;
  static String? _bekleyenUrl;
  static bool _acilisIslendi = false;

  /// Bildirim kanalı. Android'de kanal ayarları (ses/titreşim/önem) cihazda İLK
  /// oluşturulduğunda sabitlenir → titreşim deseni eklemek için YENİ kimlik
  /// ('personel_v2'); eskisi ('personel') kurulumda silinir.
  static const kanalId = 'personel_v2';
  static const _eskiKanal = 'personel';
  static final kanal = AndroidNotificationChannel(
    kanalId,
    'Personel bildirimleri',
    description: 'Görev, shift, izin ve mesai bildirimleri',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
  );

  static NotificationDetails get ayrinti => NotificationDetails(
        android: AndroidNotificationDetails(kanal.id, kanal.name,
            channelDescription: kanal.description,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            vibrationPattern: kanal.vibrationPattern,
            color: const Color(0xFF5443D2)),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true, presentBadge: true),
      );

  /// Yeni kanalı kur, eskisini sil (ön plan + arka plan görevi).
  static Future<void> kanallariKur(FlutterLocalNotificationsPlugin p) async {
    final a = p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (a == null) return;
    await a.createNotificationChannel(kanal);
    await a.createNotificationChannel(MesaiHatirlatma.kanal);
    try {
      await a.deleteNotificationChannel(channelId: _eskiKanal);
    } catch (_) {}
  }
  static const _apns = MethodChannel('bambumpos/apns');

  static Future<void>? _kurulum;

  /// Eklenti kurulumu (tek sefer). main() beklemeden başlatır; eklentiyi
  /// kullanan her yol önce bunu bekler.
  static Future<void> kur() => _kurulum ??= _kur().catchError((Object _) {
        // Eklenti kurulamadı (ör. desteklenmeyen ortam): yoklama yine çalışır.
      });

  static Future<void> _kur() async {
    MesaiHatirlatma.tercihOku(Uyg.tercih);
    await _yerel.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          // Uygulama öndeyken de afiş + ses + rozet.
          defaultPresentAlert: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
          defaultPresentSound: true,
          defaultPresentBadge: true,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final url = r.payload;
        if (url == null || url.isEmpty) return;
        if (acildi != null) {
          acildi!(url);
        } else {
          _bekleyenUrl = url; // kabuk henüz kurulmadı → basla() açar
        }
      },
    );
    await kanallariKur(_yerel);
    if (Platform.isIOS) _apns.setMethodCallHandler(_apnsCagri);

    // Arka plan yoklaması YALNIZ Android: iOS'ta BGTaskScheduler işleyicisi uygulama
    // açılışı bitmeden kaydedilmezse iOS uygulamayı kapatıyordu (try/catch yakalayamaz).
    // iPhone'a bildirim zaten APNs ile anlık gelir; yoklamaya gerek yok.
    // Açılış ekranı çizilirken platform iş parçacığını meşgul etmesin: biraz sonra.
    if (Platform.isAndroid) {
      unawaited(Future<void>.delayed(const Duration(seconds: 4), () async {
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
      }));
    }
  }

  /// Ön planda yoklama aralığı. (Arka planda yoklama YOK: Android'de
  /// WorkManager, iPhone'da APNs devralır.)
  static const yoklamaAraligi = Duration(seconds: 30);
  static DateTime _sonYoklama = DateTime.fromMillisecondsSinceEpoch(0);

  /// Oturum açıldıktan sonra: yoklamayı başlat, izin iste, iOS jetonunu kaydet.
  static Future<void> basla() async {
    await kur();
    unawaited(_acilisBildirimi());
    devam(); // ilk yoklama + zamanlayıcı (izin penceresini beklemez)
    await izinIste();
    unawaited(_apnsKaydet());
    unawaited(hatirlatmaTazele());
  }

  /// Uygulama öne geldi: son yoklama eskiyse hemen yokla, zamanlayıcıyı kur.
  static void devam() {
    if (DateTime.now().difference(_sonYoklama) > const Duration(seconds: 10)) unawaited(yokla(ilk: _sonYoklama.millisecondsSinceEpoch == 0));
    _zamanlayici?.cancel();
    _zamanlayici = Timer.periodic(yoklamaAraligi, (_) => yokla());
  }

  /// Uygulama bir bildirime (ör. Shift hatırlatması → /qr-okut) dokunularak açıldıysa o ekrana git.
  static Future<void> _acilisBildirimi() async {
    var url = _bekleyenUrl;
    _bekleyenUrl = null;
    if (url == null && !_acilisIslendi) {
      _acilisIslendi = true;
      try {
        final d = await _yerel.getNotificationAppLaunchDetails();
        if (d?.didNotificationLaunchApp ?? false) url = d!.notificationResponse?.payload;
      } catch (_) {}
      if (url == null && Platform.isIOS) {
        try {
          url = await _apns.invokeMethod<String>('acilisUrl'); // APNs dokunuşuyla soğuk açılış
        } catch (_) {}
      }
    }
    if (url == null || url.isEmpty) return;
    final u = url;
    WidgetsBinding.instance.addPostFrameCallback((_) => acildi?.call(u));
  }

  /// Shift hatırlatmalarını (Android, yerel alarm) yeniden kurar.
  /// `vardiyalar` = schedule yanıtındaki `shifts` (Shift ekranı verirse ağa gitmez).
  static Future<void> hatirlatmaEsitle({List<Map>? vardiyalar}) async {
    await kur();
    await MesaiHatirlatma.esitle(eklenti: _yerel, p: Uyg.tercih, api: Uyg.api, vardiyalar: vardiyalar);
  }

  /// Öne gelişte: Shift planı en çok 15 dk'da bir yeniden çekilir (her
  /// dönüşte ağ + 28 alarmı silip kurmak gereksizdi).
  static DateTime _sonEsitleme = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> hatirlatmaTazele() {
    if (DateTime.now().difference(_sonEsitleme) < const Duration(minutes: 15)) return Future.value();
    _sonEsitleme = DateTime.now();
    return hatirlatmaEsitle();
  }

  /// Bildirimler ekranındaki "Mesai hatırlatmaları" anahtarı.
  static Future<void> hatirlatmaAyarla(bool v) async {
    await kur();
    await MesaiHatirlatma.ayarla(v, eklenti: _yerel, p: Uyg.tercih, api: Uyg.api);
  }

  static void durdur() {
    _zamanlayici?.cancel();
    _zamanlayici = null;
  }

  /// Telefonun GERÇEK bildirim izni (sormadan okunur). null = bilinmiyor.
  /// Bildirimler sayfası bunu gösterir; eskiden durum her girişte boş
  /// başlıyordu → "açık mı değil mi" belirsizdi, her seferinde yeniden soruyordu.
  static final izin = ValueNotifier<bool?>(null);

  static Future<bool?> izinDurumu() async {
    bool? v;
    try {
      if (Platform.isAndroid) {
        v = await _yerel.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.areNotificationsEnabled();
      } else if (Platform.isIOS) {
        v = (await _yerel.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.checkPermissions())?.isEnabled;
      }
    } catch (_) {
      v = null;
    }
    izin.value = v;
    return v;
  }

  static Future<bool> izinIste() async {
    if (Platform.isAndroid) {
      await _yerel.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await _yerel
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    // İstek sonucunu değil telefonun son durumunu esas al
    return await izinDurumu() ?? false;
  }

  static String? _etag;
  static String? _sonImza;

  static Future<void>? _yoklaniyor;

  /// Aynı anda tek yoklama (zamanlayıcı + ekran yenilemesi çakışırsa birleşir).
  static Future<void> yokla({bool ilk = false}) => _yoklaniyor ??= _yokla(ilk).whenComplete(() => _yoklaniyor = null);

  static Future<void> _yokla(bool ilk) async {
    _sonYoklama = DateTime.now();
    try {
      // ETag'li: sunucu destekliyorsa değişmeyen liste 304 ile boş döner.
      final y = await Uyg.api.getEtagli('/api/v1/notifications', _etag);
      if (y == null) return; // 304: değişiklik yok
      _etag = y.veri is Map ? y.etag : null;
      final r = y.veri as Map;
      final items = ((r['items'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      okunmamis.value = (r['unread_count'] as num?)?.toInt() ?? 0;
      // Aynı liste yeniden geldiyse dinleyen ekranlar boşuna yeniden çizilmesin.
      final imza = items.map((n) => '${n['id']}:${n['read']}').join(',');
      if (imza != _sonImza || liste.value.length != items.length) {
        _sonImza = imza;
        liste.value = items;
      }

      final p = Uyg.tercih;
      final sonId = p.getInt('son_bildirim_id') ?? 0;
      final yeniler = items.where((n) => (n['id'] as num).toInt() > sonId && n['read'] != true).toList();
      if (items.isNotEmpty) {
        final enBuyuk = items.map((n) => (n['id'] as num).toInt()).reduce((a, b) => a > b ? a : b);
        if (enBuyuk != sonId) await p.setInt('son_bildirim_id', enBuyuk);
      }
      // Vardiya değişikliği: 15 dk sınırını beklemeden planı çek, hatırlatmaları
      // yeniden kur, açık Shift ekranını tazele (ilk yoklamada da — kaçırılmasın).
      if (sonId > 0 && yeniler.any(vardiyaBildirimi)) {
        _sonEsitleme = DateTime.now();
        unawaited(hatirlatmaEsitle());
        vardiyaDegisti.value++;
      }
      if (!ilk && sonId > 0) {
        for (final n in yeniler.take(3)) {
          if (MesaiHatirlatma.baslikMi(n['title'])) {
            // Android: yerel alarm zaten çaldı (ve ön planda baloncuk gösterdi) → tekrar etme.
            if (MesaiHatirlatma.yerelZamanlama && MesaiHatirlatma.acik.value) continue;
            MesaiHatirlatma.uyar(n['title'].toString(), n['body']?.toString());
            continue;
          }
          // iPhone'da APNs afişi (ses + titreşimle) zaten göründü → ikinci kez baloncuk yok.
          if (Platform.isIOS && _apnsKayitli && izin.value == true) continue;
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
    await _yoklaniyor; // eski (işaretlemeden önceki) yoklama bitsin
    await yokla(ilk: true);
  }

  static Future<void> hepsiOkundu() async {
    try {
      await Uyg.api.post('/api/v1/notifications/read-all');
    } on ApiHata {
      return;
    }
    await _yoklaniyor; // eski (işaretlemeden önceki) yoklama bitsin
    await yokla(ilk: true);
  }

  static Future<void> _apnsKaydet() async {
    if (!Platform.isIOS) return;
    try {
      final jeton = await _apns.invokeMethod<String>('jeton');
      if (jeton == null || jeton.isEmpty) return;
      await Uyg.api.post('/api/v1/portal/cihaz-jetonu', {'platform': 'ios', 'jeton': jeton});
      _apnsKayitli = true;
    } catch (_) {
      // APNs izni yok / simülatör.
    }
  }

  static Future<void> sistemBildirimi(int id, String baslik, String? govde, String? url) => _yerel.show(
        id: id,
        title: baslik,
        body: govde,
        notificationDetails: ayrinti,
        payload: url,
      );

  /// iOS: APNs bildirimine dokunuldu (AppDelegate → 'acildi').
  static Future<dynamic> _apnsCagri(MethodCall c) async {
    if (c.method != 'acildi') return null;
    final url = c.arguments?.toString() ?? '';
    if (url.isEmpty) return true;
    if (acildi != null) {
      acildi!(url);
    } else {
      _bekleyenUrl = url;
    }
    return true;
  }
}

/// Bildirimin uygulama içi adresi (`url` ya da `data.url`).
String? bildirimUrl(Map n) {
  final u = n['url'] ?? (n['data'] is Map ? (n['data'] as Map)['url'] : null);
  final s = u?.toString();
  return s == null || s.isEmpty ? null : s;
}

/// "Yeni vardiya / Vardiyan değişti / Vardiya iptal" bildirimi mi? (url /vardiyam)
bool vardiyaBildirimi(Map n) {
  final u = bildirimUrl(n);
  final yol = u == null ? null : (Uri.tryParse(u)?.path ?? u);
  return yol == '/vardiyam' || yol == '/shift' || (n['data'] is Map && (n['data'] as Map)['shift_id'] != null);
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
      await BildirimMerkezi.kanallariKur(plugin);
      final hatirlatmaAcik = p.getBool(MesaiHatirlatma.tercihAnahtari) ?? true;
      var enBuyuk = sonId;
      for (final n in items) {
        final id = (n['id'] as num).toInt();
        if (id > enBuyuk) enBuyuk = id;
        if (id <= sonId || n['read'] == true || sonId == 0) continue;
        // Shift hatırlatması: yerel alarm zaten sesli + titreşimli çaldı.
        if (hatirlatmaAcik && Platform.isAndroid && MesaiHatirlatma.baslikMi(n['title'])) continue;
        await plugin.show(
          id: id,
          title: n['title']?.toString() ?? 'Bildirim',
          body: n['body']?.toString(),
          notificationDetails: BildirimMerkezi.ayrinti,
          payload: bildirimUrl(n),
        );
      }
      await p.setInt('son_bildirim_id', enBuyuk);
      // Shift değişmiş olabilir (vardiya planlandı/değişti/iptal bildirimi dahil):
      // yerel hatırlatmaları her turda plandan tazele; plan aynıysa imza sayesinde dokunulmaz.
      await MesaiHatirlatma.esitle(eklenti: plugin, p: p, api: api, onPlan: false);
    } catch (_) {
      // Oturum yok / ağ yok: sessiz.
    }
    return true;
  });
}
