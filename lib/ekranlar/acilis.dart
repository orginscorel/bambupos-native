import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'eslesme.dart';
import 'kabuk.dart';

/// Açılış: marka animasyonu + oturum kontrolü.
/// Oturum varsa kabuğa, yoksa telefon eşleme ekranına geçer.
class AcilisEkrani extends StatefulWidget {
  const AcilisEkrani({super.key});
  @override
  State<AcilisEkrani> createState() => _AcilisEkraniState();
}

class _AcilisEkraniState extends State<AcilisEkrani> with TickerProviderStateMixin {
  late final _halka = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  String? _hata;

  @override
  void initState() {
    super.initState();
    Uyg.api.oturumDustu = oturumDustu;
    _basla();
  }

  Future<void> _basla() async {
    setState(() => _hata = null);
    final bekle = Future<void>.delayed(const Duration(milliseconds: 1100));
    bool var_;
    try {
      var_ = await Uyg.hesapYukle();
    } on ApiHata catch (e) {
      setState(() => _hata = e.mesaj);
      return;
    }
    await bekle;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, _, _) => var_ ? const Kabuk() : const EslesmeEkrani(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 1.04, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    ));
  }

  @override
  void dispose() {
    _halka.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: durumCubugu,
      child: Scaffold(
        body: Aurora(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  for (final g in [0.0, .5])
                    AnimatedBuilder(
                      animation: _halka,
                      builder: (_, _) {
                        final t = (_halka.value + g) % 1;
                        return Opacity(
                          opacity: (1 - t) * .6,
                          child: Container(
                            width: 84 + 64 * t,
                            height: 84 + 64 * t,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28 + 14 * t),
                              border: Border.all(color: g == 0 ? Marka.gok : Marka.lavanta, width: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: .3, end: 1),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: const PaMark(boyut: 84),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              Belir(gecikme: 250, child: Text('BamBumPOS', style: gosterim(26, renk: Colors.white))),
              Belir(
                gecikme: 330,
                child: Text('PERSONEL', style: TextStyle(color: Marka.gok.withValues(alpha: .75), letterSpacing: 4, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 28),
              if (_hata == null)
                const SizedBox(width: 140, child: _Serit())
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(children: [
                    Text(_hata!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 14),
                    YumusakDugme(yazi: 'Tekrar dene', ikon: Icons.refresh_rounded, onTap: _basla, zemin: Colors.white.withValues(alpha: .12), renk: Colors.white),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Serit extends StatefulWidget {
  const _Serit();
  @override
  State<_Serit> createState() => _SeritState();
}

class _SeritState extends State<_Serit> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 4,
          color: Colors.white.withValues(alpha: .15),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, _) => FractionallySizedBox(
              alignment: Alignment(-1.6 + 3.2 * _c.value, 0),
              widthFactor: .45,
              child: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Marka.gok, Marka.lavanta]))),
            ),
          ),
        ),
      );
}

/// Oturum düştüğünde (401) her yerden eşleme ekranına dön.
void oturumDustu() {
  final nav = Uyg.navigator.currentState;
  if (nav == null || Uyg.hesap.value == null) return;
  Uyg.hesap.value = null;
  nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const EslesmeEkrani()), (_) => false);
  bildir('Oturum kapandı', mesaj: 'Telefonu yeniden eşle ya da parolayla gir.', tur: BildirimTur.uyari);
}
