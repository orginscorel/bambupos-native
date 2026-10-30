import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ag_teshis.dart';
import 'api.dart';
import 'usb.dart';
import 'yazici_kimlik.dart';

/// UYGULAMA = YAZDIRMA AJANI.
///
/// Bilgisayardaki Node ajanıyla AYNI sunucu sözleşmesi
/// (/api/v1/print/agent/* + X-Agent-Token):
///   • ağı tarar → bulunan yazıcılar İşletme Yönetimi › Yazıcılar › "Ağda
///     bulunan" bölümüne, POS/ÖKC adayları POS terminalleri sayfasına düşer
///   • Android POS cihazında (Inpos, Sunmi, PAX, PAVO …) çalışıyorsa cihazın
///     kendisini POS terminali olarak bildirir
///   • ağ yazıcısı fişlerini (hazır ESC/POS baytı) TCP ile basar
///   • USB'ye takılı yazıcı / kart POS cihazlarını bulur, bildirir ve USB
///     yazıcıya yönlenen fişleri basar (core/usb.dart; Android, Windows, macOS)
///
/// Jeton `/api/v1/uygulama/ajan` ucundan alınır (bir cihaz = bir ajan).
class YazdirmaAjani extends ChangeNotifier {
  YazdirmaAjani(this._api, this._surum, {UsbKaynak? usb}) : _usb = usb ?? usbKaynagi();

  final Api _api;
  final String _surum;
  final UsbKaynak _usb;

  String? _jeton;
  List<int> _yaziciPortlari = const [9100, 631, 515];
  List<int> _posPortlari = const [];
  Duration _taramaAraligi = const Duration(minutes: 10);

  Timer? _nabiz;
  Timer? _isler;
  Timer? _tarama;
  Timer? _tekSefer;
  bool _kapandi = false;
  bool _isAliniyor = false;
  bool _taraniyor = false;

  /* YAZICI KİMLİĞİ (2026-10-30): IP değişince yazıcıyı kimliğinden bulma.
     Aynı IP'ye aynı anda hem fiş hem kimlik sorusu gitmesin: her ağ
     yazıcısı bağlantısı IP başına sıraya girer. */
  final Map<String, Future<void>> _ipSirasi = {};
  final Map<String, DateTime> _sonBaski = {};
  final Map<int, DateTime> _kurtarmaZamani = {};
  final Map<int, DateTime> _baglamaZamani = {};
  final Map<int, (String, int)> _baglanacak = {};
  Timer? _baglamaSaat;

  /// Ekranda gösterilebilecek son durum.
  String durum = 'Bekliyor';
  List<Map<String, dynamic>> bulunanYazicilar = const [];
  List<Map<String, dynamic>> bulunanPos = const [];
  DateTime? sonTarama;
  int basilanFis = 0;

  /* USB durumu (ekran: ekranlar/usb_cihazlar.dart) */
  bool get usbDestekli => _usb.destekli;
  String get usbPlatform => _usb.platform;
  List<String> get sistemYazicilari => _usb.sistemYazicilari;
  List<UsbCihaz> usbCihazlar = const [];

  /// Sunucuda yazıcı / POS olarak tanımlı USB anahtarları.
  Set<String> usbTanimli = {};

  /// Sunucuda "bunu gösterme" denmiş anahtarlar (İşletme Yönetimi'nde görünür).
  Set<String> usbGizliSunucu = {};

  /// Bu cihazda eklenen cihazların kimlikleri (yerel yedek: eski sunucu
  /// listeyi döndürmese de şerit yeniden çıkmaz).
  Set<String> usbYerelTanimli = {};

  /// "Bunu gösterme" denenlerin kimlikleri (yerel yedek; sunucu çağrısı
  /// başarısız olsa da gizli kalır).
  Set<String> usbGizlenen = {};
  DateTime? usbSonTarama;
  String? usbHata;
  Timer? _usbSaat;
  Timer? _usbErteleme;
  StreamSubscription<void>? _usbOlay;
  bool _usbTaraniyor = false;
  bool _usbBekleyen = false;
  String? _usbSonImza;
  DateTime? _usbSonBildirim;
  static const _gizlenenAnahtari = 'usb_gizlenen';
  static const _yerelTanimliAnahtari = 'usb_tanimli_yerel';

  /// POS cihazı üreticileri (Build.MANUFACTURER / BRAND / MODEL içinde aranır).
  static const _posUreticileri = [
    'sunmi', 'pax', 'ingenico', 'verifone', 'newland', 'urovo', 'castles', 'inpos', 'hugin', 'beko', 'profilo',
    'pavo', 'nexgo', 'telpo', 'imin', 'landi', 'centerm', 'feitian', 'senraise', 'wizarpos', 'aisino', 'vanstone',
  ];

  Map<String, String> get _baslik => {'X-Agent-Token': _jeton ?? ''};

  Future<void> baslat() async {
    if (_jeton != null) return;
    try {
      final r = (await _api.post('/api/v1/uygulama/ajan', {
        'surum': _surum,
        'host': Platform.localHostname,
      }) as Map);
      _jeton = r['token']?.toString();
      final t = r['tarama'] is Map ? r['tarama'] as Map : const {};
      _yaziciPortlari = _portlar(t['yazici_portlari'], _yaziciPortlari);
      _posPortlari = _portlar(t['pos_portlari'], _posPortlari);
      _taramaAraligi = Duration(minutes: ((t['aralik_dk'] as num?)?.toInt() ?? 10).clamp(2, 120));
    } on ApiHata catch (e) {
      // 503: sunucu güncellemesi bekleniyor · 423: konsoldan kapatılmış.
      durum = e.mesaj;
      notifyListeners();
      _tekSefer?.cancel();
      if (!_kapandi) _tekSefer = Timer(const Duration(minutes: 10), baslat);
      return;
    }
    if (_jeton == null || _kapandi) return;

    durum = 'Bağlı';
    notifyListeners();
    _nabizAt();
    _nabiz = Timer.periodic(const Duration(seconds: 30), (_) => _nabizAt());
    _isler = Timer.periodic(const Duration(seconds: 4), (_) => _isleriAl());
    // İlk tarama açılıştan bir dakika sonra: yüzlerce soket denemesi, personel
    // PIN girerken / ilk ekran açılırken düşük güçlü tableti yormasın.
    _tekSefer?.cancel();
    _tekSefer = Timer(const Duration(seconds: 60), tara);
    _tarama = Timer.periodic(_taramaAraligi, (_) => tara());
    _usbBaslat();
  }

  static List<int> _portlar(Object? v, List<int> vars) =>
      v is List ? v.map((e) => (e as num).toInt()).where((p) => p > 0 && p < 65536).toList() : vars;

  Future<void> _nabizAt() async {
    try {
      await _api.post('/api/v1/print/agent/heartbeat', {
        'version': _surum,
        'host': Platform.localHostname,
        'surum': _surum,
        'platform': Platform.operatingSystem,
        'usb_destek': _usb.destekli,
      }, _baslik);
    } on ApiHata {
      // Bir sonraki turda yeniden.
    }
  }

  /* ───────── Fiş basma ───────── */

  Future<void> _isleriAl() async {
    if (_isAliniyor || _jeton == null) return;
    _isAliniyor = true;
    try {
      final r = await _api.get('/api/v1/print/agent/jobs',
          sorgu: {'yalniz_ag': 1, 'limit': 5, if (_usb.destekli) 'usb': 1, 'teshis': 1}, basliklar: _baslik);
      // "Bu adreste ne var?" / "Ağı tara" istekleri (konsoldan). Arka planda.
      if (r is Map && r['teshis'] is List && !_teshisCalisiyor) {
        final t = (r['teshis'] as List).whereType<Map>().toList();
        if (t.isNotEmpty) unawaited(_teshisYap(t.first));
      }
      final isler = (r is Map && r['jobs'] is List) ? (r['jobs'] as List).whereType<Map>().toList() : const <Map>[];
      for (final is_ in isler) {
        await _bas(is_);
      }
    } on ApiHata {
      // Sunucuya ulaşılamadı; iş kuyrukta kalır.
    } finally {
      _isAliniyor = false;
    }
  }

  Future<void> _bas(Map is_) async {
    final id = (is_['id'] as num?)?.toInt();
    final yazici = is_['printer'] is Map ? is_['printer'] as Map : null;
    String? hata;
    try {
      var yon = isYonuBelirle(yazici, _usbAnahtarlar);
      // Yeni takılmış olabilir: bir kez taze listeyle dene.
      if (yon.yon == IsYonu.usbYok && yon.anahtar != null && _usb.destekli) {
        await _usbTara();
        yon = isYonuBelirle(yazici, _usbAnahtarlar);
      }
      final kopya = ((yazici?['copies'] as num?)?.toInt() ?? 1).clamp(1, 5);
      switch (yon.yon) {
        case IsYonu.eksik:
          throw 'Yazıcının ağ adresi yok';
        case IsYonu.usbYok:
          throw _usb.destekli
              ? 'USB yazıcı bağlı değil (${yon.anahtar ?? 'anahtar yok'})'
              : 'Bu cihazda USB yazıcı desteklenmez';
        case IsYonu.usb:
          final c = usbCihazlar.firstWhere((c) => c.anahtar == yon.anahtar);
          await _usb.yaz(c, base64Decode(is_['payload_base64']?.toString() ?? ''), kopya: kopya);
        case IsYonu.ag:
          var port = (yazici!['port'] as num?)?.toInt() ?? 9100;
          var hedef = yazici['ip'].toString();
          final bayt = base64Decode(is_['payload_base64']?.toString() ?? '');
          try {
            await _sirayla(hedef, () => agaYaz(hedef, port, bayt, kopya: kopya));
          } on BaglantiKurulamadi catch (e) {
            // Yazıcıya hiç bağlanılamadı (fiş kâğıda gitmedi): IP değişmiş
            // olabilir. Sunucu kimlikten KESİN bulursa adres güncellenir ve
            // fiş bir kez yeni adrese denenir; bulamazsa eski hata kalır.
            final yeni = await _agKurtar(yazici);
            if (yeni == null) rethrow;
            hedef = yeni.ip;
            port = yeni.port;
            try {
              await _sirayla(hedef, () => agaYaz(hedef, port, bayt, kopya: kopya));
            } catch (_) {
              throw e;
            }
          }
          // Kimliği henüz bağlanmamış yazıcı: işler bitince sessizce sorulur.
          final pid = (yazici['id'] as num?)?.toInt();
          if (pid != null && yazici['kimlik_eksik'] == true && yazici['aday_testi'] != true) {
            _kimlikBaglaPlanla(pid, hedef, port);
          }
      }
      basilanFis++;
    } catch (e) {
      hata = e.toString();
    }
    if (id == null) return;
    try {
      await _api.post('/api/v1/print/agent/jobs/$id/ack', {'ok': hata == null, 'error': ?hata}, _baslik);
    } on ApiHata {
      // Onay gitmezse sunucu işi zaman aşımında geri alır.
    }
  }

  /// Ham baytı (ESC/POS) ağ yazıcısına gönderir. Bağlantı HİÇ kurulamazsa
  /// [BaglantiKurulamadi] atar (fişin hiçbir parçası gitmedi demektir).
  static Future<void> agaYaz(String ip, int port, List<int> bayt, {int kopya = 1}) async {
    final Socket s;
    try {
      s = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
    } catch (e) {
      throw BaglantiKurulamadi(e);
    }
    try {
      for (var i = 0; i < kopya; i++) {
        s.add(bayt);
      }
      await s.flush();
    } finally {
      await s.close();
      s.destroy();
    }
  }

  /// Aynı IP'ye bağlantıları sıraya koyar (fiş ↔ kimlik sorusu çakışmasın).
  Future<T> _sirayla<T>(String ip, Future<T> Function() f) async {
    final onceki = _ipSirasi[ip] ?? Future<void>.value();
    final bitti = Completer<void>();
    final benim = bitti.future;
    _ipSirasi[ip] = benim;
    try {
      await onceki;
    } catch (_) {}
    try {
      return await f();
    } finally {
      _sonBaski[ip] = DateTime.now();
      bitti.complete();
      if (identical(_ipSirasi[ip], benim)) _ipSirasi.remove(ip);
    }
  }

  /// Yazıcı az önce iş bastıysa / basıyorsa kimlik sorulmaz.
  bool _yoklanabilir(String ip) {
    if (_ipSirasi.containsKey(ip)) return false;
    final s = _sonBaski[ip];
    return s == null || DateTime.now().difference(s) > const Duration(seconds: 5);
  }

  /// Kimlik sorusu (sıraya girerek). Meşgulse boş döner.
  Future<YaziciKimlik> _kimlikSor(String ip, int port, Map<String, String> arp) async {
    if (!_yoklanabilir(ip)) return YaziciKimlik(mac: arp[ip]);
    final k = await _sirayla(ip, () => KimlikYoklayici.sor(ip, port));
    return k.macIle(arp[ip]);
  }

  /// BAĞLANTI KURULAMADI → kendini onarma. Aynı ağ hızlıca (yalnız yazıcının
  /// portu) taranır, bulunan cihazların kimliği sunucuya gönderilir. Karar
  /// SUNUCUNUNDUR: kayıtlı kimlikle KESİN eşleşen (MAC ya da seri no) TEK
  /// cihaz varsa ve adres başka yazıcıya ait değilse IP güncellenir; aksi
  /// hâlde yalnız öneri yazılır. Yazıcı başına 3 dakikada bir.
  Future<({String ip, int port})?> _agKurtar(Map yazici) async {
    final id = (yazici['id'] as num?)?.toInt();
    if (id == null || yazici['aday_testi'] == true || _jeton == null) return null;
    final simdi = DateTime.now();
    final son = _kurtarmaZamani[id];
    if (son != null && simdi.difference(son) < const Duration(minutes: 3)) return null;
    _kurtarmaZamani[id] = simdi;
    try {
      final yerel = await _yerelIp();
      if (yerel == null) return null;
      final eski = yazici['ip'].toString();
      final port = (yazici['port'] as num?)?.toInt() ?? 9100;
      final onek = yerel.substring(0, yerel.lastIndexOf('.') + 1);
      final acik = await _paralelYokla([
        for (var h = 1; h < 255; h++)
          if ('$onek$h' != yerel && '$onek$h' != eski) ('$onek$h', port),
      ]);
      final arp = await KimlikYoklayici.arpTablosu();
      final cihazlar = <Map<String, dynamic>>[];
      for (final (a, p) in acik) {
        final k = await _kimlikSor(a, p, arp);
        cihazlar.add({'ip': a, 'port': p, if (!k.bos) 'kimlik': k.toJson()});
      }
      final r = await _api.post('/api/v1/print/agent/kurtar', {
        'printer_id': id,
        'eski_ip': eski,
        'cihaz_ip': yerel,
        'cihazlar': cihazlar,
      }, _baslik);
      if (r is Map && r['degisti'] == true && r['ip'] is String) {
        return (ip: r['ip'] as String, port: (r['port'] as num?)?.toInt() ?? port);
      }
    } catch (_) {
      // Eski sunucu (uç yok) / ağ hatası: eski davranış sürer.
    }
    return null;
  }

  /// Başarılı fişten sonra, işler durulunca yazıcının kimliği sorulur ve
  /// sunucuya bağlanır (yazıcı başına 30 dakikada en çok bir kez).
  void _kimlikBaglaPlanla(int id, String ip, int port) {
    final son = _baglamaZamani[id];
    if (son != null && DateTime.now().difference(son) < const Duration(minutes: 30)) return;
    _baglanacak[id] = (ip, port);
    _baglamaSaat?.cancel();
    _baglamaSaat = Timer(const Duration(seconds: 6), _kimlikleriBagla);
  }

  Future<void> _kimlikleriBagla() async {
    if (_kapandi || _jeton == null || _baglanacak.isEmpty) return;
    if (_isAliniyor) {
      _baglamaSaat = Timer(const Duration(seconds: 6), _kimlikleriBagla);
      return;
    }
    final liste = Map.of(_baglanacak);
    _baglanacak.clear();
    final arp = await KimlikYoklayici.arpTablosu();
    for (final e in liste.entries) {
      final (ip, port) = e.value;
      if (!_yoklanabilir(ip)) {
        _kimlikBaglaPlanla(e.key, ip, port);
        continue;
      }
      _baglamaZamani[e.key] = DateTime.now();
      final k = await _kimlikSor(ip, port, arp);
      if (k.bos) continue;
      try {
        await _api.post('/api/v1/print/agent/kimlik', {
          'printer_id': e.key,
          'ip': ip,
          'port': port,
          'kimlik': k.toJson(),
        }, _baslik);
      } catch (_) {
        // Eski sunucu: bir sonraki denemede.
      }
    }
  }

  bool _teshisCalisiyor = false;

  /// Konsoldan istenen ağ teşhisi: tek adres ya da tüm ağ. Sonuç ham
  /// ipuçlarıdır; türü sunucu tahmin eder. Yazıcıya baskı gitmez.
  Future<void> _teshisYap(Map istek) async {
    final id = (istek['id'] as num?)?.toInt();
    if (id == null || _jeton == null) return;
    _teshisCalisiyor = true;
    try {
      final yerel = await _yerelIp();
      Map<String, dynamic> govde;
      if (yerel == null) {
        govde = {'hata': 'Cihazın yerel ağ adresi bulunamadı'};
      } else if (istek['tur'] == 'ag') {
        final l = await AgTeshis.ag(yerel, arpOku: KimlikYoklayici.arpTablosu, kimlikSor: (ip, port) async {
          return _kimlikSor(ip, port, await KimlikYoklayici.arpTablosu());
        });
        govde = {'cihaz_ip': yerel, 'cihazlar': l};
      } else {
        final ip = '${istek['ip'] ?? ''}';
        final ayniAg = ip.contains('.') && ip.substring(0, ip.lastIndexOf('.')) == yerel.substring(0, yerel.lastIndexOf('.'));
        if (!ayniAg) {
          govde = {'cihaz_ip': yerel, 'hata': 'Bu cihaz farklı bir ağda'};
        } else {
          final c = await AgTeshis.cihaz(ip, arpOku: KimlikYoklayici.arpTablosu, kimlikSor: (a, p) async {
            return _kimlikSor(a, p, await KimlikYoklayici.arpTablosu());
          });
          govde = {'cihaz_ip': yerel, 'cihazlar': [c]};
        }
      }
      await _api.post('/api/v1/print/agent/teshis/$id', govde, _baslik);
    } catch (_) {
      // Sunucu isteği zaman aşımında başka cihaza verir.
    } finally {
      _teshisCalisiyor = false;
    }
  }

  /* ───────── Ağ taraması ───────── */

  Future<void> tara() async {
    if (_taraniyor || _jeton == null) return;
    _taraniyor = true;
    durum = 'Ağ taranıyor…';
    notifyListeners();
    try {
      final ip = await _yerelIp();
      final cihaz = await _cihazKunyesi(ip);
      final yazicilar = <Map<String, dynamic>>[];
      final pos = <Map<String, dynamic>>[];

      if (ip != null) {
        final onek = ip.substring(0, ip.lastIndexOf('.') + 1);
        final portlar = {..._yaziciPortlari, ..._posPortlari}.toList();
        final hedefler = [
          for (var h = 1; h < 255; h++)
            if ('$onek$h' != ip)
              for (final p in portlar) ('$onek$h', p),
        ];
        final acik = await _paralelYokla(hedefler);
        for (final (adres, port) in acik) {
          if (_yaziciPortlari.contains(port)) {
            yazicilar.add({'ip': adres, 'port': port, 'name': _yaziciAdi(port)});
          } else {
            pos.add({'ip': adres, 'port': port, 'tahmin': 'POS / ÖKC (port $port açık)'});
          }
        }
      }

      // Aynı yazıcı birden çok portta yanıt verirse tek kayıt (9100 öncelikli).
      final tekil = <String, Map<String, dynamic>>{};
      for (final y in yazicilar..sort((a, b) => (a['port'] == 9100 ? 0 : 1).compareTo(b['port'] == 9100 ? 0 : 1))) {
        tekil.putIfAbsent(y['ip'] as String, () => y);
      }

      // Kimlik (yalnız 9100 fiş yazıcıları; meşgul olan atlanır).
      if (tekil.values.any((y) => y['port'] == 9100)) {
        final arp = await KimlikYoklayici.arpTablosu();
        for (final y in tekil.values) {
          if (y['port'] != 9100) continue;
          final k = await _kimlikSor(y['ip'] as String, 9100, arp);
          if (!k.bos) y['kimlik'] = k.toJson();
        }
      }

      bulunanYazicilar = tekil.values.toList();
      bulunanPos = pos;
      sonTarama = DateTime.now();

      _cihaz = cihaz;
      final r = await _api.post('/api/v1/print/agent/discovered', {
        'printers': bulunanYazicilar,
        'pos': bulunanPos,
        'cihaz': cihaz,
        if (_usb.destekli && _usbSonImza != null) ...{
          'usb': [for (final c in usbCihazlar) c.sunucuyaJson()],
          'usb_platform': _usb.platform,
        },
      }, _baslik);
      if (_usb.destekli && _usbSonImza != null) {
        _usbSonBildirim = DateTime.now();
        _tanimlilariOku(r);
      }
      durum = ip == null ? 'Ağ adresi bulunamadı' : 'Bağlı · ${bulunanYazicilar.length} yazıcı';
    } on ApiHata catch (e) {
      durum = e.mesaj;
    } catch (_) {
      durum = 'Tarama tamamlanamadı';
    } finally {
      _taraniyor = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _cihaz;
  DateTime? _posTaramasi;

  /// Kasada tanımlı ethernet POS'una ulaşılamadı: IP değişmiş olabilir.
  /// Ağ taranır (sunucu listesindeki POS portları dahil, ör. inPos 59000) ve
  /// bulunanlar bildirilir; sunucu adresi kendisi günceller. En çok 10 dk'da bir.
  void posUlasilamadi() {
    if (_jeton == null || _taraniyor) return;
    final simdi = DateTime.now();
    if (_posTaramasi != null && simdi.difference(_posTaramasi!) < const Duration(minutes: 10)) return;
    _posTaramasi = simdi;
    tara();
  }

  /* ───────── USB cihazlar ───────── */

  Set<String> get _usbAnahtarlar => {for (final c in usbCihazlar) c.anahtar};

  void _usbBaslat() {
    if (!_usb.destekli || _kapandi) return;
    SharedPreferences.getInstance().then((p) {
      usbGizlenen = {...usbGizlenen, ...?p.getStringList(_gizlenenAnahtari)};
      usbYerelTanimli = {...usbYerelTanimli, ...?p.getStringList(_yerelTanimliAnahtari)};
      notifyListeners();
    }).ignore();
    // Android: takma / çıkarma anında; masaüstünde olay yok → dakikada bir
    // ucuz denetim (Windows: ayrı isolate'te kuyruk + SetupAPI, ~ms; macOS:
    // lpstat, system_profiler 5 dk'da bir). Android'de yedek denetim 5 dk.
    _usbOlay = _usb.degisti.listen((_) => usbYenile(), onError: (_) {});
    usbYenile(gecikme: const Duration(seconds: 3));
    _usbSaat = Timer.periodic(Duration(seconds: Platform.isAndroid ? 300 : 60), (_) => _usbTara());
  }

  /// Ertelemeli yenileme (art arda gelen takma olayları tek taramaya iner).
  void usbYenile({Duration gecikme = const Duration(milliseconds: 800), bool zorla = false}) {
    if (!_usb.destekli || _kapandi) return;
    _usbErteleme?.cancel();
    _usbErteleme = Timer(gecikme, () => _usbTara(zorla: zorla));
  }

  /// Ekrandaki "Yenile": hemen tarar, sunucuya da bildirir.
  Future<void> usbSimdiTara() => _usbTara(zorla: true, bildir: true);

  Future<void> _usbTara({bool zorla = false, bool bildir = false}) async {
    if (!_usb.destekli || _kapandi) return;
    if (_usbTaraniyor) {
      _usbBekleyen = true;
      return;
    }
    _usbTaraniyor = true;
    try {
      final l = await _usb.listele(zorla: zorla);
      usbHata = null;
      usbSonTarama = DateTime.now();
      final imza = usbImza(l);
      final degisti = imza != _usbSonImza || l.length != usbCihazlar.length ||
          [for (var i = 0; i < l.length; i++) l[i].izinGerekli != usbCihazlar[i].izinGerekli].any((x) => x);
      usbCihazlar = l;
      final sunucuyaDegisti = imza != _usbSonImza;
      _usbSonImza = imza;
      if (degisti) notifyListeners();
      // Liste değişince hemen; değişmese de 10 dk'da bir canlılık bildirimi.
      final eski = _usbSonBildirim == null || DateTime.now().difference(_usbSonBildirim!) > const Duration(minutes: 10);
      if (sunucuyaDegisti || eski || bildir) await _usbBildir(acil: bildir);
    } catch (e) {
      usbHata = e is UsbHata ? e.mesaj : 'USB cihazlar okunamadı';
      notifyListeners();
    } finally {
      _usbTaraniyor = false;
      if (_usbBekleyen) {
        _usbBekleyen = false;
        usbYenile();
      }
    }
  }

  /// USB listesi bu cihazın TAM listesidir (sunucu yerine koyar). Eski sunucu
  /// `discovered` alanını `printers` gelmezse boşalttığı için son ağ taraması
  /// da birlikte gönderilir.
  Future<void> _usbBildir({bool acil = false}) async {
    if (_jeton == null) return;
    // İlk ağ taraması henüz bitmediyse olağan bildirim beklenir: tarama USB
    // listesini de taşır. (Eski sunucu `printers` gelmeyince ağda bulunan
    // listeyi boşaltıyordu.) Kullanıcı eylemi (Yenile / Ekle) beklemez.
    if (!acil && sonTarama == null && !_taraniyor) {
      _tekSefer ??= Timer(const Duration(seconds: 60), tara);
      return;
    }
    try {
      final r = await _api.post('/api/v1/print/agent/discovered', {
        'usb': [for (final c in usbCihazlar) c.sunucuyaJson()],
        'usb_platform': _usb.platform,
        'usb_yalniz': true,
        if (sonTarama != null) ...{
          'printers': bulunanYazicilar,
          'pos': bulunanPos,
          'cihaz': ?_cihaz,
        },
      }, _baslik);
      _usbSonBildirim = DateTime.now();
      _tanimlilariOku(r);
    } on ApiHata {
      // Bir sonraki turda yeniden (_usbSonBildirim değişmedi).
    }
  }

  /// Sunucu yanıtında tanımlı USB anahtarları: `usb_tanimli: [..]` ya da
  /// `usb: [{anahtar, tanimli}]`.
  void _tanimlilariOku(Object? r) {
    if (r is! Map) return;
    Set<String>? yeni;
    if (r['usb_tanimli'] is List) {
      yeni = {for (final a in r['usb_tanimli'] as List) '$a'};
    } else if (r['usb'] is List) {
      yeni = {
        for (final m in (r['usb'] as List).whereType<Map>())
          if (m['tanimli'] == true || m['benimsendi'] == true) '${m['anahtar']}',
      };
    }
    final gizli = r['usb_gizli'] is List ? {for (final a in r['usb_gizli'] as List) '$a'} : null;
    var degisti = false;
    if (yeni != null && !setEquals(yeni, usbTanimli)) {
      usbTanimli = yeni;
      degisti = true;
    }
    if (gizli != null && !setEquals(gizli, usbGizliSunucu)) {
      usbGizliSunucu = gizli;
      degisti = true;
    }
    if (degisti) notifyListeners();
  }

  /// Android izin penceresi; verilirse liste yenilenir.
  Future<bool> usbIzinIste(UsbCihaz c) async {
    final ok = await _usb.izinIste(c);
    await _usbTara();
    return ok;
  }

  /// Yerel deneme fişi (sunucuya gitmez).
  Future<void> usbTestYazdir(UsbCihaz c) async {
    if (c.izinGerekli && !await usbIzinIste(c)) throw const UsbHata('USB izni verilmedi');
    final guncel = usbCihazlar.firstWhere((x) => x.anahtar == c.anahtar, orElse: () => c);
    if (!guncel.yazdirilabilir) throw UsbHata(guncel.ipucu ?? 'Bu cihaza doğrudan yazdırılamıyor');
    await _usb.yaz(guncel, usbTestFisi(guncel.ad));
  }

  /// Cihazı sunucuda yazıcı / POS olarak tanımlar. Hata metni ya da null.
  /// [tur]: 'yazici' | 'pos' (tanınmayan cihaz için personelin seçimi).
  Future<String?> usbBenimse(UsbCihaz c, {String? ad, String? istasyon, String? tur}) async {
    if (_jeton == null) return 'Yazdırma ajanı bağlı değil';
    // Android: yazıcı olarak eklemeden önce izin (yoksa ilk fiş basılamaz).
    if ((tur ?? c.tur) == 'yazici' && c.izinGerekli) await usbIzinIste(c);
    try {
      // Önce güncel listeyi bildir: sunucu anahtarı tanısın.
      await _usbBildir(acil: true);
      final r = await _api.post('/api/v1/print/agent/usb/benimse', {
        'anahtar': c.anahtar,
        if (ad != null && ad.trim().isNotEmpty) 'ad': ad.trim(),
        'istasyon': ?istasyon,
        'tur': tur ?? c.tur,
      }, _baslik);
      _tanimlilariOku(r);
      usbTanimli = {...usbTanimli, c.anahtar};
      _yerelEkle(_yerelTanimliAnahtari, c.kimlikler, tanimli: true);
      return null;
    } on ApiHata catch (e) {
      return e.mesaj;
    }
  }

  /// Sunucuda (ya da bu cihazda eklenerek) tanımlı mı? Liste satırı için.
  bool usbTanimliMi(UsbCihaz c) => usbTanimli.contains(c.anahtar) || usbYerelTanimli.contains(c.anahtar);

  /// "Bunu gösterme" denmiş mi (sunucu ya da yerel)?
  bool usbGizliMi(UsbCihaz c) => usbGizliSunucu.contains(c.anahtar) || c.kimlikler.any(usbGizlenen.contains);

  /// Şeritte önerilmez: tanımlı, gizli ya da aynı vid:pid'li bir kardeşi
  /// tanımlı / gizli (Windows'ta aynı yazıcı hem kuyruk `win:<ad>` hem ham
  /// aygıt `usb:..` olarak görünebilir; anahtar metni değişebilir).
  bool usbBilinen(UsbCihaz c) {
    if (usbTanimliMi(c) || usbGizliMi(c)) return true;
    if (c.kimlikler.any(usbYerelTanimli.contains)) return true;
    final vp = c.vidPid;
    if (vp == null) return false;
    return usbCihazlar.any((k) =>
        k.anahtar != c.anahtar && k.vidPid == vp && (usbTanimli.contains(k.anahtar) || usbGizliSunucu.contains(k.anahtar)));
  }

  /// Şeritte gösterilecek yeni cihaz (tanımsız, gizlenmemiş yazıcı / POS).
  UsbCihaz? get usbYeniCihaz {
    for (final c in usbCihazlar) {
      if ((c.tur == 'yazici' || c.tur == 'pos') && !usbBilinen(c)) return c;
    }
    return null;
  }

  /// "Bunu gösterme" ([gizli] true) ya da "Göster" (false). Önce yerelde
  /// uygulanır (sunucu çağrısı başarısız olsa / eski sunucu da olsa kalıcı),
  /// sonra sunucuya bildirilir: İşletme Yönetimi'nde gizlenenler görünür.
  Future<void> usbGizle(UsbCihaz c, {bool gizli = true}) async {
    if (gizli) {
      usbGizliSunucu = {...usbGizliSunucu, c.anahtar};
      _yerelEkle(_gizlenenAnahtari, c.kimlikler);
    } else {
      usbGizliSunucu = {...usbGizliSunucu}..remove(c.anahtar);
      usbGizlenen = {...usbGizlenen}..removeAll(c.kimlikler);
      notifyListeners();
      _yerelYaz(_gizlenenAnahtari, usbGizlenen);
    }
    if (_jeton == null) return;
    try {
      // Yanıt güncel usb_tanimli / usb_gizli listelerini taşır.
      _tanimlilariOku(await _api.post('/api/v1/print/agent/usb/gizle', {'anahtar': c.anahtar, 'gizli': gizli}, _baslik));
    } catch (_) {
      // Yerel kayıt yeterli; sunucu bir sonraki gizlemede / gösterimde eşitlenir.
    }
  }

  void _yerelEkle(String anahtar, Set<String> kimlikler, {bool tanimli = false}) {
    if (tanimli) {
      usbYerelTanimli = {...usbYerelTanimli, ...kimlikler};
    } else {
      usbGizlenen = {...usbGizlenen, ...kimlikler};
    }
    notifyListeners();
    _yerelYaz(anahtar, tanimli ? usbYerelTanimli : usbGizlenen);
  }

  static void _yerelYaz(String anahtar, Set<String> deger) {
    final l = deger.toList();
    SharedPreferences.getInstance().then((p) => p.setStringList(anahtar, l.length > 200 ? l.sublist(l.length - 200) : l)).ignore();
  }

  static String _yaziciAdi(int port) => switch (port) {
        9100 => 'Fiş yazıcısı (RAW/ESC-POS 9100)',
        631 => 'Ağ yazıcısı (IPP 631)',
        515 => 'Ağ yazıcısı (LPD 515)',
        _ => 'Ağ yazıcısı ($port)',
      };

  /// En çok 96 (telefon/tablette 48) eşzamanlı bağlantıyla port yoklar;
  /// açık olanları döner.
  static Future<List<(String, int)>> _paralelYokla(List<(String, int)> hedefler) async {
    final acik = <(String, int)>[];
    var i = 0;
    Future<void> isci() async {
      while (i < hedefler.length) {
        final (adres, port) = hedefler[i++];
        try {
          final s = await Socket.connect(adres, port, timeout: const Duration(milliseconds: 350));
          s.destroy();
          acik.add((adres, port));
        } catch (_) {
          // Kapalı / yanıt yok.
        }
      }
    }

    final mobil = Platform.isAndroid || Platform.isIOS;
    await Future.wait(List.generate(mobil ? 48 : 96, (_) => isci()));
    return acik;
  }

  static Future<String?> _yerelIp() async {
    try {
      final w = await NetworkInfo().getWifiIP();
      if (w != null && _ozelMi(w)) return w;
    } catch (_) {
      // Masaüstünde Wi-Fi API'si olmayabilir; arayüzlere bakılır.
    }
    try {
      for (final arayuz in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in arayuz.addresses) {
          if (_ozelMi(a.address)) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _ozelMi(String ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);

  static Future<Map<String, dynamic>> _cihazKunyesi(String? ip) async {
    var marka = '';
    var model = '';
    var platform = defaultTargetPlatform.name;
    try {
      final b = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await b.androidInfo;
        marka = a.manufacturer;
        model = '${a.brand} ${a.model}'.trim();
        platform = 'Android ${a.version.release}';
      } else if (Platform.isIOS) {
        final a = await b.iosInfo;
        marka = 'Apple';
        model = a.utsname.machine;
        platform = 'iOS ${a.systemVersion}';
      } else if (Platform.isWindows) {
        final a = await b.windowsInfo;
        model = a.computerName;
        platform = 'Windows';
      } else if (Platform.isMacOS) {
        final a = await b.macOsInfo;
        marka = 'Apple';
        model = a.model;
        platform = 'macOS ${a.osRelease}';
      }
    } catch (_) {}
    final aranan = '$marka $model'.toLowerCase();
    return {
      'platform': platform,
      'marka': marka,
      'model': model,
      'pos_cihazi': Platform.isAndroid && _posUreticileri.any(aranan.contains),
      'ip': ?ip,
    };
  }

  @override
  void dispose() {
    _kapandi = true;
    _tekSefer?.cancel();
    _nabiz?.cancel();
    _isler?.cancel();
    _tarama?.cancel();
    _usbSaat?.cancel();
    _usbErteleme?.cancel();
    _baglamaSaat?.cancel();
    _usbOlay?.cancel();
    _usb.kapat();
    super.dispose();
  }
}

/// Ağ yazıcısına bağlantı hiç kurulamadı (fiş gönderilmedi).
class BaglantiKurulamadi implements Exception {
  BaglantiKurulamadi(this.neden);
  final Object neden;
  @override
  String toString() => neden.toString();
}
