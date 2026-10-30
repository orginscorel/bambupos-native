import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'yazici_kimlik.dart';

/// AĞ TEŞHİSİ (2026-10-30) — "yazıcının adresinde şimdi ne var?"
///
/// Yazıcıya ulaşılamayınca sebebi çoğu zaman şudur: modem o adresi başka
/// bir cihaza (telefon, tablet, bilgisayar) vermiştir. Burada bir adres (ya
/// da tüm /24 ağı) için ipuçları toplanır; TÜRÜN TAHMİNİ sunucuda yapılır.
///
/// YAZICIYA BASKI GİTMEZ: portlara yalnız bağlanılıp kapatılır (veri yok);
/// 9100'de kimlik sorusu yazici_kimlik.dart güvenceleriyle (DLE EOT önce)
/// ve yalnız çağıran izin verirse yapılır; 80 portuna düz HTTP GET gider.
///
/// Toplanan ipuçları (hepsi kısa süreli, hata yutulur):
///   • açık / reddeden portlar (port imzası: 62078 iPhone, 445 Windows …)
///   • ters DNS (modem DHCP adlarını çoğu zaman bilir)
///   • mDNS tekil sorgusu (UDP 5353 → "Ahmet-iPhone.local")
///   • NetBIOS ad sorgusu (UDP 137 → Windows bilgisayar adı + MAC)
///   • masaüstünde ARP'tan MAC (Android/iOS'ta yok)
///   • 80 açıksa sayfa başlığı ve Server başlığı
class AgTeshis {
  AgTeshis._();

  /// Tek adres teşhisinde yoklanan portlar.
  static const tekPortlar = [9100, 80, 443, 62078, 445, 139, 22, 7000, 8008, 8009, 554, 515, 631, 5000];

  /// Tüm ağ taramasında (canlılık + imza) yoklanan portlar.
  static const agPortlari = [9100, 80, 443, 62078, 445, 139, 7000, 8009];

  /// Bir adresi teşhis eder. [arpOku] port yoklamasından SONRA çağrılır
  /// (bağlantı denemesi ARP kaydını tazeler). [kimlikSor] verilirse ve 9100
  /// açıksa yazıcı kimliği sorulur.
  static Future<Map<String, dynamic>> cihaz(
    String ip, {
    Future<Map<String, String>> Function()? arpOku,
    Future<YaziciKimlik> Function(String ip, int port)? kimlikSor,
  }) async {
    final sonuc = await Future.wait([for (final p in tekPortlar) _portYokla(ip, p, const Duration(milliseconds: 800))]);
    final acik = <int>[];
    var reddeden = false;
    for (var i = 0; i < tekPortlar.length; i++) {
      if (sonuc[i] == _Port.acik) acik.add(tekPortlar[i]);
      if (sonuc[i] == _Port.reddetti) reddeden = true;
    }
    final arp = arpOku == null ? const <String, String>{} : await arpOku();
    return _ayrinti(ip, acik, reddeden, arp[ip], kimlikSor);
  }

  /// Yerel /24 ağının canlı cihazlarını çıkarır (en çok [enCok] cihaz).
  static Future<List<Map<String, dynamic>>> ag(
    String yerelIp, {
    Future<Map<String, String>> Function()? arpOku,
    Future<YaziciKimlik> Function(String ip, int port)? kimlikSor,
    int enCok = 64,
  }) async {
    final onek = yerelIp.substring(0, yerelIp.lastIndexOf('.') + 1);
    final hedefler = [
      for (var h = 1; h < 255; h++)
        if ('$onek$h' != yerelIp)
          for (final p in agPortlari) ('$onek$h', p),
    ];
    final acik = <String, List<int>>{};
    final canli = <String>{};
    var i = 0;
    Future<void> isci() async {
      while (i < hedefler.length) {
        final (a, p) = hedefler[i++];
        final s = await _portYokla(a, p, const Duration(milliseconds: 400));
        if (s == _Port.acik) {
          (acik[a] ??= []).add(p);
          canli.add(a);
        } else if (s == _Port.reddetti) {
          canli.add(a);
        }
      }
    }

    final mobil = Platform.isAndroid || Platform.isIOS;
    await Future.wait(List.generate(mobil ? 48 : 96, (_) => isci()));
    final arp = arpOku == null ? const <String, String>{} : await arpOku();
    // Masaüstünde ARP, port yanıtı vermeyen (güvenlik duvarlı) cihazları da gösterir.
    for (final a in arp.keys) {
      if (a.startsWith(onek) && a != yerelIp) canli.add(a);
    }
    final liste = canli.toList()..sort((x, y) => _son(x).compareTo(_son(y)));
    final out = <Map<String, dynamic>>[];
    // Ayrıntılar 8'erli gruplar hâlinde (düşük güçlü tableti yormasın).
    for (var b = 0; b < liste.length && b < enCok; b += 8) {
      final grup = liste.sublist(b, (b + 8).clamp(0, liste.length.clamp(0, enCok)));
      out.addAll(await Future.wait([
        for (final a in grup) _ayrinti(a, (acik[a] ?? [])..sort(), true, arp[a], kimlikSor),
      ]));
    }
    return out;
  }

  static int _son(String ip) => int.tryParse(ip.substring(ip.lastIndexOf('.') + 1)) ?? 0;

  static Future<Map<String, dynamic>> _ayrinti(String ip, List<int> acik, bool reddeden, String? mac,
      Future<YaziciKimlik> Function(String ip, int port)? kimlikSor) async {
    final canli = acik.isNotEmpty || reddeden || mac != null;
    if (!canli) return {'ip': ip, 'canli': false};
    final r = await Future.wait<Object?>([
      _tersDns(ip),
      _mdnsAd(ip),
      _netbios(ip),
      acik.contains(80) ? _http(ip) : Future<Object?>.value(),
    ]);
    final nb = r[2] as ({String? ad, String? mac})?;
    final http = r[3] as Map<String, String>?;
    YaziciKimlik? k;
    if (acik.contains(9100) && kimlikSor != null) {
      try {
        k = await kimlikSor(ip, 9100);
      } catch (_) {}
    }
    final adlar = {'dns': ?r[0] as String?, 'mdns': ?r[1] as String?, 'netbios': ?nb?.ad};
    return {
      'ip': ip,
      'canli': true,
      'acik': acik,
      'reddeden': reddeden,
      'mac': ?(mac ?? nb?.mac),
      if (adlar.isNotEmpty) 'adlar': adlar,
      if (http != null && http.isNotEmpty) 'http': http,
      if (k != null && !k.bos) 'kimlik': k.toJson(),
    };
  }

  static Future<_Port> _portYokla(String ip, int port, Duration sure) async {
    try {
      final s = await Socket.connect(ip, port, timeout: sure);
      s.destroy();
      return _Port.acik;
    } on SocketException catch (e) {
      return reddedildiMi(e) ? _Port.reddetti : _Port.yok;
    } catch (_) {
      return _Port.yok;
    }
  }

  /// "Connection refused": cihaz VAR, port kapalı (RST döndü).
  static bool reddedildiMi(SocketException e) {
    final k = e.osError?.errorCode;
    if (k == 111 || k == 61 || k == 10061) return true;
    final m = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    return m.contains('refused');
  }

  static Future<String?> _tersDns(String ip) async {
    try {
      final r = await InternetAddress(ip).reverse().timeout(const Duration(milliseconds: 1500));
      final h = r.host.trim();
      return h.isEmpty || h == ip ? null : h;
    } catch (_) {
      return null;
    }
  }

  /// mDNS tekil (legacy unicast) PTR sorgusu: 5353 dışı kaynak porttan
  /// sorulduğunda Apple/Android/Linux yanıtlayıcıları doğrudan cevap verir.
  static Future<String?> _mdnsAd(String ip) async {
    final c = await _udp(ip, 5353, DnsPaket.ptrSorgusu(ip));
    if (c == null) return null;
    final ad = DnsPaket.ptrYaniti(c);
    return ad == null ? null : (ad.endsWith('.') ? ad.substring(0, ad.length - 1) : ad);
  }

  static Future<({String? ad, String? mac})?> _netbios(String ip) async {
    final c = await _udp(ip, 137, NetBios.sorgu());
    return c == null ? null : NetBios.yanit(c);
  }

  static Future<Uint8List?> _udp(String ip, int port, List<int> paket) async {
    RawDatagramSocket? s;
    try {
      s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final tamam = Completer<Uint8List?>();
      s.listen((o) {
        if (o != RawSocketEvent.read) return;
        final d = s?.receive();
        if (d != null && d.address.address == ip && !tamam.isCompleted) tamam.complete(d.data);
      });
      s.send(paket, InternetAddress(ip), port);
      return await tamam.future.timeout(const Duration(milliseconds: 1200), onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      s?.close();
    }
  }

  static Future<Map<String, String>?> _http(String ip) async {
    Socket? s;
    try {
      s = await Socket.connect(ip, 80, timeout: const Duration(seconds: 1));
      s.add(ascii.encode('GET / HTTP/1.0\r\nHost: $ip\r\nUser-Agent: BamBumPOS\r\nConnection: close\r\n\r\n'));
      await s.flush();
      final b = <int>[];
      await for (final d in s.timeout(const Duration(seconds: 2), onTimeout: (k) => k.close())) {
        b.addAll(d);
        if (b.length > 32768) break;
      }
      return HttpIpucu.ayristir(utf8.decode(b, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      s?.destroy();
    }
  }
}

enum _Port { acik, reddetti, yok }

/// En küçük DNS paket yardımcıları (mDNS PTR).
class DnsPaket {
  DnsPaket._();

  static List<int> ptrSorgusu(String ip) {
    final ad = '${ip.split('.').reversed.join('.')}.in-addr.arpa';
    return [
      0x00, 0x2A, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      for (final l in ad.split('.')) ...[l.length, ...ascii.encode(l)],
      0x00, 0x00, 0x0C, 0x00, 0x01,
    ];
  }

  /// İlk PTR cevabının hedef adı (sıkıştırmalı ad çözülür).
  static String? ptrYaniti(List<int> p) {
    try {
      if (p.length < 12) return null;
      final qd = (p[4] << 8) | p[5];
      final an = (p[6] << 8) | p[7];
      var o = 12;
      for (var i = 0; i < qd; i++) {
        o = ad(p, o).$2 + 4;
      }
      for (var i = 0; i < an; i++) {
        o = ad(p, o).$2;
        final tur = (p[o] << 8) | p[o + 1];
        final uz = (p[o + 8] << 8) | p[o + 9];
        o += 10;
        if (tur == 12) return ad(p, o).$1;
        o += uz;
      }
    } catch (_) {}
    return null;
  }

  /// Ad + adın bittiği ofset.
  static (String, int) ad(List<int> p, int o) {
    final parca = <String>[];
    int? donus;
    var adim = 0;
    while (true) {
      if (++adim > 64) throw const FormatException('döngü');
      final l = p[o];
      if (l == 0) {
        o++;
        break;
      }
      if (l & 0xC0 == 0xC0) {
        donus ??= o + 2;
        o = ((l & 0x3F) << 8) | p[o + 1];
        continue;
      }
      parca.add(utf8.decode(p.sublist(o + 1, o + 1 + l), allowMalformed: true));
      o += 1 + l;
    }
    return (parca.join('.'), donus ?? o);
  }
}

/// NetBIOS düğüm durum sorgusu (NBSTAT, UDP 137).
class NetBios {
  NetBios._();

  static List<int> sorgu() => [
        0x13, 0x37, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x20, 0x43, 0x4B, for (var i = 0; i < 30; i++) 0x41, 0x00,
        0x00, 0x21, 0x00, 0x01,
      ];

  /// Bilgisayar adı (benzersiz, sonek 0x00) ve kart MAC'i.
  static ({String? ad, String? mac})? yanit(List<int> p) {
    try {
      // 12 başlık + 34 ad + 2 tür + 2 sınıf + 4 TTL + 2 uzunluk = 56
      if (p.length < 57) return null;
      final n = p[56];
      var o = 57;
      String? ad;
      for (var i = 0; i < n; i++) {
        if (o + 18 > p.length) return null;
        final isim = String.fromCharCodes(p.sublist(o, o + 15).where((c) => c >= 0x20 && c < 0x7F)).trim();
        final sonek = p[o + 15];
        final grup = (p[o + 16] & 0x80) != 0;
        if (ad == null && sonek == 0x00 && !grup && isim.isNotEmpty) ad = isim;
        o += 18;
      }
      String? mac;
      if (o + 6 <= p.length) {
        mac = KimlikAyristir.macTemizle(p.sublist(o, o + 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':'));
      }
      return (ad == null && mac == null) ? null : (ad: ad, mac: mac);
    } catch (_) {
      return null;
    }
  }
}

/// HTTP yanıtından sayfa başlığı ve Server başlığı.
class HttpIpucu {
  HttpIpucu._();

  static Map<String, String> ayristir(String yanit) {
    final out = <String, String>{};
    final sunucu = RegExp(r'^server:\s*(.+)$', caseSensitive: false, multiLine: true).firstMatch(yanit);
    if (sunucu != null) out['sunucu'] = _kisa(sunucu.group(1)!);
    final baslik = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(yanit);
    if (baslik != null) {
      final t = _kisa(baslik.group(1)!.replaceAll(RegExp(r'\s+'), ' '));
      if (t.isNotEmpty) out['baslik'] = t;
    }
    return out;
  }

  static String _kisa(String s) {
    final t = s.trim();
    return t.length > 80 ? t.substring(0, 80) : t;
  }
}
