import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/durum.dart';
import 'core/tema.dart';
import 'ekranlar/acilis.dart';
import 'ortak/ortak.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(durumCubuguAcikSimge);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  Intl.defaultLocale = 'tr_TR';
  await initializeDateFormatting('tr_TR');
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.of(context).textScaler.clamp(maxScaleFactor: 1.3)),
          child: child!,
        ),
        home: ana,
      ),
    );
  }
}
