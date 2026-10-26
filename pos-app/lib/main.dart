import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app/tema.dart';
import 'core/durum.dart';
import 'ekranlar/aktivasyon_ekrani.dart';
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

  final durum = await UygulamaDurumu.kur();
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

  @override
  void initState() {
    super.initState();
    _yasam = AppLifecycleListener(onResume: widget.durum.onPlanaGeldi);
  }

  @override
  void dispose() {
    _yasam.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DurumKapsami(
      durum: widget.durum,
      child: MaterialApp(
        title: 'BamBumPOS',
        debugShowCheckedModeBanner: false,
        theme: temaKur(),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ListenableBuilder(
          listenable: widget.durum,
          builder: (context, _) => AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: switch (widget.durum.asama) {
              Asama.acilis => const AcilisEkrani(key: ValueKey('acilis')),
              Asama.baglantiYok => BaglantiBekleniyor(key: const ValueKey('baglanti'), mesaj: widget.durum.sonHata),
              Asama.aktivasyon => const AktivasyonEkrani(key: ValueKey('aktivasyon')),
              Asama.pin => const PinEkrani(key: ValueKey('pin')),
              // Cihaz/istasyon değişirse kabuk sıfırdan kurulsun.
              Asama.calisma => Kabuk(key: ValueKey('kabuk-${widget.durum.oturum?.cihazId}-${widget.durum.oturum?.istasyon}')),
            },
          ),
        ),
      ),
    );
  }
}
