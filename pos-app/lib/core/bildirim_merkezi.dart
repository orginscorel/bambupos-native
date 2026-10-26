import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'eski_windows.dart';
import 'ses.dart';

/// Ekranda kayan bildirim (web toast'ı).
class Baloncuk {
  Baloncuk({required this.id, required this.tur, required this.baslik, this.govde, this.adres, this.kalici = false});
  final int id;
  final String tur;
  final String baslik;
  final String? govde;
  final String? adres;
  final bool kalici;
}

/// BİLDİRİM MERKEZİ — web useNotifications.ts'in uygulama karşılığı.
///
/// /api/v1/notifications 15 sn'de bir yoklanır (zil, baloncuk ve ses aynı
/// kaynaktan). İlk yüklemede ses/baloncuk YOK (yalnız kalıcı tipler);
/// sonra yeni gelen okunmamışlar:
///   • uygulama öndeyse: sağ üstte baloncuk (en fazla 3) + kritik tipte bip,
///   • arka plandaysa: sistem bildirimi (sesli; Android / iOS / macOS /
///     Windows 10+), Windows'ta ayrıca görev çubuğu yanıp söner.
/// Sipariş (order_placed) web POS'taki gibi baloncuk olarak çıkmaz — zilde,
/// seste ve sistem bildiriminde kalır.
class BildirimMerkezi extends ChangeNotifier {
  BildirimMerkezi(this._api, this._tercih);

  final Api _api;
  final SharedPreferences _tercih;

  static const kritikTipler = {
    'order_placed', 'service_call', 'item_ready', 'delivery_sla_breach', 'task_assigned', 'leave_requested',
    'leave_decided', 'shift_reminder', 'awaiting_payment', 'debt_transferred', 'order_needs_approval',
  };
  static const kaliciTipler = {'delivery_sla_breach'};
  static const baloncuksuzTipler = {'order_placed'};

  int okunmamis = 0;
  List<Map<String, dynamic>> liste = const [];
  final List<Baloncuk> baloncuklar = [];

  /// Baloncuğa / sistem bildirimine dokununca açılacak adres (kabuk dinler).
  void Function(String adres)? adresAc;

  Set<int>? _gorulen;
  Timer? _zaman;
  bool _sistemHazir = false;
  final _sistem = FlutterLocalNotificationsPlugin();

  bool get sesAcik => _tercih.getString('bildirim_ses') != 'off';
  set sesAcik(bool v) {
    _tercih.setString('bildirim_ses', v ? 'on' : 'off');
    notifyListeners();
  }

  bool get _onde {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  void baslat() {
    _zaman?.cancel();
    _gorulen = null;
    _sistemKur();
    yenile();
    _zaman = Timer.periodic(const Duration(seconds: 15), (_) => yenile());
  }

  void durdur() {
    _zaman?.cancel();
    _zaman = null;
    baloncuklar.clear();
  }

  Future<void> yenile() async {
    try {
      final r = await _api.get('/api/v1/notifications');
      if (r is! Map) return;
      okunmamis = (r['unread_count'] as num?)?.toInt() ?? 0;
      liste = (r['items'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      _yeniler();
      notifyListeners();
    } on ApiHata {
      // Zil sessizce bekler.
    }
  }

  Future<void> hepsiOkundu() async {
    okunmamis = 0;
    notifyListeners();
    try {
      await _api.post('/api/v1/notifications/read-all');
    } on ApiHata {
      // sonraki yoklamada düzelir
    }
    unawaited(yenile());
  }

  Future<void> okundu(int id) async {
    try {
      await _api.post('/api/v1/notifications/$id/read');
    } on ApiHata {
      // sessiz
    }
  }

  void kapat(Baloncuk b) {
    baloncuklar.remove(b);
    notifyListeners();
  }

  void _yeniler() {
    if (_gorulen == null) {
      _gorulen = {for (final n in liste) _id(n)};
      for (final n in liste) {
        if (n['read'] != true && kaliciTipler.contains(n['type'])) _baloncukEkle(n);
      }
      return;
    }
    final taze = <Map<String, dynamic>>[];
    for (final n in liste) {
      if (_gorulen!.add(_id(n)) && n['read'] != true) taze.add(n);
    }
    if (taze.isEmpty) return;

    final kritik = taze.any((n) => kritikTipler.contains(n['type']));
    final onde = _onde;

    if (onde) {
      if (kritik && sesAcik) BildirimSesi.bip();
      final gosterilecek = taze.where((n) => !baloncuksuzTipler.contains(n['type'])).toList();
      final kalici = gosterilecek.where((n) => kaliciTipler.contains(n['type']));
      final normal = gosterilecek.where((n) => !kaliciTipler.contains(n['type'])).toList();
      for (final n in [...kalici, ...normal.take(3)]) {
        _baloncukEkle(n);
      }
      if (normal.length > 3) {
        _baloncukEkle({'id': -DateTime.now().millisecondsSinceEpoch, 'type': 'ozet', 'title': '+${normal.length - 3} yeni bildirim daha', 'body': 'Tümünü görmek için zile dokunun.'});
      }
    } else {
      if (Platform.isWindows) {
        BildirimSesi.dikkatCek();
        if (kritik && sesAcik) BildirimSesi.bip();
      }
      for (final n in taze.take(3)) {
        unawaited(_sistemBildirimi(n, sesli: kritik && sesAcik));
      }
    }
  }

  void _baloncukEkle(Map<String, dynamic> n) {
    final b = Baloncuk(
      id: _id(n),
      tur: '${n['type'] ?? ''}',
      baslik: '${n['title'] ?? ''}',
      govde: n['body']?.toString(),
      adres: (n['url']?.toString().isNotEmpty ?? false) ? n['url'].toString() : null,
      kalici: kaliciTipler.contains(n['type']),
    );
    if (baloncuklar.any((x) => x.id == b.id)) return;
    baloncuklar.insert(0, b);
    if (!b.kalici) {
      Timer(const Duration(seconds: 7), () {
        if (baloncuklar.remove(b)) notifyListeners();
      });
    }
  }

  static int _id(Map n) => (n['id'] as num?)?.toInt() ?? n.hashCode;

  /* ───── Sistem bildirimi ───── */

  Future<void> _sistemKur() async {
    if (_sistemHazir) return;
    // Windows 7 / 8.1'de sistem bildirimi altyapısı (WinRT) yok.
    if (Platform.isWindows && eskiWindows) return;
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows)) return;
    try {
      const darwin = DarwinInitializationSettings(requestAlertPermission: true, requestSoundPermission: true, requestBadgePermission: false);
      await _sistem.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
          windows: WindowsInitializationSettings(
            appName: 'BamBumPOS',
            appUserModelId: 'BamBumPOS.POS',
            guid: '6b1e0c52-7a44-4c5b-9e0b-bb05b05a0001',
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final a = r.payload;
          if (a != null && a.isNotEmpty) adresAc?.call(a);
        },
      );
      if (Platform.isAndroid) {
        await _sistem
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _sistemHazir = true;
    } catch (e) {
      debugPrint('Sistem bildirimi kurulamadı: $e');
    }
  }

  Future<void> _sistemBildirimi(Map<String, dynamic> n, {required bool sesli}) async {
    if (!_sistemHazir) return;
    try {
      await _sistem.show(
        id: _id(n) & 0x7fffffff,
        title: '${n['title'] ?? 'BamBumPOS'}',
        body: n['body']?.toString(),
        payload: n['url']?.toString(),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            sesli ? 'bildirim_sesli' : 'bildirim_sessiz',
            sesli ? 'Önemli bildirimler' : 'Diğer bildirimler',
            channelDescription: 'Sipariş, servis çağrısı, hazır ürün, görev ve mesai bildirimleri',
            importance: sesli ? Importance.high : Importance.low,
            priority: sesli ? Priority.high : Priority.low,
            playSound: sesli,
          ),
          iOS: DarwinNotificationDetails(presentSound: sesli),
          macOS: DarwinNotificationDetails(presentSound: sesli),
        ),
      );
    } catch (e) {
      debugPrint('Sistem bildirimi gösterilemedi: $e');
    }
  }
}
