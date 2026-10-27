import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'onbellek.dart';
import 'tema.dart';

/// Uygulama genel durumu: API istemcisi + oturumdaki personelin kimliği.
///
/// `hesap` = GET /api/v1/portal/hesap (ad, izinler, eklentiler, telefon …).
/// Oturum düşerse (401) kabuk eşleme ekranına döner.
class Uyg {
  Uyg._();

  static late Api api;
  static final navigator = GlobalKey<NavigatorState>();
  static final hesap = ValueNotifier<Map<String, dynamic>?>(null);
  /// Mesai/mola değişti (QR işlemi başarılı) → açık ekranlar durumu HEMEN yeniler.
  static final mesaiDegisti = ValueNotifier<int>(0);
  static late SharedPreferences tercih;

  static String get ad => hesap.value?['ad']?.toString() ?? '';
  static String get ilkAd => ad.trim().split(RegExp(r'\s+')).first;
  static String get basHarfler {
    final p = ad.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2);
    final s = p.map((e) => e.characters.first.toUpperCase()).join();
    return s.isEmpty ? '•' : s;
  }

  static bool izin(String k) => (hesap.value?['izinler'] as List?)?.contains(k) ?? false;
  /// Yönetici modu (Ekibim): personel görme/yönetme ya da görev atama yetkisi.
  static bool get yonetici => izin('staff.view') || izin('staff.manage') || izin('tasks.assign');
  static bool eklenti(String k) => (hesap.value?['eklentiler'] as Map?)?[k] == true;

  static Future<void> kur() async {
    // Tercihler + API istemcisi (çerez dizini) birlikte okunur.
    final sonuc = await Future.wait<Object>([
      SharedPreferences.getInstance(),
      Api.kur(kullaniciAjani: 'BamBumPOS-Personel/1.0 (Flutter)'),
    ]);
    tercih = sonuc[0] as SharedPreferences;
    api = sonuc[1] as Api;
    final t = tercih.getString('tema');
    temaKipi.value = t == 'dark' ? ThemeMode.dark : t == 'light' ? ThemeMode.light : ThemeMode.system;
    Onbellek.kur(tercih);
  }

  static const _hesapAnahtari = '/api/v1/portal/hesap';

  /// Son bilinen hesap (açılışta ağ beklemeden kabuğa geçmek için). 30 günden
  /// eskiyse yok sayılır; oturum düşmüşse arkadan gelen 401 eşleme ekranına döndürür.
  static Map<String, dynamic>? get onbellekHesap => Onbellek.harita(_hesapAnahtari, enEski: const Duration(days: 30));

  /// İşletmenin mesai konum kuralı (hesap › mesai_konum). Alan yoksa (eski
  /// sunucu) zorunlu değil. Kural yalnız web konsolunda açılıp kapatılır.
  static bool get konumZorunlu => (hesap.value?['mesai_konum'] as Map?)?['zorunlu'] == true;
  static int? get konumYaricap => ((hesap.value?['mesai_konum'] as Map?)?['yaricap_m'] as num?)?.round();

  static DateTime _hesapZamani = DateTime.fromMillisecondsSinceEpoch(0);

  /// Oturum var mı? Varsa kimliği yükler.
  static Future<bool> hesapYukle() async {
    try {
      final r = await api.get(_hesapAnahtari);
      final yeni = Map<String, dynamic>.from(r as Map);
      // Başka personel eşlendiyse eski kişinin önbelleği gösterilmesin.
      final eskiId = onbellekHesap?['id'];
      if (eskiId != null && eskiId != yeni['id']) await Onbellek.temizle();
      hesap.value = yeni;
      _hesapZamani = DateTime.now();
      Onbellek.yaz(_hesapAnahtari, yeni);
      return true;
    } on ApiHata catch (e) {
      if (e.oturumYok) {
        await Onbellek.temizle();
        return false;
      }
      rethrow;
    }
  }

  /// Uygulamaya dönünce hafif tazeleme (en çok 5 dk'da bir): konsolda açılan
  /// konum kuralı gibi değişiklikler açık uygulamalara da ulaşsın. Hata sessiz.
  static Future<void> hesapTazele({Duration enAz = const Duration(minutes: 5)}) async {
    if (hesap.value == null || DateTime.now().difference(_hesapZamani) < enAz) return;
    _hesapZamani = DateTime.now(); // ağ yavaşsa üst üste istek atma
    try {
      await hesapYukle();
    } catch (_) {
      // Bir sonraki dönüşte yeniden denenir.
    }
  }

  static Future<void> temaDegistir(ThemeMode m) async {
    temaKipi.value = m;
    await tercih.setString('tema', m == ThemeMode.dark ? 'dark' : m == ThemeMode.light ? 'light' : 'system');
    if (m != ThemeMode.system) {
      try {
        await api.put('/api/v1/auth/preferences', {'theme': m == ThemeMode.dark ? 'dark' : 'light'});
      } on ApiHata {
        // Yerel tercih yeterli.
      }
    }
  }

  static Future<void> cikis() async {
    try {
      await api.post('/api/v1/auth/logout');
    } on ApiHata {
      // Yine de yerelde çık.
    }
    await api.cerezleriSil();
    await Onbellek.temizle();
    hesap.value = null;
  }
}

/// Dakikayı "2s 15dk" biçimine çevirir (web ile aynı).
String dakikaYaz(num dk) {
  final m = dk.round().clamp(0, 1 << 30);
  final s = m ~/ 60;
  final k = m % 60;
  if (s > 0 && k > 0) return '${s}s ${k}dk';
  if (s > 0) return '${s}s';
  return '${k}dk';
}

/// Kuruşu "₺1.234,50" biçimine çevirir.
String paraYaz(num kurus) {
  final tl = kurus / 100;
  final tam = tl.truncate().abs();
  final ondalik = ((tl.abs() - tam) * 100).round().toString().padLeft(2, '0');
  final s = tam.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${tl < 0 ? '-' : ''}₺$s,$ondalik';
}
