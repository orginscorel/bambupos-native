import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'api.dart';

/// UYGULAMA = YAZDIRMA AJANI.
///
/// Bilgisayardaki Node ajanıyla AYNI sunucu sözleşmesi
/// (/api/v1/print/agent/* + X-Agent-Token):
///   • ağı tarar → bulunan yazıcılar İşletme Yönetimi › Yazıcılar › "Ağda
///     bulunan" bölümüne, POS/ÖKC adayları POS terminalleri sayfasına düşer
///   • Android POS cihazında (Inpos, Sunmi, PAX, PAVO …) çalışıyorsa cihazın
///     kendisini POS terminali olarak bildirir
///   • ağ yazıcısı fişlerini (hazır ESC/POS baytı) TCP ile basar
///
/// Jeton `/api/v1/uygulama/ajan` ucundan alınır (bir cihaz = bir ajan).
class YazdirmaAjani extends ChangeNotifier {
  YazdirmaAjani(this._api, this._surum);

  final Api _api;
  final String _surum;

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

  /// Ekranda gösterilebilecek son durum.
  String durum = 'Bekliyor';
  List<Map<String, dynamic>> bulunanYazicilar = const [];
  List<Map<String, dynamic>> bulunanPos = const [];
  DateTime? sonTarama;
  int basilanFis = 0;

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
    // İlk tarama açılıştan biraz sonra (ekran önce çizilsin).
    _tekSefer?.cancel();
    _tekSefer = Timer(const Duration(seconds: 8), tara);
    _tarama = Timer.periodic(_taramaAraligi, (_) => tara());
  }

  static List<int> _portlar(Object? v, List<int> vars) =>
      v is List ? v.map((e) => (e as num).toInt()).where((p) => p > 0 && p < 65536).toList() : vars;

  Future<void> _nabizAt() async {
    try {
      await _api.post('/api/v1/print/agent/heartbeat', {'version': 'uygulama-$_surum', 'host': Platform.localHostname}, _baslik);
    } on ApiHata {
      // Bir sonraki turda yeniden.
    }
  }

  /* ───────── Fiş basma ───────── */

  Future<void> _isleriAl() async {
    if (_isAliniyor || _jeton == null) return;
    _isAliniyor = true;
    try {
      final r = await _api.get('/api/v1/print/agent/jobs', sorgu: {'yalniz_ag': 1, 'limit': 5}, basliklar: _baslik);
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
      final ip = yazici?['ip']?.toString();
      if (yazici == null || ip == null || ip.isEmpty) throw 'Yazıcının ağ adresi yok';
      final port = (yazici['port'] as num?)?.toInt() ?? 9100;
      final kopya = ((yazici['copies'] as num?)?.toInt() ?? 1).clamp(1, 5);
      final bayt = base64Decode(is_['payload_base64']?.toString() ?? '');
      await agaYaz(ip, port, bayt, kopya: kopya);
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

  /// Ham baytı (ESC/POS) ağ yazıcısına gönderir.
  static Future<void> agaYaz(String ip, int port, List<int> bayt, {int kopya = 1}) async {
    final s = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
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

      bulunanYazicilar = tekil.values.toList();
      bulunanPos = pos;
      sonTarama = DateTime.now();

      await _api.post('/api/v1/print/agent/discovered', {
        'printers': bulunanYazicilar,
        'pos': bulunanPos,
        'cihaz': cihaz,
      }, _baslik);
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

  static String _yaziciAdi(int port) => switch (port) {
        9100 => 'Fiş yazıcısı (RAW/ESC-POS 9100)',
        631 => 'Ağ yazıcısı (IPP 631)',
        515 => 'Ağ yazıcısı (LPD 515)',
        _ => 'Ağ yazıcısı ($port)',
      };

  /// En çok 96 eşzamanlı bağlantıyla port yoklar; açık olanları döner.
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

    await Future.wait(List.generate(96, (_) => isci()));
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
    super.dispose();
  }
}
