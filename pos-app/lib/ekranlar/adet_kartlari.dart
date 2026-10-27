import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'ortak.dart';

/// Bir satırın tek adedi: saat · siparişi giren · devir/aktarım mı.
typedef BirimDokum = ({String? saat, String? kisi, bool devir});

/// Satırın adet adet dökümü: sunucunun `dokum` parçaları (saat · kişi ·
/// adet) tek tek adetlere açılır; döküm yoksa saat/kişi bilgisiz adetler.
List<BirimDokum> birimDokumu(Kalem k) {
  final d = (k.ham['dokum'] as List? ?? const []).whereType<Map>();
  final l = <BirimDokum>[
    for (final p in d)
      for (var j = 0; j < tamSayi(p['adet'], 1); j++) (saat: p['saat']?.toString(), kisi: p['kisi']?.toString(), devir: p['devir'] == true),
  ];
  if (l.length > k.adet) return l.sublist(0, k.adet);
  while (l.length < k.adet) {
    l.add((saat: null, kisi: null, devir: false));
  }
  return l;
}

/// ADET KARTLARI (web sipariş detayı gibi; Kasa ve Adisyon ortak): çok
/// adetli satır açılınca her adet ayrı kart —
///   [ ] 🕒 19:40 │ Çay / 👤 Muhammet Ali Yeni      30,00 ₺
/// İlk [odenmis] adet "Ödendi" görünür, seçilemez. Seçim [secili] adet
/// sıralarıdır; [degistir] null ise kutu çizilmez (yalnız döküm).
class AdetKartlari extends StatelessWidget {
  const AdetKartlari({
    super.key,
    required this.kalem,
    required this.secili,
    this.degistir,
    this.odenmis = 0,
    this.sik = false,
    this.anahtar = 'birim',
    this.solBosluk = 38,
  });

  final Kalem kalem;
  final Set<int> secili;
  final ValueChanged<int>? degistir;
  final int odenmis;

  /// Kısa masaüstü ekranı: ince kartlar, ürün + kişi tek satır.
  final bool sik;

  /// Kart anahtarı öneki: `<anahtar>-<kalem>-<sıra>` (testler için).
  final String anahtar;
  final double solBosluk;

  @override
  Widget build(BuildContext context) {
    final k = kalem;
    final dokum = birimDokumu(k);
    final dokumVar = (k.ham['dokum'] as List? ?? const []).isNotEmpty;
    final notVar = k.not != null && k.not!.trim().isNotEmpty;
    Widget kart(int i) {
      final b = dokum[i];
      final odendi = i < odenmis;
      final sec = !odendi && secili.contains(i);
      final kisi = b.kisi ?? (dokumVar && b.devir ? 'devir / aktarım' : '—');
      final bas = odendi || degistir == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              degistir!(i);
            };
      return Padding(
        padding: EdgeInsets.only(top: sik ? 4 : 6),
        child: Material(
          color: sec ? Renk.markaAcik.carp(.6) : (odendi ? Renk.ic : Renk.yuzey),
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: sec ? Renk.marka : Renk.cizgi)),
          child: InkWell(
            key: ValueKey('$anahtar-${k.id}-$i'),
            customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
            onTap: bas,
            child: Padding(
              padding: EdgeInsets.fromLTRB(degistir == null ? 10 : 4, sik ? 3 : 6, 12, sik ? 3 : 6),
              child: Row(children: [
                if (degistir != null || odendi) ...[
                  SizedBox(
                    width: 32,
                    child: odendi
                        ? Tooltip(message: 'Ödendi', child: Icon(Icons.check_circle_rounded, size: 20, color: Renk.basari))
                        : Center(
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: sec ? Renk.marka : Renk.yuzey,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: sec ? Renk.marka : Renk.cizgiKoyu, width: 1.5),
                              ),
                              child: sec ? Icon(Icons.check_rounded, size: 14, color: Renk.durumUstu) : null,
                            ),
                          ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(Icons.schedule_rounded, size: 15, color: Renk.ikinci),
                const SizedBox(width: 4),
                SizedBox(
                  width: 44,
                  child: Text(b.saat == null ? '—' : saatMetni(b.saat),
                      style: TextStyle(
                          fontSize: sik ? 13.5 : 14.5,
                          fontWeight: FontWeight.w800,
                          color: odendi ? Renk.soluk : Renk.yazi,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Container(width: 1, height: sik ? 22 : 32, margin: EdgeInsets.symmetric(horizontal: sik ? 8 : 10), color: Renk.cizgi),
                // Geniş yerde (sık düzen) ürün + kişi tek satır; dar yerde iki
                // satır: kişi adı kırpılmaz.
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  LayoutBuilder(
                    builder: (_, k2) => sik && k2.maxWidth >= 340
                        ? Row(children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: k2.maxWidth * .4),
                              child: UrunAdi(k.ad,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: odendi ? Renk.soluk : Renk.yazi)),
                            ),
                            const SizedBox(width: 10),
                            Icon(Icons.person_outline_rounded, size: 13, color: Renk.soluk),
                            const SizedBox(width: 3),
                            Expanded(child: Text(kisi, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.ikinci))),
                          ])
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            UrunAdi(k.ad,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: sik ? 13 : 13.5, fontWeight: FontWeight.w600, color: odendi ? Renk.soluk : Renk.yazi)),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.person_outline_rounded, size: 13, color: Renk.soluk)),
                              const SizedBox(width: 3),
                              // Dar kartta ad kırpılmasın: gerekirse iki satır.
                              Flexible(child: Text(kisi, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.25, color: Renk.ikinci))),
                            ]),
                          ]),
                  ),
                  if (notVar) KalemNotu(k.not!, boyut: 11.5, satir: 1),
                  ]),
                ),
                const SizedBox(width: 8),
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(para(k.birimFiyat),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        decoration: odendi || k.ikram ? TextDecoration.lineThrough : null,
                        decorationColor: Renk.soluk,
                        color: odendi || k.ikram ? Renk.soluk : Renk.yazi,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                  if (odendi) Text('Ödendi', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Renk.basari)),
                ]),
              ]),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(solBosluk, 0, 0, sik ? 4 : 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < k.adet; i++) kart(i)]),
    );
  }
}

/// Kalem notu (web: ürün adının altında not simgesi + "Not: …", soluk
/// italik). Mutfak/bar fişine de basılır; burada yalnız gösterilir.
class KalemNotu extends StatelessWidget {
  const KalemNotu(this.not, {super.key, this.boyut = 12, this.satir = 2});

  final String not;
  final double boyut;
  final int satir;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.sticky_note_2_outlined, size: boyut, color: Renk.soluk)),
          const SizedBox(width: 4),
          Flexible(
            child: Text('Not: $not',
                maxLines: satir,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: boyut, height: 1.3, fontStyle: FontStyle.italic, color: Renk.ikinci)),
          ),
        ]),
      );
}
