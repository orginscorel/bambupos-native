import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/raporlar.dart';
import '../core/tema.dart';
import '../ortak/donem.dart';
import '../ortak/ortak.dart';
import 'kabuk.dart';
import 'rapor.dart';

/// RAPORLAR merkezi: katalogdaki raporlar gruplu liste; arama + dönem.
/// Seçilen dönem açılan rapora taşınır.
class RaporlarEkrani extends StatefulWidget {
  const RaporlarEkrani({super.key});
  @override
  State<RaporlarEkrani> createState() => _RaporlarEkraniState();
}

class _RaporlarEkraniState extends State<RaporlarEkrani> {
  Donem _donem = Donem.hazir(DonemTur.bugun);
  String _ara = '';

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final q = _ara.trim().toLowerCase();
    final liste = raporlar.where((t) => q.isEmpty || t.baslik.toLowerCase().contains(q) || (t.aciklama ?? '').toLowerCase().contains(q)).toList();
    var sira = 0;
    return PaSayfa(
      baslik: 'Raporlar',
      alt: 'Bir rapora dokunun; seçili dönemle açılır',
      children: [
        DonemSecici(secili: _donem, degisti: (d) => setState(() => _donem = d)),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _ara = v),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Rapor ara'),
        ),
        const SizedBox(height: 16),
        for (final g in RaporGrup.values)
          if (liste.any((t) => t.grup == g)) ...[
            Belirme(
              sira: sira++,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                child: Row(children: [
                  Icon(g.ikon, size: 18, color: r.birincil),
                  const SizedBox(width: 8),
                  Semantics(header: true, child: Text(g.ad, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: r.metin))),
                ]),
              ),
            ),
            Belirme(
              sira: sira++,
              child: SatirGrubu([
                for (final t in liste.where((t) => t.grup == g))
                  Satir(
                    baslik: t.baslik,
                    alt: t.aciklama,
                    ikon: _ikon(t),
                    onTap: () => git(context, RaporEkrani(tanim: t, donem: _donem)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
          ],
        if (liste.isEmpty) const BosDurum(baslik: 'Rapor bulunamadı', ikon: Icons.search_off_rounded),
      ],
    );
  }

  IconData _ikon(RaporTanim t) => switch (t.grafik) {
        GrafikTur.cizgi => Icons.show_chart_rounded,
        GrafikTur.sutun => Icons.bar_chart_rounded,
        GrafikTur.siraliSutun => Icons.leaderboard_rounded,
        GrafikTur.yok => Icons.table_rows_rounded,
      };
}
