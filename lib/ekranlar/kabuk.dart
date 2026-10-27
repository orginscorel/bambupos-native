import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/bildirim.dart';
import '../core/guncelleme.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'ana_sayfa.dart';
import 'bildirimler.dart';
import 'davet.dart';
import 'destek.dart';
import 'gorevler.dart';
import 'hedefler.dart';
import 'mesaim.dart';
import 'primler.dart';
import 'profil.dart';
import 'qr_okut.dart';
import 'vardiyam.dart';

/// Oturum açıldı → kabuğa geç (geri dönüşsüz).
void kabugaGec(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 650),
      pageBuilder: (_, _, _) => const Kabuk(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
    (_) => false,
  );
}

/// Yeni sayfa aç (iOS tarzı kaydırmalı geçiş).
Future<T?> git<T>(BuildContext context, Widget sayfa) => Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => sayfa));

/// Web adresini (bildirim bağlantısı) uygulama ekranına çevirir.
void adreseGit(String url) {
  final ctx = Uyg.navigator.currentContext;
  if (ctx == null) return;
  final yol = Uri.tryParse(url)?.path ?? url;
  final sekme = switch (yol) {
    '/panelim' => 0,
    '/gorevlerim' => 1,
    '/takvim' => 2,
    '/profilim' => 3,
    _ => -1,
  };
  if (sekme >= 0) {
    Kabuk.sekme.value = sekme;
    return;
  }
  final Widget? s = switch (yol) {
    '/mesaim' => const MesaimEkrani(),
    '/hedeflerim' || '/raporlarim' => const HedeflerEkrani(),
    '/primlerim' => const PrimlerEkrani(),
    '/davet' => const DavetEkrani(),
    '/bildirimler' => const BildirimlerEkrani(),
    '/destek' => const DestekEkrani(),
    '/qr-okut' => const QrOkutEkrani(),
    _ => null,
  };
  if (s != null) git(ctx, s);
}

class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  static final sekme = ValueNotifier<int>(0);
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> {
  final _ziyaret = <int>{0};

  @override
  void initState() {
    super.initState();
    Kabuk.sekme.value = 0;
    BildirimMerkezi.acildi = adreseGit;
    BildirimMerkezi.basla();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) Guncelleme.bak(context);
      });
    });
  }

  @override
  void dispose() {
    BildirimMerkezi.durdur();
    super.dispose();
  }

  void _qr() {
    titret(1);
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const QrOkutEkrani(),
      transitionsBuilder: (_, a, _, child) {
        final e = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: e, child: ScaleTransition(scale: Tween(begin: .92, end: 1.0).animate(e), child: child));
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Kabuk.sekme,
      builder: (_, s, _) {
        _ziyaret.add(s);
        return Scaffold(
          extendBody: true,
          body: Stack(children: [
            for (var i = 0; i < 4; i++)
              Offstage(
                offstage: s != i,
                child: TickerMode(
                  enabled: s == i,
                  child: _ziyaret.contains(i)
                      ? AnimatedSwitcher(
                          duration: const Duration(milliseconds: 350),
                          child: KeyedSubtree(key: ValueKey(i), child: _sayfa(i)),
                        )
                      : const SizedBox(),
                ),
              ),
          ]),
          bottomNavigationBar: PaAltCubuk(secili: s, onSec: (i) => Kabuk.sekme.value = i, onQr: _qr),
        );
      },
    );
  }

  Widget _sayfa(int i) => switch (i) {
        0 => const AnaSayfa(),
        1 => const GorevlerEkrani(),
        2 => const VardiyamEkrani(),
        _ => const ProfilEkrani(),
      };
}

class PaAltCubuk extends StatelessWidget {
  const PaAltCubuk({super.key, required this.secili, required this.onSec, required this.onQr});
  final int secili;
  final ValueChanged<int> onSec;
  final VoidCallback onQr;

  static const _ogeler = [
    (Icons.home_rounded, 'Ana sayfa'),
    (Icons.assignment_turned_in_rounded, 'Görevler'),
    (null, 'QR Okut'),
    (Icons.calendar_month_rounded, 'Vardiyam'),
    (Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final alt = MediaQuery.paddingOf(context).bottom;
    // Görsel sıra: 0,1,[qr],2,3 → sekme indeksinden yuva indeksine.
    final yuva = secili < 2 ? secili : secili + 1;
    const yukseklik = 72.0;
    const yaricap = BorderRadius.all(Radius.circular(24));
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, (alt > 0 ? alt : 10) + 4),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SizedBox(
            height: yukseklik,
            // DÜZELTME (2026-10-27): seçili gösterge (AnimatedPositioned) eskiden
            // LayoutBuilder'ın İÇİNDEYDİ → Stack konumu yok sayıyordu, gösterge tüm
            // çubuğu lavanta-gri kaplıyordu. Artık LayoutBuilder dışta, Stack içte.
            child: LayoutBuilder(builder: (_, k) {
              final w = (k.maxWidth - 12) / 5;
              final hapW = (w - 14).clamp(40.0, 64.0);
              return Stack(clipBehavior: Clip.none, children: [
                // Gölge (cam katmanından ayrı: ClipRRect gölgeyi keserdi)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: yaricap,
                      boxShadow: r.koyu
                          ? const [BoxShadow(color: Color(0xCC000000), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -12)]
                          : const [
                              BoxShadow(color: Color(0x401C1863), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -10),
                              BoxShadow(color: Color(0x140F172A), blurRadius: 6, offset: Offset(0, 2)),
                            ],
                    ),
                  ),
                ),
                // Cam zemin: arkadaki içerik bulanıklaşır, yazılar net kalır
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: yaricap,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: r.kart.withValues(alpha: r.koyu ? .88 : .92),
                          borderRadius: yaricap,
                          border: Border.all(color: r.koyu ? const Color(0x33FFFFFF) : r.kenar),
                        ),
                      ),
                    ),
                  ),
                ),
                // Seçili sekme vurgusu — simgenin arkasında kayar
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: 6 + w * yuva + (w - hapW) / 2,
                  top: 9,
                  width: hapW,
                  height: 32,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Marka.morAcik.withValues(alpha: r.koyu ? .38 : .16),
                        Marka.mavi.withValues(alpha: r.koyu ? .30 : .12),
                      ]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(children: [
                    for (var i = 0; i < 5; i++)
                      Expanded(
                        child: i == 2
                            ? _QrDugme(onTap: onQr, yazi: _ogeler[2].$2)
                            : _Oge(
                                ikon: _ogeler[i].$1!,
                                yazi: _ogeler[i].$2,
                                aktif: i == yuva,
                                ev: i == 0,
                                onTap: () {
                                  titret();
                                  onSec(i < 2 ? i : i - 1);
                                },
                              ),
                      ),
                  ]),
                ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _Oge extends StatelessWidget {
  const _Oge({required this.ikon, required this.yazi, required this.aktif, required this.onTap, this.ev = false});
  final IconData ikon;
  final String yazi;
  final bool aktif;
  final bool ev;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final renk = aktif ? r.birincil : r.soluk;
    return Semantics(
      button: true,
      selected: aktif,
      label: yazi,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 13),
          child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
            AnimatedScale(
              scale: aktif ? 1.08 : 1,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutBack,
              child: ev
                  ? IconTheme(data: IconThemeData(color: renk), child: PaMark(boyut: 24, tek: !aktif))
                  : Icon(ikon, color: renk, size: 24),
            ),
            const SizedBox(height: 9),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 11,
                height: 1.1,
                fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
                color: renk,
              ),
              child: Text(yazi, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
            ),
          ]),
        ),
      ),
    );
  }
}

class _QrDugme extends StatefulWidget {
  const _QrDugme({required this.onTap, required this.yazi});
  final VoidCallback onTap;
  final String yazi;
  @override
  State<_QrDugme> createState() => _QrDugmeState();
}

class _QrDugmeState extends State<_QrDugme> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Semantics(
      button: true,
      label: widget.yazi,
      // Düğme çubuktan yukarı taşar; yazı diğer sekmelerin yazılarıyla aynı hizada (top 46).
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        Positioned(
          top: -24,
          child: Basilir(
            onTap: widget.onTap,
            olcek: .88,
            titresim: false,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) {
                    final t = Curves.easeOut.transform(_c.value);
                    return Opacity(
                      opacity: (1 - t) * .6,
                      child: Container(
                        width: 58 + 18 * t,
                        height: 58 + 18 * t,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20 + 5 * t), border: Border.all(color: Marka.mor, width: 2)),
                      ),
                    );
                  },
                ),
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: Marka.grad,
                    borderRadius: BorderRadius.circular(20),
                    // Cam zeminden ayrışsın: ince beyaz/koyu çerçeve
                    border: Border.all(color: r.koyu ? r.zemin : Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0xCC5443D2), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -8)],
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 27),
                ),
              ]),
            ),
          ),
        ),
        Positioned(
          top: 46,
          left: 0,
          right: 0,
          child: Text(widget.yazi,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: TextStyle(fontFamily: 'Poppins', fontSize: 11, height: 1.1, fontWeight: FontWeight.w700, color: r.metin)),
        ),
      ]),
    );
  }
}
