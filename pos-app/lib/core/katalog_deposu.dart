import 'durum.dart';
import 'modeller.dart';

/// Sipariş kataloğu: bellekte tek kopya + diskte kalıcı + ETag.
///
/// Sunucu katalog sürümünden ETag üretir; menü değişmediyse 304 döner ve
/// gövde inmez. Adisyon ekranı bu yüzden ANINDA açılır, fiyat değişince
/// ilk açılışta tazelenir.
class KatalogDeposu {
  KatalogDeposu._();
  static final KatalogDeposu ornek = KatalogDeposu._();

  Katalog? katalog;
  String? _etag;
  int? _sube;
  Future<Katalog?>? _suren;

  Future<Katalog?> yukle(UygulamaDurumu durum) => _suren ??= _yukle(durum).whenComplete(() => _suren = null);

  Future<Katalog?> _yukle(UygulamaDurumu durum) async {
    final sube = durum.oturum?.subeId ?? 0;
    final ad = 'katalog_$sube';

    if (_sube != sube) {
      katalog = null;
      _etag = null;
      _sube = sube;
    }

    if (katalog == null) {
      final ham = await durum.onbellekOku(ad);
      if (ham != null) {
        katalog = Katalog(ham);
        _etag = durum.tercihOku('${ad}_etag');
      }
    }

    try {
      final r = await durum.api.getEtagli('/api/v1/orders/catalog', _etag, sorgu: {'branch_id': sube});
      if (r != null) {
        final ham = (r.veri as Map).cast<String, dynamic>();
        katalog = Katalog(ham);
        _etag = r.etag;
        await durum.onbellekYaz(ad, ham);
        await durum.tercihYaz('${ad}_etag', r.etag);
      }
    } catch (_) {
      // Ağ yoksa elimizdeki katalogla devam.
      if (katalog == null) rethrow;
    }
    return katalog;
  }
}
