import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import 'ortak.dart';

/// Görev fotoğrafı (iş kanıtı): seçme, yükleme, küçük resim şeridi ve tam ekran.
///
/// Görseller oturum çereziyle korunur → Image.network DEĞİL, baytlar API
/// istemcisiyle indirilir ve bellekte tutulur.

const gorevFotoSiniri = 3;

/// Kaynak seçimi panosu. `tamamla` = görevi bitirirken açıldı (fotoğrafsız
/// tamamlama seçeneği de gösterilir). Dönüş: seçilen dosya yolu, 'yok'
/// (fotoğrafsız tamamla) ya da null (vazgeçti).
Future<String?> gorevFotoSec(BuildContext context, {bool tamamla = false, int mevcut = 0}) async {
  final kaynak = await panoAc<Object>(
    context,
    baslik: tamamla ? 'Görevi tamamla' : 'Fotoğraf ekle',
    alt: tamamla
        ? 'İşin bittiğini gösteren bir fotoğraf ekleyebilirsin (isteğe bağlı).'
        : 'Görevin durumunu gösteren fotoğraf ekle (en fazla $gorevFotoSiniri).',
    icerik: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SatirGrubu([
        if (mevcut < gorevFotoSiniri) ...[
          Satir(
            ikon: Icons.photo_camera_rounded,
            baslik: 'Fotoğraf çek',
            alt: 'Kamerayı aç',
            grad: true,
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          Satir(
            ikon: Icons.photo_library_rounded,
            baslik: 'Galeriden seç',
            alt: 'Telefondaki bir fotoğrafı ekle',
            ikonZemin: const Color(0xFFE0F2FE),
            ikonRenk: const Color(0xFF0284C7),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
        if (tamamla)
          Satir(
            ikon: Icons.check_rounded,
            baslik: 'Fotoğrafsız tamamla',
            ikonZemin: const Color(0xFFD1FAE5),
            ikonRenk: const Color(0xFF047857),
            onTap: () => Navigator.pop(ctx, 'yok'),
          ),
      ]),
    ]),
  );
  if (kaynak == 'yok') return 'yok';
  if (kaynak is! ImageSource) return null;
  try {
    final x = await ImagePicker().pickImage(source: kaynak, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    return x?.path;
  } on PlatformException catch (e) {
    bildir(
      kaynak == ImageSource.camera ? 'Kamera açılamadı' : 'Galeri açılamadı',
      mesaj: e.code.contains('denied') ? 'Ayarlardan uygulamaya izin ver.' : e.message,
      tur: BildirimTur.hata,
    );
    return null;
  }
}

/// Fotoğrafı yükler; sunucunun güncel listesini döner (hata → toast + null).
Future<List<Map<String, dynamic>>?> gorevFotoYukle(int gorevId, String dosyaYolu) async {
  try {
    final r = await Uyg.api.yukle('/api/v1/portal/tasks/$gorevId/foto', 'foto', dosyaYolu);
    final l = (r is Map ? r['fotolar'] as List? : null) ?? const [];
    return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  } on ApiHata catch (e) {
    bildir('Fotoğraf yüklenemedi', mesaj: e.mesaj, tur: BildirimTur.hata);
    return null;
  }
}

List<Map<String, dynamic>> gorevFotolari(Map<String, dynamic> g) =>
    ((g['fotolar'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((e) => e['url'] != null).toList();

/* ───────────── Küçük resim şeridi ───────────── */

class FotoSeridi extends StatelessWidget {
  const FotoSeridi({super.key, required this.fotolar, this.yukleniyor = false, this.boyut = 60});
  final List<Map<String, dynamic>> fotolar;
  final bool yukleniyor;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < fotolar.length; i++)
        Basilir(
          onTap: () => fotoBuyut(context, fotolar, i),
          child: Hero(
            tag: 'foto-${fotolar[i]['url']}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(dimension: boyut, child: KorumaliFoto(url: fotolar[i]['url'].toString())),
            ),
          ),
        ),
      if (yukleniyor)
        Container(
          width: boyut,
          height: boyut,
          decoration: BoxDecoration(color: r.ic, borderRadius: BorderRadius.circular(14)),
          child: Center(child: Yukleyici(boyut: 22, renk: r.birincil)),
        ),
    ]);
  }
}

/// Oturumla korunan görseli API istemcisiyle indirip çizer (bellekte önbellekli).
class KorumaliFoto extends StatefulWidget {
  const KorumaliFoto({super.key, required this.url, this.sigdir = BoxFit.cover});
  final String url;
  final BoxFit sigdir;

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
        if (s.connectionState != ConnectionState.done) return const Iskelet(yukseklik: double.infinity, radius: 0);
        final b = s.data;
        if (b == null) return yer(Icon(Icons.broken_image_rounded, color: r.silik));
        return Image.memory(b, fit: widget.sigdir, gaplessPlayback: true, errorBuilder: (_, _, _) => yer(Icon(Icons.broken_image_rounded, color: r.silik)));
      },
    );
  }
}

/* ───────────── Tam ekran görüntüleyici ───────────── */

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
      value: durumCubugu,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          PageView.builder(
            controller: _sayfa,
            itemCount: widget.fotolar.length,
            onPageChanged: (i) => setState(() => _i = i),
            itemBuilder: (_, i) {
              final url = widget.fotolar[i]['url'].toString();
              return InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Hero(tag: 'foto-$url', child: KorumaliFoto(url: url, sigdir: BoxFit.contain)),
                ),
              );
            },
          ),
          Positioned(
            top: ust + 8,
            left: 12,
            right: 12,
            child: Row(children: [
              Basilir(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded, color: Colors.white),
                ),
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
