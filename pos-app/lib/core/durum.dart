import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'modeller.dart';

enum Asama { acilis, baglantiYok, aktivasyon, pin, calisma }

/// Uygulamanın tek durum kaynağı.
///
/// Kural (işletme kararı 2026-10-26): CİHAZ hangi ekranın açılacağını,
/// PIN'le giren KİŞİ yetkiyi belirler. Cihazda "çıkış" yoktur; eşleme
/// yalnız yönetim konsolunda Cihazlar → Kaldır ile düşer (sunucu 401/403
/// döner, uygulama kendiliğinden aktivasyon ekranına geçer).
class UygulamaDurumu extends ChangeNotifier {
  UygulamaDurumu._(this.api, this.surum, this._tercih, this._onbellekDizini);

  final Api api;
  final String surum;
  final SharedPreferences _tercih;
  final String _onbellekDizini;

  Asama asama = Asama.acilis;
  Oturum? oturum;
  String? sonHata;

  Timer? _kalpAtisi;
  Timer? _yenidenDene;

  @visibleForTesting
  factory UygulamaDurumu.test(Api api, SharedPreferences tercih, String dizin) {
    final d = UygulamaDurumu._(api, '1.0.0', tercih, dizin);
    api.oturumDustu = d._oturumDustu;
    return d;
  }

  static Future<UygulamaDurumu> kur() async {
    final bilgi = await PackageInfo.fromPlatform();
    final tercih = await SharedPreferences.getInstance();
    final dizin = await getApplicationSupportDirectory();
    final api = await Api.kur(kullaniciAjani: _kullaniciAjani(bilgi.version));
    final d = UygulamaDurumu._(api, bilgi.version, tercih, dizin.path);
    api.oturumDustu = d._oturumDustu;
    return d;
  }

  static String _kullaniciAjani(String surum) {
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'macOS',
      _ => Platform.operatingSystem,
    };
    return 'BamBumPOS/$surum ($platform; ${Platform.operatingSystemVersion.split(' ').take(3).join(' ')}) BamBumPOS-Native';
  }

  /* ───────── Akış ───────── */

  Future<void> baslat() async {
    await oturumuYenile(ilk: true);
    _kalpAtisi?.cancel();
    _kalpAtisi = Timer.periodic(const Duration(seconds: 45), (_) => _nabiz());
  }

  /// Sunucudan cihaz + operatör + yetkiyi okur ve doğru ekrana geçer.
  Future<void> oturumuYenile({bool ilk = false}) async {
    try {
      final veri = await api.get('/api/v1/uygulama/oturum');
      oturum = Oturum((veri as Map).cast<String, dynamic>());
      sonHata = null;
      _gec(oturum!.operatorVar ? Asama.calisma : Asama.pin);
    } on ApiHata catch (e) {
      if (e.oturumYok || e.yetkiYok) {
        // Cihaz hiç eşlenmemiş ya da yönetici cihazı kaldırmış.
        if (e.yetkiYok) await api.cerezleriSil();
        oturum = null;
        _gec(Asama.aktivasyon);
      } else if (e.baglantiYok || (e.kod ?? 0) >= 500) {
        sonHata = e.mesaj;
        // Çalışırken kısa kopma ekranı DEĞİŞTİRMEZ; yalnız ilk açılışta bekleme ekranı.
        if (ilk || oturum == null) {
          _gec(Asama.baglantiYok);
          _yenidenDene?.cancel();
          _yenidenDene = Timer(const Duration(seconds: 4), () => oturumuYenile(ilk: true));
        }
      } else {
        sonHata = e.mesaj;
        notifyListeners();
      }
    }
  }

  /// Aktivasyon tamamlandı → oturum çerezi alındı.
  Future<void> aktiveEdildi() => oturumuYenile();

  /// Personel PIN'i ile operatör olur.
  Future<void> pinIleGir(String pin) async {
    await api.post('/terminal/operator/pin', {'pin': pin});
    await oturumuYenile();
  }

  /// Ekranı kilitler: operatör düşer, cihaz eşli kalır (PIN ekranı).
  Future<void> kilitle() async {
    try {
      await api.post('/terminal/operator/clear');
    } on ApiHata {
      // Bağlantı yoksa bile ekran kilitlenir; sunucuda operatör boşta kalma süresiyle düşer.
    }
    if (oturum != null) {
      final ham = Map<String, dynamic>.from(oturum!.ham)..['operator'] = null;
      oturum = Oturum(ham);
    }
    _gec(Asama.pin);
  }

  /// İşlem "önce personel seçin" / 401 derse ekran durumu tazelenir.
  void islemHatasi(ApiHata e) {
    if (e.kod == 422 && e.mesaj.toLowerCase().contains('personel')) {
      oturumuYenile();
    }
  }

  void _oturumDustu() {
    if (asama == Asama.aktivasyon) return;
    oturum = null;
    _gec(Asama.aktivasyon);
  }

  Future<void> _nabiz() async {
    if (asama == Asama.aktivasyon || asama == Asama.acilis) return;
    try {
      await api.post('/terminal/heartbeat');
    } on ApiHata {
      // Kalp atışı kaçarsa bir sonraki turda denenir.
    }
    // Operatörün boşta kalma süresi dolduysa / yetkisi değiştiyse yansısın.
    await oturumuYenile();
  }

  void _gec(Asama yeni) {
    asama = yeni;
    notifyListeners();
  }

  /* ───────── Basit disk önbelleği (katalog, pano) ───────── */

  Future<Map<String, dynamic>?> onbellekOku(String ad) async {
    try {
      final f = File('$_onbellekDizini${Platform.pathSeparator}$ad.json');
      if (!await f.exists()) return null;
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> onbellekYaz(String ad, Map<String, dynamic> veri) async {
    try {
      final f = File('$_onbellekDizini${Platform.pathSeparator}$ad.json');
      final gecici = File('${f.path}.tmp');
      await gecici.writeAsString(jsonEncode(veri), flush: true);
      await gecici.rename(f.path);
    } catch (_) {
      // Önbellek yazılamazsa uygulama yine çalışır.
    }
  }

  String? tercihOku(String k) => _tercih.getString(k);
  Future<void> tercihYaz(String k, String? v) async =>
      v == null ? await _tercih.remove(k) : await _tercih.setString(k, v);

  /// Uygulama ön plana döndü: arada operatör düşmüş / cihaz kaldırılmış olabilir.
  void onPlanaGeldi() {
    if (asama != Asama.acilis) oturumuYenile();
  }

  @override
  void dispose() {
    _kalpAtisi?.cancel();
    _yenidenDene?.cancel();
    super.dispose();
  }
}
