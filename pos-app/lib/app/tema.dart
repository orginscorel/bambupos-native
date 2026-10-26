import 'package:flutter/material.dart';

/// Web paneliyle (resources/css/app.css) BİREBİR aynı ölçüler.
/// Renk adları web'deki --ui-* değişkenlerine karşılık gelir; yeni renk
/// uydurulmaz. Logo moru yalnız marka işaretinde kullanılır.
abstract final class Renk {
  // --ui-primary (#1d4ed8) · --ui-accent (#2563eb) · --ui-primary-soft
  static const marka = Color(0xFF1D4ED8);
  static const markaKoyu = Color(0xFF1E40AF);
  static const vurgu = Color(0xFF2563EB);
  static const markaAcik = Color(0xFFEFF6FF);
  static const markaKenar = Color(0xFFBFDBFE);

  /// Logo karesi ve "POS" yazısı (marka işareti).
  static const logo = Color(0xFF5443D2);

  // Yüzeyler
  static const yuzey = Color(0xFFFFFFFF); // --ui-surface / raised
  static const zemin = Color(0xFFF6F8FB); // --ui-surface-alt
  static const ic = Color(0xFFF1F5F9); // --ui-surface-inset
  static const cizgi = Color(0xFFE5EAF1); // --ui-border
  static const cizgiKoyu = Color(0xFFD3DBE6); // --ui-border-strong

  // Metin
  static const yazi = Color(0xFF0F172A); // --ui-text
  static const ikinci = Color(0xFF475569); // --ui-text-muted
  static const soluk = Color(0xFF64748B); // --ui-text-subtle

  // Durum (yazı · zemin · kenar)
  static const basari = Color(0xFF15803D);
  static const basariZemin = Color(0xFFF0FDF4);
  static const basariKenar = Color(0xFFBBF7D0);
  static const uyari = Color(0xFFB45309);
  static const uyariZemin = Color(0xFFFFFBEB);
  static const uyariKenar = Color(0xFFFDE68A);
  static const hata = Color(0xFFDC2626);
  static const hataZemin = Color(0xFFFEF2F2);
  static const hataKenar = Color(0xFFFECACA);
  static const bilgi = Color(0xFF0284C7);
  static const bilgiZemin = Color(0xFFE0F2FE);
  static const bilgiKenar = Color(0xFFBAE6FD);
}

/// --radius-md (buton, input) ve --radius-lg (kart).
const kose = 8.0;
const kartKose = 12.0;
final koseYuvarlak = BorderRadius.circular(kose);
final kartYuvarlak = BorderRadius.circular(kartKose);

/// --shadow-card
const kartGolge = [BoxShadow(color: Color(0x0D1C1917), blurRadius: 2, offset: Offset(0, 1))];

const yaziTipi = 'Poppins';

ThemeData temaKur({String? yaziTipiAdi}) {
  final ad = yaziTipiAdi ?? yaziTipi;
  final sema = ColorScheme.fromSeed(
    seedColor: Renk.marka,
    primary: Renk.marka,
    surface: Renk.yuzey,
    error: Renk.hata,
  );

  final sekil = RoundedRectangleBorder(borderRadius: koseYuvarlak);
  const govde = TextStyle(color: Renk.yazi);

  return ThemeData(
    useMaterial3: true,
    fontFamily: ad,
    colorScheme: sema,
    scaffoldBackgroundColor: Renk.zemin,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    textTheme: Typography.blackMountainView.apply(fontFamily: ad, bodyColor: Renk.yazi, displayColor: Renk.yazi),
    appBarTheme: AppBarTheme(
      backgroundColor: Renk.yuzey,
      foregroundColor: Renk.yazi,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: govde.copyWith(fontFamily: ad, fontSize: 17, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: Renk.yuzey,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: kartYuvarlak, side: const BorderSide(color: Renk.cizgi)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: sekil,
        backgroundColor: Renk.marka,
        disabledBackgroundColor: const Color(0xFFAEB5EC),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: TextStyle(fontFamily: ad, fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: sekil,
        minimumSize: const Size(44, 40),
        side: const BorderSide(color: Renk.cizgi),
        foregroundColor: Renk.yazi,
        backgroundColor: Renk.yuzey,
        textStyle: TextStyle(fontFamily: ad, fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: sekil, foregroundColor: Renk.marka, textStyle: TextStyle(fontFamily: ad, fontWeight: FontWeight.w600)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: sekil, foregroundColor: Renk.ikinci)),
    chipTheme: ChipThemeData(shape: sekil, side: const BorderSide(color: Renk.cizgi), labelStyle: TextStyle(fontFamily: ad, fontSize: 13)),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: Renk.yuzey),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: sekil),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Renk.yuzey,
      isDense: true,
      hintStyle: const TextStyle(color: Renk.soluk),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: const BorderSide(color: Renk.cizgiKoyu)),
      enabledBorder: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: const BorderSide(color: Renk.cizgiKoyu)),
      focusedBorder: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: const BorderSide(color: Renk.vurgu, width: 1.5)),
    ),
    dividerTheme: const DividerThemeData(color: Renk.cizgi, space: 1, thickness: 1),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
  );
}

/// Web'deki küçük rozet (b-green, b-slate …): yumuşak zemin + kenar + koyu yazı.
class Rozet extends StatelessWidget {
  const Rozet(this.metin, {super.key, this.renk = Renk.soluk, this.zemin, this.kenar, this.ikon, this.dolu = false, this.buyuk = false});
  final String metin;
  final Color renk;
  final Color? zemin;
  final Color? kenar;
  final IconData? ikon;
  final bool dolu;
  final bool buyuk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: buyuk ? 10 : 7, vertical: buyuk ? 4 : 2),
      decoration: BoxDecoration(
        color: dolu ? renk : (zemin ?? renk.withValues(alpha: .08)),
        borderRadius: BorderRadius.circular(999),
        border: dolu ? null : Border.all(color: kenar ?? renk.withValues(alpha: .25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ikon != null) ...[Icon(ikon, size: buyuk ? 14 : 12, color: dolu ? Colors.white : renk), const SizedBox(width: 4)],
        Text(metin,
            style: TextStyle(
                fontSize: buyuk ? 12.5 : 11.5, fontWeight: FontWeight.w600, color: dolu ? Colors.white : renk, height: 1.2)),
      ]),
    );
  }
}
