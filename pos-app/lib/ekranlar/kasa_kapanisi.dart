import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'ortak.dart';

/// KASA KAPANIŞI — web /panel/kasa/yonetim (CashDesk.vue) birebiri.
/// Şartname: /root/work/spec/kasa-kapanisi.md. Sayım KÖR: beklenen tutar
/// kapanıştan önce hiçbir yerde gösterilmez.

/* ═════════════ Ortak (Giderler / Gün Sonu da kullanır) ═════════════ */

/// "26.10 09:12" (tr-TR gün.ay saat:dakika, yerel saat).
String kisaTarihSaat(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '—';
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${iki(t.day)}.${iki(t.month)} ${iki(t.hour)}:${iki(t.minute)}';
}

/// "26.10.2026 09:12:05" (toLocaleString('tr-TR')).
String tamTarihSaat(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '—';
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${iki(t.day)}.${iki(t.month)}.${t.year} ${iki(t.hour)}:${iki(t.minute)}:${iki(t.second)}';
}

/// Web ortak kabuk penceresi (.sy-ort / .sy-mod): başlık · kayan gövde · sağa
/// yaslı dip. [genislik] web `min(34rem,100%)` = 544.
Future<T?> syPencere<T>(
  BuildContext context, {
  required String baslik,
  required Widget Function(BuildContext ctx, StateSetter yenile) govde,
  required List<Widget> Function(BuildContext ctx, StateSetter yenile) dip,
  double genislik = 544,
  bool perdeKapatir = true,
  bool kapatDugmesi = false,
}) {
  return pencereAc<T>(
    context: context,
    barrierDismissible: perdeKapatir,
    barrierColor: const Color(0x730F172A),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, yenile) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: genislik, maxHeight: MediaQuery.sizeOf(ctx).height * .85),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: EdgeInsets.fromLTRB(14, kapatDugmesi ? 6 : 12, kapatDugmesi ? 6 : 14, kapatDugmesi ? 6 : 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Kabuk.line))),
              child: Row(children: [
                Expanded(child: Text(baslik, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Kabuk.ink))),
                if (kapatDugmesi)
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close_rounded, size: 18, color: Kabuk.soft),
                  ),
              ]),
            ),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: govde(ctx, yenile))),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: dip(ctx, yenile)),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Kabuk düğmeleri (36–40 px, köşe 8, birincil = brand zemin).
Widget syDugme(String metin, VoidCallback? bas, {bool birincil = false, IconData? ikon, double yukseklik = 38, Color? renk}) {
  final stil = ButtonStyle(
    minimumSize: MaterialStatePropertyAll(Size(0, yukseklik)),
    padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
    shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: koseYuvarlak)),
    textStyle: const MaterialStatePropertyAll(TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
  );
  final ic = ikon == null
      ? Text(metin)
      : Row(mainAxisSize: MainAxisSize.min, children: [Icon(ikon, size: 16), const SizedBox(width: 6), Text(metin)]);
  if (birincil) {
    return FilledButton(
      style: stil.copyWith(backgroundColor: MaterialStateProperty.resolveWith((s) => s.contains(MaterialState.disabled) ? (renk ?? Kabuk.brand).withOpacity(.5) : (renk ?? Kabuk.brand)), foregroundColor: const MaterialStatePropertyAll(Colors.white)),
      onPressed: bas,
      child: ic,
    );
  }
  return OutlinedButton(
    style: stil.copyWith(
      foregroundColor: MaterialStatePropertyAll(renk ?? Kabuk.ink),
      side: MaterialStatePropertyAll(BorderSide(color: Kabuk.line)),
      backgroundColor: MaterialStatePropertyAll(Renk.yuzey),
    ),
    onPressed: bas,
    child: ic,
  );
}

/// Inertia sayfasının prop'larını okur (sayfa HTML'indeki
/// `<script data-page type="application/json">`). Ayrı JSON ucu olmayan
/// ayarlar (ör. kasaAcilis) için. Okunamazsa null.
Future<Map<String, dynamic>?> inertiaPropsOku(Api api, String yol) async {
  try {
    final r = await api.get(yol, basliklar: {'Accept': 'text/html', 'X-Requested-With': ''});
    final html = r is String ? r : null;
    if (html == null) return null;
    final m = RegExp(r'<script data-page="[^"]*" type="application/json">([\s\S]*?)</script>').firstMatch(html);
    if (m == null) return null;
    final sayfa = jsonDecode(m.group(1)!);
    final props = sayfa is Map ? sayfa['props'] : null;
    return props is Map ? props.cast<String, dynamic>() : null;
  } catch (_) {
    return null;
  }
}

int tlMinor(String? m) {
  final n = num.tryParse((m == null || m.isEmpty ? '0' : m).replaceAll(',', '.'));
  return n == null || !n.isFinite ? 0 : (n * 100).round();
}

/* ═════════════ Ekran ═════════════ */

class KasaKapanisiEkrani extends StatefulWidget {
  const KasaKapanisiEkrani({super.key});

  @override
  State<KasaKapanisiEkrani> createState() => _KasaKapanisiEkraniState();
}

const _banknotlar = [1, 5, 10, 20, 50, 100, 200];

class _KasaKapanisiEkraniState extends State<KasaKapanisiEkrani> {
  late final Api _api = context.api;

  bool _yukleniyor = true;
  bool _mesgul = false;
  bool _otoDenendi = false;
  List<Map<String, dynamic>> _kasalar = const [];
  int? _kasaId;
  Map<String, dynamic>? _oturum;
  List<Map<String, dynamic>> _hareketler = const [];
  List<String> _acikMasalar = const [];
  String _acilisModu = 'manuel';
  int _acilisTutar = 0;

  final Map<String, String> _deger = {'acilis': '', 'nakit': '', 'kart': '', 'mobil': ''};
  final Map<int, String> _adet = {for (final b in _banknotlar) b: ''};
  String _odak = 'nakit';
  bool _nakitAcik = false;
  String _gecenTur = 'expense';

  bool get _yonetebilir => context.durum.oturum!.yetki('cash.close');

  @override
  void initState() {
    super.initState();
    _ilkYukleme();
  }

  Future<void> _ilkYukleme() async {
    final props = await inertiaPropsOku(_api, '/panel/kasa/yonetim');
    final ka = props?['kasaAcilis'];
    if (ka is Map) {
      _acilisModu = ka['mod'] == 'otomatik' ? 'otomatik' : 'manuel';
      _acilisTutar = tamSayi(ka['tutar_minor']);
    }
    await _yukle();
  }

  List<Map<String, dynamic>> _liste(Object? v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  Future<void> _yukle() async {
    try {
      final r = await _api.get('/api/v1/cash/registers');
      final kasalar = _liste(r is Map ? r['registers'] : null);
      var secili = _kasaId;
      if (secili == null || !kasalar.any((k) => tamSayi(k['id']) == secili)) {
        final acik = kasalar.where((k) => k['open_session'] != null);
        secili = acik.isNotEmpty ? tamSayi(acik.first['id']) : (kasalar.isNotEmpty ? tamSayi(kasalar.first['id']) : null);
      }
      if (!mounted) return;
      setState(() {
        _kasalar = kasalar;
        _kasaId = secili;
      });
      await _oturumYukle();
      _masalariYukle();
      if (_acilisModu == 'otomatik' && _oturum == null && _kasaId != null && _yonetebilir && !_otoDenendi) {
        _otoDenendi = true;
        await _kasaAc();
      }
      _otoDenendi = true;
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _oturumYukle() async {
    final kasa = _kasalar.where((k) => tamSayi(k['id']) == _kasaId).firstOrNull;
    final acik = kasa?['open_session'];
    if (acik is! Map) {
      if (mounted) {
        setState(() {
          _oturum = null;
          _hareketler = const [];
        });
      }
      return;
    }
    try {
      final r = await _api.get('/api/v1/cash/sessions/${acik['id']}');
      if (!mounted || r is! Map) return;
      setState(() {
        _oturum = (r['session'] as Map?)?.cast<String, dynamic>();
        _hareketler = _liste(r['movements']);
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Yüklenemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _masalariYukle() async {
    try {
      final r = await _api.get('/api/v1/orders/board');
      final masalar = _liste(r is Map ? r['tables'] : null);
      if (mounted) {
        setState(() => _acikMasalar = [
              for (final t in masalar)
                if ((t['orders'] as List? ?? const []).isNotEmpty) '${t['name'] ?? ''}',
            ]);
      }
    } on ApiHata {
      if (mounted) setState(() => _acikMasalar = const []);
    }
  }

  /* ── hesaplar ── */

  int get _banknotToplam => _banknotlar.fold(0, (t, b) => t + b * (int.tryParse(_adet[b]!) ?? 0)) * 100;
  bool get _banknotVar => _banknotlar.any((b) => (int.tryParse(_adet[b]!) ?? 0) > 0);
  int get _nakitMinor => _banknotVar ? _banknotToplam : tlMinor(_deger['nakit']);

  List<Map<String, dynamic>> get _giderler => [
        for (final h in _hareketler)
          if (const {'expense', 'advance', 'cash_out'}.contains(h['type']) && h['reversed_by_id'] == null && h['reverses_id'] == null) h,
      ];

  String _goster(String m) => m.isEmpty ? '' : '$m ₺';

  /* ── tuş takımı ── */

  void _tus(String t) => setState(() {
        if (_odak.startsWith('b')) {
          final b = int.parse(_odak.substring(1));
          var v = _adet[b]!;
          if (t == 'sil') {
            v = v.isEmpty ? v : v.substring(0, v.length - 1);
          } else if (t != '.') {
            if (v.length >= 5) return;
            v = v == '0' ? t : v + t;
          }
          _adet[b] = v;
          return;
        }
        var v = _deger[_odak] ?? '';
        if (t == 'sil') {
          v = v.isEmpty ? v : v.substring(0, v.length - 1);
        } else if (t == '.') {
          if (!v.contains('.')) v = v.isEmpty ? '0.' : '$v.';
        } else {
          final nokta = v.indexOf('.');
          if (nokta >= 0 && v.length - nokta - 1 >= 2) return;
          if (nokta < 0 && v.replaceAll('.', '').length >= 8) return;
          v = v == '0' ? t : v + t;
        }
        _deger[_odak] = v;
      });

  /* ── eylemler ── */

  Future<void> _kasaAc() async {
    final kasa = _kasaId;
    if (kasa == null || _mesgul) return;
    final otomatik = _acilisModu == 'otomatik';
    final tutar = otomatik ? _acilisTutar : tlMinor(_deger['acilis']);
    setState(() => _mesgul = true);
    try {
      await _api.post('/api/v1/cash/sessions', {'cash_register_id': kasa, 'opening_float_minor': otomatik ? null : tutar});
      if (!mounted) return;
      context.bildir2('Kasa açıldı', 'Açılış: ${para(tutar)}');
      setState(() {
        _deger['acilis'] = '';
        _odak = 'nakit';
      });
      _mesgul = false;
      await _yukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Açılamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _giderEkle() async {
    final oturumId = _oturum?['id'];
    if (oturumId == null) return;
    var tur = _gecenTur;
    final aciklama = TextEditingController();
    final tutar = TextEditingController();
    await syPencere<void>(
      context,
      baslik: 'Gider Ekle',
      kapatDugmesi: true,
      govde: (ctx, yenile) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Etiket('Tür'),
        Secici<String>(
          deger: tur,
          secenekler: const [('expense', 'Masraf'), ('advance', 'Personel avansı'), ('cash_out', 'Nakit çıkış')],
          degisti: (v) => yenile(() => tur = v ?? 'expense'),
        ),
        const SizedBox(height: 10),
        _Etiket('Açıklama'),
        TextField(controller: aciklama, maxLength: 200, decoration: const InputDecoration(hintText: 'ör. Ekmek alımı', counterText: '')),
        const SizedBox(height: 10),
        _Etiket('Tutar (₺)'),
        TextField(controller: tutar, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '0,00')),
      ]),
      dip: (ctx, yenile) => [
        syDugme('Vazgeç', () => Navigator.pop(ctx)),
        syDugme('Kaydet', _mesgul
            ? null
            : () async {
                final m = tlMinor(tutar.text.trim());
                if (m <= 0) {
                  context.bildir2('Tutar geçersiz', 'Sıfırdan büyük bir tutar girin.', hata: true);
                  return;
                }
                if (aciklama.text.trim().isEmpty) {
                  context.bildir2('Açıklama gerekli', 'Giderin ne için olduğunu yazın.', hata: true);
                  return;
                }
                yenile(() => _mesgul = true);
                try {
                  await _api.post('/api/v1/cash/sessions/$oturumId/movements', {'type': tur, 'amount_minor': m, 'reason': aciklama.text.trim()});
                  _gecenTur = tur;
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) context.bildir2('Gider eklendi', para(m));
                  await _oturumYukle();
                } on ApiHata catch (e) {
                  if (mounted) context.bildir2('Eklenemedi', e.mesaj, hata: true);
                } finally {
                  _mesgul = false;
                  if (ctx.mounted) yenile(() {});
                }
              }, birincil: true),
      ],
    );
  }

  Future<void> _geriAl(Map<String, dynamic> h) async {
    final evet = await syPencere<bool>(
      context,
      baslik: 'Gider geri alınsın mı?',
      govde: (_, __) => Text(
        '“${(h['reason'] ?? '').toString().isEmpty ? 'Gider' : h['reason']}” · ${para(tamSayi(h['amount_minor']))} ters kayıtla geri alınır; orijinal kayıt silinmez, izi kalır.',
        style: TextStyle(fontSize: 14, color: Kabuk.ink),
      ),
      dip: (ctx, _) => [syDugme('Vazgeç', () => Navigator.pop(ctx, false)), syDugme('Geri al', () => Navigator.pop(ctx, true), birincil: true)],
    );
    if (evet != true || !mounted) return;
    try {
      await _api.post('/api/v1/cash/movements/${h['id']}/reverse', {'reason': 'Kasa kapanışı ekranından geri alındı'});
      if (mounted) context.bildir2('Gider geri alındı', '');
      await _oturumYukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Geri alınamadı', e.mesaj, hata: true);
    }
  }

  Future<void> _kapanisSor() async {
    final o = _oturum;
    if (o == null) return;
    final not = TextEditingController();
    final kart = _deger['kart']!;
    final mobil = _deger['mobil']!;
    Map<String, dynamic>? sonuc;
    await syPencere<void>(
      context,
      baslik: 'Kasa kapatılsın mı?',
      govde: (ctx, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak),
          child: Column(children: [
            _OzetSatiri('Nakit', para(_nakitMinor)),
            _OzetSatiri('Kredi kartı', kart.isEmpty ? 'sayılmadı' : para(tlMinor(kart))),
            _OzetSatiri('Mobil ödeme', mobil.isEmpty ? 'sayılmadı' : para(tlMinor(mobil))),
          ]),
        ),
        const SizedBox(height: 12),
        _Etiket('Not (isteğe bağlı)'),
        TextField(controller: not, maxLength: 500, maxLines: 3, minLines: 2, decoration: const InputDecoration(counterText: '')),
        if (_acikMasalar.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Açık masa var: ${_acikMasalar.length} masa.', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C))),
          ),
      ]),
      dip: (ctx, yenile) => [
        syDugme('Vazgeç', () => Navigator.pop(ctx)),
        syDugme('Kasayı kapat', _mesgul
            ? null
            : () async {
                yenile(() => _mesgul = true);
                try {
                  final r = await _api.post('/api/v1/cash/sessions/${o['id']}/close', {
                    'counted_cash_minor': _nakitMinor,
                    'counted_card_minor': kart.isEmpty ? null : tlMinor(kart),
                    'counted_mobile_minor': mobil.isEmpty ? null : tlMinor(mobil),
                    'banknotlar': [
                      for (final b in _banknotlar)
                        if ((int.tryParse(_adet[b]!) ?? 0) > 0) {'deger': b, 'adet': int.parse(_adet[b]!)},
                    ],
                    'closing_note': not.text.trim().isEmpty ? null : not.text.trim(),
                  });
                  sonuc = r is Map ? r.cast<String, dynamic>() : {};
                  if (ctx.mounted) Navigator.pop(ctx);
                } on ApiHata catch (e) {
                  if (mounted) context.bildir2('Kapatılamadı', e.mesaj, hata: true);
                } finally {
                  _mesgul = false;
                  if (ctx.mounted) yenile(() {});
                }
              }, birincil: true),
      ],
    );
    final s = sonuc;
    if (s == null || !mounted) return;
    final kartM = kart.isEmpty ? null : tlMinor(kart);
    final mobilM = mobil.isEmpty ? null : tlMinor(mobil);
    setState(() {
      _deger.updateAll((_, __) => '');
      _adet.updateAll((_, __) => '');
      _nakitAcik = false;
      _odak = 'nakit';
    });
    _yukle();
    _sonucGoster(s, kartM, mobilM);
  }

  void _sonucGoster(Map<String, dynamic> s, int? kart, int? mobil) {
    final ses = (s['session'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rapor = (s['report'] as Map?)?.cast<String, dynamic>() ?? const {};
    final yontem = _liste(rapor['by_method']);
    int net(Set<String> m) => yontem.where((y) => m.contains(y['method'])).fold(0, (t, y) => t + tamSayi(y['net_minor']));
    final bKart = net({'credit_card', 'debit_card'});
    final bMobil = net({'qr', 'online', 'transfer'});
    final satirlar = [
      ('Nakit', tamSayi(ses['counted_cash_minor']) as int?, tamSayi(ses['expected_cash_minor']), tamSayi(ses['difference_minor']) as int?),
      ('Kredi kartı', kart, bKart, kart == null ? null : kart - bKart),
      ('Mobil ödeme', mobil, bMobil, mobil == null ? null : mobil - bMobil),
    ];
    syPencere<void>(
      context,
      baslik: 'Kasa kapandı · Z#${ses['z_number'] ?? ''}',
      govde: (_, __) => Table(
        columnWidths: const {0: FlexColumnWidth(1.2)},
        border: TableBorder(horizontalInside: BorderSide(color: Kabuk.line), bottom: BorderSide(color: Kabuk.line)),
        children: [
          TableRow(children: [
            for (final b in ['', 'Sayılan', 'Beklenen', 'Fark'])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(b, textAlign: b.isEmpty ? TextAlign.left : TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
              ),
          ]),
          for (final (ad, sayilan, beklenen, fark) in satirlar)
            TableRow(children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(ad, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(sayilan == null ? '—' : para(sayilan), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14))),
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(para(beklenen), textAlign: TextAlign.right, style: const TextStyle(fontSize: 14))),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  fark == null ? 'sayılmadı' : (fark == 0 ? 'fark yok' : '${fark > 0 ? '+' : '−'}${para(fark.abs())}'),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: fark == null || fark == 0 ? FontWeight.w400 : FontWeight.w800,
                    color: fark == null || fark == 0 ? Kabuk.ink : (fark > 0 ? Kabuk.success : const Color(0xFFB91C1C)),
                  ),
                ),
              ),
            ]),
        ],
      ),
      dip: (ctx, _) => [
        syDugme('Z raporu', () {
          Navigator.pop(ctx);
          _zAc(tamSayi(ses['id']));
        }),
        syDugme('Tamam', () => Navigator.pop(ctx), birincil: true),
      ],
    );
  }

  void _zAc(int? id) {
    if (id == null || id == 0) {
      context.bildir2('Yazdır', 'Açık kasa oturumu yok.');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ZRaporuEkrani(oturumId: id)));
  }

  /* ── görünüm ── */

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final genis = mq.width > 900;
    final kisa = mq.height <= 640 && genis;
    final olcek = mq.width >= 3400 && mq.height >= 1900 ? 2.0 : (mq.width >= 2400 && mq.height >= 1300 ? 1.5 : (mq.width >= 1800 && mq.height >= 1000 ? 1.2 : 1.0));
    final o = _oturum;
    final uyari = o != null && _acikMasalar.isNotEmpty;

    final ust = Container(
      padding: EdgeInsets.symmetric(vertical: kisa ? 8 : 12),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Kabuk.line))),
      child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Kasa Kapanışı', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Kabuk.ink)),
        if (_kasalar.length > 1)
          SizedBox(
            height: 36,
            child: DropdownButton<int>(
              value: _kasaId,
              underline: const SizedBox(),
              items: [
                for (final k in _kasalar)
                  DropdownMenuItem(value: tamSayi(k['id']), child: Text('${k['name']}${k['open_session'] != null ? ' · açık' : ''}', style: const TextStyle(fontSize: 13.5))),
              ],
              onChanged: (v) {
                setState(() => _kasaId = v);
                _oturumYukle();
              },
            ),
          ),
        if (o != null)
          Text('Z#${o['z_number']} · ${o['opened_by'] ?? '—'} · ${kisaTarihSaat(o['opened_at']?.toString())}\'de açıldı',
              style: TextStyle(fontSize: 12.5, color: Kabuk.soft)),
      ]),
    );

    final yazdir = syDugme('Yazdır', () => _zAc(o == null ? null : tamSayi(o['id'])), ikon: Icons.print_outlined, yukseklik: 36);

    Widget icerik;
    if (_yukleniyor) {
      icerik = Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        child: Text('Yükleniyor…', style: TextStyle(color: Kabuk.soft)),
      );
    } else {
      final sol = _sol();
      final sag = _sag(mq.height, kisa);
      final uyariW = uyari ? _uyari(genis) : null;
      icerik = genis
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 100, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [if (uyariW != null) ...[uyariW, const SizedBox(height: 18)], sol])),
              const SizedBox(width: 18),
              Expanded(flex: 105, child: sag),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (uyariW != null) ...[uyariW, const SizedBox(height: 14)],
              sag,
              const SizedBox(height: 14),
              sol,
            ]);
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(olcek)),
      child: ColoredBox(
        color: Renk.yuzey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: ust), const SizedBox(width: 12), yazdir]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, kisa ? 10 : 14, 16, 24),
              child: icerik,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _uyari(bool genis) => Container(
        padding: genis ? const EdgeInsets.all(14) : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: koseYuvarlak),
        child: Column(children: [
          Text('Açık Masa Uyarısı', style: TextStyle(fontSize: genis ? 18 : 15, fontWeight: FontWeight.w800, color: const Color(0xFFB91C1C))),
          const SizedBox(height: 4),
          const Text('Açık masalarınız bulunmaktadır. Bu durum raporlarınızı etkileyebilir. Lütfen dikkat edin.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Color(0xFFB91C1C))),
          const SizedBox(height: 2),
          Text('(${_acikMasalar.join(', ')})', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB91C1C))),
        ]),
      );

  Widget _sol() {
    final g = _giderler;
    final toplam = g.fold<int>(0, (t, h) => t + tamSayi(h['amount_minor']));
    final baslik = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Kabuk.soft, letterSpacing: .6);
    Widget hucre(Widget c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: c);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(children: [
          if (_oturum != null && _yonetebilir) syDugme('Gider Ekle', _giderEkle, birincil: true, ikon: Icons.add_rounded, yukseklik: 40),
          const Spacer(),
          if (g.isNotEmpty)
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Toplam gider: '),
              TextSpan(text: para(toplam), style: TextStyle(color: Kabuk.negative, fontWeight: FontWeight.w700)),
            ]), style: TextStyle(fontSize: 13, color: Kabuk.soft)),
        ]),
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 520),
            child: IntrinsicWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: Kabuk.sunken,
                  child: Row(children: [
                    Expanded(flex: 3, child: hucre(Text('AÇIKLAMA', style: baslik))),
                    Expanded(flex: 2, child: hucre(Text('TUTAR', style: baslik))),
                    Expanded(flex: 2, child: hucre(Text('OLUŞTURAN', style: baslik))),
                    Expanded(flex: 2, child: hucre(Text('ZAMAN', style: baslik))),
                    Expanded(flex: 2, child: hucre(Text('İŞLEM', style: baslik))),
                  ]),
                ),
                if (g.isEmpty)
                  Container(
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
                    padding: const EdgeInsets.all(22),
                    child: Text(_oturum != null ? 'Bu kasa oturumunda gider yok.' : 'Kasa kapalı.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: Kabuk.soft)),
                  )
                else
                  for (final h in g)
                    Container(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Kabuk.line))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Expanded(
                          flex: 3,
                          child: hucre(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${(h['reason'] ?? '').toString().isEmpty ? '—' : h['reason']}', style: const TextStyle(fontSize: 13.5)),
                            if (h['type'] != 'expense')
                              Text(h['type'] == 'advance' ? 'Avans' : (h['type'] == 'cash_out' ? 'Nakit çıkış' : '${h['type_label'] ?? ''}'),
                                  style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
                          ])),
                        ),
                        Expanded(flex: 2, child: hucre(Text(para(tamSayi(h['amount_minor'])), softWrap: false, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.negative)))),
                        Expanded(flex: 2, child: hucre(Text('${h['user'] ?? '—'}', style: const TextStyle(fontSize: 13.5)))),
                        Expanded(flex: 2, child: hucre(Text(kisaTarihSaat(h['created_at']?.toString()), style: const TextStyle(fontSize: 13.5)))),
                        Expanded(
                          flex: 2,
                          child: hucre(_yonetebilir
                              ? InkWell(
                                  onTap: () => _geriAl(h),
                                  child: Text('Geri al', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Kabuk.negative)),
                                )
                              : const SizedBox()),
                        ),
                      ]),
                    ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _alan(String etiket, String deger, {String? anahtar, bool sabit = false, double yukseklik = 48, VoidCallback? bas}) {
    final ac = anahtar != null && _odak == anahtar;
    return Material(
      color: sabit ? Kabuk.sunken : Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: ac ? Kabuk.brand : Kabuk.line, width: ac ? 2 : 1)),
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: sabit ? null : (bas ?? () => setState(() => _odak = anahtar!)),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: yukseklik),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Text(etiket, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Kabuk.soft)),
              const Spacer(),
              Text(deger, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Kabuk.ink, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sag(double h, bool kisa) {
    final aralik = (h * .012).clamp(6.0, 12.0);
    final alanH = (h * .054).clamp(38.0, 56.0);
    final tusH = (h * .062).clamp(40.0, 72.0);
    final butonH = (h * .06).clamp(42.0, 64.0);
    final o = _oturum;
    final otomatik = _acilisModu == 'otomatik';
    final ipucu = TextStyle(fontSize: 13, color: Kabuk.soft);

    final ogeler = <Widget>[];
    if (o == null && otomatik) {
      ogeler.add(_alan('Açılış tutarı (otomatik):', para(_acilisTutar), sabit: true, yukseklik: alanH));
      ogeler.add(Text('Kasa, işletme yönetiminde belirlenen açılış tutarıyla açılır.', style: ipucu));
    } else if (o == null) {
      ogeler.add(_alan('Açılış tutarı:', _deger['acilis']!.isEmpty ? '₺' : _goster(_deger['acilis']!), anahtar: 'acilis', yukseklik: alanH));
      ogeler.add(Text('Kasa kapalı. Açılış tutarını girip kasayı açın.', style: ipucu));
    } else {
      ogeler.add(_alan('Açılış tutarı:', para(tamSayi(o['opening_float_minor'])), sabit: true, yukseklik: alanH));
      final nakitAlan = _alan(
        'Nakit tutar:',
        _banknotVar ? para(_banknotToplam) : (_deger['nakit']!.isEmpty ? '0 ₺' : _goster(_deger['nakit']!)),
        anahtar: 'nakit',
        yukseklik: alanH,
        bas: () => setState(() {
          _odak = 'nakit';
          _nakitAcik = true;
        }),
      );
      ogeler.add(_nakitAcik
          ? Container(
              decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.brand)),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [nakitAlan, _banknotIzgarasi()]),
            )
          : nakitAlan);
      ogeler.add(_alan('Kredi kartı tutarı:', _deger['kart']!.isEmpty ? '₺' : _goster(_deger['kart']!), anahtar: 'kart', yukseklik: alanH));
      ogeler.add(_alan('Mobil ödeme tutarı:', _deger['mobil']!.isEmpty ? '₺' : _goster(_deger['mobil']!), anahtar: 'mobil', yukseklik: alanH));
    }

    if (o != null || !otomatik) ogeler.add(_tusTakimi(tusH, kisa));

    final etkin = !_mesgul && _yonetebilir;
    ogeler.add(SizedBox(
      height: butonH,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Kabuk.brand,
          disabledBackgroundColor: Kabuk.brand.withOpacity(.5),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        onPressed: etkin ? (o == null ? _kasaAc : _kapanisSor) : null,
        child: Text(o == null ? 'Kasayı Aç' : 'Kasa Kapanışı'),
      ),
    ));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < ogeler.length; i++) ...[if (i > 0) SizedBox(height: aralik), ogeler[i]],
    ]);
  }

  Widget _banknotIzgarasi() {
    final satirlar = <Widget>[];
    for (var i = 0; i < _banknotlar.length; i += 2) {
      satirlar.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _banknotHucresi(_banknotlar[i], sag: true)),
          Expanded(child: i + 1 < _banknotlar.length ? _banknotHucresi(_banknotlar[i + 1]) : const SizedBox()),
        ]),
      ));
    }
    return Column(children: satirlar);
  }

  Widget _banknotHucresi(int b, {bool sag = false}) {
    final secili = _odak == 'b$b';
    final adet = int.tryParse(_adet[b]!) ?? 0;
    return InkWell(
      onTap: () => setState(() => _odak = 'b$b'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: secili ? Kabuk.sunken : null,
          border: Border(
            top: BorderSide(color: Kabuk.line),
            right: sag ? BorderSide(color: Kabuk.line) : BorderSide.none,
            left: secili ? BorderSide(color: Kabuk.brand, width: 3) : BorderSide.none,
          ),
        ),
        child: Row(children: [
          Expanded(child: Text('$b ₺', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
          Expanded(child: Text('$adet adet', style: TextStyle(fontSize: 13.5, color: Kabuk.soft))),
          Expanded(child: Text(para(b * adet * 100), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13.5))),
        ]),
      ),
    );
  }

  Widget _tusTakimi(double tusH, bool kisa) {
    final bosluk = kisa ? 4.0 : 6.0;
    const tuslar = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '.', 'sil'];
    final satirlar = <Widget>[];
    for (var i = 0; i < tuslar.length; i += 3) {
      satirlar.add(Row(children: [
        for (var j = i; j < i + 3; j++) ...[
          if (j > i) SizedBox(width: bosluk),
          Expanded(
            child: SizedBox(
              height: tusH,
              child: Material(
                color: Renk.yuzey,
                shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Kabuk.line)),
                child: InkWell(
                  borderRadius: koseYuvarlak,
                  onTap: () => _tus(tuslar[j]),
                  child: Center(
                    child: Text(
                      tuslar[j] == 'sil' ? 'Sil' : tuslar[j],
                      style: TextStyle(
                        fontSize: tuslar[j] == 'sil' ? 15 : 18,
                        fontWeight: FontWeight.w700,
                        color: tuslar[j] == 'sil' ? Kabuk.negative : Kabuk.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]));
    }
    return Container(
      padding: EdgeInsets.all(bosluk),
      decoration: BoxDecoration(color: Kabuk.sunken, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      child: Column(children: [for (var i = 0; i < satirlar.length; i++) ...[if (i > 0) SizedBox(height: bosluk), satirlar[i]]]),
    );
  }
}

class _Etiket extends StatelessWidget {
  const _Etiket(this.metin);
  final String metin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(metin, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Kabuk.soft)),
      );
}

class _OzetSatiri extends StatelessWidget {
  const _OzetSatiri(this.etiket, this.deger);
  final String etiket;
  final String deger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(etiket, style: TextStyle(fontSize: 14, color: Kabuk.soft))),
          Text(deger, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Kabuk.ink)),
        ]),
      );
}

/* ═════════════ Z / X raporu (ZReport.vue) ═════════════ */

class ZRaporuEkrani extends StatefulWidget {
  const ZRaporuEkrani({super.key, required this.oturumId});
  final int oturumId;

  @override
  State<ZRaporuEkrani> createState() => _ZRaporuEkraniState();
}

class _ZRaporuEkraniState extends State<ZRaporuEkrani> {
  Map<String, dynamic>? _ses;
  Map<String, dynamic>? _rapor;
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await context.api.get('/api/v1/cash/sessions/${widget.oturumId}/report');
      if (!mounted || r is! Map) return;
      setState(() {
        _ses = (r['session'] as Map?)?.cast<String, dynamic>();
        _rapor = (r['report'] as Map?)?.cast<String, dynamic>();
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Rapor yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  String _isaretli(int m) => '${m > 0 ? '+' : (m < 0 ? '−' : '')}${para(m.abs())}';

  @override
  Widget build(BuildContext context) {
    final s = _ses;
    final r = _rapor;
    return Scaffold(
      backgroundColor: Kabuk.sunken,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Z Raporu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        leading: const BackButton(),
        shape: Border(bottom: BorderSide(color: Kabuk.line)),
      ),
      body: _yukleniyor
          ? Center(child: Text('Yükleniyor…', style: TextStyle(color: Kabuk.soft)))
          : (s == null || r == null)
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.inbox_outlined, size: 32, color: Kabuk.soft),
                    SizedBox(height: 6),
                    Text('Rapor bulunamadı', style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 672), child: _kart(s, r))),
                ),
    );
  }

  Widget _kart(Map<String, dynamic> s, Map<String, dynamic> r) {
    final kapali = s['status'] == 'closed';
    final sayim = r['sayim'] is Map ? (r['sayim'] as Map).cast<String, dynamic>() : null;
    final yontem = (r['by_method'] as List? ?? const []).whereType<Map>().toList();
    final hareket = (r['movements'] as List? ?? const []).whereType<Map>().toList();
    final fark = tamSayi(r['difference_minor'] ?? s['difference_minor']);

    Widget bolum(String b) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(b, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Kabuk.soft, letterSpacing: .6)),
        );
    Widget satir(String e, String d, {bool kalin = false, Color? renk}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(e, style: TextStyle(fontSize: 13.5, fontWeight: kalin ? FontWeight.w700 : FontWeight.w400))),
            Text(d, style: TextStyle(fontSize: 13.5, fontWeight: kalin ? FontWeight.w800 : FontWeight.w500, color: renk ?? Kabuk.ink)),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Kabuk.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${kapali ? 'Z RAPORU' : 'X RAPORU (ara — oturum açık)'} · #${s['z_number'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('${s['register_name'] ?? 'Kasa'}', style: TextStyle(fontSize: 13, color: Kabuk.soft)),
            ]),
          ),
          Rozet(kapali ? 'Kapalı (dondurulmuş)' : 'Açık (canlı)',
              renk: kapali ? Renk.ikinci : Renk.uyari, zemin: kapali ? Renk.ic : Renk.uyariZemin, kenar: kapali ? Renk.cizgi : Renk.uyariKenar),
        ]),
        const SizedBox(height: 10),
        satir('Açılış', '${tamTarihSaat(s['opened_at']?.toString())} · ${s['opened_by'] ?? '—'}'),
        satir('Kapanış', '${s['closed_at'] == null ? '—' : tamTarihSaat(s['closed_at']?.toString())} · ${s['closed_by'] ?? '—'}'),
        bolum('NAKİT MUTABAKATI'),
        satir('Açılış kasası', para(tamSayi(r['opening_float_minor']))),
        satir('Beklenen nakit', para(tamSayi(r['expected_cash_minor']))),
        satir('Sayılan nakit', r['counted_cash_minor'] == null ? '—' : para(tamSayi(r['counted_cash_minor']))),
        satir('Fark (sayılan − beklenen)', _isaretli(fark), kalin: true, renk: fark == 0 ? Kabuk.success : Kabuk.negative),
        if (sayim != null) ...[
          satir('Kredi kartı (sayılan / beklenen)',
              '${sayim['kart_minor'] == null ? 'sayılmadı' : para(tamSayi(sayim['kart_minor']))} / ${para(tamSayi(sayim['beklenen_kart_minor']))}'),
          if (sayim['kart_fark_minor'] != null) satir('Kart farkı', _isaretli(tamSayi(sayim['kart_fark_minor']))),
          satir('Mobil ödeme (sayılan / beklenen)',
              '${sayim['mobil_minor'] == null ? 'sayılmadı' : para(tamSayi(sayim['mobil_minor']))} / ${para(tamSayi(sayim['beklenen_mobil_minor']))}'),
          if (sayim['mobil_fark_minor'] != null) satir('Mobil farkı', _isaretli(tamSayi(sayim['mobil_fark_minor']))),
          for (final b in (sayim['banknotlar'] as List? ?? const []).whereType<Map>())
            satir('${b['deger']} ₺ × ${b['adet']}', para(tamSayi(b['deger']) * tamSayi(b['adet']) * 100)),
        ],
        if ((s['closing_note'] ?? '').toString().isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('Not: ${s['closing_note']}', style: TextStyle(fontSize: 13, color: Kabuk.soft))),
        bolum('ÖDEME YÖNTEMİ KIRILIMI'),
        if (yontem.isEmpty)
          Text('Bu oturumda ödeme yok', style: TextStyle(fontSize: 13, color: Kabuk.soft))
        else
          Table(
            columnWidths: const {0: FlexColumnWidth(1.6)},
            border: TableBorder(horizontalInside: BorderSide(color: Kabuk.line)),
            children: [
              TableRow(children: [
                for (final b in ['Yöntem', 'Adet', 'Tahsilat', 'İade', 'Net'])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text(b, textAlign: b == 'Yöntem' ? TextAlign.left : TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Kabuk.soft)),
                  ),
              ]),
              for (final y in yontem)
                TableRow(children: [
                  _td('${y['label'] ?? y['method']}', sol: true),
                  _td('${tamSayi(y['count'])}'),
                  _td(para(tamSayi(y['collected_minor']))),
                  _td(tamSayi(y['refunded_minor']) > 0 ? '−${para(tamSayi(y['refunded_minor']))}' : '—'),
                  _td(para(tamSayi(y['net_minor'])), kalin: true),
                ]),
            ],
          ),
        bolum('TOPLAMLAR'),
        satir('Tahsilat (${tamSayi(r['payments_count'])})', para(tamSayi(r['payments_total_minor']))),
        satir('İade (${tamSayi(r['refunds_count'])})', tamSayi(r['refunds_total_minor']) > 0 ? '−${para(tamSayi(r['refunds_total_minor']))}' : '0,00'),
        satir('İptal/void (${tamSayi(r['voids_count'])})', para(tamSayi(r['voids_total_minor']))),
        satir('Bahşiş', para(tamSayi(r['tips_total_minor']))),
        satir('İndirim', para(tamSayi(r['discounts_total_minor']))),
        satir('İkram', para(tamSayi(r['comps_total_minor']))),
        satir('Servis bedeli', para(tamSayi(r['service_charges_total_minor']))),
        bolum('KASA HAREKETLERİ'),
        for (final h in hareket)
          satir('${h['label']} (${tamSayi(h['count'])})', '${h['direction'] == 'in' ? '+' : '−'}${para(tamSayi(h['total_minor']))}'),
      ]),
    );
  }

  Widget _td(String m, {bool sol = false, bool kalin = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(m, textAlign: sol ? TextAlign.left : TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: kalin ? FontWeight.w700 : FontWeight.w400)),
      );
}
