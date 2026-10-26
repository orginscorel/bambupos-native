import 'dart:async';

import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'adisyon_ekrani.dart';
import 'ortak.dart';

/// MASA PANOSU — web'deki /panel/siparisler (Board.vue) ile birebir:
///  • sekmeler: Boş Masalar · Açık Masalar · alanlar · Şahıslar · Paket & Kanal
///  • alan başlığında "● n dolu ● n boş"
///  • masa kartı renkleri web'in durum sözlüğünden (MASA_KART/HAP/VURGU):
///      boş → yeşil · rezerve → mavi · dolu → kırmızı ·
///      30 dk'dır sipariş yok → turuncu · hesap istendi → marka mavisi
///  • sağ altta "x/y masa dolu · n şahıs" özeti
/// Veri `GET /api/v1/orders/board`; ekran açıkken 5 sn'de bir tazelenir,
/// son pano diskte tutulur (açılışta beklemeden çizilir).
class MasaPanosu extends StatefulWidget {
  const MasaPanosu({super.key, this.kasaKipi = false});
  final bool kasaKipi;

  @override
  State<MasaPanosu> createState() => _MasaPanosuState();
}

enum _Durum { bos, rezerve, dolu, bekliyor, hesap }

/// Web'deki MASA_KART / MASA_HAP / MASA_VURGU sözlüğü.
({Color kenar, Color zemin, Color hap, Color vurgu, String etiket}) _renk(_Durum d) => switch (d) {
      _Durum.bos => (kenar: Renk.basari.withValues(alpha: .55), zemin: Renk.basariZemin, hap: Renk.basari, vurgu: Renk.basari, etiket: 'BOŞ'),
      _Durum.rezerve => (kenar: Renk.bilgi.withValues(alpha: .55), zemin: Renk.bilgiZemin, hap: Renk.bilgi, vurgu: Renk.bilgi, etiket: 'REZERVE'),
      _Durum.dolu => (kenar: Renk.hataKenar, zemin: Renk.hataZemin, hap: Renk.hata, vurgu: Renk.hata, etiket: 'AÇIK ADİSYON'),
      _Durum.bekliyor => (kenar: Renk.uyariKenar, zemin: Renk.uyariZemin, hap: Renk.uyari, vurgu: Renk.uyari, etiket: 'AÇIK ADİSYON'),
      _Durum.hesap => (kenar: Renk.marka.withValues(alpha: .55), zemin: Renk.markaAcik, hap: Renk.marka, vurgu: Renk.marka, etiket: 'HESAP İSTENDİ'),
    };

class _MasaPanosuState extends State<MasaPanosu> {
  Pano? _pano;
  bool _baglantiYok = false;
  bool _yukleniyor = false;
  String _sekme = 'bos';
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

  Duration get _fark => context.durum.oturum?.saatFarki ?? Duration.zero;

  /* ───────── Durum hesapları (web Board.vue ile aynı) ───────── */

  String? _sonSiparis(Masa m) {
    String? en;
    for (final a in m.adisyonlar) {
      final iso = a.acilis;
      if (iso != null && (en == null || iso.compareTo(en) > 0)) en = iso;
    }
    return en;
  }

  String? _acilis(Masa m) {
    String? en;
    for (final a in m.adisyonlar) {
      final iso = _metin(a.ham['created_at']) ?? a.acilis;
      if (iso != null && (en == null || iso.compareTo(en) < 0)) en = iso;
    }
    return en;
  }

  static String? _metin(Object? v) => v?.toString();

  bool _bayat(Masa m) {
    final son = _sonSiparis(m);
    return son != null && gecenDakika(son, saatFarki: _fark) > 30;
  }

  _Durum _durum(Masa m) {
    if (!m.dolu && m.bagli == null) return m.rezervasyon != null ? _Durum.rezerve : _Durum.bos;
    if (m.adisyonlar.any((a) => a.hesapIstendi)) return _Durum.hesap;
    if (_bayat(m)) return _Durum.bekliyor;
    return _Durum.dolu;
  }

  /* ───────── Eylemler ───────── */

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
              child: Text('${m.ad} · adisyonlar', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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

  /* ───────── Görünüm ───────── */

  @override
  Widget build(BuildContext context) {
    final pano = _pano;
    if (pano == null) {
      return Column(children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ]);
    }

    // Web viewTabs (pano.md §4): açık masa = adisyonu olan ya da birleşik masa.
    final o = context.durum.oturum!;
    final sekmeliKip = o.eklenti('adisyon_sekmeleri', varsayilan: false);
    final acikSayi = pano.masalar.where((m) => m.dolu || m.bagli != null).length;
    final bosSayi = pano.masalar.length - acikSayi;
    final cariAcik = pano.cariler.where((c) => c.adisyonlar.isNotEmpty).length;
    final alanlar = pano.alanlar;

    final sekmeler = <(String, String, IconData, int)>[
      if (sekmeliKip) ...[
        ('bos', 'Boş Masalar', Icons.restaurant_rounded, bosSayi),
        ('acik', 'Açık Masalar', Icons.receipt_long_outlined, acikSayi),
      ],
      if (alanlar.length >= 2)
        for (final a in alanlar) ('alan:$a', a, Icons.restaurant_rounded, pano.masalar.where((m) => m.alan == a).length)
      else if (!sekmeliKip)
        ('all', 'Masalar', Icons.restaurant_rounded, pano.masalar.length),
      if (o.eklenti('receivables', varsayilan: false) && pano.cariler.isNotEmpty) ('cari', 'Şahıslar', Icons.people_alt_outlined, pano.cariler.length),
      if (o.eklenti('delivery', varsayilan: false) || pano.kanalSiparisleri.isNotEmpty)
        ('kanal', 'Paket & Kanal', Icons.local_shipping_outlined, pano.kanalSiparisleri.length),
    ];
    if (!sekmeler.any((s) => s.$1 == _sekme)) _sekme = sekmeler.first.$1;

    return Stack(children: [
      Column(children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: _SekmeSeridi(
            sekmeler: sekmeler,
            secili: _sekme,
            bas: (k) => setState(() => _sekme = k),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _yenile,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 84),
              children: [
                if (pano.talepler.isNotEmpty || pano.onayBekleyen.isNotEmpty) _uyarilar(pano),
                ..._icerik(pano),
              ],
            ),
          ),
        ),
      ]),
      if (_acilisYapiliyor)
        const Positioned.fill(child: ColoredBox(color: Color(0x22000000), child: Center(child: CircularProgressIndicator()))),
      Positioned(
        right: 14,
        bottom: 14,
        child: _OzetCipi(dolu: acikSayi, toplam: pano.masalar.length, sahis: cariAcik),
      ),
    ]);
  }

  List<Widget> _icerik(Pano pano) {
    if (_sekme == 'cari') return [_cariler(pano.cariler)];
    if (_sekme == 'kanal') {
      if (pano.kanalSiparisleri.isNotEmpty) return [_kanalBolumu(pano.kanalSiparisleri)];
      return [
        const _BosDurum(
          ikon: Icons.local_shipping_outlined,
          baslik: 'Masa dışı sipariş yok',
          metin: 'Paket, gel-al ve kiosk siparişleri burada listelenir. Yeni sipariş için “Paket / Gel-Al / Kiosk” düğmesini kullanın.',
        ),
      ];
    }

    final alanlar = _sekme.startsWith('alan:') ? [_sekme.substring(5)] : pano.alanlar;
    final suz = switch (_sekme) {
      'bos' => (Masa m) => !m.dolu && m.bagli == null,
      'acik' => (Masa m) => m.dolu || m.bagli != null,
      _ => (Masa m) => true,
    };

    final w = <Widget>[];
    for (final a in alanlar) {
      final hepsi = pano.masalar.where((m) => m.alan == a).toList();
      final gorunen = hepsi.where(suz).toList();
      if (gorunen.isEmpty) continue;
      // Web gibi: sayaç o sekmede GÖRÜNEN masaları sayar.
      w.add(_AlanBasligi(ad: a, dolu: gorunen.where((m) => m.dolu).length, bos: gorunen.where((m) => !m.dolu).length));
      final herhangiDolu = gorunen.any((m) => m.dolu || m.bagli != null);
      w.add(GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 18),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 215,
          mainAxisExtent: herhangiDolu ? 206 : 138,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: gorunen.length,
        itemBuilder: (_, i) => _masaKarti(gorunen[i]),
      ));
    }
    if (w.isEmpty) {
      w.add(_sekme.startsWith('alan:')
          ? const _BosDurum(
              ikon: Icons.restaurant_rounded,
              baslik: 'Bu alanda masa yok',
              metin: 'Seçili alanda masa tanımlı değil. Tüm salonu görmek için “Tüm masalar”a geçin.',
            )
          : const _BosDurum(
              ikon: Icons.qr_code_2_rounded,
              baslik: 'Masa bulunamadı',
              metin: 'Masalar sayfasından masa ve alan (Bahçe, Oyun Alanı, Aile Alanı…) tanımlayabilirsiniz.',
            ));
    }
    // Web: masa sekmelerinin hepsinde, masaların altında kanal siparişleri.
    if (pano.kanalSiparisleri.isNotEmpty) w.add(_kanalBolumu(pano.kanalSiparisleri));
    return w;
  }

  Widget _uyarilar(Pano pano) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
            ikon: Icons.notifications_active_outlined,
            renk: Renk.uyari,
            metin: '${t.masa} · ${t.etiket}',
            dugme: 'Tamam',
            basildi: () => _talepTamam(t),
          ),
      ]),
    );
  }

  /* ── Masa kartı ── */

  Widget _masaKarti(Masa m) {
    final d = _durum(m);
    final r = _renk(d);
    final bagli = m.bagli;

    final ust = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: r.hap, borderRadius: BorderRadius.circular(999)),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: m.ad),
            if (m.numara != null)
              TextSpan(text: '  #${m.numara}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Renk.durumUstu.withValues(alpha: .7))),
          ]),
          style: TextStyle(color: Renk.durumUstu, fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      ),
      const SizedBox(height: 3),
      Text(bagli != null ? 'BİRLEŞİK' : r.etiket,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: r.vurgu, letterSpacing: .4)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text(m.alan, style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
        if (m.kapasite != null) ...[
          Text('  ·  ', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
          Icon(Icons.people_outline_rounded, size: 13, color: Renk.soluk),
          const SizedBox(width: 2),
          Text('${m.kapasite}', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
        ],
      ]),
    ]);

    final Widget alt;
    if (bagli != null) {
      alt = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.link_rounded, color: Renk.marka),
        const SizedBox(height: 4),
        Text('${bagli['table_name'] ?? ''} ile birleşik',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.marka)),
      ]);
    } else if (!m.dolu) {
      final rez = m.rezervasyon;
      alt = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (rez != null) ...[
          Text('${rez['time'] ?? ''} · ${rez['name'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.bilgi)),
          const SizedBox(height: 4),
        ],
        Icon(Icons.add_rounded, color: r.vurgu, size: 22),
        Text(m.servisDisi ? 'Servis dışı' : 'Adisyon aç', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.vurgu)),
      ]);
    } else {
      final kalan = m.adisyonlar.fold<int>(0, (t, a) => t + a.kalan);
      final kalem = m.adisyonlar.fold<int>(0, (t, a) => t + a.kalemSayisi);
      final servis = m.adisyonlar.fold<int>(0, (t, a) => t + a.servisEdilen);
      final kisi = m.adisyonlar.fold<int>(0, (t, a) => t + (a.kisi ?? 0));
      final acilis = _acilis(m);
      final son = _sonSiparis(m);
      final bayat = _bayat(m);
      alt = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Expanded(
              child: Column(children: [
                Text('Adisyon', style: TextStyle(fontSize: 11.5, color: Renk.ikinci)),
                Text(para(kalan), maxLines: 1, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: r.vurgu)),
              ]),
            ),
            Expanded(
              child: Column(children: [
                Text('Süre', style: TextStyle(fontSize: 11.5, color: Renk.ikinci)),
                Text(sureMetni(gecenDakika(acilis, saatFarki: _fark)),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: kalem == 0 ? 0 : servis / kalem,
              minHeight: 5,
              backgroundColor: Renk.yazi.withValues(alpha: .06),
              color: r.vurgu,
            ),
          ),
          const SizedBox(height: 6),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 11.5, color: Renk.ikinci),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.schedule_rounded, size: 13, color: Renk.soluk),
              const SizedBox(width: 3),
              Text(saatMetni(acilis)),
              const SizedBox(width: 9),
              Icon(Icons.restaurant_rounded, size: 13, color: Renk.soluk),
              const SizedBox(width: 3),
              Text('$servis/$kalem'),
              if (kisi > 0) ...[
                const SizedBox(width: 9),
                Icon(Icons.people_outline_rounded, size: 13, color: Renk.soluk),
                const SizedBox(width: 3),
                Text('$kisi'),
              ],
            ]),
          ),
          const SizedBox(height: 3),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.history_rounded, size: 13, color: bayat ? Renk.uyari : Renk.soluk),
            const SizedBox(width: 3),
            Text('Son ${sureMetni(gecenDakika(son, saatFarki: _fark))}',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: bayat ? Renk.uyari : Renk.ikinci)),
          ]),
          if (m.adisyonlar.first.acan != null) ...[
            const SizedBox(height: 3),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.person_outline_rounded, size: 13, color: Renk.soluk),
              const SizedBox(width: 3),
              Text('Açan: ', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
              Flexible(
                child: Text(m.adisyonlar.first.acan!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Renk.yazi)),
              ),
            ]),
          ],
        ]),
      );
    }

    return Opacity(
      opacity: m.servisDisi ? .5 : 1,
      child: Material(
        color: r.zemin,
        borderRadius: kartYuvarlak,
        child: InkWell(
          borderRadius: kartYuvarlak,
          onTap: () => _masayaDokun(m),
          child: Container(
            decoration: BoxDecoration(borderRadius: kartYuvarlak, border: Border.all(color: r.kenar)),
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(8, 10, 8, 8), child: ust),
              Divider(height: 1, color: r.kenar.withValues(alpha: .6)),
              Expanded(child: alt),
            ]),
          ),
        ),
      ),
    );
  }

  /* ── Paket / Gel-Al / Kiosk ── */

  Widget _kanalBolumu(List<AdisyonOzet> l) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: kartYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            Icon(Icons.inventory_2_outlined, size: 18, color: Renk.marka),
            const SizedBox(width: 8),
            const Text('Paket / Gel-Al / Kiosk siparişleri', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            _Sayac(l.length),
            const Spacer(),
            if (!widget.kasaKipi && context.durum.oturum!.yetki('orders.create'))
              TextButton.icon(
                onPressed: () => _yeniAdisyon({'channel': 'pickup', 'service_type': 'takeaway'}),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Gel-al satış'),
              ),
          ]),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(10),
          child: l.isEmpty
              ? Padding(padding: EdgeInsets.all(18), child: Center(child: Text('Paket sipariş yok.', style: TextStyle(color: Renk.soluk))))
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 420, mainAxisExtent: 128, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: l.length,
                  itemBuilder: (_, i) => _KanalKarti(adisyon: l[i], fark: _fark, dokun: () => _adisyonuAc(l[i].id)),
                ),
        ),
      ]),
    );
  }

  Widget _cariler(List<CariKart> l) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260, mainAxisExtent: 118, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: l.length,
      itemBuilder: (_, i) {
        final c = l[i];
        final acik = c.adisyonlar.isNotEmpty;
        final r = _renk(acik ? _Durum.dolu : _Durum.bos);
        return Material(
          color: r.zemin,
          borderRadius: kartYuvarlak,
          child: InkWell(
            borderRadius: kartYuvarlak,
            onTap: () => acik ? _adisyonuAc(c.adisyonlar.first.id) : _yeniAdisyon({'receivable_id': c.id}),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(borderRadius: kartYuvarlak, border: Border.all(color: r.kenar)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.person_outline_rounded, size: 18, color: r.vurgu),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(c.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const Spacer(),
                if (acik)
                  Text(para(c.adisyonlar.first.kalan), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: r.vurgu))
                else
                  Text('Adisyon aç', style: TextStyle(fontWeight: FontWeight.w700, color: r.vurgu)),
                if (c.borc > 0) Text('Borç: ${para(c.borc)}', style: TextStyle(fontSize: 12, color: Renk.hata, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/* ───────── Bileşenler ───────── */

class _SekmeSeridi extends StatelessWidget {
  const _SekmeSeridi({required this.sekmeler, required this.secili, required this.bas});
  final List<(String, String, IconData, int)> sekmeler;
  final String secili;
  final ValueChanged<String> bas;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, k) {
      // Web'de sekmeler eşit genişlikte; sığmazsa yatay kayar.
      final esit = k.maxWidth / sekmeler.length >= 150;
      final ogeler = [
        for (final (anahtar, etiket, ikon, sayi) in sekmeler)
          _Sekme(etiket: etiket, ikon: ikon, sayi: sayi, secili: anahtar == secili, bas: () => bas(anahtar), esnek: esit),
      ];
      return Container(
        height: 42,
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: esit
            ? Row(children: ogeler)
            : ListView(scrollDirection: Axis.horizontal, children: ogeler),
      );
    });
  }
}

class _Sekme extends StatelessWidget {
  const _Sekme({required this.etiket, required this.ikon, required this.sayi, required this.secili, required this.bas, required this.esnek});
  final String etiket;
  final IconData ikon;
  final int sayi;
  final bool secili;
  final VoidCallback bas;
  final bool esnek;

  @override
  Widget build(BuildContext context) {
    final icerik = InkWell(
      onTap: bas,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: secili ? Renk.ic : null,
          border: Border(
            bottom: BorderSide(color: secili ? const Color(0xFF1F53C5) : Colors.transparent, width: 2),
            right: BorderSide(color: Renk.cizgi),
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 16, color: secili ? Renk.marka : Renk.ikinci),
          const SizedBox(width: 6),
          Flexible(
            child: Text(etiket,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: secili ? Renk.marka : Renk.yazi)),
          ),
          const SizedBox(width: 6),
          _Sayac(sayi, dolu: secili),
        ]),
      ),
    );
    return esnek ? Expanded(child: icerik) : icerik;
  }
}

class _Sayac extends StatelessWidget {
  const _Sayac(this.sayi, {this.dolu = false});
  final int sayi;
  final bool dolu;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: dolu ? Renk.marka : Renk.ic, borderRadius: BorderRadius.circular(5)),
        child: Text('$sayi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: dolu ? Colors.white : Renk.ikinci)),
      );
}

class _AlanBasligi extends StatelessWidget {
  const _AlanBasligi({required this.ad, required this.dolu, required this.bos});
  final String ad;
  final int dolu;
  final int bos;

  @override
  Widget build(BuildContext context) {
    Widget nokta(Color c, String m) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(m, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
        ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.restaurant_rounded, size: 16, color: Renk.marka),
        ),
        const SizedBox(width: 10),
        Text(ad, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const Spacer(),
        nokta(Renk.hata, '$dolu dolu'),
        const SizedBox(width: 10),
        nokta(Renk.basari, '$bos boş'),
      ]),
    );
  }
}

class _KanalKarti extends StatelessWidget {
  const _KanalKarti({required this.adisyon, required this.fark, required this.dokun});
  final AdisyonOzet adisyon;
  final Duration fark;
  final VoidCallback dokun;

  @override
  Widget build(BuildContext context) {
    final a = adisyon;
    final (odemeRenk, odemeIkon) = switch (a.odemeDurumu) {
      'paid' => (Renk.basari, Icons.check_circle_outline_rounded),
      'partial' => (Renk.uyari, Icons.timelapse_rounded),
      _ => (Renk.soluk, Icons.shopping_cart_outlined),
    };
    return Material(
      color: Renk.yuzey,
      borderRadius: kartYuvarlak,
      child: InkWell(
        borderRadius: kartYuvarlak,
        onTap: dokun,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(borderRadius: kartYuvarlak, border: Border.all(color: Renk.cizgi), boxShadow: kartGolge),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (a.kaynakEtiket.isNotEmpty)
                Rozet(a.kaynakEtiket, renk: Renk.bilgi, zemin: Renk.bilgiZemin, kenar: Renk.bilgiKenar, ikon: Icons.people_outline_rounded),
              const SizedBox(width: 6),
              if (a.servisTuruEtiket.isNotEmpty)
                Rozet(a.servisTuruEtiket, renk: Renk.uyari, zemin: Renk.uyariZemin, kenar: Renk.uyariKenar, ikon: Icons.shopping_cart_outlined),
              const Spacer(),
              Text('#${a.id}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.soluk)),
            ]),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('${a.kalemSayisi} kalem  ·  ${sureMetni(gecenDakika(a.acilis, saatFarki: fark))}',
                      style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
                ]),
              ),
              Text(para(a.toplam), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            const Divider(),
            const SizedBox(height: 6),
            Row(children: [
              Rozet(a.durumEtiket, renk: Renk.bilgi, zemin: Renk.bilgiZemin, kenar: Renk.bilgiKenar, ikon: Icons.arrow_forward_rounded),
              const SizedBox(width: 6),
              Rozet(a.odemeEtiket, renk: odemeRenk, ikon: odemeIkon),
              const Spacer(),
              Text('${a.servisEdilen}/${a.kalemSayisi} servis', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _OzetCipi extends StatelessWidget {
  const _OzetCipi({required this.dolu, required this.toplam, required this.sahis});
  final int dolu;
  final int toplam;
  final int sahis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.qr_code_2_rounded, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Text('$dolu/$toplam', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(width: 6),
        const Text('masa dolu', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
        if (sahis > 0) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(6)),
            child: Text('$sahis şahıs', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
          ),
        ],
      ]),
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
        color: renk.withValues(alpha: .08),
        borderRadius: koseYuvarlak,
        border: Border.all(color: renk.withValues(alpha: .35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon, size: 18, color: renk),
        const SizedBox(width: 8),
        Text(metin, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(width: 8),
        TextButton(onPressed: basildi, child: Text(dugme)),
      ]),
    );
  }
}

class _BosDurum extends StatelessWidget {
  const _BosDurum({required this.ikon, required this.baslik, required this.metin});
  final IconData ikon;
  final String baslik;
  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Column(children: [
          Icon(ikon, size: 32, color: Renk.soluk),
          const SizedBox(height: 8),
          Text(baslik, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(metin, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
        ]),
      );
}
