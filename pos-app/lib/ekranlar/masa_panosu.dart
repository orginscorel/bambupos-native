import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import '../core/senkron_merkezi.dart';
import 'adisyon_ekrani.dart';
import 'birlestir_onay.dart';
import 'ortak.dart';

/// MASA PANOSU — web'deki /panel/siparisler (Board.vue) ile birebir:
///  • sekmeler: Boş Masalar · Açık Masalar · alanlar · Şahıslar · Paket & Kanal
///    ("Önce alanlar" ayarında: alanlar · Açık Masalar · Boş Masalar)
///  • alan başlığında "● n dolu ● n boş"
///  • masa kartı renkleri web'in durum sözlüğünden (MASA_KART/HAP/VURGU):
///      boş → yeşil · rezerve → mavi · dolu → kırmızı ·
///      30 dk'dır sipariş yok → turuncu · hesap istendi → marka mavisi
///  • sağ altta "x/y masa dolu · n şahıs" özeti
/// Veri `GET /api/v1/orders/board`; ekran açıkken 5 sn'de bir tazelenir,
/// son pano diskte tutulur (açılışta beklemeden çizilir).
class MasaPanosu extends StatefulWidget {
  const MasaPanosu({super.key, this.kasaKipi = false, this.birlestirKaynak});
  final bool kasaKipi;

  /// MASAYI BİRLEŞTİR MODU (1.2.36, web ile aynı — Kardo usulü): pano bu
  /// adisyon için açılır; üstte bilgi kutusu çıkar, karta dokunmak adisyona
  /// girmek yerine birleştirme onayını açar. Sayfa, açık kalan adisyonun
  /// id'siyle kapanır (vazgeçilirse null).
  final AdisyonOzet? birlestirKaynak;

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
  late String _sekme = widget.birlestirKaynak != null ? 'acik' : 'bos';
  /// "Önce alanlar" kipinde ekran ilk sekmeyle (ilk alan) açılır — bir kez.
  bool _ilkSekmeAyarlandi = false;
  Timer? _zamanlayici;
  bool _acilisYapiliyor = false;
  String? _sonHam;
  DateTime _sonCizim = DateTime.now();

  /* YARIŞ DÜZELTMESİ (2026-10-30, birleştirme sonrası "adisyon yok" bildirimi):
     Eskiden istek sürerken gelen _yenile() DÜŞÜYORDU — birleştirme/taşıma ya
     da adisyondan dönüşte istenen tazeleme, o an yolda olan ESKİ yoklamaya
     takılıyor; eski yanıt birleştirme öncesi panoyu basıyor, ekran 5 sn (ya
     da daha uzun) bayat kalıyordu. Artık:
       • istek sürerken gelen istek "bekleyen" olur, bitince bir kez daha çalışır;
       • _tazeIste() sıra numarasını artırır → yoldaki eski yanıt yok sayılır. */
  bool _bekleyen = false;
  int _istekNo = 0;
  StreamSubscription<SenkronDegisimi>? _senkronAbone;

  /// Ekran görünmezken (üstte adisyon açık) gelen haber: görünür olunca tazele.
  bool _kirli = false;

  @override
  void initState() {
    super.initState();
    _onbellektenAc();
    _yenile();
    _zamanlayici = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && context.yoklamaUygun) _yenile();
    });
    _senkronAbone = context.durum.senkron.degisimler.listen(_senkronHaberi);
  }

  @override
  void dispose() {
    _zamanlayici?.cancel();
    _senkronAbone?.cancel();
    super.dispose();
  }

  /// Başka cihazda / bu cihazda adisyon değişti → pano hemen tazelenir.
  void _senkronHaberi(SenkronDegisimi d) {
    if (!mounted) return;
    if (!context.yoklamaUygun) {
      _kirli = true;
      return;
    }
    _tazeIste();
  }

  /// Yoldaki yanıtı geçersiz sayıp yeni pano ister (sonuç ne olursa olsun
  /// en son durum ekrana gelir).
  void _tazeIste() {
    _istekNo++;
    _kirli = false;
    _yenile();
  }

  Future<void> _onbellektenAc() async {
    // 15 dk'dan eski pano gösterilmez (kapanmış/birleşmiş adisyon görünmesin);
    // birleştir/taşı/kapat sonrası dosya zaten silinir (durum._yazmaBasarili).
    final ham = await context.durum.onbellekOku('pano', enEski: const Duration(minutes: 15));
    if (ham != null && mounted && _pano == null) setState(() => _pano = Pano(ham));
  }

  Future<void> _yenile() async {
    if (!mounted) return;
    if (_yukleniyor) {
      _bekleyen = true;
      return;
    }
    _yukleniyor = true;
    _bekleyen = false;
    if (_kirli && context.yoklamaUygun) _kirli = false;
    final no = ++_istekNo;
    try {
      final veri = (await context.api.get('/api/v1/orders/board') as Map).cast<String, dynamic>();
      // Bu istek yoldayken daha yeni bir tazeleme istendiyse eski yanıt yazılmaz.
      if (!mounted || no != _istekNo) return;
      // Pano değişmediyse (5 sn'lik turların çoğu) diske yazılmaz; ızgara da
      // yalnız "… dk" süre yazıları ilerlesin diye 20 sn'de bir yeniden çizilir.
      final ham = jsonEncode(veri);
      final ayni = ham == _sonHam && _pano != null;
      if (ayni && !_baglantiYok && DateTime.now().difference(_sonCizim) < const Duration(seconds: 20)) return;
      _sonCizim = DateTime.now();
      setState(() {
        if (!ayni) _pano = Pano(veri);
        _baglantiYok = false;
      });
      if (!ayni) {
        _sonHam = ham;
        context.durum.onbellekYaz('pano', veri, hazirMetin: ham);
      }
    } on ApiHata catch (e) {
      if (mounted && no == _istekNo) setState(() => _baglantiYok = e.baglantiYok);
    } finally {
      _yukleniyor = false;
      // Yolda kalan istek yüzünden düşen tazeleme bir kez daha çalışır.
      if ((_bekleyen || no != _istekNo) && mounted) {
        _bekleyen = false;
        _yenile();
      }
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
    if (mounted) _tazeIste();
  }

  Future<void> _masayaDokun(Masa m) async {
    if (_acilisYapiliyor) return;
    if (_birlestirModu) return _birlestirMasaSec(m);
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

  /* ═════════════ Masayı birleştir modu (1.2.36) ═════════════ */

  bool get _birlestirModu => widget.birlestirKaynak != null;
  int get _kaynakId => widget.birlestirKaynak?.id ?? 0;

  String get _kaynakAdi {
    final k = widget.birlestirKaynak;
    if (k == null) return '';
    return k.masaAdi ?? k.cariAdi ?? 'Adisyon #${k.id}';
  }

  bool _kaynakMasaMi(Masa m) => m.adisyonlar.any((a) => a.id == _kaynakId) || tamSayi(m.bagli?['order_id']) == _kaynakId;

  Widget _birlestirKutusu() => Container(
        key: const ValueKey('birlestir-kutusu'),
        margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
        child: Column(children: [
          Text.rich(
            TextSpan(children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak),
                  child: Text(_kaynakAdi, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              const TextSpan(text: '  adisyonunu '),
              const TextSpan(text: 'birleştirmek', style: TextStyle(fontWeight: FontWeight.w800)),
              const TextSpan(text: ' istediğiniz masayı seçiniz'),
            ]),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Renk.yazi),
          ),
          const SizedBox(height: 4),
          Text('Açık masa seçerseniz adisyonlar birleşir; boş masa seçerseniz adisyon o masaya taşınır.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('İşlemden vazgeç')),
        ]),
      );

  Widget _birlestirEtiketi(Masa m) {
    final bu = _kaynakMasaMi(m);
    final acik = m.dolu || m.bagli != null;
    final (ikon, metin) = bu
        ? (Icons.check_rounded, 'Bu masa')
        : acik
            ? (Icons.merge_rounded, 'Masayı birleştir')
            : (Icons.arrow_forward_rounded, 'Buraya taşı');
    return Container(
      height: 30,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(ikon, size: 15, color: Renk.yazi),
        const SizedBox(width: 6),
        Text(metin, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Future<void> _birlestirMasaSec(Masa m) async {
    if (_kaynakMasaMi(m)) return;
    final dolu = m.adisyonlar;
    final bagli = m.bagli;
    if (dolu.isNotEmpty) {
      final h = dolu.firstWhere((a) => a.ham['is_split_child'] != true, orElse: () => dolu.first);
      return _birlestirOnayla(BirlestirSecim(tur: 'acik', ad: m.ad, masaId: m.id, hedefId: h.id, kalem: h.kalemSayisi, toplam: h.toplam));
    }
    if (bagli != null) {
      return _birlestirOnayla(BirlestirSecim(
          tur: 'acik',
          ad: '${bagli['table_name'] ?? m.ad}',
          masaId: m.id,
          hedefId: tamSayi(bagli['order_id']),
          kalem: tamSayi(bagli['items_count']),
          toplam: tamSayi(bagli['remaining_minor'])));
    }
    if (m.servisDisi) {
      context.bildir('${m.ad} servis dışı.');
      return;
    }
    return _birlestirOnayla(BirlestirSecim(tur: 'bos', ad: m.ad, masaId: m.id, hedefId: null, kalem: 0, toplam: 0));
  }

  Future<void> _birlestirCariSec(CariKart c) async {
    if (c.adisyonlar.isEmpty) {
      context.bildir('${c.ad} adına açık adisyon olmadığı için birleştirilemez.', hata: true);
      return;
    }
    final h = c.adisyonlar.first;
    if (h.id == _kaynakId) return;
    return _birlestirOnayla(BirlestirSecim(tur: 'acik', ad: c.ad, masaId: null, hedefId: h.id, kalem: h.kalemSayisi, toplam: h.toplam));
  }

  Future<void> _birlestirOnayla(BirlestirSecim secim) async {
    final k = widget.birlestirKaynak!;
    final yon = await birlestirOnayPenceresi(context, kaynakAdi: _kaynakAdi, kaynakKalem: k.kalemSayisi, kaynakToplam: k.toplam, secim: secim);
    if (yon == null || !mounted) return;
    final api = context.api;
    final gidilecek = await birlestirBekleme<int>(context, tasima: secim.tur == 'bos', is_: () async {
      if (secim.tur == 'bos') {
        await api.post('/api/v1/orders/${k.id}/move', {'table_id': secim.masaId});
        return k.id;
      }
      if (yon == 'aktar') {
        await api.post('/api/v1/orders/${secim.hedefId}/merge', {'source_order_id': k.id});
        return secim.hedefId!;
      }
      await api.post('/api/v1/orders/${k.id}/merge', {'source_order_id': secim.hedefId});
      return k.id;
    });
    if (gidilecek != null && mounted) Navigator.of(context).pop(gidilecek);
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

    // Sekme sırası işletme ayarıdır (web Board.vue ile aynı kural).
    final alanOnce = o.masaSekmeSirasi == 'alan_once';
    final durumSekmeleri = <(String, String, IconData, int)>[
      if (alanOnce) ...[
        ('acik', 'Açık Masalar', Icons.receipt_long_outlined, acikSayi),
        ('bos', 'Boş Masalar', Icons.restaurant_rounded, bosSayi),
      ] else ...[
        ('bos', 'Boş Masalar', Icons.restaurant_rounded, bosSayi),
        ('acik', 'Açık Masalar', Icons.receipt_long_outlined, acikSayi),
      ],
    ];

    final sekmeler = <(String, String, IconData, int)>[
      if (sekmeliKip && !alanOnce) ...durumSekmeleri,
      if (alanlar.length >= 2)
        for (final a in alanlar) ('alan:$a', a, Icons.restaurant_rounded, pano.masalar.where((m) => m.alan == a).length)
      else if (!sekmeliKip)
        ('all', 'Masalar', Icons.restaurant_rounded, pano.masalar.length),
      if (sekmeliKip && alanOnce) ...durumSekmeleri,
      if (o.eklenti('receivables', varsayilan: false) && pano.cariler.isNotEmpty) ('cari', 'Şahıslar', Icons.people_alt_outlined, pano.cariler.length),
      if (o.eklenti('delivery', varsayilan: false) || pano.kanalSiparisleri.isNotEmpty)
        ('kanal', 'Paket & Kanal', Icons.local_shipping_outlined, pano.kanalSiparisleri.length),
    ];
    if (alanOnce && !_ilkSekmeAyarlandi && !_birlestirModu) _sekme = sekmeler.first.$1;
    _ilkSekmeAyarlandi = true;
    if (!sekmeler.any((s) => s.$1 == _sekme)) _sekme = sekmeler.first.$1;

    return Stack(children: [
      Column(children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        if (_birlestirModu) _birlestirKutusu(),
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
          mainAxisExtent: (herhangiDolu ? 206 : 138) + (_birlestirModu ? 38 : 0),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: gorunen.length,
        itemBuilder: (_, i) => Belirme(sira: i, child: _masaKarti(gorunen[i])),
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
              if (_birlestirModu) _birlestirEtiketi(m),
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
                  itemBuilder: (_, i) => Belirme(sira: i, child: _KanalKarti(adisyon: l[i], fark: _fark, dokun: () => _adisyonuAc(l[i].id))),
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
            onTap: () => _birlestirModu
                ? _birlestirCariSec(c)
                : acik
                    ? _adisyonuAc(c.adisyonlar.first.id)
                    : _yeniAdisyon({'receivable_id': c.id}),
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
