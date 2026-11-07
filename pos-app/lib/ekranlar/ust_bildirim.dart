import 'dart:async';

import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/durum.dart';

class UstBildirimVeri {
  UstBildirimVeri(this.baslik, this.metin, this.hata, this.sure, this.no);
  final String baslik;
  final String metin;
  final bool hata;
  final Duration sure;
  final int no;
}

/// ÜST BİLDİRİM (1.2.52): eski alttaki bant (SnackBar) yerine üst ortada
/// küçük bir kart. Dokunmayı ENGELLEMEZ (IgnorePointer), kendiliğinden
/// kapanır, yenisi gelince eskisinin yerini alır. Sağ üstteki bildirim
/// baloncuklarının üstünde kalır; kasa hatırlatması açıksa onun altına iner.
class UstBildirim extends StatefulWidget {
  const UstBildirim({super.key, required this.durum});
  final UygulamaDurumu durum;

  static final deger = ValueNotifier<UstBildirimVeri?>(null);
  static int _no = 0;

  static void goster(String baslik, {String metin = '', bool hata = false, Duration? sure}) {
    deger.value = UstBildirimVeri(
      baslik,
      metin,
      hata,
      sure ?? Duration(milliseconds: hata ? 3500 : 2000),
      ++_no,
    );
  }

  @override
  State<UstBildirim> createState() => _UstBildirimState();
}

class _UstBildirimState extends State<UstBildirim> {
  Timer? _kapat;

  @override
  void initState() {
    super.initState();
    UstBildirim.deger.addListener(_degisti);
    widget.durum.kasaHatirlatma.addListener(_yenile);
  }

  @override
  void dispose() {
    UstBildirim.deger.removeListener(_degisti);
    widget.durum.kasaHatirlatma.removeListener(_yenile);
    _kapat?.cancel();
    super.dispose();
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  void _degisti() {
    _kapat?.cancel();
    final v = UstBildirim.deger.value;
    if (v != null) {
      _kapat = Timer(v.sure, () {
        if (UstBildirim.deger.value?.no == v.no) UstBildirim.deger.value = null;
      });
    }
    _yenile();
  }

  @override
  Widget build(BuildContext context) {
    final v = UstBildirim.deger.value;
    final mq = MediaQuery.of(context);
    final hatirlatmaAcik = widget.durum.kasaHatirlatma.value != null;
    return Positioned(
      top: mq.padding.top + (hatirlatmaAcik ? 104 : 12),
      left: 12,
      right: 12,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, -.25), end: Offset.zero).animate(a), child: c),
            ),
            child: v == null ? const SizedBox.shrink() : _kart(v),
          ),
        ),
      ),
    );
  }

  Widget _kart(UstBildirimVeri v) {
    final zemin = v.hata ? Renk.hata : Renk.yazi;
    final yazi = v.hata ? Colors.white : Renk.yuzey;
    return ConstrainedBox(
      key: ValueKey(v.no),
      constraints: const BoxConstraints(maxWidth: 440),
      child: Material(
        color: zemin,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: .25),
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(v.hata ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, size: 18, color: yazi),
            const SizedBox(width: 10),
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v.baslik,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: v.metin.isEmpty ? FontWeight.w600 : FontWeight.w700, color: yazi)),
                if (v.metin.isNotEmpty)
                  Text(v.metin, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: yazi.withValues(alpha: .9))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
