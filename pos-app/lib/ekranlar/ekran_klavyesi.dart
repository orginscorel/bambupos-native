import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';

/// EKRAN KLAVYESİ — web'deki EkranKlavyesi.vue'nun karşılığı.
///
/// Kasa bilgisayarında (Windows dokunmatik ekran) sistem klavyesi çıkmıyor;
/// tablet/POS cihazında da web ile aynı klavye istendi. Alana DOKUNUNCA
/// açılır, alan dışına dokununca / Tamam'a basınca kapanır. Telefonlarda
/// cihazın kendi klavyesi kullanılır.
///
/// Tuşlar odak ALMAZ (GestureDetector) → imleç alanda kalır; panel
/// [TextFieldTapRegion] içinde olduğu için tuşa basmak "dışarı dokunuş"
/// sayılmaz.
abstract final class EkranKlavyesi {
  static OverlayEntry? _giris;
  static _Baglanti? _bag;

  /// Klavye açık mı — pencereler kendini yukarı almak için dinler.
  static final acik = ValueNotifier<bool>(false);

  /// Bu cihazda ekran klavyesi mi kullanılır (telefon değilse evet).
  static bool kullan(BuildContext context) {
    if (kIsWeb) return false;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) return true;
    return MediaQuery.sizeOf(context).shortestSide >= 600;
  }

  static void _ac(BuildContext context, _Baglanti bag) {
    _bag = bag;
    if (_giris == null) {
      _giris = OverlayEntry(builder: (_) => const _Panel());
      Overlay.of(context, rootOverlay: true).insert(_giris!);
    } else {
      _giris!.markNeedsBuild();
    }
    acik.value = true;
  }

  /// [sahip] verilirse yalnız o alana bağlıysa kapatır.
  static void kapat([Object? sahip]) {
    if (sahip != null && _bag?.sahip != sahip) return;
    _giris?.remove();
    _giris = null;
    _bag = null;
    acik.value = false;
  }
}

class _Baglanti {
  _Baglanti(this.sahip, this.denetim, this.degisti, this.enCok);
  final Object sahip;
  final TextEditingController denetim;
  final ValueChanged<String>? degisti;
  final int? enCok;

  void degistir(TextEditingValue Function(TextEditingValue v, TextSelection s) f) {
    final v = denetim.value;
    final s = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final yeni = f(v, s);
    if (enCok != null && yeni.text.characters.length > enCok!) return;
    denetim.value = yeni;
    degisti?.call(yeni.text);
  }

  void yaz(String metin) => degistir(
    (v, s) => TextEditingValue(
      text: v.text.replaceRange(s.start, s.end, metin),
      selection: TextSelection.collapsed(offset: s.start + metin.length),
    ),
  );

  void sil() => degistir((v, s) {
    if (!s.isCollapsed) {
      return TextEditingValue(
        text: v.text.replaceRange(s.start, s.end, ''),
        selection: TextSelection.collapsed(offset: s.start),
      );
    }
    if (s.start == 0) return v;
    final once = v.text.substring(0, s.start).characters.skipLast(1).toString();
    return TextEditingValue(
      text: once + v.text.substring(s.start),
      selection: TextSelection.collapsed(offset: once.length),
    );
  });

  void temizle() => degistir((_, __) => const TextEditingValue());
}

/// Ekran klavyesiyle çalışan metin alanı. Telefonda düz TextField gibidir.
class KlavyeliAlan extends StatefulWidget {
  const KlavyeliAlan({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.style,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.autofocus = false,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.multiline = false,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextStyle? style;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool multiline;

  @override
  State<KlavyeliAlan> createState() => _KlavyeliAlanState();
}

class _KlavyeliAlanState extends State<KlavyeliAlan> {
  final _odak = FocusNode();

  @override
  void initState() {
    super.initState();
    _odak.addListener(() {
      if (!_odak.hasFocus) EkranKlavyesi.kapat(this);
    });
  }

  @override
  void dispose() {
    EkranKlavyesi.kapat(this);
    _odak.dispose();
    super.dispose();
  }

  void _dokunuldu() {
    if (!EkranKlavyesi.kullan(context)) return;
    EkranKlavyesi._ac(context, _Baglanti(this, widget.controller, widget.onChanged, widget.maxLength));
  }

  @override
  Widget build(BuildContext context) {
    final ekran = EkranKlavyesi.kullan(context);
    return TextField(
      controller: widget.controller,
      focusNode: _odak,
      autofocus: widget.autofocus,
      decoration: widget.decoration,
      style: widget.style,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      textInputAction: widget.textInputAction,
      textCapitalization: widget.textCapitalization,
      // Ekran klavyesi varken cihazın kendi klavyesi açılmasın (fiziksel
      // klavye yine çalışır).
      keyboardType: ekran ? TextInputType.none : (widget.multiline ? TextInputType.multiline : TextInputType.text),
      showCursor: true,
      onTap: _dokunuldu,
      onTapOutside: (_) {
        if (_odak.hasFocus) _odak.unfocus();
        EkranKlavyesi.kapat(this);
      },
    );
  }
}

const _satirlar = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'ı', 'o', 'p', 'ğ', 'ü'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ş', 'i'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm', 'ö', 'ç'],
];
const _semboller = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['!', '"', '#', '\$', '%', '&', '/', '(', ')', '=', '?', '*'],
  ['-', '_', '+', ',', '.', ':', ';', '@', "'", '<', '>'],
];

/// Türkçe büyük harf (i → İ, ı → I).
String _buyult(String c) => c == 'i' ? 'İ' : (c == 'ı' ? 'I' : c.toUpperCase());

class _Panel extends StatefulWidget {
  const _Panel();
  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  bool _buyuk = false;
  bool _sembol = false;

  _Baglanti? get _b => EkranKlavyesi._bag;

  Widget _tus(Widget icerik, VoidCallback bas, {int esnek = 1, bool ana = false, bool secili = false}) => Expanded(
    flex: esnek,
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          bas();
        },
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ana ? Renk.marka : (secili ? Renk.markaAcik : Renk.yuzey),
            borderRadius: koseYuvarlak,
            border: Border.all(color: secili ? Renk.markaKenar : Renk.cizgi),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: ana ? Colors.white : Renk.yazi),
            child: IconTheme.merge(
              data: IconThemeData(size: 20, color: ana ? Colors.white : Renk.yazi),
              child: icerik,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final satirlar = _sembol ? _semboller : _satirlar;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: TextFieldTapRegion(
        child: Material(
          color: Renk.ic,
          elevation: 12,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Text('Ekran klavyesi', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
                          ),
                          const Spacer(),
                          IconButton(tooltip: 'Klavyeyi kapat', onPressed: () => EkranKlavyesi.kapat(), icon: const Icon(Icons.close_rounded, size: 20)),
                        ],
                      ),
                      for (final s in satirlar)
                        Row(
                          children: [
                            for (final c in s)
                              _tus(Text(_sembol ? c : (_buyuk ? _buyult(c) : c)), () {
                                _b?.yaz(_sembol ? c : (_buyuk ? _buyult(c) : c));
                                if (_buyuk && !_sembol) setState(() => _buyuk = false); // tek seferlik
                              }),
                          ],
                        ),
                      Row(
                        children: [
                          _tus(const Icon(Icons.arrow_upward_rounded), () => setState(() => _buyuk = !_buyuk), esnek: 2, secili: _buyuk),
                          _tus(const Text('#+=', style: TextStyle(fontSize: 16)), () => setState(() => _sembol = !_sembol), esnek: 2, secili: _sembol),
                          _tus(const Text('boşluk', style: TextStyle(fontSize: 16)), () => _b?.yaz(' '), esnek: 6),
                          _tus(const Text('temizle', style: TextStyle(fontSize: 16)), () => _b?.temizle(), esnek: 2),
                          _tus(const Icon(Icons.backspace_outlined), () => _b?.sil(), esnek: 2),
                          _tus(const Text('Tamam', style: TextStyle(fontSize: 16)), () => EkranKlavyesi.kapat(), esnek: 2, ana: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
