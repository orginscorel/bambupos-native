import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/bildirim.dart';
import 'core/durum.dart';
import 'core/tema.dart';
import 'ekranlar/acilis.dart';
import 'ortak/ortak.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(durumCubugu);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initializeDateFormatting('tr_TR');
  await Uyg.kur();
  await BildirimMerkezi.kur();
  runApp(const PersonelUygulamasi());
}

class PersonelUygulamasi extends StatelessWidget {
  const PersonelUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: temaKipi,
      builder: (_, kip, _) => MaterialApp(
        title: 'BamBumPOS Personel',
        debugShowCheckedModeBanner: false,
        navigatorKey: Uyg.navigator,
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
        builder: (context, child) => Overlay(initialEntries: [
          OverlayEntry(builder: (ctx) {
            bildirimKatmani(Overlay.of(ctx));
            return MediaQuery(
              // Büyük sistem yazı boyutunda düzen bozulmasın (en çok 1.25x).
              data: MediaQuery.of(ctx).copyWith(
                textScaler: MediaQuery.of(ctx).textScaler.clamp(maxScaleFactor: 1.25),
              ),
              child: child!,
            );
          }),
        ]),
        home: const AcilisEkrani(),
      ),
    );
  }
}
