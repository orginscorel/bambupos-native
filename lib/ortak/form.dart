import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/tema.dart';
import 'dugme.dart';
import 'ortak.dart';

export 'dugme.dart';

/// Seçilebilir köşeli çip (8 px, hap değil). Seçiliyken marka degradesi.
class SecimCipi extends StatelessWidget {
  const SecimCipi({super.key, required this.yazi, required this.secili, required this.onTap, this.ikon, this.alt, this.renk});
  final String yazi;
  final bool secili;
  final VoidCallback? onTap;
  final IconData? ikon;
  final String? alt;
  final Color? renk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final vurgu = renk ?? r.birincil;
    return Semantics(
      selected: secili,
      child: Basilir(
        onTap: onTap,
        etiket: alt == null ? yazi : '$yazi, $alt',
        olcek: .95,
        child: AnimatedContainer(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: secili && renk == null ? Marka.grad : null,
            color: secili ? (renk == null ? null : vurgu.withValues(alpha: r.koyu ? .3 : .14)) : r.kart,
            borderRadius: Marka.yaricap,
            border: Border.all(color: secili ? (renk == null ? Colors.transparent : vurgu) : r.kenar),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ikon != null) ...[Icon(ikon, size: 17, color: secili ? (renk == null ? Colors.white : vurgu) : r.soluk), const SizedBox(width: 6)],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      yazi,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secili ? (renk == null ? Colors.white : vurgu) : r.metin,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.2,
                      ),
                    ),
                    if (alt != null)
                      Text(
                        alt!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: secili && renk == null ? Colors.white70 : r.silik, fontSize: 11, height: 1.2),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form alanı başlığı.
class AlanBasligi extends StatelessWidget {
  const AlanBasligi(this.yazi, {super.key, this.sag});
  final String yazi;
  final Widget? sag;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            yazi,
            style: TextStyle(color: context.pa.soluk, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: .2),
          ),
        ),
        ?sag,
      ],
    ),
  );
}

/// Bilgi notu (ör. "Personele bildirim gider").
class BilgiNotu extends StatelessWidget {
  const BilgiNotu(this.metin, {super.key, this.ikon = Icons.notifications_active_rounded, this.renk});
  final String metin;
  final IconData ikon;
  final Color? renk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final c = renk ?? r.birincil;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: r.koyu ? .16 : .07),
        borderRadius: Marka.yaricap,
        border: Border.all(color: c.withValues(alpha: .25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ikon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(metin, style: TextStyle(color: r.metin, fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Alttan açılan sayfa iskeleti: tutamak, başlık, kaydırılabilir gövde,
/// klavyeyle yükselen alt düğme alanı.
class AltSayfa extends StatelessWidget {
  const AltSayfa({super.key, required this.baslik, required this.children, this.alt, this.dugmeler, this.ikon});
  final String baslik;
  final String? alt;
  final IconData? ikon;
  final List<Widget> children;
  final Widget? dugmeler;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * .92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: r.kenar, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  if (ikon != null) ...[
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(gradient: Marka.grad, borderRadius: Marka.yaricap),
                      child: Icon(ikon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(baslik, style: gosterim(19, renk: r.metin)),
                        ),
                        if (alt != null) Text(alt!, style: TextStyle(color: r.silik, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded, color: r.silik),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: children),
            ),
            if (dugmeler != null)
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + (mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom)),
                decoration: BoxDecoration(
                  color: r.kart,
                  border: Border(top: BorderSide(color: r.kenar)),
                ),
                child: dugmeler,
              ),
          ],
        ),
      ),
    );
  }
}

Future<T?> altSayfaAc<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: context.pa.kart,
  builder: builder,
);

/// Evet/hayır penceresi.
Future<bool> onayIste(BuildContext context, {required String baslik, String? mesaj, String evet = 'Evet', bool tehlikeli = false}) async {
  final r = context.pa;
  final s = await pencereAc<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(baslik),
      content: mesaj == null ? null : Text(mesaj),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Vazgeç')),
        FilledButton(
          style: tehlikeli ? FilledButton.styleFrom(backgroundColor: r.eksi) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(evet),
        ),
      ],
    ),
  );
  return s ?? false;
}

/// Kısa metin isteyen pencere (ret notu, düzeltme gerekçesi).
Future<String?> metinIste(BuildContext context, {required String baslik, String? ipucu, String evet = 'Tamam', int enAz = 0}) async {
  final c = TextEditingController();
  final s = await pencereAc<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) => AlertDialog(
        title: Text(baslik),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 255,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => yenile(() {}),
          decoration: InputDecoration(hintText: ipucu),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Vazgeç')),
          FilledButton(onPressed: c.text.trim().length < enAz ? null : () => Navigator.of(ctx).pop(c.text.trim()), child: Text(evet)),
        ],
      ),
    ),
  );
  return s;
}

/// Sunucu hatasını kibar bildirime çevirir. 403 → yetki mesajı.
void hataBildir(Object e, {String baslik = 'İşlem tamamlanamadı', String? yetkiMesaji}) {
  HapticFeedback.heavyImpact();
  if (e is ApiHata) {
    if (e.yetkiYok) {
      bildir('Yetkiniz yok', mesaj: yetkiMesaji ?? 'Bu işlem için yetkiniz yok. İşletme sahibinden yetki isteyebilirsiniz.', tur: BildirimTur.uyari);
      return;
    }
    bildir(baslik, mesaj: e.mesaj, tur: BildirimTur.hata);
    return;
  }
  bildir(baslik, mesaj: 'Beklenmeyen bir sorun oluştu.', tur: BildirimTur.hata);
}

/// Yükleme göstergeli tam genişlik birincil düğme.
class KaydetDugmesi extends StatelessWidget {
  const KaydetDugmesi({super.key, required this.yazi, required this.onPressed, this.mesgul = false, this.ikon = Icons.check_rounded});
  final String yazi;
  final VoidCallback? onPressed;
  final bool mesgul;
  final IconData ikon;
  @override
  Widget build(BuildContext context) => GradDugme(yazi: yazi, ikon: ikon, onTap: onPressed, yukleniyor: mesgul);
}

/// Saat seçimi kutusu ("Başlangıç 09:00").
class SaatKutusu extends StatelessWidget {
  const SaatKutusu({super.key, required this.ad, required this.saat, required this.onTap, this.not});
  final String ad;
  final TimeOfDay saat;
  final VoidCallback onTap;
  final String? not;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final s = '${saat.hour.toString().padLeft(2, '0')}:${saat.minute.toString().padLeft(2, '0')}';
    return Basilir(
      onTap: onTap,
      etiket: '$ad $s. Değiştir',
      olcek: .97,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: r.ic, borderRadius: Marka.yaricap),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ad, style: TextStyle(color: r.silik, fontSize: 12)),
                  Text(s, style: gosterim(22, renk: r.metin)),
                ],
              ),
            ),
            if (not != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: r.uyari.withValues(alpha: .15), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  not!,
                  style: TextStyle(color: r.uyari, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.schedule_rounded, color: r.silik, size: 20),
          ],
        ),
      ),
    );
  }
}

Future<TimeOfDay?> saatSec(BuildContext context, TimeOfDay ilk, {String? baslik}) => showTimePicker(
  context: context,
  initialTime: ilk,
  helpText: baslik ?? 'Saat seçin',
  cancelText: 'Vazgeç',
  confirmText: 'Tamam',
  builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
);

Future<DateTime?> gunSec(BuildContext context, DateTime ilk, {DateTime? ilkGun, DateTime? sonGun}) => showDatePicker(
  context: context,
  initialDate: ilk,
  firstDate: ilkGun ?? DateTime(ilk.year - 1),
  lastDate: sonGun ?? DateTime(ilk.year + 1, 12, 31),
  cancelText: 'Vazgeç',
  confirmText: 'Tamam',
  locale: const Locale('tr', 'TR'),
);

String saatYaz(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
