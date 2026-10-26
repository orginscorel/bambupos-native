import 'dart:async';

import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'adisyon_ekrani.dart';
import 'ortak.dart';

/// Masa panosu (sipariş girişi) ve kasa listesi.
///
/// Veri `GET /api/v1/orders/board`'dan gelir; ekran açıkken birkaç
/// saniyede bir tazelenir. Son pano diske yazılır: uygulama açılır açılmaz
/// masalar görünür, ağ yanıtı gelince güncellenir.
class MasaPanosu extends StatefulWidget {
  const MasaPanosu({super.key, this.kasaKipi = false});
  final bool kasaKipi;

  @override
  State<MasaPanosu> createState() => _MasaPanosuState();
}

class _MasaPanosuState extends State<MasaPanosu> {
  static const _paket = '__paket__';
  static const _cari = '__cari__';

  Pano? _pano;
  bool _baglantiYok = false;
  bool _yukleniyor = false;
  String? _alan;
  Timer? _zamanlayici;
  bool _acilisYapiliyor = false;

  @override
  void initState() {
    super.initState();
    _onbellektenAc();
    _yenile();
    _zamanlayici = Timer.periodic(const Duration(seconds: 5), (_) => _yenile());
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    super.dispose();
  }

  Future<void> _onbellektenAc() async {
    final ham = await context.durum.onbellekOku('pano');
    if (ham != null && mounted && _pano == null) setState(() => _pano = Pano(ham));
  }

  Future<void> _yenile() async {
    if (_yukleniyor || !mounted) return;
    _yukleniyor = true;
    try {
      final veri = (await context.api.get('/api/v1/orders/board') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _pano = Pano(veri);
        _baglantiYok = false;
      });
      context.durum.onbellekYaz('pano', veri);
    } on ApiHata catch (e) {
      if (mounted) setState(() => _baglantiYok = e.baglantiYok);
    } finally {
      _yukleniyor = false;
    }
  }

  Future<void> _adisyonuAc(int id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdisyonEkrani(adisyonId: id, kasaKipi: widget.kasaKipi),
    ));
    _yenile();
  }

  Future<void> _masayaDokun(Masa m) async {
    if (_acilisYapiliyor) return;
    final bagli = m.bagli;
    if (bagli != null) return _adisyonuAc(tamSayi(bagli['order_id']));

    if (m.dolu) {
      if (m.adisyonlar.length == 1) return _adisyonuAc(m.adisyonlar.first.id);
      final secilen = await showModalBottomSheet<int>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('${m.ad} · adisyonlar', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ),
            for (final a in m.adisyonlar)
              ListTile(
                title: Text('Adisyon #${a.id}'),
                subtitle: Text('${a.kalemSayisi} kalem · ${a.acan ?? ''}'),
                trailing: Text(para(a.kalan), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(ctx, a.id),
              ),
          ]),
        ),
      );
      if (secilen != null) await _adisyonuAc(secilen);
      return;
    }

    if (m.servisDisi) {
      context.bildir('${m.ad} servis dışı.');
      return;
    }
    if (!context.durum.oturum!.yetki('orders.create')) {
      context.bildir('Adisyon açma yetkiniz yok.', hata: true);
      return;
    }
    await _yeniAdisyon({'table_id': m.id});
  }

  Future<void> _yeniAdisyon(Map<String, dynamic> govde) async {
    setState(() => _acilisYapiliyor = true);
    try {
      dynamic r;
      try {
        r = await context.api.post('/api/v1/orders', govde);
      } on ApiHata catch (e) {
        // 409: masanın yaklaşan rezervasyonu var — personel onaylarsa açılır.
        if (e.kod != 409 || !mounted) rethrow;
        final tamam = await onayla(context, 'Rezervasyon uyarısı', e.mesaj, onay: 'Yine de aç');
        if (!tamam || !mounted) return;
        r = await context.api.post('/api/v1/orders', {...govde, 'confirm': true});
      }
      final id = tamSayi(((r as Map)['order'] as Map)['id']);
      if (mounted && id > 0) await _adisyonuAc(id);
    } on ApiHata catch (e) {
      if (mounted) {
        context.bildir(e.mesaj, hata: true);
        context.durum.islemHatasi(e);
      }
    } finally {
      if (mounted) setState(() => _acilisYapiliyor = false);
    }
  }

  Future<void> _talepTamam(ServisTalebi t) async {
    await context.islem(() => context.api.post('/api/v1/orders/service-requests/${t.id}/done'));
    _yenile();
  }

  @override
  Widget build(BuildContext context) {
    final pano = _pano;
    if (pano == null) {
      return Column(children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ]);
    }

    final o = context.durum.oturum!;
    final saatFarki = o.saatFarki;

    return Stack(children: [
      Column(children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        if (pano.talepler.isNotEmpty || pano.onayBekleyen.isNotEmpty) _uyarilar(pano),
        Expanded(child: widget.kasaKipi ? _kasaListesi(pano, saatFarki) : _masalar(pano, saatFarki)),
      ]),
      if (_acilisYapiliyor)
        const Positioned.fill(child: ColoredBox(color: Color(0x33000000), child: Center(child: CircularProgressIndicator()))),
      if (!widget.kasaKipi && o.yetki('orders.create'))
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'hizli',
            shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
            backgroundColor: Renk.marka,
            foregroundColor: Colors.white,
            onPressed: () => _yeniAdisyon({'channel': 'pickup', 'service_type': 'takeaway'}),
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('Gel-al satış'),
          ),
        ),
    ]);
  }

  Widget _uyarilar(Pano pano) {
    return Container(
      width: double.infinity,
      color: Renk.yuzey,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final a in pano.onayBekleyen)
          _UyariKarti(
            ikon: Icons.qr_code_rounded,
            renk: Renk.bilgi,
            metin: '${a.baslik} · QR siparişi onay bekliyor',
            dugme: 'Aç',
            basildi: () => _adisyonuAc(a.id),
          ),
        for (final t in pano.talepler)
          _UyariKarti(
            ikon: t.tur == 'bill' ? Icons.receipt_long_rounded : Icons.notifications_active_rounded,
            renk: Renk.uyari,
            metin: '${t.masa} · ${t.etiket}',
            dugme: 'Tamam',
            basildi: () => _talepTamam(t),
          ),
      ]),
    );
  }

  /* ───────── Masalar ───────── */

  Widget _masalar(Pano pano, Duration saatFarki) {
    final sekmeler = [
      ...pano.alanlar,
      if (pano.kanalSiparisleri.isNotEmpty) _paket,
      if (pano.cariler.isNotEmpty) _cari,
    ];
    if (sekmeler.isEmpty) {
      return const Center(child: Text('Bu şubede tanımlı masa yok.', style: TextStyle(color: Renk.soluk)));
    }
    final alan = sekmeler.contains(_alan) ? _alan! : sekmeler.first;

    final Widget icerik;
    if (alan == _paket) {
      icerik = _adisyonIzgarasi(pano.kanalSiparisleri, saatFarki);
    } else if (alan == _cari) {
      icerik = _cariIzgarasi(pano.cariler, saatFarki);
    } else {
      final masalar = pano.masalar.where((m) => m.alan == alan).toList();
      icerik = GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          mainAxisExtent: 112,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: masalar.length,
        itemBuilder: (_, i) => _MasaKarti(masa: masalar[i], saatFarki: saatFarki, dokun: () => _masayaDokun(masalar[i])),
      );
    }

    return Column(children: [
      if (sekmeler.length > 1)
        Container(
          color: Renk.yuzey,
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final s in sekmeler)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SekmeDugmesi(
                    etiket: s == _paket ? 'Paket / Diğer' : s == _cari ? 'Cariler' : s,
                    sayi: s == _paket
                        ? pano.kanalSiparisleri.length
                        : s == _cari
                            ? pano.cariler.where((c) => c.adisyonlar.isNotEmpty).length
                            : pano.masalar.where((m) => m.alan == s && m.dolu).length,
                    secili: s == alan,
                    bas: () => setState(() => _alan = s),
                  ),
                ),
            ],
          ),
        ),
      Expanded(child: RefreshIndicator(onRefresh: _yenile, child: icerik)),
    ]);
  }

  Widget _adisyonIzgarasi(List<AdisyonOzet> l, Duration saatFarki) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220, mainAxisExtent: 112, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: l.length,
        itemBuilder: (_, i) => _AdisyonKarti(adisyon: l[i], saatFarki: saatFarki, dokun: () => _adisyonuAc(l[i].id)),
      );

  Widget _cariIzgarasi(List<CariKart> l, Duration saatFarki) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220, mainAxisExtent: 112, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: l.length,
        itemBuilder: (_, i) {
          final c = l[i];
          return _KartCercevesi(
            dolu: c.adisyonlar.isNotEmpty,
            renk: Renk.marka,
            dokun: () => c.adisyonlar.isNotEmpty ? _adisyonuAc(c.adisyonlar.first.id) : _yeniAdisyon({'receivable_id': c.id}),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (c.adisyonlar.isNotEmpty)
                Text(para(c.adisyonlar.first.kalan), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (c.borc > 0) Text('Borç: ${para(c.borc)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          );
        },
      );

  /* ───────── Kasa ───────── */

  Widget _kasaListesi(Pano pano, Duration saatFarki) {
    final l = pano.acikAdisyonlar
      ..sort((a, b) {
        if (a.hesapIstendi != b.hesapIstendi) return a.hesapIstendi ? -1 : 1;
        return b.kalan.compareTo(a.kalan);
      });
    final toplam = l.fold<int>(0, (t, a) => t + a.kalan);

    return Column(children: [
      Container(
        color: Renk.yuzey,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Text('${l.length} açık adisyon', style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          const Text('Bekleyen: ', style: TextStyle(color: Renk.soluk)),
          Text(para(toplam), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      ),
      const Divider(),
      Expanded(
        child: l.isEmpty
            ? const Center(child: Text('Ödeme bekleyen adisyon yok.', style: TextStyle(color: Renk.soluk)))
            : RefreshIndicator(
                onRefresh: _yenile,
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 260, mainAxisExtent: 120, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: l.length,
                  itemBuilder: (_, i) => _AdisyonKarti(adisyon: l[i], saatFarki: saatFarki, dokun: () => _adisyonuAc(l[i].id)),
                ),
              ),
      ),
    ]);
  }
}

/* ───────── Kartlar ───────── */

class _KartCercevesi extends StatelessWidget {
  const _KartCercevesi({required this.child, required this.dokun, required this.dolu, required this.renk, this.kenar});
  final Widget child;
  final VoidCallback dokun;
  final bool dolu;
  final Color renk;
  final Color? kenar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: dolu ? renk : Renk.yuzey,
      borderRadius: koseYuvarlak,
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: dokun,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: koseYuvarlak,
            border: Border.all(color: kenar ?? (dolu ? renk : Renk.cizgi), width: kenar != null ? 2 : 1),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: dolu ? Colors.white : Renk.yazi),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MasaKarti extends StatelessWidget {
  const _MasaKarti({required this.masa, required this.saatFarki, required this.dokun});
  final Masa masa;
  final Duration saatFarki;
  final VoidCallback dokun;

  @override
  Widget build(BuildContext context) {
    final m = masa;
    final bagli = m.bagli;
    final rez = m.rezervasyon;

    if (bagli != null) {
      return _KartCercevesi(
        dolu: true,
        renk: const Color(0xFF8B80E3),
        dokun: dokun,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m.ad, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Spacer(),
          Row(children: [
            const Icon(Icons.link_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Expanded(child: Text('${bagli['table_name'] ?? ''} ile birleşik', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ]),
      );
    }

    if (!m.dolu) {
      return Opacity(
        opacity: m.servisDisi ? .45 : 1,
        child: _KartCercevesi(
          dolu: false,
          renk: Renk.yuzey,
          kenar: rez != null ? Renk.bilgi : null,
          dokun: dokun,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.ad, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (rez != null) ...[
              Text('Rezerve ${rez['time'] ?? ''}', style: const TextStyle(color: Renk.bilgi, fontWeight: FontWeight.w700)),
              Text('${rez['name'] ?? ''} · ${rez['party'] ?? ''} kişi',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Renk.soluk)),
            ] else
              Text(m.servisDisi ? 'Servis dışı' : 'Boş', style: const TextStyle(color: Renk.soluk, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
    }

    final a = m.adisyonlar.first;
    final renk = a.hesapIstendi ? Renk.uyari : a.onayBekliyor ? Renk.bilgi : Renk.marka;
    final kalan = m.adisyonlar.fold<int>(0, (t, x) => t + x.kalan);
    final dk = gecenDakika(a.acilis, saatFarki: saatFarki);

    return _KartCercevesi(
      dolu: true,
      renk: renk,
      dokun: dokun,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(m.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          if (m.adisyonlar.length > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              child: Text('${m.adisyonlar.length}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
            ),
        ]),
        const Spacer(),
        Text(para(kalan), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(
          a.hesapIstendi ? 'Hesap istendi · ${sureMetni(dk)}' : '${a.kalemSayisi} kalem · ${sureMetni(dk)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
        ),
      ]),
    );
  }
}

class _AdisyonKarti extends StatelessWidget {
  const _AdisyonKarti({required this.adisyon, required this.saatFarki, required this.dokun});
  final AdisyonOzet adisyon;
  final Duration saatFarki;
  final VoidCallback dokun;

  @override
  Widget build(BuildContext context) {
    final a = adisyon;
    final dk = gecenDakika(a.acilis, saatFarki: saatFarki);
    return _KartCercevesi(
      dolu: false,
      renk: Renk.yuzey,
      kenar: a.hesapIstendi ? Renk.uyari : null,
      dokun: dokun,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(a.baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (a.hesapIstendi) const Icon(Icons.receipt_long_rounded, size: 18, color: Renk.uyari),
        ]),
        Text(a.durumEtiket, style: const TextStyle(fontSize: 12, color: Renk.soluk)),
        const Spacer(),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Text('${a.kalemSayisi} kalem · ${sureMetni(dk)}', style: const TextStyle(fontSize: 12, color: Renk.soluk))),
          Text(para(a.kalan), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      ]),
    );
  }
}

class _SekmeDugmesi extends StatelessWidget {
  const _SekmeDugmesi({required this.etiket, required this.sayi, required this.secili, required this.bas});
  final String etiket;
  final int sayi;
  final bool secili;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: secili ? Renk.marka : Renk.zemin,
      borderRadius: koseYuvarlak,
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: bas,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Text(etiket, style: TextStyle(fontWeight: FontWeight.w700, color: secili ? Colors.white : Renk.yazi)),
            if (sayi > 0) ...[
              const SizedBox(width: 6),
              Text('$sayi', style: TextStyle(fontWeight: FontWeight.w800, color: secili ? Colors.white70 : Renk.marka)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _UyariKarti extends StatelessWidget {
  const _UyariKarti({required this.ikon, required this.renk, required this.metin, required this.dugme, required this.basildi});
  final IconData ikon;
  final Color renk;
  final String metin;
  final String dugme;
  final VoidCallback basildi;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .1),
        borderRadius: koseYuvarlak,
        border: Border.all(color: renk.withValues(alpha: .4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon, size: 18, color: renk),
        const SizedBox(width: 8),
        Text(metin, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        TextButton(onPressed: basildi, child: Text(dugme)),
      ]),
    );
  }
}
