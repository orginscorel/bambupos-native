import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'kasa_pencereleri.dart' show paraCoz;
import 'ekran_klavyesi.dart';
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

/* ───────── İndirim / iskonto (§4.6) ───────── */

/// İndirim penceresi — HAZIR İNDİRİMLER varsayılandır (işletme kararı
/// 2026-10-27). "Tutar yaz", "%" ve "Hesabı şu tutara indir" yalnız
/// `manuel_iskonto` eklentisi açık işletmede görünür (sunucu da kapalıysa
/// 403 ile reddeder; mesajı aynen gösterilir).
///
/// Değişiklik olduysa true döner (çağıran adisyonu yeniden yükler).
Future<bool> indirimPenceresi(BuildContext context, Adisyon a, {bool? manuel}) async {
  final m = manuel ?? (context.durum.oturum?.manuelIskonto ?? false);
  final r = await pencereAc<bool>(context: context, builder: (_) => _Indirim(adisyon: a, manuel: m));
  return r ?? false;
}

class _Indirim extends StatefulWidget {
  const _Indirim({required this.adisyon, required this.manuel});
  final Adisyon adisyon;
  final bool manuel;

  @override
  State<_Indirim> createState() => _IndirimState();
}

class _IndirimState extends State<_Indirim> {
  static List<Json>? _onbellek;
  List<Json>? _tanimlar = _onbellek;
  bool _manuelSekme = false;
  String _kip = 'tutar'; // tutar | yuzde | hedef
  final _deger = TextEditingController();
  final _gerekce = TextEditingController();
  bool _mesgul = false;

  Adisyon get a => widget.adisyon;
  int get _indirim => tamSayi(a.ham['discount_minor']);
  int get _iskonto => tamSayi(a.ham['iskonto_minor']);
  String get _yol => '/api/v1/orders/${a.id}';

  @override
  void initState() {
    super.initState();
    // Önbellek varsa hemen gösterilir, arkada tazelenir (tanım eklenmiş olabilir).
    _yukle();
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
      _onbellek ??= const [];
    } catch (_) {
      _onbellek ??= const [];
    }
    if (mounted) setState(() => _tanimlar = _onbellek);
  }

  Future<void> _istek(Future<dynamic> Function() f, String baslik, String metin, {String hata = 'İndirim uygulanamadı'}) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await f();
      if (!mounted) return;
      context.bildir2(baslik, metin);
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      // 403: eklenti kapalı / yetki yok — sunucunun mesajı aynen.
      if (mounted) context.bildir2(e.yetkiYok ? 'İzin verilmedi' : hata, e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  void _hazir(Json t) => _istek(() => context.api.post('$_yol/discount', {'preset_id': tamSayi(t['id']), 'expected_version': a.surum}),
      'İndirim uygulandı', '${t['name']} · ${t['value_label']}');

  void _indirimKaldir() => _istek(() => context.api.delete('$_yol/discount', {'expected_version': a.surum}), 'İndirim kaldırıldı', 'Tutar yeniden hesaplandı.',
      hata: 'Kaldırılamadı');

  void _iskontoKaldir() => _istek(() => context.api.delete('$_yol/iskonto'), 'İskonto kaldırıldı', 'Adisyon eski tutarına döndü.', hata: 'Kaldırılamadı');

  /// Manuel kipte girilen değerin sonucu: (düşülecek kuruş, hata metni).
  ({int dus, String? hata}) get _hesap {
    final toplam = a.toplam;
    final metin = _deger.text.trim();
    if (metin.isEmpty) return (dus: 0, hata: null);
    switch (_kip) {
      case 'yuzde':
        final n = double.tryParse(metin.replaceAll(' ', '').replaceAll('%', '').replaceAll(',', '.'));
        if (n == null || n <= 0 || n >= 100) return (dus: 0, hata: 'Yüzde 0 ile 100 arasında olmalı.');
        return (dus: (a.araToplam * n / 100).round(), hata: null);
      case 'hedef':
        final h = paraCoz(metin);
        if (h == null) return (dus: 0, hata: 'Tutar geçersiz.');
        if (h >= toplam) return (dus: 0, hata: 'Hedef tutar, adisyon toplamından (${para(toplam)}) küçük olmalı.');
        return (dus: toplam - h, hata: null);
      default:
        final t = paraCoz(metin);
        if (t == null || t <= 0) return (dus: 0, hata: 'Pozitif bir tutar girin.');
        if (t >= toplam) return (dus: 0, hata: 'İskonto adisyon toplamını (${para(toplam)}) aşamaz.');
        return (dus: t, hata: null);
    }
  }

  bool get _kipKilitli => _kip == 'yuzde' ? _indirim > 0 : _iskonto > 0;

  void _manuelUygula() {
    final h = _hesap;
    if (h.hata != null || h.dus <= 0) {
      context.bildir2('Değer geçersiz', h.hata ?? 'Bir değer girin.', hata: true);
      return;
    }
    final gerekce = _gerekce.text.trim();
    if (_kip == 'yuzde') {
      final n = double.parse(_deger.text.trim().replaceAll(' ', '').replaceAll('%', '').replaceAll(',', '.'));
      final y = n == n.roundToDouble() ? n.toInt().toString() : n.toString().replaceAll('.', ',');
      _istek(
        () => context.api.post('$_yol/discount', {
          'type': 'percent',
          'value': n,
          'reason': gerekce.length >= 3 ? gerekce : 'Kasada %$y indirim',
          'expected_version': a.surum,
        }),
        'İndirim uygulandı',
        '%$y · yaklaşık ${para(h.dus)} düşüldü',
      );
      return;
    }
    final hedef = _kip == 'hedef';
    final yeni = a.toplam - h.dus;
    _istek(
      () => context.api.post('$_yol/iskonto', {
        'amount_minor': h.dus,
        'reason': gerekce.length >= 3 ? gerekce : (hedef ? "Kasada hesap ${para(yeni)}'ye indirildi" : 'Kasada iskonto'),
      }),
      'İskonto uygulandı',
      '${para(h.dus)} düşüldü — yeni tutar ${para(yeni)}',
      hata: 'İskonto uygulanamadı',
    );
  }

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 560;
    final mevcut = <Widget>[
      if (_indirim > 0)
        _mevcutSatir(
          Icons.sell_outlined,
          '${a.ham['discount_reason'] ?? 'İndirim'}${a.ham['discount_percent'] != null ? ' (%${a.ham['discount_percent']})' : ''}',
          '−${para(_indirim)}',
          _indirimKaldir,
        ),
      if (_iskonto > 0)
        _mevcutSatir(Icons.percent_rounded, a.ham['iskonto_reason']?.toString() ?? 'İskonto', '−${para(_iskonto)}', _iskontoKaldir),
    ];

    final govde = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      // Adisyon özeti: ara toplam → güncel tutar.
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Row(children: [
          Icon(Icons.receipt_long_outlined, size: 18, color: Renk.ikinci),
          const SizedBox(width: 8),
          Expanded(child: Text('Kalem toplamı ${para(a.araToplam)}', style: TextStyle(fontSize: 13, color: Renk.ikinci))),
          Text('Tutar ', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
          Text(para(a.toplam), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      ),
      if (mevcut.isNotEmpty) ...[const SizedBox(height: 10), ...mevcut],
      const SizedBox(height: 14),
      if (widget.manuel)
        _Sekmeler(
          secili: _manuelSekme ? 1 : 0,
          ogeler: genis
              ? const [(Icons.bookmark_border_rounded, 'Hazır indirimler'), (Icons.edit_note_rounded, 'Manuel iskonto')]
              : const [(Icons.bookmark_border_rounded, 'Hazır'), (Icons.edit_note_rounded, 'Manuel')],
          degisti: (i) => setState(() => _manuelSekme = i == 1),
        )
      else
        Row(children: [
          Icon(Icons.bookmark_border_rounded, size: 18, color: Renk.marka),
          const SizedBox(width: 6),
          const Text('Hazır indirimler', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        ]),
      const SizedBox(height: 12),
      if (_manuelSekme && widget.manuel) _manuelGovde() else _hazirGovde(genis),
    ]);

    return AlertDialog(
      insetPadding: genis ? const EdgeInsets.symmetric(horizontal: 40, vertical: 24) : const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      contentPadding: EdgeInsets.fromLTRB(genis ? 24 : 16, 16, genis ? 24 : 16, 20),
      titlePadding: EdgeInsets.fromLTRB(genis ? 20 : 16, 16, 12, 0),
      title: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: koseYuvarlak),
          child: Icon(Icons.sell_outlined, size: 18, color: Renk.marka),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Text('İndirim / İskonto', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 20)),
      ]),
      content: SizedBox(width: 520, child: SingleChildScrollView(child: govde)),
    );
  }

  Widget _mevcutSatir(IconData ikon, String ad, String tutar, VoidCallback kaldir) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
          child: Row(children: [
            Icon(ikon, size: 17, color: Renk.uyari),
            const SizedBox(width: 8),
            Expanded(child: Text(ad, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            Text(tutar, style: TextStyle(fontWeight: FontWeight.w700, color: Renk.uyari)),
            const SizedBox(width: 6),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Renk.hata, minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 8)),
              onPressed: _mesgul ? null : kaldir,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Kaldır'),
            ),
          ]),
        ),
      );

  Widget _hazirGovde(bool genis) {
    final l = _tanimlar;
    if (l == null) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Tanımlar yükleniyor…', style: TextStyle(color: Renk.soluk)));
    }
    if (l.isEmpty) {
      return Text('Tanımlı hazır indirim yok. Yönetim › İndirim Tanımları ekranından ekleyebilirsiniz (ör. “Öğrenci”, “Personel”).',
          style: TextStyle(fontSize: 13, color: Renk.ikinci));
    }
    final kilitli = _indirim > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (kilitli)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Adisyonda zaten bir indirim var; başkasını uygulamak için önce yukarıdan kaldırın.', style: TextStyle(fontSize: 12.5, color: Renk.ikinci)),
        ),
      LayoutBuilder(builder: (ctx, k) {
        final sutun = k.maxWidth >= 400 ? 2 : 1;
        final en = (k.maxWidth - 8 * (sutun - 1)) / sutun;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in l)
            SizedBox(
              width: en,
              child: Material(
                color: Renk.yuzey,
                shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Renk.cizgi)),
                child: InkWell(
                  borderRadius: koseYuvarlak,
                  onTap: _mesgul || kilitli ? null : () => _hazir(t),
                  child: Opacity(
                    opacity: kilitli ? .5 : 1,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${t['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (t['note'] != null)
                              Text('${t['note']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.soluk)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: koseYuvarlak, border: Border.all(color: Renk.markaKenar)),
                          child: Text('${t['value_label']}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Renk.marka)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      }),
    ]);
  }

  Widget _manuelGovde() {
    final h = _hesap;
    final kilit = _kipKilitli;
    final ipucu = switch (_kip) { 'yuzde' => 'ör. 10', 'hedef' => 'ör. 350,00', _ => 'ör. 45,00' };
    final etiket = switch (_kip) { 'yuzde' => 'İndirim yüzdesi (%)', 'hedef' => 'Hesabın yeni tutarı (₺)', _ => 'Düşülecek tutar (₺)' };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (k, ikon, ad) in const [
          ('tutar', Icons.remove_circle_outline_rounded, 'Tutar yaz'),
          ('yuzde', Icons.percent_rounded, 'Yüzde (%)'),
          ('hedef', Icons.south_rounded, 'Hesabı şu tutara indir'),
        ])
          _KipDugmesi(ikon: ikon, ad: ad, secili: _kip == k, bas: () => setState(() {
                _kip = k;
                _deger.clear();
              })),
      ]),
      const SizedBox(height: 12),
      if (kilit)
        Text(
            _kip == 'yuzde'
                ? 'Adisyonda zaten bir indirim var; yüzde indirim için önce yukarıdan kaldırın.'
                : 'Adisyonda zaten bir iskonto var; yeni tutar için önce yukarıdan kaldırın.',
            style: TextStyle(fontSize: 12.5, color: Renk.ikinci))
      else ...[
        FormAlani(
          etiket: etiket,
          child: TextField(
            controller: _deger,
            autofocus: false,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(hintText: ipucu),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: 8),
        FormAlani(
          etiket: 'Gerekçe',
          ipucu: 'İsteğe bağlı — raporda görünür',
          child: TextField(controller: _gerekce, decoration: const InputDecoration(hintText: 'ör. müdavim, yönetici onayı')),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
          child: Row(children: [
            Expanded(
              child: Text(
                h.hata ?? (h.dus > 0 ? '−${para(h.dus)} düşülür' : 'Değer girince yeni tutar burada görünür.'),
                style: TextStyle(fontSize: 13, color: h.hata != null ? Renk.hata : Renk.ikinci, fontWeight: h.dus > 0 ? FontWeight.w600 : null),
              ),
            ),
            if (h.hata == null && h.dus > 0) ...[
              Text('Yeni tutar ', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              Text(para(a.toplam - h.dus), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Renk.marka)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _mesgul || h.hata != null || h.dus <= 0 ? null : _manuelUygula,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(_kip == 'yuzde' ? 'İndirimi uygula' : 'İskontoyu uygula'),
        ),
      ],
    ]);
  }
}

/// İki sekmeli seçici (alt çizgili; 8px köşe kuralına uygun, hap yok).
class _Sekmeler extends StatelessWidget {
  const _Sekmeler({required this.secili, required this.ogeler, required this.degisti});
  final int secili;
  final List<(IconData, String)> ogeler;
  final ValueChanged<int> degisti;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Row(children: [
        for (var i = 0; i < ogeler.length; i++)
          Expanded(
            child: InkWell(
              key: ValueKey('indirim-sekme-$i'),
              onTap: () => degisti(i),
              child: Container(
                height: 42,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == secili ? Renk.marka : Colors.transparent, width: 2))),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(ogeler[i].$1, size: 18, color: i == secili ? Renk.marka : Renk.ikinci),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(ogeler[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: i == secili ? Renk.marka : Renk.ikinci)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _KipDugmesi extends StatelessWidget {
  const _KipDugmesi({required this.ikon, required this.ad, required this.secili, required this.bas});
  final IconData ikon;
  final String ad;
  final bool secili;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: secili ? Renk.markaAcik : Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? Renk.marka : Renk.cizgiKoyu)),
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: bas,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ikon, size: 17, color: secili ? Renk.marka : Renk.ikinci),
            const SizedBox(width: 6),
            Text(ad, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secili ? Renk.marka : Renk.yazi)),
          ]),
        ),
      ),
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

/* ───────── Kalem notu (web Detail.vue: Not ekle / Notu düzenle) ───────── */

/// Hazırlığa gönderilmemiş kaleme not. Dönüş: null = vazgeçildi;
/// `(not: null)` = notu sil; `(not: '…')` = kaydet. [bekleyen] satır
/// adedinden azsa not yalnız gönderilmemiş adetlere uygulanır (sunucu
/// satırı böler), bu yüzden mevcut not düzenlenmez — yeni not yazılır.
Future<({String? not})?> kalemNotuPenceresi(BuildContext context, Kalem k, int bekleyen) {
  final kismi = bekleyen < k.adet;
  final mevcut = kismi ? null : k.not?.trim();
  final duzenle = mevcut != null && mevcut.isNotEmpty;
  final c = TextEditingController(text: duzenle ? mevcut : '');
  return pencereAc<({String? not})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) {
        final metin = c.text.trim();
        // Açılışta alan seçili GELMEZ; alana dokununca ekran klavyesi açılır
        // (web ile aynı) ve pencere ekranın üstüne çıkar, Kaydet görünür kalır.
        return ValueListenableBuilder<bool>(
          valueListenable: EkranKlavyesi.acik,
          builder: (ctx, klavye, _) => AlertDialog(
          alignment: klavye ? Alignment.topCenter : null,
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          title: Text(duzenle ? 'Notu düzenle' : 'Not ekle'),
          content: SizedBox(
            width: 560,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${k.adet}× ${k.ad}${k.varyant != null ? ' (${k.varyant})' : ''}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Mutfak / bar fişine basılır.', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              if (kismi) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: Renk.uyari),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Not yalnız gönderilmemiş $bekleyen adede uygulanır', style: TextStyle(fontSize: 13.5, color: Renk.uyari))),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              KlavyeliAlan(
                key: const ValueKey('kalem-notu-alan'),
                controller: c,
                minLines: 5,
                maxLines: 5,
                maxLength: 200,
                multiline: true,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 17, height: 1.4),
                decoration: const InputDecoration(
                  hintText: 'İsteğe bağlı — ör. az pişmiş, mantar eklemeyin, laktozsuz süt',
                  hintMaxLines: 2,
                  contentPadding: EdgeInsets.all(14),
                ),
                onChanged: (_) => yenile(() {}),
              ),
            ]),
          ),
          actions: [
            if (duzenle)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Renk.hata),
                onPressed: () => Navigator.pop(ctx, (not: null)),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Notu sil'),
              ),
            OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: metin.isEmpty || metin == mevcut ? null : () => Navigator.pop(ctx, (not: metin)),
              child: const Text('Kaydet'),
            ),
          ],
        ),
        );
      },
    ),
  );
}
