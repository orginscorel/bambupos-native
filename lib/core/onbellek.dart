import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// SON VERİ ÖNBELLEĞİ (önce eldekini göster, sonra tazele).
///
/// Ana sayfa, Görevler ve Shift ekranları açılırken son başarılı yanıtı
/// HEMEN çizer, arkadan sunucudan tazeler. Uygulama kapatılıp açılsa da
/// kalır (SharedPreferences zaten açılışta belleğe okunuyor → okuma bedava).
///
/// - Yazma birleştirilir (2 sn): sık yoklamalar diske her seferinde yazmaz.
/// - Oturum kapanınca / başka personel eşlenince [temizle] çağrılır.
/// - Yalnız küçük JSON yanıtlar içindir (birkaç KB).
class Onbellek {
  Onbellek._();

  static const _anahtar = 'bbp_onbellek_v1';
  static SharedPreferences? _p;
  static Map<String, dynamic>? _bellek;
  static Timer? _yazZamani;

  /// Açılışta (Uyg.kur) bir kez. Bozuk veri sessizce atılır.
  static void kur(SharedPreferences p) {
    _p = p;
    _bellek = null;
  }

  static Map<String, dynamic> get _harita {
    if (_bellek != null) return _bellek!;
    var m = <String, dynamic>{};
    try {
      final ham = _p?.getString(_anahtar);
      if (ham != null && ham.isNotEmpty) m = Map<String, dynamic>.from(jsonDecode(ham) as Map);
    } catch (_) {
      m = {};
    }
    return _bellek = m;
  }

  /// Önbellekteki veri ve kaydedildiği an; [enEski]'den eskiyse null.
  static ({dynamic veri, DateTime zaman})? oku(String anahtar, {Duration enEski = const Duration(days: 2)}) {
    if (_p == null) return null; // kurulmadı (testler): önbellek yok
    final k = _harita[anahtar];
    if (k is! Map) return null;
    final ms = (k['t'] as num?)?.toInt();
    if (ms == null) return null;
    final zaman = DateTime.fromMillisecondsSinceEpoch(ms);
    final yas = DateTime.now().difference(zaman);
    if (yas > enEski || yas.isNegative) return null;
    return (veri: k['v'], zaman: zaman);
  }

  /// Map yanıtı kopyalayarak okur (ekran değiştirse de önbellek bozulmasın).
  static Map<String, dynamic>? harita(String anahtar, {Duration enEski = const Duration(days: 2)}) {
    final o = oku(anahtar, enEski: enEski)?.veri;
    return o is Map ? Map<String, dynamic>.from(o) : null;
  }

  static void yaz(String anahtar, Object? veri) {
    if (veri == null || _p == null) return;
    _harita[anahtar] = {'t': DateTime.now().millisecondsSinceEpoch, 'v': veri};
    _yazZamani ??= Timer(const Duration(seconds: 2), _diskeYaz);
  }

  static void _diskeYaz() {
    _yazZamani = null;
    final p = _p;
    final m = _bellek;
    if (p == null || m == null) return;
    try {
      p.setString(_anahtar, jsonEncode(m));
    } catch (_) {
      // JSON'a çevrilemeyen veri: önbellek bu tur yazılmaz.
    }
  }

  static Future<void> temizle() async {
    _yazZamani?.cancel();
    _yazZamani = null;
    _bellek = {};
    try {
      await _p?.remove(_anahtar);
    } catch (_) {}
  }
}
