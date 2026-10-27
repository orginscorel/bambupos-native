import 'package:flutter/material.dart';

import '../core/canli.dart';
import '../core/tema.dart';
import '../ortak/form.dart';
import '../app/hareket.dart';
import '../ortak/ortak.dart';
import 'gorevler.dart';
import 'mesai.dart';
import 'vardiya.dart';

/// Ortadaki "+" düğmesinin hızlı eylem sayfası.
Future<void> olusturAc(BuildContext context) => altSayfaAc<void>(context, (_) => const OlusturSayfasi());

class OlusturSayfasi extends StatelessWidget {
  const OlusturSayfasi({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([Canli.gorevYetki, Canli.vardiyaYetki, Canli.bekleyenIzin, Canli.bekleyenTakas]),
      builder: (context, _) {
        final gorevKilit = Canli.gorevYetki.value == Yetki.yok;
        final vardiyaKilit = Canli.vardiyaYetki.value == Yetki.yok || Canli.vardiyaYetki.value == Yetki.kapali;
        final bekleyen = Canli.bekleyenIzin.value + Canli.bekleyenTakas.value;
        final nav = Navigator.of(context);
        void ac(Widget s) {
          nav.pop();
          nav.push(MaterialPageRoute(builder: (_) => s));
        }

        final eylemler = <_Eylem>[
          _Eylem(Icons.add_task_rounded, 'Görev oluştur', 'Kişi, öncelik, son tarih', Marka.mor, gorevKilit, () => ac(const GorevFormu())),
          _Eylem(Icons.more_time_rounded, 'Vardiya planla', 'Şablonla hızlı ekle', Marka.mavi, vardiyaKilit, () {
            final ctx = nav.context;
            nav.pop();
            vardiyaFormuAc(ctx);
          }),
          _Eylem(Icons.calendar_view_week_rounded, 'Haftalık plan', 'Kişi × gün takvimi', Marka.gok, Canli.vardiyaYetki.value == Yetki.kapali, () => ac(const VardiyaEkrani())),
          _Eylem(Icons.fact_check_rounded, 'Mesai düzelt', 'Giriş/çıkış, çıkış ver, onay', Marka.zumrut, vardiyaKilit, () => ac(const MesaiEkrani())),
          _Eylem(Icons.beach_access_rounded, 'İzin / rapor gir', 'Personel adına', Marka.kehribar, vardiyaKilit, () {
            final ctx = nav.context;
            nav.pop();
            izinFormuAc(ctx);
          }),
          _Eylem(Icons.inbox_rounded, 'Talepler', bekleyen > 0 ? '$bekleyen onay bekliyor' : 'İzin ve değişim', Marka.gul, vardiyaKilit, () => ac(const MesaiEkrani(sekme: 1)), rozet: bekleyen),
        ];
        return AltSayfa(
          baslik: 'Oluştur',
          alt: 'Ekibe iş ver, vardiya planla, mesaiyi düzelt',
          ikon: Icons.add_rounded,
          children: [
            const SizedBox(height: 8),
            LayoutBuilder(builder: (_, k) {
              final sutun = k.maxWidth >= 520 ? 3 : 2;
              final w = (k.maxWidth - 10 * (sutun - 1)) / sutun;
              return Wrap(spacing: 10, runSpacing: 10, children: [
                for (var i = 0; i < eylemler.length; i++) SizedBox(width: w, child: Belirme(sira: i, child: _EylemKutusu(eylemler[i]))),
              ]);
            }),
            const SizedBox(height: 14),
            const BilgiNotu('Görev, vardiya ve izin kayıtlarında ilgili personelin telefonuna bildirim gider.'),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _Eylem {
  const _Eylem(this.ikon, this.ad, this.alt, this.renk, this.kilitli, this.onTap, {this.rozet = 0});
  final IconData ikon;
  final String ad;
  final String alt;
  final Color renk;
  final bool kilitli;
  final VoidCallback onTap;
  final int rozet;
}

class _EylemKutusu extends StatelessWidget {
  const _EylemKutusu(this.e);
  final _Eylem e;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Basilir(
      onTap: e.kilitli
          ? () => bildir('Yetkiniz yok', mesaj: '"${e.ad}" için işletme sahibinden yetki isteyin.', tur: BildirimTur.uyari)
          : e.onTap,
      etiket: '${e.ad}. ${e.alt}${e.kilitli ? '. Kilitli' : ''}',
      child: Opacity(
        opacity: e.kilitli ? .5 : 1,
        child: Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: r.kart,
            borderRadius: Marka.yaricap,
            border: Border.all(color: r.kenar),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [e.renk.withValues(alpha: r.koyu ? .22 : .09), r.kart],
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: e.renk, borderRadius: Marka.yaricap),
                child: Icon(e.kilitli ? Icons.lock_rounded : e.ikon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              if (e.rozet > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Marka.gul, borderRadius: BorderRadius.circular(5)),
                  child: Text('${e.rozet}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                )
              else
                Icon(Icons.arrow_outward_rounded, size: 18, color: r.silik),
            ]),
            const SizedBox(height: 16),
            Text(e.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w700, fontSize: 14)),
            Text(e.alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.silik, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
