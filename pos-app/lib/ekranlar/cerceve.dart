import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/tema.dart';
import 'ortak.dart';

/// Web panelinin çerçevesi (PanelLayout): üstte marka + işletme künyesi +
/// ekran rozeti, altta cihaz/personel künyesi ve kısayollar. PIN, aktivasyon
/// ve iç ekranlar aynı çerçeveyi kullanır — web'de olduğu gibi.

String platformAdi() => switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      _ => 'Cihaz',
    };

/// Logo karesi + "BamBumPOS" yazısı (POS logo moru).
class MarkaIsareti extends StatelessWidget {
  const MarkaIsareti({super.key, this.yazi = true, this.boyut = 34});
  final bool yazi;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Logo(boyut: boyut),
      if (yazi) ...[
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'BamBum', style: TextStyle(color: Renk.yazi)),
            TextSpan(text: 'POS', style: TextStyle(color: Renk.logo.withValues(alpha: .92))),
          ]),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -.2),
        ),
      ],
    ]);
  }
}

class UstCubuk extends StatelessWidget implements PreferredSizeWidget {
  const UstCubuk({
    super.key,
    required this.baslik,
    this.altSatir,
    this.rozet,
    this.sol,
    this.orta,
    this.sag = const [],
  });

  final String baslik;
  final String? altSatir;
  final String? rozet;
  final Widget? sol;
  final Widget? orta;
  final List<Widget> sag;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final dar = g < 640;

    return Material(
      color: Renk.yuzey,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Renk.cizgi)),
            boxShadow: [BoxShadow(color: Color(0x0A1C1917), blurRadius: 3, offset: Offset(0, 1))],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            ?sol,
            MarkaIsareti(yazi: !dar),
            if (!dar || orta == null) ...[
              Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 14), color: Renk.cizgi),
              Flexible(
                flex: orta == null ? 1 : 0,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  if (altSatir != null && altSatir!.isNotEmpty)
                    Text(altSatir!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .5)),
                ]),
              ),
            ],
            if (rozet != null && g >= 900) ...[
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(6)),
                child: Text(rozet!.toUpperCase(),
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.ikinci, letterSpacing: .9)),
              ),
            ],
            if (orta != null) ...[const SizedBox(width: 14), Expanded(child: orta!)] else const Spacer(),
            ...sag,
          ]),
        ),
      ),
    );
  }
}

/// Alt çubuk: "İşletme · Cihaz · Platform" / "Personel  Rol" + kısayollar + sürüm.
class AltCubuk extends StatelessWidget {
  const AltCubuk({super.key, required this.ust, this.alt, this.rol, this.orta = const [], this.sag});
  final String ust;
  final String? alt;
  final String? rol;
  final List<Widget> orta;
  final Widget? sag;

  @override
  Widget build(BuildContext context) {
    final dar = MediaQuery.sizeOf(context).width < 640;
    final surum = context.durum.surum;

    return Material(
      color: Renk.yuzey,
      child: SafeArea(
        top: false,
        child: Container(
          height: 48,
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(children: [
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ust, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                if (alt != null || rol != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    if (alt != null)
                      Flexible(
                          child: Text(alt!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Renk.soluk))),
                    if (rol != null && rol!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(rol!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.ikinci)),
                    ],
                  ]),
              ]),
            ),
            if (orta.isNotEmpty) ...[
              Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 10), color: Renk.cizgi),
              ...orta,
            ],
            const Spacer(),
            ?sag,
            if (!dar) ...[
              const SizedBox(width: 12),
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'BamBum', style: TextStyle(color: Renk.ikinci)),
                    TextSpan(text: 'POS', style: TextStyle(color: Renk.logo.withValues(alpha: .9))),
                  ]),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                Text('v$surum', style: const TextStyle(fontSize: 10.5, color: Renk.soluk)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Alt çubuktaki kısayol düğmesi ("🛒 Siparişler").
class AltDugme extends StatelessWidget {
  const AltDugme({super.key, required this.ikon, required this.etiket, required this.bas, this.secili = false});
  final IconData ikon;
  final String etiket;
  final VoidCallback bas;
  final bool secili;

  @override
  Widget build(BuildContext context) {
    final dar = MediaQuery.sizeOf(context).width < 640;
    return InkWell(
      borderRadius: koseYuvarlak,
      onTap: bas,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: secili ? Renk.markaAcik : null,
          borderRadius: koseYuvarlak,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ikon, size: 20, color: secili ? Renk.marka : Renk.vurgu),
          if (!dar || secili) ...[
            const SizedBox(width: 7),
            Text(etiket, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: secili ? Renk.marka : Renk.yazi)),
          ],
        ]),
      ),
    );
  }
}
