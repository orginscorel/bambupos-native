import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'cerceve.dart';
import 'guncelleme.dart';
import 'ortak.dart';
import 'telefonla_giris.dart';

/// PERSONEL GİRİŞİ — web'deki terminal PIN ekranının ("Oturum aç") birebiri:
/// noktalı PIN kutusu + "en az 4 hane", 3×4 tuş takımı (Sil · 0 · Temizle),
/// geniş "Oturum aç" düğmesi; üstte işletme künyesi, altta cihaz künyesi.
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
  late final AnimationController _salla = AnimationController(vsync: this, duration: const Duration(milliseconds: 360));
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

  void _temizle() {
    if (_bekliyor) return;
    setState(() {
      _pin = '';
      _hata = null;
    });
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
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _temizle();
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
    final kunye = [o?.cihazAd, platformAdi(), o?.isletmeKod].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      appBar: UstCubuk(baslik: o?.isletme ?? 'BamBumPOS', altSatir: kunye),
      bottomNavigationBar: AltCubuk(
        ust: o?.isletme ?? '',
        alt: [o?.cihazAd, platformAdi()].whereType<String>().join(' · '),
        sag: const Text('Cihaz bu işletmeye tanımlı', style: TextStyle(fontSize: 12.5, color: Renk.ikinci)),
      ),
      body: Focus(
        focusNode: _odak,
        autofocus: true,
        onKeyEvent: _klavye,
        child: Column(
          children: [
            const GuncellemeSeridi(),
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFEEF1F8), Color(0xFFF6F8FB)],
                  ),
                ),
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    // Web düzeni: geniş ekranda PIN ve telefon kartı yan yana, dar ekranda alt alta.
                    child: LayoutBuilder(
                      builder: (context, k) {
                        final yan = k.maxWidth >= 760;
                        final telefon = _kutu(const TelefonlaGiris());
                        if (yan) {
                          return ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 800),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 54, child: _kart()),
                                  const SizedBox(width: 10),
                                  Expanded(flex: 46, child: telefon),
                                ],
                              ),
                            ),
                          );
                        }
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: Column(children: [_kart(), const SizedBox(height: 10), telefon]),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kutu(Widget icerik) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: Renk.yuzey,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Renk.cizgi),
      boxShadow: const [BoxShadow(color: Color(0x141C1917), blurRadius: 24, offset: Offset(0, 8))],
    ),
    child: icerik,
  );

  Widget _kart() {
    return _kutu(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.shield_outlined, size: 17, color: Renk.marka),
              ),
              const SizedBox(width: 10),
              const Text('Oturum aç', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Text('PIN ile', style: TextStyle(fontSize: 12, color: Renk.soluk)),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _salla,
            builder: (_, child) {
              final t = _salla.value;
              final dx = t == 0 ? 0.0 : 10 * (1 - t) * ((t * 10).floor().isEven ? 1 : -1);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Renk.ic,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _hata != null ? Renk.hataKenar : Colors.transparent),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 11,
                      height: 11,
                      margin: const EdgeInsets.only(right: 9),
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? Renk.yazi : const Color(0xFFCBD5E1)),
                    ),
                  const Spacer(),
                  Text(_pin.length >= 4 ? '${_pin.length} hane' : 'en az 4 hane', style: const TextStyle(fontSize: 12, color: Renk.soluk)),
                ],
              ),
            ),
          ),
          if (_hata != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _hata!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Renk.hata, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),
          for (final satir in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(children: [for (final h in satir) _tus(h, () => _bas(h))]),
          Row(children: [_tus('Sil', _sil, kirmizi: true), _tus('0', () => _bas('0')), _tus('Temizle', _temizle, kirmizi: true)]),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _pin.length >= 4 && !_bekliyor ? _gir : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF4F5BD5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontFamily: yaziTipi, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              child: _bekliyor
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                  : const Text('Oturum aç'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tus(String etiket, VoidCallback bas, {bool kirmizi = false}) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: Renk.yuzey,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: bas,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Renk.cizgi),
            ),
            child: Text(
              etiket,
              style: TextStyle(
                fontSize: kirmizi ? 14.5 : 21,
                fontWeight: kirmizi ? FontWeight.w600 : FontWeight.w600,
                color: kirmizi ? Renk.hata : Renk.yazi,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
