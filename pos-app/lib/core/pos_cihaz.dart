import 'dart:async';
import 'dart:io';

/// KONSOLDA TANIMLI KART POS CİHAZLARI (terminal-status `manuel_cihazlar`).
///
/// Ethernet'li cihazlarda (ör. inPos M530, 192.168.1.2:59000) kasa ekranı
/// kart seçilince arka planda hızlı bir TCP bağlantı denemesi yapar: cihaz
/// açık ve aynı ağda mı? TUTAR CİHAZA GÖNDERİLMEZ (inPos ECR protokolü yok);
/// ödeme her zaman kasiyer onayıyla tamamlanır.

/// Kasada görünen ad: `ad`, yoksa "Marka - Model", yoksa banka.
String posCihazAdi(Map c) {
  String? m(String k) {
    final v = c[k]?.toString().trim();
    return v == null || v.isEmpty ? null : v;
  }

  final ad = m('ad');
  if (ad != null) return ad;
  final mm = [?m('marka'), ?m('model')].join(' - ');
  if (mm.isNotEmpty) return mm;
  return m('banka') ?? 'Kart POS';
}

/// 'ethernet' | 'usb' | null (bağlantı bilgisi yok → eski davranış).
String? posBaglanti(Map c) {
  final b = c['baglanti']?.toString().toLowerCase();
  return b == 'ethernet' || b == 'usb' ? b : null;
}

/// Ethernet cihazının adresi (ip + port). Eksikse null.
({String ip, int port})? posAdres(Map c) {
  if (posBaglanti(c) != 'ethernet') return null;
  final ip = c['ip']?.toString().trim() ?? '';
  final port = c['port'] is num ? (c['port'] as num).toInt() : int.tryParse('${c['port'] ?? ''}');
  if (ip.isEmpty || port == null || port <= 0 || port > 65535) return null;
  return (ip: ip, port: port);
}

/// Bağlantı denemesi süresi: cihazın zaman aşımı ama en çok 3 sn (en az 0,5 sn).
Duration posDenetimSuresi(Object? zamanAsimiMs) {
  final ms = zamanAsimiMs is num ? zamanAsimiMs.toInt() : int.tryParse('${zamanAsimiMs ?? ''}');
  return Duration(milliseconds: (ms == null || ms <= 0 ? 3000 : ms).clamp(500, 3000));
}

typedef SoketBaglayici = Future<Socket> Function(String ip, int port, Duration sure);

Future<Socket> _gercekBaglan(String ip, int port, Duration sure) => Socket.connect(ip, port, timeout: sure);

/// ip:port'a TCP bağlantısı açılabiliyor mu? Bağlantı hemen kapatılır.
Future<bool> posTcpErisilebilir(String ip, int port, Duration sure, {SoketBaglayici baglan = _gercekBaglan}) async {
  try {
    final s = await baglan(ip, port, sure).timeout(sure + const Duration(milliseconds: 500));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

/// Son denetim sonuçları (aynı cihaz 30 sn içinde yeniden denenmez).
class PosErisimOnbellegi {
  PosErisimOnbellegi({this.baglan = _gercekBaglan, this.tazelik = const Duration(seconds: 30)});
  final SoketBaglayici baglan;
  final Duration tazelik;
  final _sonuc = <String, (bool, DateTime)>{};
  final _suruyor = <String, Future<bool>>{};

  /// null = henüz denetlenmedi / sürüyor.
  bool? durum(String ip, int port) => _sonuc['$ip:$port']?.$1;

  bool tazeMi(String ip, int port) {
    final s = _sonuc['$ip:$port'];
    return s != null && DateTime.now().difference(s.$2) < tazelik;
  }

  Future<bool> denetle(String ip, int port, Duration sure) {
    final k = '$ip:$port';
    return _suruyor[k] ??= posTcpErisilebilir(ip, port, sure, baglan: baglan).then((ok) {
      _sonuc[k] = (ok, DateTime.now());
      return ok;
    }).whenComplete(() {
      // Blok gövde: remove() bu Future'ı döndürür; ok işaretiyle kendini beklerdi.
      _suruyor.remove(k);
    });
  }
}
