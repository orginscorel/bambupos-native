import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/raporlar.dart';
import '../core/tema.dart';
import '../ortak/donem.dart';
import '../ortak/form.dart';
import '../ortak/ortak.dart';
import '../ortak/ust_serit.dart';
import 'kabuk.dart';
import 'rapor.dart';
import 'rapor_ozet.dart';

/// Hazır dönemler — web paneldeki (/panel/raporlar) sırayla aynı.
enum RaporDonemi { bugun, dun, yedi, buAy, gecenAy, ozel }

extension RaporDonemiX on RaporDonemi {
  String get ad => switch (this) {
        RaporDonemi.bugun => 'Bugün',
        RaporDonemi.dun => 'Dün',
        RaporDonemi.yedi => 'Son 7 gün',
        RaporDonemi.buAy => 'Bu ay',
        RaporDonemi.gecenAy => 'Geçen ay',
        RaporDonemi.ozel => 'Özel aralık',
      };

  /// "Bugün" işletmenin AÇIK İŞ GÜNÜDÜR (Uyg.isGunu); diğerleri ondan sayılır.
  Donem donem() {
    final g = Uyg.isGunu;
    return switch (this) {
      RaporDonemi.bugun => Donem.hazir(DonemTur.bugun),
      RaporDonemi.dun => Donem.hazir(DonemTur.dun),
      RaporDonemi.yedi => Donem.ozel(g.subtract(const Duration(days: 6)), g),
      RaporDonemi.buAy => Donem.hazir(DonemTur.ay),
      RaporDonemi.gecenAy => Donem.ozel(DateTime(g.year, g.month - 1, 1), DateTime(g.year, g.month, 0)),
      RaporDonemi.ozel => Donem.hazir(DonemTur.bugun),
    };
  }
}

/// RAPORLAR — web paneldeki düzen: başlık satırı = ad + dönem + (özel
/// aralıkta tarih kutuları + Filtrele) + "Rapor ▾" listesi. Sekme şeridi
/// yok; girer girmez Özet görünür. Seçilen rapor aynı yerde açılır.
class RaporlarEkrani extends StatefulWidget {
  const RaporlarEkrani({super.key});
  @override
  State<RaporlarEkrani> createState() => _RaporlarEkraniState();
}

class _RaporlarEkraniState extends State<RaporlarEkrani> {
  RaporDonemi _hazir = RaporDonemi.bugun;
  late Donem _donem = RaporDonemi.bugun.donem();

  /// Özel aralık taslağı: Filtrele'ye basılana kadar rapora gitmez (web gibi).
  late DateTime _tBas = Uyg.isGunu, _tSon = Uyg.isGunu;

  /// null = Özet.
  RaporTanim? _aktif;
  int _tazele = 0;

  void _hazirSec(RaporDonemi d) {
    setState(() {
      _hazir = d;
      if (d != RaporDonemi.ozel) {
        _donem = d.donem();
        _tBas = _donem.bas;
        _tSon = _donem.son;
      }
    });
  }

  void _filtrele() {
    if (_tBas.isAfter(_tSon)) return;
    setState(() => _donem = Donem.ozel(_tBas, _tSon));
  }

  Future<void> _raporSec() async {
    final secim = await altSayfaAc<Object>(context, (c) => _RaporListesi(aktif: _aktif));
    if (!mounted || secim == null) return;
    setState(() => _aktif = secim is RaporTanim ? secim : null);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final ad = _aktif?.baslik ?? 'Özet';
    return PaSayfa(
      baslik: 'Raporlar',
      alt: '$ad · ${Bicim.aralik(_donem.bas, _donem.son)}',
      sag: UstEylemler(profil: () => Kabuk.sekme.value = 3),
      altBosluk: 90,
      yenile: () async => setState(() => _tazele++),
      children: [
        // ═══ BAŞLIK SATIRI: dönem · rapor ═══
        Row(children: [
          Expanded(
            child: _AcilirKutu(
              ikon: Icons.calendar_month_rounded,
              etiket: 'Dönem',
              deger: _hazir.ad,
              anahtar: const Key('donem-kutusu'),
              onTap: () async {
                final d = await altSayfaAc<RaporDonemi>(
                  context,
                  (c) => AltSayfa(baslik: 'Dönem', ikon: Icons.calendar_month_rounded, children: [
                    for (final x in RaporDonemi.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SecimCipi(
                          yazi: x.ad,
                          alt: x == RaporDonemi.ozel ? 'İki tarih seçip Filtrele' : Bicim.aralik(x.donem().bas, x.donem().son),
                          secili: x == _hazir,
                          onTap: () => Navigator.of(c).pop(x),
                        ),
                      ),
                  ]),
                );
                if (d != null) _hazirSec(d);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AcilirKutu(
              ikon: Icons.bar_chart_rounded,
              etiket: 'Rapor',
              deger: ad,
              vurgulu: true,
              anahtar: const Key('rapor-kutusu'),
              onTap: _raporSec,
            ),
          ),
        ]),
        // Özel aralık: iki tarih kutusu + Filtrele (telefonda yalnız burada açılır)
        AnimatedSize(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
          curve: Hareket.giris,
          alignment: Alignment.topCenter,
          child: _hazir != RaporDonemi.ozel
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Expanded(child: _TarihKutusu(etiket: 'Başlangıç', gun: _tBas, sec: (g) => setState(() => _tBas = g))),
                    const SizedBox(width: 8),
                    Expanded(child: _TarihKutusu(etiket: 'Bitiş', gun: _tSon, sec: (g) => setState(() => _tSon = g))),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 112,
                      child: GradDugme(yukseklik: 48, parilti: false, onTap: _tBas.isAfter(_tSon) ? null : _filtrele, ikon: Icons.search_rounded, yazi: 'Filtrele'),
                    ),
                  ]),
                ),
        ),
        if (_hazir == RaporDonemi.ozel && _tBas.isAfter(_tSon))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Başlangıç, bitişten sonra olamaz.', style: TextStyle(color: r.eksi, fontSize: 12)),
          ),
        const SizedBox(height: 12),
        // ═══ RAPOR ═══
        AnimatedSwitcher(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
          transitionBuilder: asamaGecisi,
          layoutBuilder: (simdiki, oncekiler) => Stack(alignment: Alignment.topCenter, children: [...oncekiler, ?simdiki]),
          child: KeyedSubtree(
            key: ValueKey('${_aktif?.anahtar ?? 'ozet'}-$_tazele'),
            child: _aktif == null ? RaporOzeti(donem: _donem) : RaporEkrani(tanim: _aktif!, donem: _donem, gomulu: true),
          ),
        ),
      ],
    );
  }
}

/// Başlık satırındaki açılır kutu (web'deki select'in eşi): 8 px köşe, ▾ ok.
class _AcilirKutu extends StatelessWidget {
  const _AcilirKutu({required this.ikon, required this.etiket, required this.deger, required this.onTap, this.vurgulu = false, this.anahtar});
  final IconData ikon;
  final String etiket;
  final String deger;
  final VoidCallback onTap;
  final bool vurgulu;
  final Key? anahtar;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Basilir(
      key: anahtar,
      onTap: onTap,
      etiket: '$etiket: $deger. Değiştirmek için dokunun',
      olcek: .97,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: r.kart,
          borderRadius: Marka.yaricap,
          border: Border.all(color: vurgulu ? r.birincil : r.kenar, width: vurgulu ? 1.4 : 1),
        ),
        child: Row(children: [
          Icon(ikon, size: 18, color: r.birincil),
          const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(etiket, style: TextStyle(color: r.silik, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.1)),
              Text(deger, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
            ]),
          ),
          Icon(Icons.keyboard_arrow_down_rounded, color: r.soluk),
        ]),
      ),
    );
  }
}

class _TarihKutusu extends StatelessWidget {
  const _TarihKutusu({required this.etiket, required this.gun, required this.sec});
  final String etiket;
  final DateTime gun;
  final ValueChanged<DateTime> sec;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Basilir(
      onTap: () async {
        final g = await gunSec(context, gun, ilkGun: DateTime(Uyg.isGunu.year - 3), sonGun: Uyg.isGunu);
        if (g != null) sec(DateTime(g.year, g.month, g.day));
      },
      etiket: '$etiket: ${Bicim.gunAyYil(gun)}',
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: r.kenar)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiket, style: TextStyle(color: r.silik, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.1)),
          Text(Bicim.gunAyYil(gun), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
  }
}

/// "Rapor ▾" listesi: Özet + gruplu katalog (web'deki optgroup'lar gibi), aramalı.
class _RaporListesi extends StatefulWidget {
  const _RaporListesi({required this.aktif});
  final RaporTanim? aktif;
  @override
  State<_RaporListesi> createState() => _RaporListesiState();
}

class _RaporListesiState extends State<_RaporListesi> {
  String _ara = '';

  IconData _ikon(RaporTanim t) => switch (t.grafik) {
        GrafikTur.cizgi => Icons.show_chart_rounded,
        GrafikTur.sutun => Icons.bar_chart_rounded,
        GrafikTur.siraliSutun => Icons.leaderboard_rounded,
        GrafikTur.yok => Icons.table_rows_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final q = _ara.trim().toLowerCase();
    final liste = raporlar.where((t) => q.isEmpty || t.baslik.toLowerCase().contains(q) || (t.aciklama ?? '').toLowerCase().contains(q)).toList();
    Widget isaret(bool secili) => secili ? Icon(Icons.check_rounded, color: r.birincil) : Icon(Icons.chevron_right_rounded, color: r.silik);
    return AltSayfa(
      baslik: 'Rapor seçin',
      alt: 'Seçili dönemle aynı yerde açılır',
      ikon: Icons.bar_chart_rounded,
      children: [
        TextField(
          onChanged: (v) => setState(() => _ara = v),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Rapor ara', isDense: true),
        ),
        const SizedBox(height: 12),
        if (q.isEmpty || 'özet'.contains(q)) ...[
          _grupBasligi(context, 'Özet', Icons.dashboard_rounded),
          SatirGrubu([
            Satir(
              baslik: 'Özet',
              alt: 'Dönemin tamamı: rakamlar, kategori ve ödeme payı, borca yazılanlar',
              ikon: Icons.dashboard_rounded,
              sag: isaret(widget.aktif == null),
              onTap: () => Navigator.of(context).pop('ozet'),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        for (final g in RaporGrup.values)
          if (liste.any((t) => t.grup == g)) ...[
            _grupBasligi(context, g.ad, g.ikon),
            SatirGrubu([
              for (final t in liste.where((t) => t.grup == g))
                Satir(
                  baslik: t.baslik,
                  alt: t.aciklama,
                  ikon: _ikon(t),
                  sag: isaret(widget.aktif?.anahtar == t.anahtar),
                  onTap: () => Navigator.of(context).pop(t),
                ),
            ]),
            const SizedBox(height: 12),
          ],
        if (liste.isEmpty && !'özet'.contains(q)) const BosDurum(baslik: 'Rapor bulunamadı', ikon: Icons.search_off_rounded),
      ],
    );
  }

  Widget _grupBasligi(BuildContext context, String ad, IconData ikon) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Row(children: [
          Icon(ikon, size: 16, color: context.pa.birincil),
          const SizedBox(width: 6),
          Semantics(header: true, child: Text(ad.toUpperCase(), style: TextStyle(color: context.pa.soluk, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: .6))),
        ]),
      );
}
