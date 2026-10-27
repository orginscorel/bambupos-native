import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/hareket.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/canli.dart';
import '../core/durum.dart';
import '../core/tema.dart';
import '../ortak/form.dart';
import '../ortak/ortak.dart';
import '../ortak/ust_serit.dart';

/// Görev filtresi.
enum GorevSuzgec { acik, devam, geciken, bugun, biten, tumu }

extension GorevSuzgecX on GorevSuzgec {
  String get ad => switch (this) {
        GorevSuzgec.acik => 'Açık',
        GorevSuzgec.devam => 'Sürüyor',
        GorevSuzgec.geciken => 'Geciken',
        GorevSuzgec.bugun => 'Bugün',
        GorevSuzgec.biten => 'Tamamlanan',
        GorevSuzgec.tumu => 'Tümü',
      };

  bool uyar(Map<String, dynamic> t, DateTime simdi) {
    final st = t.s('status');
    final d = DateTime.tryParse(t.s('due_at'))?.toLocal();
    return switch (this) {
      GorevSuzgec.acik => st != 'done',
      GorevSuzgec.devam => st == 'in_progress',
      GorevSuzgec.geciken => st != 'done' && d != null && d.isBefore(simdi),
      GorevSuzgec.bugun => d != null && d.year == simdi.year && d.month == simdi.month && d.day == simdi.day,
      GorevSuzgec.biten => st == 'done',
      GorevSuzgec.tumu => true,
    };
  }
}

/// Öncelik → (ad, renk).
(String, Color) oncelikBilgi(String p, PaRenk r) => switch (p) {
      'high' => ('Yüksek', r.eksi),
      'low' => ('Düşük', r.silik),
      _ => ('Normal', r.birincil),
    };

String durumAdi(String s) => switch (s) {
      'in_progress' => 'Devam ediyor',
      'done' => 'Tamamlandı',
      _ => 'Açık',
    };

/// GÖREVLER: GET /api/v1/tasks (liste + atanabilir personel),
/// PUT /api/v1/tasks/{id} (durum/düzenleme), DELETE /api/v1/tasks/{id}.
/// Yetki: görmek tasks.view, yazmak tasks.assign — 403'te eylem kilitlenir.
class GorevlerEkrani extends StatefulWidget {
  const GorevlerEkrani({super.key, this.suzgec = GorevSuzgec.acik});
  final GorevSuzgec suzgec;
  @override
  State<GorevlerEkrani> createState() => _GorevlerEkraniState();
}

class _GorevlerEkraniState extends State<GorevlerEkrani> {
  late GorevSuzgec _suzgec = widget.suzgec;
  int? _kisi; // null = herkes
  String _ara = '';
  ApiHata? _hata;
  final _mesgul = <int>{};

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await Uyg.api.get('/api/v1/tasks');
      if (r is Map) {
        Canli.gorevler.value = r.l('tasks');
        Canli.gorevPersonel.value = r.l('staff');
        if (Canli.gorevYetki.value != Yetki.yok) Canli.gorevYetki.value = Yetki.var_;
      }
      if (mounted) setState(() => _hata = null);
    } on ApiHata catch (e) {
      if (e.yetkiYok) Canli.gorevYetki.value = Yetki.yok;
      if (mounted) setState(() => _hata = e);
    }
  }

  Future<void> _durum(Map<String, dynamic> t, String yeni) async {
    final id = t.i('id');
    setState(() => _mesgul.add(id));
    HapticFeedback.selectionClick();
    try {
      final r = await Uyg.api.put('/api/v1/tasks/$id', {'status': yeni});
      final g = r is Map ? r.m('task') : <String, dynamic>{};
      Canli.gorevler.value = [for (final x in Canli.gorevler.value ?? const <Map<String, dynamic>>[]) x.i('id') == id && g.isNotEmpty ? g : x];
      bildir(yeni == 'done' ? 'Görev tamamlandı' : yeni == 'in_progress' ? 'Görev başladı' : 'Görev yeniden açıldı', mesaj: t.s('title'));
    } on ApiHata catch (e) {
      if (e.yetkiYok) Canli.gorevYetki.value = Yetki.yok;
      hataBildir(e, yetkiMesaji: 'Görevi değiştirme (görev atama) yetkiniz yok.');
    } finally {
      if (mounted) setState(() => _mesgul.remove(id));
    }
  }

  Future<void> _sil(Map<String, dynamic> t) async {
    final ok = await onayIste(context, baslik: 'Görev silinsin mi?', mesaj: '"${t.s('title')}" kalıcı olarak silinir.', evet: 'Sil', tehlikeli: true);
    if (!ok) return;
    try {
      await Uyg.api.sil('/api/v1/tasks/${t.i('id')}');
      Canli.gorevler.value = [for (final x in Canli.gorevler.value ?? const <Map<String, dynamic>>[]) if (x.i('id') != t.i('id')) x];
      bildir('Görev silindi', mesaj: t.s('title'));
    } on ApiHata catch (e) {
      if (e.yetkiYok) Canli.gorevYetki.value = Yetki.yok;
      hataBildir(e, yetkiMesaji: 'Görev silme yetkiniz yok.');
    }
  }

  Future<void> _yeni() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const GorevFormu()));
    if (ok == true) _yukle();
  }

  Future<void> _detay(Map<String, dynamic> t) async {
    final yazabilir = Canli.gorevYetki.value != Yetki.yok;
    final secim = await altSayfaAc<String>(context, (ctx) => _GorevDetay(t: t, yazabilir: yazabilir));
    if (!mounted || secim == null) return;
    switch (secim) {
      case 'duzenle':
        final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => GorevFormu(gorev: t)));
        if (ok == true) _yukle();
      case 'sil':
        await _sil(t);
      default:
        await _durum(t, secim);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>?>(
      valueListenable: Canli.gorevler,
      builder: (_, liste, _) => ValueListenableBuilder<Yetki>(
        valueListenable: Canli.gorevYetki,
        builder: (_, yetki, _) => _govde(liste, yetki),
      ),
    );
  }

  Widget _govde(List<Map<String, dynamic>>? liste, Yetki yetki) {
    final r = context.pa;
    final simdi = DateTime.now();
    final tum = liste ?? const <Map<String, dynamic>>[];
    final q = _ara.trim().toLowerCase();
    final suzulen = tum.where((t) {
      if (!_suzgec.uyar(t, simdi)) return false;
      if (_kisi != null && t.m('assigned_to').i('id') != _kisi) return false;
      if (q.isNotEmpty && !'${t.s('title')} ${t.s('description')} ${t.m('assigned_to').s('name')}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
    final yazabilir = yetki != Yetki.yok;
    final kisiler = <int, String>{for (final t in tum) if (t.m('assigned_to').i('id') > 0) t.m('assigned_to').i('id'): t.m('assigned_to').s('name')};
    final sayi = {for (final f in GorevSuzgec.values) f: tum.where((t) => f.uyar(t, simdi)).length};
    return Scaffold(
      floatingActionButton: yazabilir && liste != null ? EylemDugmesi(ikon: Icons.add_task_rounded, yazi: 'Görev oluştur', onTap: _yeni) : null,
      body: PaSayfa(
        baslik: 'Görevler',
        alt: liste == null ? 'Yükleniyor…' : '${sayi[GorevSuzgec.acik]} açık · ${sayi[GorevSuzgec.geciken]} geciken',
        geri: true,
        yenile: _yukle,
        altBosluk: 96,
        sag: const ZilDugmesi(),
        children: [
          if (liste == null && _hata != null)
            PaKart(child: _hata!.yetkiYok
                ? const BosDurum(baslik: 'Görevleri görme yetkiniz yok', mesaj: 'İşletme sahibi rolünüze "Görevleri görüntüle" yetkisini ekleyebilir.', ikon: Icons.lock_rounded)
                : HataDurum(hata: _hata!, yenile: _yukle))
          else if (liste == null)
            ...[for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: Iskelet(yukseklik: 78))]
          else ...[
            _OzetSerit(sayi: sayi, secili: _suzgec, sec: (f) => setState(() => _suzgec = f)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _ara = v),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Görev ya da kişi ara', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              _KisiSuzgec(kisiler: kisiler, secili: _kisi, sec: (k) => setState(() => _kisi = k)),
            ]),
            const SizedBox(height: 12),
            if (!yazabilir)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: BilgiNotu('Görevleri görebilirsiniz; atama ve değiştirme için "Görev ata" yetkisi gerekir.', ikon: Icons.lock_outline_rounded),
              ),
            if (suzulen.isEmpty)
              PaKart(
                child: Column(children: [
                  BosDurum(
                    baslik: tum.isEmpty ? 'Henüz görev yok' : '${_suzgec.ad} görev yok',
                    mesaj: tum.isEmpty
                        ? 'Ekibe iş atayın: başlık, kişi ve son tarih yeter. Atanan kişiye bildirim gider.'
                        : 'Başka bir süzgeç seçin ya da yeni görev oluşturun.',
                    ikon: Icons.task_alt_rounded,
                  ),
                  if (yazabilir)
                    YumusakDugme(onTap: _yeni, ikon: Icons.add_rounded, yazi: 'Görev oluştur'),
                  const SizedBox(height: 8),
                ]),
              )
            else
              for (var i = 0; i < suzulen.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Belirme(
                    sira: i,
                    child: GorevKarti(
                      t: suzulen[i],
                      mesgul: _mesgul.contains(suzulen[i].i('id')),
                      onTap: () => _detay(suzulen[i]),
                      onTamamla: yazabilir ? () => _durum(suzulen[i], suzulen[i].s('status') == 'done' ? 'open' : 'done') : null,
                    ),
                  ),
                ),
            Text('Liste görev tarihine göre sıralı. Aşağı çekerek yenileyin.', textAlign: TextAlign.center, style: TextStyle(color: r.silik, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _OzetSerit extends StatelessWidget {
  const _OzetSerit({required this.sayi, required this.secili, required this.sec});
  final Map<GorevSuzgec, int> sayi;
  final GorevSuzgec secili;
  final ValueChanged<GorevSuzgec> sec;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    Color renk(GorevSuzgec f) => switch (f) {
          GorevSuzgec.geciken => r.eksi,
          GorevSuzgec.devam => Marka.mavi,
          GorevSuzgec.biten => r.arti,
          GorevSuzgec.bugun => r.uyari,
          _ => r.birincil,
        };
    return SizedBox(
      height: 64,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final f in GorevSuzgec.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Semantics(
              selected: f == secili,
              child: Basilir(
                onTap: () => sec(f),
                etiket: '${f.ad}: ${sayi[f]}',
                child: AnimatedContainer(
                  duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
                  width: 92,
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  decoration: BoxDecoration(
                    color: f == secili ? renk(f).withValues(alpha: r.koyu ? .28 : .12) : r.kart,
                    borderRadius: Marka.yaricap,
                    border: Border.all(color: f == secili ? renk(f) : r.kenar, width: f == secili ? 1.5 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(f.ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: f == secili ? renk(f) : r.soluk, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    SayacMetin(deger: sayi[f] ?? 0, yaz: (n) => Bicim.sayi(n), stil: gosterim(19, renk: f == secili ? renk(f) : r.metin)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _KisiSuzgec extends StatelessWidget {
  const _KisiSuzgec({required this.kisiler, required this.secili, required this.sec});
  final Map<int, String> kisiler;
  final int? secili;
  final ValueChanged<int?> sec;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return PopupMenuButton<int>(
      tooltip: 'Kişiye göre süz',
      shape: RoundedRectangleBorder(borderRadius: Marka.yaricap),
      onSelected: (v) => sec(v < 0 ? null : v),
      itemBuilder: (_) => [
        const PopupMenuItem(value: -1, child: Text('Herkes')),
        for (final e in kisiler.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: secili == null ? r.ic : r.birincilYumusak, borderRadius: Marka.yaricap),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_search_rounded, size: 20, color: secili == null ? r.soluk : r.birincil),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 90),
            child: Text(secili == null ? 'Herkes' : (kisiler[secili] ?? 'Kişi').split(' ').first,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}

/// Görev kartı: solda öncelik şeridi, tamamla düğmesi, kişi + son tarih.
class GorevKarti extends StatelessWidget {
  const GorevKarti({super.key, required this.t, this.onTap, this.onTamamla, this.mesgul = false});
  final Map<String, dynamic> t;
  final VoidCallback? onTap;
  final VoidCallback? onTamamla;
  final bool mesgul;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final st = t.s('status');
    final bitti = st == 'done';
    final due = DateTime.tryParse(t.s('due_at'))?.toLocal();
    final simdi = DateTime.now();
    final gecti = due != null && !bitti && due.isBefore(simdi);
    final (oAd, oRenk) = oncelikBilgi(t.s('priority'), r);
    final kisi = t.m('assigned_to').s('name', t.b('herkese_acik') ? 'Herkes' : 'Atanmamış');
    final tamamla = SizedBox.square(
      dimension: 44,
      child: mesgul
          ? const Center(child: Yukleyici(boyut: 20))
          : IconButton(
              tooltip: bitti ? 'Yeniden aç' : 'Tamamlandı işaretle',
              onPressed: onTamamla,
              icon: AnimatedSwitcher(
                duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(
                  bitti ? Icons.check_circle_rounded : st == 'in_progress' ? Icons.timelapse_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(st),
                  size: 26,
                  color: bitti ? r.arti : st == 'in_progress' ? Marka.mavi : oRenk,
                ),
              ),
            ),
    );
    return Semantics(
      container: true,
      label: '${t.s('title')}, ${durumAdi(st)}, $kisi${due != null ? ', son tarih ${Bicim.tarihSaat(due)}' : ''}${gecti ? ', gecikti' : ''}',
      child: Basilir(
        onTap: onTap,
        olcek: .985,
        child: Container(
          decoration: BoxDecoration(color: r.kart, borderRadius: Marka.yaricap, border: Border.all(color: gecti ? r.eksi.withValues(alpha: .5) : r.kenar)),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 4, color: bitti ? r.arti : oRenk),
              Padding(padding: const EdgeInsets.only(left: 4, top: 6), child: Align(alignment: Alignment.topCenter, child: tamamla)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.s('title'),
                        style: TextStyle(
                          color: bitti ? r.silik : r.metin,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          decoration: bitti ? TextDecoration.lineThrough : null,
                        )),
                    if (t.s('description').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(t.s('description'), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: r.soluk, fontSize: 12.5)),
                      ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      _Etiket(ikon: Icons.person_rounded, yazi: kisi),
                      if (due != null)
                        _Etiket(
                          ikon: gecti ? Icons.alarm_rounded : Icons.event_rounded,
                          yazi: gecti ? 'Gecikti · ${_gunSaat(due, simdi)}' : _gunSaat(due, simdi),
                          renk: gecti ? r.eksi : null,
                        ),
                      if (t.s('priority') == 'high') _Etiket(ikon: Icons.priority_high_rounded, yazi: oAd, renk: oRenk),
                      if (st == 'in_progress') _Etiket(ikon: Icons.timelapse_rounded, yazi: 'Devam ediyor', renk: Marka.mavi),
                      if ((t['photos'] is List && (t['photos'] as List).isNotEmpty) || t.s('foto_url').isNotEmpty)
                        const _Etiket(ikon: Icons.photo_camera_rounded, yazi: 'Fotoğraf'),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

String _gunSaat(DateTime d, DateTime simdi) {
  final g = DateTime(d.year, d.month, d.day);
  final b = DateTime(simdi.year, simdi.month, simdi.day);
  final fark = g.difference(b).inDays;
  final gun = fark == 0 ? 'Bugün' : fark == 1 ? 'Yarın' : fark == -1 ? 'Dün' : Bicim.gunAyKisa(d);
  return '$gun ${Bicim.saat(d)}';
}

class _Etiket extends StatelessWidget {
  const _Etiket({required this.ikon, required this.yazi, this.renk});
  final IconData ikon;
  final String yazi;
  final Color? renk;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final c = renk ?? r.soluk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: renk == null ? r.ic : c.withValues(alpha: r.koyu ? .2 : .1), borderRadius: BorderRadius.circular(5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon, size: 13, color: c),
        const SizedBox(width: 4),
        Text(yazi, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _GorevDetay extends StatelessWidget {
  const _GorevDetay({required this.t, required this.yazabilir});
  final Map<String, dynamic> t;
  final bool yazabilir;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    final st = t.s('status');
    final due = DateTime.tryParse(t.s('due_at'))?.toLocal();
    final (oAd, oRenk) = oncelikBilgi(t.s('priority'), r);
    final olusturma = DateTime.tryParse(t.s('created_at'))?.toLocal();
    final bitis = DateTime.tryParse(t.s('completed_at'))?.toLocal();
    Widget bilgi(String ad, String deger, {Color? renk}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 104, child: Text(ad, style: TextStyle(color: r.silik, fontSize: 13))),
            Expanded(child: Text(deger, style: TextStyle(color: renk ?? r.metin, fontWeight: FontWeight.w600, fontSize: 13.5))),
          ]),
        );
    return AltSayfa(
      baslik: t.s('title'),
      alt: durumAdi(st),
      ikon: Icons.assignment_rounded,
      dugmeler: !yazabilir
          ? null
          : Row(children: [
              IconButton.outlined(
                tooltip: 'Sil',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), minimumSize: const Size(50, 50), foregroundColor: r.eksi),
                onPressed: () => Navigator.of(context).pop('sil'),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Düzenle',
                style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: Marka.yaricap), minimumSize: const Size(50, 50)),
                onPressed: () => Navigator.of(context).pop('duzenle'),
                icon: const Icon(Icons.edit_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: st == 'done'
                    ? KaydetDugmesi(yazi: 'Yeniden aç', ikon: Icons.replay_rounded, onPressed: () => Navigator.of(context).pop('open'))
                    : KaydetDugmesi(yazi: 'Tamamlandı', onPressed: () => Navigator.of(context).pop('done')),
              ),
            ]),
      children: [
        if (t.s('description').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(t.s('description'), style: TextStyle(color: r.metin, fontSize: 14, height: 1.45)),
          const SizedBox(height: 8),
        ],
        Divider(color: r.kenar),
        bilgi('Atanan', t.m('assigned_to').s('name', t.b('herkese_acik') ? 'Herkes (ilk alan)' : 'Atanmamış')),
        bilgi('Öncelik', oAd, renk: oRenk),
        bilgi('Son tarih', due == null ? 'Yok' : '${Bicim.gunAdi(due)}, ${Bicim.tarihSaat(due)}', renk: due != null && st != 'done' && due.isBefore(DateTime.now()) ? r.eksi : null),
        if (t.m('created_by').isNotEmpty) bilgi('Oluşturan', t.m('created_by').s('name')),
        if (olusturma != null) bilgi('Oluşturulma', Bicim.tarihSaat(olusturma)),
        if (bitis != null) bilgi('Tamamlanma', Bicim.tarihSaat(bitis), renk: r.arti),
        if (yazabilir && st == 'open') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('in_progress'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Başladı olarak işaretle'),
          ),
        ],
        const SizedBox(height: 6),
      ],
    );
  }
}

/* ───────────────────────── Görev formu ───────────────────────── */

/// Görev oluştur / düzenle. POST /api/v1/tasks (assigned_to_id, title,
/// description, priority, due_at) · PUT /api/v1/tasks/{id} (atanan kişi
/// sunucuda değiştirilemez). Saat UTC ISO gönderilir.
class GorevFormu extends StatefulWidget {
  const GorevFormu({super.key, this.gorev, this.kisi});
  final Map<String, dynamic>? gorev;

  /// Önceden seçili kişi (Ekip ekranından "görev ver").
  final int? kisi;
  @override
  State<GorevFormu> createState() => _GorevFormuState();
}

enum _Sure { yok, bugun, yarin, hafta, ozel }

class _GorevFormuState extends State<GorevFormu> {
  late final _baslik = TextEditingController(text: widget.gorev?.s('title') ?? '');
  late final _aciklama = TextEditingController(text: widget.gorev?.s('description') ?? '');
  late int? _kisi = widget.gorev?.m('assigned_to').i('id') ?? widget.kisi;
  late bool _herkes = widget.gorev?.b('herkese_acik') ?? false;
  late String _oncelik = widget.gorev?.s('priority', 'normal') ?? 'normal';
  late DateTime? _son = DateTime.tryParse(widget.gorev?.s('due_at') ?? '')?.toLocal();
  late _Sure _sure = widget.gorev == null ? _Sure.bugun : (_son == null ? _Sure.yok : _Sure.ozel);
  bool _mesgul = false;
  String? _hata;
  String _kisiAra = '';

  bool get _duzenle => widget.gorev != null;

  @override
  void initState() {
    super.initState();
    if (!_duzenle && _son == null) _son = _sureTarihi(_Sure.bugun);
    if (Canli.gorevPersonel.value.isEmpty) Canli.gorevleriTazele().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _baslik.dispose();
    _aciklama.dispose();
    super.dispose();
  }

  DateTime? _sureTarihi(_Sure s) {
    final n = DateTime.now();
    return switch (s) {
      _Sure.yok => null,
      // Bugün 18:00 (geçtiyse 2 saat sonra, tam saate yuvarlı)
      _Sure.bugun => n.hour < 17 ? DateTime(n.year, n.month, n.day, 18) : DateTime(n.year, n.month, n.day, n.hour + 2),
      _Sure.yarin => DateTime(n.year, n.month, n.day + 1, 10),
      _Sure.hafta => DateTime(n.year, n.month, n.day + (7 - n.weekday), 18),
      _Sure.ozel => _son,
    };
  }

  Future<void> _ozelSec() async {
    final ilk = _son ?? DateTime.now().add(const Duration(hours: 2));
    final g = await gunSec(context, ilk, ilkGun: DateTime.now().subtract(const Duration(days: 1)));
    if (g == null || !mounted) return;
    final s = await saatSec(context, TimeOfDay.fromDateTime(ilk), baslik: 'Son saat');
    if (!mounted) return;
    final t = s ?? TimeOfDay.fromDateTime(ilk);
    setState(() {
      _sure = _Sure.ozel;
      _son = DateTime(g.year, g.month, g.day, t.hour, t.minute);
    });
  }

  Future<void> _kaydet() async {
    final baslik = _baslik.text.trim();
    if (baslik.isEmpty) {
      setState(() => _hata = 'Görev başlığı yazın.');
      return;
    }
    if (!_duzenle && _kisi == null && !_herkes) {
      setState(() => _hata = 'Görevi kime vereceğinizi seçin.');
      return;
    }
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final govde = <String, dynamic>{
      'title': baslik,
      'description': _aciklama.text.trim().isEmpty ? null : _aciklama.text.trim(),
      'priority': _oncelik,
      'due_at': _son == null ? null : utcIso(_son!),
    };
    try {
      if (_duzenle) {
        await Uyg.api.put('/api/v1/tasks/${widget.gorev!.i('id')}', govde);
      } else {
        govde['assigned_to_id'] = _herkes ? null : _kisi;
        await Uyg.api.post('/api/v1/tasks', govde);
      }
      HapticFeedback.mediumImpact();
      bildir(_duzenle ? 'Görev güncellendi' : 'Görev atandı', mesaj: _duzenle ? baslik : '$baslik · ${_kisiAdi ?? 'Herkes'} bildirim alacak');
      await Canli.gorevleriTazele();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiHata catch (e) {
      if (e.yetkiYok) Canli.gorevYetki.value = Yetki.yok;
      setState(() {
        _mesgul = false;
        _hata = e.yetkiYok
            ? 'Görev atama yetkiniz yok. İşletme sahibi rolünüze "Görev ata" yetkisini ekleyebilir.'
            : e.kod == 422 && _herkes
                ? 'Bu işletmede "herkese açık" görev desteklenmiyor; bir kişi seçin.'
                : e.mesaj;
      });
    }
  }

  String? get _kisiAdi {
    for (final p in Canli.gorevPersonel.value) {
      if (p.i('id') == _kisi) return p.s('name');
    }
    return widget.gorev?.m('assigned_to').s('name');
  }

  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Scaffold(
      body: PaSayfa(
        baslik: _duzenle ? 'Görevi düzenle' : 'Yeni görev',
        alt: _duzenle ? 'Atanan: ${_kisiAdi ?? 'Herkes'}' : 'Ekibe iş atayın; atanan kişiye bildirim gider',
        geri: true,
        altBosluk: 110,
        children: [
          TextField(
            controller: _baslik,
            autofocus: !_duzenle,
            maxLength: 160,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            decoration: const InputDecoration(labelText: 'Ne yapılacak?', hintText: 'Örn. Depo sayımını yap', prefixIcon: Icon(Icons.assignment_rounded)),
          ),
          TextField(
            controller: _aciklama,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Açıklama (isteğe bağlı)', hintText: 'Ayrıntı, not, kontrol listesi…', alignLabelWithHint: true),
          ),
          if (!_duzenle) ...[
            AlanBasligi('KİME', sag: Text(_herkes ? 'Herkes' : _kisiAdi ?? 'Seçilmedi', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700, fontSize: 12.5))),
            ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: Canli.gorevPersonel,
              builder: (_, kisiler, _) => _kisiSecimi(kisiler),
            ),
          ],
          const AlanBasligi('ÖNCELİK'),
          Row(children: [
            for (final (k, ad, ikon) in const [('low', 'Düşük', Icons.south_rounded), ('normal', 'Normal', Icons.remove_rounded), ('high', 'Yüksek', Icons.priority_high_rounded)]) ...[
              if (k != 'low') const SizedBox(width: 8),
              Expanded(
                child: SecimCipi(
                  yazi: ad,
                  ikon: ikon,
                  secili: _oncelik == k,
                  renk: k == 'high' ? r.eksi : null,
                  onTap: () => setState(() => _oncelik = k),
                ),
              ),
            ],
          ]),
          AlanBasligi('SON TARİH', sag: Text(_son == null ? 'Yok' : '${Bicim.gunAdi(_son!)} ${Bicim.tarihSaat(_son!)}', style: TextStyle(color: r.birincil, fontWeight: FontWeight.w700, fontSize: 12.5))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (s, ad) in const [(_Sure.bugun, 'Bugün'), (_Sure.yarin, 'Yarın 10:00'), (_Sure.hafta, 'Hafta sonu'), (_Sure.yok, 'Süresiz')])
              SecimCipi(
                yazi: ad,
                secili: _sure == s,
                alt: s == _Sure.bugun ? saatYaz(TimeOfDay.fromDateTime(_sureTarihi(_Sure.bugun)!)) : null,
                onTap: () => setState(() {
                  _sure = s;
                  _son = _sureTarihi(s);
                }),
              ),
            SecimCipi(yazi: _sure == _Sure.ozel && _son != null ? Bicim.tarihSaat(_son!) : 'Tarih seç', ikon: Icons.edit_calendar_rounded, secili: _sure == _Sure.ozel, onTap: _ozelSec),
          ]),
          const SizedBox(height: 18),
          const BilgiNotu('Görev kaydedilince atanan personelin telefonuna bildirim gider; personel uygulamasında "Görevler"de görünür.'),
          if (_hata != null) ...[
            const SizedBox(height: 12),
            BilgiNotu(_hata!, ikon: Icons.error_outline_rounded, renk: r.eksi),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.viewInsetsOf(context).bottom),
          child: KaydetDugmesi(yazi: _duzenle ? 'Değişiklikleri kaydet' : 'Görevi ata', ikon: Icons.send_rounded, mesgul: _mesgul, onPressed: _kaydet),
        ),
      ),
    );
  }

  Widget _kisiSecimi(List<Map<String, dynamic>> kisiler) {
    final r = context.pa;
    if (kisiler.isEmpty) {
      return Row(children: [
        Expanded(child: Text('Personel listesi yükleniyor…', style: TextStyle(color: r.silik))),
        TextButton(onPressed: () => Canli.gorevleriTazele(), child: const Text('Yenile')),
      ]);
    }
    final q = _kisiAra.trim().toLowerCase();
    final liste = kisiler.where((p) => q.isEmpty || p.s('name').toLowerCase().contains(q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (kisiler.length > 8)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            onChanged: (v) => setState(() => _kisiAra = v),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Personel ara', isDense: true),
          ),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SecimCipi(
          yazi: 'Herkes',
          alt: 'İlk alan yapar',
          ikon: Icons.groups_rounded,
          secili: _herkes,
          onTap: () => setState(() {
            _herkes = true;
            _kisi = null;
          }),
        ),
        for (final p in liste)
          _KisiCipi(
            ad: p.s('name', '—'),
            alt: p.s('position'),
            secili: !_herkes && _kisi == p.i('id'),
            onTap: () => setState(() {
              _herkes = false;
              _kisi = p.i('id');
            }),
          ),
      ]),
    ]);
  }
}

class _KisiCipi extends StatelessWidget {
  const _KisiCipi({required this.ad, required this.secili, required this.onTap, this.alt = ''});
  final String ad;
  final String alt;
  final bool secili;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final r = context.pa;
    return Semantics(
      selected: secili,
      child: Basilir(
        onTap: onTap,
        etiket: alt.isEmpty ? ad : '$ad, $alt',
        olcek: .95,
        child: AnimatedContainer(
          duration: Hareket.kapali(context) ? Duration.zero : Hareket.kisa,
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: secili ? r.birincilYumusak : r.kart,
            borderRadius: Marka.yaricap,
            border: Border.all(color: secili ? r.birincil : r.kenar, width: secili ? 1.5 : 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Avatar(ad, boyut: 30),
            const SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ad, style: TextStyle(color: r.metin, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2)),
              if (alt.isNotEmpty) Text(alt, style: TextStyle(color: r.silik, fontSize: 11, height: 1.2)),
            ]),
            if (secili) ...[const SizedBox(width: 6), Icon(Icons.check_rounded, size: 16, color: r.birincil)],
          ]),
        ),
      ),
    );
  }
}
