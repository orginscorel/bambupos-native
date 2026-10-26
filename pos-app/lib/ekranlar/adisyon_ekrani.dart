import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/katalog_deposu.dart';
import '../core/modeller.dart';
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

/// ADİSYON: ürün ekleme + fiş + hazırlığa gönder + ödeme.
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
  static const _sik = -1;

  Adisyon? _adisyon;
  Katalog? _katalog;
  String? _hata;
  int _kategori = _sik;
  String _arama = '';
  final _aramaDenetim = TextEditingController();
  final List<_Bekleyen> _bekleyenler = [];
  Future<void> _kuyruk = Future.value();
  int _kuyrukta = 0;
  bool _mesgul = false;
  Timer? _tazele;

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
  }

  @override
  void dispose() {
    _tazele?.cancel();
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
    _guncelle(() => _bekleyenler.add(b));

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
            child: Text('${k.adet} × ${k.ad}${k.varyant != null ? ' (${k.varyant})' : ''}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(k.durumEtiket, style: const TextStyle(color: Renk.soluk)),
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
        _ekle(k.urunId!, k.ad, 1, k.adet > 0 ? k.tutar ~/ k.adet : 0,
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

  Future<void> _kisiSayisi() async {
    final n = await metinSor(context, baslik: 'Kişi sayısı', ilkDeger: _adisyon?.kisi?.toString(), enAz: 1);
    final sayi = int.tryParse(n ?? '');
    if (sayi != null && sayi > 0 && mounted) _sirala(() => context.api.put('/api/v1/orders/$id/info', {'guest_count': sayi}));
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
    final cokGenis = g >= 1100;
    final genis = g >= 760;
    final siparisAcik = context.durum.oturum!.yetki('orders.update') || context.durum.oturum!.yetki('orders.create');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bitti, _) async {
        if (bitti) return;
        final nav = Navigator.of(context);
        if (await _cikis()) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          shape: const Border(bottom: BorderSide(color: Renk.cizgi)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a?.baslik ?? 'Adisyon', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (a != null)
              Text(
                ['#${a.id}', a.durumEtiket, if (a.acan != null) a.acan!].join(' · '),
                style: const TextStyle(fontSize: 12, color: Renk.soluk, fontWeight: FontWeight.w500),
              ),
          ]),
          actions: [
            if (a != null)
              TextButton.icon(
                onPressed: _kisiSayisi,
                icon: const Icon(Icons.people_alt_outlined, size: 20),
                label: Text(a.kisi != null ? '${a.kisi}' : 'Kişi'),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: a == null || (_katalog == null && siparisAcik && !widget.kasaKipi)
            ? Center(
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
              )
            : !a.acik
                ? _kapali(a)
                : !siparisAcik || _katalog == null
                    ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _fis()))
                    : genis
                        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            if (cokGenis) SizedBox(width: 190, child: _kategoriSutunu()),
                            if (cokGenis) const VerticalDivider(width: 1),
                            Expanded(child: _urunAlani(yatayKategori: !cokGenis)),
                            const VerticalDivider(width: 1),
                            SizedBox(width: cokGenis ? 400 : 340, child: _fis()),
                          ])
                        : Column(children: [
                            Expanded(child: _urunAlani(yatayKategori: true)),
                            _altCubuk(a),
                          ]),
      ),
    );
  }

  Widget _kapali(Adisyon a) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: Renk.basari, size: 56),
          const SizedBox(height: 12),
          Text('Adisyon ${a.durumEtiket.toLowerCase()}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Toplam ${para(a.toplam)}', style: const TextStyle(color: Renk.soluk)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Panoya dön')),
        ]),
      );

  /* ── Kategoriler ── */

  List<(int, String)> get _kategoriler {
    final k = _katalog!;
    return [
      if (k.sikKullanilan.isNotEmpty) (_sik, 'Sık kullanılan'),
      for (final c in k.doluKategoriler) (c.id, c.ad),
    ];
  }

  Widget _kategoriSutunu() {
    final l = _kategoriler;
    final secili = l.any((e) => e.$1 == _kategori) ? _kategori : (l.isEmpty ? _sik : l.first.$1);
    return ColoredBox(
      color: Renk.yuzey,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: l.length,
        itemBuilder: (_, i) {
          final (kid, ad) = l[i];
          final s = kid == secili && _arama.isEmpty;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: s ? Renk.marka : Colors.transparent,
              borderRadius: koseYuvarlak,
              child: InkWell(
                borderRadius: koseYuvarlak,
                onTap: () => _kategoriSec(kid),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(ad, style: TextStyle(fontWeight: FontWeight.w700, color: s ? Colors.white : Renk.yazi)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _kategoriSec(int kid) {
    _aramaDenetim.clear();
    _guncelle(() {
      _kategori = kid;
      _arama = '';
    });
  }

  Widget _urunAlani({required bool yatayKategori}) {
    final k = _katalog!;
    final l = _kategoriler;
    final secili = l.any((e) => e.$1 == _kategori) ? _kategori : (l.isEmpty ? _sik : l.first.$1);

    final List<Urun> urunler;
    if (_arama.isNotEmpty) {
      final a = aramaAnahtari(_arama);
      urunler = k.urunler.where((u) => u.arama.contains(a)).toList();
    } else {
      urunler = secili == _sik ? k.sikKullanilan : k.kategoriUrunleri(secili);
    }

    return Column(children: [
      Container(
        color: Renk.yuzey,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: TextField(
          controller: _aramaDenetim,
          onChanged: (v) => _guncelle(() => _arama = v.trim()),
          decoration: InputDecoration(
            hintText: 'Ürün ara',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _arama.isEmpty
                ? null
                : IconButton(onPressed: () => _kategoriSec(secili), icon: const Icon(Icons.close_rounded)),
          ),
        ),
      ),
      if (yatayKategori)
        Container(
          color: Renk.yuzey,
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              for (final (kid, ad) in l)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: kid == secili && _arama.isEmpty ? Renk.marka : Renk.zemin,
                    borderRadius: koseYuvarlak,
                    child: InkWell(
                      borderRadius: koseYuvarlak,
                      onTap: () => _kategoriSec(kid),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Text(ad,
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: kid == secili && _arama.isEmpty ? Colors.white : Renk.yazi)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      const Divider(),
      Expanded(
        child: urunler.isEmpty
            ? const Center(child: Text('Ürün bulunamadı', style: TextStyle(color: Renk.soluk)))
            : GridView.builder(
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  mainAxisExtent: 92,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: urunler.length,
                itemBuilder: (_, i) => _UrunKarti(urun: urunler[i], bas: () => _urunSec(urunler[i])),
              ),
      ),
    ]);
  }

  /* ── Fiş ── */

  Widget _fis() => ValueListenableBuilder<int>(
        valueListenable: _degisim,
        builder: (context, _, _) {
          final a = _adisyon!;
          final o = context.durum.oturum!;
          final kalemler = a.kalemler.where((k) => k.aktif || k.ikram).toList().reversed.toList();
          final odemeYetkisi = o.yetki('payments.take') && o.paraGorur;

          return ColoredBox(
            color: Renk.yuzey,
            child: Column(children: [
              if (a.onayBekliyor)
                Container(
                  color: Renk.bilgi.withValues(alpha: .1),
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    const Icon(Icons.qr_code_rounded, color: Renk.bilgi),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('QR siparişi onay bekliyor', style: TextStyle(fontWeight: FontWeight.w700))),
                    FilledButton(onPressed: _onayla, child: const Text('Onayla')),
                  ]),
                ),
              if (a.not != null && a.not!.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Renk.uyari.withValues(alpha: .1),
                  padding: const EdgeInsets.all(10),
                  child: Text('Not: ${a.not}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              Expanded(
                child: kalemler.isEmpty && _bekleyenler.isEmpty
                    ? const Center(
                        child: Text('Henüz kalem yok.\nÜrüne dokunarak ekleyin.', textAlign: TextAlign.center, style: TextStyle(color: Renk.soluk)))
                    : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                        for (final b in _bekleyenler.reversed)
                          _FisSatiri(
                            adet: b.adet,
                            ad: b.ad,
                            tutar: b.tutar,
                            alt: 'Gönderiliyor…',
                            soluk: true,
                          ),
                        for (final k in kalemler)
                          _FisSatiri(
                            adet: k.adet,
                            ad: k.varyant != null ? '${k.ad} (${k.varyant})' : k.ad,
                            tutar: k.tutar,
                            alt: [
                              if (k.secenekler.isNotEmpty) k.secenekler.join(', '),
                              if (k.not != null && k.not!.isNotEmpty) '“${k.not}”',
                            ].join(' · '),
                            durum: k.ikram ? 'İkram' : (k.bekleyenAdet > 0 && !k.hazirliksiz ? 'Gönderilmedi' : k.durumEtiket),
                            durumRengi: k.ikram
                                ? Renk.basari
                                : k.bekleyenAdet > 0 && !k.hazirliksiz
                                    ? Renk.uyari
                                    : k.durum == 'ready'
                                        ? Renk.basari
                                        : Renk.soluk,
                            ustuCizili: k.ikram || k.odendi,
                            bas: () => _kalemIslemleri(k),
                          ),
                      ]),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Column(children: [
                  if (a.indirim > 0) _ToplamSatiri('İndirim', -a.indirim),
                  if (a.ikram > 0) _ToplamSatiri('İkram', -a.ikram),
                  if (a.servisUcreti > 0) _ToplamSatiri('Servis', a.servisUcreti),
                  if (a.odenen > 0) _ToplamSatiri('Ödenen', -a.odenen),
                  Row(children: [
                    Text(a.odenen > 0 ? 'Kalan' : 'Toplam', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(para(a.kalan + _bekleyenler.fold(0, (t, b) => t + b.tutar)),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ]),
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  child: Column(children: [
                    if (a.gonderilmemis > 0 || _bekleyenler.isNotEmpty)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                          onPressed: _mesgul ? null : _gonder,
                          icon: const Icon(Icons.send_rounded),
                          label: Text('Hazırlığa gönder${a.gonderilmemis > 0 ? ' (${a.gonderilmemis})' : ''}'),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(children: [
                      if (!a.hesapIstendi && !odemeYetkisi)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: a.kalemSayisi == 0 ? null : _hesapIste,
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: const Text('Hesap iste'),
                          ),
                        ),
                      if (odemeYetkisi)
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: Renk.basari, minimumSize: const Size.fromHeight(50)),
                            onPressed: a.kalan <= 0 ? null : _odeme,
                            icon: const Icon(Icons.point_of_sale_rounded),
                            label: const Text('Ödeme al'),
                          ),
                        ),
                    ]),
                  ]),
                ),
              ),
            ]),
          );
        },
      );

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
          builder: (_) => FractionallySizedBox(heightFactor: .88, child: _fis()),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(children: [
              const SizedBox(width: 16),
              const Icon(Icons.receipt_long_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text('Adisyon · $adet ürün', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              if (a.gonderilmemis > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Renk.uyari, borderRadius: BorderRadius.circular(4)),
                  child: Text('${a.gonderilmemis} gönderilmedi',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
              const Spacer(),
              Text(para(toplam), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(width: 16),
            ]),
          ),
        ),
      ),
    );
  }
}

class _UrunKarti extends StatelessWidget {
  const _UrunKarti({required this.urun, required this.bas});
  final Urun urun;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) {
    final u = urun;
    return Opacity(
      opacity: u.mevcut ? 1 : .45,
      child: Material(
        color: Renk.yuzey,
        borderRadius: koseYuvarlak,
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: bas,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(u.ad,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.2)),
              ),
              Row(children: [
                Text(u.mevcut ? para(u.gorunenFiyat) : 'Tükendi',
                    style: TextStyle(fontWeight: FontWeight.w800, color: u.mevcut ? Renk.marka : Renk.hata)),
                const Spacer(),
                if (u.secimGerekir) const Icon(Icons.tune_rounded, size: 16, color: Renk.soluk),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FisSatiri extends StatelessWidget {
  const _FisSatiri({
    required this.adet,
    required this.ad,
    required this.tutar,
    this.alt = '',
    this.durum,
    this.durumRengi = Renk.soluk,
    this.soluk = false,
    this.ustuCizili = false,
    this.bas,
  });

  final int adet;
  final String ad;
  final int tutar;
  final String alt;
  final String? durum;
  final Color durumRengi;
  final bool soluk;
  final bool ustuCizili;
  final VoidCallback? bas;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: bas,
      child: Opacity(
        opacity: soluk ? .55 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 34, child: Text('$adet×', style: const TextStyle(fontWeight: FontWeight.w800, color: Renk.marka))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ad, style: TextStyle(fontWeight: FontWeight.w600, decoration: ustuCizili ? TextDecoration.lineThrough : null)),
                if (alt.isNotEmpty) Text(alt, style: const TextStyle(fontSize: 12, color: Renk.soluk)),
                if (durum != null && durum!.isNotEmpty)
                  Text(durum!, style: TextStyle(fontSize: 12, color: durumRengi, fontWeight: FontWeight.w700)),
              ]),
            ),
            Text(para(tutar), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _ToplamSatiri extends StatelessWidget {
  const _ToplamSatiri(this.etiket, this.tutar);
  final String etiket;
  final int tutar;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text(etiket, style: const TextStyle(color: Renk.soluk)),
          const Spacer(),
          Text(para(tutar), style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
