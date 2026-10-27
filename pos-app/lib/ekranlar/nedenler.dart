import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';

/// Web'deki hazır neden listeleri (resources/js/lib/reasons.ts).
const nedenListeleri = <String, List<String>>{
  'item_cancel': [
    'Müşteri vazgeçti', 'Yanlış girildi', 'Yanlış masaya girildi', 'Ürün tükendi', 'Hazırlanamadı', 'Çok uzun sürdü',
    'Müşteri beğenmedi', 'Ürün değişti (yenisi girildi)',
  ],
  'item_comp': [
    'Müşteri memnuniyeti', 'Şikâyet telafisi', 'Geç servis', 'Yanlış ürün geldi', 'Ürün soğuk/bozuk geldi',
    'Personel/aile ikramı', 'Yönetim ikramı', 'Doğum günü ikramı', 'Tanıtım/deneme ikramı',
  ],
  'order_cancel': [
    'Müşteri gitti (sipariş verilmedi)', 'Yanlış masa açıldı', 'Deneme/test adisyonu', 'Müşteri siparişten vazgeçti',
    'Adisyon başka masaya taşındı', 'Sistem/personel hatası',
  ],
  'order_refund': ['Müşteri şikâyeti', 'Yanlış tahsilat', 'Fazla tahsilat', 'Ürün teslim edilmedi', 'Ödeme yöntemi değişti', 'Çift çekim'],
};

/// Web ReasonSelect: ilk 6 neden çip, altında seçici ("Diğer… (yazarak)").
class NedenSecici extends StatefulWidget {
  const NedenSecici({super.key, required this.tur, required this.degisti});
  final String tur;
  final ValueChanged<String> degisti;

  @override
  State<NedenSecici> createState() => _NedenSeciciState();
}

class _NedenSeciciState extends State<NedenSecici> {
  static const _diger = '__diger__';
  String? _secili;
  final _metin = TextEditingController();

  List<String> get _liste => nedenListeleri[widget.tur] ?? const [];

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
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final n in _liste.take(6))
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => _sec(n),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: _secili == n ? Renk.markaAcik : Renk.yuzey,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _secili == n ? Renk.marka : Renk.cizgiKoyu),
              ),
              child: Text(n, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _secili == n ? Renk.marka : Renk.yazi)),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _secili,
        isExpanded: true,
        hint: const Text('Sebep seçin'),
        items: [
          for (final n in _liste) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
          const DropdownMenuItem(value: _diger, child: Text('Diğer… (yazarak)')),
        ],
        onChanged: _sec,
      ),
      if (_secili == _diger) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _metin,
          autofocus: true,
          maxLength: 255,
          decoration: const InputDecoration(hintText: 'Sebebi kısaca yazın…'),
          onChanged: (v) => widget.degisti(v.trim()),
        ),
      ],
    ]);
  }
}

/// Neden modalı (kalem iptal / ikram / adisyon iptal / iade). Döner: neden metni.
Future<String?> nedenSor(BuildContext context, {required String tur, String? ust}) {
  final baslik = switch (tur) {
    'item_cancel' => 'Kalemi iptal et',
    'item_comp' => 'İkram et',
    'order_cancel' => 'Adisyonu iptal et',
    _ => 'İade et',
  };
  var neden = '';
  return pencereAc<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) => AlertDialog(
        title: Text(baslik),
        content: SizedBox(
          width: 384,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (ust != null) ...[Text(ust, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 12)],
              Text.rich(TextSpan(children: [TextSpan(text: 'Neden'), TextSpan(text: ' *', style: TextStyle(color: Renk.hata))]),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              NedenSecici(tur: tur, degisti: (v) => neden = v),
              const SizedBox(height: 6),
              Text('Listeden seçin; farklıysa “Diğer…” ile yazın.', style: TextStyle(fontSize: 12, color: Renk.soluk)),
            ]),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            style: tur == 'item_comp' ? null : FilledButton.styleFrom(backgroundColor: Renk.hata),
            onPressed: () {
              if (neden.trim().length < 3) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                  backgroundColor: Renk.hata,
                  content: Text('Neden zorunlu — en az 3 karakterlik bir neden girin.'),
                ));
                return;
              }
              Navigator.pop(ctx, neden.trim());
            },
            child: const Text('Onayla'),
          ),
        ],
      ),
    ),
  );
}
