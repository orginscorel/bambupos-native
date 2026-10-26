import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/modeller.dart';
import 'guncelleme.dart';
import 'kds_ekrani.dart';
import 'masa_panosu.dart';
import 'ortak.dart';

/// POS ekranları. Uygulama YALNIZ bunları içerir; işletme yönetimi,
/// raporlar, ayarlar web/konsolda kalır.
enum PosEkrani {
  siparis('Masalar', Icons.table_restaurant_rounded),
  kasa('Kasa', Icons.point_of_sale_rounded),
  mutfak('Hazırlık', Icons.soup_kitchen_rounded),
  komi('Servis', Icons.room_service_rounded);

  const PosEkrani(this.etiket, this.ikon);
  final String etiket;
  final IconData ikon;
}

/// Cihaz → ilk (ana) ekran; kişi → ek ekranlar.
List<PosEkrani> ekranlariHesapla(Oturum o) {
  final ana = switch (o.istasyon) {
    'kasa' => PosEkrani.kasa,
    'kitchen' || 'barista' || 'nargile' => PosEkrani.mutfak,
    'komi' => PosEkrani.komi,
    _ => PosEkrani.siparis,
  };

  final izinli = <PosEkrani>[
    if (o.yetki('orders.view')) PosEkrani.siparis,
    if (o.yetki('payments.take') && o.paraGorur) PosEkrani.kasa,
    if (o.yetki('kds.view')) PosEkrani.mutfak,
    if (o.yetki('kds.deliver')) PosEkrani.komi,
  ];

  // Cihazın ekranı her zaman ilk sırada (yetki sunucuda ayrıca denetlenir).
  return [ana, ...izinli.where((e) => e != ana)];
}

class Kabuk extends StatefulWidget {
  const Kabuk({super.key});

  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> {
  int _secili = 0;

  @override
  Widget build(BuildContext context) {
    final durum = context.durum;

    return ListenableBuilder(
      listenable: durum,
      builder: (context, _) {
        final o = durum.oturum!;
        final ekranlar = ekranlariHesapla(o);
        if (_secili >= ekranlar.length) _secili = 0;
        final ekran = ekranlar[_secili];
        final genis = MediaQuery.sizeOf(context).width >= 900;
        final cokEkran = ekranlar.length > 1;

        final govde = KeyedSubtree(
          key: ValueKey(ekran),
          child: switch (ekran) {
            PosEkrani.siparis => const MasaPanosu(),
            PosEkrani.kasa => const MasaPanosu(kasaKipi: true),
            PosEkrani.mutfak => KdsEkrani(
                kip: 'kitchen',
                serit: const {'kitchen', 'barista', 'nargile'}.contains(o.istasyon) ? o.istasyon : null,
              ),
            PosEkrani.komi => const KdsEkrani(kip: 'runner'),
          },
        );

        return Scaffold(
          appBar: _UstCubuk(oturum: o, ekran: ekran),
          body: Column(children: [
            const GuncellemeSeridi(),
            Expanded(
              child: genis && cokEkran
                  ? Row(children: [
                      NavigationRail(
                        selectedIndex: _secili,
                        onDestinationSelected: (i) => setState(() => _secili = i),
                        labelType: NavigationRailLabelType.all,
                        backgroundColor: Renk.yuzey,
                        indicatorShape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                        destinations: [
                          for (final e in ekranlar)
                            NavigationRailDestination(icon: Icon(e.ikon), label: Text(e.etiket)),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: govde),
                    ])
                  : govde,
            ),
          ]),
          bottomNavigationBar: !genis && cokEkran
              ? NavigationBar(
                  height: 64,
                  selectedIndex: _secili,
                  onDestinationSelected: (i) => setState(() => _secili = i),
                  backgroundColor: Renk.yuzey,
                  indicatorShape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                  destinations: [
                    for (final e in ekranlar) NavigationDestination(icon: Icon(e.ikon), label: e.etiket),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class _UstCubuk extends StatelessWidget implements PreferredSizeWidget {
  const _UstCubuk({required this.oturum, required this.ekran});
  final Oturum oturum;
  final PosEkrani ekran;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final dar = MediaQuery.sizeOf(context).width < 560;

    return AppBar(
      titleSpacing: 12,
      shape: const Border(bottom: BorderSide(color: Renk.cizgi)),
      title: Row(children: [
        const Logo(boyut: 32),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(oturum.isletme, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(
              dar ? ekran.etiket : '${oturum.cihazAd} · ${ekran.etiket}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Renk.soluk, fontWeight: FontWeight.w500),
            ),
          ]),
        ),
      ]),
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: koseYuvarlak),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_rounded, size: 18, color: Renk.marka),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dar ? 90 : 180),
              child: Text(oturum.operatorAd,
                  overflow: TextOverflow.ellipsis, style: const TextStyle(color: Renk.marka, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Ekranı kilitle',
          onPressed: () => context.durum.kilitle(),
          icon: const Icon(Icons.lock_outline_rounded),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}
