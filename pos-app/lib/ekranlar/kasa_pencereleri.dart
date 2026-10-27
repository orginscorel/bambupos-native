import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'nedenler.dart';
import 'ortak.dart';

/// Kasa ekranının pencereleri (web Cashier.vue §5). Şartname:
/// /root/work/spec/kasa.md.

/* ───────── Para metni (TR) ───────── */

/// parseMoney: "1.234" → 123400, "12,50" → 1250, "12.5" → 1250; geçersiz → null.
int? paraCoz(String metin) {
  var s = metin.trim().replaceAll(' ', '').replaceAll('₺', '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (s.contains('.')) {
    final p = s.split('.');
    if (p.length > 1 && p.skip(1).every((x) => x.length == 3)) s = p.join();
  }
  final d = double.tryParse(s);
  if (d == null || d < 0) return null;
  return (d * 100).round();
}

/// formatMoneyInput: binliksiz "12,50".
String paraGirdisi(int minor) => '${minor ~/ 100},${(minor % 100).toString().padLeft(2, '0')}';

/// Fişte "1.234,56 TL".
String tl(int minor) => '${para(minor, simge: false)} TL';

/* ───────── Web simge adları ───────── */

IconData kasaSimge(String? ad) => switch (ad) {
      'cart' => Icons.shopping_cart_outlined,
      'dashboard' => Icons.credit_card_rounded,
      'card' => Icons.credit_card_rounded,
      'utensils' => Icons.restaurant_rounded,
      'arrow-right' => Icons.arrow_forward_rounded,
      'qr-code' => Icons.qr_code_2_rounded,
      'orders' => Icons.content_paste_rounded,
      'user' => Icons.person_outline_rounded,
      'users' => Icons.people_outline_rounded,
      'inbox' => Icons.inbox_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'dots-vertical' => Icons.more_vert_rounded,
      'truck' => Icons.local_shipping_outlined,
      'globe' => Icons.public_rounded,
      'monitor' => Icons.desktop_windows_outlined,
      'phone' => Icons.phone_outlined,
      'bag' || 'shopping-bag' => Icons.shopping_bag_outlined,
      'table' => Icons.table_restaurant_outlined,
      'check-circle' => Icons.check_circle_outline_rounded,
      'x-circle' => Icons.cancel_outlined,
      'alert-circle' => Icons.error_outline_rounded,
      'arrow-left' => Icons.arrow_back_rounded,
      'bell' => Icons.notifications_none_rounded,
      'kiosk' => Icons.touch_app_outlined,
      _ => Icons.receipt_long_outlined,
    };

/// Yöntem renk tonu: (boşta ikon rengi, seçili kenar, seçili zemin, seçili metin).
({Color ikon, Color kenar, Color zemin, Color yazi}) yontemTonu(String y) => switch (y) {
      'cash' => (ikon: Renk.basari, kenar: Renk.basariKenar, zemin: Renk.basariZemin, yazi: Renk.basari),
      'credit_card' || 'debit_card' => (ikon: Renk.marka, kenar: Renk.marka, zemin: Renk.markaAcik, yazi: Renk.marka),
      'meal_card' || 'gift_card' => (ikon: Renk.uyari, kenar: Renk.uyariKenar, zemin: Renk.uyariZemin, yazi: Renk.uyari),
      'transfer' || 'qr' || 'online' => (ikon: Renk.bilgi, kenar: Renk.bilgiKenar, zemin: Renk.bilgiZemin, yazi: Renk.bilgi),
      _ => (ikon: Renk.ikinci, kenar: Renk.marka, zemin: Renk.markaAcik, yazi: Renk.marka),
    };

/// PaymentMethod::options() (on_account kasada gizli).
const kasaYontemleri = <(String, String, String, bool)>[
  ('cash', 'Nakit', 'cart', false),
  ('credit_card', 'Kredi kartı', 'dashboard', true),
  ('debit_card', 'Banka kartı', 'dashboard', true),
  ('meal_card', 'Yemek kartı', 'utensils', false),
  ('transfer', 'Havale/EFT', 'arrow-right', false),
  ('qr', 'QR ödeme', 'qr-code', false),
  ('online', 'Online ödeme', 'orders', false),
  ('gift_card', 'Hediye kartı', 'inbox', false),
];

String yontemAdi(String? y) => kasaYontemleri.where((e) => e.$1 == y).map((e) => e.$2).firstOrNull ?? (y == 'on_account' ? 'Açık hesap' : (y ?? ''));

/* ───────── Ortak pencere iskeleti ───────── */

Future<T?> kasaPenceresi<T>(BuildContext context,
    {required String baslik, required Widget Function(BuildContext, StateSetter) icerik, required List<Widget> Function(BuildContext, StateSetter) dugmeler, double genislik = 384}) {
  return pencereAc<T>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) => AlertDialog(
        title: Row(children: [
          Expanded(child: Text(baslik)),
          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
        content: SizedBox(width: genislik, child: SingleChildScrollView(child: icerik(ctx, yenile))),
        actions: dugmeler(ctx, yenile),
      ),
    ),
  );
}

/* ───────── Personel PIN (§5) ───────── */

/// Terminalde PIN isteyen işlemler (void / yöntem / iade / bugün ödenenler):
/// sunucu terminal oturumunda PIN'i ZORUNLU tutar (şartname §7.16).
Future<Map<String, dynamic>?> personelPinSor(BuildContext context) {
  final c = TextEditingController();
  return kasaPenceresi<Map<String, dynamic>>(
    context,
    baslik: 'Personel PIN',
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: Renk.markaAcik, shape: BoxShape.circle),
          child: Icon(Icons.person_outline_rounded, color: Renk.marka, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text("Bu işlem için personel PIN'i gerekli. İşlem, PIN'i giren personele kaydedilir.", style: TextStyle(fontSize: 13, color: Renk.ikinci)),
        ),
      ]),
      const SizedBox(height: 12),
      FormAlani(
        etiket: 'PIN',
        child: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '••••••'),
          onChanged: (_) => yenile(() {}),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, {'pin': v.trim(), 'staff_code': null});
          },
        ),
      ),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: c.text.trim().isEmpty ? null : () => Navigator.pop(ctx, {'pin': c.text.trim(), 'staff_code': null}),
        child: const Text('Onayla'),
      ),
    ],
  );
}

/* ───────── Neden alanı (debt listesi web'deki ReasonSelect) ───────── */

const borcNedenleri = ['Müşteri sonra ödeyecek', 'Kurumsal şahıs hesabı', 'Personel hesabı', 'Nakit yetmedi', 'Kart çalışmadı'];

class _BorcNedeni extends StatefulWidget {
  const _BorcNedeni({required this.ilk, required this.degisti});
  final String ilk;
  final ValueChanged<String> degisti;

  @override
  State<_BorcNedeni> createState() => _BorcNedeniState();
}

class _BorcNedeniState extends State<_BorcNedeni> {
  static const _diger = '__diger__';
  late String? _secili = widget.ilk.isEmpty ? null : (borcNedenleri.contains(widget.ilk) ? widget.ilk : _diger);
  late final _metin = TextEditingController(text: borcNedenleri.contains(widget.ilk) ? '' : widget.ilk);

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  void _sec(String? v) {
    setState(() => _secili = v);
    widget.degisti(v == _diger ? _metin.text.trim() : (v ?? ''));
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in borcNedenleri)
            InkWell(
              borderRadius: koseYuvarlak,
              onTap: () => _sec(n),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: _secili == n ? Renk.markaAcik : Renk.yuzey,
                  borderRadius: koseYuvarlak,
                  border: Border.all(color: _secili == n ? Renk.marka : Renk.cizgiKoyu),
                ),
                child: Text(n, style: TextStyle(fontSize: 12.5, color: _secili == n ? Renk.marka : Renk.yazi)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _secili,
          isExpanded: true,
          hint: const Text('Sebep seçin'),
          items: [
            for (final n in borcNedenleri) DropdownMenuItem(value: n, child: Text(n)),
            const DropdownMenuItem(value: _diger, child: Text('Diğer… (yazarak)')),
          ],
          onChanged: _sec,
        ),
        if (_secili == _diger) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _metin,
            maxLength: 255,
            decoration: const InputDecoration(hintText: 'Sebebi kısaca yazın…'),
            onChanged: (v) => widget.degisti(v.trim()),
          ),
        ],
      ]);
}

/* ───────── Borca yaz (§4.10) ───────── */

class BorcaYazSonucu {
  BorcaYazSonucu({this.cariId, this.yeniAd, this.yeniTelefon, required this.neden});
  final int? cariId;
  final String? yeniAd;
  final String? yeniTelefon;
  final String neden;
}

Future<BorcaYazSonucu?> borcaYazPenceresi(
  BuildContext context, {
  required String baslik,
  required int kalan,
  required bool kismi,
  required int seciliAdet,
  required int seciliTutar,
  required int? mevcutCari,
}) async {
  List<Json> cariler = const [];
  try {
    final r = await context.api.get('/api/v1/receivables', sorgu: {'per_page': 200});
    final d = r is Map && r['receivables'] is Map ? (r['receivables'] as Map)['data'] : (r is Map ? r['receivables'] : null);
    cariler = (d as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  } on ApiHata {
    // Liste gelmezse yeni şahıs açılabilir.
  }
  if (!context.mounted) return null;
  var yeni = false;
  int? secili = mevcutCari;
  var neden = mevcutCari != null ? 'Şahıs adisyonu' : '';
  final ad = TextEditingController();
  final tel = TextEditingController();

  return kasaPenceresi<BorcaYazSonucu>(
    context,
    baslik: 'Borca yaz',
    genislik: 440,
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kismi ? Renk.uyariZemin : Renk.bilgiZemin,
          borderRadius: koseYuvarlak,
          border: Border.all(color: kismi ? Renk.uyariKenar : Renk.bilgiKenar),
        ),
        child: Text.rich(
          kismi
              ? TextSpan(children: [
                  TextSpan(text: baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' — yalnız '),
                  TextSpan(text: 'seçili $seciliAdet kalem', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' ('),
                  TextSpan(text: para(seciliTutar), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ') borca yazılacak. Adisyonun kalanı ('),
                  TextSpan(text: para(kalan - seciliTutar), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ') masada '),
                  const TextSpan(text: 'açık kalır', style: TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: '.'),
                ])
              : TextSpan(children: [
                  TextSpan(text: baslik, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' — kalan '),
                  TextSpan(text: para(kalan), style: const TextStyle(fontWeight: FontWeight.w700)),
                  const TextSpan(text: ' bir şahsa borç olarak yazılacak. Adisyon kapanır, tahsilat borç hesabından yapılır.'),
                ]),
          style: TextStyle(fontSize: 13, color: kismi ? Renk.uyari : Renk.bilgi),
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: yeni
              ? TextButton(onPressed: () => yenile(() => yeni = false), child: const Text('Kayıtlı şahıs'))
              : FilledButton(onPressed: () {}, child: const Text('Kayıtlı şahıs')),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: yeni
              ? FilledButton(onPressed: () {}, child: const Text('Yeni şahıs'))
              : TextButton(onPressed: () => yenile(() => yeni = true), child: const Text('Yeni şahıs')),
        ),
      ]),
      const SizedBox(height: 10),
      if (!yeni)
        cariler.isEmpty
            ? Text('Kayıtlı şahıs yok — "Yeni şahıs" ile oluşturabilirsiniz.', style: TextStyle(fontSize: 13, color: Renk.ikinci))
            : FormAlani(
                etiket: 'Şahıs (müşteri)',
                child: DropdownButtonFormField<int>(
                  initialValue: cariler.any((c) => tamSayi(c['id']) == secili) ? secili : null,
                  isExpanded: true,
                  hint: const Text('Seçin…'),
                  items: [
                    for (final c in cariler)
                      DropdownMenuItem(
                        value: tamSayi(c['id']),
                        child: Text('${c['name']}${c['phone'] != null ? ' · ${c['phone']}' : ''} — bakiye ${para(tamSayi(c['balance_minor']))}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => yenile(() => secili = v),
                ),
              )
      else ...[
        FormAlani(etiket: 'Şahıs adı', child: TextField(controller: ad, decoration: const InputDecoration(hintText: 'Örn. Ahmet Yılmaz'))),
        const SizedBox(height: 8),
        FormAlani(
          etiket: 'Telefon',
          ipucu: 'İsteğe bağlı',
          child: TextField(controller: tel, keyboardType: TextInputType.phone, decoration: const InputDecoration(hintText: '05xx…')),
        ),
      ],
      const SizedBox(height: 10),
      FormAlani(
        etiket: 'Gerekçe',
        ipucu: 'Zorunlu — listeden seçin; farklıysa “Diğer…”.',
        child: _BorcNedeni(ilk: neden, degisti: (v) => yenile(() => neden = v)),
      ),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: neden.trim().isEmpty
            ? null
            : () {
                if (yeni) {
                  if (ad.text.trim().isEmpty) {
                    ctx.bildir2('Şahıs adı gerekli', 'Borcun kime yazılacağını girin.', hata: true);
                    return;
                  }
                  Navigator.pop(ctx, BorcaYazSonucu(yeniAd: ad.text.trim(), yeniTelefon: tel.text.trim().isEmpty ? null : tel.text.trim(), neden: neden.trim()));
                } else {
                  if (secili == null) {
                    ctx.bildir2('Şahıs seçilmedi', 'Var olan bir şahıs seçin ya da yeni şahıs oluşturun.', hata: true);
                    return;
                  }
                  Navigator.pop(ctx, BorcaYazSonucu(cariId: secili, neden: neden.trim()));
                }
              },
        child: const Text('Borca yaz'),
      ),
    ],
  );
}

/* ───────── Servis bedeli (§4.8) ───────── */

/// Döner: ('uygula', tür, değer) | ('kaldir', '', 0) | null.
Future<(String, String, num)?> servisBedeliPenceresi(BuildContext context, {required bool varMi}) {
  var tur = 'percent';
  final deger = TextEditingController();
  return kasaPenceresi<(String, String, num)>(
    context,
    baslik: 'Servis bedeli',
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FormAlani(
        etiket: 'Tür',
        child: DropdownButtonFormField<String>(
          initialValue: tur,
          items: const [
            DropdownMenuItem(value: 'percent', child: Text('Yüzde (%)')),
            DropdownMenuItem(value: 'amount', child: Text('Sabit tutar (₺)')),
          ],
          onChanged: (v) => yenile(() => tur = v ?? 'percent'),
        ),
      ),
      const SizedBox(height: 10),
      FormAlani(
        etiket: tur == 'percent' ? 'Yüzde' : 'Tutar (₺)',
        child: TextField(
          controller: deger,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(hintText: tur == 'percent' ? 'ör. 10' : 'ör. 25,00'),
          onChanged: (_) => yenile(() {}),
        ),
      ),
    ]),
    dugmeler: (ctx, yenile) => [
      if (varMi) TextButton(onPressed: () => Navigator.pop(ctx, ('kaldir', '', 0)), child: const Text('Bedeli kaldır')),
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: deger.text.trim().isEmpty
            ? null
            : () {
                final num? v = tur == 'percent' ? num.tryParse(deger.text.trim().replaceAll(',', '.')) : paraCoz(deger.text);
                if (v == null || v <= 0) return;
                Navigator.pop(ctx, ('uygula', tur, v));
              },
        child: const Text('Uygula'),
      ),
    ],
  );
}

/* ───────── İkram / Ödemeyi kaldır / İade ───────── */

Future<String?> ikramPenceresi(BuildContext context, String ad) {
  var neden = '';
  return kasaPenceresi<String>(
    context,
    baslik: 'İkram (ücretsiz yap)',
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: ad, style: const TextStyle(fontWeight: FontWeight.w700)),
        const TextSpan(text: ' ikram edilecek; tutarı sıfırlanır ve Z raporunda ikram olarak izlenir.'),
      ])),
      const SizedBox(height: 12),
      FormAlani(
        etiket: 'Neden',
        ipucu: 'Listeden seçin; farklıysa “Diğer…”.',
        child: NedenSecici(tur: 'item_comp', degisti: (v) => yenile(() => neden = v)),
      ),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(onPressed: neden.trim().length < 3 ? null : () => Navigator.pop(ctx, neden.trim()), child: const Text('İkram et')),
    ],
  );
}

Future<String?> odemeyiKaldirPenceresi(BuildContext context) {
  var neden = '';
  return kasaPenceresi<String>(
    context,
    baslik: 'Ödemeyi kaldır',
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Tahsilat hiç olmamış sayılır; adisyon yeniden açılır. Nakitse çekmece defterine ters kayıt düşer.', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 12),
      FormAlani(etiket: 'Neden', child: NedenSecici(tur: 'order_refund', degisti: (v) => yenile(() => neden = v))),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Renk.hata),
        onPressed: neden.trim().length < 3 ? null : () => Navigator.pop(ctx, neden.trim()),
        child: const Text('Ödemeyi iptal et'),
      ),
    ],
  );
}

Future<({int tutar, String neden})?> iadePenceresi(BuildContext context, Json odeme) {
  final kalan = tamSayi(odeme['amount_minor']) - tamSayi(odeme['refunded_total_minor']);
  final tutar = TextEditingController(text: paraGirdisi(kalan));
  var neden = '';
  return kasaPenceresi<({int tutar, String neden})>(
    context,
    baslik: 'İade',
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${odeme['method_label'] ?? ''} — ödeme ${para(tamSayi(odeme['amount_minor']))}; iade edilebilir kalan ${para(kalan)}.',
          style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 12),
      FormAlani(
        etiket: 'İade tutarı (₺)',
        child: TextField(controller: tutar, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      ),
      const SizedBox(height: 10),
      FormAlani(etiket: 'Neden', child: NedenSecici(tur: 'order_refund', degisti: (v) => yenile(() => neden = v))),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Renk.hata),
        onPressed: neden.trim().length < 3
            ? null
            : () {
                final t = paraCoz(tutar.text);
                if (t == null || t <= 0) {
                  ctx.bildir2('Tutar geçersiz', 'Pozitif bir iade tutarı girin.', hata: true);
                  return;
                }
                Navigator.pop(ctx, (tutar: t, neden: neden.trim()));
              },
        child: const Text('İade et'),
      ),
    ],
  );
}

/// Ödeme yöntemini değiştir → (yeni yöntem, açıklama).
Future<({String yontem, String? neden})?> yontemDegistirPenceresi(BuildContext context, Json odeme) {
  String? secili;
  final aciklama = TextEditingController();
  final mevcut = '${odeme['method'] ?? ''}';
  return kasaPenceresi<({String yontem, String? neden})>(
    context,
    baslik: 'Ödeme yöntemini değiştir',
    genislik: 420,
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Renk.bilgiZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.bilgiKenar)),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: para(tamSayi(odeme['amount_minor'])), style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' şu an '),
            TextSpan(text: '${odeme['method_label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' olarak kayıtlı. Yeni yöntemi seçin — tutar değişmez; kasa çekmecesi, raporlar ve gün sonu birlikte düzelir.'),
          ]),
          style: TextStyle(fontSize: 13, color: Renk.bilgi),
        ),
      ),
      const SizedBox(height: 12),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 3.6,
        children: [
          for (final y in kasaYontemleri.where((y) => y.$1 != mevcut))
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: secili == y.$1 ? Renk.markaAcik : null,
                foregroundColor: secili == y.$1 ? Renk.marka : Renk.yazi,
                side: BorderSide(color: secili == y.$1 ? Renk.marka : Renk.cizgi),
              ),
              onPressed: () => yenile(() => secili = y.$1),
              icon: Icon(kasaSimge(y.$3), size: 16),
              label: Text(y.$2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
      const SizedBox(height: 10),
      FormAlani(
        etiket: 'Açıklama',
        ipucu: 'İsteğe bağlı — denetim kaydında görünür',
        child: TextField(controller: aciklama, decoration: const InputDecoration(hintText: 'ör. yanlışlıkla nakit seçildi')),
      ),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
      FilledButton(
        onPressed: secili == null ? null : () => Navigator.pop(ctx, (yontem: secili!, neden: aciklama.text.trim().isEmpty ? null : aciklama.text.trim())),
        child: const Text('Kaydet'),
      ),
    ],
  );
}

/* ───────── Hesabı böl (§4.5) ───────── */

Future<int?> hesabiBolPenceresi(BuildContext context, {required int kalan, int? misafir}) {
  final c = TextEditingController(text: misafir != null && misafir > 1 ? '$misafir' : '');
  return kasaPenceresi<int>(
    context,
    baslik: 'Hesabı böl',
    icerik: (ctx, yenile) {
      final n = int.tryParse(c.text.trim()) ?? 0;
      final pay = n >= 2 ? (kalan / n).ceil() : 0;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Kalan '),
          TextSpan(text: para(kalan), style: const TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' kaç kişiye bölünecek?'),
        ])),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final k in const [2, 3, 4, 5, 6, 8])
            ChoiceChip(
              label: Text('$k'),
              selected: n == k,
              onSelected: (_) => yenile(() => c.text = '$k'),
            ),
        ]),
        const SizedBox(height: 10),
        FormAlani(
          etiket: 'Kişi sayısı',
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(hintText: 'ör. 5'),
            onChanged: (_) => yenile(() {}),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Text('Kişi başı', style: TextStyle(color: Renk.ikinci)),
          const Spacer(),
          Text(para(pay), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 6),
        Text('Yukarı yuvarlanır (eksik tahsilat olmaz); kalan tutar her ödemeden sonra yeniden hesaplanır.',
            style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      ]);
    },
    dugmeler: (ctx, yenile) {
      final n = int.tryParse(c.text.trim()) ?? 0;
      final pay = n >= 2 ? (kalan / n).ceil() : 0;
      return [
        OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: pay <= 0 ? null : () => Navigator.pop(ctx, pay), child: const Text('Tutara yaz')),
      ];
    },
  );
}

/* ───────── Fiş yazıcısı (§4.18) ───────── */

/// Döner: seçilen yazıcı id'si (0 = seçimi kaldır), null = değişiklik yok;
/// `deneme` true ise "Deneme fişi bas" istendi.
Future<({int? yazici, bool deneme})?> yaziciPenceresi(BuildContext context,
    {required List<Json> yazicilar, required int? secili, required bool ajanVar, required bool adisyonVar}) {
  var s = secili;
  return kasaPenceresi<({int? yazici, bool deneme})>(
    context,
    baslik: 'Fiş yazıcısı',
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        'Kasa fişlerinin hangi yazıcıdan çıkacağını seçin. Seçim işletme genelinde saklanır; fiş kuyruğa gider ve yazdırma ajanı doğru yazıcıya basar.',
        style: TextStyle(fontSize: 13, color: Renk.ikinci),
      ),
      const SizedBox(height: 10),
      if (yazicilar.isEmpty)
        Text('Tanımlı yazıcı yok. Ayarlar > Yazıcılar bölümünden ekleyin.', style: TextStyle(fontSize: 13, color: Renk.uyari))
      else
        DropdownButtonFormField<int>(
          initialValue: s ?? 0,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: 0, child: Text('Yazıcı seçilmedi')),
            for (final y in yazicilar)
              DropdownMenuItem(
                value: tamSayi(y['id']),
                child: Text(
                    '${y['name']} · ${y['station_label'] ?? y['station'] ?? ''}${y['connection'] == 'os' ? ' · bilgisayara tanımlı' : (y['target'] != null ? ' · ${y['target']}' : '')}',
                    overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => yenile(() => s = v == 0 ? null : v),
        ),
      if (s != null && !ajanVar) ...[
        const SizedBox(height: 8),
        Text('Yazdırma ajanı çevrimdışı; fişler kuyrukta bekler, ajan açılınca basılır.', style: TextStyle(fontSize: 12, color: Renk.uyari)),
      ],
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx, (yazici: s ?? 0, deneme: false)), child: const Text('Kapat')),
      if (s != null) FilledButton(onPressed: adisyonVar ? () => Navigator.pop(ctx, (yazici: s, deneme: true)) : null, child: const Text('Deneme fişi bas')),
    ],
  );
}

/* ───────── Fiş önizleme (renderPaymentTicketBody) ───────── */

class FisGorunumu extends StatelessWidget {
  const FisGorunumu({super.key, required this.fis});
  final Json fis;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black, height: 1.35);
    final satirlar = (fis['lines'] as List? ?? const []).whereType<Map>().toList();
    final toplamlar = (fis['totals'] as List? ?? const []).whereType<Map>().toList();
    final odemeler = (fis['payments'] as List? ?? const []).whereType<Map>().toList();
    final alt = (fis['footer'] as List? ?? const []).map((e) => '$e').toList();
    Widget cizgi([bool kalin = false]) => Container(margin: const EdgeInsets.symmetric(vertical: 6), height: kalin ? 2 : 1, color: Colors.black);
    Widget iki(String a, String b, {bool kalin = false, bool ters = false}) => Container(
          color: ters ? Colors.black : null,
          padding: ters ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3) : EdgeInsets.zero,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(a, style: mono.copyWith(fontWeight: kalin || ters ? FontWeight.w800 : null, color: ters ? Colors.white : null, fontSize: ters ? 15 : null))),
            Text(b, style: mono.copyWith(fontWeight: kalin || ters ? FontWeight.w800 : null, color: ters ? Colors.white : null, fontSize: ters ? 15 : null)),
          ]),
        );
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('${fis['business'] ?? ''}'.toUpperCase(), textAlign: TextAlign.center, style: mono.copyWith(fontSize: 16, fontWeight: FontWeight.w800)),
        if ('${fis['branch'] ?? ''}'.isNotEmpty) Text('${fis['branch']}', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 11)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
          child: Text('${fis['kindLabel'] ?? ''}', textAlign: TextAlign.center, style: mono.copyWith(fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 6),
        iki('${fis['destination'] ?? ''}', '#${fis['orderNo'] ?? ''}', kalin: true),
        Text('${fis['time'] ?? ''}', style: mono.copyWith(fontSize: 11)),
        cizgi(true),
        iki('ÜRÜN', 'TUTAR', kalin: true),
        cizgi(),
        for (final s in satirlar) iki('${s['name']}', '${s['amount'] ?? ''}'),
        cizgi(),
        for (final t in toplamlar) iki('${t['label']}', '${t['value']}', ters: t['big'] == true),
        if (odemeler.isNotEmpty) ...[cizgi(true), for (final p in odemeler) iki('${p['label']}', '${p['value'] ?? ''}')],
        cizgi(true),
        for (final f in alt) Text(f, textAlign: TextAlign.center, style: mono.copyWith(fontSize: 11)),
        Text('✂ - - - - - - - - - - - -', textAlign: TextAlign.center, style: mono.copyWith(fontSize: 11)),
      ]),
    );
  }
}

/// Önizleme; döner true → "Yazdır" (kuyruğa gönder).
Future<bool> fisOnizle(BuildContext context, {required String baslik, required Json fis, required String? yaziciAdi}) async {
  final r = await kasaPenceresi<bool>(
    context,
    baslik: baslik,
    genislik: 420,
    icerik: (ctx, yenile) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .6),
        color: Renk.ic,
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(child: FisGorunumu(fis: fis)),
      ),
      const SizedBox(height: 8),
      Text(
        yaziciAdi != null
            ? 'Fiş, seçili $yaziciAdi yazıcısına gönderilir.'
            : 'Yazıcı seçilmedi. Fişi basmak için "Fiş yazıcısı" bölümünden bir kasa yazıcısı seçin.',
        style: TextStyle(fontSize: 12, color: Renk.ikinci),
      ),
    ]),
    dugmeler: (ctx, yenile) => [
      OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kapat')),
      FilledButton.icon(
        onPressed: yaziciAdi == null ? null : () => Navigator.pop(ctx, true),
        icon: const Icon(Icons.print_outlined, size: 16),
        label: const Text('Yazdır'),
      ),
    ],
  );
  return r ?? false;
}

/* ───────── Ürün ekle (OrderAddItemDialog) ───────── */

Future<Urun?> urunSecPenceresi(BuildContext context, Katalog katalog) {
  var arama = '';
  return kasaPenceresi<Urun>(
    context,
    baslik: 'Adisyona ürün ekle',
    genislik: 480,
    icerik: (ctx, yenile) {
      final n = aramaAnahtari(arama);
      final liste = arama.isEmpty
          ? ([...katalog.urunler]..sort((a, b) => b.kullanim.compareTo(a.kullanim))).take(40).toList()
          : katalog.urunler.where((u) => u.arama.contains(n)).take(60).toList();
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ürün ara…', prefixIcon: Icon(Icons.search_rounded, size: 18)),
          onChanged: (v) => yenile(() => arama = v.trim()),
        ),
        const SizedBox(height: 8),
        if (arama.isEmpty) Text('Son 30 günde en çok adisyona eklenen ürünler', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        if (liste.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Ürün bulunamadı', textAlign: TextAlign.center)),
        for (final u in liste)
          ListTile(
            dense: true,
            enabled: u.mevcut,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(u.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text(u.mevcut ? u.fiyatEtiketi('table') : 'tükendi',
                style: TextStyle(fontWeight: FontWeight.w700, color: u.mevcut ? Renk.marka : Renk.hata)),
            onTap: () => Navigator.pop(ctx, u),
          ),
      ]);
    },
    dugmeler: (ctx, yenile) => [OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
  );
}
