import 'dart:async';

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'kabuk.dart';
import 'kasa_ekrani.dart';
import 'ortak.dart';

/// BORÇLAR / ŞAHISLAR — web /panel/borclar (Receivables/Index.vue) birebiri.
/// Şartname: /root/work/spec/borclar.md.
/// Üç sekme: Borçlular · Tahsil edilenler · Borca yazılanlar; şahıs detayı,
/// oluştur/düzenle, sil, eski (defter) borcu ekle ve hızlı tahsilat pencereleri.
/// Asıl tahsilat yolu Kasa ekranıdır ("Kasada tahsil et").
class BorclarEkrani extends StatefulWidget {
  const BorclarEkrani({super.key});

  @override
  State<BorclarEkrani> createState() => _BorclarEkraniState();
}

/* ═════════════ Biçimler ═════════════ */

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

String _iki(int n) => n.toString().padLeft(2, '0');
DateTime? _t(Object? iso) => iso == null ? null : DateTime.tryParse('$iso')?.toLocal();
String _ss(DateTime t) => '${_iki(t.hour)}:${_iki(t.minute)}';

/// "bugün 19:42" · "dün 19:42" · "27 Ağustos 19:42" (farklı yılda yıl eklenir).
String _tarihSaatKisa(Object? iso) {
  final t = _t(iso);
  if (t == null) return '';
  final s = DateTime.now();
  final bugun = DateTime(s.year, s.month, s.day);
  final gun = DateTime(t.year, t.month, t.day);
  if (gun == bugun) return 'bugün ${_ss(t)}';
  if (gun == bugun.subtract(const Duration(days: 1))) return 'dün ${_ss(t)}';
  return '${t.day} ${_aylar[t.month - 1]}${t.year != s.year ? ' ${t.year}' : ''} ${_ss(t)}';
}

/// "31 Ağustos 2026 · 19:42"
String _tarihSaat(Object? iso) {
  final t = _t(iso);
  return t == null ? '' : '${t.day} ${_aylar[t.month - 1]} ${t.year} · ${_ss(t)}';
}

/// "24 Ağustos 2026 Pazartesi · 19:42"
String _ziyaret(Object? iso) {
  final t = _t(iso);
  return t == null ? '' : '${t.day} ${_aylar[t.month - 1]} ${t.year} ${_gunler[t.weekday - 1]} · ${_ss(t)}';
}

/// "13.09.26 19:42"
String _kisaTarih(Object? iso) {
  final t = _t(iso);
  return t == null ? '—' : '${_iki(t.day)}.${_iki(t.month)}.${_iki(t.year % 100)} ${_ss(t)}';
}

String _ymd(DateTime t) => '${t.year}-${_iki(t.month)}-${_iki(t.day)}';
DateTime? _gunu(String? ymd) {
  final p = ymd?.split('-');
  if (p == null || p.length != 3) return null;
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]), 12);
}

String _gunEtiketi(String ymd) {
  final t = _gunu(ymd);
  return t == null ? ymd : '${t.day} ${_aylar[t.month - 1]} ${t.year}';
}

String _aralikEtiketi(String? bas, String? bit) {
  if (bas == null || bit == null) return '—';
  return bas == bit ? _gunEtiketi(bas) : '${_gunEtiketi(bas)} – ${_gunEtiketi(bit)}';
}

/// web parseAmountMinor: boşluk ve noktaları sil, ilk virgül → nokta.
int _tutarOku(String s) {
  final v = s.replaceAll(RegExp(r'\s'), '').replaceAll('.', '').replaceFirst(',', '.');
  final d = double.tryParse(v);
  return d == null || d.isNaN ? 0 : (d * 100).round();
}

String _yontemEtiketi(Object? m) => switch (m) {
      'cash' => 'Nakit',
      'card' => 'Kart',
      'transfer' => 'Havale/EFT',
      'other' => 'Diğer',
      null => '',
      _ => '$m',
    };

/* ═════════════ İş günü aralıkları (isGunu.ts) ═════════════ */

class _IsGunu {
  String bugun = _ymd(DateTime.now());
  String? dun;
  bool yuklendi = false;

  Future<void> yukle(Api api) async {
    if (yuklendi) return;
    try {
      final r = await api.get('/api/v1/reports/eod/durum');
      if (r is Map) {
        if (r['is_gunu'] != null) bugun = '${r['is_gunu']}';
        final k = r['son_kapanis'];
        if (k is Map && k['is_gunu'] != null) dun = '${k['is_gunu']}';
      }
    } on ApiHata {
      // Okunamazsa takvim günü kullanılır.
    }
    yuklendi = true;
  }

  String _kaydir(String ymd, int gun) => _ymd(_gunu(ymd)!.add(Duration(days: gun)));

  (String, String)? aralik(String hazir) => switch (hazir) {
        'bugun' => (bugun, bugun),
        'dun' => (dun ?? _kaydir(bugun, -1), dun ?? _kaydir(bugun, -1)),
        'hafta' => (_kaydir(bugun, -6), bugun),
        'otuz' => (_kaydir(bugun, -29), bugun),
        'ay' => ('${bugun.substring(0, 8)}01', bugun),
        _ => null,
      };
}

const _hazirlar = <(String, String)>[
  ('bugun', 'Bugün'),
  ('dun', 'Dün'),
  ('hafta', 'Son 7 gün'),
  ('otuz', 'Son 30 gün'),
  ('ay', 'Bu ay'),
  ('ozel', 'Tarih seç'),
];

/* ═════════════ Ekran ═════════════ */

class _BorclarEkraniState extends State<BorclarEkrani> {
  String _sekme = 'borclular';
  late final Api _api = context.api;
  final _isGunu = _IsGunu();

  bool _can(String k) => context.durum.oturum!.yetki(k);

  // Borçlular
  List<Map<String, dynamic>> _sahislar = const [];
  int _sayfa = 1;
  int _sonSayfa = 1;
  int _toplam = 0;
  bool _yalnizBorclu = true;
  String _q = '';
  bool _yukleniyor = true;
  Timer? _gecikme;

  @override
  void initState() {
    super.initState();
    _sahislariYukle();
  }

  @override
  void dispose() {
    _gecikme?.cancel();
    super.dispose();
  }

  Future<void> _sahislariYukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await _api.get('/api/v1/receivables', sorgu: {
        if (_q.isNotEmpty) 'q': _q,
        if (_yalnizBorclu) 'only_debtors': 1,
        'page': _sayfa,
      });
      if (!mounted) return;
      final p = r is Map && r['receivables'] is Map ? r['receivables'] as Map : const {};
      setState(() {
        _sahislar = (p['data'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _sonSayfa = tamSayi(p['last_page'], 1);
        _toplam = tamSayi(p['total']);
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Şahıs listesi yüklenemedi', e.mesaj.isEmpty ? 'Beklenmeyen bir hata oluştu.' : e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _araDegisti(String v) {
    _gecikme?.cancel();
    _gecikme = Timer(const Duration(milliseconds: 300), () {
      _q = v.trim();
      _sayfa = 1;
      _sahislariYukle();
    });
  }

  /* ── pencereler ── */

  Future<void> _detayAc(int id, [Map<String, dynamic>? satir]) => cekmeceAc<void>(
        context,
        baslik: satir?['name']?.toString() ?? 'Şahıs',
        genislik: 512,
        icerik: (ctx) => _Detay(id: id, ilk: satir, api: _api, can: _can, listeyiYenile: _sahislariYukle),
      );

  Future<void> _formAc([Map<String, dynamic>? r]) async {
    final ok = await cekmeceAc<bool>(
      context,
      baslik: r == null ? 'Yeni şahıs' : 'Şahsı düzenle',
      icerik: (ctx) => _SahisFormu(kayit: r, api: _api),
    );
    if (ok == true && mounted) _sahislariYukle();
  }

  Future<void> _sil(Map<String, dynamic> r) async {
    final ok = await pencereAc<bool>(context: context, builder: (_) => _SilPenceresi(kayit: r, api: _api));
    if (ok == true && mounted) _sahislariYukle();
  }

  /* ── görünüm ── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    return ColoredBox(
      color: Renk.zemin,
      child: ListView(
        padding: EdgeInsets.fromLTRB(g >= 640 ? 16 : 12, g >= 640 ? 16 : 12, g >= 640 ? 16 : 12, g >= 1024 ? 16 : 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _sekmeSeridi(),
                const SizedBox(height: 12),
                switch (_sekme) {
                  'tahsilat' => _TarihliListe(key: const ValueKey('tahsilat'), tur: _Tur.tahsilat, api: _api, isGunu: _isGunu, kisiAc: _detayAc),
                  'yazilanlar' => _TarihliListe(key: const ValueKey('yazilanlar'), tur: _Tur.yazilan, api: _api, isGunu: _isGunu, kisiAc: _detayAc),
                  _ => _borclular(g),
                },
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sekmeSeridi() {
    Widget sekme(String k, IconData ikon, String ad) {
      final secili = _sekme == k;
      return Expanded(
        child: Material(
          color: secili ? Renk.marka : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() => _sekme = k),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ikon, size: 15, color: secili ? Colors.white : Renk.ikinci),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: secili ? Colors.white : Renk.ikinci)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Row(children: [
        sekme('borclular', Icons.people_outline_rounded, 'Borçlular'),
        const SizedBox(width: 4),
        sekme('tahsilat', Icons.account_balance_wallet_outlined, 'Tahsil edilenler'),
        const SizedBox(width: 4),
        sekme('yazilanlar', Icons.inbox_outlined, 'Borca yazılanlar'),
      ]),
    );
  }

  Widget _borclular(double g) {
    // En yüksek pozitif bakiyeli satır (eşitlikte ilk).
    var enYuksek = -1;
    var enYuksekTutar = 0;
    for (var i = 0; i < _sahislar.length; i++) {
      final b = tamSayi(_sahislar[i]['balance_minor']);
      if (b > enYuksekTutar) {
        enYuksekTutar = b;
        enYuksek = i;
      }
    }

    return _Kart(
      baslik: 'Şahıs hesapları',
      eylemler: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 34)),
          onPressed: () => _formAc(),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Yeni şahıs'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
          child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SizedBox(
                height: 38,
                child: TextField(
                  onChanged: _araDegisti,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ad, telefon, e-posta ara…',
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: Renk.soluk),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: _yalnizBorclu,
                onChanged: (v) {
                  setState(() => _yalnizBorclu = v);
                  _sayfa = 1;
                  _sahislariYukle();
                },
              ),
              const SizedBox(width: 6),
              const Text('Yalnız borçlular', style: TextStyle(fontSize: 14)),
            ]),
            Text('$_toplam şahıs', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ]),
        ),
        if (_yukleniyor && _sahislar.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_sahislar.isEmpty)
          const _Bos(
            ikon: Icons.people_outline_rounded,
            baslik: 'Şahıs yok',
            metin: 'Bir adisyonu borca taşıdığınızda ya da elle şahıs eklediğinizde burada görünür.',
          )
        else
          _Tablo(
            enAz: 720,
            sutunlar: const [
              _Sutun('Şahıs', 3),
              _Sutun('Bakiye (borç)', 2, hiza: TextAlign.right),
              _Sutun('Taşınmış adisyon', 2, hiza: TextAlign.center),
              _Sutun('Son tahsilat', 2),
              _Sutun('İşlemler', 3, hiza: TextAlign.right),
            ],
            satirlar: [
              for (var i = 0; i < _sahislar.length; i++) _sahisSatiri(_sahislar[i], i == enYuksek, g),
            ],
          ),
        if (_sonSayfa > 1)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
            child: Center(
              child: _Sayfalama(
                sayfa: _sayfa,
                son: _sonSayfa,
                git: (n) {
                  _sayfa = n;
                  _sahislariYukle();
                },
              ),
            ),
          ),
      ]),
    );
  }

  List<Widget> _sahisSatiri(Map<String, dynamic> r, bool enYuksek, double g) {
    final id = tamSayi(r['id']);
    final b = tamSayi(r['balance_minor']);
    final tel = r['phone']?.toString();
    Widget? rozet;
    if (enYuksek) {
      rozet = Tooltip(
        message: 'Bu listedeki en yüksek borç',
        child: Rozet('En yüksek borç', renk: Renk.hata, dolu: true, ikon: Icons.warning_amber_rounded),
      );
    } else if (b >= 1000000) {
      rozet = Tooltip(
        message: 'Borcu ${para(1000000)} üzerinde',
        child: Rozet('Yüksek borç', renk: Renk.uyari, dolu: true, ikon: Icons.error_outline_rounded),
      );
    }
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          InkWell(
            onTap: () => _detayAc(id, r),
            child: Text('${r['name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          ?rozet,
        ]),
        Text(tel == null || tel.isEmpty ? '—' : tel, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      ]),
      Text(para(b), textAlign: TextAlign.right, style: TextStyle(fontSize: 14, fontWeight: b > 0 ? FontWeight.w700 : FontWeight.w400, color: b > 0 ? Renk.hata : Renk.ikinci)),
      Text('${tamSayi(r['open_debt_orders_count'])}', textAlign: TextAlign.center),
      r['last_payment_at'] == null
          ? Text('Ödeme yok', style: TextStyle(fontSize: 13, color: Renk.soluk))
          : Text(_tarihSaatKisa(r['last_payment_at']), style: const TextStyle(fontSize: 13)),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => _detayAc(id, r), child: const Text('Detay')),
        IconButton(tooltip: 'Şahsı düzenle', onPressed: () => _formAc(r), icon: const Icon(Icons.edit_outlined, size: 16)),
        Tooltip(
          message: 'Hesabı sil',
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Renk.hata),
            onPressed: () => _sil(r),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: g >= 640 ? const Text('Sil') : const SizedBox.shrink(),
          ),
        ),
      ]),
    ];
  }
}

/* ═════════════ Tahsil edilenler / Borca yazılanlar ═════════════ */

enum _Tur { tahsilat, yazilan }

class _TarihliListe extends StatefulWidget {
  const _TarihliListe({super.key, required this.tur, required this.api, required this.isGunu, required this.kisiAc});
  final _Tur tur;
  final Api api;
  final _IsGunu isGunu;
  final Future<void> Function(int, [Map<String, dynamic>?]) kisiAc;

  @override
  State<_TarihliListe> createState() => _TarihliListeState();
}

class _TarihliListeState extends State<_TarihliListe> {
  late String _hazir = widget.tur == _Tur.tahsilat ? 'otuz' : 'bugun';
  String? _bas;
  String? _bit;
  Map<String, dynamic>? _v;
  bool _yukleniyor = true;

  bool get _tahsilat => widget.tur == _Tur.tahsilat;

  @override
  void initState() {
    super.initState();
    widget.isGunu.yukle(widget.api).then((_) {
      if (mounted) _hazirSec(_hazir);
    });
  }

  void _hazirSec(String h) {
    setState(() => _hazir = h);
    final a = widget.isGunu.aralik(h);
    if (a == null) {
      _bas ??= widget.isGunu.bugun;
      _bit ??= widget.isGunu.bugun;
      setState(() => _yukleniyor = false);
      return;
    }
    _bas = a.$1;
    _bit = a.$2;
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await widget.api.get(
        _tahsilat ? '/api/v1/receivables/tahsilatlar' : '/api/v1/reports/borca-yazilanlar',
        sorgu: {'from': ?_bas, 'to': ?_bit},
      );
      if (!mounted) return;
      final m = r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
      final rng = m['range'] is Map ? m['range'] as Map : const {};
      setState(() {
        _v = m;
        if (rng['from'] != null) _bas = '${rng['from']}';
        if (rng['to'] != null) _bit = '${rng['to']}';
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2(_tahsilat ? 'Tahsilatlar yüklenemedi' : 'Borca yazılanlar yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _tarihSec(bool bas) async {
    final ilk = _gunu(bas ? _bas : _bit) ?? DateTime.now();
    final t = await showDatePicker(
      context: context,
      initialDate: ilk,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('tr', 'TR'),
      helpText: bas ? 'Başlangıç' : 'Bitiş',
    );
    if (t == null || !mounted) return;
    setState(() => bas ? _bas = _ymd(t) : _bit = _ymd(t));
  }

  @override
  Widget build(BuildContext context) {
    final eylemler = <Widget>[
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Wrap(spacing: 4, runSpacing: 4, children: [
          for (final (k, ad) in _hazirlar)
            Material(
              color: _hazir == k ? Renk.markaAcik : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _hazirSec(k),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(ad, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _hazir == k ? Renk.marka : Renk.ikinci)),
                ),
              ),
            ),
        ]),
      ),
      if (_hazir == 'ozel')
        Row(mainAxisSize: MainAxisSize.min, children: [
          _tarihDugmesi(_bas, () => _tarihSec(true), 'Başlangıç'),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
          _tarihDugmesi(_bit, () => _tarihSec(false), 'Bitiş'),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 34)),
            onPressed: _yukleniyor ? null : _yukle,
            child: _yukleniyor
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Getir'),
          ),
        ]),
    ];

    return _Kart(
      baslik: _tahsilat ? 'Tahsil edilen borçlar' : 'Borca yazılanlar',
      eylemler: eylemler,
      child: _v == null
          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          : (_tahsilat ? _tahsilatIcerik(_v!) : _yazilanIcerik(_v!)),
    );
  }

  Widget _tarihDugmesi(String? ymd, VoidCallback bas, String etiket) => Semantics(
        label: etiket,
        button: true,
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: bas,
          child: Container(
            width: 144,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined, size: 14, color: Renk.soluk),
              const SizedBox(width: 6),
              Text(ymd == null ? etiket : () {
                final t = _gunu(ymd)!;
                return '${_iki(t.day)}.${_iki(t.month)}.${t.year}';
              }(), style: const TextStyle(fontSize: 13)),
            ]),
          ),
        ),
      );

  Widget _acikGunUyarisi(Map rng) {
    final acik = rng['acik_gun']?.toString();
    final bit = rng['to']?.toString();
    if (acik == null || acik.isEmpty || bit == null || bit.compareTo(acik) < 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Renk.uyariZemin.carp(.5),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 13, color: Renk.uyari),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Gün sonu alınmadı — açık gün ($acik) gece yarısı geçse de sürüyor.', style: TextStyle(fontSize: 12, color: Renk.uyari)),
        ),
      ]),
    );
  }

  Widget _ozetKutulari(List<Widget> kutular) => LayoutBuilder(builder: (context, k) {
        final kutu = [
          for (final c in kutular)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Renk.ic.withValues(alpha: .5), borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
              child: c,
            ),
        ];
        if (MediaQuery.sizeOf(context).width < 640) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < kutu.length; i++) ...[if (i > 0) const SizedBox(height: 12), kutu[i]],
          ]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < kutu.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: kutu[i])],
          ]),
        );
      });

  static final _ozetBaslik = TextStyle(fontSize: 12, color: Renk.ikinci);

  Widget _tahsilatIcerik(Map<String, dynamic> v) {
    final rng = v['range'] is Map ? v['range'] as Map : const {};
    final yontemler = (v['by_method'] as List? ?? const []).whereType<Map>().toList()
      ..sort((a, b) => tamSayi(b['amount_minor']).compareTo(tamSayi(a['amount_minor'])));
    final satirlar = (v['rows'] as List? ?? const []).whereType<Map>().toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _acikGunUyarisi(rng),
      Padding(
        padding: const EdgeInsets.all(16),
        child: _ozetKutulari([
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tahsil edilen borç', style: _ozetBaslik),
            Text(para(tamSayi(v['total_minor'])), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Renk.basari)),
            Text(_aralikEtiketi(rng['from']?.toString(), rng['to']?.toString()), style: TextStyle(fontSize: 11, color: Renk.ikinci)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('İşlem sayısı', style: _ozetBaslik),
            Text('${tamSayi(v['count'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ödeme yöntemine göre', style: _ozetBaslik),
            const SizedBox(height: 4),
            if (yontemler.isEmpty) const Text('—'),
            for (final y in yontemler)
              Row(children: [
                Expanded(child: Text('${y['label'] ?? 'Diğer'} (${tamSayi(y['count'])})', style: const TextStyle(fontSize: 13))),
                Text(para(tamSayi(y['amount_minor'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
          ]),
        ]),
      ),
      if (v['kesildi'] == true)
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Liste çok uzun; aralığı daraltın.', style: TextStyle(fontSize: 12, color: Renk.uyari)),
        ),
      if (satirlar.isEmpty && !_yukleniyor)
        const _Bos(
          ikon: Icons.account_balance_wallet_outlined,
          baslik: 'Bu aralıkta borç tahsilatı yok',
          metin: 'Borçlulardan tahsilat aldıkça kimden, ne zaman, ne ile ve ne kadar alındığı burada listelenir.',
        )
      else if (satirlar.isNotEmpty)
        _Tablo(
          enAz: 720,
          sutunlar: const [
            _Sutun('Şahıs', 3),
            _Sutun('Tarih', 2),
            _Sutun('Yöntem', 2),
            _Sutun('Alan', 2),
            _Sutun('Tahsilat', 2, hiza: TextAlign.right),
            _Sutun('Kalan borç', 2, hiza: TextAlign.right),
          ],
          satirlar: [
            for (final s in satirlar)
              [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  InkWell(
                    onTap: () => widget.kisiAc(tamSayi(s['receivable_id'])),
                    child: Text('${s['name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (s['note'] != null && '${s['note']}'.isNotEmpty) Text('${s['note']}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                ]),
                Text(_kisaTarih(s['created_at']), style: const TextStyle(fontSize: 13)),
                Align(alignment: Alignment.centerLeft, child: Rozet('${s['method_label'] ?? 'Diğer'}', renk: Renk.ikinci)),
                Text('${s['performed_by'] ?? '—'}', style: const TextStyle(fontSize: 13)),
                Text(para(tamSayi(s['amount_minor'])),
                    textAlign: TextAlign.right, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.basari)),
                Text(para(tamSayi(s['balance_after_minor'])),
                    textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: tamSayi(s['balance_after_minor']) > 0 ? Renk.hata : Renk.ikinci)),
              ],
          ],
        ),
    ]);
  }

  Widget _yazilanIcerik(Map<String, dynamic> v) {
    if (v['enabled'] == false) {
      return const _Bos(
        ikon: Icons.inbox_outlined,
        baslik: 'Borç sistemi kapalı',
        metin: 'Ayarlar → Eklentiler\'den borç/cari sistemini açtığınızda burada görünür.',
      );
    }
    final rng = v['range'] is Map ? v['range'] as Map : const {};
    final kisiler = (v['kisiler'] as List? ?? const []).whereType<Map>().toList();
    final satirlar = (v['rows'] as List? ?? const []).whereType<Map>().toList();
    final araBaslik = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: 1);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _acikGunUyarisi(rng),
      Padding(
        padding: const EdgeInsets.all(16),
        child: _ozetKutulari([
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Toplam borca yazılan', style: _ozetBaslik),
            Text(para(tamSayi(v['total_minor'])), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Renk.hata)),
            Text('Ciroda var · kasaya girmedi', style: TextStyle(fontSize: 11, color: Renk.ikinci)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kişi · işlem', style: _ozetBaslik),
            Text('${tamSayi(v['kisi'])} · ${tamSayi(v['count'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Aralık', style: _ozetBaslik),
            Text(_aralikEtiketi(rng['from']?.toString(), rng['to']?.toString()), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
      if (tamSayi(v['count']) == 0)
        const _Bos(
          ikon: Icons.inbox_outlined,
          baslik: 'Bu aralıkta borca yazılan yok',
          metin: 'Kasada bir hesap şahsa borç olarak yazıldıkça kime, ne zaman, ne kadar yazıldığı burada listelenir.',
        )
      else ...[
        Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 6), child: Text('KİŞİ BAZINDA', style: araBaslik)),
        _Tablo(
          enAz: 520,
          sutunlar: const [
            _Sutun('Şahıs', 3),
            _Sutun('İşlem', 1, hiza: TextAlign.center),
            _Sutun('Borca yazılan', 2, hiza: TextAlign.right),
            _Sutun('Güncel borç', 2, hiza: TextAlign.right),
          ],
          satirlar: [
            for (final k in kisiler)
              [
                InkWell(
                  onTap: () => widget.kisiAc(tamSayi(k['receivable_id'])),
                  child: Text('${k['name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Text('${tamSayi(k['count'])}', textAlign: TextAlign.center),
                Text(para(tamSayi(k['amount_minor'])), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: Renk.hata)),
                Text(para(tamSayi(k['balance_minor'])),
                    textAlign: TextAlign.right, style: TextStyle(color: tamSayi(k['balance_minor']) > 0 ? Renk.hata : Renk.ikinci)),
              ],
          ],
        ),
        Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 6), child: Text('İŞLEMLER', style: araBaslik)),
        _Tablo(
          enAz: 720,
          sutunlar: const [
            _Sutun('Şahıs', 3),
            _Sutun('Tarih', 2),
            _Sutun('Nereden', 2),
            _Sutun('Yazan', 2),
            _Sutun('Borca yazılan', 2, hiza: TextAlign.right),
          ],
          satirlar: [
            for (final s in satirlar)
              [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  InkWell(
                    onTap: () => widget.kisiAc(tamSayi(s['receivable_id'])),
                    child: Text('${s['name'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  if (s['reason'] != null && '${s['reason']}'.isNotEmpty) Text('${s['reason']}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                ]),
                Text(_kisaTarih(s['created_at']), style: const TextStyle(fontSize: 13)),
                Text('${s['kaynak'] ?? '—'}${s['order_id'] != null ? ' · #${s['order_id']}' : ''}', style: const TextStyle(fontSize: 13)),
                Text('${s['performed_by'] ?? '—'}', style: const TextStyle(fontSize: 13)),
                Text(para(tamSayi(s['amount_minor'])), textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700, color: Renk.hata)),
              ],
          ],
        ),
        const SizedBox(height: 12),
      ],
    ]);
  }
}

/* ═════════════ Detay çekmecesi (§6.3) ═════════════ */

class _Detay extends StatefulWidget {
  const _Detay({required this.id, this.ilk, required this.api, required this.can, required this.listeyiYenile});
  final int id;
  final Map<String, dynamic>? ilk;
  final Api api;
  final bool Function(String) can;
  final Future<void> Function() listeyiYenile;

  @override
  State<_Detay> createState() => _DetayState();
}

class _DetayState extends State<_Detay> {
  Map<String, dynamic>? _d;
  final Set<String> _acik = {};

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await widget.api.get('/api/v1/receivables/${widget.id}');
      if (mounted) setState(() => _d = r is Map ? r.cast<String, dynamic>() : const {});
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Şahıs detayı yüklenemedi', e.mesaj, hata: true);
    }
  }

  Map get _r => _d?['receivable'] is Map ? _d!['receivable'] as Map : (widget.ilk ?? const {});
  int get _bakiye => tamSayi(_r['balance_minor']);

  Future<void> _devir() async {
    final ok = await pencereAc<bool>(context: context, builder: (_) => _DevirPenceresi(kayit: _r, api: widget.api));
    if (ok == true && mounted) await Future.wait([_yukle(), widget.listeyiYenile()]);
  }

  Future<void> _tahsilat() async {
    final ok = await pencereAc<bool>(
      context: context,
      builder: (_) => _TahsilatPenceresi(kayit: _r, borcAdisyonlari: _liste('debt_orders'), api: widget.api),
    );
    if (ok == true && mounted) await Future.wait([_yukle(), widget.listeyiYenile()]);
  }

  void _kasayaGit() {
    // Web: /panel/kasa?sekme=borclar&borc={id} — kasa Borçlar sekmesini bu şahısla açar.
    kasaBorcIstegi.value = widget.id;
    ekranIstegi.value = PosEkrani.kasa;
    Navigator.pop(context);
  }

  List<Map> _liste(String k) => (_d?[k] as List? ?? const []).whereType<Map>().toList();

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final hareketler = _liste('transactions');
    final borclar = _liste('debt_orders');
    final gecmis = _liste('history_orders').where((o) => o['debt_minor'] == null).toList();
    final ozet = d?['history_summary'] is Map ? d!['history_summary'] as Map : const {};
    final sonTahsilat = hareketler.where((t) => t['type'] == 'payment').firstOrNull;
    final dar = MediaQuery.sizeOf(context).width < 640;

    final eylemler = <Widget>[
      if (widget.can('receivables.collect'))
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _bakiye <= 0 ? null : _kasayaGit,
          icon: const Icon(Icons.shopping_cart_outlined, size: 16),
          label: const Text('Kasada tahsil et'),
        ),
      if (widget.can('receivables.update'))
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: d == null ? null : _devir,
          icon: const Icon(Icons.history_rounded, size: 16),
          label: const Text('Eski (defter) borcu ekle'),
        ),
      if (widget.can('receivables.collect') && _bakiye > 0)
        TextButton(
          onPressed: d == null ? null : _tahsilat,
          child: const Text('Kasaya gitmeden hızlı kaydet', style: TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
        ),
    ];

    final bakiyeMetni = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('Güncel bakiye (borç)', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      Text(d == null && widget.ilk == null ? '…' : para(_bakiye),
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _bakiye > 0 ? Renk.hata : Renk.basari)),
      if (sonTahsilat != null)
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Son tahsilat: '),
          TextSpan(text: para(-tamSayi(sonTahsilat['amount_minor'])), style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' · ${_tarihSaat(sonTahsilat['created_at'])}'),
        ]), style: TextStyle(fontSize: 12, color: Renk.ikinci))
      else if (d != null)
        Text('Henüz tahsilat yapılmadı', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
    ]);
    final eylemSutunu = Column(crossAxisAlignment: dar ? CrossAxisAlignment.stretch : CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < eylemler.length; i++) ...[if (i > 0) const SizedBox(height: 6), eylemler[i]],
    ]);
    final bakiyeBlok = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
      child: dar
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              bakiyeMetni,
              if (eylemler.isNotEmpty) ...[const SizedBox(height: 12), eylemSutunu],
            ])
          : Row(children: [
              Expanded(child: bakiyeMetni),
              if (eylemler.isNotEmpty) ...[const SizedBox(width: 12), eylemSutunu],
            ]),
    );

    int qty(Map o) => (o['items'] as List? ?? const []).whereType<Map>().fold<int>(0, (t, k) => t + tamSayi(k['qty']));
    final ziyaretToplam = borclar.fold<int>(0, (t, o) => t + tamSayi(o['debt_amount_minor'] ?? o['total_minor']));

    return ListView(padding: const EdgeInsets.all(16), children: [
      bakiyeBlok,
      const SizedBox(height: 20),
      _BolumBasligi('Ziyaretler ve harcamalar', borclar.isEmpty ? null : '${borclar.length} kayıt · ${para(ziyaretToplam)}'),
      if (d == null)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (borclar.isEmpty)
        const _Bos(ikon: Icons.content_paste_rounded, baslik: 'Kayıt yok', metin: 'Bu şahsa taşınmış adisyon yok.', kucuk: true)
      else
        for (final o in borclar)
          _Katlanir(
            acik: _acik.contains('b${o['id']}'),
            degistir: () => setState(() => _acik.contains('b${o['id']}') ? _acik.remove('b${o['id']}') : _acik.add('b${o['id']}')),
            ust: (o['closed_at'] ?? o['created_at']) == null ? 'Adisyon #${o['id']}' : _ziyaret(o['closed_at'] ?? o['created_at']),
            alt: '#${o['id']} · ${o['table_name'] ?? o['channel_label'] ?? '—'}${qty(o) > 0 ? ' · ${qty(o)} ürün' : ''}',
            tutar: para(tamSayi(o['debt_amount_minor'] ?? o['total_minor'])),
            renk: Renk.hata,
            kalemler: (o['items'] as List? ?? const []).whereType<Map>().toList(),
            bosMetin: 'Bu adisyonun kalem dökümü yok.',
            ikramGoster: true,
          ),
      const SizedBox(height: 20),
      _BolumBasligi(
        'Ödenen siparişler (borçsuz kapananlar)',
        gecmis.isEmpty ? null : '${gecmis.length} sipariş · ${para(tamSayi(ozet['paid_total_minor']))}',
      ),
      if (d != null && gecmis.isEmpty)
        const _Bos(ikon: Icons.content_paste_rounded, baslik: 'Ödenmiş sipariş yok', metin: 'Bu kişi adına açılıp kasada ödenmiş bir adisyon henüz yok.', kucuk: true)
      else
        for (final o in gecmis)
          _Katlanir(
            acik: _acik.contains('g${o['id']}'),
            degistir: () => setState(() => _acik.contains('g${o['id']}') ? _acik.remove('g${o['id']}') : _acik.add('g${o['id']}')),
            ust: _tarihSaat(o['closed_at']),
            alt: [
              '#${o['id']} · ${o['status_label'] ?? ''}',
              if ((o['methods'] as List? ?? const []).isNotEmpty) (o['methods'] as List).map(_yontemEtiketi).join(', '),
              if (qty(o) > 0) '${qty(o)} ürün',
            ].join(' · '),
            tutar: para(tamSayi(o['total_minor'])),
            renk: Renk.basari,
            kalemler: (o['items'] as List? ?? const []).whereType<Map>().toList(),
            bosMetin: 'Kalem dökümü yok.',
            ikramGoster: false,
          ),
      const SizedBox(height: 20),
      const _BolumBasligi('Hareket geçmişi', null),
      if (d != null && hareketler.isEmpty)
        const _Bos(ikon: Icons.sync_rounded, baslik: 'Hareket yok', metin: 'Henüz borç/tahsilat kaydı yok.', kucuk: true)
      else
        for (final h in hareketler) _hareket(h),
    ]);
  }

  Widget _hareket(Map h) {
    final tur = h['type']?.toString();
    final baslik = h['reverses_id'] != null
        ? 'İskonto geri alındı'
        : switch (tur) {
            'debt_transfer' => 'Adisyon borcu',
            'payment' => 'Tahsilat',
            'discount' => 'Borç iskontosu',
            'adjustment' => 'Düzeltme',
            'opening' => 'Devir borcu (eski defter)',
            _ => '$tur',
          };
    final ekler = [
      if (h['order_id'] != null) '#${h['order_id']}',
      if (h['method'] != null) _yontemEtiketi(h['method']),
      if (tur == 'discount' && h['reversed'] == true) 'geri alındı',
      if (tur == 'discount' && h['locked'] == true) 'ödeme sonrası kilitli',
    ];
    final tutar = tamSayi(h['amount_minor']);
    final not = h['note']?.toString();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([baslik, ...ekler].join(' · '), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text(_tarihSaat(h['created_at']), style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            Text('${h['performed_by'] ?? '—'}${not != null && not.isNotEmpty ? ' · $not' : ''}', style: TextStyle(fontSize: 12, color: Renk.soluk)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(tutar > 0 ? '+${para(tutar)}' : para(tutar),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tutar > 0 ? Renk.hata : Renk.basari)),
          Text('kalan ${para(tamSayi(h['balance_after_minor']))}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        ]),
      ]),
    );
  }
}

class _BolumBasligi extends StatelessWidget {
  const _BolumBasligi(this.baslik, this.sag);
  final String baslik;
  final String? sag;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(baslik, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if (sag != null) Text(sag!, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        ]),
      );
}

class _Katlanir extends StatelessWidget {
  const _Katlanir({
    required this.acik,
    required this.degistir,
    required this.ust,
    required this.alt,
    required this.tutar,
    required this.renk,
    required this.kalemler,
    required this.bosMetin,
    required this.ikramGoster,
  });
  final bool acik;
  final VoidCallback degistir;
  final String ust;
  final String alt;
  final String tutar;
  final Color renk;
  final List<Map> kalemler;
  final String bosMetin;
  final bool ikramGoster;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: degistir,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Icon(acik ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded, size: 18, color: Renk.soluk),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ust, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(alt, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                  ]),
                ),
                Text(tutar, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: renk)),
              ]),
            ),
          ),
          if (acik)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
              child: kalemler.isEmpty
                  ? Text(bosMetin, style: TextStyle(fontSize: 12, color: Renk.soluk))
                  : Column(children: [
                      for (final k in kalemler)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(5)),
                              child: Text('${tamSayi(k['qty'])}×', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: '${k['name'] ?? ''}'),
                                if (k['variant_name'] != null) TextSpan(text: ' (${k['variant_name']})', style: TextStyle(color: Renk.ikinci)),
                                if (ikramGoster && k['is_comp'] == true) TextSpan(text: ' · ikram', style: TextStyle(color: Renk.bilgi)),
                              ]), style: const TextStyle(fontSize: 13)),
                            ),
                            Text(para(tamSayi(k['line_total_minor'])),
                                style: TextStyle(
                                  fontSize: 13,
                                  decoration: ikramGoster && k['is_comp'] == true ? TextDecoration.lineThrough : null,
                                )),
                          ]),
                        ),
                    ]),
            ),
        ]),
      );
}

/* ═════════════ Oluştur / Düzenle (§6.1) ═════════════ */

class _SahisFormu extends StatefulWidget {
  const _SahisFormu({this.kayit, required this.api});
  final Map<String, dynamic>? kayit;
  final Api api;

  @override
  State<_SahisFormu> createState() => _SahisFormuState();
}

class _SahisFormuState extends State<_SahisFormu> {
  late final _ad = TextEditingController(text: widget.kayit?['name']?.toString() ?? '');
  late final _tel = TextEditingController(text: widget.kayit?['phone']?.toString() ?? '');
  late final _eposta = TextEditingController(text: widget.kayit?['email']?.toString() ?? '');
  late final _not = TextEditingController(text: widget.kayit?['note']?.toString() ?? '');
  Map<String, String> _hatalar = const {};
  bool _mesgul = false;

  @override
  void dispose() {
    for (final c in [_ad, _tel, _eposta, _not]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _bos(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _gonder() async {
    if (_mesgul) return;
    setState(() {
      _mesgul = true;
      _hatalar = const {};
    });
    final govde = {'name': _ad.text.trim(), 'phone': _bos(_tel), 'email': _bos(_eposta), 'note': _bos(_not)};
    try {
      final k = widget.kayit;
      if (k == null) {
        await widget.api.post('/api/v1/receivables', govde);
      } else {
        await widget.api.put('/api/v1/receivables/${k['id']}', govde);
      }
      if (!mounted) return;
      context.bildir2(k == null ? 'Şahıs oluşturuldu' : 'Şahıs güncellendi', k == null ? '${govde['name']} eklendi.' : '${govde['name']} kaydedildi.');
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (!mounted) return;
      final h = e.govde?['errors'];
      if (e.kod == 422 && h is Map && h.isNotEmpty) {
        setState(() => _hatalar = {for (final x in h.entries) '${x.key}': x.value is List && (x.value as List).isNotEmpty ? '${(x.value as List).first}' : '${x.value}'});
      } else {
        context.bildir2('Kaydedilemedi', e.mesaj.isEmpty ? 'Beklenmeyen bir hata oluştu.' : e.mesaj, hata: true);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(18), children: [
            FormAlani(
              etiket: 'Ad',
              zorunlu: true,
              hata: _hatalar['name'],
              child: TextField(controller: _ad, autofocus: true, decoration: const InputDecoration(hintText: 'ör. Ahmet Bey / Şirket adı'), onSubmitted: (_) => _gonder()),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Telefon',
              hata: _hatalar['phone'],
              child: TextField(controller: _tel, keyboardType: TextInputType.phone, onSubmitted: (_) => _gonder()),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'E-posta',
              hata: _hatalar['email'],
              child: TextField(controller: _eposta, keyboardType: TextInputType.emailAddress, onSubmitted: (_) => _gonder()),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Not',
              hata: _hatalar['note'],
              child: TextField(controller: _not, decoration: const InputDecoration(hintText: 'ör. Komşu esnaf, düzenli müşteri…'), onSubmitted: (_) => _gonder()),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _mesgul ? null : _gonder,
              child: _mesgul
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(widget.kayit == null ? 'Oluştur' : 'Kaydet'),
            ),
          ]),
        ),
      ]);
}

/* ═════════════ Hesabı sil (§6.2) ═════════════ */

class _SilPenceresi extends StatefulWidget {
  const _SilPenceresi({required this.kayit, required this.api});
  final Map<String, dynamic> kayit;
  final Api api;

  @override
  State<_SilPenceresi> createState() => _SilPenceresiState();
}

class _SilPenceresiState extends State<_SilPenceresi> {
  bool _mesgul = false;

  Future<void> _sil() async {
    setState(() => _mesgul = true);
    try {
      await widget.api.delete('/api/v1/receivables/${widget.kayit['id']}');
      if (!mounted) return;
      context.bildir2('Hesap silindi', '${widget.kayit['name'] ?? ''}');
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Silinemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final engel = widget.kayit['delete_block']?.toString();
    final engelli = engel != null && engel.isNotEmpty;
    return AlertDialog(
      title: const Text('Hesabı sil'),
      content: SizedBox(
        width: 384,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: '${widget.kayit['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' adlı hesap silinsin mi?'),
          ])),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: engelli ? Renk.uyariZemin : Renk.hataZemin,
              borderRadius: koseYuvarlak,
              border: Border.all(color: engelli ? Renk.uyariKenar : Renk.hataKenar),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(engelli ? Icons.warning_amber_rounded : Icons.delete_outline_rounded, size: 16, color: engelli ? Renk.uyari : Renk.hata),
              const SizedBox(width: 8),
              Expanded(
                child: engelli
                    ? Text(engel, style: TextStyle(fontSize: 13, color: Renk.uyari))
                    : Text.rich(TextSpan(children: [
                        TextSpan(text: 'Bu hesabın borcu ve geçmiş kaydı yok; kayıt '),
                        TextSpan(text: 'tamamen silinir', style: TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' ve geri alınamaz.'),
                      ]), style: TextStyle(fontSize: 13, color: Renk.hata)),
              ),
            ]),
          ),
        ]),
      ),
      actions: engelli
          ? [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))]
          : [
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Hayır, vazgeç')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Renk.hata),
                onPressed: _mesgul ? null : _sil,
                child: _mesgul
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Evet, sil'),
              ),
            ],
    );
  }
}

/* ═════════════ Eski (defter) borcu ekle (§6.4) ═════════════ */

class _DevirPenceresi extends StatefulWidget {
  const _DevirPenceresi({required this.kayit, required this.api});
  final Map kayit;
  final Api api;

  @override
  State<_DevirPenceresi> createState() => _DevirPenceresiState();
}

class _DevirPenceresiState extends State<_DevirPenceresi> {
  final _tutar = TextEditingController();
  final _not = TextEditingController();
  bool _mesgul = false;

  int get _eski => tamSayi(widget.kayit['balance_minor']);

  @override
  void dispose() {
    _tutar.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _ekle() async {
    final t = _tutarOku(_tutar.text);
    if (t <= 0) {
      context.bildir2('Tutar geçersiz', 'Pozitif bir tutar girin.', hata: true);
      return;
    }
    setState(() => _mesgul = true);
    try {
      await widget.api.post('/api/v1/receivables/${widget.kayit['id']}/devir-borc', {
        'amount_minor': t,
        'note': _not.text.trim().isEmpty ? null : _not.text.trim(),
      });
      if (!mounted) return;
      context.bildir2('Eski borç eklendi', '${para(t)} · yeni borç ${para(_eski + t)}.');
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Eklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _tutarOku(_tutar.text);
    return AlertDialog(
      title: const Text('Eski (defter) borcu ekle'),
      content: SizedBox(
        width: 384,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Renk.bilgiZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.bilgiKenar)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Renk.bilgi),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.kayit['name'] ?? ''} için sisteme geçmeden önceki defter borcunu girin. Bu tutar ciroya ve tahsilata girmez, kasa çekmecesini etkilemez — yalnız şahsın borcuna eklenir.',
                    style: TextStyle(fontSize: 13, color: Renk.bilgi),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Eski borç tutarı (₺)',
              ipucu: 'Defterdeki kalan bakiye.',
              child: TextField(
                controller: _tutar,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: '0,00'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Açıklama',
              ipucu: 'Örn. “Defter devri — 01.09.2026 itibarıyla”.',
              child: TextField(controller: _not, decoration: const InputDecoration(hintText: 'İsteğe bağlı')),
            ),
            const SizedBox(height: 12),
            Text('Güncel borç ${para(_eski)} → eklendikten sonra ${para(_eski + (t > 0 ? t : 0))}',
                style: TextStyle(fontSize: 13, color: Renk.ikinci)),
          ]),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _mesgul ? null : _ekle,
          child: _mesgul
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Borcu ekle'),
        ),
      ],
    );
  }
}

/* ═════════════ Tahsilat al — hızlı kayıt (§6.5) ═════════════ */

class _TahsilatPenceresi extends StatefulWidget {
  const _TahsilatPenceresi({required this.kayit, required this.borcAdisyonlari, required this.api});
  final Map kayit;
  final List<Map> borcAdisyonlari;
  final Api api;

  @override
  State<_TahsilatPenceresi> createState() => _TahsilatPenceresiState();
}

class _TahsilatPenceresiState extends State<_TahsilatPenceresi> {
  late final _tutar = TextEditingController(text: para(_bakiye, simge: false));
  final _not = TextEditingController();
  String _yontem = 'cash';
  bool _mesgul = false;

  int get _bakiye => tamSayi(widget.kayit['balance_minor']);

  @override
  void dispose() {
    _tutar.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _tahsilEt() async {
    final t = _tutarOku(_tutar.text);
    if (t <= 0) {
      context.bildir2('Tutar geçersiz', 'Pozitif bir tutar girin.', hata: true);
      return;
    }
    if (t > _bakiye) {
      context.bildir2('Tutar borcu aşıyor', 'Güncel borç ${para(_bakiye)}.', hata: true);
      return;
    }
    setState(() => _mesgul = true);
    try {
      await widget.api.post('/api/v1/receivables/${widget.kayit['id']}/collect', {
        'amount_minor': t,
        'method': _yontem,
        'note': _not.text.trim().isEmpty ? null : _not.text.trim(),
      });
      if (!mounted) return;
      final kalan = _bakiye - t;
      context.bildir2('Tahsilat kaydedildi', '${para(t)} alındı · kalan borç ${para(kalan < 0 ? 0 : kalan)}.');
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Tahsilat kaydedilemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final adisyonlar = widget.borcAdisyonlari;
    return AlertDialog(
      title: const Text('Tahsilat al'),
      content: SizedBox(
        width: 384,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Kalan borç: ${para(_bakiye)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (adisyonlar.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 224),
                decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(10), children: [
                  Text('Borcu oluşturan adisyonlar (${adisyonlar.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.ikinci)),
                  for (final o in adisyonlar)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_ziyaret(o['closed_at'] ?? o['created_at']), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              Text('#${o['id']} · ${o['table_name'] ?? o['channel_label'] ?? '—'}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                            ]),
                          ),
                          Text(para(tamSayi(o['debt_amount_minor'] ?? o['total_minor'])),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Renk.hata)),
                        ]),
                        for (final k in (o['items'] as List? ?? const []).whereType<Map>())
                          Text('${tamSayi(k['qty'])}× ${k['name'] ?? ''}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                      ]),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Tutar (₺)',
              zorunlu: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _tutar,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(hintText: 'ör. 150,00'),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  OutlinedButton(onPressed: () => _tutar.text = para(_bakiye, simge: false), child: const Text('Tamamı')),
                  const SizedBox(width: 6),
                  OutlinedButton(onPressed: () => _tutar.text = para((_bakiye / 2).ceil(), simge: false), child: const Text('½')),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Yöntem',
              zorunlu: true,
              child: Secici<String>(
                deger: _yontem,
                secenekler: const [('cash', 'Nakit'), ('card', 'Kart'), ('transfer', 'Havale/EFT'), ('other', 'Diğer')],
                degisti: (v) => setState(() => _yontem = v ?? 'cash'),
              ),
            ),
            const SizedBox(height: 14),
            FormAlani(etiket: 'Not', child: TextField(controller: _not)),
          ]),
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _mesgul ? null : _tahsilEt,
          child: _mesgul
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Tahsil et'),
        ),
      ],
    );
  }
}

/* ═════════════ Ortak parçalar ═════════════ */

/// web BaseCard flush: başlık solda, eylemler sağda.
class _Kart extends StatelessWidget {
  const _Kart({required this.baslik, this.eylemler = const [], required this.child});
  final String baslik;
  final List<Widget> eylemler;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(baslik, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (eylemler.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: eylemler),
              ],
            ),
          ),
          child,
        ]),
      );
}

class _Bos extends StatelessWidget {
  const _Bos({required this.ikon, required this.baslik, required this.metin, this.kucuk = false});
  final IconData ikon;
  final String baslik;
  final String metin;
  final bool kucuk;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: kucuk ? 16 : 40, horizontal: 16),
        child: Column(children: [
          Icon(ikon, size: kucuk ? 24 : 32, color: Renk.soluk),
          const SizedBox(height: 8),
          Text(baslik, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(metin, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
        ]),
      );
}

class _Sutun {
  const _Sutun(this.ad, this.esneklik, {this.hiza = TextAlign.left});
  final String ad;
  final int esneklik;
  final TextAlign hiza;
}

/// web DataTable: dar ekranda yatay kayar (en az [enAz] px).
class _Tablo extends StatelessWidget {
  const _Tablo({required this.sutunlar, required this.satirlar, this.enAz = 720});
  final List<_Sutun> sutunlar;
  final List<List<Widget>> satirlar;
  final double enAz;

  Alignment _hiza(TextAlign h) => switch (h) {
        TextAlign.right => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      };

  Widget _satir(List<Widget> hucreler, {bool baslik = false}) => Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: baslik ? 9 : 11),
        decoration: BoxDecoration(
          color: baslik ? Renk.ic : null,
          border: Border(bottom: BorderSide(color: Renk.cizgi)),
        ),
        child: Row(children: [
          for (var i = 0; i < sutunlar.length; i++)
            Expanded(
              flex: sutunlar[i].esneklik,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Align(alignment: _hiza(sutunlar[i].hiza), child: hucreler[i]),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, k) {
        final gen = k.maxWidth < enAz ? enAz : k.maxWidth;
        final tablo = SizedBox(
          width: gen,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _satir([
              for (final s in sutunlar)
                Text(s.ad, textAlign: s.hiza, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.ikinci)),
            ], baslik: true),
            for (final r in satirlar) _satir(r),
          ]),
        );
        return k.maxWidth < enAz ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: tablo) : tablo;
      });
}

class _Sayfalama extends StatelessWidget {
  const _Sayfalama({required this.sayfa, required this.son, required this.git});
  final int sayfa;
  final int son;
  final ValueChanged<int> git;

  @override
  Widget build(BuildContext context) {
    final pencere = son < 5 ? son : 5;
    var bas = sayfa - pencere ~/ 2;
    if (bas < 1) bas = 1;
    if (bas + pencere - 1 > son) bas = son - pencere + 1;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(tooltip: 'Önceki sayfa', onPressed: sayfa > 1 ? () => git(sayfa - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
      for (var n = bas; n < bas + pencere; n++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: n == sayfa
              ? FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(36, 34), padding: EdgeInsets.zero), onPressed: null, child: Text('$n'))
              : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(36, 34), padding: EdgeInsets.zero), onPressed: () => git(n), child: Text('$n')),
        ),
      IconButton(tooltip: 'Sonraki sayfa', onPressed: sayfa < son ? () => git(sayfa + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
    ]);
  }
}
