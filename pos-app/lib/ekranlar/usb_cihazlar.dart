import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/ajan.dart';
import '../core/usb.dart';
import 'ortak.dart';

/// USB CİHAZLAR: bu cihaza USB ile takılı fiş yazıcıları ve kart POS
/// cihazları. Liste kendiliğinden yenilenir ve sunucuya bildirilir
/// (İşletme Yönetimi'nde görünür); buradan izin verilir, deneme fişi
/// basılır ve cihaz işletmeye eklenir.
Future<void> usbCihazlarAc(BuildContext context, YazdirmaAjani ajan) {
  return cekmeceAc<void>(
    context,
    baslik: 'USB cihazlar',
    icerik: (ctx) => ListenableBuilder(
      listenable: ajan,
      builder: (ctx, _) => _UsbListesi(ajan: ajan),
    ),
  );
}

IconData usbSimgesi(String tur) => switch (tur) {
      'yazici' => Icons.print_rounded,
      'pos' => Icons.point_of_sale_rounded,
      _ => Icons.usb_rounded,
    };

class _UsbListesi extends StatefulWidget {
  const _UsbListesi({required this.ajan});
  final YazdirmaAjani ajan;

  @override
  State<_UsbListesi> createState() => _UsbListesiState();
}

class _UsbListesiState extends State<_UsbListesi> {
  final _mesgul = <String>{};
  bool _taraniyor = false;

  Future<void> _is(String anahtar, Future<void> Function() f) async {
    setState(() => _mesgul.add(anahtar));
    try {
      await f();
    } finally {
      if (mounted) setState(() => _mesgul.remove(anahtar));
    }
  }

  Future<void> _tara() async {
    setState(() => _taraniyor = true);
    await widget.ajan.usbSimdiTara();
    if (mounted) setState(() => _taraniyor = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.ajan;
    final l = a.usbCihazlar;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Text(
          'Bu cihaza USB kablosuyla takılı fiş / mutfak yazıcıları ve kart POS cihazları. '
          'Takılan cihaz kendiliğinden bulunur ve İşletme Yönetimi\'ne bildirilir; '
          'buradan da işletmeye ekleyebilirsiniz. USB yazıcıya giden fişleri bu cihaz basar.',
          style: TextStyle(fontSize: 13, height: 1.45, color: Renk.ikinci),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Text(
              a.usbHata ??
                  (a.usbSonTarama == null ? 'Henüz taranmadı' : '${l.length} cihaz bulundu (${l.where((c) => c.tur == 'yazici').length} yazıcı, ${l.where((c) => c.tur == 'pos').length} POS) · son tarama ${_saat(a.usbSonTarama!)}'),
              style: TextStyle(fontSize: 12.5, color: a.usbHata != null ? Renk.uyari : Renk.soluk),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _taraniyor ? null : _tara,
            icon: _taraniyor
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Yenile'),
          ),
        ]),
        if (a.usbPlatform == 'windows' && !l.any((c) => c.tur == 'yazici' && c.yazdirilabilir) && a.usbSonTarama != null) ...[
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('usb-windows-tani'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Renk.uyariZemin, border: Border.all(color: Renk.uyariKenar), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                'Windows\'ta yüklü yazıcı bulunamadı — yazıcının sürücüsünü kurun ya da \'Generic / Text Only\' ekleyin',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Renk.uyari),
              ),
              const SizedBox(height: 6),
              Text('Windows\'un gördüğü yazıcılar (ad · port):', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
              if (a.sistemYazicilari.isEmpty)
                Text('— hiç yazıcı yok', style: TextStyle(fontSize: 12, color: Renk.ikinci))
              else
                for (final y in a.sistemYazicilari) Text(y, style: TextStyle(fontSize: 12, color: Renk.yazi)),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        if (l.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: Renk.cizgi), borderRadius: BorderRadius.circular(8)),
            child: Text(
              'Bağlı USB yazıcı ya da kart POS bulunamadı. Kabloyu takıp cihazı açın; liste kendiliğinden yenilenir.',
              style: TextStyle(fontSize: 13, color: Renk.ikinci),
            ),
          ),
        for (final c in l) ...[
          _UsbSatiri(
            cihaz: c,
            tanimli: a.usbTanimliMi(c),
            gizli: !a.usbTanimliMi(c) && a.usbGizliMi(c),
            mesgul: _mesgul.contains(c.anahtar),
            goster: () => _is(c.anahtar, () => a.usbGizle(c, gizli: false)),
            izin: () => _is(c.anahtar, () async {
              final ok = await a.usbIzinIste(c);
              if (!ok && context.mounted) context.bildir2('İzin verilmedi', 'USB cihazına erişmek için izin gerekir.', hata: true);
            }),
            test: () => _is(c.anahtar, () async {
              try {
                await a.usbTestYazdir(c);
                if (context.mounted) context.bildir2('Deneme fişi gönderildi', c.ad);
              } catch (e) {
                if (context.mounted) context.bildir2('Deneme fişi basılamadı', '$e', hata: true);
              }
            }),
            ekle: (tur) => _is(c.anahtar, () => usbEkle(context, a, c, tur: tur)),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  static String _saat(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Cihazı işletmeye ekler (ad sorulur). [sor] false ise doğrudan eklenir.
Future<void> usbEkle(BuildContext context, YazdirmaAjani a, UsbCihaz c, {required String tur, bool sor = true}) async {
  final yazici = tur == 'yazici';
  String? ad = c.ad;
  if (sor) {
    ad = await metinSor(
      context,
      baslik: yazici ? 'Yazıcı olarak ekle' : 'Kart POS olarak ekle',
      ipucu: yazici ? 'ör. Mutfak yazıcısı' : 'ör. Kasa POS',
      ilkDeger: c.ad,
      onay: 'Ekle',
      enAz: 1,
    );
    if (ad == null) return;
  }
  final hata = await a.usbBenimse(c, ad: ad, tur: tur);
  if (!context.mounted) return;
  if (hata == null) {
    context.bildir2(yazici ? 'Yazıcı eklendi' : 'Kart POS eklendi',
        yazici ? '$ad · istasyonunu İşletme Yönetimi › Yazıcılar\'dan seçebilirsiniz.' : ad);
  } else {
    context.bildir2('Eklenemedi', hata, hata: true);
  }
}

class _UsbSatiri extends StatelessWidget {
  const _UsbSatiri({
    required this.cihaz,
    required this.tanimli,
    required this.gizli,
    required this.mesgul,
    required this.goster,
    required this.izin,
    required this.test,
    required this.ekle,
  });
  final UsbCihaz cihaz;
  final bool tanimli;

  /// "Bunu gösterme" denmiş: soluk görünür, "Gizlendi" + "Göster".
  final bool gizli;
  final bool mesgul;
  final VoidCallback goster;
  final VoidCallback izin;
  final VoidCallback test;
  final void Function(String tur) ekle;

  @override
  Widget build(BuildContext context) {
    final c = cihaz;
    final (durum, renk) = c.izinGerekli
        ? ('İzin gerekli', Renk.uyari)
        : tanimli
            ? ('Sunucuda tanımlı', Renk.basari)
            : (c.ipucu ?? (c.tur == 'yazici' && !c.yazdirilabilir ? 'Yazdırılamıyor' : 'Hazır'),
                c.ipucu != null ? Renk.uyari : Renk.ikinci);
    final alt = [
      if (c.uretici case final bbDeger?) bbDeger,
      if (c.vidPid case final bbDeger?) bbDeger,
      if (c.osAd != null && c.platform != 'android') c.osAd!,
    ].join(' · ');
    final dugmeStili = OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12));

    final kutu = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border.all(color: Renk.cizgi), borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(8)),
            child: Icon(usbSimgesi(c.tur), size: 20, color: Renk.ikinci),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.ad, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (alt.isNotEmpty) Text(alt, style: TextStyle(fontSize: 12, color: Renk.soluk)),
              const SizedBox(height: 2),
              Text(
                '${switch (c.tur) {
                  'yazici' => 'Yazıcı',
                  'pos' => 'Kart POS',
                  _ => 'Tanınmayan cihaz',
                }} · $durum',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: renk),
              ),
            ]),
          ),
          if (gizli)
            Container(
              key: ValueKey('usb-gizlendi-${c.anahtar}'),
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Renk.ic, border: Border.all(color: Renk.cizgi), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.visibility_off_outlined, size: 14, color: Renk.soluk),
                const SizedBox(width: 4),
                Text('Gizlendi', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Renk.soluk)),
              ]),
            ),
          if (mesgul) const Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (gizli)
            OutlinedButton.icon(
              key: ValueKey('usb-goster-${c.anahtar}'),
              style: dugmeStili,
              onPressed: mesgul ? null : goster,
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: const Text('Göster'),
            ),
          if (c.izinGerekli) OutlinedButton(style: dugmeStili, onPressed: mesgul ? null : izin, child: const Text('İzin ver')),
          if (c.tur != 'pos' && (c.yazdirilabilir || c.izinGerekli))
            OutlinedButton(style: dugmeStili, onPressed: mesgul ? null : test, child: const Text('Test yazdır')),
          if (!tanimli && c.tur != 'pos')
            OutlinedButton(style: dugmeStili, onPressed: mesgul ? null : () => ekle('yazici'), child: const Text('Yazıcı olarak ekle')),
          if (!tanimli && c.tur != 'yazici')
            OutlinedButton(style: dugmeStili, onPressed: mesgul ? null : () => ekle('pos'), child: const Text('Kart POS olarak ekle')),
        ]),
      ]),
    );
    // Gizlenen cihaz soluk: listede durur, şeritte çıkmaz.
    return gizli ? Opacity(opacity: .6, child: kutu) : kutu;
  }
}

/// "Yeni USB yazıcı bulundu: … — Ekle" şeridi (güncelleme şeridiyle aynı
/// görünüm). Eklenen ya da "Bunu gösterme" denen cihaz bir daha çıkmaz
/// (gizlenenler USB cihazlar panelinde ve İşletme Yönetimi'nde görünür).
class UsbBulunduSeridi extends StatelessWidget {
  const UsbBulunduSeridi({super.key, required this.ajan});
  final YazdirmaAjani ajan;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ajan,
      builder: (context, _) {
        final c = ajan.usbYeniCihaz;
        if (c == null) return const SizedBox.shrink();
        final yazici = c.tur == 'yazici';
        return Material(
          color: Renk.markaAcik,
          child: Container(
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.markaKenar))),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Icon(usbSimgesi(c.tur), color: Renk.marka, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => usbCihazlarAc(context, ajan),
                  child: Text(
                    '${yazici ? 'Yeni USB yazıcı bulundu' : 'Yeni kart POS bulundu'}: ${c.ad}${c.ipucu != null ? ' (${c.ipucu})' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              FilledButton(
                key: const ValueKey('usb-serit-ekle'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 34)),
                onPressed: () => usbEkle(context, ajan, c, tur: c.tur, sor: false),
                child: const Text('Ekle'),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                key: const ValueKey('usb-serit-gizle'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => ajan.usbGizle(c),
                child: const Text('Bunu gösterme'),
              ),
            ]),
          ),
        );
      },
    );
  }
}
