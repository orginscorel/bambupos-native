import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';
import 'kabuk.dart';

/// AÇILIŞ: TELEFON EŞLEME (POS cihaz aktivasyonunun personel eşi).
///
/// Telefon 6 haneli kod + QR gösterir. Yönetici Konsol › Cihazlar › Personel
/// telefonu eşle bölümünde kodu girip personeli seçer (ya da QR'ı okutur).
/// Telefon 3 sn'de bir sorar; eşlenince karşılama animasyonu ve kalıcı oturum.
class EslesmeEkrani extends StatefulWidget {
  const EslesmeEkrani({super.key});
  @override
  State<EslesmeEkrani> createState() => _EslesmeEkraniState();
}

enum _Asama { yukleniyor, bekliyor, eslendi, hata }

class _EslesmeEkraniState extends State<EslesmeEkrani> {
  static const _konsol = 'https://bambumpos.com/musteri/isletme/cihazlar';
  _Asama _asama = _Asama.yukleniyor;
  String? _kod;
  String? _gizli;
  DateTime? _bitis;
  String _ad = '';
  String? _hata;
  /// Kalan saniye: yalnız sayaç yazısı yeniden çizilir (eskiden her saniye
  /// QR dahil tüm ekran yeniden kuruluyordu).
  final _kalan = ValueNotifier<int>(0);
  Timer? _yokla;
  Timer? _say;

  @override
  void initState() {
    super.initState();
    final p = Uyg.tercih;
    final k = p.getString('eslesme_kod');
    final g = p.getString('eslesme_gizli');
    final b = DateTime.tryParse(p.getString('eslesme_bitis') ?? '');
    if (k != null && g != null && b != null && b.difference(DateTime.now()).inSeconds > 60) {
      _kod = k;
      _gizli = g;
      _bitis = b;
      _hazir();
    } else {
      _yeniKod();
    }
  }

  @override
  void dispose() {
    _yokla?.cancel();
    _say?.cancel();
    _kalan.dispose();
    super.dispose();
  }

  Future<void> _yeniKod() async {
    setState(() => _asama = _Asama.yukleniyor);
    try {
      final r = await Uyg.api.post('/api/v1/personel-eslesme/baslat') as Map;
      _kod = r['kod'].toString();
      _gizli = r['gizli'].toString();
      _bitis = DateTime.tryParse(r['bitis'].toString())?.toLocal() ?? DateTime.now().add(const Duration(minutes: 30));
      final p = Uyg.tercih;
      await p.setString('eslesme_kod', _kod!);
      await p.setString('eslesme_gizli', _gizli!);
      await p.setString('eslesme_bitis', _bitis!.toIso8601String());
      _hazir();
    } on ApiHata catch (e) {
      setState(() {
        _asama = _Asama.hata;
        _hata = e.mesaj;
      });
    }
  }

  void _hazir() {
    setState(() => _asama = _Asama.bekliyor);
    _say?.cancel();
    void tik() {
      final k = _bitis!.difference(DateTime.now()).inSeconds;
      if (!mounted) return;
      _kalan.value = k < 0 ? 0 : k;
      if (k <= 0) _yeniKod();
    }

    tik();
    _say = Timer.periodic(const Duration(seconds: 1), (_) => tik());
    _yokla?.cancel();
    _yokla = Timer.periodic(const Duration(seconds: 3), (_) => _kontrol());
    _kontrol();
  }

  Future<void> _kontrol() async {
    if (_asama != _Asama.bekliyor || _kod == null) return;
    if (!uygulamaOnde.value) return; // arka planda yoklama yok; öne gelince sürer
    try {
      final r = await Uyg.api.post('/api/v1/personel-eslesme/durum', {'kod': _kod, 'gizli': _gizli}) as Map;
      final d = r['durum']?.toString();
      if (d == 'gecersiz') {
        await _yeniKod();
      } else if (d == 'tanimlandi') {
        await _tamamla();
      }
    } on ApiHata {
      // Ağ kesintisi: sonraki turda.
    }
  }

  Future<void> _tamamla() async {
    _yokla?.cancel();
    _say?.cancel();
    try {
      final r = await Uyg.api.post('/api/v1/personel-eslesme/tamamla', {'kod': _kod, 'gizli': _gizli}) as Map;
      _ad = r['ad']?.toString() ?? '';
      final p = Uyg.tercih;
      await p.remove('eslesme_kod');
      await p.remove('eslesme_gizli');
      await p.remove('eslesme_bitis');
      HapticFeedback.heavyImpact();
      setState(() => _asama = _Asama.eslendi);
      await Uyg.hesapYukle();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      if (!mounted) return;
      kabugaGec(context);
    } on ApiHata catch (e) {
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
      value: durumCubugu,
      child: Scaffold(
        body: Aurora(
          child: _asama == _Asama.eslendi
              ? _eslendi()
              : ListView(
                  padding: EdgeInsets.fromLTRB(22, ust + 22, 22, alt + 18),
                  children: [
                    Belir(
                      child: Row(children: [
                        const PaMark(boyut: 44),
                        const SizedBox(width: 12),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('BamBumPOS', style: gosterim(18, renk: Colors.white)),
                          Text('PERSONEL', style: TextStyle(color: Marka.gok.withValues(alpha: .75), letterSpacing: 3, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ]),
                    ),
                    const SizedBox(height: 30),
                    Belir(
                      gecikme: 80,
                      child: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Telefonunu\n'),
                          TextSpan(text: 'işletmene eşle', style: gosterim(31, renk: const Color(0xFFA5B4FC))),
                        ]),
                        style: gosterim(31, renk: Colors.white, satir: 1.15),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Belir(
                      gecikme: 140,
                      child: Text.rich(
                        TextSpan(children: [
                          const TextSpan(text: 'Yöneticin bu kodu '),
                          const TextSpan(text: 'Konsol › Cihazlar › Personel telefonu eşle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                          const TextSpan(text: ' bölümüne girsin ya da QR\'ı okutsun.'),
                        ]),
                        style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 14.5, height: 1.45),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Belir(gecikme: 200, child: _kodKarti()),
                    const SizedBox(height: 18),
                    if (_asama == _Asama.bekliyor) Belir(gecikme: 260, child: const _Bekleniyor()),
                    if (_asama == _Asama.hata)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .15), borderRadius: BorderRadius.circular(18)),
                        child: Column(children: [
                          Text(_hata ?? 'Bir sorun oluştu.', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFE4E6), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          YumusakDugme(yazi: 'Yeni kod al', onTap: _yeniKod, zemin: Colors.white, renk: Marka.lacivert1),
                        ]),
                      ),
                    const SizedBox(height: 28),
                    Row(children: [
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: .15))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('ya da', style: TextStyle(color: Colors.white.withValues(alpha: .4), fontSize: 12))),
                      Expanded(child: Divider(color: Colors.white.withValues(alpha: .15))),
                    ]),
                    const SizedBox(height: 12),
                    Basilir(
                      onTap: () => Navigator.of(context).push(HizliRota(builder: (_) => const GirisEkrani())),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: .15)),
                        ),
                        child: const Text('E-posta / telefon ve parola ile giriş', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Uyg.tercih.remove('eslesme_kod');
                        _yeniKod();
                      },
                      child: Text('Kodu yenile', style: TextStyle(color: Colors.white.withValues(alpha: .5), fontSize: 12.5)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _kodKarti() {
    final kod = _kod ?? '······';
    return Cam(
      padding: const EdgeInsets.all(18),
      child: Column(children: [
        Row(children: [
          Text('EŞLEME KODU', style: TextStyle(color: Marka.gok.withValues(alpha: .75), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.6)),
          const Spacer(),
          if (_asama == _Asama.bekliyor) ...[
            Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF6EE7B7), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            ValueListenableBuilder<int>(
              valueListenable: _kalan,
              builder: (_, k, _) => Text('${k ~/ 60}:${(k % 60).toString().padLeft(2, '0')}', style: gosterim(13, agirlik: FontWeight.w600, renk: Colors.white60)),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () {
            if (_kod != null) {
              Clipboard.setData(ClipboardData(text: _kod!));
              bildir('Kod kopyalandı', mesaj: _kod);
            }
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 6; i++) ...[
              if (i == 3) Container(width: 12, height: 3, margin: const EdgeInsets.symmetric(horizontal: 4), color: Colors.white30),
              _Hane(harf: kod.length > i ? kod[i] : '·', sira: i, anahtar: kod),
            ],
          ]),
        ),
        const SizedBox(height: 18),
        AnimatedOpacity(
          opacity: _asama == _Asama.bekliyor ? 1 : .35,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 18), spreadRadius: -18)]),
            child: _kod == null
                ? const SizedBox(width: 180, height: 180, child: Center(child: Yukleyici(renk: Marka.mor)))
                : QrImageView(
                    data: '$_konsol?pkod=$_kod#personel-esle',
                    size: 180,
                    padding: EdgeInsets.zero,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Marka.murekkep),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Marka.murekkep),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Text('Yönetici telefonuyla okutursa kod hazır gelir', style: TextStyle(color: Colors.white.withValues(alpha: .55), fontSize: 12)),
      ]),
    );
  }

  Widget _eslendi() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.elasticOut,
              builder: (_, v, _) => Transform.scale(
                scale: v,
                child: Container(
                  width: 128,
                  height: 128,
                  decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(36), boxShadow: const [BoxShadow(color: Color(0xAA5443D2), blurRadius: 40, offset: Offset(0, 16))]),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 70),
                ),
              ),
            ),
            const SizedBox(height: 30),
            Belir(gecikme: 250, child: Text('CİHAZ EŞLENDİ', style: TextStyle(color: Marka.gok.withValues(alpha: .75), letterSpacing: 2.2, fontWeight: FontWeight.w700, fontSize: 12))),
            const SizedBox(height: 8),
            Belir(gecikme: 350, child: Text(_ad.isEmpty ? 'Hoş geldin!' : 'Hoş geldin, ${_ad.split(' ').first}!', textAlign: TextAlign.center, style: gosterim(30, renk: Colors.white))),
            const SizedBox(height: 8),
            Belir(gecikme: 450, child: Text('Hesabın hazırlanıyor…', style: TextStyle(color: Colors.white.withValues(alpha: .65)))),
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
        tween: Tween(begin: 0, end: 1),
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
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.white.withValues(alpha: .15)),
          ),
          child: Text(harf, style: gosterim(28, renk: Colors.white)),
        ),
      );
}

class _Bekleniyor extends StatefulWidget {
  const _Bekleniyor();
  @override
  State<_Bekleniyor> createState() => _BekleniyorState();
}

class _BekleniyorState extends State<_Bekleniyor> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = ((_c.value - i * .15) % 1);
              final y = t < .4 ? -4 * (t < .2 ? t / .2 : (.4 - t) / .2) : 0.0;
              return Transform.translate(
                offset: Offset(0, y),
                child: Container(width: 7, height: 7, margin: const EdgeInsets.symmetric(horizontal: 2.5), decoration: BoxDecoration(color: Marka.gok.withValues(alpha: .4 + .6 * (y.abs() / 4)), shape: BoxShape.circle)),
              );
            },
          ),
        const SizedBox(width: 10),
        Text('Eşleme bekleniyor', style: TextStyle(color: Colors.white.withValues(alpha: .75), fontWeight: FontWeight.w600)),
      ]);
}

/* ───────────────────────── Parola ile giriş ───────────────────────── */

class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});
  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final _kim = TextEditingController();
  final _parola = TextEditingController();
  bool _gizli = true;
  bool _bekle = false;
  String? _hata;

  Future<void> _gir() async {
    if (_kim.text.trim().isEmpty || _parola.text.isEmpty) {
      setState(() => _hata = 'E-posta / telefon ve parolanı gir.');
      return;
    }
    setState(() {
      _bekle = true;
      _hata = null;
    });
    try {
      final r = await Uyg.api.post('/api/v1/auth/login', {'email': _kim.text.trim(), 'password': _parola.text, 'remember': true});
      if (r is Map && (r['two_factor'] == true || r['requires_two_factor'] == true)) {
        setState(() => _hata = 'Hesabında iki adımlı doğrulama açık. Telefonu eşleme koduyla bağla.');
        return;
      }
      if (await Uyg.hesapYukle()) {
        if (!mounted) return;
        kabugaGec(context);
      } else {
        setState(() => _hata = 'Giriş yapılamadı.');
      }
    } on ApiHata catch (e) {
      setState(() => _hata = e.mesaj);
    } finally {
      if (mounted) setState(() => _bekle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.paddingOf(context).top;
    InputDecoration koyu(String etiket, IconData ikon, {Widget? sag}) => InputDecoration(
          labelText: etiket,
          prefixIcon: Icon(ikon, color: Colors.white60),
          suffixIcon: sag,
          filled: true,
          fillColor: Colors.white.withValues(alpha: .1),
          labelStyle: const TextStyle(color: Colors.white60),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Colors.white.withValues(alpha: .15))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Marka.gok, width: 2)),
        );
    return AnnotatedRegion(
      value: durumCubugu,
      child: Scaffold(
        body: Aurora(
          child: ListView(padding: EdgeInsets.fromLTRB(22, ust + 10, 22, 30), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Basilir(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 28),
                ),
              ),
            ),
            const SizedBox(height: 26),
            const Belir(child: PaMark(boyut: 56)),
            const SizedBox(height: 18),
            Belir(gecikme: 60, child: Text('Parola ile giriş', style: gosterim(30, renk: Colors.white))),
            Belir(gecikme: 100, child: Text('İşletmenin sana verdiği bilgilerle gir.', style: TextStyle(color: Colors.white.withValues(alpha: .65)))),
            const SizedBox(height: 26),
            Belir(
              gecikme: 140,
              child: TextField(
                controller: _kim,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                style: const TextStyle(color: Colors.white),
                decoration: koyu('E-posta / telefon / kullanıcı adı', Icons.person_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Belir(
              gecikme: 180,
              child: TextField(
                controller: _parola,
                obscureText: _gizli,
                autofillHints: const [AutofillHints.password],
                style: const TextStyle(color: Colors.white),
                onSubmitted: (_) => _gir(),
                decoration: koyu('Parola', Icons.lock_rounded,
                    sag: IconButton(
                      icon: Icon(_gizli ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: Colors.white60),
                      onPressed: () => setState(() => _gizli = !_gizli),
                    )),
              ),
            ),
            if (_hata != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_hata!, style: const TextStyle(color: Color(0xFFFDA4AF), fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 22),
            Belir(gecikme: 220, child: GradDugme(yazi: 'Giriş yap', ikon: Icons.arrow_forward_rounded, yukleniyor: _bekle, onTap: _gir)),
          ]),
        ),
      ),
    );
  }
}
