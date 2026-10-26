import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// BamBumPOS Personel görsel kimliği — web (personel.bambumpos.com) ile aynı:
/// marka moru #5443D2 + kurumsal mavi #2563EB + gök #38BDF8; gece laciverti
/// üst alan; gövde Poppins, büyük rakam/başlık Plus Jakarta ("Jakarta").
class Marka {
  static const mor = Color(0xFF5443D2);
  static const morAcik = Color(0xFF6D5EF2);
  static const mavi = Color(0xFF2563EB);
  static const gok = Color(0xFF38BDF8);
  static const lacivert0 = Color(0xFF0D0B2B);
  static const lacivert1 = Color(0xFF1C1863);
  static const lacivert2 = Color(0xFF2A3A9E);
  static const murekkep = Color(0xFF14123A);
  static const zumrut = Color(0xFF10B981);
  static const lavanta = Color(0xFFA78BFA);
  static const gul = Color(0xFFE11D48);
  static const kehribar = Color(0xFFF59E0B);

  static const grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [morAcik, mor, mavi],
    stops: [0, .45, 1],
  );
  static const hero = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [lacivert0, lacivert1, lacivert2],
    stops: [0, .55, 1],
  );
  static const kart = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lacivert1, lacivert2, mavi],
    stops: [0, .6, 1],
  );
}

/// Açık/koyu temaya göre yüzey renkleri: `context.pa.kart` gibi.
class PaRenk {
  const PaRenk({
    required this.zemin,
    required this.kart,
    required this.kenar,
    required this.ic,
    required this.metin,
    required this.soluk,
    required this.silik,
    required this.birincil,
    required this.birincilYumusak,
    required this.koyu,
  });

  final Color zemin;
  final Color kart;
  final Color kenar;
  final Color ic;
  final Color metin;
  final Color soluk;
  final Color silik;
  final Color birincil;
  final Color birincilYumusak;
  final bool koyu;

  static const acik = PaRenk(
    zemin: Color(0xFFF4F5FB),
    kart: Colors.white,
    kenar: Color(0xFFE7E8F3),
    ic: Color(0xFFEEF0F8),
    metin: Color(0xFF0F172A),
    soluk: Color(0xFF475569),
    silik: Color(0xFF64748B),
    birincil: Marka.mor,
    birincilYumusak: Color(0xFFEEECFC),
    koyu: false,
  );
  static const karanlik = PaRenk(
    zemin: Color(0xFF0B0A1F),
    kart: Color(0xFF15142E),
    kenar: Color(0xFF26244A),
    ic: Color(0xFF1E1C44),
    metin: Color(0xFFF1F5F9),
    soluk: Color(0xFFB4BCD0),
    silik: Color(0xFF8B93AB),
    birincil: Color(0xFFA59CF7),
    birincilYumusak: Color(0x425443D2),
    koyu: true,
  );

  List<BoxShadow> get golge => koyu
      ? const [BoxShadow(color: Color(0xB3000000), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -16)]
      : const [BoxShadow(color: Color(0x591C1863), blurRadius: 32, offset: Offset(0, 12), spreadRadius: -20)];
}

extension PaTemaX on BuildContext {
  PaRenk get pa => Theme.of(this).brightness == Brightness.dark ? PaRenk.karanlik : PaRenk.acik;
}

/// Kullanıcının tema seçimi (sistem / açık / koyu) — profil ekranından değişir.
final temaKipi = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Büyük rakam/başlık yazı stili (Plus Jakarta, değişken kalınlık).
TextStyle gosterim(double boyut, {FontWeight agirlik = FontWeight.w800, Color? renk, double? satir}) => TextStyle(
      fontFamily: 'Jakarta',
      fontSize: boyut,
      fontWeight: agirlik,
      fontVariations: [FontVariation('wght', agirlik.value.toDouble())],
      letterSpacing: -0.02 * boyut,
      height: satir,
      color: renk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData temaKur(Brightness parlaklik) {
  final r = parlaklik == Brightness.dark ? PaRenk.karanlik : PaRenk.acik;
  final temel = ThemeData(
    useMaterial3: true,
    brightness: parlaklik,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: r.zemin,
    colorScheme: ColorScheme.fromSeed(seedColor: Marka.mor, brightness: parlaklik).copyWith(
      primary: r.koyu ? Marka.morAcik : Marka.mor,
      surface: r.kart,
    ),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
  return temel.copyWith(
    textTheme: temel.textTheme.apply(bodyColor: r.metin, displayColor: r.metin),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: r.ic,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: r.birincil, width: 2),
      ),
      labelStyle: TextStyle(color: r.soluk, fontWeight: FontWeight.w500),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Durum çubuğu simgeleri: lacivert üst alanın üstünde hep açık renk.
const durumCubugu = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);
