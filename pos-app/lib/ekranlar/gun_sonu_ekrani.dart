import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'cerceve.dart';
import 'kasa_kapanisi.dart' show syDugme, syPencere;
import 'ortak.dart';

/// GÜN SONU — web /panel/gun-sonu (EndOfDay.vue + tabs/EodTab.vue) birebiri.
/// Şartname: /root/work/spec/gun-sonu.md. Gün takvimle değil kasa
/// kapanışıyla biter; rakamların hepsi sunucuda hesaplanır.

/// formatCurrencyMinor: "₺1.234,56".
String _tl(int m) => '${m < 0 ? '-' : ''}₺${para(m.abs(), simge: false)}';

/// Pay (sunucu 0–100 verir) → "%26,20" — Raporlar › Özet biçimi.
String _pay(num v) => '%${v.toDouble().toStringAsFixed(2).replaceAll('.', ',')}';

const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

/// "9 Ekim 2026 Cuma".
String _gunEtiketi(String? g) {
  if (g == null || g.length < 10) return g ?? '';
  final p = g.substring(0, 10).split('-').map(int.tryParse).toList();
  if (p.any((x) => x == null)) return g;
  final t = DateTime(p[0]!, p[1]!, p[2]!, 12);
  return '${t.day} ${_aylar[t.month - 1]} ${t.year} ${_gunler[t.weekday - 1]}';
}

const _tabular = [FontFeature.tabularFigures()];

class GunSonuEkrani extends StatefulWidget {
  const GunSonuEkrani({super.key, this.gomulu = false});

  /// Raporlar sayfasının içinde (sekme): dış boşluk yok, başlık "Kapanış dönemi".
  final bool gomulu;

  @override
  State<GunSonuEkrani> createState() => _GunSonuEkraniState();
}

class _GunSonuEkraniState extends State<GunSonuEkrani> {
  late final Api _api = context.api;

  Map<String, dynamic>? _durum;
  List<Map<String, dynamic>> _yazicilar = const [];
  int? _yazici;
  String _secim = 'acik';

  Map<String, dynamic>? _s;
  List<Map<String, dynamic>> _saatler = const [];
  List<Map<String, dynamic>> _tahsilatlar = const [];
  String? _hata;
  int _istekNo = 0;
  bool _basiliyor = false;
  int _gunSaati = 6;

  @override
  void initState() {
    super.initState();
    _yaziciYukle();
    _durumYukle().then((_) => _raporYukle());
  }

  List<Map<String, dynamic>> _liste(Object? v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  Map<String, dynamic> _harita(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  Future<void> _yaziciYukle() async {
    try {
      final r = await _api.get('/api/v1/print/targets');
      final y = _liste(r is Map ? r['printers'] : null);
      final v = r is Map ? _harita(r['defaults'])['cashier'] : null;
      if (mounted) {
        setState(() {
          _yazicilar = y;
          _yazici = v != null ? tamSayi(v) : (y.isNotEmpty ? tamSayi(y.first['id']) : null);
        });
      }
    } on ApiHata {
      // sessiz
    }
  }

  Future<void> _durumYukle() async {
    try {
      final r = await _api.get('/api/v1/reports/eod/durum');
      if (!mounted || r is! Map) return;
      setState(() {
        _durum = r.cast<String, dynamic>();
        _gunSaati = tamSayi(_durum!['gun_baslangic_saati'], 6);
        if (!_secimGecerli()) _secim = 'acik';
      });
    } on ApiHata {
      if (mounted) setState(() => _durum = null);
    }
  }

  List<Map<String, dynamic>> get _gecmis => _liste(_durum?['gecmis']);
  List<Map<String, dynamic>> get _isGunleri => _liste(_durum?['is_gunleri']);

  bool _secimGecerli() {
    if (_secim == 'acik') return true;
    if (_secim.startsWith('gun:')) return _isGunleri.any((g) => g['is_gunu'] == _secim.substring(4));
    if (_secim.startsWith('k:')) return _gecmis.any((k) => '${k['id']}' == _secim.substring(2));
    return false;
  }

  Map<String, dynamic>? get _seciliGun => _secim.startsWith('gun:') ? _isGunleri.where((g) => g['is_gunu'] == _secim.substring(4)).firstOrNull : null;
  Map<String, dynamic>? get _seciliKapanis => _secim.startsWith('k:') ? _gecmis.where((k) => '${k['id']}' == _secim.substring(2)).firstOrNull : null;

  List<Map<String, dynamic>> _gununKapanislari(Map<String, dynamic> g) {
    final idler = (g['kapanis_idleri'] as List? ?? const []).map((e) => tamSayi(e)).toSet();
    final ks = _gecmis.where((k) => idler.contains(tamSayi(k['id'])) || k['is_gunu'] == g['is_gunu']).toList();
    ks.sort((a, b) => '${a['bitis_iso']}'.compareTo('${b['bitis_iso']}'));
    return ks;
  }

  Map<String, dynamic> get _filtre {
    String gun(Object? iso) {
      final s = '${iso ?? ''}';
      return s.length >= 10 ? s.substring(0, 10) : s;
    }

    final g = _seciliGun ?? _seciliKapanis;
    if (g != null) {
      return {'from': gun(g['baslangic_iso']), 'to': gun(g['bitis_iso']), 'window_from': g['baslangic_iso'], 'window_to': g['bitis_iso']};
    }
    final a = _harita(_durum?['aralik']);
    final bugun = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    return {
      'from': a['baslangic_iso'] != null ? gun(a['baslangic_iso']) : bugun,
      'to': a['bitis_iso'] != null ? gun(a['bitis_iso']) : bugun,
      if (a['baslangic_iso'] != null) 'window_from': a['baslangic_iso'],
    };
  }

  Future<void> _raporYukle() async {
    final no = ++_istekNo;
    final f = _filtre;
    setState(() => _hata = null);
    Future<dynamic> al(String k) => _api.get('/api/v1/reports/$k', sorgu: f);
    try {
      final r = await al('ops-eod');
      if (!mounted || no != _istekNo) return;
      setState(() => _s = _harita(r is Map ? r['data'] : null));
    } on ApiHata catch (e) {
      if (mounted && no == _istekNo) setState(() => _hata = e.mesaj.isEmpty ? 'Rapor yüklenemedi.' : e.mesaj);
    }
    try {
      final r = await al('sales-hourly');
      if (mounted && no == _istekNo) setState(() => _saatler = _liste(_harita(r is Map ? r['data'] : null)['hours']));
    } on ApiHata {
      // sessiz
    }
    try {
      final r = await al('receivables-collections');
      if (mounted && no == _istekNo) setState(() => _tahsilatlar = _liste(_harita(r is Map ? r['data'] : null)['rows']));
    } on ApiHata {
      // sessiz
    }
  }

  void _secimDegis(String s) {
    setState(() => _secim = s);
    _raporYukle();
  }

  /* ── eylemler ── */

  Future<void> _raporuBas(bool kapat, [int? kapanisId]) async {
    if (_basiliyor) return;
    setState(() => _basiliyor = true);
    try {
      final r = await _api.post('/api/v1/reports/eod/print', {'printer_id': _yazici, 'kapat': kapat, 'kapanis_id': kapanisId});
      if (!mounted) return;
      final m = r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
      if (m['bos_gun'] == true) {
        context.bildir2('Gün sonu zaten alınmış',
            'O andan beri hareket yok; son gün sonu raporu tekrar basıldı (${m['aralik'] ?? ''}). Gün kapatılmadı, kasa açık kaldı.');
      } else {
        context.bildir2(m['kapatildi'] == true ? 'Gün kapatıldı, rapor gönderildi' : 'Rapor gönderildi (gün açık)', '${m['aralik'] ?? ''} · ${m['printer'] ?? ''}');
      }
      await _durumYukle();
      await _raporYukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2(e.kod == 422 ? 'Yazıcı yok' : 'Basılamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _basiliyor = false);
    }
  }

  Future<void> _kapanisSor() async {
    final d = _durum ?? const {};
    final aralik = _harita(d['aralik'])['etiket']?.toString() ?? 'şu an';
    final acik = tamSayi(d['acik_adisyon']);
    final kasa = tamSayi(d['acik_kasa_oturumu']);
    final ilkSaat = context.durum.oturum!.yetki('settings.manage') && d['son_kapanis'] == null;
    var saat = _gunSaati;
    String? sonuc;
    await syPencere<void>(
      context,
      baslik: 'Kasa kapandı mı?',
      genislik: 384,
      govde: (ctx, yenile) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Rapor '),
          TextSpan(text: aralik, style: const TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' aralığını kapsar. '),
          const TextSpan(text: 'Evet', style: TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' derseniz kasa TAM O ANDA kapanır: bu pencere donar, yeni gün o saniyeden başlar. Bundan sonraki satışlar yeni güne yazılır.'),
        ]), style: TextStyle(fontSize: 13.5, color: Renk.ikinci)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          child: Column(children: [
            _iki('Açık adisyon', Text.rich(TextSpan(children: [
              TextSpan(text: '$acik', style: TextStyle(fontWeight: FontWeight.w700, color: acik > 0 ? Kabuk.warning : Kabuk.success)),
              if (acik > 0) TextSpan(text: ' · ${_tl(tamSayi(d['acik_adisyon_kalan_minor']))} tahsil edilmedi'),
            ]))),
            const SizedBox(height: 4),
            _iki('Açık kasa oturumu', Text('$kasa', style: TextStyle(fontWeight: FontWeight.w700, color: kasa > 0 ? Kabuk.warning : Kabuk.success))),
          ]),
        ),
        if (d['kapanisa_hazir'] == false) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Renk.uyari),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gün hâlâ sürüyor gibi görünüyor: açık adisyon/kasa var. Günü kapatırsanız bu adisyonlar KAPANMAZ, tahsilatları yeni güne yazılır. Emin değilseniz "Sadece ara rapor" alın — gün açık kalır.',
                  style: TextStyle(fontSize: 12.5, color: Renk.uyari),
                ),
              ),
            ]),
          ),
        ],
        if (ilkSaat) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('İlk günün başlangıç saati', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Henüz kapanış kaydı yok. İlk rapora kadar günün nereden başlayacağını bu saat belirler (06:00 seçilirse gece 05:00\'teki satış hâlâ dünkü güne yazılır). İlk kapanıştan sonra gün her zaman son kapanıştan başlar.',
                style: TextStyle(fontSize: 12, color: Renk.ikinci),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Secici<int>(
                    deger: saat,
                    secenekler: [for (var h = 0; h <= 11; h++) (h, h == 0 ? '00:00 (gece yarısı)' : '${h.toString().padLeft(2, '0')}:00')],
                    degisti: (v) => yenile(() => saat = v ?? 0),
                  ),
                ),
                const SizedBox(width: 8),
                syDugme('Kaydet', () async {
                  try {
                    await _api.post('/api/v1/reports/eod/gun-saati', {'gun_baslangic_saati': saat});
                    if (!mounted) return;
                    context.bildir2('İş günü başlangıcı kaydedildi', saat == 0 ? 'Gün gece yarısı döner.' : 'Gün her gün ${saat.toString().padLeft(2, '0')}:00\'da döner.');
                    await _durumYukle();
                    _raporYukle();
                  } on ApiHata catch (e) {
                    if (mounted) context.bildir2('Kaydedilemedi', e.mesaj, hata: true);
                  }
                }, yukseklik: 34),
              ]),
            ]),
          ),
        ],
      ]),
      dip: (ctx, _) => [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
        syDugme('Sadece ara rapor', () {
          sonuc = 'ara';
          Navigator.pop(ctx);
        }),
        syDugme('Evet, kasa kapandı', () {
          sonuc = 'kapat';
          Navigator.pop(ctx);
        }, birincil: true, ikon: Icons.print_outlined),
      ],
    );
    if (sonuc != null) _raporuBas(sonuc == 'kapat');
  }

  Future<void> _onizleme() async {
    Map<String, dynamic>? veri;
    var yukleniyor = true;
    final kapanisId = _seciliKapanis == null ? null : tamSayi(_seciliKapanis!['id']);
    Future<void> cek(StateSetter yenile) async {
      yenile(() => yukleniyor = true);
      try {
        final r = await _api.post('/api/v1/reports/eod/onizleme', {'kapanis_id': kapanisId});
        veri = r is Map ? r.cast<String, dynamic>() : null;
      } on ApiHata catch (e) {
        if (mounted) context.bildir2('Önizleme alınamadı', e.mesaj, hata: true);
      }
      yenile(() => yukleniyor = false);
    }

    var basladi = false;
    await syPencere<void>(
      context,
      baslik: 'Gün sonu fişi — önizleme',
      genislik: 672,
      govde: (ctx, yenile) {
        if (!basladi) {
          basladi = true;
          cek(yenile);
        }
        if (yukleniyor) return Text('Hazırlanıyor…', style: TextStyle(color: Renk.soluk));
        final v = veri;
        final fis = v == null ? null : _harita(v['fis']);
        if (fis == null || fis.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bar_chart_rounded, size: 30, color: Renk.soluk),
              Text('Önizleme yok', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('Rapor içeriği alınamadı.', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
            ]),
          );
        }
        final buyuk = MediaQuery.sizeOf(ctx).width >= 640;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            '${v!['aralik'] ?? ''} · ${tamSayi(v['satir_sayisi'])} satır${v['kapanmis'] == true ? ' · kapanmış dönem (donmuş rakamlar)' : ' · açık gün (rakamlar akmaya devam ediyor)'}',
            style: TextStyle(fontSize: 12, color: Renk.soluk),
          ),
          const SizedBox(height: 8),
          Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .65),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(_fisMetni(fis), style: TextStyle(fontFamily: 'monospace', fontSize: buyuk ? 11 : 9, height: 1.35, color: Renk.yazi)),
              ),
            ),
          ),
        ]);
      },
      dip: (ctx, yenile) => [
        syDugme('Kapat', () => Navigator.pop(ctx)),
        syDugme('Yenile', () => cek(yenile), birincil: true, ikon: Icons.refresh_rounded),
      ],
    );
  }

  /// 48 sütunluk termal fiş metni (EodTab fisMetni birebiri).
  String _fisMetni(Map<String, dynamic> f) {
    const g = 48;
    final out = <String>[];
    for (final k in ['business', 'branch', 'title', 'time']) {
      final v = '${f[k] ?? ''}'.trim();
      if (v.isNotEmpty) out.add(v);
    }
    out.add('');
    String ortala(String s) {
      final bos = (g - s.length).clamp(0, g);
      return '${' ' * (bos ~/ 2)}$s';
    }

    for (final l in _liste(f['lines'])) {
      if (l['rule'] == true) {
        out.add('-' * g);
      } else if (l['section'] != null) {
        out.add('');
        final b = ' ${'${l['section']}'.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase()} ';
        final kalan = (g - b.length).clamp(0, g);
        out.add('${'=' * (kalan ~/ 2)}$b${'=' * (kalan - kalan ~/ 2)}');
      } else if (l['center'] != null) {
        var satir = '';
        for (final s in '${l['center']}'.split(RegExp(r'\s+'))) {
          if (satir.isEmpty) {
            satir = s;
          } else if (satir.length + 1 + s.length <= 46) {
            satir = '$satir $s';
          } else {
            out.add(ortala(satir));
            satir = s;
          }
        }
        if (satir.isNotEmpty) out.add(ortala(satir));
      } else {
        final ad = '${l['name'] ?? ''}';
        final tutar = '${l['amount'] ?? ''}';
        if (ad.length + tutar.length + 1 > g) {
          out.add(ad);
          out.add(tutar.padLeft(g));
        } else {
          out.add('$ad${' ' * (g - ad.length - tutar.length)}$tutar');
        }
      }
    }
    out.add('');
    for (final s in (f['footer'] as List? ?? const [])) {
      out.add('$s');
    }
    return out.join('\n');
  }

  Future<void> _disaAktar(String rapor) async {
    final b = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 200, 200, 0),
      items: const [
        PopupMenuItem(value: 'csv', child: Text('CSV')),
        PopupMenuItem(value: 'xlsx', child: Text('Excel (XLSX)')),
        PopupMenuItem(value: 'pdf', child: Text('PDF')),
      ],
    );
    if (b == null || !mounted) return;
    final f = _filtre;
    final sorgu = f.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}').join('&');
    try {
      await _api.post('/api/v1/reports/exports?$sorgu', {'report': rapor, 'format': b});
      if (mounted) context.bildir2('Dışa aktarma kuyruğa alındı', 'Hazır olunca "Dışa Aktarımlar" sekmesinden indirebilirsiniz.');
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Dışa aktarılamadı', e.mesaj, hata: true);
    }
  }

  /* ── görünüm ──
     RAPORLAR DİLİ (web rapor-dili.css, 2026-10-28): tek sayfa kartı →
     başlık satırı (ad + dönem listesi | düğmeler) → dönem bilgisi → rakam
     kutuları → tablolar (tek kap; genişte yan yana). İşleyiş aynı. */

  @override
  Widget build(BuildContext context) {
    final ekran = MediaQuery.sizeOf(context).width;
    final dis = widget.gomulu
        ? const EdgeInsets.only(bottom: 12)
        : (ekran >= 1024 ? const EdgeInsets.fromLTRB(16, 12, 16, 16) : const EdgeInsets.fromLTRB(12, 8, 12, 12));
    return ColoredBox(
      color: Renk.ic,
      child: LayoutBuilder(builder: (context, k) {
        final w = k.maxWidth.isFinite ? k.maxWidth : ekran;
        final genis = w >= 900;
        final kartIc = genis ? const EdgeInsets.fromLTRB(18, 16, 18, 18) : const EdgeInsets.all(12);
        final ic = w - dis.horizontal - kartIc.horizontal - 2;
        final s = _s;
        final bos = s != null && tamSayi(s['orders']) == 0 && tamSayi(s['orders_opened']) == 0;
        final dokum = s != null && s['collection_breakdown'] is Map ? _harita(s['collection_breakdown']) : null;
        final bolumler = <Widget>[
          _baslikSatiri(ic),
          if (_durum != null) _donemBilgisi(),
          if (_hata != null) Text(_hata!, style: TextStyle(color: Renk.hata, fontSize: 13)),
          if (bos)
            _kap([
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(children: [
                  const Text('Bu dönemde hareket yok', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Adisyon açıldıkça gün sonu özeti (ciro, tahsilat, kasadaki nakit) burada oluşur.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Renk.soluk)),
                ]),
              ),
            ], genis)
          else if (s != null) ...[
            _kpi(s, w),
            _notlar(s),
            _kap([_yontemPaneli(s, dokum), if (dokum != null) _mutabakatPaneli(dokum)], genis),
            if (tamSayi(s['collected_debt_minor']) > 0 || _tahsilatlar.isNotEmpty) _kap([_borcPaneli(s)], genis),
            if (_seciliGun != null && _gununKapanislari(_seciliGun!).isNotEmpty) _kap([_bolunmePaneli(_gununKapanislari(_seciliGun!))], genis),
            _kap([_saatPaneli(s)], genis),
          ],
        ];
        return RefreshIndicator(
          onRefresh: () async {
            await _durumYukle();
            await _raporYukle();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: dis,
            child: Container(
              padding: kartIc,
              decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, height: 1.45, color: Renk.yazi),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var i = 0; i < bolumler.length; i++) ...[if (i > 0) const SizedBox(height: 12), bolumler[i]],
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _iki(String e, Widget d) => Row(children: [Expanded(child: Text(e, style: const TextStyle(fontSize: 13))), d]);

  TextSpan _b(String m) => TextSpan(text: m, style: TextStyle(fontWeight: FontWeight.w600, color: Renk.yazi));

  /// 34 px liste kutusu (rx-sec): sağda aşağı ok.
  Widget _secimKutusu<T>({required T? deger, required List<DropdownMenuItem<T>> ogeler, required ValueChanged<T?> degisti, required String etiket}) => Semantics(
        label: etiket,
        child: Container(
          height: 34,
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: deger,
              isExpanded: true,
              isDense: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Renk.soluk),
              dropdownColor: Renk.yuzey,
              borderRadius: koseYuvarlak,
              style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: Renk.yazi),
              items: ogeler,
              onChanged: degisti,
            ),
          ),
        ),
      );

  /* 1. BAŞLIK SATIRI: ad + dönem listesi | düğmeler */
  Widget _baslikSatiri(double ic) {
    final gun = _seciliGun;
    final kap = _seciliKapanis;
    final aralik = _harita(_durum?['aralik']);
    final esler = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'acik', child: Text('Açık gün · ${aralik['etiket'] ?? 'şu an'}', overflow: TextOverflow.ellipsis)),
      for (final ig in _isGunleri) ...[
        DropdownMenuItem(
          enabled: false,
          value: '#${ig['is_gunu']}',
          child: Text(_gunEtiketi('${ig['is_gunu']}'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.soluk)),
        ),
        DropdownMenuItem(
          value: 'gun:${ig['is_gunu']}',
          child: Text(
            'Tüm iş günü${tamSayi(ig['kapanis_sayisi']) > 1 ? ' (${tamSayi(ig['kapanis_sayisi'])} kapanış)' : ''} · ${_tl(tamSayi(ig['tahsilat_minor']))} tahsilat',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final k in _gununKapanislari(ig))
          DropdownMenuItem(
            value: 'k:${k['id']}',
            child: Text(
              '    ${k['saat']} · ${k['tur'] == 'gece' ? 'gece kapanışı (ertesi gün)' : 'gün kapanışı'} · ${_tl(tamSayi(k['tahsilat_minor']))} tahsilat',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    ];
    // Aynı kapanış iki gruba düşmesin (değerler tekil olmalı).
    final gorulen = <String>{};
    final tekil = [for (final e in esler) if (gorulen.add(e.value!)) e];
    final secici = _secimKutusu<String>(
      etiket: 'Kapanış dönemi',
      deger: tekil.any((e) => e.value == _secim) ? _secim : 'acik',
      ogeler: tekil,
      degisti: (v) {
        if (v != null && !v.startsWith('#')) _secimDegis(v);
      },
    );
    final yaziciSecici = _yazicilar.length > 1
        ? _secimKutusu<int>(
            etiket: 'Rapor yazıcısı',
            deger: _yazici,
            ogeler: [for (final y in _yazicilar) DropdownMenuItem(value: tamSayi(y['id']), child: Text('${y['name']} · ${y['station_label'] ?? ''}', overflow: TextOverflow.ellipsis))],
            degisti: (v) => setState(() => _yazici = v),
          )
        : null;
    final baslik = Text(widget.gomulu ? 'Kapanış dönemi' : 'Gün sonu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Renk.yazi));
    final acikDon = _secim != 'acik' ? _Dugme('Açık güne dön', () => _secimDegis('acik')) : null;
    const yukleniyor = SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

    // (düğme, ana mı)
    final dugmeler = <(Widget Function(bool dolu), bool)>[
      if (_secim == 'acik') ((d) => _Dugme('Gün sonu raporu al', _basiliyor ? null : _kapanisSor, ikon: Icons.print_outlined, ana: true, dolu: d), true),
      if (gun != null)
        for (final k in _gununKapanislari(gun))
          (
            (d) => _Dugme('${k['saat']} fişini bas', _basiliyor ? null : () => _raporuBas(false, tamSayi(k['id'])),
                ikon: Icons.print_outlined, ipucu: '${k['baslangic']} → ${k['bitis']} kapanışının fişini tekrar bas', dolu: d),
            false
          ),
      if (kap != null)
        (
          (d) => _Dugme('Bu dönemi tekrar bas', _basiliyor ? null : () => _raporuBas(false, tamSayi(kap['id'])),
              ikon: Icons.print_outlined, ana: true, ipucu: 'Bu kapanışın raporunu tekrar bas (hiçbir şeyi değiştirmez)', dolu: d),
          true
        ),
      if (_secim == 'acik' && _gecmis.isNotEmpty)
        (
          (d) => _Dugme('Önceki kapanış', _basiliyor ? null : () => _raporuBas(false, tamSayi(_gecmis.first['id'])),
              ikon: Icons.history_rounded, ipucu: '${_gecmis.first['is_gunu']} kapanışının raporunu tekrar bas', dolu: d),
          false
        ),
      if (gun == null) ((d) => _Dugme('Fiş önizleme', _onizleme, ikon: Icons.visibility_outlined, ipucu: 'Fişi basmadan ekranda gör', dolu: d), false),
      ((d) => _Dugme('Dışa aktar', () => _disaAktar('ops-eod'), ikon: Icons.download_rounded, dolu: d), false),
    ];

    Widget govde;
    if (ic < 560) {
      // TELEFON: ana düğme tam satır, diğerleri ikişer eşit genişlik.
      final digerleri = [for (final d in dugmeler) if (!d.$2) d.$1(true)];
      final satirlar = <Widget>[
        Row(children: [
          baslik,
          const SizedBox(width: 8),
          Expanded(child: secici),
          if (_basiliyor) ...[const SizedBox(width: 8), yukleniyor],
        ]),
        if (acikDon != null) Align(alignment: Alignment.centerLeft, child: acikDon),
        if (yaziciSecici case final bbDeger?) bbDeger,
        for (final d in dugmeler)
          if (d.$2) d.$1(true),
        for (var i = 0; i < digerleri.length; i += 2)
          Row(children: [
            Expanded(child: digerleri[i]),
            const SizedBox(width: 8),
            Expanded(child: i + 1 < digerleri.length ? digerleri[i + 1] : const SizedBox()),
          ]),
      ];
      govde = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < satirlar.length; i++) ...[if (i > 0) const SizedBox(height: 8), satirlar[i]],
      ]);
    } else {
      govde = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            baslik,
            SizedBox(width: math.min(420.0, ic - 110), child: secici),
            if (acikDon case final bbDeger?) bbDeger,
            if (_basiliyor) yukleniyor,
          ]),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (yaziciSecici != null) SizedBox(width: 220, child: yaziciSecici),
            for (final d in dugmeler) d.$1(false),
          ]),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: govde,
    );
  }

  /* 2. DÖNEM BİLGİSİ: ne zamandan ne zamana, ne devretti */
  Widget _donemBilgisi() {
    final d = _durum!;
    final gun = _seciliGun;
    final kap = _seciliKapanis;
    final aralik = _harita(d['aralik']);
    final etiket = gun != null ? '${gun['baslangic']} → ${gun['bitis']}' : (kap != null ? '${kap['baslangic']} → ${kap['bitis']}' : '${aralik['etiket'] ?? ''}');
    final ek = gun != null
        ? ' · ${_gunEtiketi('${gun['is_gunu']}')} iş gününün tamamı'
        : (kap != null
            ? ' · kapanmış dönem, rakamlar donmuştur'
            : (d['son_kapanis'] is Map ? ' · son kapanış ${_harita(d['son_kapanis'])['kapanis']}' : ' · henüz hiç kapanış yapılmadı; ilk rapor günü kapatır'));
    final satirlar = <Widget>[
      _bilgiSatiri(Icons.schedule_rounded, Renk.soluk, [_b(etiket), TextSpan(text: ek)]),
    ];
    if (kap != null && tamSayi(kap['devir_masa']) > 0) {
      satirlar.add(_bilgiSatiri(Icons.merge_rounded, Renk.soluk, [
        TextSpan(text: 'Önceki kapanıştan (${kap['devir_kapanis'] ?? ''}) devralınan '),
        _b('${tamSayi(kap['devir_masa'])} açık masa'),
        const TextSpan(text: ' · '),
        _b(_tl(tamSayi(kap['devir_minor']))),
        const TextSpan(text: ' — hesapları bu dönemde kapandı.'),
      ]));
    }
    if (kap != null && tamSayi(kap['acik_masa']) > 0) {
      satirlar.add(_bilgiSatiri(Icons.warning_amber_rounded, Renk.uyari, [
        const TextSpan(text: 'Kapanış anında '),
        _b('${tamSayi(kap['acik_masa'])} masa açıktı'),
        TextSpan(text: ' (${_tl(tamSayi(kap['acik_masa_minor']))}) — hesapları SONRAKİ döneme devretti.'),
      ]));
    } else if (kap == null && gun == null && tamSayi(d['acik_adisyon']) > 0) {
      satirlar.add(_bilgiSatiri(Icons.warning_amber_rounded, Renk.uyari, [
        const TextSpan(text: 'Şu an '),
        _b('${tamSayi(d['acik_adisyon'])} masa açık'),
        TextSpan(text: ' (${_tl(tamSayi(d['acik_adisyon_kalan_minor']))} tahsil edilmedi) — şimdi kapatırsanız bu tutar sonraki döneme devreder.'),
      ]));
    }
    satirlar.add(Text('Gün takvimle değil kasa kapanışıyla biter; rapor alındığında gün kapanır.', style: TextStyle(fontSize: 12, color: Renk.soluk)));
    return DefaultTextStyle.merge(
      style: TextStyle(fontSize: 12.5, color: Renk.soluk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < satirlar.length; i++) ...[if (i > 0) const SizedBox(height: 4), satirlar[i]],
      ]),
    );
  }

  Widget _bilgiSatiri(IconData ikon, Color renk, List<InlineSpan> metin) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: Icon(ikon, size: 13, color: renk)),
        const SizedBox(width: 6),
        Expanded(child: Text.rich(TextSpan(children: metin))),
      ]);

  /* 3. RAKAM KUTULARI — sıra SABİT (fişin başı → dönemin diğer rakamları) */
  Widget _kpi(Map<String, dynamic> s, double w) {
    final rev = tamSayi(s['revenue_minor']);
    final borc = tamSayi(s['debt_transferred_balance_minor']);
    final collected = tamSayi(s['collected_minor']);
    final borcPay = tamSayi(s['collected_debt_minor']);
    final tahsilatAyrimi = '${tamSayi(s['collected_count'])} işlem${borcPay <= 0 ? ' · tamamı adisyon ödemesi' : ' · adisyon ${_tl(s['collected_payments_minor'] != null ? tamSayi(s['collected_payments_minor']) : collected - borcPay)} + borçtan ${_tl(borcPay)}'}';
    final cekmece = s['cash_drawer_minor'];
    String kasaIpucu() {
      final p = <String>[
        if (s['cash_drawer_devir_minor'] != null) 'devreden ${_tl(tamSayi(s['cash_drawer_devir_minor']))}',
        for (final i in _liste(s['cash_drawer_items'])) '${tamSayi(i['amount_minor']) < 0 ? '−' : '+'} ${i['label']} ${_tl(tamSayi(i['amount_minor']).abs())}',
      ];
      var m = p.isEmpty ? 'hareket yok' : p.join(' · ');
      if (tamSayi(cekmece) < 0) m += ' · EKSİ: çekmeceyi sayın';
      return m;
    }

    final siparis = tamSayi(s['orders']);
    final misafir = tamSayi(s['guests']);
    final borcAcik = s['open_receivables_available'] == true;
    final kutular = <Widget>[
      _Kutu('Ciro — tahsil edilen', _tl(rev - borc), '$siparis adisyon kapandı · parası kasaya giren kısım'),
      _Kutu('Borca yazılan', _tl(borc), '${tamSayi(s['debt_transferred_count'])} adisyon · satıldı, parası ALINMADI'),
      _Kutu('Ciro toplamı', _tl(rev), 'tahsil edilen + borca yazılan'),
      _Kutu('Kasaya giren toplam', _tl(collected), tahsilatAyrimi),
      if (cekmece != null) _Kutu('Kasadaki nakit', _tl(tamSayi(cekmece)), kasaIpucu(), eksi: tamSayi(cekmece) < 0),
      _Kutu('Açılan adisyon', '${tamSayi(s['orders_opened'])}', 'bu dönemde sipariş verildi'),
      _Kutu('Kapanan adisyon', '${tamSayi(s['orders_closed'])}', 'tam ödenip kapandı'),
      _Kutu('Ortalama sepet', siparis > 0 ? _tl(tamSayi(s['avg_basket_minor'])) : '—', ''),
      _Kutu('Kişi başı', s['per_guest_minor'] == null ? '—' : _tl(tamSayi(s['per_guest_minor'])), misafir > 0 ? '$misafir misafir' : 'misafir girilmemiş'),
      _Kutu('Açık masa', _tl(tamSayi(s['open_table_minor'])), '${tamSayi(s['open_table_orders'])} adisyon · ciro DEĞİL'),
      _Kutu('İndirim', _tl(tamSayi(s['discount_total_minor'])), 'kapanan adisyonlarda'),
      _Kutu('İkram', _tl(tamSayi(s['comp_minor'])), tamSayi(s['comp_count']) > 0 ? '${tamSayi(s['comp_count'])} adet · maliyet ${_tl(tamSayi(s['comp_cost_minor']))}' : 'yok'),
      _Kutu('İptal', '${tamSayi(s['cancelled_orders'])}', tamSayi(s['cancelled_orders']) > 0 ? _tl(tamSayi(s['cancelled_minor'])) : 'yok'),
      _Kutu('İade', _tl(tamSayi(s['refunded_minor'])), tamSayi(s['refund_payments_count']) > 0 ? '${tamSayi(s['refund_payments_count'])} işlem' : 'yok'),
      _Kutu('Açık borç', borcAcik ? _tl(tamSayi(s['open_receivables_total_minor'])) : '—', borcAcik ? '${tamSayi(s['open_receivables_count'])} şahıs (güncel)' : 'şahıs modülü kapalı'),
    ];
    return _Izgara(sutun: w >= 900 ? 5 : (w >= 641 ? 3 : 2), aralik: 8, children: kutular);
  }

  Widget _notlar(Map<String, dynamic> s) {
    final stil = TextStyle(fontSize: 12, color: Renk.soluk);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (tamSayi(s['debt_transferred_balance_minor']) == 0 && s['open_receivables_available'] == true && tamSayi(s['open_receivables_total_minor']) > 0) ...[
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Bu dönemde borca yazılan adisyon yok — ancak '),
            _b(_tl(tamSayi(s['open_receivables_total_minor']))),
            TextSpan(text: ' tutarında açık borç (${tamSayi(s['open_receivables_count'])} şahıs) hâlâ tahsil edilmemiş.'),
          ]),
          style: stil,
        ),
        const SizedBox(height: 4),
      ],
      Text('İndirim / ikram / iptal dökümü: Adisyonlar → İndirim · iptal · Kim ne kadar borçlu: Borçlar sekmesi.', style: stil),
    ]);
  }

  /* 4. TABLO KABI: 1 px çizgi, soluk zemin; genişte iki tablo yan yana */
  Widget _kap(List<Widget> paneller, bool genis) {
    final Widget ic;
    if (paneller.length == 2 && genis) {
      ic = LayoutBuilder(
        builder: (context, k) => Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: paneller[0]), const SizedBox(width: 1), Expanded(child: paneller[1])]),
          Positioned(top: 0, bottom: 0, left: (k.maxWidth - 1) / 2, width: 1, child: ColoredBox(color: Renk.cizgi)),
        ]),
      );
    } else {
      ic = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < paneller.length; i++) ...[if (i > 0) Container(height: 1, color: Renk.cizgi), paneller[i]],
      ]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: ic,
    );
  }

  /// Tablo başlığı (ad + soluk toplam [+ eylem]) · tablo · dipnot.
  Widget _panel({required String baslik, String? ozet, Widget? eylem, required Widget tablo, Widget? dip}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
          child: Row(children: [
            Expanded(child: Text(baslik, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            if (ozet != null) ...[
              const SizedBox(width: 8),
              Text(ozet, softWrap: false, style: TextStyle(fontSize: 13, color: Renk.soluk, fontFeatures: _tabular)),
            ],
            if (eylem != null) ...[const SizedBox(width: 8), eylem],
          ]),
        ),
        tablo,
        if (dip != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
            child: DefaultTextStyle.merge(style: TextStyle(fontSize: 12, height: 1.45, color: Renk.soluk), child: dip),
          ),
      ]);

  /// Hücre metni: 13 px, tabular rakam; [sag] sayısal sütun.
  Widget _h(String m, {bool sag = false, TextStyle? stil}) => Text(
        m.isEmpty ? '—' : m,
        textAlign: sag ? TextAlign.right : TextAlign.left,
        style: const TextStyle(fontSize: 13, fontFeatures: _tabular).merge(stil),
      );

  TextStyle get _sl => TextStyle(color: Renk.soluk);
  static const _kalin = TextStyle(fontWeight: FontWeight.w600);

  /* 4a. Tahsilat — Ödeme Yöntemi */
  Widget _yontemPaneli(Map<String, dynamic> s, Map<String, dynamic>? b) {
    final satirlar = b != null ? _liste(b['rows']) : _liste(s['collection_methods']);
    final toplam = satirlar.fold<int>(0, (t, r) => t + tamSayi(r['amount_minor']));
    num pay(Map<String, dynamic> r) => r['share'] is num ? r['share'] as num : (toplam == 0 ? 0 : tamSayi(r['amount_minor']) * 100 / toplam);
    final borc = tamSayi(s['collected_debt_minor']);
    final adisyon = tamSayi(s['collected_payments_minor']);
    return _panel(
      baslik: 'Tahsilat — Ödeme Yöntemi',
      ozet: _tl(b != null ? tamSayi(b['total_minor']) : tamSayi(s['collected_minor'])),
      tablo: _Tablo(
        kolonlar: const [_Kol('Oran', 54), _Kol('Ödeme Tipi', 92), _Kol('Adet', 76, sag: true), _Kol('Tutar', 96, sag: true)],
        esnek: 1,
        bos: 'Bu dönemde kasadan ödeme alınmadı.',
        satirlar: [
          for (final r in satirlar)
            _Satir([_h(_pay(pay(r))), _h('${r['label'] ?? ''}'), _h('${tamSayi(r['count'])} işlem', sag: true), _h(_tl(tamSayi(r['amount_minor'])), sag: true)]),
        ],
        alt: b == null
            ? const []
            : [
                _Satir([
                  _h('TOPLAM TAHSİL EDİLEN', stil: _kalin),
                  _h('${tamSayi(b['total_count'])} işlem', sag: true, stil: _kalin),
                  _h(_tl(tamSayi(b['total_minor'])), sag: true, stil: _kalin),
                ], yay: const {0: 2}),
                if (tamSayi(b['debt_collected_minor']) > 0) ...[
                  _Satir([
                    Padding(padding: const EdgeInsets.only(left: 24), child: _h('Adisyon tahsilatı', stil: _sl)),
                    _h('${tamSayi(b['order_count'])}', sag: true, stil: _sl),
                    _h(_tl(tamSayi(b['order_minor'])), sag: true, stil: _sl),
                  ], yay: const {0: 2}),
                  _Satir([
                    Padding(padding: const EdgeInsets.only(left: 24), child: _h('Tahsil edilen eski borç', stil: _sl)),
                    _h('${tamSayi(b['debt_collected_count'])}', sag: true, stil: _sl),
                    _h(_tl(tamSayi(b['debt_collected_minor'])), sag: true, stil: _sl),
                  ], yay: const {0: 2}),
                ],
                _Satir([
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'BORCA YAZILAN', style: _kalin),
                    TextSpan(text: ' satıldı, parası alınmadı', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
                  ]), style: const TextStyle(fontSize: 13)),
                  _h('${tamSayi(b['debt_transferred_count'])} adisyon', sag: true, stil: _kalin),
                  _h(_tl(tamSayi(b['debt_transferred_minor'])), sag: true, stil: _kalin),
                ], yay: const {0: 2}),
              ],
      ),
      dip: Text.rich(TextSpan(children: [
        const TextSpan(text: 'Fişteki kırılımın aynısı: adisyon ödemeleri ve borç tahsilatı birlikte.'),
        if (borc > 0) ...[
          const TextSpan(text: ' Bu tutarın '),
          _b(_tl(borc)),
          TextSpan(text: ' kadarı ESKİ BORÇ tahsilatıdır (${tamSayi(s['collected_debt_count'])} işlem); bu dönemin cirosu değildir, önceki günlerde borca yazılan paranın geri ödemesidir.'),
          if (adisyon > 0) ...[const TextSpan(text: ' Kalanı '), _b(_tl(adisyon)), const TextSpan(text: ' adisyon ödemesidir.')],
        ],
      ])),
    );
  }

  /* 4b. Ciro ↔ Tahsilat */
  Widget _mutabakatPaneli(Map<String, dynamic> b) => _panel(
        baslik: 'Ciro ↔ Tahsilat',
        tablo: _Tablo(
          kolonlar: const [_Kol('Kalem', 180), _Kol('Tutar', 110, sag: true)],
          bos: 'Kalem yok.',
          satirlar: [for (final l in _liste(b['lines'])) _cizgiSatiri(l)],
        ),
        dip: Text.rich(TextSpan(children: [
          const TextSpan(text: 'Ciro, borca yazılanı da içerir; borca yazılan kısmın parası kasaya girmemiştir. Bu yüzden '),
          _b('ciro − borca yazılan = adisyon tahsilatı'),
          const TextSpan(text: ' olmalıdır. Eski borç tahsilatı bu denklemin dışındadır: kasaya girer ama bu dönemin cirosu değildir.'),
        ])),
      );

  _Satir _cizgiSatiri(Map<String, dynamic> l) {
    final tur = '${l['kind'] ?? ''}';
    final onek = tur == 'minus' ? '− ' : (tur == 'equals' ? '= ' : '');
    final m = tamSayi(l['amount_minor']);
    final tutar = tur == 'ok' ? 'TAMAM' : (tur == 'minus' ? '−${_tl(m.abs())}' : _tl(m));
    final stil = switch (tur) {
      'diff' => TextStyle(fontWeight: FontWeight.w700, color: Renk.hata),
      'ok' => TextStyle(fontWeight: FontWeight.w600, color: Renk.basari),
      'info' => TextStyle(color: Renk.soluk),
      'base' || 'equals' || 'actual' => _kalin,
      _ => const TextStyle(),
    };
    final sayi = l['count'] == null ? 0 : tamSayi(l['count']);
    return _Satir([
      Padding(
        padding: EdgeInsets.only(left: tur == 'info' ? 24 : 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '$onek${l['label'] ?? ''}'),
              if (sayi > 0) TextSpan(text: ' ($sayi)', style: TextStyle(fontWeight: FontWeight.w400, color: Renk.soluk)),
            ]),
            style: const TextStyle(fontSize: 13).merge(stil),
          ),
          if (l['note'] != null && '${l['note']}'.isNotEmpty) Text('${l['note']}', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
        ]),
      ),
      _h(tutar, sag: true, stil: stil),
    ]);
  }

  /* 5. Borçtan Tahsil Edilenler */
  Widget _borcPaneli(Map<String, dynamic> s) {
    final kapanan = _tahsilatlar.where((r) => tamSayi(r['balance_after_minor']) == 0).length;
    final kalan = _tahsilatlar.fold<int>(0, (t, r) => t + (tamSayi(r['balance_after_minor']) > 0 ? tamSayi(r['balance_after_minor']) : 0));
    return _panel(
      baslik: 'Borçtan Tahsil Edilenler',
      ozet: _tl(tamSayi(s['collected_debt_minor'])),
      eylem: _Dugme('Dışa aktar', () => _disaAktar('receivables-collections'), ikon: Icons.download_rounded, yukseklik: 28),
      tablo: _Tablo(
        kolonlar: const [
          _Kol('Tarih', 104),
          _Kol('Şahıs', 120),
          _Kol('Yöntem', 92),
          _Kol('Tahsil Edilen', 112, sag: true),
          _Kol('Kalan Borcu', 108, sag: true),
          _Kol('Alan', 104),
        ],
        esnek: 1,
        bos: 'Bu dönemde borçtan tahsilat yok.',
        satirlar: [
          for (final r in _tahsilatlar)
            _Satir([
              _h('${r['at'] ?? '—'}', stil: _sl),
              _h('${r['name'] ?? '—'}'),
              _h('${r['method'] ?? '—'}', stil: _sl),
              _h(_tl(tamSayi(r['amount_minor'])), sag: true),
              _h(_tl(tamSayi(r['balance_after_minor'])), sag: true),
              _h('${r['staff'] ?? '—'}', stil: _sl),
            ]),
        ],
      ),
      dip: _tahsilatlar.isEmpty
          ? null
          : Text.rich(TextSpan(children: [
              if (kapanan > 0) TextSpan(text: '$kapanan şahsın borcu tamamen kapandı. '),
              if (kalan > 0) ...[const TextSpan(text: 'Ödeme yapanların üzerinde hâlâ '), _b(_tl(kalan)), const TextSpan(text: ' borç duruyor. ')],
              const TextSpan(text: 'Tahsilat en eski borçtan düşer; "kalan borcu" o şahsın ödeme anındaki toplam bakiyesidir.'),
            ])),
    );
  }

  /* 6. Bu İş Günü Kaç Kapanışa Bölündü */
  Widget _bolunmePaneli(List<Map<String, dynamic>> ks) => _panel(
        baslik: 'Bu İş Günü Kaç Kapanışa Bölündü',
        tablo: _Tablo(
          kolonlar: const [
            _Kol('Kapanış', 72),
            _Kol('Bölüm', 112),
            _Kol('Dönem', 180),
            _Kol('Adisyon', 72, sag: true),
            _Kol('Ciro', 100, sag: true),
            _Kol('Tahsilat', 100, sag: true),
            _Kol('Devreden', 100, sag: true),
          ],
          esnek: 2,
          bos: 'Bu iş gününde kapanış yok.',
          satirlar: [
            for (final k in ks)
              _Satir([
                _h('${k['saat'] ?? ''}'),
                _h(k['tur'] == 'gece' ? 'Gece (ertesi gün)' : 'Gün', stil: _sl),
                _h('${k['baslangic']} → ${k['bitis']}', stil: _sl),
                _h('${tamSayi(k['kapanan_adisyon'])}', sag: true),
                _h(_tl(tamSayi(k['ciro_minor'])), sag: true),
                _h(_tl(tamSayi(k['tahsilat_minor'])), sag: true),
                _h(_tl(tamSayi(k['acik_masa_minor'])), sag: true),
              ]),
          ],
        ),
        dip: const Text(
            '23:59\'da alınan gün sonu günü kapatır; mekân açıksa gece ayrı bir kapanışla biter. Yukarıdaki rakamlar bu kapanışların TOPLAMIDIR. "Devreden" sütunu, o kapanış anında ödenmemiş masaların tutarıdır; hesapları bir sonraki kapanışta görünür. Bu yüzden bir kapanışın cirosu ile tahsilatı birbirini tutmayabilir.'),
      );

  /* 7. Saat Bazlı Satış */
  Widget _saatPaneli(Map<String, dynamic> s) {
    final satirlar = _saatler.where((h) => tamSayi(h['orders']) > 0 || tamSayi(h['revenue_minor']) > 0).toList();
    final toplam = satirlar.fold<int>(0, (t, h) => t + tamSayi(h['revenue_minor']));
    final adisyon = satirlar.fold<int>(0, (t, h) => t + tamSayi(h['orders']));
    Map<String, dynamic>? yogun;
    for (final h in satirlar) {
      if (yogun == null || tamSayi(h['revenue_minor']) > tamSayi(yogun['revenue_minor'])) yogun = h;
    }
    final gece = satirlar.where((h) => tamSayi(h['hour']) < _gunSaati).toList();
    final geceCiro = gece.fold<int>(0, (t, h) => t + tamSayi(h['revenue_minor']));
    String et(int h) => '${h.toString().padLeft(2, '0')}:00';
    return _panel(
      baslik: 'Saat Bazlı Satış',
      ozet: '${_tl(toplam)} · $adisyon adisyon',
      tablo: _Tablo(
        kolonlar: const [_Kol('Saat', 72), _Kol('Bölüm', 96), _Kol('Adisyon', 80, sag: true), _Kol('Ciro', 110, sag: true)],
        esnek: 1,
        bos: 'Bu dönemde saatlik satış yok.',
        satirlar: [
          for (final h in satirlar)
            _Satir([
              _h(et(tamSayi(h['hour']))),
              _h(tamSayi(h['hour']) < _gunSaati ? 'Gece' : 'Gündüz', stil: _sl),
              _h('${tamSayi(h['orders'])}', sag: true),
              _h(_tl(tamSayi(h['revenue_minor'])), sag: true),
            ]),
        ],
      ),
      dip: Text.rich(TextSpan(children: [
        const TextSpan(text: 'Toplam '),
        _b(_tl(toplam)),
        const TextSpan(text: ' · En yoğun saat '),
        _b(yogun == null ? '—' : '${et(tamSayi(yogun['hour']))} · ${_tl(tamSayi(yogun['revenue_minor']))}'),
        if (geceCiro > 0) ...[
          TextSpan(text: ' · Gece (00:00–${_gunSaati.toString().padLeft(2, '0')}:00) '),
          _b(_tl(geceCiro)),
          TextSpan(text: ' · ${gece.fold<int>(0, (t, h) => t + tamSayi(h['orders']))} adisyon — bu satışlar bir önceki iş gününe yazılır.'),
        ],
      ])),
    );
  }
}

/* ═════════════ Rapor dili parçaları (web rapor-dili.css) ═════════════ */

/// rx-dug: 34 px, 12 yatay boşluk, 13/500, 15 px simge; [ana] marka dolu.
/// [dolu]: bulunduğu genişliği doldurur (telefon düğme ızgarası).
class _Dugme extends StatelessWidget {
  const _Dugme(this.metin, this.onTap, {this.ikon, this.ana = false, this.ipucu, this.yukseklik = 34, this.dolu = false});
  final String metin;
  final VoidCallback? onTap;
  final IconData? ikon;
  final bool ana;
  final String? ipucu;
  final double yukseklik;
  final bool dolu;

  @override
  Widget build(BuildContext context) {
    final renk = ana ? Colors.white : Renk.yazi;
    final w = Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: ana ? Kabuk.brand : Renk.yuzey,
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: ana ? Kabuk.brand : Renk.cizgi)),
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: onTap,
          child: Container(
            height: yukseklik,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: dolu ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (ikon != null) ...[Icon(ikon, size: 15, color: renk), const SizedBox(width: 6)],
              Flexible(child: Text(metin, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: renk))),
            ]),
          ),
        ),
      ),
    );
    return ipucu == null ? w : Tooltip(message: ipucu!, child: w);
  }
}

/// Rakam kutusu (rx-kpi li): kalın etiket, soluk değer, tek satır açıklama.
class _Kutu extends StatelessWidget {
  const _Kutu(this.ad, this.deger, this.ipucu, {this.eksi = false});
  final String ad;
  final String deger;
  final String ipucu;
  final bool eksi;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(ad, style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: Renk.yazi)),
          Text(deger,
              style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: eksi ? FontWeight.w600 : FontWeight.w400, color: eksi ? Renk.hata : Renk.soluk, fontFeatures: _tabular)),
          if (ipucu.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(ipucu, style: TextStyle(fontSize: 11.5, height: 1.35, color: Renk.soluk)),
          ],
        ]),
      );
}

/// Eşit sütunlu ızgara: satır içi kutular aynı boy.
class _Izgara extends StatelessWidget {
  const _Izgara({required this.sutun, required this.children, this.aralik = 8});
  final int sutun;
  final List<Widget> children;
  final double aralik;

  @override
  Widget build(BuildContext context) {
    final satirlar = <Widget>[];
    for (var i = 0; i < children.length; i += sutun) {
      satirlar.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + sutun; j++) ...[
            if (j > i) SizedBox(width: aralik),
            Expanded(child: j < children.length ? children[j] : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < satirlar.length; i++) ...[if (i > 0) SizedBox(height: aralik), satirlar[i]],
    ]);
  }
}

class _Kol {
  const _Kol(this.ad, this.en, {this.sag = false});
  final String ad;

  /// En az genişlik (px); artan genişlik [_Tablo.esnek] sütununa gider.
  final double en;
  final bool sag;
}

class _Satir {
  const _Satir(this.hucreler, {this.yay = const {}});
  final List<Widget> hucreler;

  /// Hücre sırası → kapladığı sütun sayısı (colspan).
  final Map<int, int> yay;
}

/// rx-tbl: başlık 13/600, hücre 13, 9/12 boşluk, alt çizgi; sayısal sütun
/// sağa yaslı. Sığmazsa yatay kayar.
class _Tablo extends StatelessWidget {
  const _Tablo({required this.kolonlar, required this.satirlar, required this.bos, this.alt = const [], this.esnek = 0});
  final List<_Kol> kolonlar;
  final List<_Satir> satirlar;
  final String bos;

  /// Toplam satırları (tfoot): boş tabloda da görünür.
  final List<_Satir> alt;
  final int esnek;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, k) {
        const ic = 12.0;
        final enAz = kolonlar.fold<double>(0, (a, x) => a + x.en) + ic * 2;
        final toplam = math.max(k.maxWidth, enAz);
        final en = [for (var i = 0; i < kolonlar.length; i++) kolonlar[i].en + (i == esnek ? toplam - enAz : 0)];
        final cizgi = BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi)));

        Widget satir(_Satir s, {bool son = false}) {
          final parcalar = <Widget>[];
          var kol = 0;
          for (var i = 0; i < s.hucreler.length && kol < kolonlar.length; i++) {
            final n = s.yay[i] ?? 1;
            final gen = en.sublist(kol, math.min(kol + n, en.length)).fold<double>(0, (a, b) => a + b);
            final sag = n == 1 && kolonlar[kol].sag;
            // Sağa yaslı sütundan sonra gelen sola yaslı sütun yapışmasın.
            final sol = !sag && kol > 0 && kolonlar[kol - 1].sag ? 12.0 : 0.0;
            parcalar.add(SizedBox(
              width: gen,
              child: Align(
                alignment: sag ? Alignment.topRight : Alignment.topLeft,
                child: Padding(padding: EdgeInsets.only(left: sol, right: sag ? 0 : 8), child: s.hucreler[i]),
              ),
            ));
            kol += n;
          }
          return Container(
            width: toplam,
            padding: const EdgeInsets.symmetric(horizontal: ic, vertical: 9),
            decoration: son ? null : cizgi,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: parcalar),
          );
        }

        final hepsi = [...satirlar, ...alt];
        final govde = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          satir(_Satir([
            for (final c in kolonlar)
              Text(c.ad, maxLines: 1, textAlign: c.sag ? TextAlign.right : TextAlign.left, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ])),
          if (satirlar.isEmpty)
            Container(
              width: toplam,
              padding: const EdgeInsets.all(18),
              decoration: alt.isEmpty ? null : cizgi,
              child: Text(bos, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.soluk)),
            ),
          for (var i = 0; i < hepsi.length; i++) satir(hepsi[i], son: i == hepsi.length - 1),
        ]);
        return enAz <= k.maxWidth + .5 ? govde : SingleChildScrollView(scrollDirection: Axis.horizontal, child: govde);
      });
}
