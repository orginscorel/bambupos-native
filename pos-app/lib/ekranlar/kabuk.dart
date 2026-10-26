import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/modeller.dart';
import 'cerceve.dart';
import 'guncelleme.dart';
import 'kds_ekrani.dart';
import 'masa_panosu.dart';
import 'ortak.dart';

/// POS ekranları. Uygulama YALNIZ bunları içerir; işletme yönetimi,
/// raporlar, ayarlar web/konsolda kalır.
enum PosEkrani {
  siparis('Siparişler', 'Sipariş girişi ekranı', Icons.shopping_cart_outlined),
  kasa('Kasa', 'Kasa ekranı', Icons.point_of_sale_outlined),
  mutfak('Hazırlık', 'Hazırlık ekranı', Icons.soup_kitchen_outlined),
  komi('Servis', 'Servis ekranı', Icons.room_service_outlined);

  const PosEkrani(this.etiket, this.rozet, this.ikon);
  final String etiket;
  final String rozet;
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

        final rozet = switch (ekran) {
          PosEkrani.mutfak => '${o.istasyonEtiket} ekranı',
          _ => ekran.rozet,
        };

        return Scaffold(
          appBar: UstCubuk(
            baslik: o.isletme,
            altSatir: [o.sube ?? '', o.isletmeKod].where((s) => s.isNotEmpty).join(' · '),
            rozet: rozet,
            sag: [
              IconButton(
                tooltip: 'Ekranı kilitle (personel çıkışı)',
                onPressed: () => durum.kilitle(),
                icon: const Icon(Icons.lock_outline_rounded, color: Renk.hata),
              ),
            ],
          ),
          bottomNavigationBar: AltCubuk(
            ust: '${o.isletme} · ${o.cihazAd} · ${platformAdi()}',
            alt: o.operatorAd,
            rol: o.operatorRol,
            orta: [
              for (var i = 0; i < ekranlar.length; i++)
                AltDugme(
                  ikon: ekranlar[i].ikon,
                  etiket: ekranlar[i].etiket,
                  secili: ekranlar.length > 1 && i == _secili,
                  bas: () => setState(() => _secili = i),
                ),
            ],
          ),
          body: Column(children: [
            const GuncellemeSeridi(),
            Expanded(
              child: KeyedSubtree(
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
              ),
            ),
          ]),
        );
      },
    );
  }
}
