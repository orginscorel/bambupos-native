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

String _yuzde(num v) => '%${(v.toDouble()).toStringAsFixed(1).replaceAll('.', ',')}';

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

const _renkler = [Color(0xFF5047CE), Color(0xFF0891B2), Color(0xFF15803D), Color(0xFFD97706), Color(0xFF94A3B8)];

class GunSonuEkrani extends StatefulWidget {
  const GunSonuEkrani({super.key});

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

  /* ── görünüm ── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final s = _s;
    final bos = s != null && tamSayi(s['orders']) == 0 && tamSayi(s['orders_opened']) == 0;
    final kartlar = <Widget>[
      _donemKarti(g),
      if (_hata != null) Text(_hata!, style: TextStyle(color: Renk.hata, fontSize: 13)),
      if (bos)
        _bosDurum(Icons.receipt_long_outlined, 'Bu dönemde hareket yok', 'Adisyon açıldıkça gün sonu özeti (ciro, tahsilat, kasadaki nakit) burada oluşur.')
      else if (s != null) ...[
        _kpi(s, g),
        if (tamSayi(s['debt_transferred_balance_minor']) == 0 && s['open_receivables_available'] == true && tamSayi(s['open_receivables_total_minor']) > 0)
          Text(
            'Bu dönemde borca yazılan adisyon yok — ancak ${_tl(tamSayi(s['open_receivables_total_minor']))} tutarında açık borç (${tamSayi(s['open_receivables_count'])} şahıs) hâlâ tahsil edilmemiş.',
            style: TextStyle(fontSize: 12, color: Renk.soluk),
          ),
        _yontemKarti(s),
        if (s['collection_breakdown'] is Map) _dokumKarti(_harita(s['collection_breakdown'])),
        if (tamSayi(s['collected_debt_minor']) > 0 || _tahsilatlar.isNotEmpty) _borcKarti(s),
        if (_seciliGun != null && _gununKapanislari(_seciliGun!).isNotEmpty) _bolunmeKarti(_gununKapanislari(_seciliGun!)),
        _saatKarti(s),
        _digerKarti(s, g),
      ],
    ];

    return ColoredBox(
      color: Kabuk.sunken,
      child: RefreshIndicator(
        onRefresh: () async {
          await _durumYukle();
          await _raporYukle();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: g >= 1024 ? const EdgeInsets.fromLTRB(18, 12, 18, 26) : const EdgeInsets.fromLTRB(14, 10, 14, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
              Text('Gün sonu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.36, color: Kabuk.ink)),
              Text('gün takvimle değil kasa kapanışıyla biter; rapor alındığında gün kapanır', style: TextStyle(fontSize: 11.5, color: Kabuk.soft)),
            ]),
            const SizedBox(height: 10),
            for (var i = 0; i < kartlar.length; i++) ...[if (i > 0) const SizedBox(height: 10), kartlar[i]],
          ]),
        ),
      ),
    );
  }

  Widget _iki(String e, Widget d) => Row(children: [Expanded(child: Text(e, style: const TextStyle(fontSize: 13))), d]);

  Widget _bosDurum(IconData ikon, String b, String m) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Column(children: [
          Icon(ikon, size: 30, color: Renk.soluk),
          const SizedBox(height: 6),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(m, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
        ]),
      );

  Widget _donemKarti(double g) {
    final d = _durum;
    final gun = _seciliGun;
    final kap = _seciliKapanis;
    final aralik = _harita(d?['aralik']);
    final esler = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'acik', child: Text('Açık gün · ${aralik['etiket'] ?? 'şu an'}', overflow: TextOverflow.ellipsis)),
      for (final ig in _isGunleri) ...[
        DropdownMenuItem(
          enabled: false,
          value: '#${ig['is_gunu']}',
          child: Text(_gunEtiketi('${ig['is_gunu']}'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.soluk)),
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

    final dugmeler = <Widget>[
      if (_yazicilar.length > 1)
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          child: DropdownButton<int>(
            value: _yazici,
            underline: const SizedBox(),
            style: TextStyle(fontSize: 12, color: Renk.yazi),
            items: [for (final y in _yazicilar) DropdownMenuItem(value: tamSayi(y['id']), child: Text('${y['name']} · ${y['station_label'] ?? ''}'))],
            onChanged: (v) => setState(() => _yazici = v),
          ),
        ),
      if (_secim == 'acik') syDugme('Gün sonu raporu al', _basiliyor ? null : _kapanisSor, birincil: true, ikon: Icons.print_outlined, yukseklik: 34),
      if (gun != null)
        for (final k in _gununKapanislari(gun))
          Tooltip(
            message: '${k['baslangic']} → ${k['bitis']} kapanışının fişini tekrar bas',
            child: syDugme('${k['saat']} fişini bas', _basiliyor ? null : () => _raporuBas(false, tamSayi(k['id'])), ikon: Icons.print_outlined, yukseklik: 34),
          ),
      if (kap != null)
        Tooltip(
          message: 'Bu kapanışın raporunu tekrar bas (hiçbir şeyi değiştirmez)',
          child: syDugme('Bu dönemi tekrar bas', _basiliyor ? null : () => _raporuBas(false, tamSayi(kap['id'])), birincil: true, ikon: Icons.print_outlined, yukseklik: 34),
        ),
      if (_secim == 'acik' && _gecmis.isNotEmpty)
        Tooltip(
          message: '${_gecmis.first['is_gunu']} kapanışının raporunu tekrar bas',
          child: syDugme('Önceki kapanış', _basiliyor ? null : () => _raporuBas(false, tamSayi(_gecmis.first['id'])), ikon: Icons.history_rounded, yukseklik: 34),
        ),
      if (gun == null) Tooltip(message: 'Fişi basmadan ekranda gör', child: syDugme('Fiş önizleme', _onizleme, ikon: Icons.visibility_outlined, yukseklik: 34)),
      TextButton.icon(onPressed: () => _disaAktar('ops-eod'), icon: const Icon(Icons.download_rounded, size: 16), label: const Text('Dışa aktar')),
      if (_basiliyor) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
    ];

    Widget? alt;
    if (d != null) {
      final etiket = gun != null
          ? '${gun['baslangic']} → ${gun['bitis']}'
          : (kap != null ? '${kap['baslangic']} → ${kap['bitis']}' : '${aralik['etiket'] ?? ''}');
      final ek = gun != null
          ? ' · ${_gunEtiketi('${gun['is_gunu']}')} iş gününün tamamı'
          : (kap != null
              ? ' · kapanmış dönem, rakamlar donmuştur'
              : (d['son_kapanis'] is Map ? ' · son kapanış ${_harita(d['son_kapanis'])['kapanis']}' : ' · henüz hiç kapanış yapılmadı; ilk rapor günü kapatır'));
      final satirlar = <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.schedule_rounded, size: 13, color: Renk.ikinci)),
          const SizedBox(width: 5),
          Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: etiket, style: const TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: ek)]))),
        ]),
      ];
      if (kap != null && tamSayi(kap['devir_masa']) > 0) {
        satirlar.add(_uyariSatiri(Icons.merge_rounded, Renk.ikinci, [
          TextSpan(text: 'Önceki kapanıştan (${kap['devir_kapanis'] ?? ''}) devralınan '),
          TextSpan(text: '${tamSayi(kap['devir_masa'])} açık masa · ${_tl(tamSayi(kap['devir_minor']))}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' — hesapları bu dönemde kapandı.'),
        ]));
      }
      if (kap != null && tamSayi(kap['acik_masa']) > 0) {
        satirlar.add(_uyariSatiri(Icons.warning_amber_rounded, Kabuk.warning, [
          TextSpan(text: 'Kapanış anında ${tamSayi(kap['acik_masa'])} masa açıktı (${_tl(tamSayi(kap['acik_masa_minor']))}) — hesapları SONRAKİ döneme devretti.'),
        ]));
      } else if (kap == null && gun == null && tamSayi(d['acik_adisyon']) > 0) {
        satirlar.add(_uyariSatiri(Icons.warning_amber_rounded, Kabuk.warning, [
          TextSpan(
              text:
                  'Şu an ${tamSayi(d['acik_adisyon'])} masa açık (${_tl(tamSayi(d['acik_adisyon_kalan_minor']))} tahsil edilmedi) — şimdi kapatırsanız bu tutar sonraki döneme devreder.'),
        ]));
      }
      alt = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in satirlar) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: s)]);
    }

    return _RaporKart(
      ikon: Icons.receipt_long_outlined,
      baslik: 'Kapanış dönemi',
      not: 'Gün takvimle değil kasa kapanışıyla biter; rapor alındığında gün kapanır.',
      alt: alt,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            height: 36,
            constraints: BoxConstraints(maxWidth: g >= 640 ? 448 : g - 60),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
            child: DropdownButton<String>(
              value: tekil.any((e) => e.value == _secim) ? _secim : 'acik',
              isExpanded: true,
              underline: const SizedBox(),
              style: TextStyle(fontSize: 13, color: Renk.yazi),
              items: tekil,
              onChanged: (v) {
                if (v != null && !v.startsWith('#')) _secimDegis(v);
              },
            ),
          ),
          if (_secim != 'acik') syDugme('Açık güne dön', () => _secimDegis('acik'), yukseklik: 34),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: dugmeler),
      ]),
    );
  }

  Widget _uyariSatiri(IconData ikon, Color renk, List<InlineSpan> metin) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(ikon, size: 13, color: renk)),
        const SizedBox(width: 5),
        Expanded(child: Text.rich(TextSpan(children: metin))),
      ]);

  Widget _kpi(Map<String, dynamic> s, double g) {
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

    final kutular = [
      _StatTile('Ciro — tahsil edilen', _tl(rev - borc), '${tamSayi(s['orders'])} adisyon kapandı · parası kasaya giren kısım', Kabuk.success),
      _StatTile('Borca yazılan', _tl(borc), '${tamSayi(s['debt_transferred_count'])} adisyon · satıldı, parası ALINMADI', Kabuk.warning),
      _StatTile('Ciro toplamı', _tl(rev), 'tahsil edilen + borca yazılan', Renk.yazi),
      _StatTile('Kasaya giren toplam', _tl(collected), tahsilatAyrimi, Renk.marka),
      if (cekmece != null) _StatTile('Kasadaki nakit', _tl(tamSayi(cekmece)), kasaIpucu(), tamSayi(cekmece) < 0 ? Renk.hata : Renk.yazi),
    ];
    return _Izgara(sutun: g >= 1280 ? 5 : 2, aralik: 10, children: kutular);
  }

  Widget _yontemKarti(Map<String, dynamic> s) {
    final yontem = _liste(s['collection_methods']);
    final seg = <(String, int, String)>[
      for (final y in yontem.take(4)) ('${y['label']}', tamSayi(y['amount_minor']), '${tamSayi(y['count'])} işlem'),
      if (yontem.length > 4) ('Diğer', yontem.skip(4).fold<int>(0, (t, y) => t + tamSayi(y['amount_minor'])), '${yontem.length - 4} yöntem'),
    ].where((x) => x.$2 > 0).toList();
    final borc = tamSayi(s['collected_debt_minor']);
    final adisyon = tamSayi(s['collected_payments_minor']);
    return _RaporKart(
      ikon: Icons.account_balance_wallet_outlined,
      baslik: 'Tahsilat — ödeme yöntemi',
      not: 'Fişteki kırılımın aynısı: adisyon ödemeleri ve borç tahsilatı birlikte.',
      ozet: _tl(tamSayi(s['collected_minor'])),
      alt: borc > 0
          ? Text(
              'Bu tutarın ${_tl(borc)} kadarı ESKİ BORÇ tahsilatıdır (${tamSayi(s['collected_debt_count'])} işlem); bu dönemin cirosu değildir, önceki günlerde borca yazılan paranın geri ödemesidir.${adisyon > 0 ? ' Kalanı ${_tl(adisyon)} adisyon ödemesidir.' : ''}')
          : null,
      child: seg.isEmpty
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(Icons.account_balance_wallet_outlined, size: 26, color: Renk.soluk),
                Text('Tahsilat yok', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('Bu dönemde kasadan ödeme alınmadı.', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              ]),
            )
          : _YiginCubuk(segmentler: seg),
    );
  }

  Widget _dokumKarti(Map<String, dynamic> b) {
    final rows = _liste(b['rows']);
    final lines = _liste(b['lines']);
    Widget iki(Widget sol, Widget sag, {double girinti = 0}) =>
        Padding(padding: EdgeInsets.only(left: girinti, top: 3, bottom: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: sol), const SizedBox(width: 8), sag]));
    return _RaporKart(
      ikon: Icons.account_balance_wallet_outlined,
      baslik: 'Tahsilat dökümü',
      not: 'Para hangi yöntemle girdi, ne kadarı borca yazıldı, ciro ile tahsilat tutuyor mu. Basılan fişteki kalemlerin aynısı.',
      ozet: _tl(tamSayi(b['total_minor'])),
      flush: true,
      alt: const Text.rich(TextSpan(children: [
        TextSpan(text: 'Ciro, borca yazılanı da içerir; borca yazılan kısmın parası kasaya girmemiştir. Bu yüzden '),
        TextSpan(text: 'ciro − borca yazılan = adisyon tahsilatı', style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' olmalıdır. Eski borç tahsilatı bu denklemin dışındadır: kasaya girer ama bu dönemin cirosu değildir.'),
      ])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _Tablo(
          basliklar: const ['Ödeme yöntemi', 'İşlem', 'Tahsil edilen', 'Pay'],
          sag: const {1, 2, 3},
          bos: 'Bu dönemde kasadan ödeme alınmadı.',
          satirlar: [
            for (final r in rows) ['${r['label']}', '${tamSayi(r['count'])}', _tl(tamSayi(r['amount_minor'])), _yuzde((r['share'] as num?) ?? 0)],
          ],
          kalin: const {2},
        ),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 14),
            child: Column(children: [
              iki(const Text('TOPLAM TAHSİL EDİLEN', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: _tl(tamSayi(b['total_minor'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                    TextSpan(text: ' · ${tamSayi(b['total_count'])} işlem', style: TextStyle(fontSize: 12, color: Renk.soluk)),
                  ]))),
              if (tamSayi(b['debt_collected_minor']) > 0) ...[
                iki(Text('Adisyon tahsilatı (${tamSayi(b['order_count'])})', style: TextStyle(color: Renk.ikinci)), Text(_tl(tamSayi(b['order_minor'])), style: TextStyle(color: Renk.ikinci)), girinti: 12),
                iki(Text('Tahsil edilen eski borç (${tamSayi(b['debt_collected_count'])})', style: TextStyle(color: Renk.ikinci)),
                    Text(_tl(tamSayi(b['debt_collected_minor'])), style: TextStyle(color: Renk.ikinci)),
                    girinti: 12),
              ],
              iki(
                  Text.rich(TextSpan(children: [
                    const TextSpan(text: 'BORCA YAZILAN', style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: ' (${tamSayi(b['debt_transferred_count'])} adisyon · satıldı, parası alınmadı)', style: TextStyle(fontSize: 12, color: Renk.soluk)),
                  ])),
                  Text(_tl(tamSayi(b['debt_transferred_minor'])), style: TextStyle(fontWeight: FontWeight.w800, color: Kabuk.warning))),
            ]),
          ),
        ),
        Container(
          color: Renk.ic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('CİRO ↔ TAHSİLAT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.soluk, letterSpacing: .6)),
            const SizedBox(height: 4),
            for (final l in lines) _cizgiSatiri(l),
          ]),
        ),
      ]),
    );
  }

  Widget _cizgiSatiri(Map<String, dynamic> l) {
    final tur = '${l['kind'] ?? ''}';
    final onek = tur == 'minus' ? '− ' : (tur == 'equals' ? '= ' : '');
    final m = tamSayi(l['amount_minor']);
    final tutar = tur == 'ok' ? 'TAMAM' : (tur == 'minus' ? '−${_tl(m.abs())}' : _tl(m));
    final stil = switch (tur) {
      'diff' => TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.hata),
      'ok' => TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Renk.basari),
      'info' => TextStyle(fontSize: 14, color: Renk.ikinci),
      'base' || 'equals' || 'actual' => TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.yazi),
      _ => TextStyle(fontSize: 14, color: Renk.yazi),
    };
    final sayi = l['count'] == null ? 0 : tamSayi(l['count']);
    return Padding(
      padding: EdgeInsets.only(left: tur == 'info' ? 12 : 0, top: 3, bottom: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '$onek${l['label'] ?? ''}'),
              if (sayi > 0) TextSpan(text: ' ($sayi)', style: TextStyle(fontWeight: FontWeight.w400, color: Renk.soluk)),
            ]), style: stil),
            if (l['note'] != null && '${l['note']}'.isNotEmpty) Text('${l['note']}', style: TextStyle(fontSize: 11, color: Renk.soluk)),
          ]),
        ),
        Text(tutar, style: stil),
      ]),
    );
  }

  Widget _borcKarti(Map<String, dynamic> s) {
    final kapanan = _tahsilatlar.where((r) => tamSayi(r['balance_after_minor']) == 0).length;
    final kalan = _tahsilatlar.fold<int>(0, (t, r) => t + (tamSayi(r['balance_after_minor']) > 0 ? tamSayi(r['balance_after_minor']) : 0));
    return _RaporKart(
      ikon: Icons.receipt_long_outlined,
      baslik: 'Borçtan tahsil edilenler',
      not: 'Kim, ne zaman, hangi yöntemle ödedi; ödeme sonrası borcu ne kaldı.',
      ozet: _tl(tamSayi(s['collected_debt_minor'])),
      eylem: TextButton.icon(onPressed: () => _disaAktar('receivables-collections'), icon: const Icon(Icons.download_rounded, size: 15), label: const Text('Dışa aktar')),
      flush: true,
      alt: _tahsilatlar.isEmpty
          ? null
          : Text(
              '${kapanan > 0 ? '$kapanan şahsın borcu tamamen kapandı. ' : ''}${kalan > 0 ? 'Ödeme yapanların üzerinde hâlâ ${_tl(kalan)} borç duruyor. ' : ''}Tahsilat en eski borçtan düşer; "kalan borcu" o şahsın ödeme anındaki toplam bakiyesidir.'),
      child: _Tablo(
        basliklar: const ['Tarih', 'Şahıs', 'Yöntem', 'Tahsil edilen', 'Kalan borcu', 'Alan'],
        sag: const {3, 4},
        kalin: const {3, 4},
        bos: 'Bu dönemde borçtan tahsilat yok.',
        satirlar: [
          for (final r in _tahsilatlar)
            ['${r['at'] ?? '—'}', '${r['name'] ?? '—'}', '${r['method'] ?? '—'}', _tl(tamSayi(r['amount_minor'])), _tl(tamSayi(r['balance_after_minor'])), '${r['staff'] ?? '—'}'],
        ],
      ),
    );
  }

  Widget _bolunmeKarti(List<Map<String, dynamic>> ks) => _RaporKart(
        ikon: Icons.merge_rounded,
        baslik: 'Bu iş günü kaç kapanışa bölündü',
        not: '23:59\'da alınan gün sonu günü kapatır; mekân açıksa gece ayrı bir kapanışla biter. Yukarıdaki rakamlar bu kapanışların TOPLAMIDIR.',
        flush: true,
        alt: const Text('"Devreden" sütunu, o kapanış anında ödenmemiş masaların tutarıdır; hesapları bir sonraki kapanışta görünür. Bu yüzden bir kapanışın cirosu ile tahsilatı birbirini tutmayabilir.'),
        child: _Tablo(
          basliklar: const ['Kapanış', 'Bölüm', 'Dönem', 'Adisyon', 'Ciro', 'Tahsilat', 'Devreden'],
          sag: const {3, 4, 5, 6},
          kalin: const {4, 5, 6},
          bos: 'Bu iş gününde kapanış yok.',
          satirlar: [
            for (final k in ks)
              [
                '${k['saat'] ?? ''}',
                k['tur'] == 'gece' ? 'Gece (ertesi gün)' : 'Gün',
                '${k['baslangic']} → ${k['bitis']}',
                '${tamSayi(k['kapanan_adisyon'])}',
                _tl(tamSayi(k['ciro_minor'])),
                _tl(tamSayi(k['tahsilat_minor'])),
                _tl(tamSayi(k['acik_masa_minor'])),
              ],
          ],
        ),
      );

  Widget _saatKarti(Map<String, dynamic> s) {
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
    return _RaporKart(
      ikon: Icons.schedule_rounded,
      baslik: 'Saat bazlı satış',
      not: 'Dönem içindeki satışın saatlere dağılımı; gece saatleri ayrıca toplanır.',
      ozet: '${_tl(toplam)} · $adisyon adisyon',
      flush: true,
      alt: Wrap(spacing: 14, runSpacing: 2, children: [
        Text('Toplam ${_tl(toplam)}'),
        Text('En yoğun saat ${yogun == null ? '—' : '${et(tamSayi(yogun['hour']))} · ${_tl(tamSayi(yogun['revenue_minor']))}'}'),
        if (geceCiro > 0)
          Text('Gece (00:00–${_gunSaati.toString().padLeft(2, '0')}:00) ${_tl(geceCiro)} · ${gece.fold<int>(0, (t, h) => t + tamSayi(h['orders']))} adisyon — bu satışlar bir önceki iş gününe yazılır.'),
      ]),
      child: _Tablo(
        basliklar: const ['Saat', 'Bölüm', 'Adisyon', 'Ciro'],
        sag: const {2, 3},
        kalin: const {3},
        bos: 'Bu dönemde saatlik satış yok.',
        satirlar: [
          for (final h in satirlar) [et(tamSayi(h['hour'])), tamSayi(h['hour']) < _gunSaati ? 'Gece' : 'Gündüz', '${tamSayi(h['orders'])}', _tl(tamSayi(h['revenue_minor']))],
        ],
      ),
    );
  }

  Widget _digerKarti(Map<String, dynamic> s, double g) {
    final siparis = tamSayi(s['orders']);
    final misafir = tamSayi(s['guests']);
    final borcAcik = s['open_receivables_available'] == true;
    final ogeler = <(String, String, String, Color?)>[
      ('Açılan adisyon', '${tamSayi(s['orders_opened'])}', 'bu dönemde sipariş verildi', null),
      ('Kapanan adisyon', '${tamSayi(s['orders_closed'])}', 'tam ödenip kapandı', null),
      ('Ortalama sepet', siparis > 0 ? _tl(tamSayi(s['avg_basket_minor'])) : '—', '', null),
      ('Kişi başı', s['per_guest_minor'] == null ? '—' : _tl(tamSayi(s['per_guest_minor'])), misafir > 0 ? '$misafir misafir' : 'misafir girilmemiş', null),
      ('Açık masa', _tl(tamSayi(s['open_table_minor'])), '${tamSayi(s['open_table_orders'])} adisyon · ciro DEĞİL', Renk.hata),
      ('İndirim', _tl(tamSayi(s['discount_total_minor'])), 'kapanan adisyonlarda', null),
      ('İkram', _tl(tamSayi(s['comp_minor'])), tamSayi(s['comp_count']) > 0 ? '${tamSayi(s['comp_count'])} adet · maliyet ${_tl(tamSayi(s['comp_cost_minor']))}' : 'yok', null),
      ('İptal', '${tamSayi(s['cancelled_orders'])}', tamSayi(s['cancelled_orders']) > 0 ? _tl(tamSayi(s['cancelled_minor'])) : 'yok', null),
      ('İade', _tl(tamSayi(s['refunded_minor'])), tamSayi(s['refund_payments_count']) > 0 ? '${tamSayi(s['refund_payments_count'])} işlem' : 'yok', null),
      ('Açık borç', borcAcik ? _tl(tamSayi(s['open_receivables_total_minor'])) : '—', borcAcik ? '${tamSayi(s['open_receivables_count'])} şahıs (güncel)' : 'şahıs modülü kapalı', Renk.hata),
    ];
    return _RaporKart(
      ikon: Icons.format_list_bulleted_rounded,
      baslik: 'Dönemin diğer rakamları',
      not: 'Fişte yer alan ikincil rakamlar; ayrıntılı dökümler ilgili sekmelerde.',
      alt: const Text('İndirim / ikram / iptal dökümü: Adisyonlar → İndirim · iptal · Kim ne kadar borçlu: Borçlar sekmesi.'),
      child: _Izgara(
        sutun: g >= 1280 ? 5 : (g >= 640 ? 3 : 2),
        aralik: 16,
        satirAraligi: 12,
        children: [
          for (final (e, d, n, r) in ogeler)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.toUpperCase(), style: TextStyle(fontSize: 11, color: Renk.ikinci, letterSpacing: .3)),
              Text(d, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: r ?? Renk.yazi)),
              if (n.isNotEmpty) Text(n, style: TextStyle(fontSize: 11, color: Renk.soluk)),
            ]),
        ],
      ),
    );
  }
}

/* ═════════════ Ortak rapor bileşenleri ═════════════ */

class _RaporKart extends StatelessWidget {
  const _RaporKart({required this.ikon, required this.baslik, required this.child, this.not, this.ozet, this.eylem, this.alt, this.flush = false});
  final IconData ikon;
  final String baslik;
  final String? not;
  final String? ozet;
  final Widget? eylem;
  final Widget child;
  final Widget? alt;
  final bool flush;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(ikon, size: 16, color: Renk.soluk)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(baslik, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: -.13)),
                  if (not != null) Text(not!, style: TextStyle(fontSize: 11.5, color: Renk.ikinci)),
                ]),
              ),
              if (ozet != null) ...[
                const SizedBox(width: 8),
                Text(ozet!, softWrap: false, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
              ],
              ?eylem,
            ]),
          ),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
            padding: flush ? EdgeInsets.zero : const EdgeInsets.all(12),
            child: child,
          ),
          if (alt != null)
            Container(
              decoration: BoxDecoration(color: Renk.ic, border: Border(top: BorderSide(color: Renk.cizgi))),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: DefaultTextStyle.merge(style: TextStyle(fontSize: 11.5, color: Renk.ikinci), child: alt!),
            ),
        ]),
      );
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.etiket, this.deger, this.ipucu, this.ton);
  final String etiket;
  final String deger;
  final String ipucu;
  final Color ton;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(etiket, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Renk.ikinci)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(deger, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: ton, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Text(ipucu, style: TextStyle(fontSize: 11, color: Renk.soluk)),
        ]),
      );
}

class _Izgara extends StatelessWidget {
  const _Izgara({required this.sutun, required this.children, this.aralik = 10, this.satirAraligi});
  final int sutun;
  final List<Widget> children;
  final double aralik;
  final double? satirAraligi;

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
    return Column(children: [for (var i = 0; i < satirlar.length; i++) ...[if (i > 0) SizedBox(height: satirAraligi ?? aralik), satirlar[i]]]);
  }
}

/// ReportTable: başlıklı tablo; dar ekranda yatay kayar.
class _Tablo extends StatelessWidget {
  const _Tablo({required this.basliklar, required this.satirlar, required this.bos, this.sag = const {}, this.kalin = const {}});
  final List<String> basliklar;
  final List<List<String>> satirlar;
  final String bos;
  final Set<int> sag;
  final Set<int> kalin;

  @override
  Widget build(BuildContext context) {
    if (satirlar.isEmpty) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(bos, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.soluk)));
    }
    Widget hucre(String m, int i, {bool baslik = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            m.isEmpty ? '—' : m,
            textAlign: sag.contains(i) ? TextAlign.right : TextAlign.left,
            style: baslik
                ? TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.ikinci)
                : TextStyle(fontSize: 13, fontWeight: kalin.contains(i) ? FontWeight.w700 : FontWeight.w400),
          ),
        );
    return LayoutBuilder(
      builder: (context, k) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: k.maxWidth),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder(horizontalInside: BorderSide(color: Renk.cizgi)),
            children: [
              TableRow(decoration: BoxDecoration(color: Renk.ic), children: [for (var i = 0; i < basliklar.length; i++) hucre(basliklar[i], i, baslik: true)]),
              for (final s in satirlar) TableRow(children: [for (var i = 0; i < basliklar.length; i++) hucre(i < s.length ? s[i] : '', i)]),
            ],
          ),
        ),
      ),
    );
  }
}

/// ChartStackedBar: 28 px yatay yığılmış çubuk + açıklama satırları.
class _YiginCubuk extends StatelessWidget {
  const _YiginCubuk({required this.segmentler});
  final List<(String, int, String)> segmentler;

  @override
  Widget build(BuildContext context) {
    final toplam = segmentler.fold<int>(0, (t, s) => t + s.$2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        label: 'Gün sonu ödeme yöntemi payı',
        child: SizedBox(
          height: 28,
          child: Row(children: [
            for (var i = 0; i < segmentler.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (segmentler[i].$2 * 1000 ~/ (toplam == 0 ? 1 : toplam)).clamp(1, 1000),
                child: Tooltip(
                  message: '${_tl(segmentler[i].$2)}\n${segmentler[i].$1} · ${segmentler[i].$3}',
                  child: Container(decoration: BoxDecoration(color: _renkler[i.clamp(0, 4)], borderRadius: BorderRadius.circular(3))),
                ),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (var i = 0; i < segmentler.length; i++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _renkler[i.clamp(0, 4)], borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text(segmentler[i].$1, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 6),
            Text(_tl(segmentler[i].$2), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(' (${_yuzde(toplam == 0 ? 0 : segmentler[i].$2 * 100 / toplam)})', style: TextStyle(fontSize: 12, color: Renk.soluk)),
          ]),
      ]),
    ]);
  }
}
