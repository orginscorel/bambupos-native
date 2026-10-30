import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ajan.dart';
import 'bildirim_merkezi.dart';
import 'api.dart';
import 'kalici_dosya.dart';
import 'modeller.dart';
import 'senkron_merkezi.dart';

enum Asama { acilis, baglantiYok, aktivasyon, pin, calisma }

/// Kurtarma denemesinin sonucu (bkz. UygulamaDurumu._kurtar).
enum KurtarmaSonucu { basarili, anahtarYok, reddedildi, gecici }

/// Uygulamanın tek durum kaynağı.
///
/// Kural (işletme kararı 2026-10-26): CİHAZ hangi ekranın açılacağını,
/// PIN'le giren KİŞİ yetkiyi belirler. Cihazda "çıkış" yoktur; eşleme
/// yalnız yönetim konsolunda Cihazlar → Kaldır ile düşer (sunucu 401/403
/// döner, uygulama kendiliğinden aktivasyon ekranına geçer).
///
/// KURTARMA (2026-10-30): 401 tek başına "cihaz kaldırıldı" demek DEĞİLDİR —
/// çerezler cihazda kaybolmuş da olabilir. Cihaz elindeki kurtarma
/// anahtarıyla önce oturumunu geri almayı dener; yalnız sunucu reddederse
/// (403/404/422) aktivasyona geçilir. Bağlantı yoksa bekleme ekranı.
class UygulamaDurumu extends ChangeNotifier {
  UygulamaDurumu._(this.api, this.surum, this._tercih, this._onbellekDizini);

  final Api api;
  final String surum;
  final SharedPreferences _tercih;
  final String _onbellekDizini;

  Asama asama = Asama.acilis;
  Oturum? oturum;
  String? sonHata;

  /// Ağ taraması + fiş basma (cihaz oturumu doğrulanınca başlar).
  YazdirmaAjani? ajan;

  /// Zil + baloncuk + ses + sistem bildirimi (kabuk açıkken yoklar).
  late final BildirimMerkezi bildirim = BildirimMerkezi(api, _tercih);

  /// Adisyon değişim akışı (uzun yoklama + bu cihazın yazmaları). Kabuk
  /// açıkken çalışır; pano/adisyon/kasa ekranları abone olur.
  late final SenkronMerkezi senkron = SenkronMerkezi(api);

  Timer? _kalpAtisi;
  Timer? _yenidenDene;

  /* ───────── Kurtarma anahtarı durumu ───────── */
  late final KurtarmaDeposu _kurtarmaDeposu = KurtarmaDeposu(_onbellekDizini);
  KurtarmaAnahtari? _anahtar;
  bool _anahtarOkundu = false;
  bool _anahtarAliniyor = false;
  DateTime? _anahtarSonDeneme;
  /// Sunucu bu cihaz için anahtar üretmiyor (eski /baglan eşlemesi): bu çalışmada tekrar sorma.
  int? _anahtarDesteklenmiyor;
  Future<KurtarmaSonucu>? _kurtarmaSuruyor;
  bool _kayipIsleniyor = false;
  DateTime? _sonBasariliKurtarma;

  /// Kurtarma "geçici" bittiğinde (bağlantı yok / kilitli / askı) yeniden deneme aralığı.
  @visibleForTesting
  Duration kurtarmaBekleme = const Duration(seconds: 30);
  Duration _geciciBekleme = const Duration(seconds: 30);
  Timer? _bostaDenetim;

  /// BOŞTA KİLİT (web useTerminalIdleLock ile aynı, 3 dk): personel girişliyken
  /// ekrana dokunulmazsa operatör düşer, PIN ekranı gelir.
  static const bostaKilitSuresi = Duration(minutes: 3);
  DateTime _sonEtkinlik = DateTime.now();

  /// Sürekli açık kalması gereken ekranlar (Mesai QR) kilidi erteler.
  int kilitMuaf = 0;

  /// Dokunma / fare / klavye — main.dart'taki dinleyici çağırır.
  void etkinlik() => _sonEtkinlik = DateTime.now();

  void _bostaDenetle() {
    if (asama != Asama.calisma || !(oturum?.operatorVar ?? false)) return;
    if (kilitMuaf > 0) {
      _sonEtkinlik = DateTime.now();
      return;
    }
    if (DateTime.now().difference(_sonEtkinlik) >= bostaKilitSuresi) kilitle();
  }

  @visibleForTesting
  factory UygulamaDurumu.test(Api api, SharedPreferences tercih, String dizin) {
    final d = UygulamaDurumu._(api, '1.0.0', tercih, dizin);
    api.oturumDustu = d._oturumDustu;
    api.yazmaBasarili = d._yazmaBasarili;
    return d;
  }

  static Future<UygulamaDurumu> kur() async {
    // Birbirinden bağımsız platform çağrıları AYNI ANDA (açılış süresi).
    final bilgiF = PackageInfo.fromPlatform();
    final tercihF = SharedPreferences.getInstance();
    final dizinF = getApplicationSupportDirectory();
    final bilgi = await bilgiF;
    final basliklarF = _cihazBasliklari(bilgi.version);
    final dizin = await dizinF;
    final api = await Api.kur(
      kullaniciAjani: _kullaniciAjani(bilgi.version),
      ekBasliklar: await basliklarF,
      destekDizini: dizin.path,
    );
    final d = UygulamaDurumu._(api, bilgi.version, await tercihF, dizin.path);
    api.oturumDustu = d._oturumDustu;
    api.yazmaBasarili = d._yazmaBasarili;
    return d;
  }

  /// WEB İLE AYNI CİHAZ KÜNYESİ: sunucu (PosSerit::cihazKunyesi) cihaz adını
  /// tarayıcının Client Hints başlıklarından okur — "Lenovo TB-X606F ·
  /// Android 13". Uygulama aynı başlıkları cihazın gerçek bilgisiyle gönderir.
  static Future<Map<String, String>> _cihazBasliklari(String surum) async {
    var model = '', platform = '', surumNo = '';
    try {
      final b = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await b.androidInfo;
        final marka = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)}';
        model = a.model.toLowerCase().contains(a.manufacturer.toLowerCase()) ? a.model : '$marka ${a.model}'.trim();
        platform = 'Android';
        surumNo = a.version.release;
      } else if (Platform.isIOS) {
        final a = await b.iosInfo;
        model = a.utsname.machine.startsWith('iPad') ? 'Apple iPad' : 'Apple iPhone';
        platform = 'iOS';
        surumNo = a.systemVersion;
      } else if (Platform.isWindows) {
        platform = 'Windows';
        surumNo = (await b.windowsInfo).majorVersion.toString();
      } else if (Platform.isMacOS) {
        final a = await b.macOsInfo;
        model = a.model;
        platform = 'macOS';
        surumNo = a.osRelease.split('.').first;
      }
    } catch (_) {}
    String q(String v) => '"${v.replaceAll('"', '')}"';
    return {
      if (model.isNotEmpty) 'Sec-CH-UA-Model': q(model),
      if (platform.isNotEmpty) 'Sec-CH-UA-Platform': q(platform),
      if (surumNo.isNotEmpty) 'Sec-CH-UA-Platform-Version': q(surumNo),
      'Sec-CH-UA': '"BamBumPOS";v="${surum.split('.').first}"',
    };
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
    // Konsol › Cihazlar "Aktif" penceresi 60 sn: 10 sn'de bir atış, her
    // 4. atışta bir (40 sn) oturum yenileme.
    var tur = 0;
    _nabiz(yenile: false);
    _kalpAtisi = Timer.periodic(const Duration(seconds: 10), (_) => _nabiz(yenile: ++tur % 4 == 0));
    _bostaDenetim?.cancel();
    _bostaDenetim = Timer.periodic(const Duration(seconds: 5), (_) => _bostaDenetle());
  }

  /// Sunucudan cihaz + operatör + yetkiyi okur ve doğru ekrana geçer.
  Future<void> oturumuYenile({bool ilk = false}) async {
    try {
      final veri = await api.get('/api/v1/uygulama/oturum');
      _oturumuAl((veri as Map).cast<String, dynamic>(), ilk: ilk);
    } on ApiHata catch (e) {
      await _oturumHatasi(e, ilk: ilk);
    }
  }

  /// Son oturum yanıtının ham metni: aynı yanıt gelince ekran yeniden
  /// kurulmaz (40 sn'lik yenileme bütün kabuğu baştan çiziyordu).
  String? _sonOturumHam;

  void _oturumuAl(Map<String, dynamic> veri, {bool ilk = false}) {
    final ham = jsonEncode(veri);
    final ayni = ham == _sonOturumHam && oturum != null && sonHata == null;
    _sonOturumHam = ham;
    if (!ayni) oturum = Oturum(veri);
    sonHata = null;
    if (ajan == null) {
      ajan = YazdirmaAjani(api, surum);
      ajan!.baslat();
    }
    _anahtarGerekirseAl(oturum!.cihazId);
    // UYGULAMA KAPANIP AÇILINCA PIN (2026-10-26 işletme isteği): soğuk
    // açılışta önceki personel oturumu düşürülür, cihaz eşli kalır. Öne
    // gelme (arka plandan dönüş) bunu YAPMAZ — yalnız ilk açılış.
    if (ilk && oturum!.operatorVar) {
      unawaited(kilitle());
      return;
    }
    final yeni = oturum!.operatorVar ? Asama.calisma : Asama.pin;
    if (ayni && yeni == asama) return;
    _gec(yeni);
  }

  Future<void> _oturumHatasi(ApiHata e, {bool ilk = false}) async {
    if (e.yetkiYok) {
      // 403: oturum açık ama cihaz kaydı yok / cihaz değil → yönetici cihazı kaldırmış.
      await api.cerezleriSil();
      await _anahtariSil();
      _aktivasyonaGec();
    } else if (e.oturumYok) {
      // 401: çerez kaybı da olabilir → önce kurtarma.
      _oturumKayip();
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

  /// Aktivasyon tamamlandı → oturum çerezi alındı.
  Future<void> aktiveEdildi() => oturumuYenile();

  /// Personel PIN'i ile operatör olur.
  Future<void> pinIleGir(String pin) async {
    // Kilit isteği hâlâ yoldaysa önce o bitsin (yoksa sunucu yeni girişi silebilir).
    await _kilitIstegi;
    final r = await api.post('/terminal/operator/pin', {'pin': pin});
    // Sunucu yanıtı oturumu da taşıyorsa ikinci gidiş-dönüş yok.
    final o = r is Map ? r['oturum'] : null;
    if (o is Map && o['cihaz'] is Map && o['operator'] is Map) {
      _oturumuAl(o.cast<String, dynamic>());
      return;
    }
    await oturumuYenile();
  }

  Future<void>? _kilitIstegi;

  /// Ekranı kilitler: operatör düşer, cihaz eşli kalır (PIN ekranı).
  /// PIN ekranı HEMEN gelir; sunucuya bildirim arkada gider.
  Future<void> kilitle() {
    final istek = _kilitIstegi = api.post('/terminal/operator/clear').then<void>((_) {}, onError: (_) {
      // Bağlantı yoksa bile ekran kilitlenir; sunucuda operatör boşta kalma süresiyle düşer.
    });
    if (oturum != null) {
      final ham = Map<String, dynamic>.from(oturum!.ham)..['operator'] = null;
      oturum = Oturum(ham);
      _sonOturumHam = null;
    }
    _gec(Asama.pin);
    return istek;
  }

  /// İşlem "önce personel seçin" / 401 derse ekran durumu tazelenir.
  void islemHatasi(ApiHata e) {
    if (e.kod == 422 && e.mesaj.toLowerCase().contains('personel')) {
      oturumuYenile();
    }
  }

  /// Api kancası: herhangi bir istekte 401.
  void _oturumDustu() {
    if (asama == Asama.aktivasyon) return;
    _oturumKayip();
  }

  void _aktivasyonaGec() {
    oturum = null;
    _sonOturumHam = null;
    ajan?.dispose();
    ajan = null;
    if (asama != Asama.aktivasyon) _gec(Asama.aktivasyon);
  }

  /* ───────── Kurtarma (2026-10-30) ───────── */

  /// Oturum kayboldu (401). Aynı anda gelen birden çok 401 TEK işlem başlatır.
  void _oturumKayip() {
    if (_kayipIsleniyor || asama == Asama.aktivasyon) return;
    _kayipIsleniyor = true;
    unawaited(_oturumKayipIsle().whenComplete(() => _kayipIsleniyor = false));
  }

  Future<void> _oturumKayipIsle() async {
    final sonuc = await _kurtar();
    switch (sonuc) {
      case KurtarmaSonucu.basarili:
        // Yeni oturum: soğuk açılıştaki gibi PIN ekranı. Bu işlem bitince
        // (iç içe 401 kendini beklemesin diye) ayrı turda yenilenir.
        oturum = null;
        _sonOturumHam = null;
        _yenidenDene?.cancel();
        _yenidenDene = Timer(Duration.zero, () => oturumuYenile(ilk: true));
      case KurtarmaSonucu.anahtarYok:
      case KurtarmaSonucu.reddedildi:
        _aktivasyonaGec();
      case KurtarmaSonucu.gecici:
        // Aktivasyona GİDİLMEZ: bekleme ekranı + kendiliğinden yeniden deneme.
        oturum = null;
        _sonOturumHam = null;
        _gec(Asama.baglantiYok);
        _yenidenDene?.cancel();
        _yenidenDene = Timer(_geciciBekleme, () => oturumuYenile(ilk: true));
    }
  }

  /// Elindeki anahtarla oturumu geri almayı BİR KEZ dener (eşzamanlı çağrılar aynı sonucu bekler).
  Future<KurtarmaSonucu> _kurtar() =>
      _kurtarmaSuruyor ??= _kurtarIc().whenComplete(() => _kurtarmaSuruyor = null);

  Future<KurtarmaSonucu> _kurtarIc() async {
    final a = await _anahtariOku();
    if (a == null) return KurtarmaSonucu.anahtarYok;

    // DÖNGÜ KORUMASI: az önce kurtardık ve oturum yine düştüyse sunucuyu
    // dövme; bekleme ekranından sonra tekrar denenir.
    final son = _sonBasariliKurtarma;
    if (son != null && DateTime.now().difference(son) < const Duration(seconds: 30)) {
      sonHata = 'Cihaz oturumu yenilenemedi. Birazdan kendiliğinden yeniden denenecek.';
      _geciciBekleme = kurtarmaBekleme;
      return KurtarmaSonucu.gecici;
    }

    try {
      await api.kurtar(a);
      _sonBasariliKurtarma = DateTime.now();
      sonHata = null;
      return KurtarmaSonucu.basarili;
    } on ApiHata catch (e) {
      // Yalnız AÇIK RET anahtarı düşürür: cihaz kaldırılmış / anahtar geçersiz.
      if (e.kod == 403 || e.kod == 404 || e.kod == 422) {
        await _anahtariSil();
        return KurtarmaSonucu.reddedildi;
      }
      // Bağlantı yok, 5xx, 429, 423 (kilitli), 402 (askı): anahtar KORUNUR.
      sonHata = e.mesaj;
      // Bağlantı kopukluğunda sık, diğerlerinde (kilit/askı/hız sınırı) seyrek dene.
      _geciciBekleme = e.baglantiYok
          ? (kurtarmaBekleme < const Duration(seconds: 5) ? kurtarmaBekleme : const Duration(seconds: 5))
          : kurtarmaBekleme;
      return KurtarmaSonucu.gecici;
    } catch (_) {
      sonHata = 'Sunucuya ulaşılamıyor. İnternet bağlantısını kontrol edin.';
      _geciciBekleme = kurtarmaBekleme;
      return KurtarmaSonucu.gecici;
    }
  }

  Future<KurtarmaAnahtari?> _anahtariOku() async {
    if (!_anahtarOkundu) {
      try {
        _anahtar = await _kurtarmaDeposu.oku();
      } catch (_) {}
      _anahtarOkundu = true;
    }
    return _anahtar;
  }

  Future<void> _anahtariSil() async {
    _anahtar = null;
    _anahtarOkundu = true;
    try {
      await _kurtarmaDeposu.sil();
    } catch (_) {}
  }

  /// Oturum açıkken cihazın kurtarma anahtarı yoksa (ya da başka bir terminale
  /// aitse) sunucudan bir kez alır. Mevcut kurulumlar güncellemeden sonraki
  /// ilk açılışta anahtarını böyle edinir — yeniden aktivasyon gerekmez.
  void _anahtarGerekirseAl(int cihazId) {
    if (cihazId <= 0 || _anahtarAliniyor || _anahtarDesteklenmiyor == cihazId) return;
    if (_anahtarOkundu && _anahtar?.terminalId == cihazId) return;
    final son = _anahtarSonDeneme;
    if (son != null && DateTime.now().difference(son) < const Duration(minutes: 5)) return;
    _anahtarAliniyor = true;
    unawaited(() async {
      try {
        final mevcut = await _anahtariOku();
        if (mevcut != null && mevcut.terminalId == cihazId) return;
        _anahtarSonDeneme = DateTime.now();
        final yeni = await api.kurtarmaAnahtariAl();
        await _kurtarmaDeposu.yaz(yeni);
        _anahtar = yeni;
        _anahtarOkundu = true;
      } on ApiHata catch (e) {
        if (e.kod == 403 || e.kod == 404) _anahtarDesteklenmiyor = cihazId;
      } catch (_) {
        // disk yazılamadı: bir sonraki denemede
      } finally {
        _anahtarAliniyor = false;
      }
    }());
  }

  /// Test: cihazın elindeki kurtarma anahtarı.
  @visibleForTesting
  Future<KurtarmaAnahtari?> kurtarmaAnahtari() => _kurtarmaDeposu.oku();

  Future<void> _nabiz({bool yenile = true}) async {
    if (asama == Asama.aktivasyon || asama == Asama.acilis) return;
    try {
      await api.post('/terminal/heartbeat');
    } on ApiHata {
      // Kalp atışı kaçarsa bir sonraki turda denenir.
    }
    // Operatörün boşta kalma süresi dolduysa / yetkisi değiştiyse yansısın.
    if (yenile) await oturumuYenile();
  }

  static final _adisyonYolu = RegExp(r'/orders/(\d+)(?:/|$)');

  /// Masa düzenini değiştiren işlemler: pano önbelleği artık güvenilmez.
  static final _yapisalIslem =
      RegExp(r'/(merge|move|cariye-tasi|toplu-tasi|split|split-shares|cancel|discard-if-empty|close|pay|refund)(?:/|$)');

  /// Bu cihazın adisyon/ödeme yazması başarılı oldu (Api kancası).
  void _yazmaBasarili(String yontem, String yol) {
    final odeme = yol.startsWith('/api/v1/payments');
    if (!yol.startsWith('/api/v1/orders') && !odeme) return;
    final m = _adisyonYolu.firstMatch(yol);
    final id = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
    if (odeme || _yapisalIslem.hasMatch(yol)) unawaited(onbellekSil('pano'));
    senkron.yerelDegisim(adisyonlar: [if (id > 0) id]);
  }

  void _gec(Asama yeni) {
    // Çalışma ekranına her girişte sayaç baştan (PIN az önce girildi).
    if (yeni == Asama.calisma && asama != Asama.calisma) _sonEtkinlik = DateTime.now();
    asama = yeni;
    notifyListeners();
  }

  /* ───────── Basit disk önbelleği (katalog, pano) ───────── */

  /// [enEski] verilirse bundan eski dosya yok sayılır (bayat pano açılışta
  /// kapanmış adisyonu göstermesin).
  Future<Map<String, dynamic>?> onbellekOku(String ad, {Duration? enEski}) async {
    try {
      final f = File('$_onbellekDizini${Platform.pathSeparator}$ad.json');
      if (!await f.exists()) return null;
      if (enEski != null && DateTime.now().difference(await f.lastModified()) > enEski) return null;
      final metin = await f.readAsString();
      // Büyük katalog / pano dosyası ayrı iş parçacığında çözülür (açılışta takılma olmasın).
      final ham = metin.length > 64 * 1024 ? await Isolate.run(() => jsonDecode(metin)) : jsonDecode(metin);
      return (ham as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<void> onbellekYaz(String ad, Map<String, dynamic> veri, {String? hazirMetin}) async {
    try {
      final f = File('$_onbellekDizini${Platform.pathSeparator}$ad.json');
      final gecici = File('${f.path}.tmp');
      await gecici.writeAsString(hazirMetin ?? jsonEncode(veri), flush: true);
      await gecici.rename(f.path);
    } catch (_) {
      // Önbellek yazılamazsa uygulama yine çalışır.
    }
  }

  /// Önbelleği geçersiz sayar (birleştir/taşı/kapat sonrası 'pano').
  Future<void> onbellekSil(String ad) async {
    try {
      final f = File('$_onbellekDizini${Platform.pathSeparator}$ad.json');
      if (await f.exists()) await f.delete();
    } catch (_) {
      // silinemezse bir sonraki pano yanıtı üstüne yazar
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
    _bostaDenetim?.cancel();
    senkron.dispose();
    super.dispose();
  }
}
