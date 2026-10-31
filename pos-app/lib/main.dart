import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/hareket.dart';
import 'app/tema.dart';
import 'core/durum.dart';
import 'core/eski_windows.dart';
import 'core/gezgin_temizleyici.dart';
import 'ekranlar/acilis.dart';
import 'ekranlar/aktivasyon_ekrani.dart';
import 'ekranlar/bildirim_baloncuklari.dart';
import 'ekranlar/kabuk.dart';
import 'ekranlar/pin_ekrani.dart';
import 'ekranlar/ortak.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.android) {
    // POS tableti: sistem çubukları gizli, kaydırınca geçici görünür.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  // Kasa/mutfak ekranı uykuya geçmesin.
  WakelockPlus.enable().ignore();

  await eskiWindowsHazirla();
  // Tema tercihi ve durum kurulumu birbirini beklemez (açılış süresi).
  final tema = temaYukle();
  final durum = await UygulamaDurumu.kur();
  await tema;
  runApp(BamBumPosUygulamasi(durum: durum));
  durum.baslat();
}

class BamBumPosUygulamasi extends StatefulWidget {
  const BamBumPosUygulamasi({super.key, required this.durum});
  final UygulamaDurumu durum;

  @override
  State<BamBumPosUygulamasi> createState() => _BamBumPosUygulamasiState();
}

class _BamBumPosUygulamasiState extends State<BamBumPosUygulamasi> {
  late final AppLifecycleListener _yasam;
  final _gezgin = GlobalKey<NavigatorState>();
  late final GezginTemizleyici _temizleyici;

  @override
  void initState() {
    super.initState();
    _temizleyici = GezginTemizleyici(
      dinle: widget.durum,
      calismada: () => widget.durum.asama == Asama.calisma,
      gezgin: _gezgin,
    );
    _yasam = AppLifecycleListener(
      onResume: widget.durum.onPlanaGeldi,
      // ÇEREZLER DİSKE (2026-10-30): arka plana geçerken / kapanırken bekleyen
      // çerez yazmaları bitirilir (yazma zaten atomik; bu son durumu da korur).
      onHide: _diskeYaz,
      onPause: _diskeYaz,
      onDetach: _diskeYaz,
      // Masaüstü: pencere kapatılınca önce yazmalar biter, sonra çıkılır (en çok 2 sn).
      onExitRequested: () async {
        try {
          await widget.durum.api.diskeYaz().timeout(const Duration(seconds: 2));
        } catch (_) {}
        return AppExitResponse.exit;
      },
    );
    HardwareKeyboard.instance.addHandler(_tus);
  }

  void _diskeYaz() => widget.durum.api.diskeYaz().ignore();

  bool _tus(KeyEvent _) {
    widget.durum.etkinlik();
    return false;
  }

  @override
  void dispose() {
    _yasam.dispose();
    _temizleyici.dispose();
    HardwareKeyboard.instance.removeHandler(_tus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DurumKapsami(
      durum: widget.durum,
      child: ValueListenableBuilder<bool>(
        valueListenable: koyuTema,
        builder: (context, _, _) => MaterialApp(
          navigatorKey: _gezgin,
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
              ?child,
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
