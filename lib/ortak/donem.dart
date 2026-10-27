import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/bicim.dart';
import '../core/durum.dart';
import '../core/tema.dart';

enum DonemTur { bugun, dun, hafta, ay, ozel }

/// Seçili tarih aralığı. "Bugün" sunucunun AÇIK İŞ GÜNÜDÜR (gün sonu
/// alınmadıysa gece yarısından sonra da önceki gün); diğerleri son bilinen
/// iş gününden hesaplanır.
class Donem {
  const Donem._(this.tur, this.bas, this.son);

  final DonemTur tur;
  final DateTime bas;
  final DateTime son;

  factory Donem.hazir(DonemTur t, {DateTime? isGunu}) {
    final g = isGunu ?? Uyg.isGunu;
    return switch (t) {
      DonemTur.bugun => Donem._(t, g, g),
      DonemTur.dun => Donem._(t, g.subtract(const Duration(days: 1)), g.subtract(const Duration(days: 1))),
      DonemTur.hafta => Donem._(t, g.subtract(Duration(days: g.weekday - 1)), g),
      DonemTur.ay => Donem._(t, DateTime(g.year, g.month, 1), g),
      DonemTur.ozel => Donem._(t, g, g),
    };
  }

  factory Donem.ozel(DateTime a, DateTime b) => Donem._(DonemTur.ozel, a.isAfter(b) ? b : a, a.isAfter(b) ? a : b);

  String get ad => switch (tur) {
        DonemTur.bugun => 'Bugün',
        DonemTur.dun => 'Dün',
        DonemTur.hafta => 'Bu hafta',
        DonemTur.ay => 'Bu ay',
        DonemTur.ozel => Bicim.aralik(bas, son),
      };

  /// Kıyas cümlelerinde: "dünden", "geçen haftadan" …
  String get kiyasAdi => switch (tur) {
        DonemTur.bugun => 'düne göre',
        DonemTur.dun => 'önceki güne göre',
        DonemTur.hafta => 'önceki haftaya göre',
        DonemTur.ay => 'önceki eşit döneme göre',
        DonemTur.ozel => 'önceki eşit döneme göre',
      };

  int get gunSayisi => son.difference(bas).inDays + 1;

  /// Patron özeti (/api/v1/boss/overview) sorgusu.
  Map<String, dynamic> get ozetSorgu => switch (tur) {
        DonemTur.bugun => {'period': 'day'},
        DonemTur.hafta => {'period': 'week'},
        DonemTur.ay => {'period': 'month'},
        _ => {'from': Bicim.iso(bas), 'to': Bicim.iso(son)},
      };

  /// Rapor uçları (/api/v1/reports/…) sorgusu.
  Map<String, dynamic> get raporSorgu => switch (tur) {
        DonemTur.bugun => {'range': 'today'},
        DonemTur.dun => {'range': 'yesterday'},
        DonemTur.ay => {'range': 'month'},
        _ => {'from': Bicim.iso(bas), 'to': Bicim.iso(son)},
      };

  @override
  bool operator ==(Object other) => other is Donem && other.tur == tur && other.bas == bas && other.son == son;

  @override
  int get hashCode => Object.hash(tur, bas, son);
}

/// Yatay kaydırılan dönem seçici: Bugün / Dün / Bu hafta / Bu ay / Tarih seç.
class DonemSecici extends StatelessWidget {
  const DonemSecici({super.key, required this.secili, required this.degisti});
  final Donem secili;
  final ValueChanged<Donem> degisti;

  Future<void> _ozel(BuildContext context) async {
    final simdi = Uyg.isGunu;
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(simdi.year - 3),
      lastDate: simdi,
      initialDateRange: DateTimeRange(start: secili.bas, end: secili.son),
      helpText: 'Tarih aralığı seçin',
      saveText: 'Uygula',
      cancelText: 'Vazgeç',
      locale: const Locale('tr', 'TR'),
    );
    if (r != null) degisti(Donem.ozel(r.start, r.end));
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    Widget cip(String yazi, bool aktif, VoidCallback onTap, {IconData? ikon}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Semantics(
            selected: aktif,
            child: Basilir(
              onTap: onTap,
              etiket: yazi,
              child: AnimatedContainer(
                duration: Hareket.orta,
                curve: Hareket.giris,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: aktif ? Marka.grad : null,
                  color: aktif ? null : r.kart,
                  borderRadius: Marka.yaricap,
                  border: Border.all(color: aktif ? Colors.transparent : r.kenar),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (ikon != null) ...[Icon(ikon, size: 17, color: aktif ? Colors.white : r.soluk), const SizedBox(width: 6)],
                  Text(yazi, style: TextStyle(color: aktif ? Colors.white : r.metin, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ]),
              ),
            ),
          ),
        );
    return SizedBox(
      height: 46,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final t in [DonemTur.bugun, DonemTur.dun, DonemTur.hafta, DonemTur.ay])
          cip(Donem.hazir(t).ad, secili.tur == t, () => degisti(Donem.hazir(t))),
        cip(secili.tur == DonemTur.ozel ? secili.ad : 'Tarih seç', secili.tur == DonemTur.ozel, () => _ozel(context), ikon: Icons.date_range_rounded),
      ]),
    );
  }
}
