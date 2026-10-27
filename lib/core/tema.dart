import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';

/// BamBumPOS Patron görsel kimliği: marka moru #5443D2 + kurumsal mavi
/// #2563EB + gök #38BDF8, gece laciverti #0E0B33. Köşeler 8 px (hap/oval yok).
/// Gövde Poppins; büyük rakamlar Plus Jakarta ("Jakarta"), sabit genişlikli.
class Marka {
  static const mor = Color(0xFF5443D2);
  static const morAcik = Color(0xFF6D5EF2);
  static const mavi = Color(0xFF2563EB);
  static const gok = Color(0xFF38BDF8);
  static const gece = Color(0xFF0E0B33);
  static const gece2 = Color(0xFF1C1863);
  static const gece3 = Color(0xFF2A3A9E);
  static const murekkep = Color(0xFF14123A);
  static const zumrut = Color(0xFF059669);
  static const zumrutAcik = Color(0xFF34D399);
  static const gul = Color(0xFFE11D48);
  static const gulAcik = Color(0xFFFB7185);
  static const kehribar = Color(0xFFD97706);
  static const kehribarAcik = Color(0xFFFBBF24);
  static const lavanta = Color(0xFFA78BFA);

  static const grad = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [morAcik, mor, mavi],
    stops: [0, .5, 1],
  );
  static const geceGrad = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [gece, gece2, gece3],
    stops: [0, .6, 1],
  );

  /// Grafik dizisi (sıralı kategoriler için): mor → mavi → gök → zümrüt → kehribar → lavanta.
  static const dizi = [mor, mavi, gok, Color(0xFF10B981), Color(0xFFF59E0B), lavanta, Color(0xFFEC4899), Color(0xFF64748B)];

  /// Standart köşe yarıçapı.
  static const kose = 8.0;
  static final yaricap = BorderRadius.circular(kose);
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
    required this.arti,
    required this.eksi,
    required this.uyari,
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
  final Color arti;
  final Color eksi;
  final Color uyari;
  final bool koyu;

  static const acik = PaRenk(
    zemin: Color(0xFFF4F5FB),
    kart: Colors.white,
    kenar: Color(0xFFE3E5F0),
    ic: Color(0xFFEEF0F8),
    metin: Color(0xFF0F172A),
    soluk: Color(0xFF475569),
    silik: Color(0xFF5B6478),
    birincil: Marka.mor,
    birincilYumusak: Color(0xFFEEECFC),
    arti: Color(0xFF047857),
    eksi: Color(0xFFBE123C),
    uyari: Color(0xFFB45309),
    koyu: false,
  );
  static const karanlik = PaRenk(
    zemin: Color(0xFF0B0A1F),
    kart: Color(0xFF15142E),
    kenar: Color(0xFF2A284F),
    ic: Color(0xFF1E1C44),
    metin: Color(0xFFF1F5F9),
    soluk: Color(0xFFC0C7D8),
    silik: Color(0xFF9AA2B8),
    birincil: Color(0xFFA59CF7),
    birincilYumusak: Color(0x425443D2),
    arti: Marka.zumrutAcik,
    eksi: Marka.gulAcik,
    uyari: Marka.kehribarAcik,
    koyu: true,
  );
}

extension PaTemaX on BuildContext {
  PaRenk get pa => Theme.of(this).brightness == Brightness.dark ? PaRenk.karanlik : PaRenk.acik;
}

/// Kullanıcının tema seçimi (sistem / açık / koyu).
final temaKipi = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Büyük rakam/başlık yazı stili (Plus Jakarta, değişken kalınlık, sabit genişlikli rakam).
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
  final sekil = RoundedRectangleBorder(borderRadius: Marka.yaricap);
  final dugmeSekli = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final temel = ThemeData(
    useMaterial3: true,
    brightness: parlaklik,
    fontFamily: 'Poppins',
    scaffoldBackgroundColor: r.zemin,
    colorScheme: ColorScheme.fromSeed(seedColor: Marka.mor, brightness: parlaklik).copyWith(
      primary: r.birincil,
      surface: r.kart,
    ),
    pageTransitionsTheme: posSayfaGecisleri(),
  );
  return temel.copyWith(
    textTheme: temel.textTheme.apply(bodyColor: r.metin, displayColor: r.metin),
    cardTheme: CardThemeData(shape: sekil, color: r.kart, elevation: 0),
    dialogTheme: DialogThemeData(shape: sekil, backgroundColor: r.kart),
    // Düğme köşeleri personel uygulamasıyla aynı (16 / metin 12) — bkz. ortak/dugme.dart
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: dugmeSekli, minimumSize: const Size(44, 50))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: dugmeSekli, minimumSize: const Size(44, 50))),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), minimumSize: const Size(44, 44))),
    chipTheme: temel.chipTheme.copyWith(shape: sekil),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Marka.kose))),
    ),
    datePickerTheme: DatePickerThemeData(
      shape: sekil,
      dayShape: WidgetStatePropertyAll(sekil),
      rangePickerShape: sekil,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: r.ic,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: Marka.yaricap, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: Marka.yaricap, borderSide: BorderSide(color: r.birincil, width: 2)),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: sekil),
  );
}

/// Lacivert yüzeylerin üstünde durum çubuğu simgeleri açık renk.
const durumCubuguAcikSimge = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

/// Ekranın üst zeminine göre durum çubuğu (saat/şarj/sinyal) ve Android
/// gezinme çubuğu simge renkleri. [koyuUst] = üstte lacivert kapak var.
/// iOS `statusBarBrightness` TERS anlamlıdır (zeminin parlaklığı).
SystemUiOverlayStyle durumStili({required bool koyuUst, required bool koyuTema}) => SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: koyuUst ? Brightness.light : Brightness.dark,
      statusBarBrightness: koyuUst ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: koyuTema ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

extension DurumStiliX on BuildContext {
  /// Açık temada koyu simge, koyu temada açık simge (üstte kapak yoksa).
  SystemUiOverlayStyle durumCubugu({bool koyuUst = false}) => durumStili(koyuUst: koyuUst || pa.koyu, koyuTema: pa.koyu);
}
