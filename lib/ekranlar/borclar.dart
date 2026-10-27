import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/donem.dart';
import '../ortak/grafik.dart';
import '../ortak/ortak.dart';

/// BORCA YAZILANLAR: GET /api/v1/reports/borca-yazilanlar (range/from/to).
/// Dönemde borca yazılan (ciroda var, kasaya girmedi) kayıtlar + kişi özeti.
class BorclarEkrani extends StatefulWidget {
  const BorclarEkrani({super.key, this.donem});
  final Donem? donem;
  @override
  State<BorclarEkrani> createState() => _BorclarEkraniState();
}

class _BorclarEkraniState extends State<BorclarEkrani> {
  late Donem _donem = widget.donem ?? Donem.hazir(DonemTur.ay);
  Map<String, dynamic>? _veri;
  Object? _hata;
  int _istek = 0;
  bool _kisiye = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final no = ++_istek;
    setState(() => _hata = null);
    try {
      final r = await Uyg.api.get('/api/v1/reports/borca-yazilanlar', sorgu: _donem.raporSorgu);
      if (!mounted || no != _istek) return;
      setState(() => _veri = r is Map ? Map<String, dynamic>.from(r) : {});
    } on ApiHata catch (e) {
      if (!mounted || no != _istek) return;
      setState(() => _hata = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final v = _veri;
    final satir = v?.l('rows') ?? const [];
    final kisiler = v?.l('kisiler') ?? const [];
    return PaSayfa(
      baslik: 'Borca yazılanlar',
      alt: 'Ciroda var, kasaya girmedi',
      geri: true,
      yenile: _yukle,
      altBosluk: 40,
      children: [
        DonemSecici(
          secili: _donem,
          degisti: (d) {
            setState(() {
              _donem = d;
              _veri = null;
            });
            _yukle();
          },
        ),
        const SizedBox(height: 14),
        if (v == null && _hata != null)
          PaKart(
            child: _hata is ApiHata && (_hata as ApiHata).kod == 404
                ? const BosDurum(baslik: 'Borç / cari özelliği işletmenizde açık değil', ikon: Icons.extension_off_rounded)
                : HataDurum(hata: _hata!, yenile: _yukle),
          )
        else if (v == null)
          const Column(children: [Iskelet(yukseklik: 90), SizedBox(height: 12), Iskelet(yukseklik: 240)])
        else ...[
          Belirme(
            sira: 0,
            child: Row(children: [
              Expanded(child: _Kutu('Toplam', Bicim.para(v.i('total_minor'), tam: true))),
              const SizedBox(width: 10),
              Expanded(child: _Kutu('Kayıt', Bicim.sayi(v.i('count')))),
              const SizedBox(width: 10),
              Expanded(child: _Kutu('Kişi', Bicim.sayi(v.i('kisi')))),
            ]),
          ),
          const SizedBox(height: 14),
          if (satir.isEmpty)
            const PaKart(child: BosDurum(baslik: 'Bu dönemde borca yazılan yok', ikon: Icons.check_circle_outline_rounded))
          else ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), minimumSize: const Size(44, 44)),
              segments: const [ButtonSegment(value: false, label: Text('Kayıtlar')), ButtonSegment(value: true, label: Text('Kişiye göre'))],
              selected: {_kisiye},
              onSelectionChanged: (s) => setState(() => _kisiye = s.first),
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
              transitionBuilder: asamaGecisi,
              child: _kisiye
                  ? PaKart(
                      key: const ValueKey('k'),
                      child: Column(children: [
                        for (var i = 0; i < kisiler.length; i++)
                          CubukSatir(
                            sira: i + 1,
                            ad: kisiler[i].s('name'),
                            deger: Bicim.para(kisiler[i].i('amount_minor'), tam: true),
                            alt: '${kisiler[i].i('count')} kez · bakiye ${Bicim.paraKisa(kisiler[i].i('balance_minor'))}',
                            oran: kisiler[i].i('amount_minor') / (kisiler.first.i('amount_minor').clamp(1, 1 << 62)),
                            renk: Marka.kehribar,
                          ),
                      ]),
                    )
                  : Column(key: const ValueKey('s'), children: [
                      for (var i = 0; i < satir.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Belirme(
                            sira: i,
                            child: PaKart(
                              padding: const EdgeInsets.all(12),
                              etiket: '${satir[i].s('name')}, ${Bicim.para(satir[i].i('amount_minor'))}',
                              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Row(children: [
                                  Expanded(child: Text(satir[i].s('name'), style: TextStyle(fontWeight: FontWeight.w700, color: r.metin))),
                                  Text(Bicim.para(satir[i].i('amount_minor')), style: gosterim(15, renk: r.metin)),
                                ]),
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (DateTime.tryParse(satir[i].s('created_at')) != null) Bicim.tarihSaat(DateTime.parse(satir[i].s('created_at'))),
                                    satir[i].s('kaynak'),
                                    if (satir[i].s('performed_by').isNotEmpty) satir[i].s('performed_by'),
                                  ].where((e) => e.isNotEmpty).join(' · '),
                                  style: TextStyle(color: r.silik, fontSize: 12.5),
                                ),
                                if (satir[i].s('reason').isNotEmpty) Text(satir[i].s('reason'), style: TextStyle(color: r.soluk, fontSize: 12.5)),
                                Text('Güncel bakiye ${Bicim.para(satir[i].i('balance_minor'), tam: true)}', style: TextStyle(color: r.uyari, fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                    ]),
            ),
          ],
        ],
      ],
    );
  }
}

class _Kutu extends StatelessWidget {
  const _Kutu(this.ad, this.deger);
  final String ad;
  final String deger;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Semantics(
      container: true,
      label: '$ad: $deger',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ad, style: TextStyle(color: r.silik, fontSize: 12)),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(deger, style: gosterim(17, renk: r.metin))),
        ]),
      ),
    );
  }
}
