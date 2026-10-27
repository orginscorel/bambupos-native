import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'kasa_kapanisi.dart' show kisaTarihSaat, syDugme;
import 'ortak.dart';

/// GİDERLER — web /panel/gelir-gider (GelirGider/Index.vue) birebiri.
/// Şartname: /root/work/spec/giderler.md. Tüm hesap sunucuda; istemci
/// yalnız gösterir (tek istisna: "Kaydedince kalan" önizlemesi).

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

String _gun(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
DateTime? _ayir(String? s) {
  if (s == null || s.length < 10) return null;
  final p = s.substring(0, 10).split('-');
  if (p.length != 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]), 12);
}

String _uzunTarih(String? s) {
  final t = _ayir(s);
  return t == null ? '' : '${t.day} ${_aylar[t.month - 1]} ${t.year}';
}

/// "25 Ekim 2026" ya da "1 Ekim 2026 – 25 Ekim 2026".
String aralikEtiketi(String? from, String? to) {
  if (from == null || from.isEmpty) return '';
  if (to == null || to.isEmpty || to == from) return _uzunTarih(from);
  return '${_uzunTarih(from)} – ${_uzunTarih(to)}';
}

/// Giderler / tahsilat ekranlarının "Bugün / Dün / …" aralıkları: iş günü
/// gün sonu kapanışıyla döner (borclar.md "İş günü aralıkları").
(String, String)? isGunuAraligi(String hazir, String bugun, String? dun) {
  final b = _ayir(bugun) ?? DateTime.now();
  String once(int g) => _gun(b.subtract(Duration(days: g)));
  return switch (hazir) {
    'bugun' => (bugun, bugun),
    'dun' => (dun ?? once(1), dun ?? once(1)),
    'hafta' => (once(6), bugun),
    'otuz' => (once(29), bugun),
    'ay' => ('${bugun.substring(0, 7)}-01', bugun),
    _ => null,
  };
}

const _hazirlar = [('bugun', 'Bugün'), ('dun', 'Dün'), ('hafta', 'Son 7 gün'), ('otuz', 'Son 30 gün'), ('ay', 'Bu ay'), ('ozel', 'Tarih seç')];

const _iptalNedenleri = [
  'Yanlış girildi', 'Yanlış tutar', 'Yanlış tür seçildi', 'Mükerrer kayıt', 'Yanlış ödeme şekli', 'Gider yapılmadı', 'Tutar iade alındı', 'Deneme kaydı',
];

int _tutarMinor(String s) {
  final t = s.trim().replaceAll(' ', '').replaceAll('.', '').replaceFirst(',', '.');
  final n = double.tryParse(t);
  return n != null && n.isFinite && n > 0 ? (n * 100).round() : 0;
}

class GiderlerEkrani extends StatefulWidget {
  const GiderlerEkrani({super.key});

  @override
  State<GiderlerEkrani> createState() => _GiderlerEkraniState();
}

class _GiderlerEkraniState extends State<GiderlerEkrani> {
  late final Api _api = context.api;

  String _bugun = _gun(DateTime.now());
  String? _dun;
  String _hazir = 'bugun';
  String _from = '';
  String _to = '';
  bool _yukleniyor = false;
  Map<String, dynamic>? _veri;

  // Pencere durumu (başarılı kayda kadar korunur).
  String _tur = 'alisveris';
  String _odeme = 'cash';
  final _aciklama = TextEditingController();
  String _tutar = '';
  int? _personelId;
  List<Map<String, dynamic>>? _personel;

  @override
  void initState() {
    super.initState();
    _ilk();
  }

  @override
  void dispose() {
    _aciklama.dispose();
    super.dispose();
  }

  Future<void> _ilk() async {
    try {
      final d = await _api.get('/api/v1/reports/eod/durum');
      if (d is Map) {
        _bugun = d['is_gunu']?.toString() ?? _bugun;
        final s = d['son_kapanis'];
        _dun = s is Map ? s['is_gunu']?.toString() : null;
      }
    } on ApiHata {
      // takvim günü kullanılır
    }
    _hazirSec('bugun');
  }

  void _hazirSec(String h) {
    setState(() => _hazir = h);
    final a = isGunuAraligi(h, _bugun, _dun);
    if (a == null) {
      if (_from.isEmpty) {
        _from = _bugun;
        _to = _bugun;
      }
      return;
    }
    _from = a.$1;
    _to = a.$2;
    _yukle();
  }

  List<Map<String, dynamic>> _liste(Object? v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await _api.get('/api/v1/giderler', sorgu: {if (_from.isNotEmpty) 'from': _from, if (_to.isNotEmpty) 'to': _to});
      if (mounted && r is Map) setState(() => _veri = r.cast<String, dynamic>());
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Giderler yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _tarihSec(bool bas) async {
    final ilk = _ayir(bas ? _from : _to) ?? DateTime.now();
    final t = await showDatePicker(context: context, initialDate: ilk, firstDate: DateTime(2020), lastDate: DateTime(2100), locale: const Locale('tr', 'TR'));
    if (t == null) return;
    setState(() => bas ? _from = _gun(t) : _to = _gun(t));
  }

  /* ── görünüm ── */

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    final g = MediaQuery.sizeOf(context).width;
    final gelir = (v?['gelir'] as Map?)?.cast<String, dynamic>() ?? const {};
    final turler = _liste(v?['turler']);
    final satirlar = _liste(v?['satirlar']);
    final yazabilir = v?['yazabilir'] == true;
    final range = (v?['range'] as Map?)?.cast<String, dynamic>();
    final kalan = tamSayi(v?['kalan_minor']);

    return ColoredBox(
      color: Kabuk.sunken,
      child: SingleChildScrollView(
        padding: g >= 1024 ? const EdgeInsets.fromLTRB(18, 12, 18, 22) : const EdgeInsets.fromLTRB(14, 10, 14, 20),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 13, color: Kabuk.ink),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Başlık satırı
            Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Giderler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.36)),
              const SizedBox(width: 4),
              _kutu(DropdownButton<String>(
                value: _hazir,
                isDense: true,
                underline: const SizedBox(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 14),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Kabuk.ink),
                items: [for (final (k, e) in _hazirlar) DropdownMenuItem(value: k, child: Text(e))],
                onChanged: (h) => _hazirSec(h ?? 'bugun'),
              )),
              if (_hazir == 'ozel') ...[
                _kutu(InkWell(onTap: () => _tarihSec(true), child: Text(_from.isEmpty ? 'Başlangıç' : _from))),
                _kutu(InkWell(onTap: () => _tarihSec(false), child: Text(_to.isEmpty ? 'Bitiş' : _to))),
                syDugme('Getir', _yukleniyor ? null : _yukle, yukseklik: 32),
              ],
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text(aralikEtiketi(range?['from']?.toString() ?? _from, range?['to']?.toString() ?? _to),
                    textAlign: g < 640 ? TextAlign.left : TextAlign.right, style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
              ),
              if (yazabilir) ...[const SizedBox(width: 8), syDugme('Gider ekle', _pencereAc, birincil: true, ikon: Icons.add_rounded, yukseklik: 32)],
            ]),
            const SizedBox(height: 8),
            // KPI şeridi
            _kpi(g, [
              ('Tahsilat (nakit + kart)', para(tamSayi(gelir['kasa_pos_minor'])),
                  'nakit ${para(tamSayi(gelir['nakit_minor']))} · kart ${para(tamSayi(gelir['kart_minor']))}', Kabuk.success),
              ('Giderler', '−${para(tamSayi(v?['gider_toplam_minor']))}', '${tamSayi(v?['gider_adet'])} kayıt', Kabuk.negative),
              ('Kalan', para(kalan), 'nakit + kart tahsilattan giderler düşülmüş hâli', kalan < 0 ? Kabuk.negative : Kabuk.ink),
              ('Havale / EFT', para(tamSayi(gelir['eft_minor'])), 'kalana dahil değil · bankadan kontrol edin', Kabuk.ink),
            ]),
            if (turler.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in turler)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${t['label']} ', style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
                      Text(para(tamSayi(t['amount_minor'])), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: BorderRadius.circular(4)),
                        child: Text('${tamSayi(t['count'])}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
              ]),
            ],
            const SizedBox(height: 8),
            _tablo(satirlar, yazabilir),
          ]),
        ),
      ),
    );
  }

  Widget _kutu(Widget c) => Container(
        height: 32,
        constraints: const BoxConstraints(minWidth: 118),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        child: DefaultTextStyle.merge(style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), child: c),
      );

  Widget _kpi(double g, List<(String, String, String, Color)> ogeler) {
    final sutun = g >= 900 ? 4 : 2;
    final satirlar = <Widget>[];
    for (var i = 0; i < ogeler.length; i += sutun) {
      satirlar.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + sutun; j++) ...[
            if (j > i) const SizedBox(width: 8),
            Expanded(
              child: j >= ogeler.length
                  ? const SizedBox()
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ogeler[j].$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(ogeler[j].$2, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ogeler[j].$4, fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                        Text(ogeler[j].$3, style: TextStyle(fontSize: 11, color: Kabuk.soft)),
                      ]),
                    ),
            ),
          ],
        ]),
      ));
    }
    return Column(children: [for (var i = 0; i < satirlar.length; i++) ...[if (i > 0) const SizedBox(height: 8), satirlar[i]]]);
  }

  Widget _tablo(List<Map<String, dynamic>> satirlar, bool yazabilir) {
    final b = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Kabuk.soft, letterSpacing: .6);
    const genislik = [92.0, 130.0, 230.0, 110.0, 120.0, 110.0, 70.0];
    Widget h(int i, Widget c, {bool sag = false}) => SizedBox(
          width: genislik[i],
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Align(alignment: sag ? Alignment.centerRight : Alignment.centerLeft, child: c)),
        );
    final toplamGenislik = genislik.fold<double>(0, (t, x) => t + x);

    Widget durum(Widget c) => Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
          child: c,
        );

    return Container(
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, k) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: toplamGenislik < k.maxWidth ? k.maxWidth : toplamGenislik,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: Kabuk.sunken,
                child: Row(children: [
                  h(0, Text('TARİH', style: b)),
                  h(1, Text('TÜR', style: b)),
                  Expanded(child: h(2, Text('AÇIKLAMA', style: b))),
                  h(3, Text('ÖDEME', style: b)),
                  h(4, Text('GİREN', style: b)),
                  h(5, Text('TUTAR', style: b), sag: true),
                  h(6, const SizedBox()),
                ]),
              ),
              if (_yukleniyor && _veri == null)
                durum(Text('Yükleniyor…', textAlign: TextAlign.center, style: TextStyle(color: Kabuk.soft)))
              else if (satirlar.isEmpty)
                durum(Column(children: [
                  Text('Bu dönemde gider yok', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('Gider eklendikçe burada listelenir ve tahsilattan düşülür.', style: TextStyle(fontSize: 12, color: Kabuk.soft)),
                ]))
              else
                for (final s in satirlar)
                  Container(
                    key: ValueKey('${s['kaynak']}-${s['id']}'),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
                    child: Row(children: [
                      h(0, Text(kisaTarihSaat(s['tarih_at']?.toString()), style: TextStyle(fontSize: 12.5, color: Kabuk.soft))),
                      h(1, Text('${s['tur_label'] ?? ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                      Expanded(
                        child: h(
                          2,
                          s['personel'] != null
                              ? Text.rich(TextSpan(children: [
                                  TextSpan(text: '${s['personel']}'),
                                  if (s['aciklama'] != null) TextSpan(text: ' · ${s['aciklama']}', style: TextStyle(color: Kabuk.soft)),
                                ]), style: const TextStyle(fontSize: 12.5))
                              : Text('${s['aciklama'] ?? '—'}', style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                      h(3, Text('${s['odeme_label'] ?? ''}', style: TextStyle(fontSize: 12.5, color: Kabuk.soft))),
                      h(4, Text('${s['olusturan'] ?? (s['kaynak'] == 'kasa_hareketi' ? 'Kasa yönetimi' : '—')}', style: const TextStyle(fontSize: 12.5))),
                      h(5, Text('−${para(tamSayi(s['tutar_minor']))}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Kabuk.negative)), sag: true),
                      h(
                        6,
                        yazabilir && s['iptal_edilebilir'] == true
                            ? SizedBox(
                                height: 28,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    minimumSize: const Size(0, 28),
                                    foregroundColor: Kabuk.soft,
                                    side: BorderSide(color: Kabuk.line),
                                    shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                  ),
                                  onPressed: () => _iptalPenceresi(s),
                                  child: const Text('İptal'),
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ]),
                  ),
            ]),
          ),
        ),
      ),
    );
  }

  /* ── "Gider ekle" penceresi ── */

  Future<void> _personelYukle(StateSetter yenile) async {
    if (_personel != null) return;
    try {
      final r = await _api.get('/api/v1/giderler/personel');
      _personel = _liste(r is Map ? r['personel'] : null);
    } on ApiHata {
      _personel = const [];
    }
    yenile(() {});
  }

  Future<void> _pencereAc() async {
    final v = _veri ?? const {};
    final turler = _liste(v['turler_secenek']);
    final odemeler = _liste(v['odeme_sekilleri']);
    final kasaPos = tamSayi((v['gelir'] as Map?)?['kasa_pos_minor']);
    final kalan = tamSayi(v['kalan_minor']);
    var numpad = false;
    var kaydediliyor = false;
    if (turler.any((t) => t['value'] == _tur && t['personel'] == true)) _personelYukle((f) => setState(f));

    await pencereAc<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x730F172A),
      builder: (ctx) => StatefulBuilder(builder: (ctx, yenile) {
        final secili = turler.where((t) => t['value'] == _tur).firstOrNull;
        final personelli = secili?['personel'] == true;
        final oneriler = ((secili?['oneriler'] as List?) ?? const []).map((e) => '$e').toList();
        final tutar = _tutarMinor(_tutar);
        final genis = MediaQuery.sizeOf(ctx).width >= 820;

        Future<void> kaydet() async {
          if (tutar <= 0) {
            context.bildir2('Tutar gerekli', 'Giderin tutarını yazın.', hata: true);
            yenile(() => numpad = true);
            return;
          }
          if (personelli && _personelId == null) {
            context.bildir2('Personel seçin', 'Personel giderinde kime ödendiğini seçin.', hata: true);
            return;
          }
          yenile(() => kaydediliyor = true);
          try {
            await _api.post('/api/v1/giderler', {
              'tur': _tur,
              'aciklama': _aciklama.text.trim().isEmpty ? null : _aciklama.text.trim(),
              'personel_id': personelli ? _personelId : null,
              'tutar_minor': tutar,
              'odeme_sekli': _odeme,
            });
            if (!mounted) return;
            context.bildir2('Gider eklendi', '${para(tutar)} gider olarak işlendi.');
            _aciklama.clear();
            _tutar = '';
            _personelId = null;
            if (ctx.mounted) Navigator.pop(ctx);
            _yukle();
          } on ApiHata catch (e) {
            if (mounted) context.bildir2('Gider eklenemedi', e.mesaj, hata: true);
          } finally {
            if (ctx.mounted) yenile(() => kaydediliyor = false);
          }
        }

        void tus(String t) => yenile(() {
              if (t == 'sil') {
                if (_tutar.isNotEmpty) _tutar = _tutar.substring(0, _tutar.length - 1);
              } else if (t == ',') {
                if (!_tutar.contains(',')) _tutar = _tutar.isEmpty ? '0,' : '$_tutar,';
              } else {
                final v = _tutar.indexOf(',');
                if (v >= 0 && _tutar.length - v - 1 >= 2) return;
                _tutar += t;
              }
            });

        final sol = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Et('Gider türü'),
          LayoutBuilder(builder: (context, k) {
            final sutun = (k.maxWidth / 110).floor().clamp(1, 6);
            final w = (k.maxWidth - 6 * (sutun - 1)) / sutun;
            return Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in turler)
                SizedBox(
                  width: w,
                  child: _Secim(
                    secili: t['value'] == _tur,
                    bas: () {
                      yenile(() {
                        _tur = '${t['value']}';
                        _aciklama.clear();
                        _personelId = null;
                      });
                      if (t['personel'] == true) _personelYukle(yenile);
                    },
                    child: Text('${t['label']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]);
          }),
          if (personelli) ...[
            const _Et('Personel'),
            Secici<int>(
              deger: _personelId,
              yerTutucu: 'Personel seçin…',
              secenekler: [for (final p in _personel ?? const <Map<String, dynamic>>[]) (tamSayi(p['id']), '${p['name']}')],
              degisti: (v) => yenile(() => _personelId = v),
            ),
          ],
          const _Et('Açıklama'),
          TextField(
            controller: _aciklama,
            maxLength: 160,
            onTap: () => yenile(() => numpad = false),
            onChanged: (_) => yenile(() {}),
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(hintText: 'ör. market alışverişi', counterText: ''),
          ),
          if (oneriler.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final o in oneriler)
                SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: _aciklama.text == o ? Kabuk.brand : Kabuk.soft,
                      side: BorderSide(color: _aciklama.text == o ? Kabuk.brand : Kabuk.line),
                      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => yenile(() => _aciklama.text = o),
                    child: Text(o),
                  ),
                ),
            ]),
          ],
          const _Et('Ödeme şekli'),
          LayoutBuilder(builder: (context, k) {
            final w = (k.maxWidth - 8) / 2;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in odemeler)
                SizedBox(
                  width: w,
                  child: _Secim(
                    secili: o['value'] == _odeme,
                    yukseklik: 56,
                    bas: () => yenile(() => _odeme = '${o['value']}'),
                    child: Row(children: [
                      _OdemeSimgesi(deger: '${o['value']}'),
                      const SizedBox(width: 10),
                      Flexible(child: Text('${o['label']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                    ]),
                  ),
                ),
            ]);
          }),
        ]);

        final sag = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Et('Tutar'),
          InkWell(
            onTap: () => yenile(() => numpad = true),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: numpad ? Kabuk.brand : Kabuk.line, width: numpad ? 2 : 1)),
              child: Row(children: [
                Text('₺', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Kabuk.soft)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_tutar.isEmpty ? '0,00' : _tutar,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _tutar.isEmpty ? Kabuk.line : Kabuk.ink, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
                Text('TRY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Kabuk.soft)),
              ]),
            ),
          ),
          if (numpad) ...[
            const SizedBox(height: 6),
            _Numpad(bas: tus),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak),
            child: Wrap(spacing: 16, runSpacing: 4, children: [
              Text.rich(TextSpan(children: [const TextSpan(text: 'Tahsilat '), TextSpan(text: para(kasaPos), style: const TextStyle(fontWeight: FontWeight.w700))]),
                  style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Bu gider '),
                TextSpan(text: tutar > 0 ? '−${para(tutar)}' : '—', style: TextStyle(fontWeight: FontWeight.w700, color: tutar > 0 ? Kabuk.negative : Kabuk.ink)),
              ]), style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Kaydedince kalan '),
                TextSpan(text: para(kalan - tutar), style: TextStyle(fontWeight: FontWeight.w700, color: kalan - tutar < 0 ? Kabuk.negative : Kabuk.ink)),
              ]), style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
            ]),
          ),
        ]);

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 1088, maxHeight: MediaQuery.sizeOf(ctx).height - 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
                child: Row(children: [
                  const Expanded(child: Text('Gider ekle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 16)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                  child: genis
                      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 105, child: sol), const SizedBox(width: 18), Expanded(flex: 100, child: sag)])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [sol, sag]),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
                child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                  syDugme('Geri', () => Navigator.pop(ctx)),
                  syDugme(kaydediliyor ? 'Ekleniyor…' : 'Ekle${tutar > 0 ? ' · ${para(tutar)}' : ''}', kaydediliyor ? null : kaydet, birincil: true),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  /* ── "Gideri iptal et" penceresi ── */

  Future<void> _iptalPenceresi(Map<String, dynamic> s) async {
    final neden = TextEditingController();
    var isleniyor = false;
    await pencereAc<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x730F172A),
      builder: (ctx) => StatefulBuilder(builder: (ctx, yenile) {
        final genis = MediaQuery.sizeOf(ctx).width >= 620;
        Widget kunye(String e, String d, {Color? renk}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e, style: TextStyle(fontSize: 11, color: Kabuk.soft)),
              Text(d, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: renk ?? Kabuk.ink)),
            ]);
        final kunyeler = [
          kunye('Tür', '${s['tur_label'] ?? ''}'),
          kunye('Tutar', para(tamSayi(s['tutar_minor'])), renk: Kabuk.negative),
          kunye('Ödeme', '${s['odeme_label'] ?? ''}'),
          kunye('Tarih', kisaTarihSaat(s['tarih_at']?.toString())),
        ];
        final aciklama = [if (s['personel'] != null) '${s['personel']}', if (s['aciklama'] != null) '${s['aciklama']}'].join(' · ');

        Future<void> onayla() async {
          yenile(() => isleniyor = true);
          try {
            await _api.post('/api/v1/giderler/${s['id']}/iptal', {'neden': neden.text.trim()});
            if (!mounted) return;
            context.bildir2('Gider iptal edildi', 'Gider kaldırıldı; kalan tutar yeniden hesaplandı.');
            if (ctx.mounted) Navigator.pop(ctx);
            _yukle();
          } on ApiHata catch (e) {
            if (mounted) context.bildir2('İptal edilemedi', e.mesaj, hata: true);
          } finally {
            if (ctx.mounted) yenile(() => isleniyor = false);
          }
        }

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 672, maxHeight: MediaQuery.sizeOf(ctx).height - 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
                child: Row(children: [
                  const Expanded(child: Text('Gideri iptal et', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, size: 16)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (genis)
                          Row(children: [for (final k in kunyeler) Expanded(child: k)])
                        else ...[
                          Row(children: [Expanded(child: kunyeler[0]), Expanded(child: kunyeler[1])]),
                          const SizedBox(height: 6),
                          Row(children: [Expanded(child: kunyeler[2]), Expanded(child: kunyeler[3])]),
                        ],
                        if (aciklama.isNotEmpty) ...[const SizedBox(height: 6), kunye('Açıklama', aciklama)],
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text('Nakit gider iptal edilince tutar kasa çekmecesine geri eklenir.', style: TextStyle(fontSize: 13, color: Kabuk.soft)),
                    const _Et('Sebep seç'),
                    LayoutBuilder(builder: (context, k) {
                      final sutun = (k.maxWidth / 156).floor().clamp(1, 4);
                      final w = (k.maxWidth - 6 * (sutun - 1)) / sutun;
                      return Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final n in _iptalNedenleri)
                          SizedBox(
                            width: w,
                            child: _Secim(
                              secili: neden.text == n,
                              yukseklik: 38,
                              bas: () => yenile(() => neden.text = n),
                              child: Text(n, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ]);
                    }),
                    const _Et('Ya da yaz'),
                    TextField(
                      controller: neden,
                      maxLength: 120,
                      onChanged: (_) => yenile(() {}),
                      decoration: const InputDecoration(hintText: 'ör. yanlış girildi', counterText: ''),
                    ),
                  ]),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
                child: Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                  syDugme('Vazgeç', () => Navigator.pop(ctx)),
                  syDugme(isleniyor ? 'İptal ediliyor…' : 'İptal et', isleniyor || neden.text.trim().length < 3 ? null : onayla, birincil: true),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _Et extends StatelessWidget {
  const _Et(this.metin);
  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 5),
        child: Text(metin.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Kabuk.soft, letterSpacing: .66)),
      );
}

/// Seçilebilir kart düğme: seçiliyken brand çerçeve + %10 brand zemin.
class _Secim extends StatelessWidget {
  const _Secim({required this.secili, required this.bas, required this.child, this.yukseklik = 46});
  final bool secili;
  final VoidCallback bas;
  final Widget child;
  final double yukseklik;

  @override
  Widget build(BuildContext context) => Material(
        color: secili ? Color.alphaBlend(Kabuk.brand.withValues(alpha: .10), Renk.yuzey) : Renk.yuzey,
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? Kabuk.brand : Kabuk.line)),
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: bas,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: yukseklik),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Center(
                child: DefaultTextStyle.merge(style: TextStyle(color: secili ? Kabuk.brand : Kabuk.ink), child: child),
              ),
            ),
          ),
        ),
      );
}

class _OdemeSimgesi extends StatelessWidget {
  const _OdemeSimgesi({required this.deger});
  final String deger;

  @override
  Widget build(BuildContext context) {
    final (ikon, ton) = switch (deger) {
      'cash' => (Icons.account_balance_wallet_outlined, Kabuk.success),
      'credit_card' => (Icons.credit_card_rounded, Kabuk.brand),
      'transfer' => (Icons.arrow_forward_rounded, Kabuk.info),
      _ => (Icons.more_vert_rounded, Kabuk.soft),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: ton.withValues(alpha: .14), borderRadius: koseYuvarlak),
      child: Icon(ikon, size: 20, color: ton),
    );
  }
}

class _Numpad extends StatelessWidget {
  const _Numpad({required this.bas});
  final ValueChanged<String> bas;

  @override
  Widget build(BuildContext context) {
    const tuslar = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', ',', 'sil'];
    return Column(children: [
      for (var i = 0; i < tuslar.length; i += 3) ...[
        if (i > 0) const SizedBox(height: 6),
        Row(children: [
          for (var j = i; j < i + 3; j++) ...[
            if (j > i) const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 46,
                child: Material(
                  color: Renk.yuzey,
                  shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
                  child: InkWell(
                    borderRadius: koseYuvarlak,
                    onTap: () => bas(tuslar[j]),
                    child: Center(
                      child: tuslar[j] == 'sil'
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.arrow_back_rounded, size: 16, color: Kabuk.soft),
                              SizedBox(width: 4),
                              Text('Sil', style: TextStyle(fontSize: 13.5, color: Kabuk.soft)),
                            ])
                          : Text(tuslar[j], style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Kabuk.ink)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ]),
      ],
    ]);
  }
}
