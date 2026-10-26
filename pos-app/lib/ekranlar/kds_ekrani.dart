import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'kabuk.dart';
import 'ortak.dart';

/// HAZIRLIK (Mutfak / Barista / Nargile — web Kitchen.vue) ve KOMİ (Runner.vue)
/// ekranları. Şartname: /root/work/spec/kds.md (bölüm numaraları ona göre).
///
/// Akış (§0.4): ilk açılışta tam kuyruk, sonra `updates?cursor=` uzun
/// yoklaması (sunucu ≤20 sn bekler, değişiklik olunca hemen döner; 204 =
/// değişiklik yok). Her eylemden sonra tam kuyruk tazelenir.
/// Bu ekranlarda PARA YOK (sunucu yanıtında da yok).
class KdsEkrani extends StatefulWidget {
  const KdsEkrani({super.key, required this.kip, this.serit});

  /// 'kitchen' (hazırlık) | 'runner' (komi/servis)
  final String kip;

  /// kitchen | barista | nargile (yalnız hazırlık kipinde).
  final String? serit;

  @override
  State<KdsEkrani> createState() => _KdsEkraniState();
}

/* ───────── §0.5 SLA ───────── */

enum _Sla { ok, warn, late }

_Sla _slaSeviye(int bekleme, int hedef, [double oran = 1.5]) {
  if (bekleme >= (hedef * oran).ceil()) return _Sla.late;
  if (bekleme >= hedef) return _Sla.warn;
  return _Sla.ok;
}

String _slaMetni(int m) => m < 60 ? '$m dk' : '${m ~/ 60} sa ${(m % 60).toString().padLeft(2, '0')} dk';

Json _j(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Json> _l(Object? v) => (v as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
String? _m(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

String _hedefAdi(Json k) =>
    _m(k['table_name']) ?? _m(k['receivable_name']) ?? _m(k['customer_name']) ?? 'Sipariş #${k['id']}';

class _KdsEkraniState extends State<KdsEkrani> {
  late final Api _api;
  SharedPreferences? _tercih;

  Json? _veri;
  int _imlec = 0;
  bool _calisiyor = true;
  bool _baglantiYok = false;
  bool _mesgul = false;
  Duration _kayma = Duration.zero;
  Timer? _saat;
  int _akis = 0; // şube değişince/yeniden başlayınca eski döngü durur

  // §1.9 yeni sipariş / ek kalem tespiti
  final Set<int> _bilinenSiparis = {};
  final Set<int> _bilinenKalem = {};
  bool _ilkYukleme = true;
  Set<int> _vurgu = {};
  int _yeniSayisi = 0;
  Timer? _vurguSayaci;

  // §0.6 ses / §1.10 oto-fiş
  bool _ses = true;
  bool _otoFis = true;
  final List<String> _basilan = [];

  // §1.11 yazıcı seçimi
  List<Json> _yazicilar = const [];
  bool _ajanCevrimici = false;
  int? _seciliYazici;

  // §2.5 son götürülenler (yalnız bellekte)
  final List<({int id, String etiket})> _sonGoturulen = [];

  bool get _komi => widget.kip == 'runner';
  String get _kulvarAdi => switch (widget.serit) {
        'barista' => 'Barista',
        'nargile' => 'Nargile',
        _ => 'Mutfak',
      };
  String get _ekranIstasyonu => widget.serit ?? 'kitchen';

  Map<String, dynamic> get _sorgu => _komi ? {'mode': 'runner'} : {'mode': 'kitchen', 'lane': ?widget.serit};

  Oturum get _o => context.durum.oturum!;

  @override
  void initState() {
    super.initState();
    _api = context.api;
    _baslat();
    _saat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _calisiyor = false;
    _saat?.cancel();
    _vurguSayaci?.cancel();
    super.dispose();
  }

  Future<void> _baslat() async {
    _tercih = await SharedPreferences.getInstance();
    final t = _tercih!;
    _ses = t.getString(_komi ? 'kds_runner_sound' : 'kds_kitchen_sound') != 'off';
    _otoFis = t.getString('bhx-kds-autoprint') != 'off';
    try {
      final b = jsonDecode(t.getString('bhx-kds-printed-items') ?? '[]');
      if (b is List) _basilan.addAll(b.map((e) => '$e'));
    } catch (_) {}
    if (!_komi) _yazicilariYukle();
    _dongu(++_akis);
  }

  /* ───────── §0.4 akış ───────── */

  Future<void> _tam() async {
    final r = await _api.get('/api/v1/kds/queue', sorgu: _sorgu);
    _isle(r, tam: true);
  }

  Future<void> _tazele() => _tam().catchError((_) {});

  Future<void> _dongu(int akis) async {
    var bekleme = 1;
    while (_calisiyor && mounted && akis == _akis) {
      try {
        if (_veri == null) {
          await _tam();
        } else {
          final r = await _api.get('/api/v1/kds/updates', sorgu: {..._sorgu, 'cursor': _imlec}, zamanAsimi: const Duration(seconds: 40));
          if (r is Map) _isle(r);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        bekleme = 1;
      } on ApiHata catch (e) {
        if (!mounted) return;
        setState(() => _baglantiYok = e.baglantiYok);
        if (e.yetkiYok || e.kod == 404) {
          setState(() => _veri = {'_yetki': e.mesaj});
          return;
        }
        if (_veri == null && !e.baglantiYok) context.bildir2(_komi ? 'Liste yüklenemedi' : 'Kuyruk yüklenemedi', e.mesaj, hata: true);
        await Future<void>.delayed(Duration(seconds: bekleme));
        bekleme = (bekleme * 2).clamp(1, 15);
      }
    }
  }

  void _isle(dynamic r, {bool tam = false}) {
    if (r is! Map || !mounted) return;
    final v = r.cast<String, dynamic>();
    final sunucu = DateTime.tryParse('${v['server_time'] ?? ''}');
    if (sunucu != null) _kayma = sunucu.difference(DateTime.now());
    final sessiz = _ilkYukleme;
    _ilkYukleme = false;
    setState(() {
      _veri = v;
      _imlec = tamSayi(v['cursor'], _imlec);
      _baglantiYok = false;
    });
    _komi ? _komiYeniler(v, sessiz) : _mutfakYeniler(v, sessiz);
  }

  int _dk(Object? iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return 0;
    final f = DateTime.now().add(_kayma).difference(t).inMinutes;
    return f < 0 ? 0 : f;
  }

  /* ───────── §0.6 ses ───────── */

  Future<void> _bip([int kez = 2]) async {
    if (!_ses) return;
    for (var i = 0; i < kez; i++) {
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.mediumImpact();
      if (i < kez - 1) await Future<void>.delayed(const Duration(milliseconds: 650));
    }
  }

  void _sesDegistir() {
    setState(() => _ses = !_ses);
    _tercih?.setString(_komi ? 'kds_runner_sound' : 'kds_kitchen_sound', _ses ? 'on' : 'off');
    if (_ses) _bip(1);
  }

  void _vurgula(Set<int> idler, Duration sure) {
    setState(() {
      _vurgu = idler;
      _yeniSayisi = _komi ? 0 : _yeniSayisi;
    });
    _vurguSayaci?.cancel();
    _vurguSayaci = Timer(sure, () {
      if (mounted) {
        setState(() {
          _vurgu = {};
          _yeniSayisi = 0;
        });
      }
    });
  }

  /* ───────── §1.9 mutfak: yeni sipariş / ek kalem ───────── */

  void _mutfakYeniler(Json v, bool sessiz) {
    final kartlar = _l(v['orders']);
    final yeniSiparis = <Json>[];
    final ekKalemKart = <Json>[];
    for (final k in kartlar) {
      final id = tamSayi(k['id']);
      final kalemler = _l(k['items']);
      if (!_bilinenSiparis.contains(id)) {
        yeniSiparis.add(k);
      } else if (kalemler.any((x) => !_bilinenKalem.contains(tamSayi(x['id'])))) {
        ekKalemKart.add(k);
      }
      _bilinenSiparis.add(id);
      for (final x in kalemler) {
        _bilinenKalem.add(tamSayi(x['id']));
      }
    }
    _otoFisBas(kartlar, sessiz);
    if (sessiz || (yeniSiparis.isEmpty && ekKalemKart.isEmpty)) return;

    _bip();
    _vurgula({...yeniSiparis.map((k) => tamSayi(k['id'])), ...ekKalemKart.map((k) => tamSayi(k['id']))}, const Duration(seconds: 12));
    setState(() => _yeniSayisi = yeniSiparis.length);
    if (yeniSiparis.length == 1) {
      final k = yeniSiparis.first;
      final etiket = _m(k['table_name']) ?? _m(k['receivable_name']) ?? _m(k['customer_name']) ?? _m(k['channel_label']) ?? '#${k['id']}';
      context.bildir2('Yeni sipariş geldi', '$etiket · #${k['id']}');
    } else if (yeniSiparis.length > 1) {
      context.bildir2('${yeniSiparis.length} yeni sipariş geldi', 'Kuyruğa yeni siparişler düştü.');
    } else if (ekKalemKart.length == 1) {
      final k = ekKalemKart.first;
      final etiket = _m(k['table_name']) ?? _m(k['receivable_name']) ?? _m(k['customer_name']) ?? '#${k['id']}';
      context.bildir2('Masaya ek sipariş', '$etiket · yeni kalem eklendi');
    } else {
      context.bildir2('Masaya ek sipariş', '${ekKalemKart.length} adisyona yeni kalem eklendi');
    }
  }

  /* ───────── §1.10 oto-fiş + §1.11 yazıcı ───────── */

  String get _subeAnahtari => '${_o.ham['sube'] is Map ? (_o.ham['sube'] as Map)['id'] : ''}';

  void _otoFisBas(List<Json> kartlar, bool sessiz) {
    if (!_otoFis) return;
    final yeniler = <int, List<String>>{};
    for (final k in kartlar) {
      for (final x in _l(k['items'])) {
        final anahtar = '${widget.serit ?? 'kitchen'}:$_subeAnahtari:${x['id']}';
        if (_basilan.contains(anahtar)) continue;
        _basilan.add(anahtar);
        (yeniler[tamSayi(k['id'])] ??= []).add(anahtar);
      }
    }
    if (yeniler.isEmpty) return;
    if (_basilan.length > 2000) _basilan.removeRange(0, _basilan.length - 2000);
    _tercih?.setString('bhx-kds-printed-items', jsonEncode(_basilan));
    if (sessiz) return; // ilk yüklemede yalnız işaretlenir
    final yazici = _seciliYazici;
    if (yazici == null) return; // sunucu yazıcısı seçilmemiş
    for (final siparis in yeniler.keys) {
      _api.post('/api/v1/orders/$siparis/print', {'printer_id': yazici, 'kind': 'kitchen'}).catchError((Object e) {
        if (mounted) context.bildir2('Yazıcıya gönderilemedi', '$e', hata: true);
        return null;
      });
    }
  }

  void _otoFisDegistir() {
    setState(() => _otoFis = !_otoFis);
    _tercih?.setString('bhx-kds-autoprint', _otoFis ? 'on' : 'off');
  }

  Future<void> _yazicilariYukle() async {
    try {
      final r = _j(await _api.get('/api/v1/print/targets'));
      if (!mounted) return;
      setState(() {
        _yazicilar = _l(r['printers']);
        _ajanCevrimici = r['agent_online'] == true;
        final d = _j(r['defaults'])[_ekranIstasyonu];
        _seciliYazici = d == null ? null : tamSayi(d);
      });
    } on ApiHata {
      // Yazıcı listesi gelmezse oto-fiş yalnız işaretler.
    }
  }

  /* ───────── eylemler (§1.8 / §2.4 runAction) ───────── */

  Future<void> _eylem(Future<dynamic> Function() f, {String? ok, String okMetin = '', VoidCallback? sonra}) async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    HapticFeedback.lightImpact();
    try {
      await f();
      sonra?.call();
      if (ok != null && mounted) context.bildir2(ok, okMetin);
      await _tazele();
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (e.kod == 409) {
        context.bildir2('Eşzamanlı değişiklik',
            _komi ? 'Sipariş başka ekrandan değişti; liste tazelendi.' : 'Sipariş bu sırada başka ekrandan değişti; kuyruk tazelendi.',
            hata: true);
        _tazele();
      } else {
        context.bildir2('İşlem tamamlanamadı', e.mesaj, hata: true);
        context.durum.islemHatasi(e);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  /// §1.7 aşamalı akış: Kabul → Başlat → Bitir; kapalıysa tek "Tamamla".
  ({String to, String etiket})? _sonrakiAdim(Json x) {
    final d = '${x['status']}';
    if (d == 'ready' || d == 'served' || d == 'cancelled') return null;
    if (!_o.eklenti('kds_stages')) return (to: 'ready', etiket: 'Tamamla');
    return switch (d) {
      'placed' || 'sent_to_station' => (to: 'accepted', etiket: 'Kabul'),
      'accepted' => (to: 'preparing', etiket: 'Başlat'),
      'preparing' => (to: 'ready', etiket: 'Bitir'),
      _ => null,
    };
  }

  void _adim(Json kart, Json x, String to) => _eylem(
        () => _api.post('/api/v1/kds/items/${x['id']}/status', {'to': to, 'expected_version': tamSayi(kart['version'])}),
        ok: to == 'ready' ? '${x['name']} hazır' : null,
      );

  void _geriAl(Json kart, Json x) => _eylem(
        () => _api.post('/api/v1/kds/items/${x['id']}/undo', {'expected_version': tamSayi(kart['version'])}),
        ok: 'İşaret geri alındı',
      );

  void _tumunuHazirla(Json kart) => _eylem(
        () => _api.post('/api/v1/kds/orders/${kart['id']}/station-ready', {
          'station': null,
          'lane': widget.serit,
          'expected_version': tamSayi(kart['version']),
        }),
        ok: 'Sipariş hazır olarak işaretlendi',
      );

  /* ───────── build ───────── */

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    Widget govde;
    if (v == null) {
      govde = Center(child: Text(_komi ? 'Liste yükleniyor…' : 'Kuyruk yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    } else if (v['_yetki'] != null) {
      govde = Center(child: Text('${v['_yetki']}', style: TextStyle(color: Renk.soluk)));
    } else {
      govde = _komi ? _komiGovde(v) : _mutfakGovde(v);
    }

    return ColoredBox(
      color: Renk.zemin,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        _durumCubugu(v),
        if (!_komi && _yeniSayisi > 0) _yeniSeridi(),
        Expanded(child: govde),
        if (_komi && _sonGoturulen.isNotEmpty) _sonGoturulenSeridi(),
      ]),
    );
  }

  /* ── üst çubuk #status + #actions (§1.2 / §1.3 / §2.1) ── */

  Widget _cip(String metin, {bool uyari = false, IconData? ikon}) => Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: uyari ? Renk.hata : Renk.ic,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: uyari ? Renk.hata : Renk.cizgi),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (ikon != null) ...[Icon(ikon, size: 13, color: uyari ? Colors.white : Renk.yazi), const SizedBox(width: 5)],
          Text(metin,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: uyari ? Colors.white : Renk.yazi,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      );

  Widget _simgeDugme(IconData ikon, String ipucu, VoidCallback bas, {Color? renk}) => Tooltip(
        message: ipucu,
        child: IconButton(
          onPressed: bas,
          style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: koseYuvarlak)),
          icon: Icon(ikon, size: 20, color: (renk ?? Renk.ikinci)),
        ),
      );

  Widget _durumCubugu(Json? v) {
    final telefon = MediaQuery.sizeOf(context).width < 640;
    final List<Widget> cipler;
    final List<Widget> eylemler;
    if (_komi) {
      cipler = [_cip('${_l(v?['items']).length} hazır ürün')];
      eylemler = [
        _simgeDugme(_ses ? Icons.volume_up_outlined : Icons.volume_off_outlined, _ses ? 'Yeni ürün sesi: açık' : 'Yeni ürün sesi: kapalı', _sesDegistir,
            renk: _ses ? Renk.ikinci : Renk.soluk),
      ];
    } else {
      final kartlar = _l(v?['orders']);
      var bekleyen = 0;
      var geciken = 0;
      for (final k in kartlar) {
        final ks = _l(k['items']);
        bekleyen += ks.where((x) => x['status'] != 'ready').length;
        if (_kartSla(ks) == _Sla.late) geciken++;
      }
      cipler = [
        _cip('$bekleyen bekleyen'),
        if (geciken > 0) ...[const SizedBox(width: 6), _cip('$geciken gecikti', uyari: true, ikon: Icons.warning_amber_rounded)],
      ];
      eylemler = [
        if (_o.yetki('kds.deliver'))
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: () => ekranIstegi.value = PosEkrani.komi,
              icon: const Icon(Icons.inbox_outlined, size: 17),
              label: const Text('Komi'),
            ),
          ),
        if (_o.yetki('kds.manage')) _simgeDugme(Icons.settings_outlined, 'İstasyon yönetimi', _istasyonYonetimi),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Tooltip(
            message: _otoFis ? 'Oto-fiş açık: yeni sipariş otomatik yazdırılır' : 'Oto-fiş kapalı',
            child: Material(
              color: _otoFis ? Renk.basariZemin : Colors.transparent,
              shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: _otoFis ? Renk.basari : Renk.cizgi)),
              child: InkWell(
                customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                onTap: _otoFisDegistir,
                child: SizedBox(
                  height: 36,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.print_outlined, size: 17, color: _otoFis ? Renk.basari : Renk.soluk),
                      if (!telefon) ...[
                        const SizedBox(width: 6),
                        Text(_otoFis ? 'Oto-fiş açık' : 'Oto-fiş kapalı',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _otoFis ? Renk.basari : Renk.soluk)),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        _simgeDugme(
          Icons.power_outlined,
          _seciliAd != null ? 'Termal yazıcı bağlı ($_seciliAd) — ayarlar' : 'Termal yazıcı bağla (sessiz otomatik fiş)',
          _yaziciPenceresi,
          renk: _seciliAd != null ? Renk.basari : Renk.soluk,
        ),
        _simgeDugme(_ses ? Icons.volume_up_outlined : Icons.volume_off_outlined, _ses ? 'Yeni sipariş sesi: açık' : 'Yeni sipariş sesi: kapalı',
            _sesDegistir,
            renk: _ses ? Renk.ikinci : Renk.soluk),
      ];
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 24),
          child: Row(children: [
            Text(_komi ? 'Komi · Servis Ekranı' : '$_kulvarAdi Hazırlık Ekranı',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Renk.yazi)),
            const SizedBox(width: 12),
            ...cipler,
            const SizedBox(width: 16),
            ...eylemler,
          ]),
        ),
      ),
    );
  }

  String? get _seciliAd {
    final s = _seciliYazici;
    if (s == null) return null;
    return _m(_yazicilar.where((p) => tamSayi(p['id']) == s).firstOrNull?['name']) ?? 'Yazıcı';
  }

  Widget _yeniSeridi() => Container(
        color: Renk.marka,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const _NabizNoktasi(),
          const SizedBox(width: 8),
          Text('$_yeniSayisi yeni sipariş geldi', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );

  /* ═════════════ §1.5–1.6 MUTFAK ═════════════ */

  _Sla _kalemSla(Json x) =>
      x['status'] == 'ready' ? _Sla.ok : _slaSeviye(_dk(x['created_at']), tamSayi(x['target_minutes'], 15).clamp(1, 9999));

  _Sla _kartSla(List<Json> ks) {
    var en = _Sla.ok;
    for (final x in ks) {
      final s = _kalemSla(x);
      if (s.index > en.index) en = s;
    }
    return en;
  }

  Widget _mutfakGovde(Json v) {
    final kartlar = _l(v['orders'])..sort((a, b) => tamSayi(a['id']).compareTo(tamSayi(b['id'])));
    if (kartlar.isEmpty) {
      return const _BosDurum(
        baslik: 'Bekleyen sipariş yok',
        aciklama: 'Yeni sipariş geldiğinde burada görünür — ekran her 4 saniyede bir kendini yeniler.',
      );
    }
    return LayoutBuilder(builder: (context, k) {
      final g = MediaQuery.sizeOf(context).width;
      final enAz = g >= 1536 ? 380.0 : 340.0;
      const bosluk = 16.0;
      final sutun = ((k.maxWidth - 24 + bosluk) / (enAz + bosluk)).floor().clamp(1, 12);
      final satirlar = <List<Json>>[];
      for (var i = 0; i < kartlar.length; i += sutun) {
        satirlar.add(kartlar.sublist(i, (i + sutun).clamp(0, kartlar.length)));
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: satirlar.length,
        separatorBuilder: (_, _) => const SizedBox(height: bosluk),
        itemBuilder: (_, i) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var j = 0; j < sutun; j++) ...[
            if (j > 0) const SizedBox(width: bosluk),
            Expanded(child: j < satirlar[i].length ? _kart(satirlar[i][j]) : const SizedBox()),
          ],
        ]),
      );
    });
  }

  Widget _kart(Json k) {
    final ks = _l(k['items']);
    final sla = _kartSla(ks);
    final yeni = _vurgu.contains(tamSayi(k['id']));
    final kenar = switch (sla) {
      _Sla.late => Renk.hata,
      _Sla.warn => Renk.uyari,
      _ => yeni ? Renk.markaKenar : Renk.cizgi,
    };
    final basZemin = switch (sla) {
      _Sla.late => Renk.hataZemin,
      _Sla.warn => Renk.uyariZemin,
      _ => Renk.zemin,
    };
    final sureRengi = switch (sla) {
      _Sla.late => Renk.hata,
      _Sla.warn => Renk.uyari,
      _ => Renk.yazi,
    };
    final alt = [k['channel_label'], k['area_name'], k['waiter']].map(_m).whereType<String>().join(' · ');
    final bekleyen = ks.where((x) => x['status'] != 'ready').length;

    return Container(
      decoration: BoxDecoration(
        color: Renk.yuzey,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kenar, width: 2),
        boxShadow: kartGolge,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: basZemin,
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_hedefAdi(k), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                if (alt.isNotEmpty) Text(alt, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
              ]),
            ),
            Tooltip(
              message: 'Sipariş verileli geçen süre',
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule_rounded, size: 16, color: sureRengi),
                const SizedBox(width: 4),
                Text(_slaMetni(_dk(k['placed_at'])),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: sureRengi, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
            _simgeDugme(Icons.print_outlined, 'Fiş önizle ve yazdır', () => _fisOnizle(k, ks, teslim: false)),
          ]),
        ),
        if (sla == _Sla.late)
          Container(
            color: Renk.hata,
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: Colors.white),
              SizedBox(width: 4),
              Text('GECİKTİ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: .6)),
            ]),
          ),
        if (_m(k['note']) != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Renk.bilgiZemin, border: Border(bottom: BorderSide(color: Renk.bilgiKenar))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 15, color: Renk.bilgi),
              const SizedBox(width: 6),
              Expanded(child: Text('${k['note']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Renk.bilgi))),
            ]),
          ),
        for (var i = 0; i < ks.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          _kalemSatiri(k, ks[i]),
        ],
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
          padding: const EdgeInsets.all(8),
          child: bekleyen > 0
              ? FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  onPressed: _mesgul ? null : () => _tumunuHazirla(k),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text('Tümünü hazırla ($bekleyen)'),
                )
              : SizedBox(
                  height: 40,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.inbox_outlined, size: 18, color: Renk.basari),
                    SizedBox(width: 6),
                    Text('Garson & Komi bekliyor', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Renk.basari)),
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _kalemSatiri(Json kart, Json x) {
    final hazir = x['status'] == 'ready';
    final adim = _sonrakiAdim(x);
    final secenekler = _l(x['options']).map((o) => _m(o['option_name']) ?? _m(o['name'])).whereType<String>().join(' · ');
    final alerjen = _l(x['allergens']).map((a) => _m(a['name'])).whereType<String>().toList();
    final diyet = (x['diets'] as List? ?? const []).map((d) => d is Map ? '${d['name'] ?? ''}' : '$d').where((s) => s.isNotEmpty).toList();
    final recete = _m(x['recipe']);

    return Opacity(
      opacity: hazir ? .55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
              child: Text('${x['qty'] ?? 1}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 10),
            _KalemGorseli(url: _m(x['image_url']), ad: '${x['name'] ?? ''}', boyut: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${x['name'] ?? ''}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, decoration: hazir ? TextDecoration.lineThrough : null)),
                if (_m(x['variant_name']) != null)
                  Text('${x['variant_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
                if (secenekler.isNotEmpty) Text(secenekler, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              ]),
            ),
          ]),
          if (_m(x['note']) != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: Renk.bilgiZemin, borderRadius: BorderRadius.circular(6)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.error_outline_rounded, size: 14, color: Renk.bilgi),
                const SizedBox(width: 5),
                Expanded(child: Text('${x['note']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Renk.bilgi))),
              ]),
            ),
          if (alerjen.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: Renk.hataZemin, borderRadius: BorderRadius.circular(6)),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: Renk.hata),
                const SizedBox(width: 5),
                Expanded(child: Text(alerjen.join(' · '), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Renk.hata))),
              ]),
            ),
          // İstasyon süzgeci yok (§1.3 NOT) → istasyon adı her zaman gösterilir.
          if (diyet.isNotEmpty || recete != null || _m(x['station_label']) != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (diyet.isNotEmpty)
                  Text.rich(
                    TextSpan(children: [const TextSpan(text: 'Diyet: ', style: TextStyle(fontWeight: FontWeight.w700)), TextSpan(text: diyet.join(' · '))]),
                    style: TextStyle(fontSize: 12, color: Renk.soluk),
                  ),
                if (recete != null)
                  InkWell(
                    onTap: () => _recete(x),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.assignment_outlined, size: 13, color: Renk.marka),
                      SizedBox(width: 3),
                      Text('Reçete', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.marka)),
                    ]),
                  ),
                if (_m(x['station_label']) != null)
                  Text('${x['station_label']}', style: TextStyle(fontSize: 12, color: Renk.soluk.withValues(alpha: .7))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              if (adim != null)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                    onPressed: _mesgul ? null : () => _adim(kart, x, adim.to),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: Text(adim.etiket),
                  ),
                )
              else if (hazir)
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(color: Renk.basariZemin, borderRadius: koseYuvarlak),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check_circle_outline_rounded, size: 15, color: Renk.basari),
                      SizedBox(width: 5),
                      Text('Hazır', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Renk.basari)),
                    ]),
                  ),
                ),
              if (hazir) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Geri al',
                  child: IconButton(
                    onPressed: _mesgul ? null : () => _geriAl(kart, x),
                    icon: Icon(Icons.undo_rounded, size: 17, color: Renk.ikinci),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  /* ═════════════ §2 KOMİ ═════════════ */

  void _komiYeniler(Json v, bool sessiz) {
    final yeni = <int>{};
    for (final x in _l(v['items'])) {
      final id = tamSayi(x['id']);
      if (!_bilinenKalem.contains(id)) yeni.add(id);
      _bilinenKalem.add(id);
    }
    if (sessiz || yeni.isEmpty) return;
    _bip();
    _vurgula(yeni, const Duration(seconds: 10));
  }

  Widget _komiGovde(Json v) {
    final kalemler = _l(v['items'])..sort((a, b) => '${a['updated_at'] ?? ''}'.compareTo('${b['updated_at'] ?? ''}'));
    if (kalemler.isEmpty) {
      return const _BosDurum(
        baslik: 'Taşınacak ürün yok',
        aciklama: "Mutfak 'hazır' verdiğinde ürünler burada görünür — ekran her 4 saniyede bir kendini yeniler.",
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: kalemler.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1152), child: _komiSatiri(kalemler[i]))),
    );
  }

  Widget _komiSatiri(Json x) {
    final dk = _dk(x['updated_at']);
    final seviye = dk >= 5 ? _Sla.late : (dk >= 2 ? _Sla.warn : _Sla.ok);
    final nereye = _m(x['table_name']) ?? _m(x['receivable_name']) ?? _m(x['channel_label']) ?? '';
    final altNereye = [x['area_name'], x['waiter']].map(_m).whereType<String>().join(' · ');
    final alerjen = _l(x['allergens']).map((a) => _m(a['name'])).whereType<String>().toList();
    final diyet = (x['diets'] as List? ?? const []).map((d) => d is Map ? '${d['name'] ?? ''}' : '$d').where((s) => s.isNotEmpty).toList();
    final alindi = _m(x['picked_up_at']) != null;
    final id = tamSayi(x['id']);

    final (cipZemin, cipKenar, cipYazi) = switch (seviye) {
      _Sla.late => (Renk.hata, Renk.hata, Colors.white),
      _Sla.warn => (Renk.uyariZemin, Renk.uyariKenar, Renk.uyari),
      _ => (Renk.ic, Renk.cizgi, Renk.ikinci),
    };

    return Container(
      decoration: BoxDecoration(
        color: Renk.yuzey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _vurgu.contains(id) ? Renk.markaKenar : Renk.cizgi),
        boxShadow: kartGolge,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Wrap(spacing: 20, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _KalemGorseli(url: _m(x['image_url']), ad: '${x['name'] ?? ''}', boyut: 64),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nereye, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            if (altNereye.isNotEmpty) Text(altNereye, style: TextStyle(fontSize: 14, color: Renk.ikinci)),
          ]),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 256, maxWidth: 480),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${x['qty'] ?? 1}× ', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: '${x['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (_m(x['variant_name']) != null) TextSpan(text: ' — ${x['variant_name']}', style: TextStyle(color: Renk.ikinci)),
              ]),
              style: const TextStyle(fontSize: 18),
            ),
            if (_m(x['note']) != null) Text('Not: ${x['note']}', style: TextStyle(fontSize: 14, color: Renk.bilgi)),
            if (alerjen.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 4, runSpacing: 4, children: [for (final a in alerjen) _cip(a, uyari: true, ikon: Icons.warning_amber_rounded)]),
              ),
            if (diyet.isNotEmpty) Text(diyet.join(' · '), style: TextStyle(fontSize: 12, color: Renk.soluk)),
          ]),
        ),
        Tooltip(
          message: 'Hazır olalı geçen süre',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: cipZemin, borderRadius: BorderRadius.circular(6), border: Border.all(color: cipKenar)),
            child: Text('${_slaMetni(dk)}${seviye == _Sla.late ? ' · gecikti' : ''}',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cipYazi, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _simgeDugme(Icons.print_outlined, 'Teslim fişini önizle ve yazdır', () => _fisOnizle(x, [x], teslim: true)),
          const SizedBox(width: 6),
          if (!alindi)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 18)),
              onPressed: _mesgul ? null : () => _eylem(() => _api.post('/api/v1/kds/items/$id/pickup'), ok: 'Teslim alındı'),
              child: const Text('Teslim aldım'),
            )
          else ...[
            Tooltip(
              message: 'Teslim işaretini geri al',
              child: IconButton(
                onPressed: _mesgul ? null : () => _eylem(() => _api.delete('/api/v1/kds/items/$id/pickup'), ok: 'Teslim işareti geri alındı'),
                icon: Icon(Icons.undo_rounded, color: Renk.ikinci),
              ),
            ),
            Icon(Icons.check_rounded, size: 14, color: Renk.basari),
            const SizedBox(width: 3),
            Text(_m(x['picked_up_by']) ?? 'Alındı', style: TextStyle(fontSize: 14, color: Renk.basari)),
            const SizedBox(width: 10),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 18)),
              onPressed: _mesgul ? null : () => _goturdum(x),
              child: const Text('Masaya götürdüm'),
            ),
          ],
        ]),
      ]),
    );
  }

  void _goturdum(Json x) {
    final id = tamSayi(x['id']);
    final etiket = '${x['qty'] ?? 1}× ${x['name'] ?? ''} → ${_m(x['table_name']) ?? _m(x['receivable_name']) ?? _m(x['channel_label']) ?? ''}';
    _eylem(
      () => _api.post('/api/v1/kds/items/$id/status', {'to': 'served', 'expected_version': tamSayi(x['order_version'])}),
      ok: 'Masaya götürüldü',
      sonra: () => setState(() {
        _sonGoturulen.removeWhere((e) => e.id == id);
        _sonGoturulen.insert(0, (id: id, etiket: etiket));
        if (_sonGoturulen.length > 5) _sonGoturulen.removeLast();
      }),
    );
  }

  Widget _sonGoturulenSeridi() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Renk.yuzey,
          border: Border(top: BorderSide(color: Renk.cizgi)),
          boxShadow: [BoxShadow(color: Color(0x140F172A), blurRadius: 10, offset: Offset(0, -2))],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Text('SON GÖTÜRÜLENLER', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .5)),
            for (final s in _sonGoturulen)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.only(left: 10),
                decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.etiket, style: const TextStyle(fontSize: 13)),
                  TextButton.icon(
                    onPressed: _mesgul
                        ? null
                        : () => _eylem(
                              () => _api.post('/api/v1/kds/items/${s.id}/undo', const <String, dynamic>{}),
                              ok: 'Servis işareti geri alındı',
                              sonra: () => setState(() => _sonGoturulen.removeWhere((e) => e.id == s.id)),
                            ),
                    icon: const Icon(Icons.undo_rounded, size: 14),
                    label: const Text('Geri al'),
                  ),
                ]),
              ),
          ]),
        ),
      );

  /* ═════════════ §1.12 / §2.6 pencereler ═════════════ */

  Future<void> _fisOnizle(Json kart, List<Json> kalemler, {required bool teslim}) async {
    final o = _o;
    final sube = o.sube ?? '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(teslim ? 'Teslim fişi önizleme' : 'İstasyon fişi önizleme'),
        content: SingleChildScrollView(
          child: _Fis(
            isletme: o.isletme,
            sube: sube,
            istasyon: teslim ? 'Teslim' : _kulvarAdi,
            no: tamSayi(teslim ? kart['order_id'] : kart['id']),
            hedef: teslim ? (_m(kart['table_name']) ?? _m(kart['receivable_name']) ?? _m(kart['channel_label']) ?? '') : _hedefAdi(kart),
            servis: [teslim ? kart['channel_label'] : (kart['service_type_label'] ?? kart['channel_label']), kart['area_name'], kart['waiter']]
                .map(_m)
                .whereType<String>()
                .join(' · '),
            saat: saatMetni('${teslim ? kart['updated_at'] : kart['placed_at']}'),
            not: _m(teslim ? kart['order_note'] : kart['note']),
            kalemler: kalemler,
            teslim: teslim,
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              await _sunucudanBas(tamSayi(teslim ? kart['order_id'] : kart['id']));
            },
            icon: const Icon(Icons.print_outlined, size: 17),
            label: const Text('Yazdır'),
          ),
        ],
      ),
    );
  }

  Future<void> _sunucudanBas(int siparisId) async {
    final yazici = _seciliYazici;
    if (yazici == null) {
      context.bildir2('Yazıcı seçilmedi', 'Termal yazıcı düğmesinden bu ekranın yazıcısını seçin.', hata: true);
      return;
    }
    try {
      await _api.post('/api/v1/orders/$siparisId/print', {'printer_id': yazici, 'kind': 'kitchen'});
      if (mounted) context.bildir2('Fiş yazıcıya gönderildi', _seciliAd ?? '');
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Yazıcıya gönderilemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _recete(Json x) => showDialog<void>(
        context: context,
        builder: (ctx) {
          final alerjen = _l(x['allergens']).map((a) => _m(a['name'])).whereType<String>().toList();
          return AlertDialog(
            title: const Text('Reçete / hazırlama'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_m(x['image_url']) != null)
                    ClipRRect(borderRadius: koseYuvarlak, child: CachedNetworkImage(imageUrl: '${x['image_url']}', height: 180, fit: BoxFit.cover)),
                  const SizedBox(height: 10),
                  Text('${x['qty'] ?? 1}× ${x['name'] ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  if (_m(x['variant_name']) != null) Text('${x['variant_name']}', style: TextStyle(color: Renk.ikinci)),
                  if (alerjen.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      const Text('Alerjen:', style: TextStyle(fontWeight: FontWeight.w700)),
                      for (final a in alerjen) Rozet(a, renk: Renk.hata, kenar: Renk.hata),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
                    child: Text('${x['recipe'] ?? ''}', style: const TextStyle(fontSize: 15, height: 1.45)),
                  ),
                ]),
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
          );
        },
      );

  /// Termal yazıcı (§1.11 + §1.12): native'de "bu ekranın yazıcısı"
  /// sunucu yazıcı seçimidir; fiş ağ yazıcısına uygulamanın yazdırma
  /// ajanı ya da işletmenin ajanı üzerinden gider.
  Future<void> _yaziciPenceresi() async {
    await _yazicilariYukle();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, yenile) => AlertDialog(
          title: const Text('Termal yazıcı'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
                child: Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Durum: ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: _seciliAd != null ? 'Doğrudan yazıcı bağlı ($_seciliAd)' : 'Yazıcı seçilmedi'),
                ])),
              ),
              const SizedBox(height: 12),
              const Text('Bu ekranın yazıcısı', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (_yazicilar.isEmpty)
                Text('Tanımlı yazıcı yok. Ayarlar > Yazıcılar bölümünden ekleyin.', style: TextStyle(color: Renk.ikinci))
              else
                DropdownButtonFormField<int?>(
                  initialValue: _seciliYazici,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Yazıcı seçilmedi')),
                    for (final p in _yazicilar)
                      DropdownMenuItem<int?>(
                        value: tamSayi(p['id']),
                        child: Text(
                          '${p['name']} · ${p['station_label'] ?? ''} · ${p['connection'] == 'os' ? 'bilgisayara tanımlı' : (p['target'] ?? '')}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) async {
                    try {
                      await _api.post('/api/v1/print/targets/default', {'printer_id': v, 'station': _ekranIstasyonu});
                      setState(() => _seciliYazici = v);
                      yenile(() {});
                      if (mounted) {
                        v == null
                            ? context.bildir2('Yazıcı seçimi kaldırıldı', 'Oto-fiş yalnız işaretler; yazıcı seçin.')
                            : context.bildir2('Yazıcı seçildi', 'Tüm cihazlarda fişler “$_seciliAd” yazıcısına gidecek.');
                      }
                    } on ApiHata catch (e) {
                      if (mounted) context.bildir2('Kaydedilemedi', e.mesaj, hata: true);
                    }
                  },
                ),
              if (_seciliYazici != null && !_ajanCevrimici)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Yazdırma ajanı çevrimdışı. Fişler kuyrukta bekler; ağdaki bir POS uygulaması açıkken otomatik basılır.',
                      style: TextStyle(fontSize: 12, color: Renk.uyari)),
                ),
              if (_seciliYazici != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final r = _j(await _api.post('/api/v1/printers/$_seciliYazici/test'));
                      if (!mounted) return;
                      r['agent_online'] == true
                          ? context.bildir2('Test fişi gönderildi', 'Birkaç saniye içinde basılır.')
                          : context.bildir2('Kuyrukta bekliyor', '${r['message'] ?? ''}');
                    } on ApiHata catch (e) {
                      if (mounted) context.bildir2('Test başarısız', e.mesaj, hata: true);
                    }
                  },
                  icon: const Icon(Icons.print_outlined, size: 17),
                  label: const Text('Seçili yazıcıya test fişi'),
                ),
              ],
            ]),
          ),
          actions: [OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat'))],
        ),
      ),
    );
  }

  Future<void> _istasyonYonetimi() => showDialog<void>(context: context, builder: (_) => const _IstasyonYonetimi());
}

/* ═════════════ Bileşenler ═════════════ */

class _BosDurum extends StatelessWidget {
  const _BosDurum({required this.baslik, required this.aciklama});
  final String baslik;
  final String aciklama;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle_outline_rounded, size: 44, color: Renk.soluk),
            const SizedBox(height: 10),
            Text(baslik, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(aciklama, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
          ]),
        ),
      );
}

/// KdsItemImage: köşe 8, kenarlı kare; yoksa tepsi simgesi. Dokununca büyür.
class _KalemGorseli extends StatelessWidget {
  const _KalemGorseli({required this.url, required this.ad, required this.boyut});
  final String? url;
  final String ad;
  final double boyut;

  @override
  Widget build(BuildContext context) {
    final yer = Container(
      width: boyut,
      height: boyut,
      decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Icon(Icons.inbox_outlined, size: boyut > 60 ? 22 : 18, color: Renk.soluk),
    );
    final u = url;
    if (u == null) return yer;
    return Tooltip(
      message: '$ad — büyüt',
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: () => showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.black,
            insetPadding: const EdgeInsets.all(12),
            child: InkWell(onTap: () => Navigator.pop(ctx), child: InteractiveViewer(child: CachedNetworkImage(imageUrl: u, fit: BoxFit.contain))),
          ),
        ),
        child: Container(
          width: boyut,
          height: boyut,
          decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: u,
            fit: BoxFit.cover,
            memCacheWidth: (boyut * MediaQuery.devicePixelRatioOf(context)).round(),
            errorWidget: (_, _, _) => yer,
          ),
        ),
      ),
    );
  }
}

class _NabizNoktasi extends StatefulWidget {
  const _NabizNoktasi();

  @override
  State<_NabizNoktasi> createState() => _NabizNoktasiState();
}

class _NabizNoktasiState extends State<_NabizNoktasi> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(alignment: Alignment.center, children: [
            Transform.scale(
              scale: 1 + _c.value,
              child: Opacity(
                opacity: 1 - _c.value,
                child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ),
            ),
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ]),
        ),
      );
}

/// §2.7 fiş düzeni (KdsTicket): 300 px beyaz kâğıt, siyah yazı, Courier.
class _Fis extends StatelessWidget {
  const _Fis({
    required this.isletme,
    required this.sube,
    required this.istasyon,
    required this.no,
    required this.hedef,
    required this.servis,
    required this.saat,
    required this.not,
    required this.kalemler,
    required this.teslim,
  });
  final String isletme;
  final String sube;
  final String istasyon;
  final int no;
  final String hedef;
  final String servis;
  final String saat;
  final String? not;
  final List<Json> kalemler;
  final bool teslim;

  @override
  Widget build(BuildContext context) {
    const yazi = TextStyle(fontFamily: 'Courier New', color: Colors.black, fontSize: 13);
    Widget cizgi({bool kalin = false}) => Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          height: kalin ? 2 : 1,
          color: Colors.black,
        );
    final adet = kalemler.fold<int>(0, (t, x) => t + tamSayi(x['qty'], 1));
    return Container(
      width: 300,
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: yazi,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(isletme.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          if (sube.isNotEmpty) Text(sube, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(istasyon.toUpperCase(),
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700, fontFamily: 'Courier New')),
          ),
          Row(children: [Text('ADİSYON #$no', style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text(saat)]),
          cizgi(),
          Text(hedef, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          if (servis.isNotEmpty) Text(servis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          cizgi(kalin: true),
          if (kalemler.isEmpty) const Text('(kalem yok)', textAlign: TextAlign.center),
          for (final x in kalemler)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 34,
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                    child: Text('${x['qty'] ?? 1}×', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${x['name'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                ]),
                if (_m(x['variant_name']) != null || _l(x['options']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: Text(
                      [_m(x['variant_name']), ..._l(x['options']).map((o) => _m(o['option_name']))].whereType<String>().join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (_m(x['note']) != null)
                  Container(
                    margin: const EdgeInsets.only(left: 40, top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(border: Border.all(color: Colors.black)),
                    child: Text('» ${x['note']}', style: const TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
          cizgi(kalin: true),
          Row(children: [
            const Text('TOPLAM', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${kalemler.length} çeşit · $adet adet'),
          ]),
          if (not != null)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Text('SİPARİŞ NOTU: $not', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          cizgi(),
          Text(teslim ? 'TESLİM FİŞİ' : 'İSTASYON FİŞİ', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('#$no · $saat', textAlign: TextAlign.center),
          const Text('✂ - - - - - - - - - - - - -', textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

/// §1.12 StationManager: "İstasyonlar" / "Personel Ataması" sekmeleri.
class _IstasyonYonetimi extends StatefulWidget {
  const _IstasyonYonetimi();

  @override
  State<_IstasyonYonetimi> createState() => _IstasyonYonetimiState();
}

class _IstasyonYonetimiState extends State<_IstasyonYonetimi> {
  late final Api _api = context.api;
  bool _yukleniyor = true;
  String? _hata;
  bool _personel = false;
  List<Json> _istasyonlar = const [];
  List<Json> _kullanicilar = const [];
  final _yeni = TextEditingController();

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    _yeni.dispose();
    super.dispose();
  }

  Future<void> _yukle() async {
    try {
      final s = _j(await _api.get('/api/v1/kds/stations'));
      final a = _j(await _api.get('/api/v1/kds/station-assignments'));
      if (!mounted) return;
      setState(() {
        _istasyonlar = _l(s['stations']);
        _kullanicilar = _l(a['users']);
        _yukleniyor = false;
        _hata = null;
      });
    } on ApiHata catch (e) {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
          _hata = e.mesaj;
        });
      }
    }
  }

  Future<void> _yap(Future<dynamic> Function() f, String ok) async {
    try {
      await f();
      if (mounted) context.bildir2(ok, '');
      await _yukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('İşlem tamamlanamadı', e.mesaj, hata: true);
    }
  }

  Future<void> _ekle() async {
    final ad = _yeni.text.trim();
    if (ad.isEmpty) return;
    _yeni.clear();
    await _yap(() => _api.post('/api/v1/kds/stations', {'name': ad}), 'İstasyon eklendi');
  }

  @override
  Widget build(BuildContext context) {
    Widget sekme(String ad, IconData? ikon, bool secili, VoidCallback bas) => InkWell(
          onTap: bas,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: secili ? Renk.marka : Colors.transparent, width: 2))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (ikon != null) ...[Icon(ikon, size: 16, color: secili ? Renk.marka : Renk.ikinci), const SizedBox(width: 6)],
              Text(ad, style: TextStyle(fontWeight: FontWeight.w700, color: secili ? Renk.marka : Renk.ikinci)),
            ]),
          ),
        );

    final aktifler = _istasyonlar.where((s) => s['is_active'] != false).toList();
    final Widget icerik;
    if (_yukleniyor) {
      icerik = const Padding(padding: EdgeInsets.all(24), child: Text('Yükleniyor…'));
    } else if (_hata != null) {
      icerik = Padding(padding: const EdgeInsets.all(24), child: Text('Yüklenemedi\n$_hata', style: TextStyle(color: Renk.hata)));
    } else if (!_personel) {
      icerik = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _yeni,
              maxLength: 80,
              decoration: const InputDecoration(hintText: 'Yeni istasyon adı (ör. Pizza Fırını)', counterText: ''),
              onSubmitted: (_) => _ekle(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _ekle, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Ekle')),
        ]),
        const SizedBox(height: 8),
        for (final s in _istasyonlar)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
            child: Row(children: [
              Expanded(
                child: Opacity(
                  opacity: s['is_active'] == false ? .55 : 1,
                  child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text('${s['name']}',
                        style: TextStyle(fontWeight: FontWeight.w600, decoration: s['is_active'] == false ? TextDecoration.lineThrough : null)),
                    Rozet('${s['key']}'),
                    if (s['is_builtin'] == true) Rozet('yerleşik', renk: Renk.marka),
                  ]),
                ),
              ),
              if (s['is_builtin'] != true && s['id'] != null) ...[
                Switch(
                  value: s['is_active'] != false,
                  onChanged: (v) => _yap(() => _api.put('/api/v1/kds/stations/${s['id']}', {'is_active': v}),
                      v ? 'İstasyon aktifleştirildi' : 'İstasyon pasifleştirildi'),
                ),
                IconButton(
                  tooltip: 'Sil',
                  onPressed: () => _yap(() => _api.delete('/api/v1/kds/stations/${s['id']}'), 'İstasyon silindi'),
                  icon: Icon(Icons.delete_outline_rounded, color: Renk.hata, size: 19),
                ),
              ],
            ]),
          ),
        const SizedBox(height: 8),
        Text('Yerleşik istasyonlar silinemez. Ürünler istasyonlara Menü → Ürün → Operasyon kartından yönlendirilir.',
            style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      ]);
    } else {
      icerik = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Atama yapılan personel mutfak ekranında yalnız kendi istasyonlarını görür ve işaretler. Ataması olmayan personel tüm istasyonları görür.',
          style: TextStyle(fontSize: 13, color: Renk.ikinci),
        ),
        const SizedBox(height: 8),
        for (final u in _kullanicilar)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['name']}${_m(u['position']) != null ? ' — ${u['position']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in aktifler)
                  () {
                    final anahtarlar = (u['station_keys'] as List? ?? const []).map((e) => '$e').toList();
                    final secili = anahtarlar.contains('${s['key']}');
                    return FilterChip(
                      label: Text('${s['name']}'),
                      selected: secili,
                      showCheckmark: false,
                      selectedColor: Renk.marka,
                      labelStyle: TextStyle(color: secili ? Colors.white : Renk.yazi, fontSize: 12.5),
                      onSelected: (v) {
                        final yeni = [...anahtarlar.where((k) => k != '${s['key']}'), if (v) '${s['key']}'];
                        _yap(() => _api.put('/api/v1/kds/station-assignments/${u['id']}', {'station_keys': yeni}), 'Atama güncellendi');
                      },
                    );
                  }(),
              ]),
            ]),
          ),
      ]);
    }

    return AlertDialog(
      title: const Text('İstasyon Yönetimi'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              sekme('İstasyonlar', null, !_personel, () => setState(() => _personel = false)),
              sekme('Personel Ataması', Icons.people_outline_rounded, _personel, () => setState(() => _personel = true)),
            ]),
            const Divider(height: 1),
            const SizedBox(height: 12),
            icerik,
          ]),
        ),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}
