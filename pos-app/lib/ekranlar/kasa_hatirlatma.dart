import 'dart:async';

import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/durum.dart';

/// KASA HATIRLATMASI (1.2.49): kasa cihazında kasa yetkilisi 3 dk boşta
/// kalınca PIN'e düşmek yerine üst ortada küçük bir kart çıkar. Ekranı
/// kapatmaz (yalnız kartın kendisi dokunma alır). 10 sn'de dokunulmazsa
/// kendiliğinden kapanır ve oturum sürer; "PIN ekranına dön" → kilitle.
class KasaHatirlatma extends StatefulWidget {
  const KasaHatirlatma({super.key, required this.durum});
  final UygulamaDurumu durum;

  @override
  State<KasaHatirlatma> createState() => _KasaHatirlatmaState();
}

class _KasaHatirlatmaState extends State<KasaHatirlatma> with SingleTickerProviderStateMixin {
  static const _sure = Duration(seconds: 10);
  late final AnimationController _sayac = AnimationController(vsync: this, duration: _sure);
  Timer? _kapat;
  String? _ad;

  @override
  void initState() {
    super.initState();
    widget.durum.kasaHatirlatma.addListener(_degisti);
  }

  @override
  void dispose() {
    widget.durum.kasaHatirlatma.removeListener(_degisti);
    _kapat?.cancel();
    _sayac.dispose();
    super.dispose();
  }

  void _degisti() {
    final ad = widget.durum.kasaHatirlatma.value;
    _kapat?.cancel();
    if (ad == null) {
      _sayac.stop();
      if (mounted) setState(() => _ad = null);
      return;
    }
    setState(() => _ad = ad);
    _sayac.forward(from: 0);
    _kapat = Timer(_sure, _gizle);
  }

  void _gizle() => widget.durum.kasaHatirlatma.value = null;

  void _pineDon() {
    _gizle();
    widget.durum.kilitle();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    final mq = MediaQuery.of(context);
    return Positioned(
      top: mq.padding.top + 12,
      left: 12,
      right: 12,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Material(
            key: const ValueKey('kasa-hatirlatma'),
            color: Renk.yuzey,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: .25),
            shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Renk.markaKenar)),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.person_pin_outlined, size: 19, color: Renk.marka),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Kasada girili hesap', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Renk.soluk)),
                      Text(ad.isEmpty ? 'Personel' : ad,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Renk.yazi)),
                      Text('Doğru değilse PIN ekranına dönün.', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    key: const ValueKey('kasa-hatirlatma-pin'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                    ),
                    onPressed: _pineDon,
                    child: const Text('PIN ekranına dön', style: TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                    key: const ValueKey('kasa-hatirlatma-kapat'),
                    onPressed: _gizle,
                    icon: Icon(Icons.close_rounded, size: 18, color: Renk.soluk),
                  ),
                ]),
              ),
              // 10 sn geri sayım: dolunca kart kapanır, oturum sürer.
              AnimatedBuilder(
                animation: _sayac,
                builder: (_, _) => LinearProgressIndicator(
                  value: 1 - _sayac.value,
                  minHeight: 3,
                  color: Renk.marka,
                  backgroundColor: Renk.markaAcik,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
