import 'package:flutter/material.dart';

import '../core/bicim.dart';
import '../core/bildirim.dart';
import '../core/canli.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ekranlar/bildirimler.dart';
import '../app/hareket.dart';
import 'grafik.dart';
import 'ortak.dart';

/// Köşeli sayaç rozeti (hap DEĞİL: 5 px köşe). 0 ise çizilmez.
class Rozet extends StatelessWidget {
  const Rozet(this.sayi, {super.key, this.renk = Marka.gul, this.kenar});
  final int sayi;
  final Color renk;

  /// Rozetin arkasındaki yüzeyle arasına ince çerçeve (simge üstünde).
  final Color? kenar;
  @override
  Widget build(BuildContext context) {
    if (sayi <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: renk,
        borderRadius: BorderRadius.circular(5),
        border: kenar == null ? null : Border.all(color: kenar!, width: 1.5),
      ),
      child: Text(sayi > 99 ? '99+' : '$sayi',
          style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.1)),
    );
  }
}

/// Yuvarlak ikon düğmesi + köşede rozet (zil gibi).
class YuvarlakDugme extends StatelessWidget {
  const YuvarlakDugme({super.key, required this.ikon, required this.etiket, required this.onTap, this.rozet = 0, this.koyuZemin = false});
  final IconData ikon;
  final String etiket;
  final VoidCallback onTap;
  final int rozet;
  final bool koyuZemin;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Basilir(
      onTap: onTap,
      etiket: rozet > 0 ? '$etiket, $rozet yeni' : etiket,
      olcek: .9,
      child: SizedBox.square(
        dimension: 44,
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: koyuZemin ? Colors.white.withValues(alpha: .10) : r.kart,
              border: Border.all(color: koyuZemin ? Colors.white.withValues(alpha: .16) : r.kenar),
            ),
            child: Icon(ikon, size: 21, color: koyuZemin ? Colors.white : r.metin),
          ),
          Positioned(top: -1, right: -3, child: Rozet(rozet, kenar: koyuZemin ? Marka.gece2 : r.zemin)),
        ]),
      ),
    );
  }
}

/// Bildirim zili (okunmamış sayısıyla).
class ZilDugmesi extends StatelessWidget {
  const ZilDugmesi({super.key, this.koyuZemin = false});
  final bool koyuZemin;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: BildirimMerkezi.okunmamis,
        builder: (_, n, _) => YuvarlakDugme(
          ikon: n > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
          etiket: 'Bildirimler',
          rozet: n,
          koyuZemin: koyuZemin,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BildirimlerEkrani())),
        ),
      );
}

/// Kişinin baş harfli yuvarlak avatarı.
class Avatar extends StatelessWidget {
  const Avatar(this.ad, {super.key, this.boyut = 40, this.onTap, this.nokta});
  final String ad;
  final double boyut;
  final VoidCallback? onTap;

  /// Sağ altta durum noktası (mesaide = yeşil).
  final Color? nokta;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final daire = Stack(clipBehavior: Clip.none, children: [
      Container(
        width: boyut,
        height: boyut,
        alignment: Alignment.center,
        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: Marka.grad),
        child: Text(basHarf(ad), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: boyut * .36)),
      ),
      if (nokta != null)
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: boyut * .3,
            height: boyut * .3,
            decoration: BoxDecoration(color: nokta, shape: BoxShape.circle, border: Border.all(color: r.kart, width: 2)),
          ),
        ),
    ]);
    if (onTap == null) return ExcludeSemantics(child: daire);
    return Basilir(onTap: onTap, etiket: 'Hesap ve ayarlar', olcek: .9, child: SizedBox.square(dimension: 44, child: Center(child: daire)));
  }
}

/// Sekme başlığının sağındaki eylemler: zil + avatar (Daha fazla'ya gider).
class UstEylemler extends StatelessWidget {
  const UstEylemler({super.key, this.profil});
  final VoidCallback? profil;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const ZilDugmesi(),
        if (profil != null) ...[const SizedBox(width: 6), Avatar(Uyg.ad.isEmpty ? 'Patron' : Uyg.ad, onTap: profil)],
      ]);
}

/* ───────────────────────── Patron üst şeridi ───────────────────────── */

String selamla([DateTime? an]) {
  final saat = (an ?? DateTime.now()).hour;
  return saat < 6 ? 'İyi geceler' : saat < 12 ? 'Günaydın' : saat < 18 ? 'İyi günler' : 'İyi akşamlar';
}

/// ÖZET KAPAĞI (tam genişlik, durum çubuğunun altına kadar lacivert):
/// şube adı, selamlama + tarih, canlı göstergesi, bildirim zili, avatar;
/// büyük ciro sayacı + dönem çizgisi (kıyas kesikli) ve "şu an" kutuları
/// (açık masa · mesaide · adisyon — her zaman BUGÜN, [Canli.ozet]).
class OzetKapak extends StatelessWidget {
  const OzetKapak({
    super.key,
    required this.ciro,
    required this.donemAdi,
    this.degisim,
    this.altYazi,
    this.cizgi = const [],
    this.kiyas = const [],
    this.cizgiSon,
    this.cizgiEtiketleri = const ('', ''),
    this.onProfil,
    this.onEkip,
    this.yukleniyor = false,
  });
  final int? ciro;
  final String donemAdi;
  final double? degisim;
  final String? altYazi;
  final List<double> cizgi;
  final List<double> kiyas;
  final int? cizgiSon;
  final (String, String) cizgiEtiketleri;
  final VoidCallback? onProfil;
  final VoidCallback? onEkip;
  final bool yukleniyor;

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.paddingOf(context).top;
    final ad = Uyg.ilkAd;
    final simdi = DateTime.now();
    final beyaz70 = Colors.white.withValues(alpha: .72);
    return Container(
      padding: EdgeInsets.fromLTRB(16, ust + 10, 12, 18),
      decoration: const BoxDecoration(gradient: Marka.geceGrad),
      child: Stack(children: [
        // Köşede silik marka ızgarası (dekor; boya maliyeti yok denecek kadar az)
        Positioned(right: -20, top: 40, child: IgnorePointer(child: CustomPaint(size: const Size(180, 180), painter: _IzgaraDekor()))),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const PaMark(boyut: 38),
            const SizedBox(width: 12),
            Expanded(
              child: ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: Canli.meta,
                builder: (_, _, _) {
                  final sube = Canli.subeAdi;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((sube.isEmpty ? 'BamBumPOS Patron' : sube).toUpperCase(),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Marka.gok, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                    Semantics(
                      header: true,
                      child: Text(ad.isEmpty ? selamla(simdi) : '${selamla(simdi)}, $ad',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(20, renk: Colors.white)),
                    ),
                  ]);
                },
              ),
            ),
            const ZilDugmesi(koyuZemin: true),
            if (onProfil != null) ...[
              const SizedBox(width: 2),
              Basilir(
                onTap: onProfil,
                etiket: 'Hesap ve ayarlar',
                olcek: .9,
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Marka.gok, width: 2)),
                      child: Text(basHarf(Uyg.ad.isEmpty ? 'Patron' : Uyg.ad), style: const TextStyle(color: Marka.mor, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    ),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          ValueListenableBuilder<DateTime?>(
            valueListenable: Canli.sonGuncelleme,
            builder: (_, son, _) => Row(children: [
              Icon(Icons.calendar_today_rounded, size: 13, color: beyaz70),
              const SizedBox(width: 6),
              Flexible(
                child: Text('${Bicim.gunAdi(simdi)}, ${Bicim.gunAyYil(simdi)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: beyaz70, fontSize: 12.5)),
              ),
              const SizedBox(width: 10),
              _CanliNokta(aktif: son != null && !yukleniyor),
              const SizedBox(width: 5),
              Text(yukleniyor ? 'Güncelleniyor…' : son == null ? 'Bağlanıyor…' : 'Canlı · ${Bicim.saat(son)}',
                  style: TextStyle(color: beyaz70, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(height: 16),
          // Büyük ciro
          Row(children: [
            Text('CİRO · ${donemAdi.toUpperCase()}', style: TextStyle(color: Marka.gok.withValues(alpha: .95), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            const Spacer(),
            DegisimRozeti(degisim, koyuZemin: true),
          ]),
          const SizedBox(height: 4),
          if (ciro == null)
            Container(height: 44, width: 180, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: Marka.yaricap))
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SayacMetin(deger: ciro!, yaz: (n) => Bicim.para(n), stil: gosterim(38, renk: Colors.white)),
            ),
          if (altYazi != null) Text(altYazi!, style: TextStyle(color: beyaz70, fontSize: 12.5)),
          const SizedBox(height: 10),
          if (cizgi.length >= 2 || kiyas.length >= 2) ...[
            MiniCizgi(degerler: cizgi, kiyas: kiyas, son: cizgiSon, yukseklik: 60),
            const SizedBox(height: 4),
            Row(children: [
              Text(cizgiEtiketleri.$1, style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 10.5)),
              const Spacer(),
              if (kiyas.length >= 2) ...[
                Container(width: 10, height: 2, color: Colors.white.withValues(alpha: .45)),
                const SizedBox(width: 4),
                Text('kıyas', style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 10.5)),
                const SizedBox(width: 10),
              ],
              Text(cizgiEtiketleri.$2, style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 10.5)),
            ]),
            const SizedBox(height: 12),
          ],
          ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: Canli.ozet,
            builder: (_, v, _) {
              if (v == null) {
                return Row(children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: Container(height: 72, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .07), borderRadius: Marka.yaricap))),
                  ],
                ]);
              }
              final s = v.m('sales');
              final acik = v.m('open');
              final ms = v.l('on_shift');
              final planli = v.l('upcoming_today').length;
              return Row(children: [
                Expanded(
                  child: _CanliKutu(
                    ikon: Icons.table_restaurant_rounded,
                    ad: 'Açık masa',
                    deger: acik.i('open_tables'),
                    yaz: (n) => Bicim.sayi(n),
                    altYazi: Bicim.paraKisa(acik.i('open_amount_minor')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CanliKutu(
                    ikon: Icons.badge_rounded,
                    ad: 'Mesaide',
                    deger: ms.length,
                    yaz: (n) => '${Bicim.sayi(n)} kişi',
                    altYazi: planli > 0 ? '+$planli gelecek' : 'Ekibi gör ›',
                    onTap: onEkip,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CanliKutu(
                    ikon: Icons.receipt_long_rounded,
                    ad: 'Adisyon',
                    deger: s.i('orders'),
                    yaz: (n) => Bicim.sayi(n),
                    altYazi: 'ort. ${Bicim.paraKisa(s.i('avg_basket_minor'))}',
                  ),
                ),
              ]);
            },
          ),
        ]),
      ]),
    );
  }
}

/// Kapağın sağ üstünde silik QR-ızgara dekoru (markanın bulucu kareleri).
class _IzgaraDekor extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .05);
    const a = 18.0;
    for (var y = 0.0; y < s.height; y += a) {
      for (var x = 0.0; x < s.width; x += a) {
        if (((x + y) / a).round() % 3 == 0) c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, a - 5, a - 5), const Radius.circular(2)), p);
      }
    }
  }

  @override
  bool shouldRepaint(_IzgaraDekor o) => false;
}

class _CanliKutu extends StatelessWidget {
  const _CanliKutu({required this.ikon, required this.ad, required this.deger, required this.yaz, this.altYazi, this.onTap});
  final IconData ikon;
  final String ad;
  final num deger;
  final String Function(num) yaz;
  final String? altYazi;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final kutu = Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: Marka.yaricap,
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(ikon, size: 13, color: Marka.gok),
          const SizedBox(width: 4),
          Expanded(
            child: Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 11)),
          ),
        ]),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SayacMetin(deger: deger, yaz: yaz, stil: gosterim(17, renk: Colors.white)),
        ),
        const SizedBox(height: 2),
        Text(altYazi ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withValues(alpha: .62), fontSize: 10.5)),
      ]),
    );
    if (onTap == null) return Semantics(container: true, label: '$ad ${yaz(deger)}', excludeSemantics: true, child: kutu);
    return Basilir(onTap: onTap, etiket: '$ad ${yaz(deger)}', child: kutu);
  }
}

/// Canlı göstergesi: yeşil nokta; tazelemede kısa bir opaklık atımı.
class _CanliNokta extends StatelessWidget {
  const _CanliNokta({required this.aktif});
  final bool aktif;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: aktif ? 1 : .45,
        duration: Hareket.kapali(context) ? Duration.zero : Hareket.orta,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: aktif ? Marka.zumrutAcik : Marka.kehribarAcik),
        ),
      );
}
