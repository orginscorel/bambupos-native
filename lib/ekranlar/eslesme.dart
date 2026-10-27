import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'kabuk.dart';

/// PATRON TELEFONU EŞLEME.
///
/// Telefon 6 haneli kod + QR gösterir. YALNIZ İŞLETME SAHİBİ panelde
/// İşletme Yönetimi › Cihazlar › "Patron telefonu eşle" bölümünde kodu girer
/// (ya da QR'ı okutur) ve patron paneli yetkisi olan kişiyi (sahip, müdür,
/// şube müdürü) seçer. Telefon 3 sn'de bir sorar; eşlenince kalıcı oturum.
///
/// 429 (çok istek): sunucunun önerdiği süre kadar beklenir, geri sayım
/// gösterilir; döngüye girip istek yağdırılmaz.
class EslesmeEkrani extends StatefulWidget {
  const EslesmeEkrani({super.key});

  /// QR içeriğinin kökü (web Pair.vue'deki konsolUrl ile aynı: hosts.panel).
  static const konsol = 'https://bambumpos.com/musteri/isletme/cihazlar';

  static String qrAdresi(String kod) => '$konsol?patronkod=$kod#patron-esle';

  @override
  State<EslesmeEkrani> createState() => _EslesmeEkraniState();
}

enum _Asama { yukleniyor, bekliyor, eslendi, hata, bekleme }

class _EslesmeEkraniState extends State<EslesmeEkrani> {
  _Asama _asama = _Asama.yukleniyor;
  String? _kod;
  String? _gizli;
  DateTime? _bitis;
  String _ad = '';
  String? _hata;
  String? _tanimlananAd;
  int _kalan = 0;
  Timer? _yokla;
  Timer? _say;
  DateTime? _sustur; // 429 sonrası bu ana kadar istek atılmaz
  int _ardisikHata = 0;

  @override
  void initState() {
    super.initState();
    Uyg.oturumlu = false;
    final p = Uyg.tercih;
    final k = p.getString('eslesme_kod');
    final g = p.getString('eslesme_gizli');
    final b = DateTime.tryParse(p.getString('eslesme_bitis') ?? '');
    if (k != null && g != null && b != null && b.difference(DateTime.now()).inSeconds > 60) {
      _kod = k;
      _gizli = g;
      _bitis = b;
      WidgetsBinding.instance.addPostFrameCallback((_) => _hazir());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _yeniKod());
    }
  }

  @override
  void dispose() {
    _yokla?.cancel();
    _say?.cancel();
    super.dispose();
  }

  Future<void> _yeniKod() async {
    if (!mounted) return;
    _yokla?.cancel();
    setState(() {
      _asama = _Asama.yukleniyor;
      _tanimlananAd = null;
    });
    try {
      final r = await Uyg.api.post('/api/v1/patron-eslesme/baslat') as Map;
      _kod = r['kod'].toString();
      _gizli = r['gizli'].toString();
      _bitis = DateTime.tryParse(r['bitis'].toString())?.toLocal() ?? DateTime.now().add(const Duration(minutes: 10));
      final p = Uyg.tercih;
      await p.setString('eslesme_kod', _kod!);
      await p.setString('eslesme_gizli', _gizli!);
      await p.setString('eslesme_bitis', _bitis!.toIso8601String());
      _hazir();
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (e.cokIstek) {
        _beklet(e.bekle ?? const Duration(seconds: 30), sonra: _yeniKod);
        return;
      }
      setState(() {
        _asama = _Asama.hata;
        _hata = e.mesaj;
      });
    }
  }

  /// 429: geri sayım gösterip süre dolunca [sonra]'yı bir kez çalıştırır.
  void _beklet(Duration sure, {required Future<void> Function() sonra}) {
    _yokla?.cancel();
    _say?.cancel();
    _sustur = DateTime.now().add(sure);
    setState(() {
      _asama = _Asama.bekleme;
      _kalan = sure.inSeconds;
    });
    _say = Timer.periodic(const Duration(seconds: 1), (z) {
      if (!mounted) {
        z.cancel();
        return;
      }
      final k = _sustur!.difference(DateTime.now()).inSeconds;
      setState(() => _kalan = k < 0 ? 0 : k);
      if (k <= 0) {
        z.cancel();
        _sustur = null;
        sonra();
      }
    });
  }

  void _hazir() {
    if (!mounted) return;
    setState(() => _asama = _Asama.bekliyor);
    _say?.cancel();
    void tik() {
      if (!mounted) return;
      final k = _bitis!.difference(DateTime.now()).inSeconds;
      setState(() => _kalan = k < 0 ? 0 : k);
      if (k <= 0) _yeniKod();
    }

    tik();
    _say = Timer.periodic(const Duration(seconds: 1), (_) => tik());
    _yokla?.cancel();
    _yokla = Timer.periodic(const Duration(seconds: 3), (_) => _kontrol());
    _kontrol();
  }

  bool _soruyor = false;

  Future<void> _kontrol() async {
    if (_asama != _Asama.bekliyor || _kod == null || _soruyor) return;
    if (_sustur != null && DateTime.now().isBefore(_sustur!)) return;
    _soruyor = true;
    try {
      final r = await Uyg.api.post('/api/v1/patron-eslesme/durum', {'kod': _kod, 'gizli': _gizli}) as Map;
      _ardisikHata = 0;
      final d = r['durum']?.toString();
      if (d == 'gecersiz' || d == 'aktif') {
        // Kodun süresi doldu ya da kod (yarıda kalan bir eşlemede) zaten kullanıldı.
        await Uyg.tercih.remove('eslesme_kod');
        await _yeniKod();
      } else if (d == 'tanimlandi') {
        if (mounted) setState(() => _tanimlananAd = r['ad']?.toString());
        await _tamamla();
      }
    } on ApiHata catch (e) {
      if (e.cokIstek) {
        // Yoklamayı süre boyunca durdur; ekran kodu göstermeye devam eder.
        _sustur = DateTime.now().add(e.bekle ?? const Duration(seconds: 30));
      } else if (e.baglantiYok) {
        // Ağ kesintisi: art arda hatada yoklamayı seyrelt (3 → 15 sn).
        _ardisikHata++;
        if (_ardisikHata >= 5) _sustur = DateTime.now().add(const Duration(seconds: 15));
      }
    } finally {
      _soruyor = false;
    }
  }

  Future<void> _tamamla() async {
    _yokla?.cancel();
    _say?.cancel();
    try {
      final r = await Uyg.api.post('/api/v1/patron-eslesme/tamamla', {'kod': _kod, 'gizli': _gizli}) as Map;
      _ad = r['ad']?.toString() ?? '';
      await Uyg.adKaydet(_ad);
      final p = Uyg.tercih;
      await p.remove('eslesme_kod');
      await p.remove('eslesme_gizli');
      await p.remove('eslesme_bitis');
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() => _asama = _Asama.eslendi);
      await Future<void>.delayed(Duration(milliseconds: Hareket.kapali(context) ? 600 : 2200));
      if (!mounted) return;
      kabugaGec(context);
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (e.cokIstek) {
        _beklet(e.bekle ?? const Duration(seconds: 30), sonra: () async => _hazir());
        return;
      }
      setState(() {
        _asama = _Asama.hata;
        _hata = e.mesaj;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alt = MediaQuery.paddingOf(context).bottom;
    final ust = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion(
      value: durumCubuguAcikSimge,
      child: Scaffold(
        backgroundColor: Marka.gece,
        body: GeceZemin(
          child: AnimatedSwitcher(
            duration: Hareket.uzun,
            transitionBuilder: asamaGecisi,
            child: _asama == _Asama.eslendi
                ? KeyedSubtree(key: const ValueKey('eslendi'), child: _eslendi())
                : Center(
                    key: const ValueKey('form'),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(20, ust + 22, 20, alt + 18),
                        children: [
                          Belirme(
                            sira: 0,
                            child: Row(children: [
                              const PaMark(boyut: 44),
                              const SizedBox(width: 12),
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('BamBumPOS', style: gosterim(18, renk: Colors.white)),
                                Text('PATRON', style: TextStyle(color: Marka.gok.withValues(alpha: .85), letterSpacing: 3, fontSize: 11, fontWeight: FontWeight.w700)),
                              ]),
                            ]),
                          ),
                          const SizedBox(height: 28),
                          Belirme(
                            sira: 1,
                            child: Semantics(
                              header: true,
                              child: Text.rich(
                                TextSpan(children: [
                                  const TextSpan(text: 'Telefonunuzu\n'),
                                  TextSpan(text: 'işletmenize eşleyin', style: gosterim(30, renk: const Color(0xFFA5B4FC))),
                                ]),
                                style: gosterim(30, renk: Colors.white, satir: 1.15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Belirme(
                            sira: 2,
                            child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: 'İşletme sahibi bu kodu panelde '),
                                const TextSpan(text: 'İşletme Yönetimi › Cihazlar › Patron telefonu eşle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                const TextSpan(text: ' bölümüne girsin ya da QR\'ı okutsun.'),
                              ]),
                              style: TextStyle(color: Colors.white.withValues(alpha: .78), fontSize: 14.5, height: 1.45),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Belirme(sira: 3, child: _kodKarti()),
                          const SizedBox(height: 16),
                          if (_asama == _Asama.bekliyor) Belirme(sira: 4, child: _Bekleniyor(ad: _tanimlananAd)),
                          if (_asama == _Asama.bekleme) _beklemeKutusu(),
                          if (_asama == _Asama.hata) _hataKutusu(),
                          const SizedBox(height: 18),
                          Belirme(sira: 5, child: _not()),
                          const SizedBox(height: 8),
                          if (_asama == _Asama.bekliyor)
                            Center(
                              child: TextButton(
                                onPressed: () {
                                  Uyg.tercih.remove('eslesme_kod');
                                  _yeniKod();
                                },
                                child: Text('Kodu yenile', style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 13)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _not() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: Marka.yaricap,
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.verified_user_rounded, color: Marka.gok, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Patron telefonunu yalnız işletme sahibi eşler. Yalnız patron paneli yetkisi olan kişiler (sahip, müdür, şube müdürü) seçilebilir. '
              'Eşlemeyi kaldırmak da sahibe aittir: Cihazlar bölümünden kaldırıldığında bu telefon bu ekrana döner.',
              style: TextStyle(color: Colors.white.withValues(alpha: .75), fontSize: 12.5, height: 1.45),
            ),
          ),
        ]),
      );

  Widget _beklemeKutusu() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Marka.kehribar.withValues(alpha: .18), borderRadius: Marka.yaricap),
        child: Row(children: [
          const Icon(Icons.hourglass_top_rounded, color: Marka.kehribarAcik),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Çok fazla deneme yapıldı. $_kalan sn sonra otomatik olarak yeniden denenecek.',
                style: const TextStyle(color: Color(0xFFFEF3C7), fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Widget _hataKutusu() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .18), borderRadius: Marka.yaricap),
        child: Column(children: [
          Text(_hata ?? 'Bir sorun oluştu.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFE4E6), fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () {
              Uyg.tercih.remove('eslesme_kod');
              _yeniKod();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Marka.gece2),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Yeni kod al'),
          ),
        ]),
      );

  Widget _kodKarti() {
    final kod = _kod ?? '······';
    final dk = _kalan ~/ 60;
    final sn = (_kalan % 60).toString().padLeft(2, '0');
    final aktif = _asama == _Asama.bekliyor;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: Marka.yaricap,
        border: Border.all(color: Colors.white.withValues(alpha: .14)),
      ),
      child: Column(children: [
        Row(children: [
          Text('EŞLEME KODU', style: TextStyle(color: Marka.gok.withValues(alpha: .85), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
          const Spacer(),
          if (aktif)
            Semantics(
              label: 'Kodun kalan süresi $dk dakika $sn saniye',
              excludeSemantics: true,
              child: Row(children: [
                Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF6EE7B7), shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text('$dk:$sn', style: gosterim(13, agirlik: FontWeight.w600, renk: Colors.white70)),
              ]),
            ),
        ]),
        const SizedBox(height: 14),
        Semantics(
          label: _kod == null ? 'Kod hazırlanıyor' : 'Eşleme kodu ${_kod!.split('').join(' ')}. Kopyalamak için dokunun.',
          button: _kod != null,
          excludeSemantics: true,
          child: GestureDetector(
            onTap: () {
              if (_kod != null) {
                Clipboard.setData(ClipboardData(text: _kod!));
                bildir('Kod kopyalandı', mesaj: _kod);
              }
            },
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i == 3) Container(width: 12, height: 3, margin: const EdgeInsets.symmetric(horizontal: 4), color: Colors.white30),
                  _Hane(harf: kod.length > i ? kod[i] : '·', sira: i, anahtar: kod),
                ],
              ]),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AnimatedOpacity(
          opacity: aktif ? 1 : .35,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: Marka.yaricap),
            child: _kod == null
                ? const SizedBox(width: 176, height: 176, child: Center(child: Yukleyici(renk: Marka.mor)))
                : Semantics(
                    label: 'Eşleme QR kodu',
                    image: true,
                    child: QrImageView(
                      data: EslesmeEkrani.qrAdresi(_kod!),
                      size: 176,
                      padding: EdgeInsets.zero,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Marka.murekkep),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Marka.murekkep),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text('Sahip telefonuyla okutursa kod hazır gelir', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 12)),
      ]),
    );
  }

  Widget _eslendi() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: Hareket.kapali(context) ? 1 : 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.elasticOut,
              builder: (_, v, _) => Transform.scale(
                scale: v,
                child: Container(
                  width: 124,
                  height: 124,
                  decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0xAA5443D2), blurRadius: 40, offset: Offset(0, 16))]),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 68),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Belirme(sira: 4, child: Text('TELEFON EŞLENDİ', style: TextStyle(color: Marka.gok.withValues(alpha: .85), letterSpacing: 2.2, fontWeight: FontWeight.w700, fontSize: 12))),
            const SizedBox(height: 8),
            Belirme(
                sira: 6,
                child: Text(_ad.isEmpty ? 'Hoş geldiniz!' : 'Hoş geldiniz, ${_ad.split(' ').first}!',
                    textAlign: TextAlign.center, style: gosterim(28, renk: Colors.white))),
            const SizedBox(height: 8),
            Belirme(sira: 8, child: Text('İşletmenizin özeti hazırlanıyor…', style: TextStyle(color: Colors.white.withValues(alpha: .72)))),
          ]),
        ),
      );
}

class _Hane extends StatelessWidget {
  const _Hane({required this.harf, required this.sira, required this.anahtar});
  final String harf;
  final int sira;
  final String anahtar;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey('$anahtar$sira'),
        tween: Tween(begin: Hareket.kapali(context) ? 1 : 0, end: 1),
        duration: Duration(milliseconds: 450 + sira * 60),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: .5 + .5 * v, child: Opacity(opacity: v.clamp(0, 1), child: child)),
        child: Container(
          width: 42,
          height: 54,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: Marka.yaricap,
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
          ),
          child: Text(harf, style: gosterim(28, renk: Colors.white)),
        ),
      );
}

class _Bekleniyor extends StatefulWidget {
  const _Bekleniyor({this.ad});
  final String? ad;
  @override
  State<_Bekleniyor> createState() => _BekleniyorState();
}

class _BekleniyorState extends State<_Bekleniyor> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Hareket.kapali(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < 3; i++)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) {
                final t = ((_c.value - i * .15) % 1);
                final y = t < .4 ? -4 * (t < .2 ? t / .2 : (.4 - t) / .2) : 0.0;
                return Transform.translate(
                  offset: Offset(0, y),
                  child: Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(color: Marka.gok.withValues(alpha: .4 + .6 * (y.abs() / 4)), shape: BoxShape.circle)),
                );
              },
            ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(widget.ad == null ? 'İşletme sahibinin eşlemesi bekleniyor' : '${widget.ad} olarak giriş yapılıyor…',
                style: TextStyle(color: Colors.white.withValues(alpha: .82), fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
