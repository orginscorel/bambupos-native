import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import 'form.dart';
import 'ortak.dart';

/// FOTOĞRAFLI GÖREV ONAYI (sunucu 2026-10-30) — görev fotoğrafları.
///
/// Fotoğraflar oturum çereziyle korunur (GET /api/v1/tasks/{id}/foto/{ad})
/// → Image.network DEĞİL, baytlar API istemcisiyle indirilip bellekte tutulur.

List<Map<String, dynamic>> gorevFotolari(Map g) =>
    ((g['fotolar_panel'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((e) => e['url'] != null).toList();

Map<String, dynamic>? gorevOnay(Map g) => g['onay'] is Map ? Map<String, dynamic>.from(g['onay'] as Map) : null;

/// Küçük resim şeridi (dokununca tam ekran).
class FotoSeridi extends StatelessWidget {
  const FotoSeridi({super.key, required this.fotolar, this.boyut = 96});
  final List<Map<String, dynamic>> fotolar;
  final double boyut;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < fotolar.length; i++)
          Basilir(
            onTap: () => fotoBuyut(context, fotolar, i),
            etiket: 'Fotoğraf ${i + 1}, büyüt',
            child: ClipRRect(
              borderRadius: Marka.yaricap,
              child: SizedBox.square(dimension: boyut, child: KorumaliFoto(url: fotolar[i]['url'].toString(), boyut: boyut)),
            ),
          ),
      ]);
}

/// Oturumla korunan görseli API istemcisiyle indirip çizer (bellekte önbellekli).
class KorumaliFoto extends StatefulWidget {
  const KorumaliFoto({super.key, required this.url, this.sigdir = BoxFit.cover, this.boyut});
  final String url;
  final BoxFit sigdir;
  final double? boyut;

  static final _onbellek = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> baytlar(String url) => _onbellek.putIfAbsent(url, () async {
        try {
          return await Uyg.api.indir(url);
        } on ApiHata {
          _onbellek.remove(url);
          return null;
        }
      });

  @override
  State<KorumaliFoto> createState() => _KorumaliFotoState();
}

class _KorumaliFotoState extends State<KorumaliFoto> {
  late Future<Uint8List?> _f = KorumaliFoto.baytlar(widget.url);

  @override
  void didUpdateWidget(KorumaliFoto eski) {
    super.didUpdateWidget(eski);
    if (eski.url != widget.url) _f = KorumaliFoto.baytlar(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    Widget yer(Widget c) => ColoredBox(color: r.ic, child: Center(child: c));
    return FutureBuilder<Uint8List?>(
      future: _f,
      builder: (_, s) {
        if (s.connectionState != ConnectionState.done) return yer(const Yukleyici(boyut: 18));
        final b = s.data;
        if (b == null) return yer(Icon(Icons.broken_image_rounded, color: r.silik));
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final kenar = widget.boyut ?? MediaQuery.sizeOf(context).width;
        final carpan = widget.sigdir == BoxFit.cover ? 2.0 : 1.0;
        return Image.memory(b,
            fit: widget.sigdir,
            gaplessPlayback: true,
            cacheWidth: (kenar * dpr * carpan).round().clamp(64, 2048),
            errorBuilder: (_, _, _) => yer(Icon(Icons.broken_image_rounded, color: r.silik)));
      },
    );
  }
}

/// Tam ekran görüntüleyici (kaydır, iki parmakla büyüt).
void fotoBuyut(BuildContext context, List<Map<String, dynamic>> fotolar, int ilk) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => _FotoGoruntuleyici(fotolar: fotolar, ilk: ilk),
    transitionsBuilder: (_, a, _, c) => FadeTransition(opacity: a, child: c),
  ));
}

class _FotoGoruntuleyici extends StatefulWidget {
  const _FotoGoruntuleyici({required this.fotolar, required this.ilk});
  final List<Map<String, dynamic>> fotolar;
  final int ilk;
  @override
  State<_FotoGoruntuleyici> createState() => _FotoGoruntuleyiciState();
}

class _FotoGoruntuleyiciState extends State<_FotoGoruntuleyici> {
  late int _i = widget.ilk;
  late final _sayfa = PageController(initialPage: widget.ilk);

  @override
  void dispose() {
    _sayfa.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ust = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion(
      value: durumCubuguAcikSimge,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          PageView.builder(
            controller: _sayfa,
            itemCount: widget.fotolar.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 5,
              child: Center(child: KorumaliFoto(url: widget.fotolar[i]['url'].toString(), sigdir: BoxFit.contain)),
            ),
          ),
          Positioned(
            top: ust + 8,
            left: 12,
            right: 12,
            child: Row(children: [
              IconButton(
                tooltip: 'Kapat',
                style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .14), minimumSize: const Size(44, 44)),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
              const Spacer(),
              if (widget.fotolar.length > 1)
                Text('${_i + 1} / ${widget.fotolar.length}', style: gosterim(15, agirlik: FontWeight.w600, renk: Colors.white)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Ret gerekçesi penceresi (zorunlu, en az 3 karakter). Dönüş: gerekçe ya da null.
Future<String?> retGerekcesiSor(BuildContext context, String baslik) =>
    altSayfaAc<String>(context, (_) => _GerekceFormu(baslik: baslik));

class _GerekceFormu extends StatefulWidget {
  const _GerekceFormu({required this.baslik});
  final String baslik;
  @override
  State<_GerekceFormu> createState() => _GerekceFormuState();
}

class _GerekceFormuState extends State<_GerekceFormu> {
  final _c = TextEditingController();
  String? _hata;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _gonder() {
    final t = _c.text.trim();
    if (t.length < 3) {
      setState(() => _hata = 'Personelin neyi düzelteceğini kısaca yazın.');
      return;
    }
    Navigator.of(context).pop(t);
  }

  @override
  Widget build(BuildContext context) => AltSayfa(
        baslik: 'Görevi geri gönder',
        alt: widget.baslik,
        ikon: Icons.undo_rounded,
        dugmeler: KaydetDugmesi(yazi: 'Geri gönder', ikon: Icons.undo_rounded, onPressed: _gonder),
        children: [
          const SizedBox(height: 6),
          TextField(
            controller: _c,
            autofocus: true,
            maxLength: 500,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Gerekçe (personel görür)', hintText: 'ör. Alt raf da düzenlensin', errorText: _hata),
          ),
        ],
      );
}

/// Reddet / Onayla düğme çifti (büyük dokunma alanı).
class OnayDugmeleri extends StatelessWidget {
  const OnayDugmeleri({super.key, required this.onOnayla, required this.onReddet, this.mesgul = false});
  final VoidCallback onOnayla;
  final VoidCallback onReddet;
  final bool mesgul;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: YumusakDugme(yazi: 'Reddet', ikon: Icons.undo_rounded, onTap: mesgul ? null : onReddet)),
        const SizedBox(width: 8),
        Expanded(child: KaydetDugmesi(yazi: 'Onayla', mesgul: mesgul, onPressed: mesgul ? null : onOnayla)),
      ]);
}
