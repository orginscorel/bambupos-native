import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// QR OKUT — işletmedeki dönen mesai QR'ı okutulur, alttan pano açılır:
///   mesaide değil → Mesaiye başla
///   mesaide       → Molaya çık · Mesaiyi bitir · Kısa mola
///   molada        → Molayı bitir · (Mesai bitir kilitli)
/// Uçlar: GET/POST /api/v1/portal/qr-mesai/{token}/{kod} (web ile aynı).
class QrOkutEkrani extends StatefulWidget {
  const QrOkutEkrani({super.key});
  @override
  State<QrOkutEkrani> createState() => _QrOkutEkraniState();
}

class _QrOkutEkraniState extends State<QrOkutEkrani> with SingleTickerProviderStateMixin {
  static final _desen = RegExp(r'/qr-mesai/([A-Za-z0-9]{10,64})/([0-9A-Fa-f]{12})');

  final _kamera = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  late final _tarama = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  bool _on = false;
  bool _fener = false;
  bool _isabet = false;
  bool _mesgul = false;
  DateTime _sonYanlis = DateTime(2000);

  Map<String, dynamic>? _pano;
  String? _token;
  String? _kod;
  int _kalan = 0;
  Timer? _say;
  String? _islem; // eylem anahtarı
  String? _islemTur;
  Map<String, dynamic>? _bitti;

  @override
  void dispose() {
    _kamera.dispose();
    _tarama.dispose();
    _say?.cancel();
    super.dispose();
  }

  Future<void> _algila(BarcodeCapture c) async {
    if (_mesgul || _pano != null || _bitti != null) return;
    final ham = c.barcodes.firstOrNull?.rawValue;
    if (ham == null) return;
    final m = _desen.firstMatch(ham);
    if (m == null) {
      if (DateTime.now().difference(_sonYanlis).inSeconds > 3) {
        _sonYanlis = DateTime.now();
        bildir('Bu bir mesai QR\'ı değil', mesaj: 'Kasadaki ya da giriş ekranındaki mesai QR\'ını okutun.', tur: BildirimTur.uyari);
      }
      return;
    }
    _mesgul = true;
    HapticFeedback.mediumImpact();
    setState(() => _isabet = true);
    _token = m.group(1);
    _kod = m.group(2);
    try {
      final r = await Uyg.api.get('/api/v1/portal/qr-mesai/$_token/$_kod') as Map;
      _panoyuAc(Map<String, dynamic>.from(r));
    } on ApiHata catch (e) {
      bildir('QR geçerli değil', mesaj: e.mesaj, tur: BildirimTur.hata);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) setState(() => _isabet = false);
    } finally {
      _mesgul = false;
    }
  }

  void _panoyuAc(Map<String, dynamic> d) {
    setState(() {
      _pano = d;
      _kalan = (d['kalan_sn'] as num?)?.toInt() ?? 30;
    });
    _say?.cancel();
    _say = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _kalan = math.max(0, _kalan - 1));
      if (_kalan == 0) t.cancel();
    });
  }

  bool _kapandi = false;

  /// Ekranı TEK dokunuşta kapatır (X, başarı ekranı, otomatik). İki kez pop etmez.
  void _kapat() {
    if (_kapandi || !mounted) return;
    _kapandi = true;
    _say?.cancel();
    unawaited(_kamera.stop().catchError((_) {}));
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _panoyuKapat() {
    _say?.cancel();
    setState(() {
      _pano = null;
      _isabet = false;
    });
  }

  Future<void> _calistir(String eylem, [String? tur]) async {
    if (_islem != null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _islem = eylem;
      _islemTur = tur;
    });
    try {
      final r = await Uyg.api.post('/api/v1/portal/qr-mesai/$_token/$_kod', {'eylem': eylem, 'mola_turu': ?tur}) as Map;
      _say?.cancel();
      HapticFeedback.heavyImpact();
      // Ana sayfa / Mesaim durumu HEMEN yenilesin (eskiden 60 sn yoklamayı bekliyordu)
      Uyg.mesaiDegisti.value++;
      setState(() {
        _pano = null;
        _bitti = Map<String, dynamic>.from(r);
      });
      unawaited(_kamera.stop());
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      _kapat();
    } on ApiHata catch (e) {
      bildir('İşlem yapılamadı', mesaj: e.mesaj, tur: BildirimTur.hata);
    } finally {
      if (mounted) {
        setState(() {
          _islem = null;
          _islemTur = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.paddingOf(context).top;
    final alt = MediaQuery.paddingOf(context).bottom;
    return AnnotatedRegion(
      value: durumCubugu,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: AnimatedScale(
              scale: _pano != null ? 1.06 : 1,
              duration: const Duration(milliseconds: 500),
              child: MobileScanner(
                controller: _kamera,
                onDetect: _algila,
                errorBuilder: (_, e) => _KameraHatasi(hata: e, tekrar: () => _kamera.start()),
              ),
            ),
          ),
          // Karartma + çerçeve
          if (_bitti == null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _pano != null ? .6 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: CustomPaint(painter: _CerceveCizer(isabet: _isabet)),
                ),
              ),
            ),
          if (_bitti == null && _pano == null && !_isabet)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(builder: (_, k) {
                  final kenar = math.min(k.maxWidth * .7, 280.0);
                  final ustK = (k.maxHeight - kenar) / 2 - 40;
                  return AnimatedBuilder(
                    animation: _tarama,
                    builder: (_, _) => Stack(children: [
                      Positioned(
                        left: (k.maxWidth - kenar) / 2 + kenar * .08,
                        width: kenar * .84,
                        top: ustK + kenar * (.06 + .88 * Curves.easeInOut.transform(_tarama.value)),
                        height: 3,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            gradient: const LinearGradient(colors: [Colors.transparent, Color(0xFF7DD3FC), Color(0xFFA5B4FC), Colors.transparent]),
                            boxShadow: const [BoxShadow(color: Color(0x995443D2), blurRadius: 18, spreadRadius: 4)],
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
            ),
          // Kamera seçimi
          if (_pano == null && _bitti == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: alt + 40,
              child: Column(children: [
                Text('Aktif kamera', style: TextStyle(color: Colors.white.withValues(alpha: .75), fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Container(
                  width: 220,
                  height: 50,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(18)),
                  child: Stack(fit: StackFit.expand, children: [
                    AnimatedAlign(
                      alignment: _on ? Alignment.centerRight : Alignment.centerLeft,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      child: FractionallySizedBox(
                        widthFactor: .5,
                        child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                    Row(children: [
                      for (final (on, yazi) in [(false, 'Arka'), (true, 'Ön')])
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              if (_on == on) return;
                              titret();
                              await _kamera.switchCamera();
                              setState(() => _on = on);
                            },
                            child: Center(child: Text(yazi, style: TextStyle(fontWeight: FontWeight.w800, color: _on == on ? Marka.murekkep : Colors.white))),
                          ),
                        ),
                    ]),
                  ]),
                ),
              ]),
            ),
          // Pano
          if (_pano != null) ...[
            Positioned.fill(child: GestureDetector(onTap: _islem == null ? _panoyuKapat : null, child: Container(color: Colors.transparent))),
            Align(alignment: Alignment.bottomCenter, child: _Pano(veri: _pano!, kalan: _kalan, islem: _islem, islemTur: _islemTur, calistir: _calistir, yeniden: _panoyuKapat)),
          ],
          if (_bitti != null) Positioned.fill(child: GestureDetector(onTap: _kapat, child: _Basari(veri: _bitti!))),
          // Üst çubuk — EN ÜSTTE: pano arkasındaki dokunma katmanı ve başarı ekranı X'i örtmesin
          Positioned(
            left: 16,
            right: 16,
            top: ust + 12,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: .4), borderRadius: BorderRadius.circular(30)),
                child: const Text('Mesai / mola QR\'ını okut', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              _YuvarlakDugme(
                ikon: _fener ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                etkin: _fener,
                onTap: () async {
                  await _kamera.toggleTorch();
                  setState(() => _fener = !_fener);
                },
              ),
              const SizedBox(width: 8),
              _YuvarlakDugme(ikon: Icons.close_rounded, onTap: _kapat),
            ]),
          ),
        ]),
      ),
    );
  }
}

/* ───────────────────────── Çerçeve ───────────────────────── */

class _CerceveCizer extends CustomPainter {
  _CerceveCizer({required this.isabet});
  final bool isabet;
  @override
  void paint(Canvas c, Size s) {
    final kenar = math.min(s.width * .7, 280.0);
    final rect = Rect.fromLTWH((s.width - kenar) / 2, (s.height - kenar) / 2 - 40, kenar, kenar);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(28));
    c.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & s), Path()..addRRect(rr)),
      Paint()..color = const Color(0x8C09081E),
    );
    final renk = isabet ? const Color(0xFF34D399) : Colors.white;
    final kalem = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = renk;
    final golge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..color = (isabet ? const Color(0xFF34D399) : Marka.mor).withValues(alpha: .55)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    const u = 38.0;
    const r = 28.0;
    final kose = [
      Path()
        ..moveTo(rect.left, rect.top + u)
        ..lineTo(rect.left, rect.top + r)
        ..arcToPoint(Offset(rect.left + r, rect.top), radius: const Radius.circular(r))
        ..lineTo(rect.left + u, rect.top),
      Path()
        ..moveTo(rect.right - u, rect.top)
        ..lineTo(rect.right - r, rect.top)
        ..arcToPoint(Offset(rect.right, rect.top + r), radius: const Radius.circular(r))
        ..lineTo(rect.right, rect.top + u),
      Path()
        ..moveTo(rect.right, rect.bottom - u)
        ..lineTo(rect.right, rect.bottom - r)
        ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: const Radius.circular(r))
        ..lineTo(rect.right - u, rect.bottom),
      Path()
        ..moveTo(rect.left + u, rect.bottom)
        ..lineTo(rect.left + r, rect.bottom)
        ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: const Radius.circular(r))
        ..lineTo(rect.left, rect.bottom - u),
    ];
    for (final p in kose) {
      c.drawPath(p, golge);
      c.drawPath(p, kalem);
    }
  }

  @override
  bool shouldRepaint(_CerceveCizer o) => o.isabet != isabet;
}

class _YuvarlakDugme extends StatelessWidget {
  const _YuvarlakDugme({required this.ikon, required this.onTap, this.etkin = false});
  final IconData ikon;
  final VoidCallback onTap;
  final bool etkin;
  @override
  Widget build(BuildContext context) => Basilir(
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: etkin ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(17)),
          child: Icon(ikon, color: etkin ? Colors.black : Colors.white, size: 23),
        ),
      );
}

class _KameraHatasi extends StatelessWidget {
  const _KameraHatasi({required this.hata, required this.tekrar});
  final MobileScannerException hata;
  final VoidCallback tekrar;
  @override
  Widget build(BuildContext context) {
    final izin = hata.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: Marka.lacivert0,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const PaIkon(Icons.qr_code_scanner_rounded, boyut: 64, zemin: Color(0xFFEEECFC), renk: Marka.mor),
          const SizedBox(height: 14),
          Text(izin ? 'Kamera izni gerekli' : 'Kamera açılamadı', style: gosterim(21, renk: Marka.murekkep)),
          const SizedBox(height: 8),
          Text(
            izin ? 'QR okutmak için kameraya izin ver: Ayarlar › BamBumPOS Personel › Kamera.' : 'Kamera başka bir uygulama tarafından kullanılıyor olabilir.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF475569)),
          ),
          const SizedBox(height: 18),
          GradDugme(yazi: 'Tekrar dene', onTap: tekrar),
        ]),
      ),
    );
  }
}

/* ───────────────────────── Alttan pano ───────────────────────── */

class _Pano extends StatelessWidget {
  const _Pano({required this.veri, required this.kalan, required this.islem, required this.islemTur, required this.calistir, required this.yeniden});
  final Map<String, dynamic> veri;
  final int kalan;
  final String? islem;
  final String? islemTur;
  final Future<void> Function(String, [String?]) calistir;
  final VoidCallback yeniden;

  static String _sure(int dk) => dk < 60 ? '$dk dk' : '${dk ~/ 60} sa${dk % 60 > 0 ? ' ${dk % 60} dk' : ''}';

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final alt = MediaQuery.paddingOf(context).bottom;
    final kisi = veri['kisi'] as Map? ?? const {};
    final cihaz = veri['cihaz'] as Map? ?? const {};
    final durum = veri['durum'] as Map? ?? const {};
    final mola = veri['mola'] as Map? ?? const {};
    final eylemler = ((veri['eylemler'] as List?) ?? const []).map((e) => e.toString()).toList();
    final kilitli = veri['kilitli'] is Map ? Map<String, dynamic>.from(veri['kilitli'] as Map) : <String, dynamic>{};
    final calisiyor = durum['status'] == 'working';
    final molada = durum['on_break'] == true;
    final doldu = kalan <= 0;
    final kullanilan = (mola['kullanilan'] as num?)?.toInt() ?? 0;
    final hak = (mola['hak'] as num?)?.toInt() ?? 0;
    final kalanHak = (mola['kalan'] as num?)?.toInt() ?? 0;
    final asim = (mola['asim'] as num?)?.toInt() ?? 0;
    final calisilan = ((durum['entry'] as Map?)?['worked_min'] as num?)?.toInt() ?? 0;

    final kartlar = <_Kart>[];
    if (eylemler.contains('mesai_basla')) {
      kartlar.add(_Kart('mesai_basla', 'Mesaiye başla', 'Giriş ${DateFormat('HH:mm').format(DateTime.now())} · ${cihaz['ad'] ?? ''}', Icons.schedule_rounded, Marka.grad));
    }
    if (eylemler.contains('mola_bitir')) {
      final bas = DateTime.tryParse(durum['break_started_at']?.toString() ?? '')?.toLocal();
      final dk = bas == null ? 0 : DateTime.now().difference(bas).inMinutes;
      kartlar.add(_Kart('mola_bitir', 'Molayı bitir', '${_sure(dk)} süredir moladasın', Icons.check_rounded,
          const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF34D399), Color(0xFF0D9488), Color(0xFF115E59)])));
    }
    if (eylemler.contains('mola_basla')) {
      kartlar.add(_Kart('mola_basla', 'Molaya çık', kalanHak > 0 ? 'Kalan hakkın ${_sure(kalanHak)}' : 'Hak doldu · kayda geçer', Icons.coffee_rounded,
          const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA78BFA), Color(0xFF7C3AED), Color(0xFF5B21B6)]),
          tur: 'break'));
    }
    if (eylemler.contains('mesai_bitir')) {
      kartlar.add(_Kart('mesai_bitir', 'Mesaiyi bitir', 'Bugün ${_sure(calisilan)} çalıştın', Icons.logout_rounded,
          const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Marka.lacivert2, Marka.lacivert1, Marka.lacivert0]),
          kilit: kilitli['mesai_bitir']?.toString()));
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 520),
      curve: const Cubic(.22, 1, .36, 1),
      builder: (_, v, child) => Transform.translate(offset: Offset(0, 500 * v), child: child),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 560),
        padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + alt),
        decoration: BoxDecoration(
          color: r.kart,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: const [BoxShadow(color: Color(0x880D0B2B), blurRadius: 60, offset: Offset(0, -20))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: r.kenar, borderRadius: BorderRadius.circular(9)))),
          const SizedBox(height: 14),
          // Kişi satırı
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: Marka.grad, borderRadius: BorderRadius.circular(17)),
                child: Text((kisi['ad']?.toString() ?? '?').characters.first.toUpperCase(), style: gosterim(20, renk: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kisi['ad']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: gosterim(17, renk: r.metin)),
                  Text([cihaz['ad'], cihaz['sube']].whereType<Object>().join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: r.soluk)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: r.kart, borderRadius: BorderRadius.circular(20)),
                child: Text('$kullanilan dk / ${_sure(hak)}', style: gosterim(14, agirlik: FontWeight.w700, renk: asim > 0 ? Marka.gul : r.metin)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(shape: BoxShape.circle, color: !calisiyor ? r.silik : molada ? const Color(0xFF8B5CF6) : Marka.zumrut),
            ),
            const SizedBox(width: 8),
            Text(!calisiyor ? 'Mesaide değilsin' : molada ? 'Moladasın' : 'Mesaidesin',
                style: TextStyle(fontWeight: FontWeight.w700, color: !calisiyor ? r.soluk : molada ? const Color(0xFF7C3AED) : const Color(0xFF059669))),
            const Spacer(),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(value: (kalan / 40).clamp(0.0, 1.0), strokeWidth: 3, color: doldu ? Marka.gul : r.soluk, backgroundColor: r.kenar),
            ),
            const SizedBox(width: 8),
            Text(doldu ? 'QR süresi doldu' : '$kalan sn geçerli', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: doldu ? Marka.gul : r.soluk)),
          ]),
          const SizedBox(height: 12),
          for (var i = 0; i < kartlar.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < kartlar.length - 1 ? 10 : 0),
              child: Belir(
                gecikme: i * 70,
                child: _EylemKarti(
                  kart: kartlar[i],
                  ana: i == 0,
                  isleniyor: islem == kartlar[i].eylem && islemTur == kartlar[i].tur,
                  pasif: islem != null || doldu,
                  onTap: () => calistir(kartlar[i].eylem, kartlar[i].tur),
                ),
              ),
            ),
          if (eylemler.contains('mola_basla') && !doldu)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Belir(
                gecikme: 160,
                child: _KisaMola(isleniyor: islem == 'mola_basla' && islemTur == 'toilet', pasif: islem != null, onTap: () => calistir('mola_basla', 'toilet')),
              ),
            ),
          if (doldu)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: YumusakDugme(yazi: 'QR süresi doldu · yeniden okut', ikon: Icons.refresh_rounded, onTap: yeniden),
            ),
          if (asim > 0)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(color: Marka.gul.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
              child: Text('Mola hakkını ${_sure(asim)} aştın; kayda geçer.', textAlign: TextAlign.center, style: const TextStyle(color: Marka.gul, fontWeight: FontWeight.w600, fontSize: 12.5)),
            ),
        ]),
      ),
    );
  }
}

class _Kart {
  _Kart(this.eylem, this.baslik, this.alt, this.ikon, this.grad, {this.tur, this.kilit});
  final String eylem;
  final String baslik;
  final String alt;
  final IconData ikon;
  final Gradient grad;
  final String? tur;
  final String? kilit;
}

class _EylemKarti extends StatefulWidget {
  const _EylemKarti({required this.kart, required this.ana, required this.isleniyor, required this.pasif, required this.onTap});
  final _Kart kart;
  final bool ana;
  final bool isleniyor;
  final bool pasif;
  final VoidCallback onTap;
  @override
  State<_EylemKarti> createState() => _EylemKartiState();
}

class _EylemKartiState extends State<_EylemKarti> with TickerProviderStateMixin {
  late final _parilti = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();
  late final _halka = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  late final _serit = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(_EylemKarti o) {
    super.didUpdateWidget(o);
    if (widget.isleniyor && !_serit.isAnimating) _serit.repeat();
    if (!widget.isleniyor) _serit.stop();
  }

  @override
  void dispose() {
    _parilti.dispose();
    _halka.dispose();
    _serit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final k = widget.kart;
    final kilitli = k.kilit != null;
    final yuk = widget.ana ? 116.0 : 82.0;
    final disk = widget.ana ? 68.0 : 54.0;
    final icerik = Container(
      height: yuk,
      decoration: BoxDecoration(
        gradient: kilitli ? null : k.grad,
        color: kilitli ? r.ic : null,
        borderRadius: BorderRadius.circular(widget.ana ? 26 : 22),
        border: kilitli ? Border.all(color: r.kenar, width: 1.5) : null,
        boxShadow: kilitli ? null : const [BoxShadow(color: Color(0x880D0B2B), blurRadius: 34, offset: Offset(0, 18), spreadRadius: -20)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (!kilitli) ...[
          Positioned(right: -40, top: -40, child: Container(width: 140, height: 140, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white.withValues(alpha: .22), Colors.white.withValues(alpha: 0)])))),
          AnimatedBuilder(
            animation: _parilti,
            builder: (_, _) {
              final t = _parilti.value;
              final x = t < .6 ? -1.3 : -1.3 + (t - .6) / .25 * 2.6;
              return Positioned.fill(
                child: Transform.translate(
                  offset: Offset(x * 300, 0),
                  child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .25), Colors.white.withValues(alpha: 0)], stops: const [.35, .5, .65]))),
                ),
              );
            },
          ),
        ],
        if (widget.isleniyor)
          AnimatedBuilder(
            animation: _serit,
            builder: (_, _) => Positioned.fill(child: CustomPaint(painter: _SeritCizer(_serit.value, Colors.white.withValues(alpha: .14)))),
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.ana ? 18 : 14),
          child: Row(children: [
            SizedBox(
              width: disk + 12,
              height: disk + 12,
              child: Stack(alignment: Alignment.center, children: [
                if (widget.ana && !kilitli)
                  AnimatedBuilder(
                    animation: _halka,
                    builder: (_, _) {
                      final t = Curves.easeOut.transform(_halka.value);
                      return Opacity(
                        opacity: (1 - t) * .8,
                        child: Container(
                          width: disk + 12 * t,
                          height: disk + 12 * t,
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22 + 4 * t), border: Border.all(color: Colors.white.withValues(alpha: .5), width: 2)),
                        ),
                      );
                    },
                  ),
                Container(
                  width: disk,
                  height: disk,
                  decoration: BoxDecoration(
                    color: kilitli ? r.kart : Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(disk * .32),
                    border: kilitli ? null : Border.all(color: Colors.white.withValues(alpha: .2)),
                  ),
                  child: widget.isleniyor
                      ? const Center(child: Yukleyici(boyut: 26))
                      : Icon(kilitli ? Icons.lock_rounded : k.ikon, color: kilitli ? r.silik : Colors.white, size: widget.ana ? 32 : 25),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(k.baslik, style: gosterim(widget.ana ? 23 : 18.5, renk: kilitli ? r.soluk : Colors.white)),
                const SizedBox(height: 2),
                Text(widget.isleniyor ? 'Kaydediliyor…' : (k.kilit ?? k.alt),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: kilitli ? r.silik : Colors.white.withValues(alpha: .78))),
              ]),
            ),
            if (!kilitli)
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ),
          ]),
        ),
      ]),
    );
    return Basilir(onTap: kilitli || widget.pasif ? null : widget.onTap, olcek: .96, child: icerik);
  }
}

class _SeritCizer extends CustomPainter {
  _SeritCizer(this.t, this.renk);
  final double t;
  final Color renk;
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = renk;
    const g = 28.0;
    for (double x = -s.height - g + t * g * 2; x < s.width + s.height; x += g * 2) {
      c.drawPath(
        Path()
          ..moveTo(x, s.height)
          ..lineTo(x + g, s.height)
          ..lineTo(x + g + s.height * .5, 0)
          ..lineTo(x + s.height * .5, 0)
          ..close(),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_SeritCizer o) => o.t != t;
}

class _KisaMola extends StatelessWidget {
  const _KisaMola({required this.isleniyor, required this.pasif, required this.onTap});
  final bool isleniyor;
  final bool pasif;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Basilir(
      onTap: pasif ? null : onTap,
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: r.kart,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: r.kenar, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x331C1863), blurRadius: 22, offset: Offset(0, 10), spreadRadius: -14)],
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(15)),
            child: isleniyor ? const Center(child: Yukleyici(boyut: 22, renk: Color(0xFF0284C7))) : const Icon(Icons.water_drop_rounded, color: Color(0xFF0284C7)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Kısa mola', style: gosterim(16, renk: r.metin)),
              Text(isleniyor ? 'Kaydediliyor…' : 'Tuvalet · birkaç dakikalık ara', style: TextStyle(fontSize: 12, color: r.soluk)),
            ]),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: r.ic, shape: BoxShape.circle),
            child: Icon(Icons.arrow_forward_rounded, size: 17, color: r.soluk),
          ),
        ]),
      ),
    );
  }
}

/* ───────────────────────── Başarı ───────────────────────── */

class _Basari extends StatelessWidget {
  const _Basari({required this.veri});
  final Map<String, dynamic> veri;
  @override
  Widget build(BuildContext context) {
    final eylem = veri['eylem']?.toString();
    final grad = switch (eylem) {
      'mola_basla' => const LinearGradient(colors: [Color(0xFFC4B5FD), Color(0xFF7C3AED)]),
      'mesai_bitir' => const LinearGradient(colors: [Color(0xFF6EE7B7), Color(0xFF059669)]),
      _ => const LinearGradient(colors: [Color(0xFF7DD3FC), Marka.mavi]),
    };
    final cihaz = veri['cihaz'] as Map? ?? const {};
    return Container(
      color: const Color(0xEB0D0B2B),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(30),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 240,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            for (var i = 0; i < 18; i++) _Konfeti(i),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(gradient: grad, shape: BoxShape.circle, boxShadow: const [BoxShadow(color: Color(0x885443D2), blurRadius: 40, offset: Offset(0, 14))]),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: const Interval(.4, 1, curve: Curves.easeOut),
                  builder: (_, v, _) => CustomPaint(painter: _TikCizer(v)),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Belir(gecikme: 300, child: Text(veri['mesaj']?.toString() ?? 'Tamam', textAlign: TextAlign.center, style: gosterim(30, renk: Colors.white))),
        if (veri['alt'] != null)
          Belir(
            gecikme: 400,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(veri['alt'].toString(), textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: .7), fontSize: 15)),
            ),
          ),
        Belir(
          gecikme: 500,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text([cihaz['ad'], cihaz['sube']].whereType<Object>().join(' · '), style: TextStyle(color: Colors.white.withValues(alpha: .45), fontSize: 13)),
          ),
        ),
      ]),
    );
  }
}

class _TikCizer extends CustomPainter {
  _TikCizer(this.t);
  final double t;
  @override
  void paint(Canvas c, Size s) {
    final yol = Path()
      ..moveTo(s.width * .27, s.height * .52)
      ..lineTo(s.width * .44, s.height * .68)
      ..lineTo(s.width * .74, s.height * .36);
    final m = yol.computeMetrics().first;
    c.drawPath(
      m.extractPath(0, m.length * t),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_TikCizer o) => o.t != t;
}

class _Konfeti extends StatelessWidget {
  const _Konfeti(this.i);
  final int i;
  static const _renk = [Marka.mor, Marka.mavi, Marka.gok, Marka.lavanta, Color(0xFF34D399)];
  @override
  Widget build(BuildContext context) {
    final a = i / 18 * math.pi * 2;
    final r = 90.0 + (i % 3) * 22;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 1100 + (i % 4) * 60),
      curve: const Cubic(.22, 1, .36, 1),
      builder: (_, v, _) => Transform.translate(
        offset: Offset(math.cos(a) * r * v, math.sin(a) * r * v),
        child: Transform.rotate(
          angle: v * (i * 47 % 360) * math.pi / 180,
          child: Opacity(opacity: (1 - v).clamp(0, 1), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: _renk[i % 5], borderRadius: BorderRadius.circular(2)))),
        ),
      ),
    );
  }
}
