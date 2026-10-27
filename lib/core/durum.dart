import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'bicim.dart';
import 'tema.dart';

/// Uygulama genel durumu: API istemcisi, gezgin, yerel tercihler ve oturumdaki
/// kişinin adı (eşleme yanıtından; sunucuda patron için "hesap" ucu yok).
class Uyg {
  Uyg._();

  static late Api api;
  static final navigator = GlobalKey<NavigatorState>();
  static late SharedPreferences tercih;

  /// Kabuk açık mı? (401 yalnız oturumlu alanda eşleme ekranına döndürür.)
  static bool oturumlu = false;

  static String get ad => tercih.getString('ad') ?? '';
  static String get ilkAd => ad.trim().split(RegExp(r'\s+')).first;
  static Future<void> adKaydet(String a) => tercih.setString('ad', a);

  /// Son bilinen açık iş günü (overview `range.from`, period=day). "Dün" ve
  /// "Bu hafta" aralıkları buna göre hesaplanır — gün sonu alınmamışsa sunucu
  /// takvimden farklı bir günü "bugün" sayar.
  static DateTime get isGunu {
    final d = Bicim.gunCoz(tercih.getString('is_gunu'));
    final n = DateTime.now();
    return d ?? DateTime(n.year, n.month, n.day);
  }

  static Future<void> isGunuKaydet(String ymd) => tercih.setString('is_gunu', ymd);

  static Future<void> kur({SharedPreferences? p, Api? hazirApi}) async {
    tercih = p ?? await SharedPreferences.getInstance();
    final t = tercih.getString('tema');
    temaKipi.value = t == 'dark' ? ThemeMode.dark : t == 'light' ? ThemeMode.light : ThemeMode.system;
    api = hazirApi ?? await Api.kur(kullaniciAjani: 'BamBumPOS-Patron/1.0 (Flutter)');
  }

  /// Oturum var mı? Hafif bir oturumlu uca (bildirimler) sorar: 200 → var,
  /// 401 → yok. Bağlantı hatası yukarı fırlar (açılış "tekrar dene" gösterir).
  static Future<bool> oturumVarMi() async {
    try {
      await api.get('/api/v1/notifications');
      return true;
    } on ApiHata catch (e) {
      if (e.oturumYok) return false;
      // 403/404: oturum var ama bildirim ucu kapalı — yine de içeri al.
      if (e.yetkiYok || e.kod == 404) return true;
      rethrow;
    }
  }

  static Future<void> temaDegistir(ThemeMode m) async {
    temaKipi.value = m;
    await tercih.setString('tema', m == ThemeMode.dark ? 'dark' : m == ThemeMode.light ? 'light' : 'system');
  }
}
