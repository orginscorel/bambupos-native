import 'dart:async';

import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'ortak.dart';

/// İLK AÇILIŞ: cihaz kodu üretir, ekranda gösterir.
///
/// Yönetici konsolda (İşletme Yönetimi › Cihazlar → Yeni tanımlı cihaz)
/// kodu girip cihaza ad + açılacak ekranı seçer. Uygulama durumu birkaç
/// saniyede bir sorar; "tanımlandı" görünce kendiliğinden aktive olur.
/// Kod + gizli anahtar diskte tutulur: uygulama kapanıp açılsa da aynı kod
/// geçerli kalır (yönetici kodu girerken cihaz yeniden başlarsa iş bozulmaz).
class AktivasyonEkrani extends StatefulWidget {
  const AktivasyonEkrani({super.key});

  @override
  State<AktivasyonEkrani> createState() => _AktivasyonEkraniState();
}

class _AktivasyonEkraniState extends State<AktivasyonEkrani> {
  static const _anahtar = 'aktivasyon';

  String? _kod;
  String? _gizli;
  DateTime? _bitis;
  String _durum = 'yukleniyor';
  String? _hata;
  bool _tamamlaniyor = false;
  Timer? _sorgu;
  Timer? _saniye;

  @override
  void initState() {
    super.initState();
    _hazirla();
    _saniye = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _bitis != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _sorgu?.cancel();
    _saniye?.cancel();
    super.dispose();
  }

  Future<void> _hazirla() async {
    final kayitli = context.durum.tercihOku(_anahtar);
    if (kayitli != null) {
      final p = kayitli.split('|');
      final bitis = p.length == 3 ? DateTime.tryParse(p[2]) : null;
      if (bitis != null && bitis.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        _kod = p[0];
        _gizli = p[1];
        _bitis = bitis;
        _durum = 'bekliyor';
        setState(() {});
        _sorguyaBasla();
        return;
      }
    }
    await _yeniKod();
  }

  Future<void> _yeniKod() async {
    _sorgu?.cancel();
    setState(() {
      _durum = 'yukleniyor';
      _hata = null;
    });
    try {
      final r = (await context.api.post('/api/v1/cihaz-aktivasyon/baslat') as Map).cast<String, dynamic>();
      _kod = r['kod']?.toString();
      _gizli = r['gizli']?.toString();
      _bitis = DateTime.tryParse(r['bitis']?.toString() ?? '')?.toLocal() ?? DateTime.now().add(const Duration(minutes: 30));
      if (!mounted) return;
      await context.durum.tercihYaz(_anahtar, '$_kod|$_gizli|${_bitis!.toIso8601String()}');
      setState(() => _durum = 'bekliyor');
      _sorguyaBasla();
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _durum = 'hata';
        _hata = e.mesaj;
      });
      // Bağlantı yoksa kendiliğinden yeniden dene.
      _sorgu = Timer(const Duration(seconds: 5), _yeniKod);
    }
  }

  void _sorguyaBasla() {
    _sorgu?.cancel();
    _sorgu = Timer.periodic(const Duration(seconds: 3), (_) => _durumSor());
    _durumSor();
  }

  Future<void> _durumSor() async {
    if (_kod == null || _gizli == null || _tamamlaniyor) return;
    if (_bitis != null && DateTime.now().isAfter(_bitis!)) {
      await _yeniKod();
      return;
    }
    try {
      final r = (await context.api.post('/api/v1/cihaz-aktivasyon/durum', {'kod': _kod, 'gizli': _gizli}) as Map);
      final d = r['durum']?.toString() ?? 'bekliyor';
      if (!mounted) return;
      if (d == 'gecersiz') {
        await _yeniKod();
      } else if (d == 'tanimlandi' || d == 'aktif') {
        await _tamamla();
      } else if (_durum != d || _hata != null) {
        setState(() {
          _durum = d;
          _hata = null;
        });
      }
    } on ApiHata catch (e) {
      if (mounted && e.baglantiYok) setState(() => _hata = e.mesaj);
    }
  }

  Future<void> _tamamla() async {
    if (_tamamlaniyor) return;
    setState(() {
      _tamamlaniyor = true;
      _durum = 'tanimlandi';
    });
    try {
      await context.api.post('/api/v1/cihaz-aktivasyon/tamamla', {'kod': _kod, 'gizli': _gizli});
      _sorgu?.cancel();
      if (!mounted) return;
      await context.durum.tercihYaz(_anahtar, null);
      if (!mounted) return;
      await context.durum.aktiveEdildi();
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _tamamlaniyor = false;
        _hata = e.mesaj;
        // 423: başka cihaza kilitli / izin kaldırılmış — sorgu durur, yönetici çözmeli.
        if (e.kod == 423) {
          _sorgu?.cancel();
          _durum = 'kilitli';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 760;
    final kalan = _bitis?.difference(DateTime.now());

    final kodKutusu = Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Cihaz tanımlama kodu', style: TextStyle(color: Renk.soluk, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      if (_durum == 'yukleniyor')
        const SizedBox(height: 96, child: Center(child: CircularProgressIndicator()))
      else if (_kod != null)
        FittedBox(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final h in _kod!.split(''))
              Container(
                width: 64,
                height: 84,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Renk.markaAcik,
                  borderRadius: koseYuvarlak,
                  border: Border.all(color: Renk.marka.withValues(alpha: .25)),
                ),
                child: Text(h,
                    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: Renk.marka, letterSpacing: 0)),
              ),
          ]),
        ),
      const SizedBox(height: 16),
      _durumSatiri(kalan),
      if (_hata != null) ...[
        const SizedBox(height: 10),
        Text(_hata!, textAlign: TextAlign.center, style: const TextStyle(color: Renk.hata, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: _tamamlaniyor ? null : _yeniKod,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('Yeni kod üret'),
      ),
    ]);

    const yonerge = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Bu cihazı işletmenize bağlayın', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      SizedBox(height: 16),
      _Adim(no: 1, metin: 'Yönetim panelinde İşletme Yönetimi › Cihazlar sayfasını açın.'),
      _Adim(no: 2, metin: '“Yeni tanımlı cihaz” düğmesine basın ve yandaki kodu girin.'),
      _Adim(no: 3, metin: 'Cihaza bir ad verin ve açılacak ekranı seçin (Sipariş, Kasa, Mutfak …).'),
      _Adim(no: 4, metin: 'Kaydedince bu cihaz kendiliğinden açılır; personel kendi PIN\'iyle girer.'),
    ]);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(children: [
                const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Logo(boyut: 40),
                  SizedBox(width: 12),
                  Text('BamBumPOS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: genis
                        ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                            const Expanded(child: yonerge),
                            const SizedBox(width: 32),
                            Expanded(child: kodKutusu),
                          ])
                        : Column(children: [kodKutusu, const SizedBox(height: 28), yonerge]),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Sunucu: ${context.api.taban.host}', style: const TextStyle(color: Renk.soluk, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _durumSatiri(Duration? kalan) {
    final (ikon, renk, metin) = switch (_durum) {
      'tanimlandi' => (Icons.check_circle_rounded, Renk.basari, 'Kod tanımlandı, cihaz açılıyor…'),
      'kilitli' => (Icons.lock_rounded, Renk.hata, 'Cihaz eşlenemedi'),
      'hata' => (Icons.wifi_off_rounded, Renk.uyari, 'Kod alınamadı, yeniden deneniyor…'),
      _ => (
          Icons.hourglass_top_rounded,
          Renk.soluk,
          kalan == null || kalan.isNegative
              ? 'Yönetici bekleniyor…'
              : 'Yönetici bekleniyor · ${kalan.inMinutes}:${(kalan.inSeconds % 60).toString().padLeft(2, '0')}'
        ),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (_durum == 'tanimlandi')
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4))
      else
        Icon(ikon, size: 18, color: renk),
      const SizedBox(width: 8),
      Text(metin, style: TextStyle(color: renk, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _Adim extends StatelessWidget {
  const _Adim({required this.no, required this.metin});
  final int no;
  final String metin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Renk.marka, borderRadius: BorderRadius.circular(6)),
          child: Text('$no', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(metin, style: const TextStyle(fontSize: 15, height: 1.4))),
      ]),
    );
  }
}
