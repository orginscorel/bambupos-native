import 'package:flutter/material.dart';

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

/// Varyant + seçenek + adet + not. Zorunlu gruplar seçilmeden "Ekle" kapalı.
Future<UrunSecimi?> urunSecimiAc(BuildContext context, Urun urun) {
  final genis = MediaQuery.sizeOf(context).width >= 700;
  final icerik = _UrunSecimi(urun: urun);
  if (genis) {
    return showDialog<UrunSecimi>(
      context: context,
      builder: (_) => Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720), child: icerik)),
    );
  }
  return showModalBottomSheet<UrunSecimi>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(heightFactor: .9, child: icerik),
  );
}

class _UrunSecimi extends StatefulWidget {
  const _UrunSecimi({required this.urun});
  final Urun urun;

  @override
  State<_UrunSecimi> createState() => _UrunSecimiState();
}

class _UrunSecimiState extends State<_UrunSecimi> {
  int? _varyant;
  final Map<int, Set<int>> _secim = {};
  int _adet = 1;
  final _not = TextEditingController();

  Urun get u => widget.urun;

  @override
  void initState() {
    super.initState();
    if (u.varyantlar.isNotEmpty) {
      _varyant = u.varyantlar.firstWhere((v) => v.varsayilan, orElse: () => u.varyantlar.first).id;
    }
    for (final g in u.gruplar) {
      _secim[g.id] = g.secenekler.where((s) => s.varsayilan).map((s) => s.id).toSet();
      if (g.tekli && _secim[g.id]!.length > 1) _secim[g.id] = {_secim[g.id]!.first};
    }
  }

  @override
  void dispose() {
    _not.dispose();
    super.dispose();
  }

  int get _birim {
    var f = u.fiyat;
    if (_varyant != null) {
      final v = u.varyantlar.firstWhere((v) => v.id == _varyant);
      if (v.fiyat > 0) f = v.fiyat;
    }
    for (final g in u.gruplar) {
      for (final s in g.secenekler) {
        if (_secim[g.id]!.contains(s.id)) f += s.fiyat;
      }
    }
    return f;
  }

  String? _eksik() {
    for (final g in u.gruplar) {
      final n = _secim[g.id]!.length;
      final enAz = g.zorunlu ? (g.enAz < 1 ? 1 : g.enAz) : g.enAz;
      if (n < enAz) return '“${g.ad}” için seçim yapın';
    }
    return null;
  }

  void _dokun(SecenekGrubu g, Secenek s) {
    setState(() {
      final sec = _secim[g.id]!;
      if (g.tekli) {
        if (sec.contains(s.id) && !g.zorunlu) {
          sec.clear();
        } else {
          sec
            ..clear()
            ..add(s.id);
        }
      } else if (sec.contains(s.id)) {
        sec.remove(s.id);
      } else if (g.enCok == null || g.enCok == 0 || sec.length < g.enCok!) {
        sec.add(s.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final eksik = _eksik();

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Row(children: [
          Expanded(child: Text(u.ad, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      const Divider(),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), children: [
          if (u.varyantlar.length > 1) ...[
            const _Baslik('Seçenek'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in u.varyantlar)
                _SecimKutusu(
                  etiket: v.ad,
                  ek: para(v.fiyat > 0 ? v.fiyat : u.fiyat),
                  secili: _varyant == v.id,
                  bas: () => setState(() => _varyant = v.id),
                ),
            ]),
            const SizedBox(height: 18),
          ],
          for (final g in u.gruplar) ...[
            _Baslik(g.ad,
                ek: g.zorunlu ? 'Zorunlu' : (g.tekli ? 'Tek seçim' : (g.enCok != null && g.enCok! > 0 ? 'En çok ${g.enCok}' : 'Çoklu'))),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in g.secenekler)
                _SecimKutusu(
                  etiket: s.ad,
                  ek: s.fiyat > 0 ? '+${para(s.fiyat)}' : null,
                  secili: _secim[g.id]!.contains(s.id),
                  bas: () => _dokun(g, s),
                ),
            ]),
            const SizedBox(height: 18),
          ],
          const _Baslik('Not'),
          TextField(controller: _not, maxLength: 255, decoration: const InputDecoration(hintText: 'Örn. az pişmiş, soğansız')),
        ]),
      ),
      const Divider(),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            _AdetSecici(adet: _adet, degisti: (a) => setState(() => _adet = a)),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: eksik != null
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
                child: Text(eksik ?? 'Ekle · ${para(_birim * _adet)}'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.metin, {this.ek});
  final String metin;
  final String? ek;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(metin, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          if (ek != null) ...[
            const SizedBox(width: 8),
            Text(ek!, style: const TextStyle(color: Renk.soluk, fontSize: 12)),
          ],
        ]),
      );
}

class _SecimKutusu extends StatelessWidget {
  const _SecimKutusu({required this.etiket, this.ek, required this.secili, required this.bas});
  final String etiket;
  final String? ek;
  final bool secili;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: secili ? Renk.markaAcik : Renk.yuzey,
      borderRadius: koseYuvarlak,
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: bas,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: koseYuvarlak,
            border: Border.all(color: secili ? Renk.marka : Renk.cizgi, width: secili ? 2 : 1),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etiket, style: TextStyle(fontWeight: FontWeight.w700, color: secili ? Renk.marka : Renk.yazi)),
            if (ek != null) Text(ek!, style: const TextStyle(fontSize: 12, color: Renk.soluk)),
          ]),
        ),
      ),
    );
  }
}

class _AdetSecici extends StatelessWidget {
  const _AdetSecici({required this.adet, required this.degisti});
  final int adet;
  final ValueChanged<int> degisti;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Renk.cizgi), borderRadius: koseYuvarlak),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: adet > 1 ? () => degisti(adet - 1) : null, icon: const Icon(Icons.remove_rounded)),
        SizedBox(width: 32, child: Text('$adet', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        IconButton(onPressed: adet < 100 ? () => degisti(adet + 1) : null, icon: const Icon(Icons.add_rounded)),
      ]),
    );
  }
}
