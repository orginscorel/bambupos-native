import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'ortak.dart';

/// ÖNCEKİ ADİSYONLAR — web /panel/siparisler/gecmis (Gecmis.vue) birebiri.
/// Şartname: /root/work/spec/onceki-adisyonlar.md.
///  - <1024 px kart listesi + altta sayfalama; ≥1024 px başlık satırı
///    (Yenile · tarih · sayfalama) + tablo.
///  - Arama kutusu ve hazır dönem çipleri web'de de YOK.
///  - Yoklama yok; yalnız Yenile / tarih / sayfa değişimi.
class GecmisEkrani extends StatefulWidget {
  const GecmisEkrani({super.key});

  @override
  State<GecmisEkrani> createState() => _GecmisEkraniState();
}

const _aylarKisa = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

DateTime? _t(Object? iso) => iso == null ? null : DateTime.tryParse('$iso')?.toLocal();
String _iki(int n) => n.toString().padLeft(2, '0');

/// "02 Eki 2026"
String _tarihKisa(Object? iso) {
  final t = _t(iso);
  return t == null ? '—' : '${_iki(t.day)} ${_aylarKisa[t.month - 1]} ${t.year}';
}

/// "14:32"
String _saatKisa(Object? iso) {
  final t = _t(iso);
  return t == null ? '' : '${_iki(t.hour)}:${_iki(t.minute)}';
}

/// "26 Ekim 2026 Pazartesi 14:32:05" (ipucu)
String _zamanTam(Object? iso) {
  final t = _t(iso);
  return t == null ? '' : '${t.day} ${_aylar[t.month - 1]} ${t.year} ${_gunler[t.weekday - 1]} ${_iki(t.hour)}:${_iki(t.minute)}:${_iki(t.second)}';
}

/// "26.10 14:32" (detay)
String _saatDetay(Object? iso) {
  final t = _t(iso);
  return t == null ? '—' : '${_iki(t.day)}.${_iki(t.month)} ${_iki(t.hour)}:${_iki(t.minute)}';
}

String _ymd(DateTime t) => '${t.year}-${_iki(t.month)}-${_iki(t.day)}';

IconData _turSimgesi(Object? tur) => switch (tur) {
      'masa' => Icons.qr_code_2_rounded,
      'sahis' => Icons.person_outline_rounded,
      _ => Icons.inventory_2_outlined,
    };

class _GecmisEkraniState extends State<GecmisEkrani> {
  List<Map<String, dynamic>> _satirlar = const [];
  int _sayfa = 1;
  int _sonSayfa = 1;
  DateTime? _gun;
  bool _yukleniyor = true;
  String? _hata;
  int? _basiliyor;

  late final Api _api = context.api;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    setState(() {
      _yukleniyor = true;
      _hata = null;
    });
    try {
      final r = await _api.get('/api/v1/orders/gecmis', sorgu: {
        if (_gun != null) 'gun': _ymd(_gun!),
        if (_sayfa > 1) 'sayfa': _sayfa,
      });
      if (!mounted) return;
      final m = r is Map ? r : const {};
      final s = m['sayfalama'] is Map ? m['sayfalama'] as Map : const {};
      setState(() {
        _satirlar = (m['satirlar'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _sonSayfa = tamSayi(s['son_sayfa'], 1);
        _sayfa = tamSayi(s['sayfa'], _sayfa);
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() {
        _hata = e.mesaj.isEmpty ? 'Liste alınamadı.' : e.mesaj;
        _satirlar = const [];
      });
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _sayfayaGit(int n) {
    if (n < 1 || n > _sonSayfa || n == _sayfa) return;
    _sayfa = n;
    _yukle();
  }

  Future<void> _tarihSec() async {
    final simdi = DateTime.now();
    final t = await showDatePicker(
      context: context,
      initialDate: _gun ?? simdi,
      firstDate: DateTime(2020),
      lastDate: simdi.add(const Duration(days: 1)),
      locale: const Locale('tr', 'TR'),
      helpText: 'İş günü',
    );
    if (t == null || !mounted) return;
    _gun = t;
    _sayfa = 1;
    _yukle();
  }

  Future<void> _fisBas(int id) async {
    if (_basiliyor != null) return;
    setState(() => _basiliyor = id);
    try {
      final r = await _api.post('/api/v1/orders/gecmis/$id/fis');
      if (mounted) context.bildir2('Fiş gönderildi', r is Map ? '${r['mesaj'] ?? ''}' : '');
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Fiş basılamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _basiliyor = null);
    }
  }

  Future<void> _detayAc(int id) => showDialog<void>(
        context: context,
        builder: (_) => _Detay(id: id, api: _api, fisBas: _fisBas, basiliyor: () => _basiliyor == id),
      );

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final genis = g >= 1024;
    final yan = g <= 560 ? 12.0 : 18.0;

    return ColoredBox(
      color: Renk.yuzey,
      child: genis ? _genis(yan) : _dar(yan, g),
    );
  }

  /* ── ≥1024: başlık satırı + tablo ── */

  Widget _genis(double yan) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(yan, 16, yan, 12),
        child: Row(children: [
          Text('Önceki adisyonlar', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Renk.yazi)),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
            onPressed: _yukleniyor ? null : _yukle,
            icon: const Icon(Icons.sync_rounded, size: 15),
            label: const Text('Yenile', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const Spacer(),
          _TarihKutusu(gun: _gun, bas: _tarihSec),
          const SizedBox(width: 10),
          _Sayfalama(sayfa: _sayfa, son: _sonSayfa, git: _sayfayaGit),
        ]),
      ),
      if (_hata != null) Padding(padding: EdgeInsets.fromLTRB(yan, 0, yan, 10), child: _HataKutusu(_hata!)),
      Expanded(child: _tablo(yan)),
    ]);
  }

  static const _sutunlar = <(String, double?)>[
    ('Adisyon No', 108),
    ('Masa', 210),
    ('Ürünler', null),
    ('Ürün Toplamı', 118),
    ('Tutar', 136),
    ('Ödeme Toplamı', 150),
    ('Kapanma Zamanı', 158),
    ('İşlemler', 112),
  ];

  Widget _hucre(int i, Widget c, double yan) {
    final (_, gen) = _sutunlar[i];
    final ic = Padding(
      padding: EdgeInsets.only(left: i == 0 ? yan : 12, right: i == _sutunlar.length - 1 ? yan : 12),
      child: Center(child: c),
    );
    return gen == null ? Expanded(child: ic) : SizedBox(width: gen + (i == 0 || i == _sutunlar.length - 1 ? yan - 12 : 0), child: ic);
  }

  Widget _tablo(double yan) {
    final baslik = Container(
      height: 38,
      decoration: BoxDecoration(
        color: Renk.ic,
        border: Border(top: BorderSide(color: Renk.cizgi), bottom: BorderSide(color: Renk.cizgiKoyu)),
      ),
      child: Row(children: [
        for (var i = 0; i < _sutunlar.length; i++)
          _hucre(
            i,
            Text(_sutunlar[i].$1.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.ikinci, letterSpacing: .66)),
            yan,
          ),
      ]),
    );

    Widget govde;
    if (_yukleniyor) {
      govde = Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.soluk))));
    } else if (_satirlar.isEmpty) {
      govde = Padding(
        padding: EdgeInsets.symmetric(vertical: 48, horizontal: 20),
        child: Column(children: [
          Icon(Icons.content_paste_rounded, size: 32, color: Renk.soluk),
          SizedBox(height: 10),
          Text('Bu dönemde kapanmış adisyon yok', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.yazi)),
          SizedBox(height: 4),
          Text('Dönemi değiştirin ya da masa/kişi aramasını temizleyin. Masada duran açık adisyonlar bu listede görünmez.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
        ]),
      );
    } else {
      govde = Column(children: [for (final s in _satirlar) _tabloSatiri(s, yan)]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      baslik,
      Expanded(child: SingleChildScrollView(child: govde)),
    ]);
  }

  Widget _tabloSatiri(Map<String, dynamic> s, double yan) {
    final id = tamSayi(s['id']);
    final urunler = (s['urunler'] as List? ?? const []).map((e) => '$e').toList();
    final fazla = tamSayi(s['urun_fazla']);
    final ek = (urunler.length > 3 ? urunler.length - 3 : 0) + fazla;
    final kisi = s['kisi'] == null ? null : tamSayi(s['kisi']);
    final basiliyor = _basiliyor == id;

    return _Hover(
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(children: [
          _hucre(0, Text('#${s['no'] ?? id}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)), yan),
          _hucre(
            1,
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
                child: Icon(_turSimgesi(s['tur']), size: 15, color: Renk.ikinci),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Text('${s['masa'] ?? 'Paket/Şahıs'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  if (kisi != null && kisi > 0) Text('$kisi kişi', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Renk.ikinci)),
                ]),
              ),
            ]),
            yan,
          ),
          _hucre(
            2,
            Tooltip(
              message: urunler.join(', ') + (ek > 0 ? ' — tümü için tıklayın' : ''),
              child: InkWell(
                borderRadius: koseYuvarlak,
                onTap: () => _detayAc(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final u in urunler.take(3)) Text(u, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Renk.yazi)),
                    if (ek > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(6)),
                        child: Text('+$ek', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.ikinci)),
                      ),
                  ]),
                ),
              ),
            ),
            yan,
          ),
          _hucre(3, Text('${tamSayi(s['urun_adedi'])}', style: const TextStyle(fontSize: 13.5)), yan),
          _hucre(4, Text(para(tamSayi(s['tutar_minor'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)), yan),
          _hucre(5, Text(para(tamSayi(s['tahsil_minor'])), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.basari)), yan),
          _hucre(
            6,
            Tooltip(
              message: _zamanTam(s['kapanma']),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_tarihKisa(s['kapanma']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(_saatKisa(s['kapanma']), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Renk.soluk)),
              ]),
            ),
            yan,
          ),
          _hucre(
            7,
            Container(
              decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
              clipBehavior: Clip.antiAlias,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _islemDugmesi(Icons.visibility_outlined, 'Adisyon detayı', () => _detayAc(id)),
                Container(width: 1, height: 34, color: Renk.cizgiKoyu),
                _islemDugmesi(Icons.print_outlined, 'Fişi yeniden bas', basiliyor ? null : () => _fisBas(id)),
              ]),
            ),
            yan,
          ),
        ]),
      ),
    );
  }

  Widget _islemDugmesi(IconData ikon, String ipucu, VoidCallback? bas) => Tooltip(
        message: ipucu,
        child: InkWell(
          onTap: bas,
          child: SizedBox(width: 40, height: 34, child: Icon(ikon, size: 18, color: bas == null ? Renk.cizgiKoyu : Renk.yazi)),
        ),
      );

  /* ── <1024: kart listesi + altta sayfalama ── */

  Widget _dar(double yan, double g) {
    final ust = g >= 640 ? 14.0 : 8.0;
    final alt = g >= 640 ? 26.0 : 14.0;
    return RefreshIndicator(
      onRefresh: _yukle,
      child: ListView(
        padding: EdgeInsets.fromLTRB(yan, ust, yan, alt + MediaQuery.paddingOf(context).bottom),
        children: [
          if (_hata != null) ...[_HataKutusu(_hata!), const SizedBox(height: 8)],
          if (_yukleniyor)
            Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.soluk))))
          else if (_satirlar.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40, horizontal: 12),
              child: Column(children: [
                Text('Bu dönemde kapanmış adisyon yok', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Dönemi değiştirin ya da aramayı temizleyin. Masada duran açık adisyonlar bu listede görünmez.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              ]),
            )
          else
            for (final s in _satirlar) Padding(padding: const EdgeInsets.only(bottom: 6), child: _kart(s)),
          const SizedBox(height: 12),
          Center(child: _Sayfalama(sayfa: _sayfa, son: _sonSayfa, git: _sayfayaGit)),
        ],
      ),
    );
  }

  Widget _kart(Map<String, dynamic> s) {
    final id = tamSayi(s['id']);
    final urunler = (s['urunler'] as List? ?? const []).map((e) => '$e').toList();
    final fazla = tamSayi(s['urun_fazla']);
    final kisi = s['kisi'] == null ? null : tamSayi(s['kisi']);
    final basiliyor = _basiliyor == id;

    return Container(
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                highlightColor: Renk.ic,
                onTap: () => _detayAc(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Text('#${s['no'] ?? id}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Icon(_turSimgesi(s['tur']), size: 14, color: Renk.ikinci),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text('${s['masa'] ?? 'Paket/Şahıs'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                      if (kisi != null && kisi > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(7)),
                          child: Text('$kisi kişi', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.ikinci)),
                        ),
                      ],
                      const Spacer(),
                      Text(para(tamSayi(s['tutar_minor'])), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 3),
                    Text('${tamSayi(s['urun_adedi'])} ürün · ${urunler.join(', ')}${fazla > 0 ? ', +$fazla' : ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.schedule_rounded, size: 13, color: Renk.soluk),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: _zamanTam(s['kapanma']),
                        child: Text.rich(TextSpan(children: [
                          TextSpan(text: _tarihKisa(s['kapanma']), style: TextStyle(fontWeight: FontWeight.w700, color: Renk.yazi)),
                          TextSpan(text: ' ${_saatKisa(s['kapanma'])}'),
                        ]), style: TextStyle(fontSize: 12.5, color: Renk.ikinci)),
                      ),
                      const Spacer(),
                      Text('Tahsil ${para(tamSayi(s['tahsil_minor']))}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Renk.basari)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
          Container(
            width: 44,
            decoration: BoxDecoration(border: Border(left: BorderSide(color: Renk.cizgi))),
            child: Opacity(
              opacity: basiliyor ? .5 : 1,
              child: Tooltip(
                message: 'Fişi yeniden bas',
                child: InkWell(onTap: basiliyor ? null : () => _fisBas(id), child: Icon(Icons.print_outlined, size: 17, color: Renk.ikinci)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/* ═════════════ Bileşenler ═════════════ */

class _Hover extends StatefulWidget {
  const _Hover({required this.child});
  final Widget child;

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _ustunde = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _ustunde = true),
        onExit: (_) => setState(() => _ustunde = false),
        child: ColoredBox(color: _ustunde ? Renk.ic : Colors.transparent, child: widget.child),
      );
}

class _HataKutusu extends StatelessWidget {
  const _HataKutusu(this.mesaj);
  final String mesaj;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: Renk.hataZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.hataKenar)),
        child: Text(mesaj, style: TextStyle(fontSize: 12.5, color: Renk.hata)),
      );
}

class _TarihKutusu extends StatelessWidget {
  const _TarihKutusu({required this.gun, required this.bas});
  final DateTime? gun;
  final VoidCallback bas;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'İş günü',
        button: true,
        child: InkWell(
          borderRadius: koseYuvarlak,
          onTap: bas,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_today_outlined, size: 15, color: Renk.soluk),
              const SizedBox(width: 8),
              Text(
                gun == null ? 'gg.aa.yyyy' : '${_iki(gun!.day)}.${_iki(gun!.month)}.${gun!.year}',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: gun == null ? Renk.soluk : Renk.yazi),
              ),
            ]),
          ),
        ),
      );
}

/// Web sayfalama öbeği: ‹ · en çok 5 sayı · ›.
class _Sayfalama extends StatelessWidget {
  const _Sayfalama({required this.sayfa, required this.son, required this.git});
  final int sayfa;
  final int son;
  final ValueChanged<int> git;

  @override
  Widget build(BuildContext context) {
    final s = son < 1 ? 1 : son;
    final pencere = s < 5 ? s : 5;
    var bas = sayfa - pencere ~/ 2;
    if (bas < 1) bas = 1;
    if (bas + pencere - 1 > s) bas = s - pencere + 1;

    Widget dugme(Widget c, VoidCallback? f, {bool secili = false, String? ipucu}) => Tooltip(
          message: ipucu ?? '',
          child: Opacity(
            opacity: f == null && !secili ? .4 : 1,
            child: Material(
              color: secili ? Renk.ic : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: secili ? BorderSide(color: Renk.cizgi) : BorderSide.none),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: secili ? null : f,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
                  child: Center(child: DefaultTextStyle.merge(style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Renk.yazi), child: c)),
                ),
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        dugme(const Icon(Icons.chevron_left_rounded, size: 18), sayfa > 1 ? () => git(sayfa - 1) : null, ipucu: 'Önceki sayfa'),
        for (var n = bas; n < bas + pencere; n++) dugme(Text('$n'), () => git(n), secili: n == sayfa),
        dugme(const Icon(Icons.chevron_right_rounded, size: 18), sayfa < son ? () => git(sayfa + 1) : null, ipucu: 'Sonraki sayfa'),
      ]),
    );
  }
}

/* ═════════════ Detay penceresi (§8) ═════════════ */

class _Detay extends StatefulWidget {
  const _Detay({required this.id, required this.api, required this.fisBas, required this.basiliyor});
  final int id;
  final Api api;
  final Future<void> Function(int) fisBas;
  final bool Function() basiliyor;

  @override
  State<_Detay> createState() => _DetayState();
}

class _DetayState extends State<_Detay> {
  Map<String, dynamic>? _d;
  bool _basiyor = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await widget.api.get('/api/v1/orders/gecmis/${widget.id}');
      if (mounted) setState(() => _d = r is Map ? r.cast<String, dynamic>() : const {});
    } on ApiHata catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      context.bildir2('Adisyon açılamadı', e.mesaj, hata: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final a = d?['adisyon'] is Map ? (d!['adisyon'] as Map) : const {};
    final kalemler = (d?['kalemler'] as List? ?? const []).whereType<Map>().toList();
    final t = d?['toplamlar'] is Map ? (d!['toplamlar'] as Map) : const {};
    final odemeler = (d?['odemeler'] as List? ?? const []).whereType<Map>().toList();
    final masa = a['masa']?.toString();

    Widget satir(String e, int tutar, {Color? renk, bool kalin = false, String on = ''}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(e, style: TextStyle(fontSize: 13, color: (renk ?? Renk.yazi) == Renk.yazi ? Renk.ikinci : (renk ?? Renk.yazi), fontWeight: kalin ? FontWeight.w700 : FontWeight.w400))),
            Text('$on${para(tutar)}', style: TextStyle(fontSize: 13, color: (renk ?? Renk.yazi), fontWeight: kalin ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: 'Adisyon #${a['no'] ?? '…'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (masa != null) TextSpan(text: ' · $masa', style: TextStyle(fontWeight: FontWeight.w600, color: Renk.ikinci)),
                ]), style: const TextStyle(fontSize: 16)),
              ),
              IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Flexible(
            child: d == null
                ? Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.soluk))))
                : ListView(shrinkWrap: true, padding: const EdgeInsets.all(18), children: [
                    Text('Ürünler', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.soluk)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                      child: Column(children: [
                        for (var i = 0; i < kalemler.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: Renk.cizgi))),
                            child: Row(children: [
                              SizedBox(
                                width: 34,
                                child: Text('${tamSayi(kalemler[i]['adet'])}x', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: Renk.soluk)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text('${kalemler[i]['ad'] ?? ''}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: kalemler[i]['durum'] == 'cancelled' ? Renk.soluk : Renk.yazi,
                                      decoration: kalemler[i]['durum'] == 'cancelled' ? TextDecoration.lineThrough : null,
                                    )),
                              ),
                              if (kalemler[i]['ikram'] == true)
                                Text('İKRAM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.uyari))
                              else
                                Text(para(tamSayi(kalemler[i]['tutar_minor'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
                      child: Column(children: [
                        satir('Ara toplam', tamSayi(t['ara_toplam_minor'])),
                        if (tamSayi(t['indirim_minor']) > 0)
                          satir('İndirim${t['indirim_sebep'] != null ? ' (${t['indirim_sebep']})' : ''}', tamSayi(t['indirim_minor']), renk: Renk.hata, on: '−'),
                        if (tamSayi(t['ikram_minor']) > 0) satir('İkram', tamSayi(t['ikram_minor']), renk: Renk.uyari),
                        satir('Toplam', tamSayi(t['toplam_minor']), kalin: true),
                        satir('Tahsil edilen', tamSayi(t['tahsil_minor']), renk: Renk.basari, kalin: true),
                        if (tamSayi(t['borc_minor']) > 0) satir('Borca yazılan', tamSayi(t['borc_minor']), renk: Renk.hata),
                      ]),
                    ),
                    if (odemeler.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('Ödemeler', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.soluk)),
                      const SizedBox(height: 6),
                      for (final o in odemeler)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            Expanded(
                              child: Text.rich(TextSpan(children: [
                                TextSpan(text: '${o['etiket'] ?? ''}${o['iade'] == true ? ' · iade' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(text: '  ${_saatDetay(o['zaman'])}', style: TextStyle(color: Renk.soluk)),
                              ]), style: const TextStyle(fontSize: 13)),
                            ),
                            Rozet('${o['durum_ad'] ?? ''}', renk: o['iyi'] == true ? Renk.basari : Renk.soluk),
                            const SizedBox(width: 8),
                            Text(
                              '${o['iade'] == true ? '−' : ''}${para(tamSayi(o['tutar_minor']).abs())}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: o['iade'] == true ? Renk.hata : Renk.yazi),
                            ),
                          ]),
                        ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
                      child: Text('Açan: ${a['acan'] ?? '—'} · Kapatan: ${a['kapatan'] ?? '—'} · ${_saatDetay(a['kapanma'])}',
                          style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                    ),
                  ]),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _basiyor || d == null
                    ? null
                    : () async {
                        setState(() => _basiyor = true);
                        await widget.fisBas(widget.id);
                        if (mounted) setState(() => _basiyor = false);
                      },
                icon: const Icon(Icons.print_outlined, size: 16),
                label: const Text('Fişi yeniden bas'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
