import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/hareket.dart';
import 'app/tema.dart';
import 'core/baslangic_log.dart';
import 'core/durum.dart';
import 'core/eski_windows.dart';
import 'ekranlar/acilis.dart';
import 'ekranlar/aktivasyon_ekrani.dart';
import 'ekranlar/bildirim_baloncuklari.dart';
import 'ekranlar/kabuk.dart';
import 'ekranlar/pin_ekrani.dart';
import 'ekranlar/ortak.dart';

// pos-win7 dalı: açılış adımları ve yakalanmamış her hata
// %LOCALAPPDATA%\BamBumPOS\logs\baslangic.log dosyasına yazılır
// (core/baslangic_log.dart; native taraf windows/runner/baslangic_log.cpp).
void main() {
  BaslangicLog.yaz('main() başladı · Dart ${Platform.version.split(' ').first} · ${Platform.operatingSystemVersion}');
  runZonedGuarded<Future<void>>(_baslat, (hata, iz) => BaslangicLog.hata('zone', hata, iz));
}

Future<void> _baslat() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onceki = FlutterError.onError;
  FlutterError.onError = (ayrinti) {
    BaslangicLog.hata('FlutterError', ayrinti.exception, ayrinti.stack);
    onceki?.call(ayrinti);
  };
  PlatformDispatcher.instance.onError = (hata, iz) {
    BaslangicLog.hata('PlatformDispatcher', hata, iz);
    return true;
  };
  BaslangicLog.yaz('Flutter bağlamı hazır (eski Windows: $eskiWindows)');

  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // POS tableti: sistem çubukları gizli, kaydırınca geçici görünür.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // Kasa/mutfak ekranı uykuya geçmesin.
    WakelockPlus.enable().catchError((Object e) => BaslangicLog.yaz('Ekran uyku kilidi açılamadı: $e'));

    await eskiWindowsHazirla();
    BaslangicLog.yaz('Sertifika ayarı tamam');
    // Tema tercihi ve durum kurulumu birbirini beklemez (açılış süresi).
    final tema = temaYukle();
    final durum = await UygulamaDurumu.kur();
    await tema;
    BaslangicLog.yaz('Uygulama durumu kuruldu (sürüm ${durum.surum}); arayüz başlıyor');
    runApp(BamBumPosUygulamasi(durum: durum));
    WidgetsBinding.instance.addPostFrameCallback((_) => BaslangicLog.yaz('İlk Flutter karesi çizildi — açılış tamam'));
    durum.baslat();
  } catch (hata, iz) {
    BaslangicLog.hata('açılış', hata, iz);
    runApp(_AcilisHatasi(hata: '$hata', gunluk: BaslangicLog.yol));
  }
}

/// Açılış tamamlanamadıysa boş/donuk pencere yerine neden + günlük yolu.
class _AcilisHatasi extends StatelessWidget {
  const _AcilisHatasi({required this.hata, this.gunluk});
  final String hata;
  final String? gunluk;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('BamBumPOS başlatılamadı', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SelectableText(hata, textAlign: TextAlign.center),
              if (gunluk != null) ...[
                const SizedBox(height: 12),
                SelectableText('Ayrıntılar: $gunluk', textAlign: TextAlign.center),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class BamBumPosUygulamasi extends StatefulWidget {
  const BamBumPosUygulamasi({super.key, required this.durum});
  final UygulamaDurumu durum;

  @override
  State<BamBumPosUygulamasi> createState() => _BamBumPosUygulamasiState();
}

class _BamBumPosUygulamasiState extends State<BamBumPosUygulamasi> {
  late final AppLifecycleListener _yasam;

  @override
  void initState() {
    super.initState();
    _yasam = AppLifecycleListener(onResume: widget.durum.onPlanaGeldi);
    HardwareKeyboard.instance.addHandler(_tus);
  }

  bool _tus(KeyEvent _) {
    widget.durum.etkinlik();
    return false;
  }

  @override
  void dispose() {
    _yasam.dispose();
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DurumKapsami(
      durum: widget.durum,
      child: ValueListenableBuilder<bool>(
        valueListenable: koyuTema,
        builder: (context, _, __) => MaterialApp(
          title: 'BamBumPOS',
          debugShowCheckedModeBanner: false,
          theme: temaKur(),
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // Bildirim baloncukları her ekranın (adisyon dahil) üstünde.
          // Dinleyici her dokunuşu "etkinlik" sayar (boşta kilit sayacı).
          builder: (context, child) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => widget.durum.etkinlik(),
            onPointerMove: (_) => widget.durum.etkinlik(),
            onPointerHover: (_) => widget.durum.etkinlik(),
            onPointerSignal: (_) => widget.durum.etkinlik(),
            child: Stack(children: [
              if (child case final bbDeger?) bbDeger,
              BildirimBaloncuklari(merkez: widget.durum.bildirim),
            ]),
          ),
          // Açılış perdesi bütün aşamaların üstünde oynar, oturum denetimi
          // bitince açılır; aşamalar arası geçiş asamaGecisi ile.
          home: ListenableBuilder(
            listenable: widget.durum,
            builder: (context, _) => AcilisKatmani(
              hazir: widget.durum.asama != Asama.acilis,
              surum: widget.durum.surum,
              child: AnimatedSwitcher(
              duration: Hareket.uzun,
              reverseDuration: Hareket.uzun,
              switchInCurve: Curves.linear,
              transitionBuilder: asamaGecisi,
              child: switch (widget.durum.asama) {
                Asama.acilis => ColoredBox(key: const ValueKey('acilis'), color: Renk.zemin, child: const SizedBox.expand()),
                Asama.baglantiYok => BaglantiBekleniyor(key: const ValueKey('baglanti'), mesaj: widget.durum.sonHata),
                Asama.aktivasyon => const AktivasyonEkrani(key: ValueKey('aktivasyon')),
                Asama.pin => const PinEkrani(key: ValueKey('pin')),
                // Cihaz/istasyon değişirse kabuk sıfırdan kurulsun.
                Asama.calisma => Kabuk(key: ValueKey('kabuk-${widget.durum.oturum?.cihazId}-${widget.durum.oturum?.istasyon}')),
              },
            ),
            ),
          ),
        ),
      ),
    );
  }
}
