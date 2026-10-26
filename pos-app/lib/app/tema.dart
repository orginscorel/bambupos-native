import 'package:flutter/material.dart';

/// BamBumPOS tasarım dili: marka moru, 8 px köşe, hap/oval yok.
abstract final class Renk {
  static const marka = Color(0xFF5443D2);
  static const markaKoyu = Color(0xFF3B2DB0);
  static const markaAcik = Color(0xFFEEEBFC);
  static const zemin = Color(0xFFF4F5F8);
  static const yuzey = Colors.white;
  static const cizgi = Color(0xFFE3E5EC);
  static const yazi = Color(0xFF1C1D26);
  static const soluk = Color(0xFF6B6F80);
  static const basari = Color(0xFF15A34A);
  static const uyari = Color(0xFFE38A06);
  static const hata = Color(0xFFDC2F2F);
  static const bilgi = Color(0xFF2563EB);
}

const kose = 8.0;
final koseYuvarlak = BorderRadius.circular(kose);

/// [yaziTipi] yalnız testte verilir; cihazda sistem yazı tipi kullanılır
/// (Android Roboto, iOS/macOS SF, Windows Segoe UI) — ek indirme yok.
ThemeData temaKur({String? yaziTipi}) {
  final sema = ColorScheme.fromSeed(
    seedColor: Renk.marka,
    primary: Renk.marka,
    surface: Renk.yuzey,
    error: Renk.hata,
  );

  final sekil = RoundedRectangleBorder(borderRadius: koseYuvarlak);

  return ThemeData(
    useMaterial3: true,
    fontFamily: yaziTipi,
    colorScheme: sema,
    scaffoldBackgroundColor: Renk.zemin,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Renk.yuzey,
      foregroundColor: Renk.yazi,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: yaziTipi, fontSize: 17, fontWeight: FontWeight.w700, color: Renk.yazi),
    ),
    cardTheme: CardThemeData(
      color: Renk.yuzey,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: const BorderSide(color: Renk.cizgi)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: sekil,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: sekil,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: Renk.cizgi),
        foregroundColor: Renk.yazi,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: sekil)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: sekil)),
    chipTheme: ChipThemeData(shape: sekil, side: const BorderSide(color: Renk.cizgi)),
    dialogTheme: DialogThemeData(shape: sekil, backgroundColor: Renk.yuzey),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(kose))),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: sekil),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Renk.yuzey,
      isDense: true,
      border: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: const BorderSide(color: Renk.cizgi)),
      enabledBorder: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: const BorderSide(color: Renk.cizgi)),
    ),
    dividerTheme: const DividerThemeData(color: Renk.cizgi, space: 1, thickness: 1),
  );
}
