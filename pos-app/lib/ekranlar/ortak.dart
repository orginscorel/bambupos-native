import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/durum.dart';

/// Durum nesnesini ağaca taşır (ek paket gerekmeden).
class DurumKapsami extends InheritedWidget {
  const DurumKapsami({super.key, required this.durum, required super.child});
  final UygulamaDurumu durum;

  static UygulamaDurumu of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DurumKapsami>()!.durum;

  @override
  bool updateShouldNotify(DurumKapsami old) => old.durum != durum;
}

extension DurumErisimi on BuildContext {
  UygulamaDurumu get durum => DurumKapsami.of(this);
  Api get api => DurumKapsami.of(this).api;

  /// Periyodik ekran yoklaması şimdi yapılmalı mı? Uygulama arka plandaysa ya
  /// da ekranın üstünde tam sayfa başka bir ekran (adisyon, ayrıntı) açıksa
  /// HAYIR: görünmeyen ekran için ağ + çizim + pil harcanmaz. Üstteki sayfa
  /// kapanınca ekran zaten kendini tazeler / bir sonraki turda yakalar.
  bool get yoklamaUygun => uygulamaOnde() && TickerMode.getNotifier(this).value;

  void bildir(String mesaj, {bool hata = false}) {
    final m = ScaffoldMessenger.maybeOf(this);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      content: Text(mesaj),
      backgroundColor: hata ? Renk.hata : Renk.yazi,
      duration: Duration(milliseconds: hata ? 3500 : 1800),
    ));
  }

  /// Bir işlemi çalıştırır; hata mesajını gösterir, oturum gerekiyorsa tazeler.
  Future<T?> islem<T>(Future<T> Function() is_) async {
    try {
      return await is_();
    } on ApiHata catch (e) {
      if (mounted) {
        bildir(e.mesaj, hata: true);
        durum.islemHatasi(e);
      }
      return null;
    }
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.boyut = 56});
  final double boyut;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/simge/logo.png',
        width: boyut,
        height: boyut,
        cacheWidth: (boyut * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.medium,
      );
}

class AcilisEkrani extends StatelessWidget {
  const AcilisEkrani({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Logo(boyut: 72),
          SizedBox(height: 20),
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
        ]),
      ),
    );
  }
}

class BaglantiBekleniyor extends StatelessWidget {
  const BaglantiBekleniyor({super.key, this.mesaj});
  final String? mesaj;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Renk.soluk),
            const SizedBox(height: 16),
            const Text('Bağlantı bekleniyor', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(mesaj ?? 'Sunucuya ulaşılamıyor.', textAlign: TextAlign.center, style: TextStyle(color: Renk.soluk)),
            const SizedBox(height: 4),
            Text('Bağlantı gelince kendiliğinden devam eder.', style: TextStyle(color: Renk.soluk)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => context.durum.oturumuYenile(ilk: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Şimdi dene'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Ekranın üstünde ince bağlantı uyarısı.
class BaglantiSeridi extends StatelessWidget {
  const BaglantiSeridi({super.key, required this.gorunur});
  final bool gorunur;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      child: gorunur
          ? Container(
              width: double.infinity,
              color: Renk.uyari,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              child: const Text('Bağlantı yok — son veriler gösteriliyor',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

/// Basit metin sorusu (iptal/ikram gerekçesi, not ...).
Future<String?> metinSor(BuildContext context,
    {required String baslik, String? ipucu, String? ilkDeger, String onay = 'Tamam', int enAz = 0, List<String> hazir = const []}) {
  final c = TextEditingController(text: ilkDeger);
  return pencereAc<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) => AlertDialog(
        title: Text(baslik),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (hazir.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final h in hazir)
                  ActionChip(label: Text(h), onPressed: () => yenile(() => c.text = h)),
              ]),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: c,
              autofocus: hazir.isEmpty,
              maxLength: 255,
              decoration: InputDecoration(hintText: ipucu),
              onChanged: (_) => yenile(() {}),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: c.text.trim().length >= enAz ? () => Navigator.pop(ctx, c.text.trim()) : null,
            child: Text(onay),
          ),
        ],
      ),
    ),
  );
}

Future<bool> onayla(BuildContext context, String baslik, String metin, {String onay = 'Evet', bool tehlikeli = false}) async {
  final r = await pencereAc<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(baslik),
      content: Text(metin),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
        FilledButton(
          style: tehlikeli ? FilledButton.styleFrom(backgroundColor: Renk.hata) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(onay),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Web'deki başlıklı bildirim (useToast: success(başlık, metin) / danger(...)).
extension BaslikliBildirim on BuildContext {
  void bildir2(String baslik, String metin, {bool hata = false}) {
    final m = ScaffoldMessenger.maybeOf(this);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      backgroundColor: hata ? Renk.hata : Renk.yazi,
      duration: Duration(milliseconds: hata ? 4000 : 2400),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (metin.isNotEmpty) Text(metin, style: const TextStyle(fontSize: 13)),
      ]),
    ));
  }
}

/// Web'deki çekmece (BaseDrawer): geniş ekranda sağdan açılan panel,
/// telefonda tam yükseklikte alt sayfa. [icerik] çekmeceyi kapatmak için
/// `Navigator.pop(context, sonuc)` kullanır.
Future<T?> cekmeceAc<T>(BuildContext context, {required String baslik, required Widget Function(BuildContext) icerik, double genislik = 480}) {
  final genis = MediaQuery.sizeOf(context).width >= 760;
  Widget cerceve(BuildContext ctx) => Material(
        color: Renk.yuzey,
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              height: 56,
              padding: const EdgeInsets.only(left: 18, right: 6),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
              child: Row(children: [
                Expanded(child: Text(baslik, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(child: icerik(ctx)),
          ]),
        ),
      );
  if (!genis) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      builder: (ctx) => FractionallySizedBox(heightFactor: .94, child: cerceve(ctx)),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: baslik,
    barrierColor: const Color(0x8C0F172A),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, __) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(width: genislik, height: double.infinity, child: cerceve(ctx)),
    ),
    transitionBuilder: (_, a, __, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Etiketli form alanı (web FormField: etiket · alan · ipucu/hata).
class FormAlani extends StatelessWidget {
  const FormAlani({super.key, required this.etiket, required this.child, this.zorunlu = false, this.ipucu, this.hata});
  final String etiket;
  final Widget child;
  final bool zorunlu;
  final String? ipucu;
  final String? hata;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: etiket),
          if (zorunlu) TextSpan(text: ' *', style: TextStyle(color: Renk.hata)),
        ]), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Renk.yazi)),
        const SizedBox(height: 5),
        child,
        if (hata != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(hata!, style: TextStyle(fontSize: 12, color: Renk.hata)))
        else if (ipucu != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(ipucu!, style: TextStyle(fontSize: 12, color: Renk.soluk))),
      ]);
}

/// Açılır seçim kutusu (web BaseSelect). Değer `null` = yer tutucu.
class Secici<T> extends StatelessWidget {
  const Secici({super.key, required this.deger, required this.secenekler, required this.degisti, this.yerTutucu});
  final T? deger;
  final List<(T, String)> secenekler;
  final ValueChanged<T?> degisti;
  final String? yerTutucu;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
        value: secenekler.any((s) => s.$1 == deger) ? deger : null,
        isExpanded: true,
        hint: yerTutucu == null ? null : Text(yerTutucu!, style: TextStyle(color: Renk.soluk, fontSize: 14)),
        borderRadius: koseYuvarlak,
        items: [for (final (v, e) in secenekler) DropdownMenuItem<T>(value: v, child: Text(e, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)))],
        onChanged: degisti,
      );
}

/* ── Porsiyon son eki (2026-10-27 işletme isteği) ──
   Ad "… Yarım Porsiyon" / "… Tam Porsiyon" (ya da yalnız "Yarım"/"Tam") ile
   bitiyorsa son ek renkli yazılır: Yarım = uyarı (turuncu), Tam = başarı
   (yeşil). Kutu/rozet yok; ad metni değişmez (arama, fiş aynı). */
final _porsiyonDesen = RegExp(r'^(.*\S)\s+((yarım|tam)(\s+porsiyon)?)$', caseSensitive: false, unicode: true);

/// Adı temel ad + renkli porsiyon eki olarak böler. Eşleşmezse tek parça.
List<InlineSpan> urunAdiParcalari(String ad, {TextStyle? stil}) {
  final m = _porsiyonDesen.firstMatch(ad.trim());
  if (m == null) return [TextSpan(text: ad, style: stil)];
  final tur = m.group(3)!.toLowerCase();
  final yarim = tur == 'yarım' || tur == 'yarim' || tur.startsWith('yar');
  return [
    TextSpan(text: '${m.group(1)} ', style: stil),
    TextSpan(
      text: m.group(2),
      style: (stil ?? const TextStyle()).copyWith(
        color: yarim ? Renk.uyari : Renk.basari,
        fontWeight: FontWeight.w700,
      ),
    ),
  ];
}

/// Ürün adı — porsiyon eki renkli. `Text(ad, …)` yerine kullanılır.
class UrunAdi extends StatelessWidget {
  const UrunAdi(this.ad, {super.key, this.style, this.maxLines, this.overflow, this.textAlign});
  final String ad;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: urunAdiParcalari(ad, stil: style)),
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
      );
}
