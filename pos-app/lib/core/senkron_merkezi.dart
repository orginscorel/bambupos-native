import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';

/// Değişimdeki tek olay (sunucu `olaylar[]`).
class SenkronOlayi {
  const SenkronOlayi({required this.adisyonId, required this.tur, this.hedefId});
  final int adisyonId;
  final String tur;

  /// `merged_into` / `item_moved_out` olayında kalemlerin gittiği adisyon.
  final int? hedefId;
}

/// Dinleyicilere giden haber.
///
/// * [tam] = ne değiştiği bilinmiyor (imleç sıfırlandı, olay taştı, uygulama
///   öne geldi) → herkes kendini baştan yüklesin.
/// * [yerel] = bu cihazın kendi yazma işlemi (yanıtı ekrana zaten basıldı);
///   adisyon ekranı kendi id'si için yeniden sormaz, pano/kasa yenilenir.
class SenkronDegisimi {
  const SenkronDegisimi({this.adisyonlar = const {}, this.olaylar = const [], this.tam = false, this.yerel = false});
  final Set<int> adisyonlar;
  final List<SenkronOlayi> olaylar;
  final bool tam;
  final bool yerel;

  bool ilgilendirir(int adisyonId) => tam || adisyonlar.contains(adisyonId);

  /// Adisyon bu değişimde başka bir adisyona BİRLEŞTİRİLDİYSE hedefi.
  int? birlesmeHedefi(int adisyonId) {
    for (final o in olaylar.reversed) {
      if (o.adisyonId == adisyonId && o.tur == 'merged_into' && (o.hedefId ?? 0) > 0) return o.hedefId;
    }
    return null;
  }
}

/// SENKRON MERKEZİ (2026-10-30) — adisyon değişimlerinin ortak kaynağı.
///
/// Saha bildirimi: masa birleştirmeden sonra personel adisyonu panoda
/// bulamıyor, birkaç saniye sonra "geliyordu". Ekranlar 3-5 sn'lik kendi
/// yoklamalarıyla tazeleniyordu; artık:
///
///  1. Oturum (kabuk) açıkken `GET /api/v1/orders/degisim?imlec=N` UZUN
///     YOKLAMAYLA izlenir (sunucu olay düşene kadar ~20 sn bekler, KDS ile
///     aynı kalıp). Olay gelince [degisimler] akışına haber düşer; masa
///     panosu, adisyon ve kasa ekranları anında yenilenir.
///  2. Bu cihazın kendi yazma işlemi ([yerelDegisim]) beklemeden haber verir
///     (sunucu ucu yoksa da çalışır).
///  3. Hata / ağ yoksa artan bekleme (2 → 60 sn); ekranların kendi 3-5 sn
///     yoklaması YEDEK olarak sürdüğü için veri yine gelir.
///  4. Uygulama arka plandayken döngü durur; öne gelince imleçsiz bir
///     tazeleme yapılır ve herkese [SenkronDegisimi.tam] gider.
///  5. Eski sunucuda uç yoksa (404) ya da yetki yoksa (403) sessizce
///     devre dışı kalır.
class SenkronMerkezi {
  SenkronMerkezi(this._api);

  final Api _api;
  final _akis = StreamController<SenkronDegisimi>.broadcast();

  /// Sunucu "bu cihazın personeli başka cihazda giriş yaptı" dedi (1.2.44):
  /// durum oturumu tazeler → ~1 sn'de PIN ekranı.
  void Function()? operatorDustu;

  /// Değişim haberleri (abonelik `dispose`'ta iptal edilmeli).
  Stream<SenkronDegisimi> get degisimler => _akis.stream;

  /// Sunucu ucu yok / yetki yok → uzun yoklama kapalı (yerel haberler sürer).
  bool get devreDisi => _devreDisi;
  bool _devreDisi = false;

  /// Uzun yoklama son turda sunucuya ulaştı mı (tanı için).
  bool get canli => _canli;
  bool _canli = false;

  static const _yol = '/api/v1/orders/degisim';
  static const _istekZamanAsimi = Duration(seconds: 45);
  static const _enUzunBekleme = Duration(seconds: 60);

  int? _imlec;
  int _nesil = 0;
  int _kullanici = 0;
  bool _calisiyor = false;
  int _hataSayisi = 0;
  AppLifecycleListener? _yasam;

  /// Kabuk açılınca çağrılır. Sayaçlıdır: kabuk cihaz/istasyon değişince
  /// yeniden kurulurken YENİ kabuğun baslat'ı eskinin durdur'undan önce
  /// gelebilir; son kullanıcı bırakınca döngü durur.
  void baslat() {
    _kullanici++;
    if (_calisiyor) return;
    _calisiyor = true;
    _yasam ??= AppLifecycleListener(
      onResume: _oneGeldi,
      onPause: _arkayaGitti,
      onHide: _arkayaGitti,
      onDetach: _arkayaGitti,
    );
    _imlec = null;
    _hataSayisi = 0;
    if (uygulamaOnde()) _donguyuBaslat();
  }

  /// Kabuk kapanınca (PIN ekranı / aktivasyon) çağrılır.
  void durdur() {
    if (_kullanici > 0) _kullanici--;
    if (_kullanici > 0) return;
    _calisiyor = false;
    _nesil++;
    _canli = false;
    _yasam?.dispose();
    _yasam = null;
  }

  /// Bu cihaz bir adisyonu değiştirdi (birleştir/taşı/kapat/ödeme …).
  /// [adisyonlar] boşsa pano ve kasa yine de yenilenir.
  void yerelDegisim({Iterable<int> adisyonlar = const []}) {
    if (_akis.isClosed) return;
    _akis.add(SenkronDegisimi(adisyonlar: adisyonlar.where((x) => x > 0).toSet(), yerel: true));
  }

  void _oneGeldi() {
    if (!_calisiyor) return;
    // Arka plandayken kaçan her şey: imleçsiz tazele, herkese "tam" haber.
    _imlec = null;
    _hataSayisi = 0;
    if (!_akis.isClosed) _akis.add(const SenkronDegisimi(tam: true));
    _donguyuBaslat();
  }

  void _arkayaGitti() {
    _nesil++; // süren istek bitince sonucu yok sayılır, döngü durur
    _canli = false;
  }

  void _donguyuBaslat() {
    if (_devreDisi || !_calisiyor) return;
    final nesil = ++_nesil;
    unawaited(_dongu(nesil));
  }

  bool _gecerli(int nesil) => nesil == _nesil && _calisiyor && !_devreDisi;

  Future<void> _dongu(int nesil) async {
    while (_gecerli(nesil)) {
      final baslangic = DateTime.now();
      try {
        final imlec = _imlec;
        final r = await _api.get(_yol,
            sorgu: imlec == null ? null : {'imlec': imlec}, zamanAsimi: _istekZamanAsimi);
        if (!_gecerli(nesil)) return;
        _hataSayisi = 0;
        _canli = true;

        if (r is Map) {
          _isle(r.cast<String, dynamic>(), ilk: imlec == null);
        } else if (DateTime.now().difference(baslangic) < const Duration(seconds: 2)) {
          // 204 hemen döndü (sunucuda uzun yoklama kapalı): döngü sunucuyu
          // dövmesin, ekranların kendi yoklaması kadar bekle.
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      } on ApiHata catch (e) {
        if (!_gecerli(nesil)) return;
        _canli = false;
        if (e.kod == 404 || e.kod == 405 || e.yetkiYok) {
          // Eski sunucu (uç yok) ya da rol yetkisiz: sessizce kapan, 5 sn yoklama yeter.
          _devreDisi = true;
          return;
        }
        if (e.oturumYok) return; // durum aktivasyona geçer, kabuk durdurur
        _hataSayisi++;
        final sn = 1 << _hataSayisi.clamp(1, 6); // 2, 4, 8 … 64
        final bekle = Duration(seconds: sn) > _enUzunBekleme ? _enUzunBekleme : Duration(seconds: sn);
        await Future<void>.delayed(bekle);
      } catch (_) {
        if (!_gecerli(nesil)) return;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  }

  void _isle(Map<String, dynamic> r, {required bool ilk}) {
    final yeniImlec = (r['imlec'] as num?)?.toInt();
    if (yeniImlec != null) _imlec = yeniImlec;
    if (r['operator_dustu'] == true) {
      operatorDustu?.call();
      return;
    }
    if (ilk || r['ilk'] == true) return; // başlangıç imleci: ekranlar zaten kendini yüklüyor
    if (_akis.isClosed) return;

    if (r['sifirlandi'] == true || r['tasma'] == true) {
      _akis.add(const SenkronDegisimi(tam: true));
      return;
    }

    final adisyonlar = <int>{
      for (final x in (r['degisen_adisyonlar'] as List? ?? const [])) (x as num?)?.toInt() ?? 0,
    }..remove(0);
    final olaylar = [
      for (final o in (r['olaylar'] as List? ?? const []).whereType<Map>())
        SenkronOlayi(
          adisyonId: (o['order_id'] as num?)?.toInt() ?? 0,
          tur: '${o['tur'] ?? ''}',
          hedefId: (o['hedef_adisyon_id'] as num?)?.toInt(),
        ),
    ];
    if (adisyonlar.isEmpty && olaylar.isEmpty) return;
    _akis.add(SenkronDegisimi(adisyonlar: adisyonlar, olaylar: olaylar));
  }

  void dispose() {
    _kullanici = 0;
    durdur();
    _akis.close();
  }
}
