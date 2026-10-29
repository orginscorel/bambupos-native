import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'ortak.dart';

/// MASAYI BİRLEŞTİR — ONAY + BEKLEME (1.2.36, web BirlestirOnay.vue ile aynı).
///
/// Masa seçimi masa panosunun kendisinde yapılır (pano birleştirme modunda,
/// kartlar birebir aynı). Burada yalnız seçimden sonrası var: yönü ayrıntılı
/// soran onay penceresi ve işlem sürerken ekranı kaplayan bekleme kutusu.
/// Boş masa seçilirse birleştirme olmaz; adisyon o masaya TAŞINIR.
class BirlestirSecim {
  const BirlestirSecim({required this.tur, required this.ad, required this.masaId, required this.hedefId, required this.kalem, required this.toplam});

  /// 'acik' (açık adisyonlu masa/şahıs) ya da 'bos' (boş masa → taşıma).
  final String tur;
  final String ad;
  final int? masaId;
  final int? hedefId;
  final int kalem;
  final int toplam;
}

/// Onay penceresi. Dönüş: 'aktar' (bu adisyon → seçilen), 'al' (seçilen →
/// bu adisyon), 'tasi' (boş masaya taşı) ya da vazgeçilirse null.
Future<String?> birlestirOnayPenceresi(
  BuildContext context, {
  required String kaynakAdi,
  required int kaynakKalem,
  required int kaynakToplam,
  required BirlestirSecim secim,
}) =>
    pencereAc<String>(
      context: context,
      builder: (_) => _OnayPenceresi(kaynakAdi: kaynakAdi, kaynakKalem: kaynakKalem, kaynakToplam: kaynakToplam, secim: secim),
    );

class _OnayPenceresi extends StatefulWidget {
  const _OnayPenceresi({required this.kaynakAdi, required this.kaynakKalem, required this.kaynakToplam, required this.secim});
  final String kaynakAdi;
  final int kaynakKalem;
  final int kaynakToplam;
  final BirlestirSecim secim;

  @override
  State<_OnayPenceresi> createState() => _OnayPenceresiState();
}

class _OnayPenceresiState extends State<_OnayPenceresi> {
  String _yon = 'aktar';

  @override
  Widget build(BuildContext context) {
    final s = widget.secim;
    final k = widget.kaynakAdi;
    final bos = s.tur == 'bos';

    Widget kutu(String ust, String ad, int kalem, int toplam) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
            child: Column(children: [
              Text(ust, style: TextStyle(fontSize: 11, color: Renk.ikinci)),
              Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('$kalem kalem · ${para(toplam)}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            ]),
          ),
        );

    Widget secenek(String yon) {
      final secili = _yon == yon;
      final aktar = yon == 'aktar';
      final kapanan = aktar ? k : s.ad;
      final kalan = aktar ? s.ad : k;
      final adet = aktar ? widget.kaynakKalem : s.kalem;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: secili ? Renk.markaAcik : Renk.yuzey,
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? Renk.marka : Renk.cizgi, width: secili ? 1.5 : 1)),
          child: InkWell(
            key: ValueKey('birlestir-yon-$yon'),
            customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
            onTap: () => setState(() => _yon = yon),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(secili ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: secili ? Renk.marka : Renk.soluk),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$kapanan → $kalan', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '$kapanan adisyonundaki $adet kalem ${aktar ? '$kalan adisyonuna eklenir' : 'bu adisyona alınır'}. '),
                        TextSpan(text: '$kapanan kapanır ve boşalır. ', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.yazi)),
                        TextSpan(text: '$kalan açık kalır.\nBirleşik adisyon: ${widget.kaynakKalem + s.kalem} kalem · ${para(widget.kaynakToplam + s.toplam)}'),
                      ]),
                      style: TextStyle(fontSize: 12, height: 1.4, color: Renk.ikinci),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(bos ? 'Adisyon taşınsın mı?' : 'Bu masa ile birleşsin mi?'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (bos) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: k, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' adisyonu (${widget.kaynakKalem} kalem, ${para(widget.kaynakToplam)}) olduğu gibi '),
                  TextSpan(text: s.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' masasına taşınır. $k boşalır.'),
                ])),
              ),
              const SizedBox(height: 8),
              Text('Seçilen masa boş olduğu için birleştirme yapılmaz; adisyon tek parça taşınır.',
                  style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            ] else ...[
              Row(children: [
                kutu('Bu adisyon', k, widget.kaynakKalem, widget.kaynakToplam),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.merge_rounded, color: Renk.soluk)),
                kutu('Seçilen', s.ad, s.kalem, s.toplam),
              ]),
              const SizedBox(height: 14),
              const Text('Hangi adisyon açık kalsın?', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              secenek('aktar'),
              secenek('al'),
              Text('Ürünler, fiyatlar, ekleyen personel, sipariş saatleri, notlar ve kişi sayısı korunur; işlem iki adisyonun geçmişine yazılır.',
                  style: TextStyle(fontSize: 11.5, color: Renk.ikinci)),
            ],
          ]),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton.icon(
          key: const ValueKey('birlestir-onayla'),
          onPressed: () => Navigator.pop(context, bos ? 'tasi' : _yon),
          icon: Icon(bos ? Icons.arrow_forward_rounded : Icons.merge_rounded, size: 16),
          label: Text(bos ? 'Evet, taşı' : 'Evet, birleştir'),
        ),
      ],
    );
  }
}

/// İşlem sürerken ekranı kaplayan bekleme kutusu; bitince kısa bir "✓"
/// gösterip kapanır. Hata olursa bildirim çıkar ve null döner.
Future<T?> birlestirBekleme<T>(BuildContext context, {required bool tasima, required Future<T> Function() is_}) async {
  final durum = ValueNotifier<bool>(false); // false: sürüyor, true: bitti
  final kok = Navigator.of(context, rootNavigator: true);
  pencereAc<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Renk.yuzey,
          borderRadius: koseYuvarlak,
          child: SizedBox(
            width: 240,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
              child: ValueListenableBuilder<bool>(
                valueListenable: durum,
                builder: (_, bitti, _) => Column(mainAxisSize: MainAxisSize.min, children: [
                  if (bitti)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: Renk.basari, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: Colors.white, size: 26),
                    )
                  else
                    const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 3.5)),
                  const SizedBox(height: 14),
                  Text(
                    bitti ? (tasima ? 'Taşındı' : 'Birleştirildi') : (tasima ? 'Taşınıyor…' : 'Birleştiriliyor…'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  try {
    final sonuc = await is_();
    durum.value = true;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    kok.pop();
    if (context.mounted) context.bildir2(tasima ? 'Adisyon taşındı' : 'Adisyonlar birleştirildi', '');
    return sonuc;
  } on ApiHata catch (e) {
    kok.pop();
    if (context.mounted) context.bildir2(tasima ? 'Taşınamadı' : 'Birleştirilemedi', e.mesaj, hata: true);
    return null;
  } finally {
    durum.dispose();
  }
}
