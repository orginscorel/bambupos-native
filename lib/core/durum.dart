import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
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
    tercih = await SharedPreferences.getInstance();
    final t = tercih.getString('tema');
    temaKipi.value = t == 'dark' ? ThemeMode.dark : t == 'light' ? ThemeMode.light : ThemeMode.system;
    api = await Api.kur(kullaniciAjani: 'BamBumPOS-Personel/1.0 (Flutter)');
  }

  /// Oturum var mı? Varsa kimliği yükler.
  static Future<bool> hesapYukle() async {
    try {
      final r = await api.get('/api/v1/portal/hesap');
      hesap.value = Map<String, dynamic>.from(r as Map);
      return true;
    } on ApiHata catch (e) {
      if (e.oturumYok) return false;
      rethrow;
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
