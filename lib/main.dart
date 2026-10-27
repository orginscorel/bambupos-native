import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/demo_veri.dart';
import 'core/durum.dart';
import 'core/tema.dart';
import 'ekranlar/acilis.dart';
import 'ekranlar/kabuk.dart';
import 'ortak/ortak.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge: durum ve gezinme çubukları şeffaf; simge rengini her
  // ekran AnnotatedRegion ile üst zeminine göre seçer.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(durumCubuguAcikSimge);
  Intl.defaultLocale = 'tr_TR';
  await initializeDateFormatting('tr_TR');
  if (demoKipi) {
    // DEMO: eşleme/oturum yok; bütün uçlar sentetik veriden (lib/core/demo_veri.dart).
    final p = await SharedPreferences.getInstance();
    await p.setString('ad', demoPatronAdi);
    await Uyg.kur(p: p, hazirApi: Api.bellekte(DemoSunucu()));
    runApp(const PatronUygulamasi(ana: Kabuk()));
    return;
  }
  await Uyg.kur();
  Uyg.api.oturumDustu = oturumDustu;
  runApp(const PatronUygulamasi());
}

class PatronUygulamasi extends StatelessWidget {
  const PatronUygulamasi({super.key, this.ana = const AcilisEkrani()});

  /// Testlerde farklı açılış ekranı verilebilir.
  final Widget ana;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: temaKipi,
      builder: (_, kip, _) => MaterialApp(
        title: 'BamBumPOS Patron',
        debugShowCheckedModeBanner: false,
        navigatorKey: Uyg.navigator,
        scaffoldMessengerKey: mesajci,
        themeMode: kip,
        theme: temaKur(Brightness.light),
        darkTheme: temaKur(Brightness.dark),
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Büyük sistem yazı boyutunda düzen bozulmasın (en çok 1,3x).
        builder: (context, child) {
          final icerik = MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.of(context).textScaler.clamp(maxScaleFactor: 1.3)),
            child: child!,
          );
          return demoKipi && kIsWeb ? TelefonCercevesi(child: icerik) : icerik;
        },
        home: ana,
      ),
    );
  }
}

/// Yalnız DEMO + web: geniş ekranda uygulamayı ~430 px telefon çerçevesinde
/// ortalar (dar ekranda/telefonda tam ekran). Çerçeve içi MediaQuery telefon
/// boyutunu ve 44 px durum çubuğu payını bildirir.
class TelefonCercevesi extends StatelessWidget {
  const TelefonCercevesi({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width < 600) return child;
    final h = (mq.size.height - 48).clamp(560.0, 900.0);
    const w = 414.0;
    return ColoredBox(
      color: Marka.gece,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mq.size.width > 980)
              Padding(
                padding: const EdgeInsets.only(right: 48),
                child: SizedBox(
                  width: 260,
                  child: DefaultTextStyle(
                    style: const TextStyle(decoration: TextDecoration.none, fontFamily: 'Poppins'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BamBumPOS Patron', style: gosterim(26, renk: Colors.white)),
                        const SizedBox(height: 8),
                        Text(
                          'Önizleme · örnek kafe verisiyle çalışır. Görev, vardiya ve izin eylemleri yalnız bu tarayıcıda, bellekte denenir.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                            fontSize: 13.5,
                            height: 1.5,
                            fontFamily: 'Poppins',
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Container(
              width: w + 16,
              height: h + 16,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF05041A),
                borderRadius: BorderRadius.circular(Marka.kose * 4),
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
                boxShadow: const [BoxShadow(color: Color(0x885443D2), blurRadius: 60, spreadRadius: -10, offset: Offset(0, 20))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Marka.kose * 3),
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(w, h),
                    padding: const EdgeInsets.only(top: 24, bottom: 8),
                    viewPadding: const EdgeInsets.only(top: 24, bottom: 8),
                  ),
                  child: SizedBox(width: w, height: h, child: child),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
