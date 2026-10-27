import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/durum.dart';
import '../core/konum.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// KONUM KAPISI — işletme mesai konum kuralını konsolda açtıysa
/// (hesap › mesai_konum.zorunlu) konum servisi açık ve izin verilmiş olmalı.
/// Değilse tam ekran, kapatılamayan bir kapı uygulamanın TÜM sayfalarının
/// üstünde durur (main.dart › builder; yalnız sistem pencereleri üstündedir).
///
/// - Yalnız kabuk açıkken (oturum varken) çalışır: Kabuk `etkin`i yönetir.
/// - Denetim ucuzdur ve izin penceresi AÇMAZ (Konum.izinDurumu); pencereyi
///   yalnız "Konum iznini ver" düğmesi açar.
/// - Uygulamaya her dönüşte yeniden bakar; izin verilince kendiliğinden kapanır.
/// - Kural kapalıysa / alan yoksa kapı hiç görünmez (konum QR anında istenir).
class KonumKapisi extends StatefulWidget {
  const KonumKapisi({super.key});

  /// Kabuk açık mı (oturumlu alan)? Giriş/eşleme ekranlarında kapı yok.
  static final etkin = ValueNotifier<bool>(false);

  /// İzin denetimi (testte sahte durum verilebilir).
  static Future<KonumDurum> Function() denetci = Konum.izinDurumu;

  @override
  State<KonumKapisi> createState() => _KonumKapisiState();
}

class _KonumKapisiState extends State<KonumKapisi> with WidgetsBindingObserver {
  KonumDurum? _durum; // null = bilinmiyor / kural kapalı
  bool _mesgul = false;
  int _tur = 0; // eski denetim sonucu yenisinin üstüne yazmasın

  bool get _acik => KonumKapisi.etkin.value && Uyg.konumZorunlu && _durum != null && _durum != KonumDurum.tamam;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    KonumKapisi.etkin.addListener(_degisti);
    Uyg.hesap.addListener(_degisti);
    _degisti();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    KonumKapisi.etkin.removeListener(_degisti);
    Uyg.hesap.removeListener(_degisti);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _degisti();
  }

  // Dinleyiciler build/dispose sırasında tetiklenebilir → bir sonraki mikro görevde.
  void _degisti() => scheduleMicrotask(_denetle);

  Future<void> _denetle() async {
    if (!mounted) return;
    final tur = ++_tur;
    if (!KonumKapisi.etkin.value || !Uyg.konumZorunlu) {
      if (_durum != null) setState(() => _durum = null);
      return;
    }
    final d = await KonumKapisi.denetci();
    if (!mounted || tur != _tur) return;
    if (d != _durum) {
      final onceAcik = _acik;
      setState(() => _durum = d);
      if (!onceAcik && _acik) FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Future<void> _izinVer() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      switch (_durum) {
        case KonumDurum.servisKapali:
          await Geolocator.openLocationSettings();
        case KonumDurum.kaliciRed:
          await Geolocator.openAppSettings();
        default:
          final bas = DateTime.now();
          final i = await Geolocator.requestPermission();
          // Pencere hiç açılmadan (kalıcı ret) hemen döndüyse ayarlara götür.
          if (i == LocationPermission.deniedForever && DateTime.now().difference(bas).inMilliseconds < 600) {
            await Geolocator.openAppSettings();
          }
      }
    } catch (_) {
      // Eklenti hatası: durum aşağıda yeniden okunur.
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
    await _denetle();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _acik ? _Kapi(key: const ValueKey('kapi'), durum: _durum!, mesgul: _mesgul, onIzin: _izinVer) : const SizedBox.shrink(key: ValueKey('yok')),
    );
  }
}

class _Kapi extends StatelessWidget {
  const _Kapi({super.key, required this.durum, required this.mesgul, required this.onIzin});
  final KonumDurum durum;
  final bool mesgul;
  final VoidCallback onIzin;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final mq = MediaQuery.of(context);
    final ust = mq.padding.top;
    final alt = mq.padding.bottom;
    final kisa = mq.size.height < 760;
    final isletme = Uyg.hesap.value?['isletme']?.toString();
    final yaricap = Uyg.konumYaricap;

    final (dugme, dugmeIkon, ipucu) = switch (durum) {
      KonumDurum.kaliciRed => (
        'Ayarlardan izin ver',
        Icons.settings_rounded,
        'Konum izni daha önce reddedildi. Ayarlar › Konum bölümünde "Uygulamayı kullanırken" seçeneğini seç, sonra uygulamaya dön.',
      ),
      KonumDurum.servisKapali => ('Konum servisini aç', Icons.location_on_rounded, 'Telefonunun konum servisi kapalı. Açtıktan sonra uygulamaya dön.'),
      _ => ('Konum iznini ver', Icons.my_location_rounded, 'Açılan pencerede "Uygulamayı kullanırken" seçeneğini seç.'),
    };

    final genis = mq.size.width >= 600;
    final icerik = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaKart(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'İşletmen mesai giriş-çıkışını konumla doğruluyor. Mesai ve mola QR\'ını okutabilmek için konum iznini açman gerekiyor.',
                style: TextStyle(color: r.metin, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: r.kenar),
              const SizedBox(height: 4),
              _Madde(
                ikon: Icons.qr_code_scanner_rounded,
                yazi: yaricap != null && yaricap > 0 ? 'Mesai QR\'ını işletmenin yaklaşık $yaricap m yakınında okutabilirsin.' : 'Mesai QR\'ını yalnız işletmedeyken okutabilirsin.',
              ),
              const _Madde(ikon: Icons.touch_app_rounded, yazi: 'Konumun yalnız QR okuttuğun anda kontrol edilir.'),
              const _Madde(ikon: Icons.shield_rounded, yazi: 'Sürekli takip edilmez; arka planda konum alınmaz.', guvence: true),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(durum == KonumDurum.izinYok ? Icons.info_outline_rounded : Icons.error_outline_rounded, size: 18, color: durum == KonumDurum.izinYok ? r.soluk : Marka.kehribar),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(ipucu, style: TextStyle(fontSize: 12.5, height: 1.4, color: r.soluk)),
              ),
            ],
          ),
        ),
      ],
    );
    final eylem = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GradDugme(yazi: dugme, ikon: dugmeIkon, yukleniyor: mesgul, onTap: onIzin),
        const SizedBox(height: 10),
        Text(
          durum == KonumDurum.servisKapali ? 'Konumu açtığında bu ekran kendiliğinden kapanır.' : 'İzin verdiğinde bu ekran kendiliğinden kapanır.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: r.silik),
        ),
      ],
    );

    return BlockSemantics(
      child: Material(
        color: r.zemin,
        child: AnnotatedRegion(
          value: durumCubugu,
          child: Column(
            children: [
              Aurora(
                child: SizedBox(
                  width: double.infinity,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, ust + (kisa ? 10 : 22), 24, kisa ? 40 : 50),
                    child: Column(
                      children: [
                        _Nabiz(boyut: kisa ? 64 : 76),
                        SizedBox(height: kisa ? 10 : 14),
                        Text(
                          'Konum izni gerekli',
                          textAlign: TextAlign.center,
                          style: gosterim(kisa ? 22 : 25, renk: Colors.white),
                        ),
                        if (isletme != null && isletme.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            isletme,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: .65)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: r.zemin,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: genis
                        // Tablet: düğme içeriğin hemen altında (ekranın dibinde boşluk kalmasın).
                        ? LayoutBuilder(
                            builder: (_, k) => SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 48 + alt),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: (k.maxHeight - 72 - alt).clamp(0, double.infinity)),
                                child: Align(
                                  alignment: const Alignment(0, -.35),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 520),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [icerik, const SizedBox(height: 24), eylem]),
                                  ),
                                ),
                              ),
                            ),
                          )
                        // Telefon: içerik kayar, düğme başparmak erimindeki altta sabit.
                        : Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: icerik),
                              ),
                              Padding(
                                // Kap 24 px yukarı kaydırıldığı için alttaki pay zaten 24 px büyük.
                                padding: EdgeInsets.fromLTRB(16, 8, 16, alt > 0 ? alt : 16),
                                child: eylem,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Madde extends StatelessWidget {
  const _Madde({required this.ikon, required this.yazi, this.guvence = false});
  final IconData ikon;
  final String yazi;
  final bool guvence;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final yesil = r.koyu ? const Color(0xFF6EE7B7) : const Color(0xFF047857);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          guvence ? PaIkon(ikon, boyut: 34, zemin: Marka.zumrut.withValues(alpha: .12), renk: yesil) : PaIkon(ikon, boyut: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              yazi,
              style: TextStyle(fontSize: 13, height: 1.4, color: guvence ? yesil : r.soluk, fontWeight: guvence ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nefes alan halkalı konum simgesi (QR düğmesiyle aynı dil).
class _Nabiz extends StatefulWidget {
  const _Nabiz({required this.boyut});
  final double boyut;
  @override
  State<_Nabiz> createState() => _NabizState();
}

class _NabizState extends State<_Nabiz> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.boyut;
    return SizedBox(
      width: d + 28,
      height: d + 28,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = Curves.easeOut.transform(_c.value);
              return Opacity(
                opacity: (1 - t) * .6,
                child: Container(
                  width: d + 28 * t,
                  height: d + 28 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: .7), width: 2),
                  ),
                ),
              );
            },
          ),
          Container(
            width: d,
            height: d,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: Marka.grad,
              boxShadow: [BoxShadow(color: Color(0x995443D2), blurRadius: 28, offset: Offset(0, 6), spreadRadius: -2)],
            ),
            child: Icon(Icons.location_on_rounded, color: Colors.white, size: d * .44),
          ),
        ],
      ),
    );
  }
}
