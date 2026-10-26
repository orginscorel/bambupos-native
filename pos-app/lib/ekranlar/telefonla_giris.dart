import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'ortak.dart';

/// "Telefonla oturum aç" — web PIN ekranındaki QR kartının birebiri
/// (TerminalOperatorGate.vue). Cihaz bir giriş anahtarı alır, adresini kare
/// olarak çizer; personel telefonuyla okutup onaylar, cihaz 3 sn'de bir
/// sorar ve "açıldı" gelince o personel olarak devam eder. Kare ömrü dolmadan
/// (~110 sn) yenilenir.
class TelefonlaGiris extends StatefulWidget {
  const TelefonlaGiris({super.key});

  @override
  State<TelefonlaGiris> createState() => _TelefonlaGirisState();
}

class _TelefonlaGirisState extends State<TelefonlaGiris> {
  String? _adres;
  String _mesaj = 'Kare hazırlanıyor…';
  int _kalan = 0;
  int _toplam = 110;
  int _onayliTur = 0;
  Timer? _sayac;
  Timer? _yoklama;
  Timer? _tazele;
  late final Api _api = context.api;

  @override
  void initState() {
    super.initState();
    _anahtarAl();
    _yoklama = Timer.periodic(const Duration(seconds: 3), (_) => _yokla());
  }

  @override
  void dispose() {
    _sayac?.cancel();
    _yoklama?.cancel();
    _tazele?.cancel();
    super.dispose();
  }

  Future<void> _anahtarAl() async {
    _onayliTur = 0;
    try {
      final d = (await _api.post('/api/v1/auth/qr-giris') as Map);
      final adres = d['adres']?.toString();
      final omur = (d['omur'] as num?)?.toInt() ?? 120;
      if (!mounted || adres == null) return;
      setState(() {
        _adres = adres;
        _toplam = (omur - 10).clamp(5, 600);
        _kalan = _toplam;
      });
      _sayac?.cancel();
      _sayac = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _kalan = (_kalan - 1).clamp(0, _toplam));
      });
      _tazele?.cancel();
      _tazele = Timer(Duration(seconds: (omur - 10).clamp(30, 600)), _anahtarAl);
    } on ApiHata {
      if (mounted) {
        setState(() {
          _adres = null;
          _mesaj = 'Kare alınamadı';
        });
      }
      _tazele?.cancel();
      _tazele = Timer(const Duration(seconds: 10), _anahtarAl);
    }
  }

  Future<void> _yokla() async {
    if (_adres == null) return;
    try {
      final d = (await _api.get('/api/v1/auth/qr-giris/durum') as Map);
      final durum = d['durum']?.toString();
      if (!mounted) return;
      if (durum == 'acildi') {
        context.bildir('Hoş geldin ${d['ad'] ?? ''}'.trim());
        await context.durum.oturumuYenile();
      } else if (durum == 'onaylandi') {
        if (++_onayliTur >= 3) _anahtarAl();
      } else if (durum != null && durum != 'bekliyor') {
        if (d['mesaj'] != null) context.bildir(d['mesaj'].toString(), hata: true);
        _anahtarAl();
      }
    } on ApiHata {
      // Ağ koptu: sonraki yoklamada tekrar dener.
    }
  }

  String get _sureMetni {
    if (_kalan <= 0) return 'Kare yenileniyor…';
    if (_kalan < 60) return 'Kare $_kalan sn sonra yenilenir';
    return 'Kare ${_kalan ~/ 60}:${(_kalan % 60).toString().padLeft(2, '0')} sonra yenilenir';
  }

  @override
  Widget build(BuildContext context) {
    final kod = context.durum.oturum?.isletmeKod ?? '';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.qr_code_scanner_rounded, size: 17, color: Renk.marka),
        ),
        const SizedBox(width: 10),
        const Text('Telefonla oturum aç', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      Center(
        child: Container(
          width: 150,
          height: 150,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Renk.cizgi),
            boxShadow: const [BoxShadow(color: Color(0x141C1917), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: _adres == null
              ? Center(child: Text(_mesaj, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Renk.soluk)))
              : QrImageView(data: _adres!, padding: EdgeInsets.zero, gapless: true),
        ),
      ),
      const SizedBox(height: 8),
      Text(_sureMetni, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Renk.ikinci)),
      const SizedBox(height: 4),
      Center(
        child: SizedBox(
          width: 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _toplam > 0 ? _kalan / _toplam : 0,
              minHeight: 3,
              backgroundColor: Renk.ic,
              color: Renk.ikinci,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text.rich(
        TextSpan(children: [
          TextSpan(text: 'Telefonunuzun kamerasıyla kareyi okutun. Telefonda '),
          TextSpan(text: 'hangi hesapla giriş yaptıysanız', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.yazi)),
          TextSpan(text: ' bu cihazda o personel olarak devam edersiniz. Kare iki dakikada bir yenilenir.'),
        ]),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Renk.ikinci, height: 1.45),
      ),
      if (kod.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            const Text('YENİ CİHAZ BAĞLAMAK İÇİN',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Renk.soluk, letterSpacing: .8)),
            const SizedBox(height: 4),
            Text(kod, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 4)),
            const SizedBox(height: 2),
            Text('${context.api.taban.host}/baglan adresine gidip bu kodu yazın.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: Renk.ikinci)),
          ]),
        ),
      ],
    ]);
  }
}
