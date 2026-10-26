import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'ortak.dart';

/// Personel girişi: yalnız PIN. Giren kişinin yetkisi ekranı belirler.
class PinEkrani extends StatefulWidget {
  const PinEkrani({super.key});

  @override
  State<PinEkrani> createState() => _PinEkraniState();
}

class _PinEkraniState extends State<PinEkrani> with SingleTickerProviderStateMixin {
  static const _enCok = 10;
  String _pin = '';
  String? _hata;
  bool _bekliyor = false;
  late final AnimationController _salla =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
  final _odak = FocusNode();

  @override
  void dispose() {
    _salla.dispose();
    _odak.dispose();
    super.dispose();
  }

  void _bas(String h) {
    if (_bekliyor || _pin.length >= _enCok) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += h;
      _hata = null;
    });
  }

  void _sil() {
    if (_pin.isEmpty || _bekliyor) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _gir() async {
    if (_pin.length < 4 || _bekliyor) return;
    setState(() => _bekliyor = true);
    try {
      await context.durum.pinIleGir(_pin);
    } on ApiHata catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _salla.forward(from: 0);
      setState(() {
        _hata = e.mesaj;
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _bekliyor = false);
    }
  }

  KeyEventResult _klavye(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.character;
    if (k != null && RegExp(r'^\d$').hasMatch(k)) {
      _bas(k);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _sil();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _gir();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final o = context.durum.oturum;

    return Scaffold(
      body: Focus(
        focusNode: _odak,
        autofocus: true,
        onKeyEvent: _klavye,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(children: [
                  const Logo(boyut: 52),
                  const SizedBox(height: 14),
                  Text(o?.isletme ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(
                    [o?.cihazAd, o?.istasyonEtiket, o?.sube].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    style: const TextStyle(color: Renk.soluk),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  const Text('Personel PIN\'inizi girin', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  AnimatedBuilder(
                    animation: _salla,
                    builder: (_, child) {
                      final t = _salla.value;
                      final dx = t == 0 ? 0.0 : 10 * (1 - t) * ((t * 10).floor().isEven ? 1 : -1);
                      return Transform.translate(offset: Offset(dx, 0), child: child);
                    },
                    child: SizedBox(
                      height: 22,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: i < _pin.length ? Renk.marka : Colors.transparent,
                              border: Border.all(color: i < _pin.length ? Renk.marka : Renk.cizgi, width: 2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: Center(
                      child: _hata == null
                          ? null
                          : Text(_hata!, style: const TextStyle(color: Renk.hata, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                    ),
                  ),
                  _TusTakimi(
                    bas: _bas,
                    sil: _sil,
                    gir: _gir,
                    girAktif: _pin.length >= 4 && !_bekliyor,
                    bekliyor: _bekliyor,
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TusTakimi extends StatelessWidget {
  const _TusTakimi({required this.bas, required this.sil, required this.gir, required this.girAktif, required this.bekliyor});
  final void Function(String) bas;
  final VoidCallback sil;
  final VoidCallback gir;
  final bool girAktif;
  final bool bekliyor;

  @override
  Widget build(BuildContext context) {
    Widget tus(Widget icerik, VoidCallback? f, {Color? zemin, Color? renk}) => Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: zemin ?? Renk.yuzey,
            borderRadius: koseYuvarlak,
            child: InkWell(
              borderRadius: koseYuvarlak,
              onTap: f,
              child: Container(
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                child: DefaultTextStyle.merge(
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: renk ?? Renk.yazi),
                  child: IconTheme(data: IconThemeData(color: renk ?? Renk.yazi, size: 26), child: icerik),
                ),
              ),
            ),
          ),
        );

    final satirlar = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    return Column(children: [
      for (final s in satirlar)
        Row(children: [for (final h in s) Expanded(child: tus(Text(h), () => bas(h)))]),
      Row(children: [
        Expanded(child: tus(const Icon(Icons.backspace_outlined), sil)),
        Expanded(child: tus(const Text('0'), () => bas('0'))),
        Expanded(
          child: tus(
            bekliyor
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                : const Icon(Icons.arrow_forward_rounded),
            girAktif ? gir : null,
            zemin: girAktif ? Renk.marka : Renk.markaAcik,
            renk: Colors.white,
          ),
        ),
      ]),
    ]);
  }
}
