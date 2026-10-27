import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import 'ortak.dart';

/// MESAİ / MOLA QR — web /mesai-ekran/{token} (mesai/ekran.blade.php) birebiri.
/// Tüm personel "Tümü" menüsünden açar (yetki aranmaz; kapı vardiya eklentisi).
/// Kod sunucuda HMAC ile üretilir, 10 sn'de bir değişir; QR karesi adresten
/// cihazda çizilir (sunucunun SVG'si ile aynı içerik).
class MesaiQrEkrani extends StatefulWidget {
  const MesaiQrEkrani({super.key});

  @override
  State<MesaiQrEkrani> createState() => _MesaiQrEkraniState();
}

class _MesaiQrEkraniState extends State<MesaiQrEkrani> {
  bool _mola = false;
  Map<String, dynamic>? _paket;
  String? _hata;
  int _kalan = 0;
  bool _bagli = true;
  Timer? _saniye;
  int _sayac = 0;
  bool _mesgul = false;
  late final Api _api = context.api;
  // QR ekranı duvarda açık kalır: açıkken boşta kilit devreye girmez.
  late final UygulamaDurumu _durum = context.durum;

  @override
  void initState() {
    super.initState();
    _durum.kilitMuaf++;
    _yukle();
    _saniye = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _sayac++;
      if (_kalan <= 1) {
        _yukle();
      } else {
        setState(() => _kalan--);
        // 2 sn'de bir "okutuldu mu" yoklaması: okutulduysa sunucu yeni
        // kodu döner ve QR süre dolmadan değişir (web ekranı ile aynı).
        if (_sayac.isEven && _paket != null) _yukle(yokla: true);
      }
    });
  }

  // Kare yalnız adres değişince kodlanır; saniyelik geri sayım QR'ı yeniden
  // kodlayıp boyamaz (önceden her saniye baştan hesaplanıyordu).
  String? _kareAdres;
  Widget? _kareWidget;
  Widget _kare(String adres) {
    if (adres != _kareAdres || _kareWidget == null) {
      _kareAdres = adres;
      _kareWidget = RepaintBoundary(
        child: QrImageView(
          data: adres,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0F172A)),
          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0F172A)),
        ),
      );
    }
    return _kareWidget!;
  }

  @override
  void dispose() {
    _saniye?.cancel();
    _durum.kilitMuaf--;
    super.dispose();
  }

  Future<void> _yukle({bool yokla = false}) async {
    // Yoklama üst üste binmez; tam yükleme (kip değişimi, süre dolumu) hep geçer.
    if (_mesgul && yokla) return;
    _mesgul = true;
    final mola = _mola;
    try {
      final eski = _paket;
      final son = yokla && eski != null ? eski['kod']?.toString() : null;
      final r = await _api.get('/api/v1/uygulama/mesai-qr', sorgu: {
        'kip': mola ? 'mola' : 'mesai',
        if (son case final bbDeger?) 'son': bbDeger,
      });
      // Yanıt gelene kadar kip değiştiyse eski kipin karesi basılmaz.
      if (!mounted || r is! Map || mola != _mola) return;
      setState(() {
        final yeni = r.cast<String, dynamic>();
        _paket = yeni['ayni'] == true && _paket != null
            ? {..._paket!, 'kalan': yeni['kalan'], 'saat': yeni['saat'], 'tarih': yeni['tarih']}
            : yeni;
        _kalan = tamSayi(r['kalan'], 10).clamp(1, 60);
        _hata = null;
        _bagli = true;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _bagli = false;
        _kalan = 5;
        if (_paket == null || e.kod == 404) _hata = e.mesaj;
      });
    } finally {
      _mesgul = false;
    }
  }

  void _kip(bool mola) {
    if (mola == _mola) return;
    setState(() {
      _mola = mola;
      _paket = null;
    });
    _yukle();
  }

  @override
  Widget build(BuildContext context) {
    final p = _paket;
    if (_hata != null && p == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.qr_code_2_rounded, size: 40, color: Renk.soluk),
            const SizedBox(height: 10),
            const Text('Mesai QR açılamadı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(_hata!, textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _yukle, child: const Text('Tekrar dene')),
          ]),
        ),
      );
    }

    final g = MediaQuery.sizeOf(context);
    final yanYana = g.width >= 820;
    final qrBoy = (yanYana ? g.height * .55 : g.width * .72).clamp(200.0, 380.0);
    final adim = tamSayi(p?['yenileme_sn'], 10);

    final qr = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Renk.cizgi)),
      child: SizedBox(
        width: qrBoy,
        height: qrBoy,
        child: p == null
            ? const Center(child: CircularProgressIndicator())
            : _kare('${p['adres']}'),
      ),
    );

    Widget kipDugmesi(String ad, bool mola) {
      final secili = _mola == mola;
      return Expanded(
        child: Material(
          color: secili ? Renk.marka : Renk.yuzey,
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? Renk.marka : Renk.cizgiKoyu)),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
            onTap: () => _kip(mola),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(ad, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: secili ? Colors.white : Renk.yazi)),
              ),
            ),
          ),
        ),
      );
    }

    Widget adimSatiri(int n, InlineSpan metin) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: koseYuvarlak),
              child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Renk.marka)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text.rich(metin, style: TextStyle(fontSize: 14, color: Renk.ikinci))),
          ]),
        );

    final yan = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('ŞU AN GÖSTERİLEN KOD', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Renk.soluk, letterSpacing: .8)),
        const SizedBox(height: 4),
        Text(_mola ? 'Mola Başlat / Bitir' : 'Mesai Giriş / Çıkış', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Renk.yazi)),
        const SizedBox(height: 4),
        Text(
          _mola ? 'Molaya çıkmak veya molayı bitirmek için kodu okutun.' : 'Mesaiye başlamak veya bitirmek için kodu okutun.',
          style: TextStyle(fontSize: 14.5, color: Renk.ikinci),
        ),
        const SizedBox(height: 14),
        Row(children: [kipDugmesi('Mesai Giriş / Çıkış', false), const SizedBox(width: 8), kipDugmesi('Mola Başlat / Bitir', true)]),
        const SizedBox(height: 6),
        adimSatiri(1, const TextSpan(text: "Telefonun kamerasını QR'a tutun.")),
        adimSatiri(
          2,
          TextSpan(children: [
            const TextSpan(text: 'Açılan sayfada '),
            TextSpan(text: _mola ? 'Mola başlat / bitir' : 'Mesai başlat / bitir', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' deyin.'),
          ]),
        ),
        adimSatiri(3, TextSpan(text: 'Kod $adim saniyede bir değişir; ekran fotoğrafı işe yaramaz.')),
        const SizedBox(height: 16),
        Row(children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(value: (_kalan / (adim <= 0 ? 10 : adim)).clamp(0, 1), strokeWidth: 4, color: Renk.marka, backgroundColor: Renk.ic),
              Text('$_kalan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Renk.yazi)),
            ]),
          ),
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Yeni kod\n', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.yazi)),
              TextSpan(text: 'saniye içinde', style: TextStyle(color: Renk.ikinci)),
            ]),
            style: const TextStyle(fontSize: 13),
          ),
          const Spacer(),
          if (p != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${p['saat'] ?? ''}'.split(':').take(2).join(':'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Renk.yazi)),
              Text('${p['tarih'] ?? ''}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            ]),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: _bagli ? Renk.basari : Renk.hata, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(_bagli ? 'Bağlı' : 'Bağlantı yok — yeniden deneniyor', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          const SizedBox(width: 10),
          Expanded(child: Text('Kod $adim sn · doğrulama penceresi 30 sn', style: TextStyle(fontSize: 12, color: Renk.soluk))),
        ]),
      ]),
    );

    return ColoredBox(
      color: Renk.zemin,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: yanYana
              ? Row(mainAxisSize: MainAxisSize.min, children: [qr, const SizedBox(width: 40), Flexible(child: yan)])
              : Column(children: [qr, const SizedBox(height: 20), yan]),
        ),
      ),
    );
  }
}
