import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';

class UrunSecimi {
  UrunSecimi({required this.varyantId, required this.secenekler, required this.adet, this.not, required this.birimFiyat, required this.etiket});
  final int? varyantId;
  final List<int> secenekler;
  final int adet;
  final String? not;
  final int birimFiyat;
  final String etiket;
}

/// Ürün yapılandırma penceresi — web Detail.vue §4.1 birebir:
/// "Boyut / Porsiyon" varyantları, seçenek grupları (tek seçim / en çok n /
/// çoklu), ücretsiz seçenek limiti, adet sınırları, not.
Future<UrunSecimi?> urunSecimiAc(BuildContext context, Urun urun, {String kanal = 'table'}) {
  return pencereAc<UrunSecimi>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 512, maxHeight: 760), child: _UrunSecimi(urun: urun, kanal: kanal)),
    ),
  );
}

class _UrunSecimi extends StatefulWidget {
  const _UrunSecimi({required this.urun, required this.kanal});
  final Urun urun;
  final String kanal;

  @override
  State<_UrunSecimi> createState() => _UrunSecimiState();
}

class _UrunSecimiState extends State<_UrunSecimi> {
  int? _varyant;
  final Map<int, List<int>> _secim = {}; // seçim sırası korunur
  late int _adet = widget.urun.minAdet;
  final _not = TextEditingController();

  Urun get u => widget.urun;

  @override
  void initState() {
    super.initState();
    if (u.varyantlar.isNotEmpty) {
      _varyant = u.varyantlar.firstWhere((v) => v.varsayilan, orElse: () => u.varyantlar.first).id;
    }
    for (final g in u.gruplar) {
      final v = g.secenekler.where((s) => s.varsayilan).map((s) => s.id).toList();
      _secim[g.id] = g.tekli && v.length > 1 ? [v.first] : v;
    }
  }

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  /// Grup fiyatı: seçilenler pahalıdan ucuza; ilk `free_limit` tanesi ücretsiz.
  int _grupFiyati(SecenekGrubu g) {
    final f = [
      for (final s in g.secenekler)
        if (_secim[g.id]!.contains(s.id)) s.fiyat,
    ]..sort((a, b) => b.compareTo(a));
    return f.skip(g.ucretsizLimit).fold(0, (t, x) => t + x);
  }

  int get _birim {
    var f = u.kanalFiyati(widget.kanal);
    if (_varyant != null) {
      final v = u.varyantlar.firstWhere((v) => v.id == _varyant);
      f = v.fiyat;
    }
    for (final g in u.gruplar) {
      f += _grupFiyati(g);
    }
    return f;
  }

  bool get _zorunluEksik => u.gruplar.any((g) => g.zorunlu && g.secenekler.isNotEmpty && _secim[g.id]!.isEmpty);
  bool get _adetGecerli => _adet >= u.minAdet && _adet <= u.maxAdet;

  void _dokun(SecenekGrubu g, Secenek s) {
    setState(() {
      final sec = _secim[g.id]!;
      if (g.tekli) {
        sec
          ..clear()
          ..add(s.id);
      } else if (sec.contains(s.id)) {
        sec.remove(s.id);
      } else if (g.enCok == null || g.enCok == 0 || sec.length < g.enCok!) {
        sec.add(s.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final gorsel = u.gorsel;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
        child: Row(children: [
          Expanded(child: Text(u.ad, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 12), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (gorsel != null) ...[
              InkWell(
                onTap: () => pencereAc<void>(
                  context: context,
                  builder: (ctx) => Dialog(child: InkWell(onTap: () => Navigator.pop(ctx), child: CachedNetworkImage(imageUrl: u.ham['image_url']?.toString() ?? gorsel))),
                ),
                child: ClipRRect(borderRadius: koseYuvarlak, child: CachedNetworkImage(imageUrl: gorsel, width: 64, height: 64, fit: BoxFit.cover)),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Renk.bilgiZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.bilgiKenar)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: Renk.bilgi),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: u.ad, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: ' adisyona eklenecek. Adedi seçip onaylayın; yanlışsa '),
                        const TextSpan(text: 'Vazgeç', style: TextStyle(fontWeight: FontWeight.w700)),
                        const TextSpan(text: ' ile başka ürün seçin.'),
                      ]),
                      style: TextStyle(fontSize: 13, color: Renk.yazi),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
          if (u.varyantlar.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Boyut / Porsiyon', style: TextStyle(fontWeight: FontWeight.w600)),
            RadioGroup<int>(
              groupValue: _varyant,
              onChanged: (x) => setState(() => _varyant = x),
              child: Column(children: [
                for (final v in u.varyantlar)
                  RadioListTile<int>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: v.id,
                    title: Text('${v.ad} — ${para(v.fiyat)}'),
                  ),
              ]),
            ),
          ],
          for (final g in u.gruplar.where((g) => g.secenekler.isNotEmpty)) ...[
            const SizedBox(height: 14),
            Text.rich(TextSpan(children: [
              TextSpan(text: g.ad, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (g.zorunlu) TextSpan(text: ' *', style: TextStyle(color: Renk.hata)),
              TextSpan(
                text: g.tekli ? '  (tek seçim)' : (g.enCok != null && g.enCok! > 0 ? '  (en çok ${g.enCok})' : '  (çoklu seçim)'),
                style: TextStyle(fontSize: 12, color: Renk.soluk),
              ),
            ])),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in g.secenekler)
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _dokun(g, s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: _secim[g.id]!.contains(s.id) ? Renk.marka : Renk.yuzey,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _secim[g.id]!.contains(s.id) ? Renk.marka : Renk.cizgiKoyu),
                    ),
                    child: Text(
                      s.fiyat > 0 ? '${s.ad} +${para(s.fiyat)}' : s.ad,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _secim[g.id]!.contains(s.id) ? Colors.white : Renk.yazi),
                    ),
                  ),
                ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            const Text('Adet', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            IconButton.outlined(
              tooltip: 'Azalt',
              onPressed: _adet > u.minAdet ? () => setState(() => _adet--) : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            SizedBox(width: 44, child: Text('$_adet', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            IconButton.outlined(
              tooltip: 'Artır',
              onPressed: _adet < u.maxAdet ? () => setState(() => _adet++) : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            const Spacer(),
            Text(para(_birim * _adet), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Renk.marka)),
          ]),
          const SizedBox(height: 14),
          const Text('Not', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(controller: _not, maxLength: 255, decoration: const InputDecoration(hintText: 'ör. az pişmiş, soğansız')),
        ]),
      ),
      const Divider(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(children: [
          if (_zorunluEksik)
            Expanded(child: Text('Zorunlu (*) seçimleri tamamlayın.', style: TextStyle(fontSize: 12, color: Renk.hata)))
          else
            const Spacer(),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _zorunluEksik || !_adetGecerli
                ? null
                : () {
                    final v = _varyant == null ? null : u.varyantlar.firstWhere((x) => x.id == _varyant);
                    Navigator.pop(
                      context,
                      UrunSecimi(
                        varyantId: _varyant,
                        secenekler: _secim.values.expand((e) => e).toList(),
                        adet: _adet,
                        not: _not.text.trim().isEmpty ? null : _not.text.trim(),
                        birimFiyat: _birim,
                        etiket: v != null && u.varyantlar.length > 1 ? '${u.ad} (${v.ad})' : u.ad,
                      ),
                    );
                  },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Adisyona ekle'),
          ),
        ]),
      ),
    ]);
  }
}
