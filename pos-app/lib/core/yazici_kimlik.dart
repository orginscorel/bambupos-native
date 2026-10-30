import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// AĞ YAZICISI KİMLİĞİ (parmak izi) — 2026-10-30.
///
/// Neden: modem (DHCP) yazıcıya yeni IP verince kayıtlı adres boşa düşüyor
/// ve fişler basılmıyordu. Yazıcıyı adresinden değil KİMLİĞİNDEN tanımak
/// için iki iz toplanır:
///   • ESC/POS "transmit" komutları (GS I n): üretici, model, seri no,
///     yazılım sürümü. Bu komutlar yazıcıdan BİLGİ İSTER, kâğıda hiçbir şey
///     basmaz.
///   • Masaüstünde ARP tablosundan MAC adresi (Android'de okunamaz; sunucu
///     aynı ağdaki masaüstü ajanların raporlarını birleştirir).
///
/// KÂĞIDA BASMAMA GÜVENCESİ:
///   1) Önce yalnız DLE EOT 1 (10 04 01) gönderilir: tamamı denetim baytı,
///      yazdırılabilir karakter içermez; ESC/POS yazıcı bunu gerçek zamanlı
///      durum sorusu sayar ve tek bayt yanıt verir. Lazer/ofis yazıcısı
///      9100'de bu baytlarla sayfa çıkarmaz.
///   2) Yanıt ESC/POS durum baytı biçiminde DEĞİLSE bağlantı hemen kapanır;
///      GS I hiç gönderilmez.
///   3) Yazıcı çevrimdışı (kapak açık / kâğıt besleniyor) bildiriyorsa
///      GS I gönderilmez.
///   4) GS I'yı tanımayan bir klon tamponuna bir harf alırsa bile satır sonu
///      gönderilmediği için basılmaz; çıkışta ESC @ tamponu temizler (her
///      fiş de zaten ESC @ ile başlar).
///   5) Meşgul yazıcı (iş basılıyor) yoklanmaz — çağıran taraf denetler.
class YaziciKimlik {
  const YaziciKimlik({this.mac, this.seri, this.model, this.uretici, this.surum, this.modelKodu, this.escpos = false});

  final String? mac;
  final String? seri;
  final String? model;
  final String? uretici;
  final String? surum;

  /// GS I 1 / GS I 2 tek bayt yanıtları ("20/02" gibi): zayıf ipucu.
  final String? modelKodu;

  /// DLE EOT 1'e ESC/POS biçiminde yanıt verdi mi?
  final bool escpos;

  bool get bos => mac == null && seri == null && model == null && uretici == null && surum == null && modelKodu == null && !escpos;

  YaziciKimlik macIle(String? m) =>
      YaziciKimlik(mac: m ?? mac, seri: seri, model: model, uretici: uretici, surum: surum, modelKodu: modelKodu, escpos: escpos);

  Map<String, dynamic> toJson() => {
        'mac': ?mac,
        'seri': ?seri,
        'model': ?model,
        'uretici': ?uretici,
        'surum': ?surum,
        'model_kodu': ?modelKodu,
        'escpos': escpos,
      };

  @override
  String toString() => jsonEncode(toJson());
}

/// Yanıt ayrıştırma — saf işlevler (birim testli: test/yazici_kimlik_test.dart).
class KimlikAyristir {
  KimlikAyristir._();

  /// DLE EOT 1 — gerçek zamanlı yazıcı durumu.
  static const durumSorusu = [0x10, 0x04, 0x01];

  /// ESC @ — yazıcıyı başlatır, yazdırma tamponunu temizler (basmaz).
  static const baslat = [0x1B, 0x40];

  /// Sorulan GS I parametreleri: 1 model kodu, 2 tür kodu, 65 yazılım,
  /// 66 üretici, 67 model adı, 68 seri no.
  static const sorular = [1, 2, 66, 67, 68, 65];

  static List<int> gsI(int n) => [0x1D, 0x49, n];

  /// ESC/POS DLE EOT 1 yanıtı: bit0=0, bit1=1, bit4=1, bit7=0 sabittir.
  static bool durumBaytiMi(int b) => b >= 0 && b <= 255 && (b & 0x93) == 0x12;

  /// Bit3: yazıcı çevrimdışı.
  static bool cevrimdisiMi(int b) => (b & 0x08) != 0;

  /// GS I 65..69 yanıtı: 0x5F + ASCII veri + 0x00. Tamamlanmadıysa null.
  /// Veri yazdırılabilir ASCII'ye süzülür, kırpılır; boşsa null.
  static String? metin(List<int> bayt) {
    final bas = bayt.indexOf(0x5F);
    if (bas < 0) return null;
    final son = bayt.indexOf(0x00, bas + 1);
    if (son < 0) return null;
    final s = String.fromCharCodes(bayt.sublist(bas + 1, son).where((c) => c >= 0x20 && c < 0x7F)).trim();
    return s.isEmpty || s.length > 80 ? null : s;
  }

  /// GS I 65..69 yanıtı tamamlandı mı (başlık + NUL geldi)?
  static bool metinTamam(List<int> bayt) {
    final bas = bayt.indexOf(0x5F);
    return bas >= 0 && bayt.indexOf(0x00, bas + 1) > bas;
  }

  /// GS I 1/2 yanıtı: tek bayt (başlıksız). 0x5F başlıklıysa metin sayılır.
  static String? tekBayt(List<int> bayt) {
    if (bayt.isEmpty) return null;
    if (bayt.first == 0x5F) return metin(bayt);
    return bayt.first.toRadixString(16).padLeft(2, '0');
  }

  /// Seri no anlamlı mı? Fabrika boşlukları ("000000", "123456789",
  /// "XXXXXXXX", tek karakter tekrarı) kimlik sayılmaz: iki farklı yazıcıda
  /// aynı çıkabilir.
  static String? seriTemizle(String? s) {
    if (s == null) return null;
    final t = s.trim();
    if (t.length < 4 || t.length > 64) return null;
    final k = t.toUpperCase();
    if (RegExp(r'^(.)\1+$').hasMatch(k)) return null;
    const bos = {'123456789', '1234567890', '12345678', '0123456789', 'SERIAL', 'NONE', 'NULL', 'UNKNOWN', 'DEFAULT'};
    if (bos.contains(k)) return null;
    return t;
  }

  /// MAC biçimini birleştirir: "0-11-22-a-b-c" / "00:11:22:0a:0b:0c" →
  /// "00:11:22:0A:0B:0C". Yayın / sıfır / çoklu yayın adresleri null.
  static String? macTemizle(String? m) {
    if (m == null) return null;
    final p = m.trim().split(RegExp(r'[:\-]'));
    if (p.length != 6) return null;
    final o = <String>[];
    for (final x in p) {
      if (x.isEmpty || x.length > 2 || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(x)) return null;
      o.add(x.toUpperCase().padLeft(2, '0'));
    }
    final s = o.join(':');
    if (s == '00:00:00:00:00:00' || s == 'FF:FF:FF:FF:FF:FF') return null;
    if (int.parse(o.first, radix: 16) & 0x01 == 1) return null; // çoklu yayın
    return s;
  }

  /// ARP çıktısını IP → MAC eşlemine çevirir. Windows (`arp -a`):
  ///   "  192.168.1.102        00-11-22-33-44-55     dynamic"
  /// macOS / Linux (`arp -an`):
  ///   "? (192.168.1.102) at 0:11:22:33:44:55 on en0 ifscope [ethernet]"
  /// Linux /proc/net/arp:
  ///   "192.168.1.102 0x1 0x2 00:11:22:33:44:55 * eth0"
  /// Aynı MAC birden çok IP'de görünürse (Wi-Fi tekrarlayıcı MAC çevirisi)
  /// o MAC hiçbir IP'ye verilmez: kimlik sayılamaz.
  static Map<String, String> arp(String cikti) {
    final ham = <String, String>{};
    final ipDesen = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})');
    final macDesen = RegExp(r'([0-9A-Fa-f]{1,2}(?:[:\-][0-9A-Fa-f]{1,2}){5})');
    for (final satir in const LineSplitter().convert(cikti)) {
      final i = ipDesen.firstMatch(satir);
      final m = macDesen.firstMatch(satir.substring(i?.end ?? 0));
      if (i == null || m == null) continue;
      final mac = macTemizle(m.group(1));
      if (mac == null) continue;
      ham[i.group(1)!] = mac;
    }
    final sayi = <String, int>{};
    for (final m in ham.values) {
      sayi[m] = (sayi[m] ?? 0) + 1;
    }
    return {for (final e in ham.entries) if (sayi[e.value] == 1) e.key: e.value};
  }
}

/// Yoklayıcı: soketle sorar, ARP okur.
class KimlikYoklayici {
  KimlikYoklayici._();

  static const _baglanmaSuresi = Duration(milliseconds: 900);
  static const _yanitSuresi = Duration(milliseconds: 450);

  /// [ip]:[port]'taki cihaza kimlik sorar. ESC/POS değilse ya da yanıt
  /// vermezse `escpos=false` döner (hiçbir GS I gönderilmeden).
  static Future<YaziciKimlik> sor(String ip, int port) async {
    Socket? s;
    try {
      s = await Socket.connect(ip, port, timeout: _baglanmaSuresi);
      final tampon = <int>[];
      var tetik = Completer<void>();
      final abone = s.listen((d) {
        tampon.addAll(d);
        if (!tetik.isCompleted) tetik.complete();
      }, onError: (_) {}, onDone: () {
        if (!tetik.isCompleted) tetik.complete();
      }, cancelOnError: false);

      Future<List<int>> bekle(bool Function(List<int>) tamam) async {
        final bitis = DateTime.now().add(_yanitSuresi);
        while (!tamam(tampon)) {
          final kalan = bitis.difference(DateTime.now());
          if (kalan <= Duration.zero) break;
          tetik = Completer<void>();
          await tetik.future.timeout(kalan, onTimeout: () {});
        }
        final c = List<int>.from(tampon);
        tampon.clear();
        return c;
      }

      // 1) Durum sorusu — yalnız denetim baytı.
      s.add(KimlikAyristir.durumSorusu);
      await s.flush();
      final d = await bekle((b) => b.isNotEmpty);
      if (d.isEmpty || !KimlikAyristir.durumBaytiMi(d.first)) {
        await abone.cancel();
        return const YaziciKimlik();
      }
      if (KimlikAyristir.cevrimdisiMi(d.first)) {
        await abone.cancel();
        return const YaziciKimlik(escpos: true);
      }

      // 2) GS I soruları — birer birer; yanıtsız olan atlanır.
      final y = <int, String?>{};
      var yanitsiz = false;
      for (final n in KimlikAyristir.sorular) {
        s.add(KimlikAyristir.gsI(n));
        await s.flush();
        final cevap = await bekle(n >= 65 ? KimlikAyristir.metinTamam : (b) => b.isNotEmpty);
        if (cevap.isEmpty) yanitsiz = true;
        y[n] = n >= 65 ? KimlikAyristir.metin(cevap) : KimlikAyristir.tekBayt(cevap);
      }
      // Tanınmayan komut tampona bir şey bırakmış olabilir: temizle.
      if (yanitsiz) {
        s.add(KimlikAyristir.baslat);
        await s.flush();
      }
      await abone.cancel();
      final kod = [y[1], y[2]].whereType<String>().join('/');
      return YaziciKimlik(
        escpos: true,
        uretici: y[66],
        model: y[67],
        seri: KimlikAyristir.seriTemizle(y[68]),
        surum: y[65],
        modelKodu: kod.isEmpty ? null : kod,
      );
    } catch (_) {
      return const YaziciKimlik();
    } finally {
      try {
        await s?.close();
      } catch (_) {}
      s?.destroy();
    }
  }

  /// Masaüstünde ARP tablosu (IP → MAC). Android / iOS'ta boş döner.
  static Future<Map<String, String>> arpTablosu() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) return const {};
      if (Platform.isLinux) {
        final f = File('/proc/net/arp');
        if (await f.exists()) return KimlikAyristir.arp(await f.readAsString());
      }
      final r = await Process.run('arp', Platform.isWindows ? ['-a'] : ['-an'], runInShell: Platform.isWindows)
          .timeout(const Duration(seconds: 4));
      if (r.exitCode != 0) return const {};
      return KimlikAyristir.arp('${r.stdout}');
    } catch (_) {
      return const {};
    }
  }
}
