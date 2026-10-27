import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../core/bicim.dart';
import '../core/bildirim.dart';
import '../core/tema.dart';
import '../ortak/ortak.dart';

/// BİLDİRİMLER: GET /api/v1/notifications; okundu: POST …/{id}/read, read-all.
class BildirimlerEkrani extends StatefulWidget {
  const BildirimlerEkrani({super.key});
  @override
  State<BildirimlerEkrani> createState() => _BildirimlerEkraniState();
}

class _BildirimlerEkraniState extends State<BildirimlerEkrani> {
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yenile();
  }

  Future<void> _yenile() async {
    await BildirimMerkezi.yokla(ilk: true);
    if (mounted) setState(() => _yukleniyor = false);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: BildirimMerkezi.liste,
      builder: (_, liste, _) => ValueListenableBuilder<int>(
        valueListenable: BildirimMerkezi.okunmamis,
        builder: (_, okunmamis, _) => PaSayfa(
          baslik: 'Bildirimler',
          alt: okunmamis > 0 ? '$okunmamis okunmamış' : 'Hepsi okundu',
          geri: true,
          yenile: _yenile,
          sag: okunmamis > 0 ? TextButton(onPressed: BildirimMerkezi.hepsiOkundu, child: const Text('Tümünü okundu say')) : null,
          children: [
            if (_yukleniyor && liste.isEmpty)
              const Column(children: [Iskelet(yukseklik: 64), SizedBox(height: 8), Iskelet(yukseklik: 64), SizedBox(height: 8), Iskelet(yukseklik: 64)])
            else if (liste.isEmpty)
              const PaKart(child: BosDurum(baslik: 'Bildirim yok', ikon: Icons.notifications_none_rounded))
            else
              for (var i = 0; i < liste.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Belirme(
                    sira: i,
                    child: PaKart(
                      padding: const EdgeInsets.all(12),
                      renk: liste[i].b('read') ? null : r.birincilYumusak,
                      etiket: '${liste[i].b('read') ? '' : 'Okunmamış. '}${liste[i].s('title')}. ${liste[i].s('body')}',
                      onTap: liste[i].b('read') ? null : () => BildirimMerkezi.okundu(liste[i].i('id')),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(liste[i].b('read') ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, color: r.birincil, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(liste[i].s('title', 'Bildirim'), style: TextStyle(fontWeight: FontWeight.w700, color: r.metin)),
                            if (liste[i].s('body').isNotEmpty) Text(liste[i].s('body'), style: TextStyle(color: r.soluk, fontSize: 13)),
                            if (DateTime.tryParse(liste[i].s('created_at')) != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(Bicim.tarihSaat(DateTime.parse(liste[i].s('created_at'))), style: TextStyle(color: r.silik, fontSize: 11.5)),
                              ),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
