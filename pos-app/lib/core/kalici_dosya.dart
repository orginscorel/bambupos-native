import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';

/// KESİNTİYE DAYANIKLI DOSYA YAZIMI (2026-10-30).
///
/// SAHA ARIZASI: Çamlık kasa bilgisayarı (Windows) yeniden açılınca kendi
/// kendine aktivasyon ekranına düştü. Sunucuda hiçbir şey kapatılmamıştı;
/// çerez dosyası yazılırken uygulama kapanmış, dosya BOŞ kalmıştı.
/// cookie_jar'ın FileStorage'ı `writeAsString` ile önce dosyayı sıfırlayıp
/// sonra yazıyor; Laravel her yanıtta çerezi tazelediği için bu dosya
/// saniyede birkaç kez baştan yazılıyordu. Arada süreç biterse (pencere
/// kapatma, çökme, Windows kapanışı, antivirüs kilidi) bütün çerezler gider.
///
/// Burada yazma ATOMİKTİR: önce `<dosya>.tmp` yazılır ve diske zorlanır,
/// sonra tek hamlede asıl dosyanın üstüne taşınır. Ardından aynı içerik
/// `<dosya>.bak` olarak da saklanır. Okurken asıl dosya yok / boş / bozuksa
/// sırasıyla `.bak` ve (taşınamadan kalmış) `.tmp` denenir. Bozuk okuma
/// HİÇBİR ZAMAN iyi veriyi silmez.
class AtomikDosya {
  AtomikDosya._();

  /// Aynı yola eşzamanlı iki yazma `.tmp` dosyasında çakışmasın.
  static final Map<String, Future<void>> _siralar = {};

  /// İçerik geçerli JSON (nesne ya da liste) mi?
  static bool jsonMu(String metin) {
    try {
      final v = jsonDecode(metin);
      return v is Map || v is List;
    } catch (_) {
      return false;
    }
  }

  static Future<void> yaz(String yol, String icerik) {
    final onceki = _siralar[yol] ?? Future<void>.value();
    final is_ = onceki.catchError((_) {}).then((_) => _yaz(yol, icerik));
    _siralar[yol] = is_;
    is_.whenComplete(() {
      if (identical(_siralar[yol], is_)) _siralar.remove(yol);
    }).ignore();
    return is_;
  }

  static Future<void> _yaz(String yol, String icerik) async {
    final dosya = File(yol);
    await dosya.parent.create(recursive: true);

    // 1) Asıl dosya: .tmp → diske zorla → üstüne taşı (atomik).
    await _tmpUzerindenYaz(yol, '$yol.tmp', icerik);

    // 2) Yedek: aynı yöntemle. Yedek yazılamazsa asıl dosya zaten sağlam.
    try {
      await _tmpUzerindenYaz('$yol.bak', '$yol.bak.tmp', icerik);
    } catch (_) {}
  }

  static Future<void> _tmpUzerindenYaz(String hedef, String gecici, String icerik) async {
    final tmp = File(gecici);
    await tmp.writeAsString(icerik, flush: true);
    FileSystemException? sonHata;
    // Windows'ta antivirüs / dizin tarayıcı hedefi bir an kilitleyebilir: birkaç kez dene.
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.rename(hedef);
        return;
      } on FileSystemException catch (e) {
        sonHata = e;
        await Future<void>.delayed(Duration(milliseconds: 40 * (i + 1)));
      }
    }
    // Taşınamadı: .tmp tam ve diskte duruyor (okuma onu da dener); hata yukarı gider.
    throw sonHata!;
  }

  /// Asıl → .bak → .tmp sırasıyla ilk GEÇERLİ içeriği döndürür; hiçbiri yoksa null.
  static Future<String?> oku(String yol, {bool Function(String metin)? gecerli}) async {
    final denetle = gecerli ?? jsonMu;
    for (final aday in [yol, '$yol.bak', '$yol.tmp', '$yol.bak.tmp']) {
      try {
        final f = File(aday);
        if (!await f.exists()) continue;
        final metin = await f.readAsString();
        if (metin.trim().isEmpty || !denetle(metin)) continue;
        return metin;
      } catch (_) {
        // okunamadı / yarım UTF-8: sıradaki aday
      }
    }
    return null;
  }

  /// Dosyayı ve bütün kopyalarını siler (yalnız bilinçli silmede çağrılır).
  static Future<void> sil(String yol) async {
    for (final aday in [yol, '$yol.bak', '$yol.tmp', '$yol.bak.tmp']) {
      try {
        final f = File(aday);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

/// cookie_jar deposu: FileStorage'ın AYNI dizin düzeniyle (mevcut kurulumların
/// çerezleri olduğu gibi okunur) ama atomik yazma + yedekten okuma ile.
class DayanikliCerezDeposu implements Storage {
  DayanikliCerezDeposu(this.dizin);

  /// FileStorage'a verilen kök dizinle aynı (…/cerezler/).
  final String dizin;
  late String _gecerliDizin;

  /// Test: init sonrası çerez dosyalarının durduğu dizin.
  String get gecerliDizin => _gecerliDizin;

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {
    // FileStorage.init ile birebir aynı yol (4.0.x): <kök>/ie0_ps1/
    var kok = dizin.replaceAll('\\', '/');
    if (!kok.endsWith('/')) kok += '/';
    _gecerliDizin = '${kok}ie${ignoreExpires ? 1 : 0}_ps${persistSession ? 1 : 0}/';
    await Directory(_gecerliDizin).create(recursive: true);
  }

  String _yol(String anahtar) => '$_gecerliDizin$anahtar';

  @override
  Future<String?> read(String key) => AtomikDosya.oku(_yol(key));

  @override
  Future<void> write(String key, String value) => AtomikDosya.yaz(_yol(key), value);

  @override
  Future<void> delete(String key) => AtomikDosya.sil(_yol(key));

  @override
  Future<void> deleteAll(List<String> keys) async {
    final d = Directory(_gecerliDizin);
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);
  }
}

/// Cihaz kurtarma anahtarı: çerezler kaybolursa oturumu geri almak için
/// (sunucu yalnız özetini saklar; bkz. POST /api/v1/uygulama/kurtar).
class KurtarmaAnahtari {
  const KurtarmaAnahtari(this.terminalId, this.anahtar);

  final int terminalId;
  final String anahtar;

  Map<String, dynamic> toJson() => {'terminal_id': terminalId, 'anahtar': anahtar};

  static KurtarmaAnahtari? jsondan(Object? v) {
    if (v is! Map) return null;
    final id = v['terminal_id'];
    final a = v['anahtar'];
    final tid = id is int ? id : int.tryParse('$id');
    if (tid == null || tid <= 0 || a is! String || a.length < 40) return null;
    return KurtarmaAnahtari(tid, a);
  }
}

/// Anahtar ÇEREZLERDEN AYRI, kendi küçük dosyasında (atomik + .bak) durur:
/// çerez dosyası bozulsa bile anahtar sağlam kalır.
class KurtarmaDeposu {
  KurtarmaDeposu(String dizin) : yol = '$dizin${Platform.pathSeparator}kurtarma.json';

  final String yol;

  Future<KurtarmaAnahtari?> oku() async {
    final metin = await AtomikDosya.oku(yol, gecerli: (m) {
      try {
        return KurtarmaAnahtari.jsondan(jsonDecode(m)) != null;
      } catch (_) {
        return false;
      }
    });
    return metin == null ? null : KurtarmaAnahtari.jsondan(jsonDecode(metin));
  }

  Future<void> yaz(KurtarmaAnahtari a) => AtomikDosya.yaz(yol, jsonEncode(a.toJson()));

  Future<void> sil() => AtomikDosya.sil(yol);
}
