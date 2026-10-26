import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/katalog_deposu.dart';
import '../core/modeller.dart';
import 'cerceve.dart';
import 'odeme.dart';
import 'ortak.dart';
import 'urun_secimi.dart';

/// Ekranda sunucu yanıtı beklenen kalem (iyimser gösterim).
class _Bekleyen {
  _Bekleyen(this.ad, this.adet, this.tutar);
  final String ad;
  final int adet;
  final int tutar;
}

/// Web'deki olay adları (Detail.vue eventTypeLabels).
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
};

/// ADİSYON — web'deki /panel/siparisler/{id} (Detail.vue) düzeni:
///   üst çubukta geri + ürün arama · solda kategori sekmeleri + görselli ürün
///   ızgarası · sağda adisyon başlığı, dört bilgi kutusu (Açılış / Süre /
///   Son sipariş / Ürün), Sepet–Geçmiş sekmeleri, kalemler, ara toplam ve
///   Ödenen / Kalan / Toplam kutuları.
///
/// Hız kuralları:
///  - Katalog bellekte/diskte hazır (ETag) — ekran beklemeden açılır.
///  - Ürüne dokununca satır ANINDA fişte görünür; istek arkadan sıralı
///    kuyrukla gider (aynı adisyona eşzamanlı yazım yok → sürüm çakışmaz).
///  - Her eklemede `op_id` + `Idempotency-Key`: ağ koparsa ve yeniden
///    gönderilirse aynı ürün İKİ KEZ yazılmaz.
class AdisyonEkrani extends StatefulWidget {
  const AdisyonEkrani({super.key, required this.adisyonId, this.kasaKipi = false});
  final int adisyonId;
  final bool kasaKipi;

  @override
  State<AdisyonEkrani> createState() => _AdisyonEkraniState();
}

class _AdisyonEkraniState extends State<AdisyonEkrani> {
  static const _tumu = -1;

  Adisyon? _adisyon;
  Katalog? _katalog;
  String? _hata;
  int _kategori = _tumu;
  String _arama = '';
  bool _gecmis = false;
  final _aramaDenetim = TextEditingController();
  final List<_Bekleyen> _bekleyenler = [];
  Future<void> _kuyruk = Future.value();
  int _kuyrukta = 0;
  bool _mesgul = false;
  Timer? _tazele;
  Timer? _saat;

  /// Alt sayfadaki fiş de güncellensin diye.
  final _degisim = ValueNotifier<int>(0);

  int get id => widget.adisyonId;

  @override
  void initState() {
    super.initState();
    _katalog = KatalogDeposu.ornek.katalog;
    _adisyonuYukle();
    _kataloguYukle();
    // Başka cihazdan eklenen/hazırlanan kalemler görünsün.
    _tazele = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_kuyrukta == 0 && !_mesgul) _adisyonuYukle(sessiz: true);
    });
    // Süre kutusu dakikada bir ilerlesin.
    _saat = Timer.periodic(const Duration(seconds: 30), (_) => _degisim.value++);
  }

  @override
  void dispose() {
    _tazele?.cancel();
    _saat?.cancel();
    _aramaDenetim.dispose();
    _degisim.dispose();
    super.dispose();
  }

  void _guncelle(VoidCallback f) {
    if (!mounted) return;
    setState(f);
    _degisim.value++;
  }

  Future<void> _adisyonuYukle({bool sessiz = false}) async {
    try {
      final r = await context.api.get('/api/v1/orders/$id');
      _adisyonuIsle(r);
    } on ApiHata catch (e) {
      if (!sessiz) _guncelle(() => _hata = e.mesaj);
    }
  }

  void _adisyonuIsle(dynamic r) {
    final ham = r is Map ? r['order'] : null;
    if (ham is Map) _guncelle(() => _adisyon = Adisyon(ham.cast<String, dynamic>()));
  }

  Future<void> _kataloguYukle() async {
    try {
      final k = await KatalogDeposu.ornek.yukle(context.durum);
      if (mounted && k != null) _guncelle(() => _katalog = k);
    } catch (e) {
      if (mounted && _katalog == null) _guncelle(() => _hata = e.toString());
    }
  }

  /// İstekleri SIRAYLA çalıştırır; yanıttaki güncel adisyonu ekrana basar.
  Future<void> _sirala(Future<dynamic> Function() is_, {_Bekleyen? bekleyen}) {
    _kuyrukta++;
    final f = _kuyruk.then((_) async {
      try {
        final r = await is_();
        _adisyonuIsle(r);
      } on ApiHata catch (e) {
        if (mounted) {
          context.bildir(e.mesaj, hata: true);
          context.durum.islemHatasi(e);
          if (e.kod == 409) _adisyonuYukle(sessiz: true);
        }
      } finally {
        _kuyrukta--;
        if (bekleyen != null) _guncelle(() => _bekleyenler.remove(bekleyen));
      }
    });
    _kuyruk = f;
    return f;
  }

  /* ───────── Ürün ekleme ───────── */

  Future<void> _urunSec(Urun u) async {
    if (!u.mevcut) {
      context.bildir('${u.ad} şu an tükendi.');
      return;
    }
    if (u.secimGerekir) {
      final s = await urunSecimiAc(context, u);
      if (s == null || !mounted) return;
      _ekle(u.id, s.etiket, s.adet, s.birimFiyat, varyantId: s.varyantId, secenekler: s.secenekler, not: s.not);
    } else {
      _ekle(u.id, u.ad, 1, u.gorunenFiyat, varyantId: u.varyantlar.length == 1 ? u.varyantlar.first.id : null);
    }
  }

  void _ekle(int urunId, String ad, int adet, int birim,
      {int? varyantId, List<int> secenekler = const [], String? not}) {
    HapticFeedback.lightImpact();
    final b = _Bekleyen(ad, adet, birim * adet);
    _guncelle(() {
      _bekleyenler.add(b);
      _gecmis = false;
    });

    final api = context.api;
    final islem = api.yeniIslemKimligi();
    _sirala(
      () => api.post(
        '/api/v1/orders/$id/items',
        {
          'product_id': urunId,
          'variant_id': ?varyantId,
          'qty': adet,
          if (secenekler.isNotEmpty) 'option_ids': secenekler,
          'note': ?not,
          'op_id': islem,
        },
        {'Idempotency-Key': islem},
      ),
      bekleyen: b,
    );
  }

  /* ───────── Kalem işlemleri ───────── */

  Future<void> _kalemIslemleri(Kalem k) async {
    final o = context.durum.oturum!;
    final secim = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('${k.adet}×${k.ad}${k.varyant != null ? ' (${k.varyant})' : ''}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              [k.durumEtiket, if (k.ilkEkleme.kisi != null) '${saatMetni(k.ilkEkleme.saat)} · ${k.ilkEkleme.kisi}'].join(' · '),
              style: const TextStyle(color: Renk.soluk, fontSize: 13),
            ),
          ),
          if (k.taslak) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: k.adet > 1 ? () => Navigator.pop(ctx, 'azalt') : null,
                        icon: const Icon(Icons.remove_rounded),
                        label: const Text('Bir azalt'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(ctx, 'artir'), icon: const Icon(Icons.add_rounded), label: const Text('Bir artır'))),
              ]),
            ),
            const SizedBox(height: 6),
            ListTile(leading: const Icon(Icons.edit_note_rounded), title: const Text('Not ekle / değiştir'), onTap: () => Navigator.pop(ctx, 'not')),
            ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Renk.hata),
                title: const Text('Kalemi sil', style: TextStyle(color: Renk.hata)),
                onTap: () => Navigator.pop(ctx, 'sil')),
          ] else ...[
            if (k.urunId != null)
              ListTile(leading: const Icon(Icons.add_rounded), title: const Text('Aynısından bir tane daha'), onTap: () => Navigator.pop(ctx, 'tekrar')),
            if (o.yetki('orders.comp') && !k.ikram)
              ListTile(leading: const Icon(Icons.card_giftcard_rounded), title: const Text('İkram et'), onTap: () => Navigator.pop(ctx, 'ikram')),
            if (o.yetki('orders.comp') && k.ikram)
              ListTile(leading: const Icon(Icons.undo_rounded), title: const Text('İkramı geri al'), onTap: () => Navigator.pop(ctx, 'ikramGeri')),
            if (o.yetki('orders.cancel'))
              ListTile(
                  leading: const Icon(Icons.block_rounded, color: Renk.hata),
                  title: const Text('Kalemi iptal et', style: TextStyle(color: Renk.hata)),
                  onTap: () => Navigator.pop(ctx, 'iptal')),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (secim == null || !mounted) return;

    final api = context.api;
    final yol = '/api/v1/orders/$id/items/${k.id}';
    switch (secim) {
      case 'azalt':
        _sirala(() => api.put(yol, {'qty': k.adet - 1}));
      case 'artir':
        _sirala(() => api.put(yol, {'qty': k.adet + 1}));
      case 'not':
        final n = await metinSor(context, baslik: 'Kalem notu', ilkDeger: k.not, ipucu: 'Örn. acısız');
        if (n != null) _sirala(() => api.put(yol, {'note': n}));
      case 'sil':
        _sirala(() => api.delete(yol, {'keep_open': true}));
      case 'tekrar':
        final secenekler = (k.ham['options'] as List? ?? const [])
            .map((x) => tamSayi((x as Map)['option_id']))
            .where((x) => x > 0)
            .toList();
        _ekle(k.urunId!, k.ad, 1, k.birimFiyat,
            varyantId: k.ham['variant_id'] == null ? null : tamSayi(k.ham['variant_id']), secenekler: secenekler);
      case 'ikram':
        final g = await metinSor(context, baslik: 'İkram gerekçesi', enAz: 3, hazir: const ['Müşteri memnuniyeti', 'Müdavim', 'Gecikme telafisi']);
        if (g != null) _sirala(() => api.post('$yol/comp', {'reason': g}));
      case 'ikramGeri':
        _sirala(() => api.delete('$yol/comp'));
      case 'iptal':
        final g = await metinSor(context,
            baslik: 'İptal gerekçesi', enAz: 3, onay: 'İptal et', hazir: const ['Müşteri vazgeçti', 'Yanlış giriş', 'Ürün kalmadı']);
        if (g != null) _sirala(() => api.post('$yol/cancel', {'reason': g, 'keep_open': true}));
    }
  }

  /* ───────── Adisyon işlemleri ───────── */

  Future<void> _gonder() async {
    _guncelle(() => _mesgul = true);
    await _kuyruk; // önce bekleyen eklemeler sunucuya ulaşsın
    if (!mounted) return;
    await _sirala(() => context.api.post('/api/v1/orders/$id/send-to-kitchen'));
    if (mounted) {
      _guncelle(() => _mesgul = false);
      context.bildir('Hazırlığa gönderildi');
    }
  }

  Future<void> _hesapIste() async {
    await _sirala(() => context.api.post('/api/v1/orders/$id/request-bill'));
    if (mounted) context.bildir('Hesap istendi — kasaya iletildi');
  }

  Future<void> _onayla() => _sirala(() => context.api.post('/api/v1/orders/$id/approve'));

  Future<void> _yazdir() async {
    final r = await context.islem(() => context.api.post('/api/v1/orders/$id/print', {'kind': 'receipt'}));
    if (r != null && mounted) context.bildir('Adisyon fişi yazıcıya gönderildi');
  }

  Future<void> _adisyonNotu() async {
    final n = await metinSor(context, baslik: 'Adisyon notu', ilkDeger: _adisyon?.not, ipucu: 'Örn. doğum günü, pastayı sonra getir');
    if (n != null && mounted) _sirala(() => context.api.put('/api/v1/orders/$id/info', {'note': n}));
  }

  Future<void> _kisiSayisi() async {
    final n = await metinSor(context, baslik: 'Kişi sayısı', ilkDeger: _adisyon?.kisi?.toString(), enAz: 1);
    final sayi = int.tryParse(n ?? '');
    if (sayi != null && sayi > 0 && mounted) _sirala(() => context.api.put('/api/v1/orders/$id/info', {'guest_count': sayi}));
  }

  Future<void> _adisyonuIptal() async {
    final g = await metinSor(context,
        baslik: 'Adisyonu iptal et', enAz: 3, onay: 'Adisyonu iptal et', hazir: const ['Müşteri vazgeçti', 'Yanlış masa', 'Deneme']);
    if (g == null || !mounted) return;
    await _sirala(() => context.api.post('/api/v1/orders/$id/cancel', {'reason': g}));
    if (mounted && _adisyon != null && !_adisyon!.acik) Navigator.of(context).pop();
  }

  Future<void> _odeme() async {
    await _kuyruk;
    final a = _adisyon;
    if (a == null || !mounted) return;
    if (a.kalan <= 0) {
      context.bildir('Ödenecek tutar yok.');
      return;
    }
    final yeni = await odemeAc(context, a);
    if (yeni == null || !mounted) return;
    _guncelle(() => _adisyon = yeni);
    if (!yeni.acik || yeni.kalan <= 0) {
      context.bildir('Adisyon kapandı');
      Navigator.of(context).pop();
    }
  }

  Future<bool> _cikis() async {
    await _kuyruk;
    // Hiç kalem girilmeden açılan adisyon masayı boşuna meşgul etmesin.
    final a = _adisyon;
    if (a != null && a.acik && a.kalemler.isEmpty && mounted) {
      try {
        await context.api.post('/api/v1/orders/$id/discard-if-empty');
      } on ApiHata {
        // Sunucu zaten temizler; çıkış engellenmez.
      }
    }
    return true;
  }

  /* ───────── Görünüm ───────── */

  @override
  Widget build(BuildContext context) {
    final a = _adisyon;
    final g = MediaQuery.sizeOf(context).width;
    final genis = g >= 820;
    final o = context.durum.oturum!;
    final siparisAcik = o.yetki('orders.update') || o.yetki('orders.create');

    final Widget govde;
    if (a == null || (_katalog == null && siparisAcik && !widget.kasaKipi)) {
      govde = Center(
        child: _hata != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_hata!, style: const TextStyle(color: Renk.hata)),
                const SizedBox(height: 12),
                OutlinedButton(
                    onPressed: () {
                      _guncelle(() => _hata = null);
                      _adisyonuYukle();
                      _kataloguYukle();
                    },
                    child: const Text('Tekrar dene')),
              ])
            : const CircularProgressIndicator(),
      );
    } else if (!a.acik) {
      govde = _kapali(a);
    } else if (!siparisAcik || _katalog == null) {
      govde = Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _fis()));
    } else if (genis) {
      govde = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _urunAlani()),
        Container(width: 1, color: Renk.cizgi),
        SizedBox(width: g >= 1200 ? 400 : 360, child: _fis()),
      ]);
    } else {
      govde = Column(children: [Expanded(child: _urunAlani()), _altCubuk(a)]);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bitti, _) async {
        if (bitti) return;
        final nav = Navigator.of(context);
        if (await _cikis()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: Renk.yuzey,
        appBar: UstCubuk(
          baslik: o.isletme,
          altSatir: [o.sube ?? '', o.isletmeKod].where((s) => s.isNotEmpty).join(' · '),
          rozet: 'Sipariş ekranı',
          sol: IconButton(
            tooltip: 'Panoya dön',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28, color: Renk.yazi),
          ),
          orta: siparisAcik && _katalog != null && a != null && a.acik ? _aramaKutusu() : null,
        ),
        body: govde,
      ),
    );
  }

  Widget _aramaKutusu() => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _aramaDenetim,
              onChanged: (v) => _guncelle(() => _arama = v.trim()),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ürün ara…',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                prefixIcon: const Icon(Icons.search_rounded, size: 19, color: Renk.soluk),
                suffixIcon: _arama.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _aramaDenetim.clear();
                          _guncelle(() => _arama = '');
                        },
                        icon: const Icon(Icons.close_rounded, size: 18)),
              ),
            ),
          ),
        ),
      );

  Widget _kapali(Adisyon a) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: Renk.basari, size: 56),
          const SizedBox(height: 12),
          Text('Adisyon ${a.durumEtiket.toLowerCase()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Toplam ${para(a.toplam)}', style: const TextStyle(color: Renk.soluk)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Panoya dön')),
        ]),
      );

  /* ── Ürün alanı ── */

  Widget _urunAlani() {
    final k = _katalog!;
    final gorselli = context.durum.oturum!.eklenti('adisyon_gorselli');
    final kategoriler = [(_tumu, 'Tümü'), for (final c in k.doluKategoriler) (c.id, c.ad)];
    final secili = kategoriler.any((e) => e.$1 == _kategori) ? _kategori : _tumu;

    final List<Urun> urunler;
    if (_arama.isNotEmpty) {
      final a = aramaAnahtari(_arama);
      urunler = k.urunler.where((u) => u.arama.contains(a)).toList();
    } else {
      urunler = secili == _tumu ? k.urunler : k.kategoriUrunleri(secili);
    }

    return ColoredBox(
      color: Renk.yuzey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Web: kalın metin sekmeleri, satıra sığmazsa alt satıra iner.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Wrap(spacing: 4, runSpacing: 0, children: [
            for (final (kid, ad) in kategoriler)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  _aramaDenetim.clear();
                  _guncelle(() {
                    _kategori = kid;
                    _arama = '';
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: kid == secili && _arama.isEmpty ? Renk.marka : Colors.transparent, width: 2.5),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (kid == _tumu) ...[
                      Icon(Icons.format_list_bulleted_rounded, size: 18, color: kid == secili ? Renk.marka : Renk.yazi),
                      const SizedBox(width: 4),
                    ],
                    Text(ad,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          color: kid == secili && _arama.isEmpty ? Renk.marka : Renk.yazi,
                        )),
                  ]),
                ),
              ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ColoredBox(
            color: Renk.zemin,
            child: urunler.isEmpty
                ? const Center(child: Text('Ürün bulunamadı', style: TextStyle(color: Renk.soluk)))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 215,
                      mainAxisExtent: gorselli ? 116 : 78,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: urunler.length,
                    itemBuilder: (_, i) => _UrunKarti(urun: urunler[i], gorselli: gorselli, bas: () => _urunSec(urunler[i])),
                  ),
          ),
        ),
      ]),
    );
  }

  /* ── Fiş (sağ panel) ── */

  Widget _fis() => ValueListenableBuilder<int>(
        valueListenable: _degisim,
        builder: (context, _, _) {
          final a = _adisyon!;
          final o = context.durum.oturum!;
          final fark = o.saatFarki;
          final kalemler = a.kalemler.where((k) => k.aktif || k.ikram).toList();
          final odemeYetkisi = o.yetki('payments.take') && o.paraGorur;
          final bekleyenToplam = _bekleyenler.fold<int>(0, (t, b) => t + b.tutar);
          final sonSiparis = a.kalemler
              .map((k) => k.ilkEkleme.saat ?? _metin(k.ham['created_at']))
              .whereType<String>()
              .fold<String?>(null, (en, s) => en == null || s.compareTo(en) > 0 ? s : en);
          final urunAdedi = a.aktifKalemler.fold<int>(0, (t, k) => t + k.adet) + _bekleyenler.fold<int>(0, (t, b) => t + b.adet);
          final kdv = (a.ham['vat_by_rate'] as List? ?? const []).whereType<Map>().toList();

          return ColoredBox(
            color: Renk.yuzey,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Başlık
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: a.baslik, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        TextSpan(text: '  #${a.id}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.soluk)),
                      ]),
                    ),
                  ),
                  Rozet(a.durumEtiket, renk: Renk.bilgi, zemin: Renk.bilgiZemin, kenar: Renk.bilgiKenar, ikon: Icons.circle),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (a.kaynakEtiket.isNotEmpty) _ust(a.kaynakEtiket),
                  if (a.servisTuruEtiket.isNotEmpty) _ust('·  ${a.servisTuruEtiket}'),
                  InkWell(
                    onTap: _kisiSayisi,
                    child: _ust('·  ${a.kisi ?? '—'} kişi', ikon: Icons.people_outline_rounded),
                  ),
                  _ust('·  ${a.servisEdilen}/${a.kalemSayisi} servis', ikon: Icons.restaurant_rounded, renk: Renk.uyari),
                  if (a.acan != null) _ust('·  ${a.acan}'),
                ]),
              ),
              if (a.onayBekliyor)
                Container(
                  color: Renk.bilgiZemin,
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.qr_code_rounded, color: Renk.bilgi),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('QR siparişi onay bekliyor', style: TextStyle(fontWeight: FontWeight.w600))),
                    FilledButton(onPressed: _onayla, child: const Text('Onayla')),
                  ]),
                ),
              // Dört bilgi kutusu
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Container(
                  decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                  clipBehavior: Clip.antiAlias,
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _BilgiKutusu('AÇILIŞ', saatMetni(_metin(a.ham['created_at']))),
                      _BilgiKutusu('SÜRE', sureMetni(gecenDakika(_metin(a.ham['created_at']), saatFarki: fark)), renk: Renk.bilgi),
                      _BilgiKutusu('SON SİPARİŞ', sonSiparis == null ? '—' : saatMetni(sonSiparis), renk: Renk.uyari),
                      _BilgiKutusu('ÜRÜN', '$urunAdedi', renk: Renk.marka, zemin: Renk.markaAcik, son: true),
                    ]),
                  ),
                ),
              ),
              if (a.not != null && a.not!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
                  child: Text('Not: ${a.not}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              const SizedBox(height: 8),
              // Sepet / Geçmiş + simge düğmeler
              Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi), bottom: BorderSide(color: Renk.cizgi))),
                height: 44,
                child: Row(children: [
                  _FisSekmesi(
                      ikon: Icons.shopping_cart_outlined,
                      etiket: 'Sepet',
                      sayi: kalemler.length + _bekleyenler.length,
                      secili: !_gecmis,
                      bas: () => _guncelle(() => _gecmis = false)),
                  _FisSekmesi(
                      ikon: Icons.sync_rounded,
                      etiket: 'Geçmiş',
                      sayi: a.olaylar.length,
                      secili: _gecmis,
                      bas: () => _guncelle(() => _gecmis = true)),
                  const Spacer(),
                  _SimgeDugme(ikon: Icons.print_outlined, ipucu: 'Adisyon fişi yazdır', bas: _yazdir, vurgulu: true),
                  _SimgeDugme(ikon: Icons.sticky_note_2_outlined, ipucu: 'Adisyon notu', bas: _adisyonNotu),
                  _SimgeDugme(
                    ikon: Icons.more_vert_rounded,
                    ipucu: 'Diğer',
                    bas: () async {
                      final s = await showModalBottomSheet<String>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(leading: const Icon(Icons.people_outline_rounded), title: const Text('Kişi sayısı'), onTap: () => Navigator.pop(ctx, 'kisi')),
                            if (!a.hesapIstendi)
                              ListTile(leading: const Icon(Icons.receipt_long_outlined), title: const Text('Hesap iste (kasaya gönder)'), onTap: () => Navigator.pop(ctx, 'hesap')),
                            ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('Yenile'), onTap: () => Navigator.pop(ctx, 'yenile')),
                          ]),
                        ),
                      );
                      if (s == 'kisi') _kisiSayisi();
                      if (s == 'hesap') _hesapIste();
                      if (s == 'yenile') _adisyonuYukle();
                    },
                  ),
                  if (o.yetki('orders.cancel'))
                    _SimgeDugme(ikon: Icons.delete_outline_rounded, ipucu: 'Adisyonu iptal et', bas: _adisyonuIptal, tehlikeli: true),
                  const SizedBox(width: 6),
                ]),
              ),
              Expanded(
                child: _gecmis
                    ? _gecmisListesi(a)
                    : kalemler.isEmpty && _bekleyenler.isEmpty
                        ? const Center(
                            child: Text('Sepet boş.\nÜrüne dokunarak ekleyin.', textAlign: TextAlign.center, style: TextStyle(color: Renk.soluk)))
                        : ListView(padding: EdgeInsets.zero, children: [
                            for (final k in kalemler) _kalemSatiri(k),
                            for (final b in _bekleyenler) _bekleyenSatiri(b),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                              child: Column(children: [
                                _ToplamSatiri('Ara toplam', a.araToplam + bekleyenToplam),
                                if (a.ikram > 0) _ToplamSatiri('İkramlar', a.ikram, renk: Renk.basari),
                                if (a.indirim > 0) _ToplamSatiri('İndirim', -a.indirim, renk: Renk.hata),
                                if (a.servisUcreti > 0) _ToplamSatiri('Servis bedeli', a.servisUcreti),
                                for (final v in kdv)
                                  _ToplamSatiri('KDV %${_oran(v['rate'])} (dahil)', tamSayi(v['vat_minor']), kucuk: true),
                              ]),
                            ),
                          ]),
              ),
              if (a.gonderilmemis > 0 || _bekleyenler.isNotEmpty || odemeYetkisi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Row(children: [
                    if (a.gonderilmemis > 0 || _bekleyenler.isNotEmpty)
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: _mesgul ? null : _gonder,
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text('Hazırlığa gönder${a.gonderilmemis > 0 ? ' (${a.gonderilmemis})' : ''}'),
                        ),
                      ),
                    if ((a.gonderilmemis > 0 || _bekleyenler.isNotEmpty) && odemeYetkisi) const SizedBox(width: 8),
                    if (odemeYetkisi)
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Renk.basari, minimumSize: const Size.fromHeight(48)),
                          onPressed: a.kalan <= 0 ? null : _odeme,
                          icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                          label: const Text('Ödeme al'),
                        ),
                      ),
                  ]),
                ),
              // Ödenen / Kalan / Toplam
              Container(
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
                child: IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _AltKutu(ikon: Icons.check_circle_outline_rounded, etiket: 'ÖDENEN', tutar: a.odenen, renk: Renk.basari, zemin: Renk.basariZemin),
                    _AltKutu(
                        ikon: Icons.account_balance_wallet_outlined,
                        etiket: 'KALAN',
                        tutar: a.kalan + bekleyenToplam,
                        renk: Renk.uyari,
                        zemin: Renk.uyariZemin),
                    _AltKutu(
                        ikon: Icons.receipt_outlined,
                        etiket: 'TOPLAM',
                        tutar: a.toplam + bekleyenToplam,
                        renk: Renk.marka,
                        zemin: Renk.markaAcik,
                        son: true),
                  ]),
                ),
              ),
              if (!odemeYetkisi)
                Container(
                  color: Renk.yuzey,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Text(
                    a.hesapIstendi ? 'Hesap istendi — adisyon kasada.' : 'Kalemler hazırlığa gönderildikten sonra adisyon kasaya iletilebilir.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11.5, color: Renk.ikinci),
                  ),
                ),
            ]),
          );
        },
      );

  static String? _metin(Object? v) => v?.toString();

  static String _oran(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString().replaceAll('.', ',');
  }

  Widget _ust(String m, {IconData? ikon, Color renk = Renk.soluk}) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (ikon != null) ...[Icon(ikon, size: 13, color: renk), const SizedBox(width: 2)],
        Text(m, style: TextStyle(fontSize: 11.5, color: renk, fontWeight: renk == Renk.soluk ? FontWeight.w400 : FontWeight.w600)),
      ]);

  Widget _kalemSatiri(Kalem k) {
    final bekliyor = k.bekleyenAdet > 0 && !k.hazirliksiz && !k.ikram;
    final alt = [
      if (k.ikram) 'İkram${k.ikramNedeni != null ? ' — ${k.ikramNedeni}' : ''}',
      if (k.secenekler.isNotEmpty) k.secenekler.join(', '),
      if (k.not != null && k.not!.isNotEmpty) '“${k.not}”',
      if (bekliyor) 'Hazırlığa gönderilmedi' else if (!k.ikram && k.durumEtiket.isNotEmpty) k.durumEtiket,
    ];
    return Material(
      color: Renk.zemin,
      child: InkWell(
        onTap: () => _kalemIslemleri(k),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${k.adet}×${k.ad}${k.varyant != null ? ' (${k.varyant})' : ''}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                if (alt.isNotEmpty)
                  Text(alt.join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: k.ikram ? Renk.basari : (bekliyor ? Renk.uyari : Renk.soluk),
                        fontWeight: bekliyor ? FontWeight.w600 : FontWeight.w400,
                      )),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(para(k.tutar),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    decoration: k.ikram ? TextDecoration.lineThrough : null,
                    color: k.ikram ? Renk.soluk : Renk.yazi,
                  )),
              Text('${para(k.birimFiyat)} / adet', style: const TextStyle(fontSize: 11.5, color: Renk.soluk)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _bekleyenSatiri(_Bekleyen b) => Opacity(
        opacity: .55,
        child: Container(
          color: Renk.zemin,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Expanded(child: Text('${b.adet}×${b.ad}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6)),
            const SizedBox(width: 8),
            Text(para(b.tutar), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _gecmisListesi(Adisyon a) {
    if (a.olaylar.isEmpty) return const Center(child: Text('Kayıt yok', style: TextStyle(color: Renk.soluk)));
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: a.olaylar.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (_, i) {
        final e = a.olaylar[i];
        final tur = '${e['type'] ?? ''}';
        final p = e['payload'] is Map ? e['payload'] as Map : const {};
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: _olayAdlari[tur] ?? tur, style: const TextStyle(fontSize: 13)),
                if (tur == 'item_swapped' && p.isNotEmpty)
                  TextSpan(text: '  ${p['from']} → ${p['to']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                if (p['name'] != null && tur.startsWith('item_'))
                  TextSpan(text: '  ${p['qty'] ?? p['added_qty'] ?? ''}×${p['name']}', style: const TextStyle(fontSize: 12, color: Renk.ikinci)),
                if (e['user'] != null) TextSpan(text: '  · ${e['user']}', style: const TextStyle(fontSize: 12, color: Renk.soluk)),
              ])),
            ),
            Text(saatMetni(e['created_at']?.toString()), style: const TextStyle(fontSize: 12, color: Renk.soluk)),
          ]),
        );
      },
    );
  }

  Widget _altCubuk(Adisyon a) {
    final adet = a.aktifKalemler.fold<int>(0, (t, k) => t + k.adet) + _bekleyenler.fold<int>(0, (t, b) => t + b.adet);
    final toplam = a.kalan + _bekleyenler.fold<int>(0, (t, b) => t + b.tutar);
    return Material(
      color: Renk.marka,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => FractionallySizedBox(heightFactor: .92, child: _fis()),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(children: [
              const SizedBox(width: 16),
              const Icon(Icons.shopping_cart_outlined, color: Colors.white),
              const SizedBox(width: 10),
              Text('${a.baslik} · $adet ürün', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
              if (a.gonderilmemis > 0) ...[
                const SizedBox(width: 8),
                Rozet('${a.gonderilmemis} gönderilmedi', renk: Renk.uyari, dolu: true),
              ],
              const Spacer(),
              Text(para(toplam), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(width: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

/* ───────── Bileşenler ───────── */

class _UrunKarti extends StatelessWidget {
  const _UrunKarti({required this.urun, required this.gorselli, required this.bas});
  final Urun urun;
  final bool gorselli;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) {
    final u = urun;
    final gorsel = gorselli ? u.gorsel : null;
    final oran = MediaQuery.devicePixelRatioOf(context);

    Widget resim(BoxFit fit) => CachedNetworkImage(
          imageUrl: gorsel!,
          fit: fit,
          memCacheWidth: (220 * oran).round(),
          fadeInDuration: const Duration(milliseconds: 120),
          errorWidget: (_, _, _) => const SizedBox.shrink(),
        );

    return Opacity(
      opacity: u.mevcut ? 1 : .5,
      child: Material(
        color: Renk.yuzey,
        borderRadius: koseYuvarlak,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: bas,
          child: Container(
            decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi), boxShadow: kartGolge),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (gorselli)
                Expanded(
                  child: gorsel == null
                      ? Container(color: Renk.ic, child: const Icon(Icons.restaurant_rounded, color: Color(0xFFCBD5E1)))
                      : Stack(fit: StackFit.expand, children: [
                          // Web: aynı görsel bulanık zemin olarak, ortada net hâli.
                          ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Opacity(opacity: .7, child: resim(BoxFit.cover)),
                          ),
                          resim(BoxFit.contain),
                        ]),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                    child: Text(u.ad,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.15)),
                  ),
                  const SizedBox(width: 4),
                  if (!u.mevcut)
                    const Text('tükendi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.hata))
                  else ...[
                    const Icon(Icons.sell_outlined, size: 13, color: Renk.vurgu),
                    const SizedBox(width: 3),
                    Text(para(u.gorunenFiyat), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Renk.vurgu)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BilgiKutusu extends StatelessWidget {
  const _BilgiKutusu(this.etiket, this.deger, {this.renk = Renk.yazi, this.zemin, this.son = false});
  final String etiket;
  final String deger;
  final Color renk;
  final Color? zemin;
  final bool son;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: zemin, border: son ? null : const Border(right: BorderSide(color: Renk.cizgi))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(etiket, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Renk.soluk, letterSpacing: .4)),
            const SizedBox(height: 2),
            Text(deger, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: renk)),
          ]),
        ),
      );
}

class _FisSekmesi extends StatelessWidget {
  const _FisSekmesi({required this.ikon, required this.etiket, required this.sayi, required this.secili, required this.bas});
  final IconData ikon;
  final String etiket;
  final int sayi;
  final bool secili;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: bas,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: secili ? Renk.marka : Colors.transparent, width: 2)),
          ),
          child: Row(children: [
            Icon(ikon, size: 18, color: secili ? Renk.marka : Renk.ikinci),
            const SizedBox(width: 6),
            Text(etiket, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, color: secili ? Renk.marka : Renk.yazi)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(5)),
              child: Text('$sayi', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      );
}

class _SimgeDugme extends StatelessWidget {
  const _SimgeDugme({required this.ikon, required this.ipucu, required this.bas, this.vurgulu = false, this.tehlikeli = false});
  final IconData ikon;
  final String ipucu;
  final VoidCallback bas;
  final bool vurgulu;
  final bool tehlikeli;

  @override
  Widget build(BuildContext context) {
    final renk = tehlikeli ? Renk.hata : (vurgulu ? Renk.marka : Renk.ikinci);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: ipucu,
        child: Material(
          color: tehlikeli ? Renk.hataZemin : (vurgulu ? Renk.markaAcik : Renk.yuzey),
          borderRadius: koseYuvarlak,
          child: InkWell(
            borderRadius: koseYuvarlak,
            onTap: bas,
            child: Container(
              width: 34,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: koseYuvarlak,
                border: Border.all(color: tehlikeli ? Renk.hataKenar : (vurgulu ? Renk.markaKenar : Renk.cizgi)),
              ),
              child: Icon(ikon, size: 18, color: renk),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToplamSatiri extends StatelessWidget {
  const _ToplamSatiri(this.etiket, this.tutar, {this.renk = Renk.yazi, this.kucuk = false});
  final String etiket;
  final int tutar;
  final Color renk;
  final bool kucuk;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Text(etiket, style: TextStyle(fontSize: kucuk ? 11.5 : 13, color: renk == Renk.yazi ? Renk.ikinci : renk)),
          const Spacer(),
          Text(para(tutar), style: TextStyle(fontSize: kucuk ? 11.5 : 13, fontWeight: FontWeight.w500, color: renk)),
        ]),
      );
}

class _AltKutu extends StatelessWidget {
  const _AltKutu({required this.ikon, required this.etiket, required this.tutar, required this.renk, required this.zemin, this.son = false});
  final IconData ikon;
  final String etiket;
  final int tutar;
  final Color renk;
  final Color zemin;
  final bool son;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: zemin, border: son ? null : const Border(right: BorderSide(color: Renk.cizgi))),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ikon, size: 12, color: Renk.soluk),
              const SizedBox(width: 3),
              Text(etiket, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Renk.soluk, letterSpacing: .4)),
            ]),
            const SizedBox(height: 2),
            Text(para(tutar), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: renk)),
          ]),
        ),
      );
}
