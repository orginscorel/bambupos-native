import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'ortak.dart';

/// Ödeme al: nakit / kart. Nakitte alınan tutar kalandan fazlaysa sunucuya
/// KALAN gönderilir, fark para üstü olarak gösterilir.
/// Başarılıysa güncel adisyon döner.
Future<Adisyon?> odemeAc(BuildContext context, Adisyon adisyon) {
  return showDialog<Adisyon>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: _Odeme(adisyon: adisyon)),
    ),
  );
}

class _Odeme extends StatefulWidget {
  const _Odeme({required this.adisyon});
  final Adisyon adisyon;

  @override
  State<_Odeme> createState() => _OdemeState();
}

class _OdemeState extends State<_Odeme> {
  String _yontem = 'cash';
  String _girdi = ''; // kuruş cinsinden rakamlar
  bool _gonderiliyor = false;
  String? _hata;

  int get _kalan => widget.adisyon.kalan;
  int get _tutar => _girdi.isEmpty ? _kalan : int.parse(_girdi);
  int get _gonderilecek => _tutar > _kalan ? _kalan : _tutar;
  int get _paraUstu => _yontem == 'cash' && _tutar > _kalan ? _tutar - _kalan : 0;

  void _tus(String t) {
    HapticFeedback.selectionClick();
    setState(() {
      _hata = null;
      if (t == '⌫') {
        if (_girdi.isNotEmpty) _girdi = _girdi.substring(0, _girdi.length - 1);
      } else if (t == '00') {
        if (_girdi.isNotEmpty && _girdi.length < 8) _girdi += '00';
      } else if (_girdi.length < 9) {
        _girdi = (_girdi + t).replaceFirst(RegExp(r'^0+'), '');
      }
    });
  }

  void _hazir(int minor) => setState(() {
        _girdi = minor.toString();
        _hata = null;
      });

  Future<void> _al() async {
    if (_gonderilecek <= 0) return;
    if (_yontem == 'card' && _tutar > _kalan) {
      setState(() => _hata = 'Kartla kalandan fazla tahsil edilemez.');
      return;
    }
    setState(() => _gonderiliyor = true);
    try {
      final r = await context.api.post('/api/v1/orders/${widget.adisyon.id}/pay', {
        'amount_minor': _gonderilecek,
        'method': _yontem,
        'expected_version': widget.adisyon.surum,
      });
      final yeni = Adisyon(((r as Map)['order'] as Map).cast<String, dynamic>());
      if (!mounted) return;
      final ustu = _paraUstu;
      // Pencere kapanınca bu bağlam ölür; bildirimi alttaki ekran gösterir.
      final mesaj = ScaffoldMessenger.of(context);
      Navigator.pop(context, yeni);
      if (ustu > 0) {
        mesaj.showSnackBar(SnackBar(content: Text('Para üstü: ${para(ustu)}'), duration: const Duration(seconds: 6)));
      }
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _gonderiliyor = false;
        _hata = e.mesaj;
      });
      context.durum.islemHatasi(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget yontem(String k, String etiket, IconData ikon) => Expanded(
          child: Material(
            color: _yontem == k ? Renk.marka : Renk.yuzey,
            borderRadius: koseYuvarlak,
            child: InkWell(
              borderRadius: koseYuvarlak,
              onTap: () => setState(() => _yontem = k),
              child: Container(
                height: 52,
                decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: _yontem == k ? Renk.marka : Renk.cizgi)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(ikon, color: _yontem == k ? Colors.white : Renk.yazi),
                  const SizedBox(width: 8),
                  Text(etiket, style: TextStyle(fontWeight: FontWeight.w700, color: _yontem == k ? Colors.white : Renk.yazi)),
                ]),
              ),
            ),
          ),
        );

    Widget tus(String t) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              onPressed: _gonderiliyor ? null : () => _tus(t),
              child: t == '⌫' ? const Icon(Icons.backspace_outlined) : Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Ödeme · ${widget.adisyon.baslik}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          IconButton(onPressed: _gonderiliyor ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
        const SizedBox(height: 4),
        Text('Kalan: ${para(_kalan)}', style: const TextStyle(color: Renk.soluk, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Row(children: [
          yontem('cash', 'Nakit', Icons.payments_outlined),
          const SizedBox(width: 10),
          yontem('card', 'Kart', Icons.credit_card_rounded),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Renk.zemin, borderRadius: koseYuvarlak),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_yontem == 'cash' ? 'Alınan' : 'Tahsil edilecek', style: const TextStyle(color: Renk.soluk, fontSize: 12)),
            Text(para(_tutar), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            if (_paraUstu > 0)
              Text('Para üstü: ${para(_paraUstu)}', style: const TextStyle(color: Renk.basari, fontWeight: FontWeight.w800, fontSize: 16)),
            if (_tutar < _kalan)
              Text('Kısmi ödeme · kalacak ${para(_kalan - _tutar)}', style: const TextStyle(color: Renk.uyari, fontWeight: FontWeight.w600)),
          ]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(label: const Text('Tamamı'), onPressed: () => _hazir(_kalan)),
          if (_kalan >= 200) ActionChip(label: const Text('Yarısı'), onPressed: () => _hazir(_kalan ~/ 2)),
          if (_yontem == 'cash')
            for (final b in const [5000, 10000, 20000, 50000, 100000])
              if (b >= _kalan) ActionChip(label: Text(para(b)), onPressed: () => _hazir(b)),
        ]),
        const SizedBox(height: 10),
        for (final s in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['00', '0', '⌫'],
        ])
          Row(children: [for (final t in s) tus(t)]),
        if (_hata != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_hata!, style: const TextStyle(color: Renk.hata, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: Renk.basari),
          onPressed: _gonderiliyor || _gonderilecek <= 0 ? null : _al,
          child: _gonderiliyor
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
              : Text('${para(_gonderilecek)} tahsil et', style: const TextStyle(fontSize: 17)),
        ),
      ]),
    );
  }
}
