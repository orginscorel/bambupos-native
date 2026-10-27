import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hareket.dart';

/// Koyu / açık tema anahtarı (web: `<html data-theme>`, localStorage `theme`).
/// Değişince kök uygulama bütün ağacı yeniden çizer; renkler aşağıdaki
/// getter'lardan okunduğu için ekran durumu (açık adisyon vb.) kaybolmaz.
final koyuTema = ValueNotifier<bool>(false);
bool get _k => koyuTema.value;

const _temaAnahtari = 'tema'; // web localStorage `theme` ile aynı anlam: 'dark' | 'light'

/// Açılışta kayıtlı tercihi yükler (yoksa açık tema).
Future<void> temaYukle() async {
  try {
    koyuTema.value = (await SharedPreferences.getInstance()).getString(_temaAnahtari) == 'dark';
  } catch (_) {
    // Tercih okunamazsa açık tema.
  }
}

/// Temayı değiştirir; bütün ekranlar yeniden çizilir, durum korunur.
void temaDegistir() {
  koyuTema.value = !koyuTema.value;
  SharedPreferences.getInstance().then((p) => p.setString(_temaAnahtari, koyuTema.value ? 'dark' : 'light')).ignore();
  void yenile(Element e) {
    e.markNeedsBuild();
    e.visitChildren(yenile);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(yenile);
}

/// Web paneliyle (resources/css/app.css) BİREBİR aynı ölçüler.
/// Renk adları web'deki --ui-* değişkenlerine karşılık gelir; yeni renk
/// uydurulmaz. Koyu değerler app.css `[data-theme='dark']` bloğundan.
/// Logo moru yalnız marka işaretinde kullanılır.
abstract final class Renk {
  // --ui-primary · --ui-accent · --ui-primary-soft
  static Color get marka => _k ? const Color(0xFF2563EB) : const Color(0xFF1D4ED8);
  static Color get markaKoyu => _k ? const Color(0xFF1D4ED8) : const Color(0xFF1E40AF);
  static Color get vurgu => _k ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
  static Color get markaAcik => _k ? const Color(0x2E2563EB) : const Color(0xFFEFF6FF);
  static Color get markaKenar => _k ? const Color(0x522563EB) : const Color(0xFFBFDBFE);

  /// Logo karesi ve "POS" yazısı (marka işareti).
  static const logo = Color(0xFF5443D2);

  // Yüzeyler
  static Color get yuzey => _k ? const Color(0xFF151E33) : const Color(0xFFFFFFFF); // --ui-surface-raised
  static Color get zemin => _k ? const Color(0xFF0B1120) : const Color(0xFFF6F8FB); // --ui-surface-alt
  static Color get ic => _k ? const Color(0xFF1C2740) : const Color(0xFFF1F5F9); // --ui-surface-inset
  static Color get cizgi => _k ? const Color(0xFF26314A) : const Color(0xFFE5EAF1); // --ui-border
  static Color get cizgiKoyu => _k ? const Color(0xFF35425F) : const Color(0xFFD3DBE6); // --ui-border-strong

  // Metin
  static Color get yazi => _k ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A); // --ui-text
  static Color get ikinci => _k ? const Color(0xFFC2CBDA) : const Color(0xFF475569); // --ui-text-muted
  static Color get soluk => _k ? const Color(0xFF8A97AC) : const Color(0xFF64748B); // --ui-text-subtle

  /// Dolu durum rozetinin üstündeki yazı (--ui-on-status).
  static Color get durumUstu => _k ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

  // Durum (yazı · zemin · kenar)
  static Color get basari => _k ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
  static Color get basariZemin => _k ? const Color(0x1F4ADE80) : const Color(0xFFF0FDF4);
  static Color get basariKenar => _k ? const Color(0x524ADE80) : const Color(0xFFBBF7D0);
  static Color get uyari => _k ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
  static Color get uyariZemin => _k ? const Color(0x1FFBBF24) : const Color(0xFFFFFBEB);
  static Color get uyariKenar => _k ? const Color(0x52FBBF24) : const Color(0xFFFDE68A);
  static Color get hata => _k ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  static Color get hataZemin => _k ? const Color(0x1FF87171) : const Color(0xFFFEF2F2);
  static Color get hataKenar => _k ? const Color(0x52F87171) : const Color(0xFFFECACA);
  static Color get bilgi => _k ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
  static Color get bilgiZemin => _k ? const Color(0x1F38BDF8) : const Color(0xFFE0F2FE);
  static Color get bilgiKenar => _k ? const Color(0x5238BDF8) : const Color(0xFFBAE6FD);
}

/// Zemin renginin saydamlığını ÇARPAR (koyu temada zeminler zaten yarı
/// saydam; `withOpacity()` onları ezip parlatıyordu).
extension Saydamlik on Color {
  Color carp(double f) => withOpacity(opacity * f);
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
    brightness: _k ? Brightness.dark : Brightness.light,
    seedColor: Renk.marka,
    primary: Renk.marka,
    surface: Renk.yuzey,
    error: Renk.hata,
  );

  final sekil = RoundedRectangleBorder(borderRadius: koseYuvarlak);
  final govde = TextStyle(color: Renk.yazi);

  return ThemeData(
    useMaterial3: true,
    brightness: _k ? Brightness.dark : Brightness.light,
    fontFamily: ad,
    colorScheme: sema,
    scaffoldBackgroundColor: Renk.zemin,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    // Sayfa geçişleri: app/hareket.dart (bütün platformlarda aynı dil).
    pageTransitionsTheme: posSayfaGecisleri(),
    textTheme: (_k ? Typography.whiteMountainView : Typography.blackMountainView).apply(fontFamily: ad, bodyColor: Renk.yazi, displayColor: Renk.yazi),
    appBarTheme: AppBarTheme(
      backgroundColor: Renk.yuzey,
      foregroundColor: Renk.yazi,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: govde.copyWith(fontFamily: ad, fontSize: 17, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardTheme(
      color: Renk.yuzey,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: kartYuvarlak, side: BorderSide(color: Renk.cizgi)),
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
        side: BorderSide(color: Renk.cizgi),
        foregroundColor: Renk.yazi,
        backgroundColor: Renk.yuzey,
        textStyle: TextStyle(fontFamily: ad, fontWeight: FontWeight.w500, fontSize: 14),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: sekil, foregroundColor: Renk.marka, textStyle: TextStyle(fontFamily: ad, fontWeight: FontWeight.w600)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: sekil, foregroundColor: Renk.ikinci)),
    chipTheme: ChipThemeData(shape: sekil, side: BorderSide(color: Renk.cizgi), labelStyle: TextStyle(fontFamily: ad, fontSize: 13)),
    dialogTheme: DialogTheme(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: Renk.yuzey),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: sekil),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Renk.yuzey,
      isDense: true,
      hintStyle: TextStyle(color: Renk.soluk),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: BorderSide(color: Renk.cizgiKoyu)),
      enabledBorder: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: BorderSide(color: Renk.cizgiKoyu)),
      focusedBorder: OutlineInputBorder(borderRadius: koseYuvarlak, borderSide: BorderSide(color: Renk.vurgu, width: 1.5)),
    ),
    dividerTheme: DividerThemeData(color: Renk.cizgi, space: 1, thickness: 1),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
  );
}

/// Web'deki küçük rozet (b-green, b-slate …): yumuşak zemin + kenar + koyu yazı.
class Rozet extends StatelessWidget {
  // ignore: prefer_initializing_formals — dışarıya `renk` adı korunur.
  const Rozet(this.metin, {super.key, Color? renk, this.zemin, this.kenar, this.ikon, this.dolu = false, this.buyuk = false}) : _renk = renk;
  final String metin;
  final Color? _renk;
  Color get renk => _renk ?? Renk.soluk;
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
        color: dolu ? renk : (zemin ?? renk.withOpacity(.08)),
        borderRadius: BorderRadius.circular(999),
        border: dolu ? null : Border.all(color: kenar ?? renk.withOpacity(.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (ikon != null) ...[Icon(ikon, size: buyuk ? 14 : 12, color: dolu ? Renk.durumUstu : renk), const SizedBox(width: 4)],
        Text(metin,
            style: TextStyle(
                fontSize: buyuk ? 12.5 : 11.5, fontWeight: FontWeight.w600, color: dolu ? Renk.durumUstu : renk, height: 1.2)),
      ]),
    );
  }
}
