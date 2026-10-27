import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'ortak.dart';

/// Adisyon ekranının pencereleri (web Detail.vue §4). Belge:
/// /root/work/spec/adisyon-detay.md.

/* ───────── Kişi sayısı / adisyon notu (§4.5) ───────── */

Future<({int? kisi, String? not})?> bilgiPenceresi(BuildContext context, Adisyon a) {
  final kisi = TextEditingController(text: a.kisi?.toString() ?? '');
  final not = TextEditingController(text: a.not ?? '');
  return pencereAc(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) => AlertDialog(
        title: const Text('Kişi sayısı / adisyon notu'),
        content: SizedBox(
          width: 384,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              FormAlani(
                etiket: 'Kişi sayısı',
                ipucu: 'Boş bırakılabilir; hesap bölerken kişi başı tutarda kullanılır',
                child: TextField(controller: kisi, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'ör. 4'), onChanged: (_) => yenile(() {})),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final n in const [1, 2, 3, 4, 5, 6, 8, 10])
                  ChoiceChip(
                    label: Text('$n'),
                    selected: kisi.text == '$n',
                    selectedColor: Renk.marka,
                    labelStyle: TextStyle(color: kisi.text == '$n' ? Colors.white : Renk.yazi, fontWeight: FontWeight.w600),
                    onSelected: (_) => yenile(() => kisi.text = '$n'),
                  ),
              ]),
              const SizedBox(height: 14),
              FormAlani(
                etiket: 'Adisyon notu',
                ipucu: 'Adisyonun tamamı için (ör. “doğum günü, pasta sonda gelsin”)',
                child: TextField(controller: not, maxLength: 500, decoration: const InputDecoration(hintText: 'İsteğe bağlı')),
              ),
            ]),
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final m = kisi.text.trim();
              int? n;
              if (m.isNotEmpty) {
                n = int.tryParse(m);
                if (n == null || n < 1 || n > 200) {
                  context.bildir2('Kişi sayısı geçersiz', '1–200 arası bir sayı girin ya da boş bırakın.', hata: true);
                  return;
                }
              }
              Navigator.pop(ctx, (kisi: n, not: not.text.trim().isEmpty ? null : not.text.trim()));
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}

/* ───────── Taşı (§4.4) ───────── */

class TasimaSonucu {
  TasimaSonucu({this.masaId, this.cariId, this.adet, this.masaAdi, this.cariAdi});
  final int? masaId;
  final int? cariId;
  final int? adet;
  final String? masaAdi;
  final String? cariAdi;
}

/// [kalem]: tek kalem taşıma; [topluOzet]: seçili kalemler listesi; ikisi de
/// yoksa adisyonun tamamı. [partiOzet] parti açıkken "Evet, taşı" onayı
/// için (başlık, satırlar, toplam) — null ise onay sorulmaz.
Future<TasimaSonucu?> tasimaPenceresi(
  BuildContext context, {
  required Adisyon adisyon,
  Kalem? kalem,
  List<({Kalem k, int adet})>? toplu,
  bool partiOnayi = false,
}) {
  return pencereAc<TasimaSonucu>(
    context: context,
    builder: (_) => _Tasima(adisyon: adisyon, kalem: kalem, toplu: toplu, partiOnayi: partiOnayi),
  );
}

class _Tasima extends StatefulWidget {
  const _Tasima({required this.adisyon, this.kalem, this.toplu, required this.partiOnayi});
  final Adisyon adisyon;
  final Kalem? kalem;
  final List<({Kalem k, int adet})>? toplu;
  final bool partiOnayi;

  @override
  State<_Tasima> createState() => _TasimaState();
}

class _TasimaState extends State<_Tasima> {
  List<Json> _masalar = const [];
  List<Json> _cariler = const [];
  bool _yukleniyor = true;
  int? _masa;
  int? _cari;
  late int _adet = widget.kalem?.adet ?? 0;
  bool _onayGoster = false;

  Adisyon get a => widget.adisyon;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    final api = context.api;
    final oturum = context.durum.oturum!;
    try {
      final b = (await api.get('/api/v1/orders/board') as Map);
      _masalar = (b['tables'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .where((t) => tamSayi(t['id']) != (a.ham['table_id'] == null ? -1 : tamSayi(a.ham['table_id'])))
          .toList();
    } on ApiHata {
      // Masa listesi alınamazsa yalnız şahıs seçilebilir.
    }
    if (oturum.yetki('receivables.view')) {
      try {
        final r = (await api.get('/api/v1/receivables', sorgu: {'per_page': 200}) as Map);
        final d = r['receivables'] is Map ? (r['receivables'] as Map)['data'] : r['receivables'];
        _cariler = (d as List? ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .where((c) => tamSayi(c['id']) != (a.ham['receivable_id'] == null ? -1 : tamSayi(a.ham['receivable_id'])))
            .toList();
      } on ApiHata {
        // Şahıs listesi yoksa bölüm gizli.
      }
    }
    if (mounted) setState(() => _yukleniyor = false);
  }

  String _hedefAdi() {
    if (_masa != null) {
      return _masalar.firstWhere((t) => tamSayi(t['id']) == _masa, orElse: () => const {})['name']?.toString() ?? 'seçilen masa';
    }
    final c = _cariler.firstWhere((t) => tamSayi(t['id']) == _cari, orElse: () => const {});
    return c.isEmpty ? 'seçilen kişi' : '${c['name']} (şahıs)';
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kalem;
    final toplu = widget.toplu;
    final baslik = toplu != null ? 'Seçili kalemleri taşı' : (k != null ? 'Kalemi taşı' : 'Adisyonu taşı');

    final topluAdet = toplu?.fold<int>(0, (t, x) => t + x.adet) ?? 0;
    final topluTutar = toplu?.fold<int>(0, (t, x) => t + (x.k.adet == 0 ? 0 : (x.k.tutar * x.adet / x.k.adet).round())) ?? 0;
    final kismiVar = toplu?.any((x) => x.adet < x.k.adet) ?? false;

    final Widget icerik;
    if (_onayGoster) {
      // Parti onay özeti (§4.4 adım 2)
      final kalemler = toplu?.map((x) => x.k).toList() ?? a.aktifKalemler;
      final partiler = <int, List<Kalem>>{};
      for (final x in kalemler) {
        (partiler[tamSayi(x.ham['parti_no'], tamSayi(a.ham['aktif_parti'], 1))] ??= []).add(x);
      }
      final adlar = a.ham['parti_adlari'] is Map ? a.ham['parti_adlari'] as Map : const {};
      final hepsi = a.aktifKalemler;
      icerik = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(
            '${toplu == null ? 'Adisyonun TAMAMI (tüm partiler)' : (partiler.length > 1 ? 'Bu partiler' : 'Bu parti')} → ${_hedefAdi()} taşınıyor. Onaylıyor musunuz?',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final e in partiler.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${e.key}. parti${adlar['${e.key}'] != null ? ' · ${adlar['${e.key}']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${e.value.length} kalem · ${e.value.length == hepsi.where((x) => tamSayi(x.ham['parti_no'], tamSayi(a.ham['aktif_parti'], 1)) == e.key).length ? 'partinin tamamı' : 'partinin bir kısmı'}',
                      style: TextStyle(fontSize: 12, color: Renk.ikinci),
                    ),
                  ]),
                ),
                Text(para(e.value.fold(0, (t, x) => t + x.tutar)), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          const Divider(),
          Row(children: [
            const Expanded(child: Text('Taşınacak toplam', style: TextStyle(fontWeight: FontWeight.w600))),
            Text(para(kalemler.fold(0, (t, x) => t + x.tutar)), style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ]),
      );
    } else {
      icerik = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (toplu != null) ...[
          Text(
            '$topluAdet adet${toplu.length > 1 ? ' · ${toplu.length} üründen' : ''} · ${para(topluTutar)} taşınacak',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          for (final x in toplu)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Expanded(child: Text('${x.adet}× ${x.k.ad}${x.adet < x.k.adet ? ' (${x.k.adet} adetten)' : ''}', style: const TextStyle(fontSize: 13))),
                if (x.adet < x.k.adet) Text('${x.k.adet - x.adet} adet burada kalır', style: TextStyle(fontSize: 12, color: Renk.soluk)),
              ]),
            ),
          if (kismiVar)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Kısmi taşıma: seçmediğiniz partiler bu adisyonda kalır.', style: TextStyle(fontSize: 12, color: Renk.uyari)),
            ),
          const SizedBox(height: 12),
        ] else if (k != null) ...[
          Text('${k.adet} × ${k.ad}', style: const TextStyle(fontWeight: FontWeight.w600)),
          if (k.adet > 1) ...[
            const SizedBox(height: 10),
            FormAlani(
              etiket: 'Kaç adet taşınsın?',
              ipucu: 'Kalanı bu adisyonda kalır; toplamlar iki adisyona bölünür.',
              child: Row(children: [
                IconButton.outlined(onPressed: _adet > 1 ? () => setState(() => _adet--) : null, icon: const Icon(Icons.remove_rounded)),
                SizedBox(width: 48, child: Text('$_adet', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                IconButton.outlined(onPressed: _adet < k.adet ? () => setState(() => _adet++) : null, icon: const Icon(Icons.add_rounded)),
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => _adet = k.adet), child: Text('Tamamı (${k.adet})')),
              ]),
            ),
            if (_adet < k.adet)
              Text.rich(TextSpan(children: [
                TextSpan(text: '$_adet adet', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' taşınacak, '),
                TextSpan(text: '${k.adet - _adet} adet', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' bu adisyonda kalacak.'),
              ]), style: const TextStyle(fontSize: 13)),
          ],
          const SizedBox(height: 12),
        ],
        if (_yukleniyor)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else ...[
          FormAlani(
            etiket: 'Hedef masa',
            ipucu: k != null || toplu != null ? 'Hedef masada açık adisyon varsa kalemler ona eklenir.' : 'Masaya taşımak için seçin.',
            child: IgnorePointer(
              ignoring: _cari != null,
              child: Opacity(
                opacity: _cari != null ? .5 : 1,
                child: Secici<int>(
                  deger: _masa,
                  yerTutucu: 'Masa seçin',
                  secenekler: [
                    for (final t in _masalar)
                      (
                        tamSayi(t['id']),
                        '${t['name']}${(t['orders'] as List? ?? const []).isNotEmpty ? ' (açık adisyon: ${(t['orders'] as List).length})' : ''} — ${t['status_label'] ?? ''}'
                      ),
                  ],
                  degisti: (v) => setState(() => _masa = v),
                ),
              ),
            ),
          ),
          if (_cariler.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: Text('YA DA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.soluk))),
            ),
            FormAlani(
              etiket: 'Şahsa taşı',
              ipucu: k != null || toplu != null
                  ? 'Ürün kişinin adisyonuna geçer; kişide açık adisyon yoksa açılır.'
                  : 'Hesap seçtiğiniz kişinin üzerine geçer, masa boşalır.',
              child: IgnorePointer(
                ignoring: _masa != null,
                child: Opacity(
                  opacity: _masa != null ? .5 : 1,
                  child: Secici<int>(
                    deger: _cari,
                    yerTutucu: 'Kişi seçin',
                    secenekler: [for (final c in _cariler) (tamSayi(c['id']), '${c['name']}')],
                    degisti: (v) => setState(() => _cari = v),
                  ),
                ),
              ),
            ),
          ],
        ],
      ]);
    }

    final hedefVar = _masa != null || _cari != null;
    return AlertDialog(
      title: Text(baslik),
      content: SizedBox(width: 384, child: SingleChildScrollView(child: icerik)),
      actions: _onayGoster
          ? [
              OutlinedButton(onPressed: () => setState(() => _onayGoster = false), child: const Text('Hayır, geri dön')),
              FilledButton(onPressed: _bitir, child: const Text('Evet, taşı')),
            ]
          : [
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
              FilledButton(
                onPressed: !hedefVar
                    ? null
                    : () {
                        if (widget.partiOnayi && widget.kalem == null) {
                          setState(() => _onayGoster = true);
                        } else {
                          _bitir();
                        }
                      },
                child: const Text('Taşı'),
              ),
            ],
    );
  }

  void _bitir() {
    Navigator.pop(
      context,
      TasimaSonucu(
        masaId: _masa,
        cariId: _cari,
        adet: widget.kalem != null && _adet < widget.kalem!.adet ? _adet : null,
        masaAdi: _masa == null ? null : _hedefAdi(),
        cariAdi: _cari == null ? null : _hedefAdi(),
      ),
    );
  }
}

/* ───────── İndirim (§4.6) ───────── */

Future<bool> indirimPenceresi(BuildContext context, Adisyon a) async {
  final r = await pencereAc<bool>(context: context, builder: (_) => _Indirim(adisyon: a));
  return r ?? false;
}

class _Indirim extends StatefulWidget {
  const _Indirim({required this.adisyon});
  final Adisyon adisyon;

  @override
  State<_Indirim> createState() => _IndirimState();
}

class _IndirimState extends State<_Indirim> {
  static List<Json>? _onbellek;
  List<Json>? _tanimlar = _onbellek;
  bool _serbest = false;
  String _tur = 'percent';
  final _deger = TextEditingController();
  final _gerekce = TextEditingController();
  bool _mesgul = false;

  Adisyon get a => widget.adisyon;

  @override
  void initState() {
    super.initState();
    if (_onbellek == null) _yukle();
  }

  @override
  void dispose() {
    _deger.dispose();
    _gerekce.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final r = (await context.api.get('/api/v1/discount-presets') as Map);
      _onbellek = (r['presets'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } on ApiHata {
      _onbellek = const [];
    }
    if (mounted) setState(() => _tanimlar = _onbellek);
  }

  Future<void> _gonder(Map<String, dynamic> govde, String baslik, String metin) async {
    setState(() => _mesgul = true);
    try {
      await context.api.post('/api/v1/orders/${a.id}/discount', {...govde, 'expected_version': a.surum});
      if (!mounted) return;
      context.bildir2(baslik, metin);
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('İndirim uygulanamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _kaldir() async {
    setState(() => _mesgul = true);
    try {
      await context.api.delete('/api/v1/orders/${a.id}/discount', {'expected_version': a.surum});
      if (!mounted) return;
      context.bildir2('İndirim kaldırıldı', 'Tutar yeniden hesaplandı.');
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Kaldırılamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final varMi = tamSayi(a.ham['discount_minor']) > 0;
    final yuzde = a.ham['discount_percent'];
    Widget govde;
    if (varMi) {
      govde = Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
        child: Row(children: [
          Icon(Icons.sell_outlined, size: 20, color: Renk.uyari),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a.ham['discount_reason'] ?? 'İndirim'}${yuzde != null ? ' (%$yuzde)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text('Bu adisyonda zaten bir indirim var. Başka indirim uygulamak için önce bunu kaldırın.', style: TextStyle(fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Renk.hata, minimumSize: const Size(0, 36)),
            onPressed: _mesgul ? null : _kaldir,
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Kaldır'),
          ),
        ]),
      );
    } else {
      final l = _tanimlar;
      govde = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('Hazır indirimler', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (l == null)
          Text('Tanımlar yükleniyor…', style: TextStyle(color: Renk.soluk))
        else if (l.isEmpty)
          Text(
              'Tanımlı hazır indirim yok. Sol menüdeki İndirim Tanımları ekranından ekleyebilirsiniz (ör. “Şehit/Gazi yakını”, “Kamu personeli”).',
              style: TextStyle(fontSize: 13, color: Renk.ikinci))
        else
          LayoutBuilder(builder: (ctx, k) {
            final iki = k.maxWidth >= 400;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in l)
                SizedBox(
                  width: iki ? (k.maxWidth - 8) / 2 : k.maxWidth,
                  child: Material(
                    color: Renk.yuzey,
                    borderRadius: koseYuvarlak,
                    child: InkWell(
                      borderRadius: koseYuvarlak,
                      onTap: _mesgul ? null : () => _gonder({'preset_id': tamSayi(t['id'])}, 'İndirim uygulandı', '${t['name']} · ${t['value_label']}'),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (t['note'] != null) Text('${t['note']}', style: TextStyle(fontSize: 12, color: Renk.soluk)),
                            ]),
                          ),
                          Rozet('${t['value_label']}', renk: Renk.marka, zemin: Renk.markaAcik),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]);
          }),
        const Divider(height: 24),
        if (!_serbest)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: () => setState(() => _serbest = true), child: const Text('+ Tanımsız (serbest) indirim gir')),
          )
        else ...[
          FormAlani(
            etiket: 'Tür',
            child: Secici<String>(
              deger: _tur,
              secenekler: const [('percent', 'Yüzde (%)'), ('amount', 'Sabit tutar (₺)')],
              degisti: (v) => setState(() => _tur = v ?? 'percent'),
            ),
          ),
          const SizedBox(height: 10),
          FormAlani(
            etiket: _tur == 'percent' ? 'Yüzde' : 'Tutar (₺)',
            child: TextField(
              controller: _deger,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(hintText: _tur == 'percent' ? 'ör. 10' : 'ör. 25,00'),
            ),
          ),
          const SizedBox(height: 10),
          FormAlani(
            etiket: 'Gerekçe',
            child: TextField(controller: _gerekce, decoration: const InputDecoration(hintText: 'ör. yönetici onaylı özel indirim')),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => setState(() => _serbest = false), child: const Text('Vazgeç')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _mesgul
                  ? null
                  : () {
                      final n = double.tryParse(_deger.text.replaceAll(' ', '').replaceAll(',', '.'));
                      if (n == null || n <= 0) {
                        context.bildir2('Değer geçersiz', 'Sıfırdan büyük bir değer girin.', hata: true);
                        return;
                      }
                      if (_gerekce.text.trim().length < 3) {
                        context.bildir2('Gerekçe gerekli', 'En az 3 karakterlik bir gerekçe yazın.', hata: true);
                        return;
                      }
                      _gonder({
                        'type': _tur,
                        'value': _tur == 'percent' ? n : (n * 100).round(),
                        'reason': _gerekce.text.trim(),
                      }, 'İndirim uygulandı', _gerekce.text.trim());
                    },
              child: const Text('Uygula'),
            ),
          ]),
        ],
      ]);
    }
    return AlertDialog(
      title: const Text('İndirim'),
      content: SizedBox(width: 512, child: SingleChildScrollView(child: govde)),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}

/* ───────── Birleştir (§4.7) ───────── */

Future<int?> birlestirPenceresi(BuildContext context, Adisyon a) {
  return pencereAc<int>(context: context, builder: (_) => _Birlestir(adisyon: a));
}

class _Birlestir extends StatefulWidget {
  const _Birlestir({required this.adisyon});
  final Adisyon adisyon;

  @override
  State<_Birlestir> createState() => _BirlestirState();
}

class _BirlestirState extends State<_Birlestir> {
  List<Json>? _liste;
  int? _secili;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final r = (await context.api.get('/api/v1/orders', sorgu: {'open': 1, 'per_page': 200}) as Map);
        final d = r['orders'] is Map ? (r['orders'] as Map)['data'] : r['orders'];
        _liste = (d as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).where((o) => tamSayi(o['id']) != widget.adisyon.id).toList();
      } on ApiHata {
        _liste = const [];
      }
      if (mounted) setState(() {});
    }();
  }

  @override
  Widget build(BuildContext context) {
    final l = _liste;
    return AlertDialog(
      title: const Text('Adisyon birleştir'),
      content: SizedBox(
        width: 384,
        child: l == null
            ? const SizedBox(height: 60, child: Center(child: CircularProgressIndicator()))
            : FormAlani(
                etiket: 'Kaynak adisyon',
                zorunlu: true,
                ipucu: 'Seçilen adisyonun kalemleri bu adisyona aktarılır ve kaynak kapanır.',
                child: Secici<int>(
                  deger: _secili,
                  yerTutucu: 'Adisyon seçin',
                  secenekler: [
                    for (final o in l)
                      (
                        tamSayi(o['id']),
                        '#${o['id']} — ${o['table_name'] ?? o['receivable_name'] ?? o['channel_label'] ?? ''} · ${o['items_count'] ?? 0} kalem · ${o['total_display'] ?? ''} ₺'
                      ),
                  ],
                  degisti: (v) => setState(() => _secili = v),
                ),
              ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _secili == null ? null : () => Navigator.pop(context, _secili), child: const Text('Birleştir')),
      ],
    );
  }
}

/* ───────── Parti kapatma (§4.8) / parti adı (§4.9) / adisyon boşaldı (§4.3) ───────── */

Future<bool> partiKapatSor(BuildContext context, Adisyon a) async {
  final n = tamSayi(a.ham['aktif_parti'], 1);
  final ad = a.ham['parti_adlari'] is Map ? (a.ham['parti_adlari'] as Map)['$n'] : null;
  final kalemler = a.aktifKalemler.where((k) => (k.ham['parti_no'] == null ? n : tamSayi(k.ham['parti_no'])) == n).toList();
  final r = await pencereAc<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$n. parti sonlandırılsın mı?'),
      content: SizedBox(
        width: 384,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Oyunun $n. partisi${ad != null ? ' ($ad)' : ''} sonlandı mı?', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' Onaylarsanız ${n + 1}. parti başlar ve bundan sonra eklenen ürünler yeni ele yazılır.'),
          ])),
          if (kalemler.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Bu parti', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('${kalemler.length} kalem', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                  ]),
                ),
                Text(para(kalemler.fold(0, (t, k) => t + k.tutar)), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Adisyon KAPANMAZ, masa boşalmaz; hesap kasada tek seferde ya da parti parti alınabilir. Yanlışlıkla açılan parti geri alınamaz.',
            style: TextStyle(fontSize: 12, color: Renk.ikinci),
          ),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır, devam etsin')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, yeni ele geç')),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> partiAdiSor(BuildContext context, int no, String? mevcut) {
  final c = TextEditingController(text: mevcut ?? '');
  return pencereAc<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('$no. partiye isim'),
      content: SizedBox(
        width: 384,
        child: FormAlani(
          etiket: 'Parti adı',
          ipucu: 'Boş bırakılırsa ad kaldırılır. Yalnız ekranda görünür; fişe ve hesaba girmez.',
          child: TextField(
            controller: c,
            maxLength: 40,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'ör. Ahmet Bey masası'),
            onSubmitted: (_) => Navigator.pop(ctx, c.text.trim()),
          ),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Kaydet')),
      ],
    ),
  );
}

Future<bool> adisyonBosaldiSor(BuildContext context) async {
  final r = await pencereAc<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Adisyonda ürün kalmadı'),
      content: SizedBox(
        width: 384,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bu adisyondaki tüm ürünler iptal edildi. Adisyon kapatılsın mı?'),
          SizedBox(height: 8),
          Text(
            '“Evet” derseniz iptal sebebi sorulur ve masa boşa döner. “Hayır” derseniz adisyon açık kalır, yeni ürün ekleyebilirsiniz.',
            style: TextStyle(fontSize: 12, color: Renk.ikinci),
          ),
        ]),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hayır, açık kalsın')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Renk.hata), onPressed: () => Navigator.pop(ctx, true), child: const Text('Evet, kapat')),
      ],
    ),
  );
  return r ?? false;
}
