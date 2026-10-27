import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/katalog_deposu.dart';
import '../core/modeller.dart';
import 'adet_kartlari.dart';
import 'adisyon_pencereleri.dart';
import 'cerceve.dart';
import 'kabuk.dart';
import 'nedenler.dart';
import 'ekran_klavyesi.dart';
import 'ortak.dart';
import 'urun_secimi.dart';

/// ADİSYON — web /panel/siparisler/{id} (Detail.vue) birebiri.
/// Şartname: /root/work/spec/adisyon-detay.md (bölüm numaraları ona göre).
///
/// Bu ekranda PARA ALINMAZ (web'de de yok): ödeme kasada.
/// Boş adisyon kuralları (§5.8 / §5.9):
///  - Hiç ürün girilmemiş adisyondan çıkınca (ya da uygulama arka plana
///    geçince) `discard-if-empty` → masa boşa döner, 0 TL adisyon kalmaz.
///  - Son kalem çıkarılınca sunucu adisyonu kendisi kapatır (keep_open
///    GÖNDERİLMEZ — web de göndermez).
///  - Tüm kalemler iptal edildiyse "Adisyonda ürün kalmadı" sorulur.
class AdisyonEkrani extends StatefulWidget {
  const AdisyonEkrani({super.key, required this.adisyonId, this.kasaKipi = false});
  final int adisyonId;
  final bool kasaKipi;

  @override
  State<AdisyonEkrani> createState() => _AdisyonEkraniState();
}

/// Web olay adları (eventTypeLabels).
const _olayAdlari = {
  'opened': 'Adisyon açıldı',
  'item_added': 'Kalem eklendi',
  'item_updated': 'Kalem güncellendi',
  'item_removed': 'Kalem çıkarıldı',
  'item_cancelled': 'Kalem iptal',
  'item_comped': 'İkram',
  'item_status_changed': 'Kalem durumu',
  'item_moved_in': 'Kalem geldi',
  'item_moved_out': 'Kalem taşındı',
  'status_changed': 'Durum değişti',
  'status_derived': 'Durum güncellendi',
  'discount_applied': 'İndirim',
  'payment_recorded': 'Ödeme',
  'cancelled': 'İptal',
  'refunded': 'İade',
  'order_moved': 'Adisyon taşındı',
  'merged_from': 'Birleştirildi (alındı)',
  'merged_into': 'Birleştirildi',
  'split_out': 'Bölündü',
  'split_from': 'Bölünerek açıldı',
  'split_shares': 'Hesap payları',
  'payment_reversed': 'Ödeme iptal (void)',
  'refund_applied': 'İade işlendi',
  'service_charge_applied': 'Servis bedeli',
  'rounding_applied': 'Yuvarlama',
  'sent_to_kitchen': 'Hazırlığa gönderildi',
  'item_swapped': 'Ürün değiştirildi',
  'items_added_public': 'Müşteri QR menüden ekledi',
  'items_served_on_payment': 'Ödemede servis edildi sayıldı',
  'order_info_updated': 'Adisyon bilgisi güncellendi',
  'discount_removed': 'İndirim kaldırıldı',
  'debt_transferred': 'Borca taşındı',
  'payment_reconciled': 'Ödeme tamamlandı, adisyon kapandı',
  'auto_closed_empty': 'Boş adisyon otomatik kapatıldı',
};

/// Adisyon/kalem durum etiketleri (Geçmiş sekmesinde "→ durum").
const _durumAdlari = {
  'draft': 'Taslak',
  'pending_approval': 'Onay bekliyor',
  'placed': 'Hazırlanıyor',
  'sent_to_station': 'Hazırlanıyor',
  'accepted': 'Hazırlanıyor',
  'preparing': 'Hazırlanıyor',
  'partially_ready': 'Hazırlanıyor',
  'ready': 'Garson & Komi bekliyor',
  'awaiting_service': 'Garson & Komi bekliyor',
  'served': 'Servis edildi',
  'bill_requested': 'Hesap istendi',
  'partially_paid': 'Kısmi ödendi',
  'paid': 'Ödendi',
  'cancelled': 'İptal',
  'refunded': 'İade',
  'debt_transferred': 'Borca taşındı',
};

Color _durumRengi(String? v) => switch (v) {
      'success' => Renk.basari,
      'warning' => Renk.uyari,
      'danger' => Renk.hata,
      'info' => Renk.bilgi,
      'primary' => Renk.marka,
      _ => Renk.yazi,
    };

/// Kategori simgesi (web AppIcon adları; bilinmeyende simge yok).
IconData? _kategoriSimgesi(String? ad) => switch (ad) {
      'coffee' => Icons.coffee_outlined,
      'utensils' => Icons.restaurant_rounded,
      'pizza' => Icons.local_pizza_outlined,
      'cake' => Icons.cake_outlined,
      'wine' || 'glass' => Icons.wine_bar_outlined,
      'beer' => Icons.sports_bar_outlined,
      'ice-cream' => Icons.icecream_outlined,
      'soup' => Icons.soup_kitchen_outlined,
      'burger' => Icons.lunch_dining_outlined,
      'salad' => Icons.eco_outlined,
      'tea' || 'cup' => Icons.emoji_food_beverage_outlined,
      'nargile' => Icons.local_fire_department_outlined,
      'star' => Icons.star_outline_rounded,
      'tag' => Icons.sell_outlined,
      _ => null,
    };

class _AdisyonEkraniState extends State<AdisyonEkrani> with WidgetsBindingObserver {
  Adisyon? _a;
  bool _yukleniyor = true;
  Katalog? _katalog;

  int _ana = 0;
  int _alt = 0;
  String _arama = '';
  final _aramaDenetim = TextEditingController();
  bool _gecmis = false;

  bool _mesgul = false;
  int _modal = 0;
  bool _bosaldiSoruldu = false;
  bool _atildi = false;
  bool _ayrildi = false;

  /// §5.6 seçim modeli.
  final Set<int> _secili = {};
  /// Kısmi seçim: satır → seçili adet sıraları (yoksa ve _secili'deyse tamamı).
  final Map<int, Set<int>> _birim = {};
  int? _acikDokum;

  /// §2.6 hızlı ekleme kuyruğu + kart rozetleri.
  final List<Urun> _kuyruk = [];
  final Map<int, int> _rozet = {};
  bool _kuyrukCalisiyor = false;

  Timer? _yoklama;
  bool _yoklaniyor = false;
  String? _etag;
  String? _imza;
  late final Api _api;

  int get id => widget.adisyonId;
  Oturum get _o => context.durum.oturum!;
  bool _can(String k) => _o.yetki(k) || _o.yetkiler.contains('*');

  /// web canOrPin: terminal oturumunda düğme hep görünür; yetkiyi sunucu
  /// işlemi yapan personelde denetler (uygulama her zaman terminaldir).
  bool _canOrPin(String _) => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = context.api;
    _katalog = KatalogDeposu.ornek.katalog;
    _yukle();
    _kataloguYukle();
    // CANLI (1.2.19): aynı adisyondaki başka personelin eklediği kalemler 3 sn
    // içinde görünür; ETag'le sorulur, değişmediyse hiçbir şey çizilmez.
    _yoklama = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _modal == 0 && !_mesgul && !_kuyrukCalisiyor && !_yoklaniyor && context.yoklamaUygun) _yukle(sessiz: true, canli: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _yoklama?.cancel();
    _aramaDenetim.dispose();
    _bosIseAt();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused || s == AppLifecycleState.detached) {
      _bosIseAt();
    } else if (s == AppLifecycleState.resumed && _modal == 0) {
      _yukle(sessiz: true);
    }
  }

  /* ═════════════ Yükleme ═════════════ */

  Future<void> _yukle({bool sessiz = false, bool canli = false}) async {
    _yoklaniyor = true;
    try {
      if (canli && _a != null) {
        final y = await context.api.getEtagli('/api/v1/orders/$id', _etag);
        if (y == null || !mounted) return; // 304: değişmedi
        _etag = y.etag;
        final ham = y.veri is Map ? (y.veri as Map)['order'] : null;
        // ETag'siz sunucu: gövde aynıysa yeniden çizilmez.
        final imza = ham is Map ? jsonEncode(ham) : null;
        if (imza != null && imza == _imza) return;
        // Yoklama yanıtı gelirken kendi işlemimiz başladıysa eski veri yazılmaz.
        if (_mesgul || _kuyrukCalisiyor || _modal > 0) return;
        _isle(y.veri);
        return;
      }
      final r = await context.api.get('/api/v1/orders/$id');
      _etag = null;
      _isle(r);
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (e.kod == 404) return _bulunamadi();
      if (!sessiz) context.bildir2('Adisyon yüklenemedi', e.mesaj, hata: true);
    } finally {
      _yoklaniyor = false;
      if (mounted && _yukleniyor) setState(() => _yukleniyor = false);
    }
  }

  void _isle(dynamic r) {
    final ham = r is Map ? r['order'] : null;
    if (ham is! Map || !mounted) return;
    _imza = jsonEncode(ham);
    final a = Adisyon(ham.cast<String, dynamic>());
    setState(() {
      _a = a;
      _yukleniyor = false;
      // Artık olmayan (ya da taşınamaz) kalemler seçimden düşer.
      final gecerli = {for (final k in a.kalemler) if (_tasinabilir(k)) k.id};
      _secili.removeWhere((x) => !gecerli.contains(x));
      _birim.removeWhere((x, _) => !gecerli.contains(x));
    });
    // Arka plandayken boş adisyon atıldıysa ekranda kalmanın anlamı yok.
    if (_atildi && !a.acik && a.kalemler.isEmpty) _panoyaDon();
  }

  Future<void> _kataloguYukle() async {
    try {
      final k = await KatalogDeposu.ornek.yukle(context.durum);
      if (mounted && k != null) setState(() => _katalog = k);
    } catch (_) {
      // Katalog gelmezse ızgara boş kalır, adisyon çalışır (§5.2).
    }
  }

  void _bulunamadi() {
    context.bildir2('Adisyon bulunamadı', 'Bu adisyon kapatılmış ya da geçmiş sıfırlanmış olabilir. Sipariş ekranına dönülüyor.', hata: true);
    Future.delayed(const Duration(milliseconds: 1200), _panoyaDon);
  }

  void _panoyaDon() {
    if (!mounted || _ayrildi) return;
    _ayrildi = true;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  /// §5.8: hiç kalem girilmemiş açık adisyon sessizce kapatılır.
  void _bosIseAt() {
    final a = _a;
    if (_atildi || a == null || !a.acik || a.kalemler.isNotEmpty) return;
    if (a.odenen != 0 || tamSayi(a.ham['discount_minor']) != 0 || tamSayi(a.ham['iskonto_minor']) != 0) return;
    _atildi = true;
    _api.post('/api/v1/orders/$id/discard-if-empty').catchError((_) => null);
  }

  Future<T?> _penceredeyken<T>(Future<T?> Function() f) async {
    _modal++;
    try {
      return await f();
    } finally {
      _modal--;
    }
  }

  /// web runOp: tek seferde bir işlem; yanıttaki adisyon ekrana basılır.
  Future<bool> _islem(Future<dynamic> Function() f,
      {String? ok, String okMetin = '', bool yeniledi = true, String hataBaslik = 'İşlem tamamlanamadı'}) async {
    if (_mesgul) return false;
    setState(() => _mesgul = true);
    try {
      final r = await f();
      if (yeniledi) _isle(r);
      if (ok != null && mounted) context.bildir2(ok, okMetin);
      _bosaldiysaSor();
      return true;
    } on ApiHata catch (e) {
      if (!mounted) return false;
      if (e.kod == 404) {
        _bulunamadi();
      } else if (e.kod == 409) {
        context.bildir2('Eşzamanlı değişiklik', e.mesaj, hata: true);
        _yukle(sessiz: true);
      } else {
        context.bildir2(hataBaslik, e.mesaj, hata: true);
        context.durum.islemHatasi(e);
      }
      return false;
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  int get _surum => tamSayi(_a?.ham['version']);
  String get _yol => '/api/v1/orders/$id';

  /* ═════════════ §5.9 Adisyon boşaldı ═════════════ */

  Future<void> _bosaldiysaSor() async {
    final a = _a;
    if (a == null || !a.acik || a.kalemler.isEmpty || a.aktifKalemler.isNotEmpty || a.odenen > 0) return;
    if (_bosaldiSoruldu) return;
    _bosaldiSoruldu = true;
    final evet = await adisyonBosaldiSor(context);
    if (evet && mounted) await _adisyonuIptal();
  }

  /* ═════════════ Ürün ekleme (§2.6 / §4.1) ═════════════ */

  void _urunDokun(Urun u) {
    if (!u.mevcut) return;
    if (u.secimGerekir) {
      _urunPenceresi(u);
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _rozet[u.id] = (_rozet[u.id] ?? 0) + 1);
    _kuyruk.add(u);
    _kuyruguIsle();
  }

  Future<void> _kuyruguIsle() async {
    if (_kuyrukCalisiyor) return;
    _kuyrukCalisiyor = true;
    final api = context.api;
    try {
      while (_kuyruk.isNotEmpty && mounted) {
        final u = _kuyruk.first;
        final varyant = u.varyantlar.isEmpty ? null : u.varyantlar.firstWhere((v) => v.varsayilan, orElse: () => u.varyantlar.first).id;
        final anahtar = api.yeniIslemKimligi();
        try {
          final r = await api.post(
            '$_yol/items',
            {'product_id': u.id, 'variant_id': varyant, 'qty': u.minAdet, 'option_ids': <int>[], 'note': null},
            {'Idempotency-Key': anahtar},
          );
          _kuyruk.removeAt(0);
          _isle(r);
          if (mounted) setState(() => _rozet[u.id] = ((_rozet[u.id] ?? 1) - 1).clamp(0, 999));
          _otoGonderimBildir(u);
        } on ApiHata catch (e) {
          _kuyruk.clear();
          if (mounted) {
            setState(_rozet.clear);
            context.bildir2('Eklenemedi', e.mesaj, hata: true);
            if (e.kod == 404) _bulunamadi();
          }
          return;
        }
      }
    } finally {
      _kuyrukCalisiyor = false;
    }
  }

  /// §5.5: eklenti açıksa sunucu kalemi anında istasyona gönderir.
  void _otoGonderimBildir(Urun u) {
    final a = _a;
    if (a == null || !mounted || a.gonderilmemis > 0) return;
    final k = a.aktifKalemler.where((k) => k.urunId == u.id).firstOrNull;
    if (k == null || k.durum == 'placed' || k.hazirliksiz) return;
    context.bildir2('${u.ad} hazırlığa gönderildi', k.istasyon ?? 'Otomatik gönderim açık');
  }

  Future<void> _urunPenceresi(Urun u) async {
    final api = context.api;
    final anahtar = api.yeniIslemKimligi(); // pencere başına tek anahtar
    final s = await _penceredeyken(() => urunSecimiAc(context, u, kanal: _a?.kanal ?? 'table'));
    if (s == null || !mounted) return;
    final ok = await _islem(
      () => api.post(
        '$_yol/items',
        {'product_id': u.id, 'variant_id': s.varyantId, 'qty': s.adet, 'option_ids': s.secenekler, 'note': s.not},
        {'Idempotency-Key': anahtar},
      ),
      ok: '${u.ad} eklendi',
    );
    if (ok) _otoGonderimBildir(u);
  }

  /* ═════════════ Kalem işlemleri ═════════════ */

  bool _tasinabilir(Kalem k) => k.aktif && !k.odendi;
  int _bekleyen(Kalem k) => k.ham.containsKey('pending_qty') ? k.bekleyenAdet : (k.durum == 'placed' ? k.adet : 0);

  Future<void> _adet(Kalem k, int fark) async {
    final yeni = k.adet + fark;
    if (yeni < 1) return;
    await _islem(() => context.api.put('$_yol/items/${k.id}', {'qty': yeni, 'expected_version': _surum}));
  }

  Future<void> _cikar(Kalem k) async {
    final ok = await _islem(() => context.api.delete('$_yol/items/${k.id}', {'expected_version': _surum}), ok: 'Kalem çıkarıldı');
    if (ok) _secimiTemizle(k.id);
  }

  /// Kalem notu (yalnız hazırlığa gönderilmemiş adetler). Sunucu kısmen
  /// gönderilmiş satırı böler; yanıttaki adisyon ekrana basılır.
  Future<void> _kalemNotu(Kalem k) async {
    final r = await _penceredeyken(() => kalemNotuPenceresi(context, k, _bekleyen(k)));
    if (r == null || !mounted) return;
    await _islem(
      () => context.api.patch('$_yol/items/${k.id}/note', {'note': r.not, 'expected_version': _surum}),
      ok: r.not == null ? 'Not silindi' : 'Not kaydedildi',
      okMetin: k.ad,
      hataBaslik: 'Not kaydedilemedi',
    );
  }

  Future<void> _servisEdildi(Kalem k) =>
      _islem(() => context.api.put('$_yol/items/${k.id}/status', {'status': 'served', 'expected_version': _surum}), ok: 'Servis edildi');

  /// Kısmi adet: yalnız seçilen adet satır adedinden azsa gönderilir.
  Map<String, dynamic> _kismi(Kalem k) {
    final n = _topluAdedi(k).clamp(1, k.adet);
    return n < k.adet ? {'qty': n} : const {};
  }

  String _nedenUstu(Kalem k) {
    final n = _secili.contains(k.id) ? _topluAdedi(k).clamp(1, k.adet) : k.adet;
    return '$n × ${k.ad}${n < k.adet ? ' · ${k.adet - n} adet adisyonda kalır' : ''}';
  }

  Future<void> _kalemIptal(Kalem k) async {
    final neden = await _penceredeyken(() => nedenSor(context, tur: 'item_cancel', ust: _nedenUstu(k)));
    if (neden == null || !mounted) return;
    final ok = await _islem(
      () => context.api.post('$_yol/items/${k.id}/cancel', {'reason': neden, 'expected_version': _surum, ..._kismi(k)}),
      ok: 'Kalem iptal edildi',
    );
    if (ok) _secimiTemizle(k.id);
  }

  Future<void> _ikram(Kalem k) async {
    if (k.ikram) {
      final ok = await _islem(() => context.api.delete('$_yol/items/${k.id}/comp', {'expected_version': _surum}), ok: 'İkram kaldırıldı');
      if (ok) _secimiTemizle(k.id);
      return;
    }
    final neden = await _penceredeyken(() => nedenSor(context, tur: 'item_comp', ust: _nedenUstu(k)));
    if (neden == null || !mounted) return;
    final ok = await _islem(
      () => context.api.post('$_yol/items/${k.id}/comp', {'reason': neden, 'expected_version': _surum, ..._kismi(k)}),
      ok: 'İkram edildi',
    );
    if (ok) _secimiTemizle(k.id);
  }

  /* ═════════════ Seçim (§5.6) ═════════════ */

  int _topluAdedi(Kalem k) {
    final b = _birim[k.id];
    if (b == null) return _secili.contains(k.id) ? k.adet : 0;
    return b.length.clamp(0, k.adet);
  }

  /// Seçili adet sıraları (adet kartlarındaki kutular).
  Set<int> _seciliBirimler(Kalem k) =>
      _birim[k.id] ?? (_secili.contains(k.id) ? {for (var i = 0; i < k.adet; i++) i} : const <int>{});

  void _anaKutu(Kalem k) => setState(() {
        final tam = _secili.contains(k.id) && _topluAdedi(k) >= k.adet;
        _birim.remove(k.id);
        if (tam) {
          _secili.remove(k.id);
        } else {
          _secili.add(k.id);
        }
      });

  /// Tek adedi seç / bırak: taşıma / ikram / iptalde adet = seçili kart sayısı.
  void _birimDegistir(Kalem k, int i) => setState(() {
        final s = {..._seciliBirimler(k)};
        if (!s.remove(i)) s.add(i);
        s.removeWhere((x) => x < 0 || x >= k.adet);
        if (s.isEmpty) {
          _birim.remove(k.id);
          _secili.remove(k.id);
        } else if (s.length >= k.adet) {
          _birim.remove(k.id);
          _secili.add(k.id);
        } else {
          _birim[k.id] = s;
          _secili.add(k.id);
        }
      });

  void _secimiTemizle([int? kalemId]) => setState(() {
        if (kalemId == null) {
          _secili.clear();
          _birim.clear();
        } else {
          _secili.remove(kalemId);
          _birim.remove(kalemId);
        }
      });

  List<Kalem> get _seciliKalemler => _a?.aktifKalemler.where((k) => _secili.contains(k.id)).toList() ?? const [];

  /* ═════════════ Taşıma / birleştirme (§4.4 / §4.7) ═════════════ */

  void _hedefeGit(dynamic r) {
    final t = r is Map ? r['target_order'] : null;
    final hedef = t is Map ? tamSayi(t['id']) : 0;
    if (hedef > 0 && hedef != id && mounted) {
      _ayrildi = true;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => AdisyonEkrani(adisyonId: hedef, kasaKipi: widget.kasaKipi)));
    }
  }

  Future<void> _topluTasi() async {
    final a = _a;
    final secim = _seciliKalemler;
    if (a == null || secim.isEmpty) return;
    final toplu = [for (final k in secim) (k: k, adet: _topluAdedi(k).clamp(1, k.adet))];
    final s = await _penceredeyken(() => tasimaPenceresi(context, adisyon: a, toplu: toplu, partiOnayi: a.ham['aktif_parti'] != null));
    if (s == null || !mounted) return;
    final api = context.api;
    final kismiVar = toplu.any((x) => x.adet < x.k.adet);

    if (!kismiVar) {
      dynamic son;
      final ok = await _islem(() async {
        son = await api.post('$_yol/items/toplu-tasi', {
          'item_ids': [for (final x in toplu) x.k.id],
          'table_id': s.masaId,
          'receivable_id': s.cariId,
          'expected_version': _surum,
        });
        return son;
      });
      if (ok) {
        if (mounted) context.bildir2('${son is Map ? tamSayi(son['moved'], toplu.length) : toplu.length} kalem taşındı', 'Hedef adisyona geçiliyor…');
        _secimiTemizle();
        _hedefeGit(son);
      }
      return;
    }

    // Kısmi seçim: satır satır tek-kalem ucu, her yanıt sürümü günceller.
    if (_mesgul) return;
    setState(() => _mesgul = true);
    dynamic son;
    var adet = 0;
    try {
      for (final x in toplu) {
        final govde = {
          if (s.cariId != null) 'receivable_id': s.cariId else 'table_id': s.masaId,
          'expected_version': _surum,
          'qty': x.adet,
        };
        son = await api.post('$_yol/items/${x.k.id}/${s.cariId != null ? 'cariye-tasi' : 'move'}', govde);
        _isle(son);
        adet += x.adet;
      }
      if (mounted) context.bildir2('$adet adet taşındı', 'Hedef adisyona geçiliyor…');
      _secimiTemizle();
      _hedefeGit(son);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Taşınamadı', e.mesaj, hata: true);
      _yukle();
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _adisyonuTasi() async {
    if (_secili.isNotEmpty) return _topluTasi();
    final a = _a;
    if (a == null) return;
    final s = await _penceredeyken(() => tasimaPenceresi(context, adisyon: a, partiOnayi: a.ham['aktif_parti'] != null));
    if (s == null || !mounted) return;
    await _adisyonTasimaIstegi(s, birlestir: false);
  }

  Future<void> _adisyonTasimaIstegi(TasimaSonucu s, {required bool birlestir}) async {
    final api = context.api;
    final yol = s.cariId != null ? '$_yol/cariye-tasi' : '$_yol/move';
    final govde = {
      if (s.cariId != null) 'receivable_id': s.cariId else 'table_id': s.masaId,
      'expected_version': _surum,
      if (birlestir) 'birlestir': true,
    };
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      final r = await api.post(yol, govde);
      _isle(r);
      final hedef = r is Map ? tamSayi(r['hedef_adisyon_id']) : 0;
      if (r is Map && r['birlestirildi'] == true && hedef > 0 && hedef != id) {
        if (mounted) context.bildir2('Adisyonlar birleştirildi', 'Hedef adisyona geçiliyor…');
        _hedefeGit({'target_order': {'id': hedef}});
      } else if (mounted) {
        context.bildir2(s.cariId != null ? 'Adisyon şahsa taşındı' : 'Adisyon taşındı', '');
      }
    } on ApiHata catch (e) {
      if (!mounted) return;
      final hatalar = e.govde?['errors'];
      if (!birlestir && hatalar is Map && hatalar.containsKey('hedef_adisyon_id')) {
        setState(() => _mesgul = false);
        final evet = await _penceredeyken(() => _birlestirmeTeklifi(e.mesaj));
        if (evet == true && mounted) await _adisyonTasimaIstegi(s, birlestir: true);
        return;
      }
      if (e.kod == 409) {
        context.bildir2('Eşzamanlı değişiklik', e.mesaj, hata: true);
        _yukle(sessiz: true);
      } else {
        context.bildir2('Taşınamadı', e.mesaj, hata: true);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<bool?> _birlestirmeTeklifi(String mesaj) => pencereAc<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Adisyonu taşı'),
          content: SizedBox(
            width: 384,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Renk.uyari),
                  const SizedBox(width: 8),
                  Expanded(child: Text(mesaj, style: TextStyle(fontWeight: FontWeight.w600, color: Renk.uyari))),
                ]),
                const SizedBox(height: 6),
                Text(
                  'Birleştirirseniz bu adisyondaki kalemler hedefteki açık adisyona eklenir, bu adisyon kapanır ve masası boşalır. Ödeme tek hesaptan alınır.',
                  style: TextStyle(fontSize: 12, color: Renk.ikinci),
                ),
              ]),
            ),
          ),
          actions: [
            OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.merge_rounded, size: 15),
              label: const Text('Birleştir ve taşı'),
            ),
          ],
        ),
      );

  Future<void> _birlestir() async {
    final a = _a;
    if (a == null) return;
    final kaynak = await _penceredeyken(() => birlestirPenceresi(context, a));
    if (kaynak == null || !mounted) return;
    await _islem(() => context.api.post('$_yol/merge', {'source_order_id': kaynak, 'expected_version': _surum}), ok: 'Adisyonlar birleştirildi');
  }

  /* ═════════════ Adisyon işlemleri ═════════════ */

  Future<void> _onayla() => _islem(() => context.api.post('$_yol/approve'), ok: 'Sipariş onaylandı');

  Future<bool> _gonder() => _islem(() => context.api.post('$_yol/send-to-kitchen'), ok: 'Kalemler hazırlığa gönderildi');

  /// "Tamamlandı — hazırlığa gönder": başarıda panoya döner.
  Future<void> _tamamlandi() async {
    if (await _gonder()) _panoyaDon();
  }

  Future<void> _hesapGeriAl() =>
      _islem(() => context.api.post('$_yol/send-to-service', {'expected_version': _surum}), ok: 'Hesap isteği geri alındı');

  Future<void> _adisyonuIptal() async {
    final neden = await _penceredeyken(() => nedenSor(context, tur: 'order_cancel'));
    if (neden == null || !mounted) return;
    await _islem(() => context.api.post('$_yol/cancel', {'reason': neden, 'expected_version': _surum}), ok: 'Adisyon iptal edildi');
  }

  Future<void> _iade() async {
    final neden = await _penceredeyken(() => nedenSor(context, tur: 'order_refund'));
    if (neden == null || !mounted) return;
    await _islem(() => context.api.post('$_yol/refund', {'reason': neden, 'expected_version': _surum}), ok: 'İade kaydedildi');
  }

  Future<void> _bilgi() async {
    final a = _a;
    if (a == null) return;
    final r = await _penceredeyken(() => bilgiPenceresi(context, a));
    if (r == null || !mounted) return;
    await _islem(() => context.api.put('$_yol/info', {'guest_count': r.kisi, 'note': r.not, 'expected_version': _surum}),
        ok: 'Adisyon bilgisi güncellendi');
  }

  Future<void> _indirim() async {
    final a = _a;
    if (a == null) return;
    final degisti = await _penceredeyken(() => indirimPenceresi(context, a));
    if (degisti == true && mounted) _yukle(sessiz: true);
  }

  Future<void> _yazdir() async {
    try {
      final r = await context.api.post('$_yol/print', {'kind': 'receipt'});
      if (mounted) context.bildir2('Hesap fişi gönderildi', r is Map ? '${r['printer'] ?? 'Kasa yazıcısı'}' : 'Kasa yazıcısı');
    } on ApiHata catch (e) {
      // Web tarayıcı yazdırmasına düşer; uygulamada yazıcı tanımlı değilse bildirilir.
      if (mounted) context.bildir2('Hesap fişi yazdırılamadı', e.mesaj, hata: true);
    }
  }

  Future<void> _partiKapat() async {
    final a = _a;
    if (a == null) return;
    final evet = await partiKapatSor(context, a);
    if (evet && mounted) await _islem(() => context.api.post('$_yol/parti-kapat', {'expected_version': _surum}), ok: 'Yeni parti başladı');
  }

  Future<void> _partiAdi(int no, String? mevcut) async {
    final ad = await partiAdiSor(context, no, mevcut);
    if (ad == null || !mounted) return;
    await _islem(
      () => context.api.post('$_yol/parti-adi', {'parti_no': no, 'ad': ad.isEmpty ? null : ad, 'expected_version': _surum}),
      ok: ad.isEmpty ? 'Parti adı kaldırıldı' : 'Parti adı kaydedildi',
    );
  }

  void _kasayaGit() {
    ekranIstegi.value = PosEkrani.kasa;
    _panoyaDon();
  }

  /* ═════════════ Görünüm ═════════════ */

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final a = _a;
    final g = MediaQuery.sizeOf(context).width;
    final genis = g >= 1024;
    final sube = (o.seritKimlik['sube'] as String?) ?? o.sube;

    Widget govde;
    if (a == null) {
      govde = _yukleniyor
          ? const SizedBox()
          : Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline_rounded, size: 40, color: Renk.soluk),
                SizedBox(height: 10),
                Text('Adisyon bulunamadı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Silinmiş ya da erişiminiz olmayan bir adisyon.', style: TextStyle(color: Renk.ikinci)),
              ]),
            );
    } else if (genis) {
      final sag = g >= 1536 ? 420.0 : 392.0;
      govde = a.acik
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _urunBolumu(a, g, sinirli: false)),
              Container(width: 1, color: Renk.cizgi),
              SizedBox(width: sag, child: _panel(a, genis: true)),
            ])
          : _panel(a, genis: true);
    } else {
      final h = MediaQuery.sizeOf(context).height;
      govde = ListView(padding: const EdgeInsets.all(12), children: [
        if (a.acik) ...[
          _kart(SizedBox(height: h * .46 + 92, child: _urunBolumu(a, g, sinirli: true))),
          const SizedBox(height: 12),
        ],
        _kart(_panel(a, genis: false, icerikYuksekligi: h * .45)),
      ]);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bitti, _) {
        if (bitti) return;
        _bosIseAt();
        _ayrildi = true;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Renk.yuzey,
        appBar: UstCubuk(
          baslik: o.isletme,
          altSatir: [sube ?? '', o.isletmeKod].where((s) => s.isNotEmpty).join(' · '),
          rozet: 'Sipariş Ekranı',
          zil: true,
          sol: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Geri',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back_rounded, size: 22, color: Renk.yazi),
            ),
          ),
          orta: a != null && a.acik ? _aramaKutusu() : null,
          sag: a == null ? const [] : _ustEylemler(a),
        ),
        bottomNavigationBar: posAltSerit(context, secili: null, git: (e) {
          ekranIstegi.value = e;
          _panoyaDon();
        }),
        body: govde,
      ),
    );
  }

  Widget _kart(Widget c) => Container(
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: c,
      );

  /* ── §2.1 üst çubuk eylemleri ── */

  List<Widget> _ustEylemler(Adisyon a) {
    final telefon = MediaQuery.sizeOf(context).width < 640;
    Widget dugme(String etiket, IconData ikon, VoidCallback? bas, {bool ikincil = false}) {
      final stil = ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      );
      final ic = telefon ? Icon(ikon, size: 16) : Row(mainAxisSize: MainAxisSize.min, children: [Icon(ikon, size: 14), const SizedBox(width: 6), Text(etiket)]);
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: etiket,
          child: ikincil
              ? OutlinedButton(style: stil, onPressed: _mesgul ? null : bas, child: ic)
              : FilledButton(style: stil, onPressed: _mesgul ? null : bas, child: ic),
        ),
      );
    }

    return [
      if (a.onayBekliyor && _can('orders.update')) dugme('Siparişi onayla', Icons.check_rounded, _onayla),
      if (!a.onayBekliyor && a.acik && a.gonderilmemis > 0 && _can('orders.update'))
        dugme('Hazırlığa gönder (${a.gonderilmemis})', Icons.restaurant_rounded, _gonder),
      if (a.hesapIstendi)
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.schedule_rounded, size: 13, color: Renk.uyari),
              SizedBox(width: 5),
              Text('Kasada bekliyor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.uyari)),
            ]),
          ),
        ),
      if (a.hesapIstendi && _canOrPin('orders.update')) dugme('Geri al', Icons.undo_rounded, _hesapGeriAl, ikincil: true),
    ];
  }

  Widget _aramaKutusu() => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 38,
            child: KlavyeliAlan(
              controller: _aramaDenetim,
              onChanged: (v) => setState(() => _arama = v.trim()),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ürün ara…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                prefixIcon: Icon(Icons.search_rounded, size: 19, color: Renk.soluk),
                suffixIcon: _arama.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _aramaDenetim.clear();
                          setState(() => _arama = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18)),
              ),
            ),
          ),
        ),
      );

  /* ── §1.3 ürün bölümü ── */

  Widget _urunBolumu(Adisyon a, double g, {required bool sinirli}) {
    final k = _katalog;
    final kategoriler = k?.kategoriler ?? const <Kategori>[];
    final duz = kategoriler.every((c) => c.ustId == null);
    final anaKategoriler = duz ? kategoriler : kategoriler.where((c) => c.ustId == null).toList();
    final altKategoriler = duz || _ana == 0 ? const <Kategori>[] : kategoriler.where((c) => c.ustId == _ana).toList();
    final gorselli = _o.eklenti('adisyon_gorselli');

    var urunler = k?.urunler ?? const <Urun>[];
    if (_alt != 0) {
      urunler = urunler.where((u) => u.kategoriId == _alt).toList();
    } else if (_ana != 0) {
      final cocuk = {_ana, for (final c in kategoriler) if (c.ustId == _ana) c.id};
      urunler = urunler.where((u) => cocuk.contains(u.kategoriId)).toList();
    }
    if (_arama.isNotEmpty) {
      final n = aramaAnahtari(_arama);
      urunler = urunler.where((u) => u.arama.contains(n)).toList();
    }
    if (_ana == 0 && _alt == 0 && _arama.isEmpty) {
      urunler = [...urunler]..sort((x, y) => y.kullanim.compareTo(x.kullanim));
    }
    final renkler = {for (final c in kategoriler) c.id: c.renk};

    Widget sekme(String ad, bool secili, VoidCallback bas, {IconData? ikon, bool alt = false}) => InkWell(
          onTap: bas,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: alt ? 4 : 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: secili ? Renk.marka : Colors.transparent, width: 2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (ikon != null) ...[Icon(ikon, size: 17, color: secili ? Renk.marka : (alt ? Renk.ikinci : Renk.yazi)), const SizedBox(width: 6)],
              Text(ad,
                  style: TextStyle(
                    fontSize: alt ? 15 : 17,
                    fontWeight: alt ? FontWeight.w600 : FontWeight.w800,
                    color: secili ? Renk.marka : (alt ? Renk.ikinci : Renk.yazi),
                  )),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_arama.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            Icon(Icons.restaurant_rounded, size: 12, color: Renk.ikinci),
            const SizedBox(width: 4),
            Text('${urunler.length} ürün bulundu', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Wrap(spacing: 24, runSpacing: 6, children: [
          sekme('Tümü', _ana == 0, () => setState(() {
                _ana = 0;
                _alt = 0;
              }), ikon: Icons.format_list_bulleted_rounded),
          for (final c in anaKategoriler)
            sekme(c.ad, _ana == c.id, () => setState(() {
                  _ana = c.id;
                  _alt = 0;
                }), ikon: _kategoriSimgesi(c.ham['icon']?.toString())),
        ]),
      ),
      if (altKategoriler.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Renk.ic, border: Border(top: BorderSide(color: Renk.cizgi))),
          child: Wrap(spacing: 20, runSpacing: 4, children: [
            sekme('Tümü', _alt == 0, () => setState(() => _alt = 0), alt: true),
            for (final c in altKategoriler) sekme(c.ad, _alt == c.id, () => setState(() => _alt = c.id), alt: true),
          ]),
        ),
      const SizedBox(height: 8),
      Expanded(
        child: LayoutBuilder(builder: (context, kutu) {
          final sutun = gorselli
              ? (g >= 1536 ? 5 : (g >= 640 ? 4 : 3))
              : (g >= 1536 ? 8 : (g >= 1280 ? 6 : (g >= 768 ? 5 : (g >= 640 ? 4 : 3))));
          const bosluk = 8.0;
          final hucre = (kutu.maxWidth - 24 - bosluk * (sutun - 1)) / sutun;
          if (k == null) {
            return GridView.count(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              crossAxisCount: sutun,
              mainAxisSpacing: bosluk,
              crossAxisSpacing: bosluk,
              childAspectRatio: gorselli ? .78 : 1,
              children: [for (var i = 0; i < 12; i++) Container(decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(12)))],
            );
          }
          if (urunler.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.search_rounded, size: 32, color: Renk.soluk),
                SizedBox(height: 8),
                Text('Ürün bulunamadı', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Arama ya da kategori filtresini değiştirin.', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              ]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: sutun,
              mainAxisSpacing: bosluk,
              crossAxisSpacing: bosluk,
              mainAxisExtent: !gorselli ? hucre : (hucre < 190 ? hucre + 92 : _UrunKarti.bantYuksekligi(hucre) + 46),
            ),
            itemCount: urunler.length,
            itemBuilder: (_, i) {
              final u = urunler[i];
              return _UrunKarti(
                urun: u,
                kanal: a.kanal,
                gorselli: gorselli,
                bekleyen: _rozet[u.id] ?? 0,
                kategoriRengi: renkler[u.kategoriId],
                bas: () => _urunDokun(u),
              );
            },
          );
        }),
      ),
    ]);
  }

  /* ── §1.4 adisyon paneli ── */

  Widget _panel(Adisyon a, {required bool genis, double? icerikYuksekligi}) {
    final icerik = _gecmis ? _gecmisListesi(a) : _sepet(a);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: genis ? MainAxisSize.max : MainAxisSize.min, children: [
      _kunye(a),
      _aracCubugu(a, genis),
      if (genis) Expanded(child: icerik) else ConstrainedBox(constraints: BoxConstraints(maxHeight: icerikYuksekligi ?? 400), child: icerik),
      _toplamSeridi(a),
      _anaEylem(a),
    ]);
  }

  Widget _kunye(Adisyon a) {
    final fark = _o.saatFarki;
    final ad = a.masaAdi ?? a.cariAdi ?? a.musteri ?? '#${a.id}';
    final varyant = a.ham['status_variant']?.toString();
    final acilis = a.ham['created_at']?.toString();
    final baslangic = a.ham['placed_at']?.toString() ?? acilis;
    String? son;
    for (final e in a.olaylar) {
      if (e['type'] == 'item_added') {
        final t = e['created_at']?.toString();
        if (t != null && (son == null || t.compareTo(son) > 0)) son = t;
      }
    }
    son ??= baslangic;
    final bayat = a.acik && son != null && gecenDakika(son, saatFarki: fark) > 30;
    final dk = gecenDakika(baslangic, saatFarki: fark);
    final sure = dk < 60 ? '$dk dk' : '${dk ~/ 60} sa ${(dk % 60).toString().padLeft(2, '0')} dk';
    final urunAdedi = a.aktifKalemler.fold<int>(0, (t, k) => t + k.adet);
    final meta = <Widget>[
      if (a.kaynakEtiket.isNotEmpty) Text(a.kaynakEtiket),
      if (a.servisTuruEtiket.isNotEmpty) Text(a.servisTuruEtiket),
      if (a.kisi != null)
        Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.people_outline_rounded, size: 13, color: Renk.ikinci), const SizedBox(width: 3), Text('${a.kisi} kişi')]),
      if (a.kalemSayisi > 0 && a.servisEdilen < a.kalemSayisi)
        Tooltip(
          message: 'Servis edilen / toplam kalem',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.restaurant_rounded, size: 13, color: Renk.uyari),
            const SizedBox(width: 3),
            Text('${a.servisEdilen}/${a.kalemSayisi} servis', style: TextStyle(color: Renk.uyari, fontWeight: FontWeight.w600)),
          ]),
        ),
      if (a.acan != null) Tooltip(message: 'Adisyonu açan: ${a.acan}', child: Text(a.acan!)),
    ];

    Widget hucre(String baslik, String deger, {Color? renk, String? ipucu}) => Expanded(
          child: Tooltip(
            message: ipucu ?? '',
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: Renk.cizgi))),
              child: Column(children: [
                Text(baslik.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
                Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: (renk ?? Renk.yazi))),
              ]),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: ad, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                TextSpan(text: '  #${a.id.toString().padLeft(3, '0')}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.soluk)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: _durumRengi(varyant), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(a.durumEtiket, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _durumRengi(varyant))),
            ]),
          ),
        ]),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, color: Renk.ikinci),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (var i = 0; i < meta.length; i++) ...[
                  if (i > 0) const Padding(padding: EdgeInsets.symmetric(horizontal: 5), child: Text('·')),
                  meta[i],
                ],
              ]),
            ),
          ),
        if (a.ham['receivable_id'] != null)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(children: [
              Icon(Icons.people_outline_rounded, size: 13, color: Renk.marka),
              SizedBox(width: 4),
              Expanded(
                child: Text('Şahıs adisyonu — kasada tahsil edilebilir ya da borcuna yazılabilir',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.marka)),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              hucre('Açılış', saatMetni(acilis)),
              hucre('Süre', sure, renk: Renk.bilgi),
              hucre('Son sipariş', saatMetni(son),
                  renk: bayat ? Renk.uyari : Renk.yazi, ipucu: bayat ? 'Son siparişin üzerinden 30 dakikadan fazla geçti' : 'Son sipariş saati'),
              Container(
                width: 70,
                color: Renk.markaAcik,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('ÜRÜN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.marka.withValues(alpha: .8), letterSpacing: .4)),
                  Text('$urunAdedi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Renk.marka)),
                ]),
              ),
            ]),
          ),
        ),
        if (a.not != null && a.not!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: BorderRadius.circular(6)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 14, color: Renk.uyari),
              const SizedBox(width: 6),
              Expanded(child: Text(a.not!, style: TextStyle(fontSize: 12, color: Renk.uyari))),
            ]),
          ),
      ]),
    );
  }

  /* ── araç çubuğu (Sepet / Geçmiş + simgeler) ── */

  Widget _aracCubugu(Adisyon a, bool genis) {
    final aktif = a.aktifKalemler;
    Widget sekme(IconData ikon, String ad, int sayi, bool secili, VoidCallback bas) => Tooltip(
          message: '$ad — $sayi ${ad == 'Sepet' ? 'kalem' : 'kayıt'}',
          child: InkWell(
            onTap: bas,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: secili ? Renk.marka : Colors.transparent, width: 2))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ikon, size: 19, color: secili ? Renk.marka : Renk.ikinci),
                if (genis) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(ad,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: secili ? Renk.marka : Renk.ikinci)),
                  ),
                ],
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(999)),
                  child: Text('$sayi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.ikinci)),
                ),
              ]),
            ),
          ),
        );

    Widget simge(IconData ikon, String ipucu, VoidCallback? bas, {Color? renk, Color? zemin, Color? kenar}) => Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Tooltip(
            message: ipucu,
            child: Material(
              color: (zemin ?? Renk.ic),
              shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: (kenar ?? Renk.cizgi))),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                onTap: bas,
                child: SizedBox(width: 34, height: 34, child: Icon(ikon, size: 18, color: (renk ?? Renk.ikinci))),
              ),
            ),
          ),
        );

    final notVar = a.not != null && a.not!.isNotEmpty;
    return Container(
      height: 52,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Flexible(child: sekme(Icons.shopping_cart_outlined, 'Sepet', aktif.length, !_gecmis, () => setState(() => _gecmis = false))),
            Flexible(child: sekme(Icons.sync_rounded, 'Geçmiş', a.olaylar.length, _gecmis, () => setState(() => _gecmis = true))),
          ]),
        ),
        Container(
          padding: const EdgeInsets.only(left: 2, right: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: Renk.cizgi))),
          child: Row(children: [
            simge(Icons.print_outlined, 'Hesap fişi yazdır', _yazdir, renk: Renk.bilgi, zemin: Renk.bilgiZemin, kenar: Renk.bilgiKenar),
            if (a.acik && _can('orders.update'))
              simge(Icons.sticky_note_2_outlined, notVar ? 'Adisyon notu: ${a.not}' : 'Kişi sayısı / adisyon notu', _bilgi,
                  renk: notVar ? Renk.uyari : Renk.ikinci, zemin: notVar ? Renk.uyariZemin : Renk.ic, kenar: notVar ? Renk.uyariKenar : Renk.cizgi),
            Builder(builder: (c) => simge(Icons.more_vert_rounded, 'Diğer işlemler', () => _digerMenu(c, a))),
            if (a.acik && a.odenen == 0 && _canOrPin('orders.cancel'))
              simge(Icons.delete_outline_rounded, 'Adisyonu iptal et', _mesgul ? null : _adisyonuIptal,
                  renk: Renk.hata, zemin: Renk.hataZemin, kenar: Renk.hataKenar),
          ]),
        ),
      ]),
    );
  }

  Future<void> _digerMenu(BuildContext c, Adisyon a) async {
    final kutu = c.findRenderObject() as RenderBox;
    final p = kutu.localToGlobal(Offset.zero);
    final indirimVar = tamSayi(a.ham['discount_minor']) > 0;
    final s = await _penceredeyken(() => showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(p.dx - 220, p.dy + kutu.size.height + 4, 16, 0),
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Renk.cizgi)),
          items: [
            if (a.acik && _can('orders.update')) _menuOgesi('tasi', Icons.arrow_forward_rounded, 'Adisyonu başka masaya taşı'),
            if (a.acik && _can('orders.merge_tables')) _menuOgesi('birlestir', Icons.merge_rounded, 'Birleştir'),
            if (a.acik && _canOrPin('orders.discount')) _menuOgesi('indirim', Icons.sell_outlined, indirimVar ? 'İndirimi kaldır' : 'İndirim uygula'),
            if (a.durum == 'paid' && _can('orders.refund')) _menuOgesi('iade', Icons.arrow_back_rounded, 'İade et', tehlikeli: true),
          ],
        ));
    switch (s) {
      case 'tasi':
        _adisyonuTasi();
      case 'birlestir':
        _birlestir();
      case 'indirim':
        _indirim();
      case 'iade':
        _iade();
    }
  }

  PopupMenuItem<String> _menuOgesi(String d, IconData ikon, String ad, {bool tehlikeli = false, bool etkin = true}) => PopupMenuItem<String>(
        value: d,
        enabled: etkin,
        height: 40,
        child: Row(children: [
          Icon(ikon, size: 17, color: !etkin ? Renk.soluk : (tehlikeli ? Renk.hata : Renk.yazi)),
          const SizedBox(width: 10),
          Text(ad, style: TextStyle(fontSize: 13.5, color: !etkin ? Renk.soluk : (tehlikeli ? Renk.hata : Renk.yazi))),
        ]),
      );

  /* ── §2.4 sepet ── */

  Widget _sepet(Adisyon a) {
    final aktif = a.aktifKalemler;
    if (aktif.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.content_paste_rounded, size: 32, color: Renk.soluk),
            SizedBox(height: 8),
            Text('Adisyon boş', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Soldan ürün seçerek adisyonu açın.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
          ]),
        ),
      );
    }

    final partili = a.ham['aktif_parti'] != null;
    final aktifParti = tamSayi(a.ham['aktif_parti'], 1);
    final adlar = a.ham['parti_adlari'] is Map ? a.ham['parti_adlari'] as Map : const {};
    final satirlar = <Widget>[];
    if (partili) {
      final gruplar = <int, List<Kalem>>{};
      for (final k in aktif) {
        (gruplar[k.ham['parti_no'] == null ? aktifParti : tamSayi(k.ham['parti_no'])] ??= []).add(k);
      }
      for (final no in gruplar.keys.toList()..sort()) {
        final ks = gruplar[no]!;
        satirlar.add(_partiBasligi(no, ks, no == aktifParti, adlar['$no']?.toString()));
        satirlar.addAll(ks.map((k) => _kalemSatiri(a, k)));
      }
    } else {
      satirlar.addAll(aktif.map((k) => _kalemSatiri(a, k)));
    }

    final iskonto = tamSayi(a.ham['iskonto_minor']);
    return ListView(padding: EdgeInsets.zero, children: [
      if (_secili.isNotEmpty) _secimSeridi(a),
      ...satirlar,
      if (iskonto > 0)
        Container(
          decoration: BoxDecoration(
            color: Renk.uyariZemin.carp(.4),
            border: Border(left: BorderSide(color: Renk.uyari, width: 4), bottom: BorderSide(color: Renk.cizgi)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak),
              child: Icon(Icons.sell_outlined, size: 15, color: Renk.uyari),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('İskonto', style: TextStyle(fontWeight: FontWeight.w700)),
                Text(a.ham['iskonto_reason']?.toString() ?? 'Kasada tutar düşümü', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
              ]),
            ),
            Text('−${para(iskonto)}', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.uyari)),
          ]),
        ),
      _tutarDokumu(a),
    ]);
  }

  Widget _secimSeridi(Adisyon a) {
    final secim = _seciliKalemler;
    final adet = secim.fold<int>(0, (t, k) => t + _topluAdedi(k));
    final tutar = secim.fold<int>(0, (t, k) => t + (k.adet == 0 ? 0 : (k.tutar / k.adet * _topluAdedi(k)).round()));
    final tek = secim.length == 1 ? secim.first : null;
    final cikarMi = tek != null && tek.durum == 'placed' && _topluAdedi(tek) >= tek.adet;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(color: Renk.markaAcik, border: Border(bottom: BorderSide(color: Renk.marka.withValues(alpha: .3)))),
      child: Row(children: [
        Expanded(
          child: Text('$adet adet seçili${secim.length > 1 ? ' · ${secim.length} üründen' : ''} · ${para(tutar)}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Renk.marka)),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: () => _secimiTemizle(),
          child: const Text('Vazgeç'),
        ),
        const SizedBox(width: 6),
        Builder(
          builder: (c) => OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              side: BorderSide(color: Renk.marka.withValues(alpha: .4)),
              backgroundColor: Renk.yuzey,
            ),
            onPressed: () async {
              final kutu = c.findRenderObject() as RenderBox;
              final p = kutu.localToGlobal(Offset.zero);
              final s = await _penceredeyken(() => showMenu<String>(
                    context: context,
                    position: RelativeRect.fromLTRB(p.dx - 200, p.dy + kutu.size.height + 4, 16, 0),
                    shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Renk.cizgi)),
                    items: [
                      if (_canOrPin('orders.comp'))
                        _menuOgesi('ikram', Icons.check_circle_outline_rounded, tek?.ikram == true ? 'İkramı kaldır' : 'İkram et', etkin: tek != null),
                      if (_can('orders.update')) _menuOgesi('tasi', Icons.arrow_forward_rounded, 'Başka masaya taşı'),
                      _menuOgesi('iptal', Icons.cancel_outlined, cikarMi ? 'Çıkar' : 'İptal et (nedenli)',
                          tehlikeli: true, etkin: tek != null && (tek.durum == 'placed' || _canOrPin('orders.cancel'))),
                    ],
                  ));
              if (!mounted) return;
              switch (s) {
                case 'ikram':
                  if (tek != null) _ikram(tek);
                case 'tasi':
                  _topluTasi();
                case 'iptal':
                  if (tek != null) cikarMi ? _cikar(tek) : _kalemIptal(tek);
              }
            },
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.more_vert_rounded, size: 15), SizedBox(width: 4), Text('Menü')]),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: _mesgul ? null : _topluTasi,
          icon: const Icon(Icons.arrow_forward_rounded, size: 14),
          label: const Text('Taşı'),
        ),
      ]),
    );
  }

  Widget _partiBasligi(int no, List<Kalem> ks, bool acik, String? ad) {
    final tutar = ks.fold<int>(0, (t, k) => t + k.tutar);
    final tamOdendi = ks.every((k) => k.odendi);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: acik ? Renk.markaAcik.carp(.6) : Renk.ic,
        border: Border(bottom: BorderSide(color: acik ? Renk.marka.withValues(alpha: .3) : Renk.cizgi)),
      ),
      child: Row(children: [
        Text('$no. parti', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: acik ? Renk.marka : Renk.yazi)),
        const SizedBox(width: 8),
        if (_can('orders.update'))
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _partiAdi(no, ad),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 144),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: ad != null ? Renk.marka.withValues(alpha: .4) : Renk.cizgiKoyu),
              ),
              child: Text(ad ?? '+ isim',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ad != null ? Renk.marka : Renk.ikinci)),
            ),
          )
        else if (ad != null)
          Text(ad, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        if (acik)
          Rozet('SÜRÜYOR', renk: Renk.marka, dolu: true)
        else if (tamOdendi)
          Rozet('ÖDENDİ', renk: Renk.basari, dolu: true),
        const Spacer(),
        if (!tamOdendi && _can('orders.update'))
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: '$no. partinin ürünlerini seç (taşımak için)',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8), textStyle: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  _birim.clear();
                  _secili
                    ..clear()
                    ..addAll(ks.where(_tasinabilir).map((k) => k.id));
                }),
                child: const Text('Bu partiyi seç'),
              ),
            ),
          ),
        Text(para(tutar), style: TextStyle(fontWeight: FontWeight.w700, color: acik ? Renk.marka : Renk.yazi)),
      ]),
    );
  }

  Widget _kalemSatiri(Adisyon a, Kalem k) {
    final secilebilir = _tasinabilir(k) && _can('orders.update');
    final topluAdet = _topluAdedi(k);
    final tam = _secili.contains(k.id) && topluAdet >= k.adet;
    final kismi = _secili.contains(k.id) && topluAdet > 0 && topluAdet < k.adet;
    final bekleyen = _bekleyen(k);
    final acik = _acikDokum == k.id;
    // Not: yalnız gönderilmemiş adet varken (web: "Gönderilmedi" yanında).
    final notDuzenlenir = a.acik && bekleyen > 0 && _can('orders.update');
    final notVar = k.not != null && k.not!.trim().isNotEmpty;
    final notEtiket = notVar && bekleyen >= k.adet ? 'Notu düzenle' : 'Not ekle';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: Renk.ic, border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (secilebilir)
            Tooltip(
              message: '${k.ad} — taşımak için seç',
              child: SizedBox(
                width: 28,
                child: Checkbox(
                  value: tam ? true : (kismi ? null : false),
                  tristate: true,
                  visualDensity: VisualDensity.compact,
                  onChanged: (_) => _anaKutu(k),
                ),
              ),
            )
          else if (k.odendi)
            Tooltip(
              message: 'Parası alındı — taşınamaz',
              child: Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.lock_outline_rounded, size: 14, color: Renk.basari)),
            ),
          if (secilebilir) const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: acik ? 'Dökümü kapat' : 'Kim, kaçta sipariş etti?',
              child: InkWell(
                onTap: () => setState(() => _acikDokum = acik ? null : k.id),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${k.adet}×', style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: ' ${k.ad}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (k.varyant != null) TextSpan(text: ' (${k.varyant})', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (k.secenekler.isNotEmpty) Text(k.secenekler.join(', '), style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                  if (k.not != null && k.not!.trim().isNotEmpty) KalemNotu(k.not!),
                  if (k.ikram) Text('İkram — ${k.ikramNedeni ?? ''}', style: TextStyle(fontSize: 12, color: Renk.basari)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Opacity(
              opacity: k.ikram ? .6 : 1,
              child: Text(para(k.tutar),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, decoration: k.ikram ? TextDecoration.lineThrough : null)),
            ),
            Text('${para(k.birimFiyat)} / adet', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
          ]),
        ]),
        // Adet kartları (web sipariş detayı / Kasa ile aynı): her adet ayrı
        // kart — kutu · saat · ürün · siparişi giren · birim fiyat.
        if (acik)
          AdetKartlari(
            key: ValueKey('adisyon-adetler-${k.id}'),
            kalem: k,
            secili: secilebilir ? _seciliBirimler(k) : const {},
            degistir: secilebilir ? (i) => _birimDegistir(k, i) : null,
            anahtar: 'adisyon-birim',
            solBosluk: secilebilir ? 34 : 0,
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            // Rozet + Not düğmesi: dar panelde düğme rozetin altına iner.
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (bekleyen > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: BorderRadius.circular(999), border: Border.all(color: Renk.uyariKenar)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.schedule_rounded, size: 11, color: Renk.uyari),
                      const SizedBox(width: 4),
                      Text(bekleyen >= k.adet ? 'Gönderilmedi' : '$bekleyen adet gönderilmedi',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Renk.uyari)),
                    ]),
                  ),
                if (notDuzenlenir)
                  Tooltip(
                    message: '$notEtiket — mutfak / bar fişine basılır',
                    child: TextButton.icon(
                      key: ValueKey('kalem-not-${k.id}'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                      ),
                      onPressed: _mesgul ? null : () => _kalemNotu(k),
                      icon: Icon(notVar && bekleyen >= k.adet ? Icons.edit_note_rounded : Icons.sticky_note_2_outlined, size: 15),
                      label: Text(notEtiket, style: const TextStyle(fontSize: 12.5)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 6),
            if (a.acik) ...[
              if (k.durum == 'placed' && !k.ikram)
                Container(
                  decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _kucukDugme(Icons.remove_rounded, k.adet > 1 && !_mesgul ? () => _adet(k, -1) : null, 'Azalt'),
                    SizedBox(width: 28, child: Text('${k.adet}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
                    _kucukDugme(Icons.add_rounded, _mesgul ? null : () => _adet(k, 1), 'Artır'),
                  ]),
                ),
              if (k.durum == 'ready' && _can('kds.deliver'))
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: _mesgul ? null : () => _servisEdildi(k),
                  icon: const Icon(Icons.restaurant_rounded, size: 14),
                  label: const Text('Servis edildi'),
                ),
              if (k.durum == 'placed' && _can('orders.update'))
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Çıkar (henüz hazırlığa gönderilmedi)',
                    child: IconButton(
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: koseYuvarlak)),
                      onPressed: _mesgul ? null : () => _cikar(k),
                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: Renk.hata),
                    ),
                  ),
                ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _kucukDugme(IconData ikon, VoidCallback? bas, String ipucu) => Tooltip(
        message: ipucu,
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: bas,
          child: SizedBox(width: 32, height: 32, child: Icon(ikon, size: 16, color: bas == null ? Renk.cizgiKoyu : Renk.yazi)),
        ),
      );

  Widget _tutarDokumu(Adisyon a) {
    final indirim = tamSayi(a.ham['discount_minor']);
    final yuzde = a.ham['discount_percent'];
    final iskonto = tamSayi(a.ham['iskonto_minor']);
    final kdvler = (a.ham['vat_by_rate'] as List? ?? const []).whereType<Map>().toList();
    String oran(Object? v) {
      final d = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
      return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1).replaceAll('.', ',');
    }

    Widget satir(String e, String t, {Color? renk, double boy = 14}) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Text(e, style: TextStyle(fontSize: boy, color: (renk ?? Renk.yazi) == Renk.yazi ? Renk.ikinci : (renk ?? Renk.yazi))),
            const Spacer(),
            Text(t, style: TextStyle(fontSize: boy, color: (renk ?? Renk.yazi), fontWeight: FontWeight.w500)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        satir('Ara toplam', para(a.araToplam)),
        if (indirim > 0) satir('İndirim${yuzde != null ? ' (%${oran(yuzde)})' : ''}', '−${para(indirim)}', renk: Renk.uyari),
        if (iskonto > 0) satir('İskonto', '−${para(iskonto)}', renk: Renk.uyari),
        if (a.ikram > 0) satir('İkramlar', para(a.ikram), renk: Renk.basari),
        satir(kdvler.length == 1 ? 'KDV %${oran(kdvler.first['rate'])} (dahil)' : 'Toplam KDV (dahil)', para(tamSayi(a.ham['vat_total_minor'])),
            renk: Renk.ikinci, boy: 12),
      ]),
    );
  }

  /* ── §6 geçmiş ── */

  Widget _gecmisListesi(Adisyon a) {
    if (a.olaylar.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.schedule_rounded, size: 30, color: Renk.soluk),
            SizedBox(height: 6),
            Text('Kayıt yok', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: a.olaylar.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = a.olaylar[i];
        final tur = '${e['type'] ?? ''}';
        final p = e['payload'] is Map ? e['payload'] as Map : const {};
        final hedef = e['to_status']?.toString();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: _olayAdlari[tur] ?? tur, style: const TextStyle(fontSize: 14)),
                if (tur == 'item_swapped' && p.isNotEmpty) TextSpan(text: ' ${p['from']} → ${p['to']}', style: const TextStyle(fontSize: 12)),
                if (hedef != null) TextSpan(text: ' → ${_durumAdlari[hedef] ?? hedef}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                if (e['user'] != null) TextSpan(text: ' · ${e['user']}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
              ])),
            ),
            Text(saatMetni(e['created_at']?.toString()), style: TextStyle(fontSize: 12, color: Renk.soluk)),
          ]),
        );
      },
    );
  }

  /* ── toplam şeridi + §2.5 ana eylem ── */

  Widget _toplamSeridi(Adisyon a) {
    Widget hucre(IconData ikon, String baslik, String deger, Color renk, Color zemin, {bool son = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: zemin.carp(.5), border: son ? null : Border(right: BorderSide(color: Renk.cizgi))),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ikon, size: 11, color: Renk.soluk),
                const SizedBox(width: 3),
                Text(baslik.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
              ]),
              const SizedBox(height: 2),
              Text(deger, style: TextStyle(fontSize: MediaQuery.sizeOf(context).width >= 640 ? 16 : 14, fontWeight: FontWeight.w700, color: renk)),
            ]),
          ),
        );
    final kalanVar = a.kalan > 0;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          hucre(Icons.check_circle_outline_rounded, 'Ödenen', para(a.odenen), Renk.basari, Renk.basariZemin),
          hucre(Icons.account_balance_wallet_outlined, 'Kalan', '${a.ham['remaining_display'] ?? para(a.kalan, simge: false)} ₺',
              kalanVar ? Renk.uyari : Renk.basari, kalanVar ? Renk.uyariZemin : Renk.basariZemin),
          hucre(Icons.receipt_outlined, 'Toplam', '${a.ham['total_display'] ?? para(a.toplam, simge: false)} ₺', Renk.marka, Renk.markaAcik, son: true),
        ]),
      ),
    );
  }

  Widget _anaEylem(Adisyon a) {
    final partili = a.ham['aktif_parti'] != null;
    final aktifParti = tamSayi(a.ham['aktif_parti'], 1);
    final partiAdi = a.ham['parti_adlari'] is Map ? (a.ham['parti_adlari'] as Map)['$aktifParti']?.toString() : null;
    final unsent = a.gonderilmemis;
    final ogeler = <Widget>[];

    if (partili && a.acik && _can('orders.update')) {
      ogeler.add(OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        onPressed: _mesgul ? null : _partiKapat,
        icon: const Icon(Icons.sync_rounded, size: 16),
        label: Text('$aktifParti. parti${partiAdi != null ? ' · $partiAdi' : ''} kapat — yeni el'),
      ));
    }
    if (a.acik && unsent > 0) {
      ogeler.add(Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, size: 17, color: Renk.uyari),
          const SizedBox(width: 8),
          Expanded(child: Text('$unsent kalem henüz hazırlığa gönderilmedi.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Renk.uyari))),
        ]),
      ));
      if (_can('orders.update')) {
        ogeler.add(FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          onPressed: _mesgul ? null : _tamamlandi,
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text('Tamamlandı — hazırlığa gönder ($unsent)'),
        ));
      }
    } else if (a.hesapIstendi) {
      if (_can('payments.take') || _can('cash.view')) {
        ogeler.add(OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          onPressed: _kasayaGit,
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 17),
          label: const Text('Kasada bekliyor — Kasaya git'),
        ));
      } else {
        ogeler.add(Text('Adisyon kasada bekliyor.', textAlign: TextAlign.center, style: TextStyle(color: Renk.uyari, fontWeight: FontWeight.w600)));
      }
      if (_canOrPin('orders.update')) {
        ogeler.add(TextButton.icon(
          onPressed: _mesgul ? null : _hesapGeriAl,
          icon: const Icon(Icons.undo_rounded, size: 15),
          label: const Text('Yanlışlıkla mı oldu? Hesap isteğini geri al'),
        ));
      }
    } else if (!a.acik) {
      ogeler.add(Text('Bu adisyon kapalı.', textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci)));
    } else {
      ogeler.add(Text('Kalemler hazırlığa gönderildikten sonra adisyon kasaya iletilebilir.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Renk.ikinci)));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Renk.yuzey,
        boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < ogeler.length; i++) ...[if (i > 0) const SizedBox(height: 8), ogeler[i]],
      ]),
    );
  }
}

/* ═════════════ Ürün kartı (§1.3) ═════════════ */

class _UrunKarti extends StatelessWidget {
  const _UrunKarti({
    required this.urun,
    required this.kanal,
    required this.gorselli,
    required this.bekleyen,
    required this.bas,
    this.kategoriRengi,
  });
  final Urun urun;
  final String kanal;
  final bool gorselli;
  final int bekleyen;
  final String? kategoriRengi;
  final VoidCallback bas;

  /// Web ölçüsü: telefonda (dar kart) kare görsel; geniş kartta görsel
  /// bandı yatay (1280 px tablette ≈ 205×76).
  static double bantYuksekligi(double genislik) => genislik < 190 ? genislik : (genislik * .37).clamp(72, 120);

  Color? get _renk {
    final r = kategoriRengi;
    if (r == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(r)) return null;
    return Color(int.parse('FF${r.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final u = urun;
    final secenekli = u.mevcut && u.secimGerekir;
    final oran = MediaQuery.devicePixelRatioOf(context);
    final ilkHarf = u.ad.isEmpty ? '?' : u.ad.characters.first.replaceAll('i', 'İ').toUpperCase();

    Widget monogram(double boy) {
      final r = _renk;
      return Container(
        color: r?.withValues(alpha: .18) ?? Renk.ic,
        alignment: Alignment.center,
        child: Text(ilkHarf, style: TextStyle(fontSize: boy, fontWeight: FontWeight.w900, color: r ?? Renk.soluk)),
      );
    }

    Widget rozetBekleyen(double boy) => Container(
          padding: EdgeInsets.symmetric(horizontal: boy * .6, vertical: 1),
          decoration: BoxDecoration(color: Renk.marka, borderRadius: BorderRadius.circular(999)),
          child: Text('+$bekleyen', style: TextStyle(color: Colors.white, fontSize: boy, fontWeight: FontWeight.w700)),
        );

    Widget rozetSecenek(double boy) => Tooltip(
          message: 'Seçenekli ürün — varyant/ek seçim sorulur',
          child: Container(
            width: boy,
            height: boy,
            decoration: BoxDecoration(color: Renk.uyari, shape: BoxShape.circle),
            child: Icon(Icons.dashboard_outlined, size: boy * .54, color: Colors.white),
          ),
        );

    final Widget icerik;
    if (gorselli) {
      final gorsel = u.gorsel;
      Widget resim(BoxFit fit) => CachedNetworkImage(
            imageUrl: gorsel!,
            fit: fit,
            memCacheWidth: (400 * oran).round().clamp(200, 800),
            fadeInDuration: const Duration(milliseconds: 120),
            errorWidget: (_, _, _) => monogram(20),
          );
      icerik = LayoutBuilder(builder: (context, kutu) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: bantYuksekligi(kutu.maxWidth),
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Renk.ic.withValues(alpha: .7)),
            if (gorsel == null)
              monogram(20)
            else ...[
              // Bulanık zemin: aynı görsel 16 px'e küçük çözülüp gerilir — GPU
              // bulanıklığı (ImageFiltered) ve saydamlık katmanı yok; ürün
              // ızgarası kaydırılırken kart başına iki ekran dışı katman açılıyordu.
              CachedNetworkImage(
                imageUrl: gorsel,
                fit: BoxFit.cover,
                memCacheWidth: 16,
                filterQuality: FilterQuality.medium,
                fadeInDuration: const Duration(milliseconds: 120),
                color: const Color.fromRGBO(255, 255, 255, .7),
                colorBlendMode: BlendMode.modulate,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
              resim(BoxFit.contain),
            ],
            if (!u.mevcut)
              Container(
                color: const Color(0x990F172A),
                alignment: Alignment.center,
                child: const Text('TÜKENDİ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .6)),
              ),
            if (bekleyen > 0) Positioned(left: 6, top: 6, child: rozetBekleyen(11)),
            if (secenekli) Positioned(right: 6, top: 6, child: rozetSecenek(24)),
          ]),
        ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: LayoutBuilder(builder: (context, k) {
              final dar = k.maxWidth < 170;
              final fiyat = Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.sell_outlined, size: dar ? 15 : 14, color: Renk.marka.withValues(alpha: .7)),
                const SizedBox(width: 3),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(u.fiyatEtiketi(kanal), style: TextStyle(fontSize: dar ? 18 : 13.5, fontWeight: FontWeight.w800, color: Renk.marka)),
                  ),
                ),
              ]);
              // Dar kartta (telefonda 3 sütun) ad üstte (17 px, 2 satır), fiyat altta.
              if (k.maxWidth < 170) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(u.ad, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 4),
                  fiyat,
                ]);
              }
              return Row(children: [
                Expanded(
                  child: Text(u.ad, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.15)),
                ),
                const SizedBox(width: 6),
                fiyat,
              ]);
            }),
          ),
        ),
      ]));
    } else {
      icerik = Stack(children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(u.ad, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.15)),
              const SizedBox(height: 4),
              Text(u.fiyatEtiketi(kanal), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Renk.basari)),
              if (!u.mevcut) Text('TÜKENDİ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Renk.hata)),
            ]),
          ),
        ),
        if (bekleyen > 0) Positioned(left: 5, top: 5, child: rozetBekleyen(10)),
        if (secenekli) Positioned(right: 5, top: 5, child: rozetSecenek(20)),
      ]);
    }

    return Opacity(
      opacity: u.mevcut ? 1 : .5,
      child: Semantics(
        label: u.mevcut ? '${u.ad} ekle' : '${u.ad} tükendi',
        button: true,
        child: Material(
          color: Renk.yuzey,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Renk.cizgi)),
          clipBehavior: Clip.antiAlias,
          shadowColor: const Color(0x140F172A),
          elevation: 1,
          child: InkWell(onTap: u.mevcut ? bas : null, child: icerik),
        ),
      ),
    );
  }
}
