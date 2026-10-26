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
          bottomNavigationBar: _AltCubuk(secili: s, onSec: (i) => Kabuk.sekme.value = i, onQr: _qr),
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

class _AltCubuk extends StatelessWidget {
  const _AltCubuk({required this.secili, required this.onSec, required this.onQr});
  final int secili;
  final ValueChanged<int> onSec;
  final VoidCallback onQr;

  static const _ogeler = [
    (Icons.home_rounded, 'Ana sayfa'),
    (Icons.assignment_turned_in_rounded, 'Görevler'),
    (null, 'Okut'),
    (Icons.calendar_month_rounded, 'Vardiyam'),
    (Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final alt = MediaQuery.paddingOf(context).bottom;
    // Görsel sıra: 0,1,[qr],2,3 → sekme indeksinden yuva indeksine.
    final yuva = secili < 2 ? secili : secili + 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, alt + 10),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SizedBox(
            height: 70,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: r.kart.withValues(alpha: .96),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: r.kenar),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: const [BoxShadow(color: Color(0x551C1863), blurRadius: 40, offset: Offset(0, 18), spreadRadius: -18)],
                  ),
                ),
              ),
              LayoutBuilder(builder: (_, k) {
                final w = (k.maxWidth - 16) / 5;
                return AnimatedPositioned(
                  duration: const Duration(milliseconds: 520),
                  curve: Curves.elasticOut,
                  left: 8 + w * yuva + 4,
                  top: 9,
                  width: w - 8,
                  height: 52,
                  child: Container(
                    decoration: BoxDecoration(color: r.birincilYumusak, borderRadius: BorderRadius.circular(17)),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 20,
                      height: 3.5,
                      margin: const EdgeInsets.only(bottom: 1),
                      decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x995443D2), blurRadius: 8)]),
                    ),
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  for (var i = 0; i < 5; i++)
                    Expanded(
                      child: i == 2
                          ? _QrDugme(onTap: onQr)
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
            ]),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        scale: aktif ? 1.06 : 1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.elasticOut,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (ev)
            IconTheme(data: IconThemeData(color: renk), child: PaMark(boyut: 24, tek: !aktif))
          else
            Icon(ikon, color: renk, size: 24),
          const SizedBox(height: 3),
          Text(yazi, maxLines: 1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: renk)),
        ]),
      ),
    );
  }
}

class _QrDugme extends StatefulWidget {
  const _QrDugme({required this.onTap});
  final VoidCallback onTap;
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
  Widget build(BuildContext context) => Center(
        child: Transform.translate(
          offset: const Offset(0, -18),
          child: Basilir(
            onTap: widget.onTap,
            olcek: .88,
            titresim: false,
            child: SizedBox(
              width: 66,
              height: 66,
              child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) {
                    final t = Curves.easeOut.transform(_c.value);
                    return Opacity(
                      opacity: (1 - t) * .7,
                      child: Container(
                        width: 60 + 18 * t,
                        height: 60 + 18 * t,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(21 + 5 * t), border: Border.all(color: Marka.mor, width: 2)),
                      ),
                    );
                  },
                ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: Marka.grad,
                    borderRadius: BorderRadius.circular(21),
                    boxShadow: const [BoxShadow(color: Color(0xCC5443D2), blurRadius: 26, offset: Offset(0, 12), spreadRadius: -8)],
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 30),
                ),
              ]),
            ),
          ),
        ),
      );
}
