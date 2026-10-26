import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'ortak.dart';
import 'surum_notlari.dart';

/// WEB POS KABUĞU — resources/css/pos-kabuk.css + PosUst.vue + PanelSerit.vue
/// birebiri. Ölçüler tarayıcıdan okundu (2026-10-26, 390 / 820 / 1280 px):
///   üst çubuk 55 px, alt şerit ≥701 px'te tek satır 49 px, ≤700 px'te iki
///   kat (kısayol satırı + künye/simgeler); kısayol 36 px · köşe 10;
///   cihaz simgesi 36×36 (telefonda 32×32) · yeşil nokta 7 px.

/// Kabuğun kendi belirteçleri (pos-kabuk.css :root kapsamı).
abstract final class Kabuk {
  static bool get _k => koyuTema.value;
  static Color get ink => _k ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  static Color get brand => _k ? const Color(0xFF9B92FF) : const Color(0xFF5047CE);
  static Color get warning => _k ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  static Color get success => _k ? const Color(0xFF34D399) : const Color(0xFF15803D);
  static Color get info => _k ? const Color(0xFF22D3EE) : const Color(0xFF0891B2);
  static Color get soft => _k ? const Color(0xFF8A97AC) : const Color(0xFF64748B);
  static Color get line => _k ? const Color(0xFF26314A) : const Color(0xFFE5EAF1);
  static Color get sunken => _k ? const Color(0xFF1C2740) : const Color(0xFFF1F5F9);
  static Color get negative => _k ? const Color(0xFFF87171) : const Color(0xFFDC2626);

  /// Kabuk zemini (--surface): üst çubuk, açılır kutular.
  static Color get surface => _k ? const Color(0xFF0B1120) : const Color(0xFFFFFFFF);

  /// color-mix(in srgb, var(--surface) 92%, #64748b) → şerit zemini.
  static Color get serit => _k ? const Color(0xFF12192A) : const Color(0xFFF2F4F6);
}

String platformAdi() => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'Android',
  TargetPlatform.iOS => 'iOS',
  TargetPlatform.windows => 'Windows',
  TargetPlatform.macOS => 'macOS',
  TargetPlatform.linux => 'Linux',
  _ => 'Cihaz',
};

/// Web AppIcon adı → Material simgesi (şerit/çekmece/cihaz için).
IconData webSimge(String? ad) => switch (ad) {
  'orders' => Icons.content_paste_rounded,
  'cart' => Icons.shopping_cart_outlined,
  'history' => Icons.history_rounded,
  'qr-code' => Icons.qr_code_2_rounded,
  'wallet' => Icons.account_balance_wallet_outlined,
  'chef-hat' => Icons.soup_kitchen_outlined,
  'coffee' => Icons.coffee_outlined,
  'nargile' => Icons.local_fire_department_outlined,
  'bell' => Icons.notifications_none_rounded,
  'truck' => Icons.local_shipping_outlined,
  'inbox' => Icons.inbox_outlined,
  'receipt' => Icons.receipt_outlined,
  'clipboard' => Icons.assignment_outlined,
  'calendar' => Icons.calendar_today_outlined,
  'tablet' => Icons.tablet_android_outlined,
  'clock' => Icons.schedule_rounded,
  'printer' || 'yazici' => Icons.print_outlined,
  'terminal' => Icons.tablet_android_outlined,
  'mesaiqr' => Icons.qr_code_scanner_rounded,
  'monitor' => Icons.desktop_windows_outlined,
  'globe' => Icons.public_rounded,
  'users' => Icons.people_outline_rounded,
  _ => Icons.circle_outlined,
};

/// Kısayol simge rengi (pos-kabuk.css `.k[data-renk]`).
Color seritRengi(String? r) => switch (r) {
  'brand' || 'bilgi2' => Kabuk.brand,
  'info' => Kabuk.info,
  'uyari' => Kabuk.warning,
  'basari' => Kabuk.success,
  _ => Kabuk.ink,
};

/// Logo + "BamBum" + mor "POS" (pos-kabuk.css .pg-mrk: 16 px / 800).
class MarkaIsareti extends StatelessWidget {
  const MarkaIsareti({super.key, this.yazi = true, this.boyut = 30});
  final bool yazi;
  final double boyut;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Logo(boyut: boyut),
      ),
      if (yazi) ...[
        const SizedBox(width: 10),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'BamBum',
                style: TextStyle(color: Kabuk.ink),
              ),
              TextSpan(
                text: 'POS',
                style: TextStyle(color: Kabuk.brand),
              ),
            ],
          ),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -.3),
        ),
      ],
    ],
  );
}

/* ═══════════════════════ ÜST ÇUBUK (.pg-ust) ═══════════════════════ */

/// Başlık bloğu: arama kutusu yoksa kalan genişliği kaplar; varsa en çok
/// 320 px (arama kutusu Expanded'dır).
Widget _baslikAlani({required bool esnek, required Widget child}) =>
    esnek ? Expanded(child: child) : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: child);

class UstCubuk extends StatelessWidget implements PreferredSizeWidget {
  const UstCubuk({super.key, required this.baslik, this.altSatir, this.rozet, this.sol, this.orta, this.sag = const [], this.zil = false});

  final String baslik;
  final String? altSatir;
  final String? rozet;
  final Widget? sol;
  final Widget? orta;
  final List<Widget> sag;

  /// Bildirim zili (web: terminal ekranlarında var).
  final bool zil;

  @override
  Size get preferredSize => const Size.fromHeight(55);

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final telefon = g <= 700;

    return Material(
      color: Kabuk.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 55,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Kabuk.line)),
          ),
          child: Row(
            children: [
              ?sol,
              MarkaIsareti(yazi: !telefon),
              // Başlık + rozet tek esnek blokta: kalan boşluk SAĞA taşmaz,
              // zil ve tema düğmesi her genişlikte sağ uçta durur (web .pg-ust).
              _baslikAlani(
                esnek: orta == null,
                child: Row(
                  mainAxisSize: orta == null ? MainAxisSize.max : MainAxisSize.min,
                  children: [
                    if (!telefon && (orta == null || g >= 1100)) ...[
                      Container(width: 1, height: 30, margin: const EdgeInsets.only(left: 16, right: 14), color: Kabuk.line),
                      Flexible(
                        flex: 1,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              baslik,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Kabuk.ink),
                            ),
                            if (altSatir != null && altSatir!.isNotEmpty)
                              Text(
                                altSatir!.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Kabuk.soft, letterSpacing: .5),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (rozet != null && g >= 900) ...[
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          rozet!.toUpperCase(),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Kabuk.soft, letterSpacing: .9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (orta != null) ...[const SizedBox(width: 14), Expanded(child: orta!)],
              ...sag,
              if (zil) const BildirimZili(),
              const TemaDugmesi(),
              const KilitDugmesi(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Web bildirim zili: 20 sn'de bir /api/v1/notifications; açınca hepsi okundu.
class BildirimZili extends StatefulWidget {
  const BildirimZili({super.key});

  @override
  State<BildirimZili> createState() => _BildirimZiliState();
}

class _BildirimZiliState extends State<BildirimZili> {
  int _okunmamis = 0;
  List<Map<String, dynamic>> _liste = const [];
  Timer? _t;
  late final Api _api = context.api;

  @override
  void initState() {
    super.initState();
    _yukle();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => _yukle());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final r = (await _api.get('/api/v1/notifications') as Map);
      if (!mounted) return;
      setState(() {
        _okunmamis = tamSayi(r['unread_count']);
        _liste = (r['items'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      });
    } on ApiHata {
      // Zil sessizce bekler.
    }
  }

  Future<void> _ac(BuildContext context) async {
    if (_okunmamis > 0) {
      _api.post('/api/v1/notifications/read-all').then((_) => _yukle()).catchError((_) {});
      setState(() => _okunmamis = 0);
    }
    final kutu = context.findRenderObject() as RenderBox?;
    final konum = kutu?.localToGlobal(Offset.zero) ?? Offset.zero;
    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(konum.dx - 280, konum.dy + 44, 16, 0),
      constraints: const BoxConstraints(minWidth: 320, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(color: Kabuk.line),
      ),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          child: Row(
            children: [
              Text(
                'Bildirimler',
                style: TextStyle(fontWeight: FontWeight.w800, color: Kabuk.ink),
              ),
              const Spacer(),
              Text('${_liste.length} kayıt', style: TextStyle(fontSize: 12, color: Kabuk.soft)),
            ],
          ),
        ),
        if (_liste.isEmpty)
          PopupMenuItem<void>(
            enabled: false,
            child: Text('Bildirim yok.', style: TextStyle(color: Kabuk.soft)),
          )
        else
          for (final n in _liste.take(20))
            PopupMenuItem<void>(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${n['title'] ?? ''}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Kabuk.ink, fontSize: 13),
                  ),
                  if (n['body'] != null) Text('${n['body']}', style: TextStyle(fontSize: 12, color: Kabuk.soft)),
                  Text(saatMetni(n['created_at']?.toString()), style: TextStyle(fontSize: 11, color: Kabuk.soft)),
                ],
              ),
            ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Builder(
    builder: (ctx) => IconButton(
      tooltip: _okunmamis > 0 ? 'Bildirimler ($_okunmamis yeni)' : 'Bildirimler',
      onPressed: () => _ac(ctx),
      icon: Badge(
        isLabelVisible: _okunmamis > 0,
        label: Text(_okunmamis > 99 ? '99+' : '$_okunmamis'),
        child: Icon(Icons.notifications_none_rounded, color: Kabuk.soft, size: 20),
      ),
    ),
  );
}

/* ═══════════════════════ ALT ŞERİT (.pg-alt) ═══════════════════════ */

class SeritKisayol {
  const SeritKisayol({required this.ad, required this.kisa, required this.ikon, this.renk, required this.bas, this.secili = false});
  final String ad;
  final String kisa;
  final IconData ikon;
  final String? renk;
  final VoidCallback bas;
  final bool secili;
}

class SeritCihaz {
  const SeritCihaz({
    required this.ad,
    required this.ikon,
    required this.balon,
    this.durum = 'iyi',
    this.aciklama,
    this.ayrintilar = const [],
    this.eylem,
    this.dinle,
    this.canli,
  });
  final String ad;
  final IconData ikon;
  final String balon;

  /// iyi | uyari | kopuk
  final String durum;

  /// Dokununca açılan kutuda "ne işe yarar" metni.
  final String? aciklama;

  /// Kutuda başlık → değer satırları.
  final List<(String, String)> ayrintilar;

  /// Kutunun altındaki düğme (ör. "Şimdi tara", "Ekranı aç").
  final ({String ad, VoidCallback bas, bool kapat})? eylem;

  /// Canlı durum: değişince simge ve açık kutu yeniden çizilir.
  final Listenable? dinle;
  final SeritCihaz Function()? canli;

  SeritCihaz get guncel => canli?.call() ?? this;
}

class AltCubuk extends StatelessWidget {
  const AltCubuk({
    super.key,
    required this.isletme,
    this.cihaz,
    this.kisi,
    this.rol,
    this.kisiMenusu,
    this.kisayollar = const [],
    this.tumu,
    this.cihazlar = const [],
    this.sagMetin,
    this.surum,
  });

  final String isletme;
  final String? cihaz;
  final String? kisi;
  final String? rol;

  /// İsme dokununca yukarı açılan kişi menüsü.
  final Widget Function(BuildContext)? kisiMenusu;
  final List<SeritKisayol> kisayollar;
  final VoidCallback? tumu;
  final List<SeritCihaz> cihazlar;

  /// PIN ekranı gibi kısayolsuz şeritlerde sağdaki düz metin.
  final String? sagMetin;
  final String? surum;

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final telefon = g <= 700;

    final kim = _Kunye(isletme: isletme, cihaz: cihaz, kisi: kisi, rol: rol, kisiMenusu: kisiMenusu);
    final kisaSatir = Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final k in kisayollar) _KisayolDugmesi(k: k, g: g)],
    );
    final sag = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tumu != null) _TumuDugmesi(bas: tumu!),
        if (sagMetin != null) Text(sagMetin!, style: TextStyle(fontSize: 12.5, color: Kabuk.soft)),
        if (cihazlar.isNotEmpty || tumu != null) ...[
          const SizedBox(width: 6),
          for (final c in cihazlar) _CihazSimgesi(c: c, telefon: telefon),
        ],
        if (g > 1100 && surum != null) ...[
          const SizedBox(width: 8),
          // Web: sürüme dokununca sürüm notları açılır.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => surumNotlariAc(context),
            child: Tooltip(
              message: 'Sürüm notlarını aç',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'BamBum',
                          style: TextStyle(color: Kabuk.soft),
                        ),
                        TextSpan(
                          text: 'POS',
                          style: TextStyle(color: Kabuk.ink, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  Text('v$surum', style: TextStyle(fontSize: 11, color: Kabuk.soft)),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    return Material(
      color: Kabuk.serit,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Kabuk.line)),
          ),
          padding: EdgeInsets.symmetric(horizontal: g <= 560 ? 14 : 18),
          child: telefon
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kisayollar.isNotEmpty)
                      SizedBox(
                        height: 46,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: kisaSatir),
                        ),
                      ),
                    SizedBox(
                      height: kisayollar.isEmpty ? 49 : 52,
                      child: Row(
                        children: [
                          Expanded(child: kim),
                          sag,
                        ],
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  height: 49,
                  child: Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: g <= 860 ? g * .4 : g * .36),
                        child: kim,
                      ),
                      Expanded(
                        child: Center(
                          child: kisayollar.isEmpty
                              ? const SizedBox()
                              : Container(
                                  height: 49,
                                  padding: const EdgeInsets.symmetric(horizontal: 26),
                                  decoration: BoxDecoration(
                                    border: Border.symmetric(vertical: BorderSide(color: Kabuk.line)),
                                  ),
                                  child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: kisaSatir),
                                ),
                        ),
                      ),
                      sag,
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Kunye extends StatelessWidget {
  const _Kunye({required this.isletme, this.cihaz, this.kisi, this.rol, this.kisiMenusu});
  final String isletme;
  final String? cihaz;
  final String? kisi;
  final String? rol;
  final Widget Function(BuildContext)? kisiMenusu;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: isletme),
              if (cihaz != null && cihaz!.isNotEmpty)
                TextSpan(
                  text: ' · $cihaz',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Kabuk.soft),
                ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Kabuk.ink, height: 1.3),
        ),
        if (kisi != null)
          Builder(
            builder: (ctx) => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: kisiMenusu == null ? null : () => _kisiMenusuAc(ctx),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        kisi!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: Kabuk.soft),
                      ),
                    ),
                    if (rol != null && rol!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(7)),
                        child: Text(
                          rol!,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Kabuk.ink, height: 1.5),
                        ),
                      ),
                    ],
                    if (kisiMenusu != null)
                      Padding(
                        padding: EdgeInsets.only(left: 2),
                        child: Icon(Icons.keyboard_arrow_up_rounded, size: 15, color: Kabuk.soft),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Kişi menüsü: adın ÜSTÜNDE açılan kutu (.kmenu: köşe 13, gölge, 6 px iç boşluk).
  Future<void> _kisiMenusuAc(BuildContext ctx) async {
    final kutu = ctx.findRenderObject() as RenderBox;
    final konum = kutu.localToGlobal(Offset.zero);
    final g = MediaQuery.sizeOf(ctx).width;
    final genislik = g <= 700 ? 320.0 : (g <= 1024 ? 272.0 : 240.0);
    await showGeneralDialog<void>(
      context: ctx,
      barrierDismissible: true,
      barrierLabel: 'Kişi menüsü',
      barrierColor: Colors.transparent,
      pageBuilder: (dctx, _, _) => Stack(
        children: [
          Positioned(
            left: konum.dx,
            bottom: MediaQuery.sizeOf(dctx).height - konum.dy + 6,
            width: genislik.clamp(200, g - 24),
            child: Container(
              decoration: BoxDecoration(
                color: Kabuk.surface,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Kabuk.line),
                boxShadow: const [BoxShadow(color: Color(0x610F172A), blurRadius: 48, offset: Offset(0, 20), spreadRadius: -16)],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(padding: const EdgeInsets.all(6), child: kisiMenusu!(dctx)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kişi menüsünün içi (KisiMenuIc.vue): baş harf kutusu · ad + rol · işletme · şube
/// · "Personel değiştir". Terminalde ÇIKIŞ YOK (işletme kararı).
class KisiMenusuIci extends StatelessWidget {
  const KisiMenusuIci({super.key, required this.ad, this.rol, required this.alt, required this.personelDegistir});
  final String ad;
  final String? rol;
  final String alt;
  final VoidCallback personelDegistir;

  @override
  Widget build(BuildContext context) {
    final harf = ad.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(9)),
                child: Text(
                  harf.isEmpty ? '•' : harf,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Kabuk.ink),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: ad,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (rol != null && rol!.isNotEmpty)
                            TextSpan(
                              text: rol,
                              style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: Kabuk.ink),
                    ),
                    Text(
                      alt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Kabuk.soft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Kabuk.line),
        const SizedBox(height: 4),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Navigator.pop(context);
            personelDegistir();
          },
          child: SizedBox(
            height: 38,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(Icons.people_outline_rounded, size: 17, color: Kabuk.ink),
                  SizedBox(width: 10),
                  Text(
                    'Personel değiştir',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Kabuk.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KisayolDugmesi extends StatelessWidget {
  const _KisayolDugmesi({required this.k, required this.g});
  final SeritKisayol k;
  final double g;

  @override
  Widget build(BuildContext context) {
    // Web: >860 tam ad · 701–860 yalnız simge · ≤700 kısa ad.
    final etiket = g > 860 ? k.ad : (g <= 700 ? k.kisa : null);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: k.secili ? Kabuk.sunken : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: k.bas,
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: g <= 1024 ? 11 : 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(k.ikon, size: 21, color: seritRengi(k.renk)),
                if (etiket != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    etiket,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.ink),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TumuDugmesi extends StatelessWidget {
  const _TumuDugmesi({required this.bas});
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: bas,
    child: SizedBox(
      height: 36,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_vert_rounded, size: 18, color: Kabuk.ink),
            SizedBox(width: 6),
            Text(
              'Tümü',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.ink),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _durumRengi(String d) => switch (d) {
  'uyari' => Kabuk.warning,
  'kopuk' => Kabuk.negative,
  _ => Kabuk.success,
};

String _durumAdi(String d) => switch (d) {
  'uyari' => 'Dikkat',
  'kopuk' => 'Çalışmıyor',
  _ => 'Çalışıyor',
};

/// Alt şerit cihaz simgesi: durumuna göre yeşil / sarı / kırmızı yanar;
/// dokununca ne işe yaradığını ve şu anki durumunu anlatan kutu açılır.
class _CihazSimgesi extends StatelessWidget {
  const _CihazSimgesi({required this.c, required this.telefon});
  final SeritCihaz c;
  final bool telefon;

  @override
  Widget build(BuildContext context) {
    final d = c.dinle;
    if (d == null) return _ciz(context, c);
    return ListenableBuilder(listenable: d, builder: (ctx, _) => _ciz(ctx, c.guncel));
  }

  Widget _ciz(BuildContext context, SeritCihaz x) {
    final boyut = telefon ? 32.0 : 36.0;
    final renk = _durumRengi(x.durum);
    return Tooltip(
      message: '${x.ad} — ${x.balon}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => cihazAyrintiAc(context, c),
        child: SizedBox(
          width: boyut,
          height: boyut,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(x.ikon, size: telefon ? 17 : 18, color: renk),
              Positioned(
                right: telefon ? 5 : 6,
                bottom: telefon ? 5 : 6,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: renk,
                    shape: BoxShape.circle,
                    border: Border.all(color: Kabuk.serit, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cihaz simgesine dokununca şeridin üstünde, sağda açılan kutu
/// ("Tüm bölümler" kutusuyla aynı yer ve görünüm).
Future<void> cihazAyrintiAc(BuildContext context, SeritCihaz c) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: c.ad,
    barrierColor: const Color(0x730F172A),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) {
      final mq = MediaQuery.of(ctx);
      final dar = mq.size.width <= 640;
      final altBosluk = (mq.size.width <= 700 ? 104.0 : 49.0) + 7 + mq.padding.bottom;
      Widget govde(SeritCihaz x) {
        final renk = _durumRengi(x.durum);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 55,
              padding: const EdgeInsets.only(left: 14, right: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                    child: Icon(x.ikon, size: 18, color: renk),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      x.ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Kabuk.ink),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: renk, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(_durumAdi(x.durum), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: renk)),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, size: 18, color: Kabuk.soft),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(x.balon, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Kabuk.ink)),
                    if (x.aciklama != null) ...[
                      const SizedBox(height: 8),
                      Text(x.aciklama!, style: TextStyle(fontSize: 13, height: 1.45, color: Kabuk.soft)),
                    ],
                    if (x.ayrintilar.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Kabuk.line),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(children: [
                          for (var i = 0; i < x.ayrintilar.length; i++)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                border: i == 0 ? null : Border(top: BorderSide(color: Kabuk.line)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(x.ayrintilar[i].$1, style: TextStyle(fontSize: 12.5, color: Kabuk.soft)),
                                  ),
                                  const SizedBox(width: 10),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 170),
                                    child: Text(
                                      x.ayrintilar[i].$2,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Kabuk.ink),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ]),
                      ),
                    ],
                    if (x.eylem != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: () {
                          final e = x.eylem!;
                          if (e.kapat) Navigator.pop(ctx);
                          e.bas();
                        },
                        child: Text(x.eylem!.ad),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      }

      return Stack(
        children: [
          Positioned(
            right: dar ? 10 : 14,
            left: dar ? 10 : null,
            bottom: altBosluk,
            width: dar ? null : (mq.size.width * .92).clamp(0, 340).toDouble(),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: mq.size.height * (dar ? .72 : .66)),
              child: Material(
                color: Kabuk.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Kabuk.line),
                ),
                clipBehavior: Clip.antiAlias,
                elevation: 12,
                shadowColor: const Color(0x2E0F172A),
                child: c.dinle == null
                    ? govde(c)
                    : ListenableBuilder(listenable: c.dinle!, builder: (_, _) => govde(c.guncel)),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/* ═══════════════════════ "TÜMÜ" KUTUSU (.pg-cek) ═══════════════════════ */

class CekmeceOgesi {
  const CekmeceOgesi({required this.ad, required this.ikon, required this.bas, this.secili = false});
  final String ad;
  final IconData ikon;
  final VoidCallback bas;
  final bool secili;
}

/// Şeridin ÜSTÜNDE sağa yaslı kutu: genişlik min(320, %92), ≤640 px'te iki
/// yandan 10 px; köşe 14; başlık 55 px "Tüm bölümler"; satır 38 px; perde %45.
Future<void> tumBolumlerAc(BuildContext context, List<CekmeceOgesi> ogeler) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tüm bölümler',
    barrierColor: const Color(0x730F172A),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) {
      final mq = MediaQuery.of(ctx);
      final dar = mq.size.width <= 640;
      final altBosluk = (mq.size.width <= 700 ? 104.0 : 49.0) + 7 + mq.padding.bottom;
      return Stack(
        children: [
          Positioned(
            right: dar ? 10 : 14,
            left: dar ? 10 : null,
            bottom: altBosluk,
            width: dar ? null : (mq.size.width * .92).clamp(0, 320).toDouble(),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: mq.size.height * (dar ? .72 : .66)),
              child: Material(
                color: Kabuk.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Kabuk.line),
                ),
                clipBehavior: Clip.antiAlias,
                elevation: 12,
                shadowColor: const Color(0x2E0F172A),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 55,
                      padding: const EdgeInsets.only(left: 18, right: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Kabuk.line)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Tüm bölümler',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Kabuk.ink),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: Icon(Icons.close_rounded, size: 18, color: Kabuk.soft),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(12),
                        children: [
                          for (final o in ogeler)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Material(
                                color: o.secili ? Kabuk.sunken : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    o.bas();
                                  },
                                  child: SizedBox(
                                    height: 38,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Row(
                                        children: [
                                          Icon(o.ikon, size: 18, color: Kabuk.ink),
                                          const SizedBox(width: 10),
                                          Text(
                                            o.ad,
                                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.ink),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Web .pg-tema: 36×36, çerçevesiz, 8 px köşe; simge temayı söyler.
/// Web .pg-eylem.kilit: ekranı kilitler, PIN ekranına döner (cihaz eşli kalır).
/// Yalnız bir personel girişliyken çizilir.
class KilitDugmesi extends StatelessWidget {
  const KilitDugmesi({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.durum;
    if (d.oturum?.operatorVar != true) return const SizedBox.shrink();
    return Tooltip(
      message: 'Ekranı kilitle — geri dönmek için PIN gerekir',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: d.kilitle,
        child: SizedBox(width: 36, height: 36, child: Icon(Icons.lock_outline_rounded, size: 18, color: Kabuk.soft)),
      ),
    );
  }
}

class TemaDugmesi extends StatelessWidget {
  const TemaDugmesi({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
    message: koyuTema.value ? 'Açık temaya geç' : 'Koyu temaya geç',
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: temaDegistir,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(koyuTema.value ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 18, color: koyuTema.value ? Kabuk.ink : Kabuk.soft),
      ),
    ),
  );
}
