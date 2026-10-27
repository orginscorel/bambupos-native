import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/bildirim.dart';
import '../core/durum.dart';
import '../core/guncelleme.dart';
import '../core/tema.dart';
import 'daha_fazla.dart';
import 'ekip.dart';
import 'ozet.dart';
import 'raporlar.dart';

/// Eşleme tamam → kabuğa geç (geri dönüşsüz).
void kabugaGec(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      transitionDuration: Hareket.kapali(context) ? Duration.zero : const Duration(milliseconds: 600),
      pageBuilder: (_, _, _) => const Kabuk(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ),
    (_) => false,
  );
}

/// Yeni sayfa aç (tema geçişiyle: PosSayfaGecisi / iOS'ta Cupertino).
Future<T?> git<T>(BuildContext context, Widget sayfa) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => sayfa));

class Kabuk extends StatefulWidget {
  const Kabuk({super.key});
  static final sekme = ValueNotifier<int>(0);
  @override
  State<Kabuk> createState() => _KabukState();
}

class _KabukState extends State<Kabuk> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _ziyaret = <int>{0};
  int _onceki = 0;

  /// Sekme değişiminde yeni sekme kısa bir kaymayla belirir (EkranGecisi'nin
  /// durum KORUYAN eşi: sekmeler Offstage'de yaşamaya devam eder).
  late final _gecis = AnimationController(vsync: this, duration: Hareket.orta, value: 1);

  @override
  void initState() {
    super.initState();
    Uyg.oturumlu = true;
    Kabuk.sekme.value = 0;
    Kabuk.sekme.addListener(_sekmeDegisti);
    BildirimMerkezi.basla();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) Guncelleme.bak();
      });
    });
  }

  void _sekmeDegisti() {
    if (!mounted) return;
    if (Hareket.kapali(context)) {
      _gecis.value = 1;
    } else {
      _gecis.forward(from: 0);
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      Guncelleme.bak();
      BildirimMerkezi.yokla();
      OzetEkrani.tazele.value++;
    }
  }

  @override
  void dispose() {
    Kabuk.sekme.removeListener(_sekmeDegisti);
    WidgetsBinding.instance.removeObserver(this);
    BildirimMerkezi.durdur();
    _gecis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Kabuk.sekme.value;
    _ziyaret.add(s);
    final yon = s >= _onceki ? 1 : -1;
    _onceki = s;
    final e = CurvedAnimation(parent: _gecis, curve: Hareket.giris);
    return Scaffold(
      body: Stack(children: [
        for (var i = 0; i < 4; i++)
          Offstage(
            offstage: s != i,
            child: TickerMode(
              enabled: s == i,
              child: _ziyaret.contains(i)
                  ? FadeTransition(
                      opacity: s == i ? e : kAlwaysCompleteAnimation,
                      child: SlideTransition(
                        position: s == i ? Tween(begin: Offset(.03 * yon, 0), end: Offset.zero).animate(e) : const AlwaysStoppedAnimation(Offset.zero),
                        child: _sayfa(i),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: const GuncellemeKarti())),
        ),
      ]),
      bottomNavigationBar: AltCubuk(secili: s, onSec: (i) => Kabuk.sekme.value = i),
    );
  }

  Widget _sayfa(int i) => switch (i) {
        0 => const OzetEkrani(),
        1 => const RaporlarEkrani(),
        2 => const EkipEkrani(),
        _ => const DahaFazlaEkrani(),
      };
}

/// Alt gezinme çubuğu: 4 sekme, seçili sekmenin arkasında kayan 8 px köşeli vurgu.
class AltCubuk extends StatelessWidget {
  const AltCubuk({super.key, required this.secili, required this.onSec});
  final int secili;
  final ValueChanged<int> onSec;

  static const ogeler = [
    (Icons.insights_rounded, 'Özet'),
    (Icons.bar_chart_rounded, 'Raporlar'),
    (Icons.groups_rounded, 'Ekip'),
    (Icons.more_horiz_rounded, 'Daha fazla'),
  ];

  static const yukseklik = 64.0;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final alt = math.max(MediaQuery.paddingOf(context).bottom, 4.0);
    return Container(
      height: yukseklik + alt,
      padding: EdgeInsets.only(bottom: alt),
      decoration: BoxDecoration(
        color: r.kart,
        border: Border(top: BorderSide(color: r.kenar)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LayoutBuilder(builder: (_, k) {
            final w = k.maxWidth / ogeler.length;
            final vw = (w - 20).clamp(40.0, 72.0);
            return Stack(children: [
              AnimatedPositioned(
                duration: Hareket.kapali(context) ? Duration.zero : Hareket.uzun,
                curve: Curves.easeOutBack,
                left: w * secili + (w - vw) / 2,
                top: 7,
                width: vw,
                height: 30,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: r.birincilYumusak,
                    borderRadius: Marka.yaricap,
                  ),
                ),
              ),
              Row(children: [
                for (var i = 0; i < ogeler.length; i++)
                  Expanded(
                    child: _Oge(
                      ikon: ogeler[i].$1,
                      yazi: ogeler[i].$2,
                      aktif: i == secili,
                      rozet: i == 3,
                      onTap: () => onSec(i),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _Oge extends StatelessWidget {
  const _Oge({required this.ikon, required this.yazi, required this.aktif, required this.onTap, this.rozet = false});
  final IconData ikon;
  final String yazi;
  final bool aktif;
  final bool rozet;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final renk = aktif ? r.birincil : r.silik;
    Widget simge = Icon(ikon, color: renk, size: 23);
    if (rozet) {
      simge = ValueListenableBuilder<int>(
        valueListenable: BildirimMerkezi.okunmamis,
        builder: (_, n, child) => Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: Marka.gul,
          child: child,
        ),
        child: simge,
      );
    }
    return ValueListenableBuilder<int>(
      valueListenable: BildirimMerkezi.okunmamis,
      builder: (_, n, _) => Semantics(
        button: true,
        selected: aktif,
        label: rozet && n > 0 ? '$yazi, $n okunmamış bildirim' : yazi,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: Marka.yaricap,
          child: SizedBox(
            height: AltCubuk.yukseklik,
            child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
              const SizedBox(height: 10),
              AnimatedScale(scale: aktif ? 1.08 : 1, duration: Hareket.orta, curve: Curves.easeOutBack, child: simge),
              const SizedBox(height: 8),
              Text(yazi,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 11.5, height: 1.1, fontWeight: aktif ? FontWeight.w700 : FontWeight.w500, color: renk)),
            ]),
          ),
        ),
      ),
    );
  }
}
