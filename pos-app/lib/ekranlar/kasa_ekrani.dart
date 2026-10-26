import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/katalog_deposu.dart';
import '../core/modeller.dart';
import 'adisyon_pencereleri.dart';
import 'kasa_pencereleri.dart';
import 'ortak.dart';
import 'urun_secimi.dart';

/// KASA — web /panel/kasa (Cashier.vue) birebiri. Şartname:
/// /root/work/spec/kasa.md (bölüm numaraları ona göre).
///
/// İki kip (§1.2): SEÇİM (Adisyonlar / Borçlar / Bugün ödenenler kart
/// ızgarası) ve TAHSİLAT (ödeme işlemleri + adisyon ya da borç dökümü).
/// Üst ve alt şerit kabukta; bu widget yalnız gövdeyi çizer.
class KasaEkrani extends StatefulWidget {
  const KasaEkrani({super.key});

  @override
  State<KasaEkrani> createState() => _KasaEkraniState();
}

/// Borçlar ekranından "Kasada tahsil et": şahıs id'si gelince Borçlar
/// sekmesi o şahısla açılır (değer okununca null yapılır).
final kasaBorcIstegi = ValueNotifier<int?>(null);

/// Kart durumu (§1.3 kartDurum).
enum _KartDurum { acik, kismi, odendi, hesap }

class _KasaEkraniState extends State<KasaEkrani> {
  late final Api _api;
  Timer? _tur;
  int _modal = 0;
  final _odak = FocusNode(debugLabel: 'kasa');

  /* seçim kipi */
  String _sekme = 'orders'; // orders | debts | paid
  List<AdisyonOzet> _adisyonlar = const [];
  bool _yukleniyor = true;
  List<Json> _borclular = const [];
  bool _borcYukleniyor = false;
  String _borcArama = '';

  /* tahsilat — adisyon */
  AdisyonOzet? _secili;
  Adisyon? _detay;
  bool _detayYasak = false;
  List<Json> _odemeler = const [];
  String _sagSekme = 'items';
  bool _duzelt = false;
  final Set<int> _kalemSecim = {};
  String _tutar = '';
  String _verilen = '';
  final _bahsis = TextEditingController();
  String? _yontem;
  bool _yuvarla = false;
  String _hedef = 'amount'; // amount | tendered | debt | debtTendered | iskonto
  bool _taze = true;
  bool _odeniyor = false;
  bool _mesgul = false;
  Json? _pos;
  int? _kasaId;
  bool _indirimPaneli = false;
  List<Json>? _hazirIndirimler;
  final _iskontoMetin = TextEditingController();

  /* tahsilat — borç */
  Json? _borclu;
  List<Json> _hareketler = const [];
  Json? _dokum;
  bool _dokumYukleniyor = false;
  String _borcSag = 'dokum';
  String _borcTutar = '';
  String _borcVerilen = '';
  String _borcIskonto = '';
  String? _borcYontem;
  ({int tahsil, int onceki, int kalan, String yontem, Json dokum})? _sonBorcFisi;

  /* bugün ödenenler */
  String? _kilit;
  Timer? _kilitSayaci;
  Json? _odenenler;
  String? _kilitHata;

  /* yazıcı */
  List<Json> _yazicilar = const [];
  int? _yazici;
  bool _ajanVar = false;

  Oturum get _o => context.durum.oturum!;
  bool _can(String k) => _o.yetki(k) || _o.yetkiler.contains('*');
  bool get _odemeYetkisi => _can('payments.take');
  bool get _iadeYetkisi => _can('payments.refund');
  bool get _indirimYetkisi => _can('orders.discount');
  bool get _borcIskontoAcik => _indirimYetkisi && _o.eklenti('borc_iskonto', varsayilan: false);
  bool get _kalemDuzenler => _can('orders.update');
  bool get _ikramEder => _can('orders.comp');
  bool get _bahsisAcik => _o.eklenti('tips', varsayilan: false);

  @override
  void initState() {
    super.initState();
    _api = context.api;
    _yukle();
    _posDurumu();
    _kasalariYukle();
    _yazicilariYukle();
    _tur = Timer.periodic(const Duration(seconds: 5), (_) => _kasaTuru());
    kasaBorcIstegi.addListener(_borcIstegi);
    _borcIstegi();
  }

  Future<void> _borcIstegi() async {
    final id = kasaBorcIstegi.value;
    if (id == null || !mounted) return;
    kasaBorcIstegi.value = null;
    setState(() => _sekme = 'debts');
    await _borclulariYukle();
    final d = _borclular.where((x) => tamSayi(x['id']) == id && tamSayi(x['balance_minor']) > 0).firstOrNull;
    if (d != null && mounted) _borcluSec(d);
  }

  @override
  void dispose() {
    _tur?.cancel();
    kasaBorcIstegi.removeListener(_borcIstegi);
    _kilitSayaci?.cancel();
    _odak.dispose();
    _bahsis.dispose();
    _iskontoMetin.dispose();
    super.dispose();
  }

  /* ═════════════ Yükleme / yoklama (§6) ═════════════ */

  void _kasaTuru() {
    if (!mounted || _modal > 0 || _duzelt) return;
    _yukle(sessiz: true);
    _posDurumu(sessiz: true);
    if (_secili != null) _seciliyiTazele();
  }

  Future<void> _yukle({bool sessiz = false}) async {
    try {
      final r = await _api.get('/api/v1/payments/pending-orders', sorgu: {'q': ''});
      final l = (r is Map ? r['orders'] as List? : null) ?? const [];
      if (!mounted) return;
      setState(() {
        _adisyonlar = l.whereType<Map>().map((e) => AdisyonOzet(e.cast<String, dynamic>())).toList();
        _yukleniyor = false;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      setState(() => _yukleniyor = false);
      if (!sessiz) context.bildir2('Adisyonlar yüklenemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _posDurumu({bool sessiz = false}) async {
    try {
      final r = await _api.get('/api/v1/payments/terminal-status');
      if (mounted && r is Map) setState(() => _pos = r.cast<String, dynamic>());
    } on ApiHata {
      if (!sessiz && mounted) setState(() => _pos = null);
    }
  }

  Future<void> _kasalariYukle() async {
    try {
      final r = await _api.get('/api/v1/cash/registers');
      final l = ((r is Map ? r['registers'] : null) as List? ?? const []).whereType<Map>().toList();
      final acik = l.where((k) => k['open_session'] != null).firstOrNull;
      if (mounted) setState(() => _kasaId = acik == null ? null : tamSayi(acik['id']));
    } on ApiHata {
      // Kasa yetkisi yoksa sessiz; sunucu oturumu otomatik açar (§4.19).
    }
  }

  Future<void> _yazicilariYukle() async {
    try {
      final r = await _api.get('/api/v1/print/targets');
      if (r is! Map || !mounted) return;
      final d = r['defaults'] is Map ? r['defaults'] as Map : const {};
      setState(() {
        _yazicilar = (r['printers'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _ajanVar = r['agent_online'] == true;
        _yazici = d['cashier'] == null ? null : tamSayi(d['cashier']);
      });
    } on ApiHata {
      // Yazıcı listesi yoksa fiş önizlemeyle kalır.
    }
  }

  Future<void> _borclulariYukle() async {
    setState(() => _borcYukleniyor = true);
    try {
      final r = await _api.get('/api/v1/receivables', sorgu: {'per_page': 200});
      final d = r is Map && r['receivables'] is Map ? (r['receivables'] as Map)['data'] : (r is Map ? r['receivables'] : null);
      if (!mounted) return;
      setState(() => _borclular = (d as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList());
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Şahıslar yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _borcYukleniyor = false);
    }
  }

  Future<T?> _penceredeyken<T>(Future<T?> Function() f) async {
    _modal++;
    try {
      return await f();
    } finally {
      _modal--;
    }
  }

  /* ═════════════ Adisyon seçimi (§4.1) ═════════════ */

  int get _kalan => _secili?.kalan ?? 0;
  int get _tutarMinor => paraCoz(_tutar) ?? 0;
  int get _bahsisMinor => _bahsisAcik ? (paraCoz(_bahsis.text) ?? 0) : 0;
  int? get _paraUstu {
    if (_yontem != 'cash' || _verilen.trim().isEmpty) return null;
    final v = paraCoz(_verilen);
    if (v == null) return null;
    return (v - _tutarMinor - _bahsisMinor).clamp(0, 1 << 40);
  }

  bool get _duzenlenebilir => (_detay?.acik ?? false) && _kalan > 0;

  Future<void> _sec(AdisyonOzet a) async {
    setState(() {
      _secili = a;
      _detay = null;
      _detayYasak = false;
      _odemeler = const [];
      _duzelt = false;
      _sagSekme = 'items';
      _kalemSecim.clear();
      _indirimPaneli = false;
      _borclu = null;
    });
    _formuSifirla();
    await Future.wait([_seciliyiTazele(hataGoster: true), _detayiTazele()]);
    _formuSifirla();
  }

  Future<void> _seciliyiTazele({bool hataGoster = false}) async {
    final s = _secili;
    if (s == null) return;
    try {
      final r = await _api.get('/api/v1/orders/${s.id}/payments');
      if (!mounted || _secili?.id != s.id || r is! Map) return;
      setState(() {
        if (r['order'] is Map) _secili = AdisyonOzet((r['order'] as Map).cast<String, dynamic>());
        _odemeler = (r['payments'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      });
    } on ApiHata catch (e) {
      if (hataGoster && mounted) context.bildir2('Adisyon yüklenemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _detayiTazele() async {
    final s = _secili;
    if (s == null) return;
    if (!(_kalemDuzenler || _ikramEder || _can('orders.view'))) {
      setState(() => _detayYasak = true);
      return;
    }
    try {
      final r = await _api.get('/api/v1/orders/${s.id}');
      if (!mounted || _secili?.id != s.id || r is! Map || r['order'] is! Map) return;
      setState(() => _detay = Adisyon((r['order'] as Map).cast<String, dynamic>()));
    } on ApiHata catch (e) {
      if (mounted && (e.kod == 401 || e.kod == 403)) setState(() => _detayYasak = true);
    }
  }

  void _formuSifirla() {
    if (!mounted) return;
    setState(() {
      _tutar = _kalan > 0 ? paraGirdisi(_kalan) : '';
      _verilen = '';
      _bahsis.clear();
      _yontem = null;
      _yuvarla = false;
      _hedef = 'amount';
      _taze = true;
    });
  }

  void _secimeDon() => setState(() {
        _secili = null;
        _detay = null;
        _borclu = null;
        _duzelt = false;
        _kalemSecim.clear();
        _indirimPaneli = false;
        _sonBorcFisi = null;
      });

  /// Kalem/indirim/iskonto değişikliği sonrası (§4.9 afterItemChange).
  Future<void> _degisimSonrasi({bool liste = true}) async {
    await Future.wait([_seciliyiTazele(), _detayiTazele()]);
    if (liste) _yukle(sessiz: true);
    if (mounted) {
      setState(() {
        _tutar = _kalan > 0 ? paraGirdisi(_kalan) : '';
        _taze = true;
      });
    }
  }

  /* ═════════════ Numpad (§3) ═════════════ */

  String _hedefMetni(String h) => switch (h) {
        'iskonto' => _borcIskonto,
        'debtTendered' => _borcVerilen,
        'debt' => _borcTutar,
        'tendered' => _verilen,
        _ => _tutar,
      };

  void _hedefYaz(String h, String v) {
    switch (h) {
      case 'iskonto':
        _borcIskonto = v;
      case 'debtTendered':
        _borcVerilen = v;
      case 'debt':
        _borcTutar = v;
      case 'tendered':
        _verilen = v;
      default:
        _tutar = v;
    }
  }

  void _tus(String k) {
    final borc = _hedef == 'debt' || _hedef == 'iskonto' || _hedef == 'debtTendered';
    if (borc ? _borclu == null : _secili == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      final tazeOlur = _hedef == 'amount' || _hedef == 'debt' || _hedef == 'iskonto';
      var m = _hedefMetni(_hedef);
      if (k == 'del') {
        if (tazeOlur && _taze) {
          m = '';
          _taze = false;
        } else if (m.isNotEmpty) {
          m = m.substring(0, m.length - 1);
        }
        _hedefYaz(_hedef, m);
        return;
      }
      if (tazeOlur && _taze) {
        m = '';
        _taze = false;
      }
      if (k == ',') {
        if (!m.contains(',')) m = '${m.isEmpty ? '0' : m},';
      } else {
        final i = m.indexOf(',');
        if (i >= 0 && m.length - i - 1 >= 2) return;
        m = m + k;
      }
      final aday = paraCoz(m) ?? 0;
      if (_hedef == 'amount' && aday > _kalan) m = paraGirdisi(_kalan);
      final bakiye = tamSayi(_borclu?['balance_minor']);
      if ((_hedef == 'debt' || _hedef == 'iskonto') && aday > bakiye) m = paraGirdisi(bakiye);
      _hedefYaz(_hedef, m);
    });
  }

  void _hizliTutar(double oran) => setState(() {
        _tutar = paraGirdisi(oran >= 1 ? _kalan : (_kalan * oran).ceil());
        _hedef = 'amount';
        _taze = true;
      });

  void _tutarYaz(int minor) => setState(() {
        _tutar = paraGirdisi(minor.clamp(0, _kalan));
        _hedef = 'amount';
        _taze = true;
      });

  Future<void> _bolPenceresi() async {
    final pay = await _penceredeyken(() => hesabiBolPenceresi(context, kalan: _kalan, misafir: _detay?.kisi ?? _secili?.kisi));
    if (pay != null) _tutarYaz(pay);
  }

  KeyEventResult _klavye(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isAltPressed || kb.isMetaPressed) return KeyEventResult.ignored;
    if (_secili == null || _kalan <= 0 || _modal > 0) return KeyEventResult.ignored;
    final birincil = FocusManager.instance.primaryFocus?.context;
    if (birincil != null && birincil.findAncestorWidgetOfExactType<EditableText>() != null) return KeyEventResult.ignored;
    final c = e.character;
    if (c != null && RegExp(r'^[0-9]$').hasMatch(c)) {
      _tus(c);
      return KeyEventResult.handled;
    }
    if (c == ',' || c == '.') {
      _tus(',');
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _tus('del');
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_odemeYetkisi && !_odeniyor) _ode();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /* ═════════════ Tahsilat (§4.2) ═════════════ */

  bool get _terminalYontemi => kasaYontemleri.any((y) => y.$1 == _yontem && y.$4);
  bool get _posManuel => (_pos?['simulated'] ?? true) == true || (_pos?['online'] ?? false) != true;

  String get _odemeDugmeMetni {
    if (_terminalYontemi) return _posManuel ? 'Manuel onayla (POS bağlı değil)' : 'Terminale gönder';
    return '${yontemAdi(_yontem)} ödemesini al';
  }

  Future<void> _ode() async {
    final s = _secili;
    if (s == null || _odeniyor) return;
    _odeniyor = true; // senkron kilit (§7.3)
    setState(() {});
    try {
      if (_tutarMinor <= 0) {
        context.bildir2('Tutar geçersiz', 'Pozitif bir tutar girin.', hata: true);
        return;
      }
      if (_yontem == null) {
        context.bildir2('Ödeme yöntemi seçin', 'Nakit, kart veya diğer yöntemlerden birini seçin.', hata: true);
        return;
      }
      final nakit = _yontem == 'cash';
      final govde = <String, dynamic>{
        'method': _yontem,
        'amount_minor': _tutarMinor,
        'tip_minor': _bahsisMinor,
        'tendered_minor': nakit && _verilen.trim().isNotEmpty ? paraCoz(_verilen) : null,
        'note': null,
        'round': _yuvarla,
        'cash_register_id': _kasaId,
        'expected_version': s.surum,
        if (_kalemSecim.isNotEmpty) 'item_ids': _kalemSecim.toList(),
      };
      final r = await _api.post('/api/v1/orders/${s.id}/payments', govde, {'Idempotency-Key': _api.yeniIslemKimligi()});
      if (!mounted) return;
      final p = r is Map && r['payment'] is Map ? r['payment'] as Map : const {};
      final durum = '${p['status'] ?? ''}';
      if (durum == 'succeeded') {
        final ust = tamSayi(p['change_minor']);
        context.bildir2('Ödeme alındı', '${p['method_label'] ?? yontemAdi(_yontem)} — ${para(tamSayi(p['amount_minor']))}${ust > 0 ? ' · Para üstü ${para(ust)}' : ''}');
      } else if (durum == 'pending') {
        context.bildir2('Terminale gönderildi', 'Terminal onayı bekleniyor — gönderim tahsilat DEĞİLDİR; sonucu sorgulayın.');
      } else {
        final pr = r is Map && r['provider_result'] is Map ? r['provider_result'] as Map : const {};
        context.bildir2('Ödeme başarısız', '${pr['message'] ?? 'Sağlayıcı reddetti.'}', hata: true);
      }
      await _seciliyiTazele();
      await _detayiTazele();
      _yukle(sessiz: true);
      if (mounted) setState(_kalemSecim.clear);
      _formuSifirla();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Ödeme alınamadı', e.mesaj, hata: true);
      _seciliyiTazele();
    } finally {
      _odeniyor = false;
      if (mounted) setState(() {});
    }
  }

  /* ═════════════ Kalem seçimi (§4.4) ═════════════ */

  List<Kalem> get _gorunenKalemler => _detay?.aktifKalemler ?? const [];

  int get _seciliToplam => _gorunenKalemler.where((k) => _kalemSecim.contains(k.id) && !k.ikram && !k.odendi).fold(0, (t, k) => t + k.tutar);

  void _kalemDokun(Kalem k) {
    if (_duzelt || k.ikram || k.odendi) return;
    setState(() {
      _kalemSecim.contains(k.id) ? _kalemSecim.remove(k.id) : _kalemSecim.add(k.id);
    });
    _seciminiYaz();
  }

  void _seciminiYaz() => setState(() {
        _tutar = paraGirdisi(_kalemSecim.isEmpty ? _kalan : _seciliToplam.clamp(0, _kalan));
        _hedef = 'amount';
        _taze = true;
      });

  /* ═════════════ Adisyon üzerinde işlemler ═════════════ */

  Future<bool> _islem(Future<dynamic> Function() f, {String? ok, String okMetin = '', String hataBaslik = 'İşlem tamamlanamadı', bool liste = true}) async {
    if (_mesgul) return false;
    setState(() => _mesgul = true);
    try {
      await f();
      if (ok != null && mounted) context.bildir2(ok, okMetin);
      await _degisimSonrasi(liste: liste);
      return true;
    } on ApiHata catch (e) {
      if (mounted) context.bildir2(hataBaslik, e.mesaj, hata: true);
      _detayiTazele();
      return false;
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  String get _oyol => '/api/v1/orders/${_secili!.id}';
  int get _surum => _detay?.surum ?? _secili?.surum ?? 0;

  Future<void> _adet(Kalem k, int yeni) => _islem(
        () => _api.put('$_oyol/items/${k.id}', {'qty': yeni, 'expected_version': _surum}),
        ok: 'Adet güncellendi',
        okMetin: '${k.ad} — $yeni adet',
        hataBaslik: 'Güncellenemedi',
      );

  Future<void> _cikar(Kalem k) async {
    final evet = await _penceredeyken(() => onayla(context, 'Kalemi çıkar', '${k.ad} adisyondan çıkarılacak. Tutar buna göre güncellenir.', onay: 'Kalemi çıkar', tehlikeli: true));
    if (evet != true || !mounted) return;
    await _islem(() => _api.delete('$_oyol/items/${k.id}', {'expected_version': _surum}), ok: 'Kalem çıkarıldı', okMetin: k.ad, hataBaslik: 'Çıkarılamadı');
  }

  Future<void> _ikram(Kalem k) async {
    final neden = await _penceredeyken(() => ikramPenceresi(context, k.ad));
    if (neden == null || !mounted) return;
    await _islem(() => _api.post('$_oyol/items/${k.id}/comp', {'reason': neden, 'expected_version': _surum}),
        ok: 'İkram işlendi', okMetin: '${k.ad} ücretsiz', hataBaslik: 'İşlenemedi');
  }

  Future<void> _ikramKaldir(Kalem k) => _islem(() => _api.delete('$_oyol/items/${k.id}/comp', {'expected_version': _surum}),
      ok: 'İkram kaldırıldı', okMetin: '${k.ad} yeniden ücretli', hataBaslik: 'İşlenemedi');

  Future<void> _kalemDegistir(Kalem k) async {
    final katalog = KatalogDeposu.ornek.katalog ?? await KatalogDeposu.ornek.yukle(context.durum);
    final u = k.urunId == null ? null : katalog?.urun(k.urunId!);
    if (!mounted) return;
    if (u == null) {
      // Ürün katalogda yoksa yalnız adet/not değişir.
      final not = await _penceredeyken(() => metinSor(context, baslik: 'Kalemi değiştir — ${k.ad}', ilkDeger: k.not, ipucu: 'Not'));
      if (not == null || !mounted) return;
      await _islem(() => _api.put('$_oyol/items/${k.id}', {'qty': k.adet, 'note': not.isEmpty ? null : not, 'expected_version': _surum}),
          ok: 'Kalem güncellendi', okMetin: k.ad, hataBaslik: 'Güncellenemedi');
      return;
    }
    final s = await _penceredeyken(() => urunSecimiAc(context, u));
    if (s == null || !mounted) return;
    await _islem(
      () => _api.put('$_oyol/items/${k.id}', {'qty': s.adet, 'note': s.not, 'option_ids': s.secenekler, 'expected_version': _surum}),
      ok: 'Kalem güncellendi',
      okMetin: '${k.ad} — ${s.adet} adet · ${para(s.birimFiyat * s.adet)}',
      hataBaslik: 'Güncellenemedi',
    );
  }

  Future<void> _urunEkle() async {
    final katalog = KatalogDeposu.ornek.katalog ?? await KatalogDeposu.ornek.yukle(context.durum);
    if (!mounted) return;
    if (katalog == null) {
      context.bildir2('Katalog getirilemedi', 'Bağlantıyı kontrol edip tekrar deneyin.', hata: true);
      return;
    }
    final u = await _penceredeyken(() => urunSecPenceresi(context, katalog));
    if (u == null || !mounted) return;
    UrunSecimi? s;
    if (u.secimGerekir) {
      s = await _penceredeyken(() => urunSecimiAc(context, u, kanal: _secili?.kanal ?? 'table'));
      if (s == null || !mounted) return;
    }
    final varyant = s?.varyantId ?? (u.varyantlar.isEmpty ? null : u.varyantlar.firstWhere((v) => v.varsayilan, orElse: () => u.varyantlar.first).id);
    final adet = s?.adet ?? u.minAdet;
    await _islem(
      () => _api.post(
        '$_oyol/items',
        {'product_id': u.id, 'variant_id': varyant, 'qty': adet, 'option_ids': s?.secenekler ?? const <int>[], 'note': s?.not, 'expected_version': _surum},
        {'Idempotency-Key': _api.yeniIslemKimligi()},
      ),
      ok: '${u.ad} eklendi',
      okMetin: '$adet adet · ${para((s?.birimFiyat ?? u.gorunenFiyat) * adet)}',
      hataBaslik: 'Eklenemedi',
    );
  }

  Future<void> _indirimDiyalogu() async {
    final d = _detay;
    if (d == null) return;
    final degisti = await _penceredeyken(() => indirimPenceresi(context, d));
    if (degisti == true && mounted) await _degisimSonrasi();
  }

  Future<void> _servisBedeli() async {
    final varMi = tamSayi(_detay?.ham['service_charge_minor'] ?? _secili?.ham['service_charge_minor']) > 0;
    final r = await _penceredeyken(() => servisBedeliPenceresi(context, varMi: varMi));
    if (r == null || !mounted) return;
    if (r.$1 == 'kaldir') {
      await _islem(() => _api.delete('$_oyol/service-charge', {'expected_version': _surum}), ok: 'Servis bedeli kaldırıldı', hataBaslik: 'Uygulanamadı', liste: false);
    } else {
      await _islem(() => _api.post('$_oyol/service-charge', {'type': r.$2, 'value': r.$3, 'reason': 'Servis bedeli'}),
          ok: 'Servis bedeli eklendi', hataBaslik: 'Uygulanamadı', liste: false);
    }
  }

  Future<void> _sipariseGeriGonder() async {
    if (_mesgul) return;
    setState(() => _mesgul = true);
    try {
      await _api.post('$_oyol/send-to-service', {'expected_version': _surum});
      if (!mounted) return;
      context.bildir2('Siparişe geri gönderildi', 'Adisyon yeniden serviste; garson devam edebilir.');
      _secimeDon();
      _yukle(sessiz: true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Gönderilemedi', e.mesaj.isEmpty ? 'Lütfen tekrar deneyin.' : e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _borcaYaz() async {
    final s = _secili;
    if (s == null) return;
    final ucretli = _gorunenKalemler.where((k) => !k.ikram && !k.odendi).toList();
    final seciliUcretli = ucretli.where((k) => _kalemSecim.contains(k.id)).toList();
    final kismi = seciliUcretli.isNotEmpty && seciliUcretli.length < ucretli.length;
    final tutar = seciliUcretli.fold<int>(0, (t, k) => t + k.tutar);
    final r = await _penceredeyken(() => borcaYazPenceresi(
          context,
          baslik: _baslik(s),
          kalan: _kalan,
          kismi: kismi,
          seciliAdet: seciliUcretli.length,
          seciliTutar: tutar,
          mevcutCari: s.ham['receivable_id'] == null ? null : tamSayi(s.ham['receivable_id']),
        ));
    if (r == null || !mounted) return;
    setState(() => _mesgul = true);
    try {
      var cari = r.cariId;
      if (cari == null) {
        final y = await _api.post('/api/v1/receivables', {'name': r.yeniAd, 'phone': r.yeniTelefon});
        cari = y is Map && y['receivable'] is Map ? tamSayi((y['receivable'] as Map)['id']) : null;
      }
      if (cari == null) throw ApiHata(422, 'Şahıs oluşturulamadı.');
      if (kismi) {
        await _api.post('$_oyol/kalemleri-borca-yaz', {'item_ids': seciliUcretli.map((k) => k.id).toList(), 'receivable_id': cari, 'reason': r.neden});
        if (!mounted) return;
        context.bildir2('Seçili kalemler borca yazıldı', '${seciliUcretli.length} kalem · ${para(tutar)} şahsın borcuna aktarıldı; adisyonun kalanı açık.');
        setState(_kalemSecim.clear);
        await _degisimSonrasi();
      } else {
        await _api.post('$_oyol/transfer-to-debt', {'receivable_id': cari, 'reason': r.neden});
        if (!mounted) return;
        context.bildir2('Borca taşındı', '${_baslik(s)} borç hesabına aktarıldı.');
        _secimeDon();
        _yukle(sessiz: true);
      }
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Borca taşınamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  /* ── satır içi indirim / iskonto paneli (§4.6) ── */

  Future<void> _indirimPaneliAc() async {
    setState(() => _indirimPaneli = !_indirimPaneli);
    if (_indirimPaneli && _hazirIndirimler == null) {
      try {
        final r = await _api.get('/api/v1/discount-presets');
        if (mounted) {
          setState(() => _hazirIndirimler = ((r is Map ? r['presets'] : null) as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList());
        }
      } on ApiHata {
        if (mounted) setState(() => _hazirIndirimler = const []);
      }
    }
  }

  Future<void> _hazirIndirim(Json p) => _islem(() => _api.post('$_oyol/discount', {'preset_id': p['id'], 'expected_version': _surum}),
      ok: 'İndirim uygulandı', okMetin: '${p['name']} · ${p['value_label']}', hataBaslik: 'İndirim uygulanamadı');

  Future<void> _indirimKaldir() => _islem(() => _api.delete('$_oyol/discount', {'expected_version': _surum}),
      ok: 'İndirim kaldırıldı', okMetin: 'Tutar yeniden hesaplandı.', hataBaslik: 'İndirim kaldırılamadı');

  Future<void> _iskontoUygula({required bool hedefKip}) async {
    final girilen = paraCoz(_iskontoMetin.text) ?? 0;
    final toplam = _secili?.toplam ?? 0;
    final deger = hedefKip ? (toplam - girilen).clamp(0, 1 << 40) : girilen;
    if (deger <= 0) {
      context.bildir2('Tutar geçersiz', hedefKip ? 'Hedef tutar, adisyon toplamından küçük olmalı.' : 'Pozitif bir indirim tutarı girin.', hata: true);
      return;
    }
    if (deger >= toplam + tamSayi(_secili?.ham['discount_minor'])) {
      context.bildir2('İndirim çok yüksek', 'İndirim adisyon toplamını aşamaz.', hata: true);
      return;
    }
    final ok = await _islem(
      () => _api.post('$_oyol/iskonto', {'amount_minor': deger, 'reason': hedefKip ? "Kasada hesap ${para(girilen)}'ye indirildi" : 'Kasada iskonto'}),
      ok: 'İskonto uygulandı',
      okMetin: '${para(deger)} düşüldü — yeni tutar ${para(toplam - deger)}',
      hataBaslik: 'İskonto uygulanamadı',
    );
    if (ok) _iskontoMetin.clear();
  }

  Future<void> _iskontoKaldir() => _islem(() => _api.delete('$_oyol/iskonto'), ok: 'İskonto kaldırıldı', okMetin: 'Adisyon eski tutarına döndü.', hataBaslik: 'İskonto kaldırılamadı');

  /* ── ödemeler: sorgula / void / iade / yöntem (§4.11, §4.12) ── */

  Future<void> _sorgula(Json p) async {
    try {
      final r = await _api.post('/api/v1/payments/${p['id']}/query');
      final pr = r is Map && r['provider_result'] is Map ? r['provider_result'] as Map : const {};
      final d = r is Map && r['payment'] is Map ? '${(r['payment'] as Map)['status']}' : '';
      if (!mounted) return;
      if (d == 'succeeded') {
        context.bildir2('Ödeme doğrulandı', 'Sağlayıcı işlemi onayladı.');
      } else if (d == 'failed') {
        context.bildir2('Ödeme reddedilmiş', '${pr['message'] ?? ''}', hata: true);
      } else {
        context.bildir2('Hâlâ bekliyor', '${pr['message'] ?? 'Sağlayıcı işliyor; tekrar deneyin.'}');
      }
      await _degisimSonrasi();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Sorgulanamadı', e.mesaj, hata: true);
    }
  }

  Future<void> _void(Json p) async {
    final neden = await _penceredeyken(() => odemeyiKaldirPenceresi(context));
    if (neden == null || !mounted) return;
    final pin = await _penceredeyken(() => personelPinSor(context));
    if (pin == null || !mounted) return;
    final ok = await _islem(() => _api.post('/api/v1/payments/${p['id']}/void', {'reason': neden, ...pin}),
        ok: 'Ödeme iptal edildi', okMetin: 'Tahsilat geri alındı; adisyon yeniden açıldı.', hataBaslik: 'İptal edilemedi');
    if (ok) _odenenleriYenile();
  }

  Future<void> _iade(Json p) async {
    final r = await _penceredeyken(() => iadePenceresi(context, p));
    if (r == null || !mounted) return;
    final pin = await _penceredeyken(() => personelPinSor(context));
    if (pin == null || !mounted) return;
    await _islem(() => _api.post('/api/v1/payments/${p['id']}/refund', {'amount_minor': r.tutar, 'reason': r.neden, ...pin}),
        ok: 'İade yapıldı', okMetin: '${para(r.tutar)} iade edildi.', hataBaslik: 'İade edilemedi');
  }

  Future<void> _yontemDegistir(Json p) async {
    final r = await _penceredeyken(() => yontemDegistirPenceresi(context, p));
    if (r == null || !mounted) return;
    final pin = await _penceredeyken(() => personelPinSor(context));
    if (pin == null || !mounted) return;
    final ok = await _islem(() => _api.post('/api/v1/payments/${p['id']}/yontem', {'method': r.yontem, 'reason': r.neden, ...pin}),
        ok: 'Ödeme yöntemi düzeltildi',
        okMetin: '${para(tamSayi(p['amount_minor']))} artık ${yontemAdi(r.yontem)} olarak kayıtlı; raporlar ve kasa güncellendi.',
        hataBaslik: 'Yöntem değiştirilemedi');
    if (ok) _odenenleriYenile();
  }

  /* ═════════════ Fiş (§4.18) ═════════════ */

  String? get _yaziciAdi => _yazici == null ? null : _yazicilar.where((y) => tamSayi(y['id']) == _yazici).map((y) => '${y['name']}').firstOrNull ?? 'seçili';

  String _zaman(DateTime t) =>
      '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _oran(Object? v) {
    final d = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return d == d.roundToDouble() ? '%${d.toInt()}' : '%${d.toStringAsFixed(1)}';
  }

  /// Adisyon fişi verisi (hesap / ödeme).
  Json _fisVerisi(String tur) {
    final s = _secili!;
    final d = _detay;
    final h = d?.ham ?? s.ham;
    final hedef = s.masaAdi ?? s.cariAdi ?? s.musteri ?? s.kanalEtiket;
    final etiket = tur == 'bill' ? 'HESAP FİŞİ' : 'ADİSYON FİŞİ';
    final satirlar = <Json>[];
    var cesit = 0;
    var adet = 0;
    for (final k in d?.aktifKalemler ?? const <Kalem>[]) {
      cesit++;
      adet += k.adet;
      satirlar.add({'name': '${k.adet}x ${k.ad}${k.varyant != null ? ' (${k.varyant})' : ''}', 'amount': k.ikram ? 'İKRAM' : tl(k.tutar)});
      if (k.adet > 1 && !k.ikram) satirlar.add({'name': '    ${k.adet} × ${tl(k.birimFiyat)}', 'amount': ''});
      if (k.secenekler.isNotEmpty) satirlar.add({'name': '    ${k.secenekler.join(' · ')}', 'amount': ''});
      if (k.not != null && k.not!.isNotEmpty) satirlar.add({'name': '    » ${k.not}', 'amount': ''});
    }
    if (cesit > 0) satirlar.add({'name': '$cesit çeşit · $adet adet ürün', 'amount': ''});

    final toplamlar = <Json>[
      {'label': 'Ara toplam', 'value': tl(tamSayi(h['items_total_minor']))},
      if (tamSayi(h['comp_total_minor']) > 0) {'label': 'İkram', 'value': '-${tl(tamSayi(h['comp_total_minor']))}'},
      if (tamSayi(h['discount_minor']) > 0) {'label': 'İndirim', 'value': '-${tl(tamSayi(h['discount_minor']))}'},
      if (tamSayi(h['iskonto_minor']) > 0)
        {'label': 'İskonto${h['iskonto_reason'] != null ? ' (${h['iskonto_reason']})' : ''}', 'value': '-${tl(tamSayi(h['iskonto_minor']))}'},
      if (tamSayi(h['service_charge_minor']) > 0) {'label': 'Servis', 'value': tl(tamSayi(h['service_charge_minor']))},
      if (tamSayi(h['rounding_minor']) != 0) {'label': 'Yuvarlama', 'value': tl(tamSayi(h['rounding_minor']))},
      {'label': 'TOPLAM', 'value': tl(s.toplam), 'big': true},
    ];
    final kdv = (h['vat_by_rate'] as List? ?? const []).whereType<Map>().toList();
    if (kdv.length == 1) {
      toplamlar.add({'label': 'KDV ${_oran(kdv.first['rate'])} (dahil)', 'value': tl(tamSayi(kdv.first['vat_minor']))});
    } else {
      toplamlar.add({'label': 'Toplam KDV (dahil)', 'value': tl(tamSayi(h['vat_total_minor']))});
      for (final v in kdv) {
        toplamlar.add({'label': '  KDV ${_oran(v['rate'])} (dahil)', 'value': tl(tamSayi(v['vat_minor']))});
      }
    }
    if (tur == 'payment') {
      toplamlar.add({'label': 'Ödenen', 'value': tl(s.odenen)});
      if (s.kalan > 0) toplamlar.add({'label': 'Kalan', 'value': tl(s.kalan)});
    }

    // Ödemeler yönteme göre birleşik (§7.13).
    final basarili = _odemeler.where((p) => p['kind'] == 'payment' && p['status'] == 'succeeded').toList();
    final yontemler = <String, ({int tutar, int ust})>{};
    for (final p in basarili) {
      final k = '${p['method_label'] ?? p['method']}';
      final e = yontemler[k];
      yontemler[k] = (tutar: (e?.tutar ?? 0) + tamSayi(p['amount_minor']), ust: (e?.ust ?? 0) + tamSayi(p['change_minor']));
    }
    final odemeler = <Json>[
      for (final e in yontemler.entries) {'label': '${e.key}${e.value.ust > 0 ? ' (para üstü ${tl(e.value.ust)})' : ''}', 'value': tl(e.value.tutar)},
      if (tur == 'payment' && basarili.isNotEmpty) {'label': basarili.length == 1 ? 'Tek işlemde ödendi' : '${basarili.length} işlemde (parçada) ödendi', 'value': ''},
    ];
    final sube = _o.sube ?? '';
    final kisi = d?.kisi ?? s.kisi;
    return {
      'business': _o.isletme,
      'branch': [sube, s.kanalEtiket, if (kisi != null) '$kisi kişi'].where((x) => x.isNotEmpty).join(' · '),
      'kindLabel': etiket,
      'destination': hedef,
      'orderNo': '${s.id}',
      'title': '$hedef · $etiket #${s.id}',
      'time': _zaman(DateTime.now()),
      'lines': satirlar,
      'totals': toplamlar,
      'payments': odemeler,
      'footer': tur == 'bill'
          ? ['Bu fiş ön-hesaptır — ödeme kasada alınır.', 'Bu belge bilgi amaçlıdır, mali değeri yoktur.', 'Ön-hesap · #${s.id}']
          : ['Bizi tercih ettiğiniz için teşekkürler', 'Bu belge bilgi amaçlıdır, mali değeri yoktur.', 'Adisyon kapanışı · #${s.id}'],
    };
  }

  Future<void> _fisGonder(Json fis, {int? siparis, required String baslik}) async {
    if (_yazici == null) {
      await _yaziciSec(uyari: true);
      return;
    }
    try {
      await _api.post('/api/v1/print/receipt', {'printer_id': _yazici, 'order_id': ?siparis, 'title': baslik, 'receipt': fis});
      if (mounted) context.bildir2('Fiş yazıcıya gönderildi', _yaziciAdi ?? '');
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Yazıcıya gönderilemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _fisYazdir(String tur) async {
    final s = _secili;
    if (s == null) return;
    await _fisGonder(_fisVerisi(tur), siparis: s.id, baslik: '${tur == 'bill' ? 'Hesap' : 'Ödeme'} fişi #${s.id}');
  }

  Future<void> _fisOnizle(String tur) async {
    final s = _secili;
    if (s == null) return;
    final fis = _fisVerisi(tur);
    final yaz = await _penceredeyken(() => fisOnizle(context, baslik: tur == 'bill' ? 'Hesap fişi önizleme' : 'Ödeme fişi önizleme', fis: fis, yaziciAdi: _yaziciAdi));
    if (yaz == true && mounted) await _fisGonder(fis, siparis: s.id, baslik: '${tur == 'bill' ? 'Hesap' : 'Ödeme'} fişi #${s.id}');
  }

  Future<void> _yaziciSec({bool uyari = false}) async {
    if (uyari) context.bildir2('Yazıcı seçilmedi', 'Fişin çıkacağı kasa yazıcısını seçin.');
    await _yazicilariYukle();
    if (!mounted) return;
    final r = await _penceredeyken(() => yaziciPenceresi(context, yazicilar: _yazicilar, secili: _yazici, ajanVar: _ajanVar, adisyonVar: _secili != null));
    if (r == null || !mounted) return;
    final yeni = r.yazici == 0 ? null : r.yazici;
    if (yeni != _yazici) {
      try {
        await _api.post('/api/v1/print/targets/default', {'printer_id': yeni, 'station': 'cashier'});
        if (!mounted) return;
        setState(() => _yazici = yeni);
        context.bildir2(yeni == null ? 'Yazıcı seçimi kaldırıldı' : 'Kasa yazıcısı seçildi',
            yeni == null ? 'Fişler için yeniden yazıcı seçmeniz gerekir.' : 'Tüm cihazlarda fişler “$_yaziciAdi” yazıcısına gidecek.');
      } on ApiHata {
        if (mounted) context.bildir2('Kaydedilemedi', 'Seçim sunucuya yazılamadı.', hata: true);
      }
    }
    if (r.deneme) _fisYazdir('bill');
  }

  /* ═════════════ Borç tahsilatı (§4.17) ═════════════ */

  int get _bakiye => tamSayi(_borclu?['balance_minor']);
  int get _borcTutarMinor => paraCoz(_borcTutar) ?? 0;

  Future<void> _borcluSec(Json d) async {
    setState(() {
      _borclu = d;
      _secili = null;
      _detay = null;
      _borcTutar = paraGirdisi(tamSayi(d['balance_minor']));
      _borcYontem = null;
      _borcIskonto = '';
      _borcVerilen = '';
      _sonBorcFisi = null;
      _hedef = 'debt';
      _taze = true;
      _borcSag = 'dokum';
    });
    await _borcluTazele();
  }

  Future<void> _borcluTazele() async {
    final b = _borclu;
    if (b == null) return;
    setState(() => _dokumYukleniyor = true);
    try {
      final r = await Future.wait([
        _api.get('/api/v1/receivables/${b['id']}'),
        _api.get('/api/v1/receivables/${b['id']}/borc-dokumu'),
      ]);
      if (!mounted || _borclu?['id'] != b['id']) return;
      setState(() {
        final a = r[0];
        if (a is Map) {
          if (a['receivable'] is Map) _borclu = (a['receivable'] as Map).cast<String, dynamic>();
          _hareketler = (a['transactions'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        }
        if (r[1] is Map) _dokum = (r[1] as Map).cast<String, dynamic>();
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Şahıs yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _dokumYukleniyor = false);
    }
  }

  Future<void> _borcTahsil() async {
    final b = _borclu;
    if (b == null || _mesgul) return;
    if (_borcYontem == null) {
      context.bildir2('Ödeme yöntemi seçin', 'Nakit, kart, havale veya diğer yöntemlerden birini seçin.', hata: true);
      return;
    }
    final t = _borcTutarMinor;
    if (t <= 0) {
      context.bildir2('Tutar geçersiz', 'Pozitif bir tutar girin.', hata: true);
      return;
    }
    if (t > _bakiye) {
      context.bildir2('Tutar borcu aşıyor', 'Güncel borç ${para(_bakiye)}.', hata: true);
      return;
    }
    setState(() => _mesgul = true);
    final onceki = _bakiye;
    final dokum = _dokum ?? const <String, dynamic>{};
    final yontem = _borcYontem!;
    try {
      final r = await _api.post('/api/v1/receivables/${b['id']}/collect', {'amount_minor': t, 'method': yontem, 'note': null});
      if (!mounted) return;
      final yeni = r is Map && r['receivable'] is Map ? (r['receivable'] as Map).cast<String, dynamic>() : null;
      final kalan = yeni == null ? onceki - t : tamSayi(yeni['balance_minor']);
      context.bildir2('Borç tahsil edildi', '${b['name']} — ${para(t)} · kalan borç ${para(kalan)}');
      setState(() {
        _sonBorcFisi = (tahsil: t, onceki: onceki, kalan: kalan, yontem: yontem, dokum: dokum);
        if (yeni != null) _borclu = yeni;
        _borcTutar = paraGirdisi(kalan);
        _borcVerilen = '';
        _taze = true;
      });
      _borclulariYukle();
      await _borcluTazele();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Tahsil edilemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _borcIskontoYap() async {
    final b = _borclu;
    final x = paraCoz(_borcIskonto) ?? 0;
    if (b == null || _mesgul) return;
    if (x <= 0 || x > _bakiye) {
      context.bildir2('Tutar geçersiz', 'İskonto 0 ile güncel borç (${para(_bakiye)}) arasında olmalı.', hata: true);
      return;
    }
    setState(() => _mesgul = true);
    try {
      final r = await _api.post('/api/v1/receivables/${b['id']}/iskonto', {'amount_minor': x});
      final yeni = r is Map && r['receivable'] is Map ? (r['receivable'] as Map).cast<String, dynamic>() : null;
      if (!mounted) return;
      context.bildir2('İskonto uygulandı', '${b['name']} — ${para(x)} borçtan düşüldü · kalan borç ${para(yeni == null ? _bakiye - x : tamSayi(yeni['balance_minor']))}');
      setState(() {
        if (yeni != null) _borclu = yeni;
        _borcIskonto = '';
        _borcTutar = paraGirdisi(_bakiye);
        _hedef = 'debt';
        _taze = true;
      });
      _borclulariYukle();
      await _borcluTazele();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('İskonto uygulanamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _borcIskontoGeriAl(int tid, int tutar, {required bool degistir}) async {
    final b = _borclu;
    if (b == null) return;
    final evet = await _penceredeyken(() => onayla(
          context,
          degistir ? 'İskontoyu değiştir' : 'İskontoyu kaldır',
          '${para(tutar)} iskonto kaldırılacak; ${b['name']} borcu ${para(_bakiye + tutar)} olacak.${degistir ? ' Ardından yeni tutarı iskonto kutusuna yazıp "İndir"e basın.' : ''}',
          onay: degistir ? 'Kaldır ve değiştir' : 'Kaldır',
          tehlikeli: !degistir,
        ));
    if (evet != true || !mounted) return;
    try {
      final r = await _api.post('/api/v1/receivables/${b['id']}/iskonto/$tid/geri-al');
      final yeni = r is Map && r['receivable'] is Map ? (r['receivable'] as Map).cast<String, dynamic>() : null;
      if (!mounted) return;
      context.bildir2('İskonto kaldırıldı', '${b['name']} — ${para(tutar)} borca eklendi · borç ${para(yeni == null ? _bakiye + tutar : tamSayi(yeni['balance_minor']))}');
      setState(() {
        if (yeni != null) _borclu = yeni;
        if (degistir) {
          _borcIskonto = paraGirdisi(tutar);
          _hedef = 'iskonto';
        }
      });
      _borclulariYukle();
      await _borcluTazele();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('İskonto kaldırılamadı', e.mesaj, hata: true);
    }
  }

  Json _borcFisVerisi() {
    final f = _sonBorcFisi!;
    final b = _borclu!;
    final ad = '${b['name']}';
    final siparisler = (f.dokum['orders'] as List? ?? const []).whereType<Map>().toList();
    final yAd = switch (f.yontem) { 'cash' => 'Nakit', 'card' => 'Kart', 'transfer' => 'Havale/EFT', _ => 'Diğer' };
    final kdv = tamSayi(f.dokum['vat_total_minor']);
    return {
      'business': _o.isletme,
      'branch': [_o.sube ?? '', 'Şahıs borç tahsilatı'].where((x) => x.isNotEmpty).join(' · '),
      'kindLabel': 'BORÇ TAHSİLAT FİŞİ',
      'destination': ad,
      'orderNo': 'Şahıs #${b['id']}',
      'title': '$ad · BORÇ TAHSİLAT FİŞİ',
      'time': _zaman(DateTime.now()),
      'lines': [
        for (final o in siparisler)
          {
            'name': [
              'Adisyon #${o['order_id']}',
              if (o['table'] != null) '${o['table']}',
              if (tamSayi(o['iskonto_minor']) > 0) 'iskonto −${tl(tamSayi(o['iskonto_minor']))}',
              if (tamSayi(o['discount_minor']) > 0) 'indirim −${tl(tamSayi(o['discount_minor']))}',
              if (tamSayi(o['borc_iskonto_minor']) > 0) 'borç iskontosu −${tl(tamSayi(o['borc_iskonto_minor']))}',
            ].join(' · '),
            'amount': tl(tamSayi(o['remaining_minor'])),
          },
      ],
      'totals': [
        {'label': 'Önceki borç', 'value': tl(f.onceki)},
        {'label': 'TAHSİL EDİLEN', 'value': tl(f.tahsil), 'big': true},
        {'label': 'Kalan borç', 'value': tl(f.kalan)},
        if (kdv > 0) {'label': 'Toplam KDV (dahil)', 'value': tl(kdv)},
      ],
      'payments': [
        {'label': yAd, 'value': tl(f.tahsil)},
      ],
      'footer': ['Bizi tercih ettiğiniz için teşekkürler', 'Bu belge bilgi amaçlıdır, mali değeri yoktur.', 'Borç tahsilatı · Şahıs #${b['id']}'],
    };
  }

  Future<void> _borcFisi({bool onizle = false}) async {
    if (_sonBorcFisi == null || _borclu == null) return;
    final fis = _borcFisVerisi();
    final baslik = 'Borç tahsilat fişi · ${_borclu!['name']}';
    if (onizle) {
      final yaz = await _penceredeyken(() => fisOnizle(context, baslik: 'Tahsilat fişi önizleme', fis: fis, yaziciAdi: _yaziciAdi));
      if (yaz != true) return;
    }
    if (mounted) await _fisGonder(fis, baslik: baslik);
  }

  /* ═════════════ Bugün ödenenler (§4.14) ═════════════ */

  Future<void> _kilidiAc() async {
    final pin = await _penceredeyken(() => personelPinSor(context));
    if (pin == null || !mounted) return;
    try {
      final r = await _api.post('/api/v1/kasa/bugun-odenenler/kilit', pin);
      if (r is! Map || !mounted) return;
      final bitis = DateTime.tryParse('${r['bitis']}');
      setState(() {
        _kilit = '${r['anahtar']}';
        _kilitHata = null;
      });
      _kilitSayaci?.cancel();
      _kilitSayaci = Timer(bitis == null ? const Duration(minutes: 15) : bitis.difference(DateTime.now()), () {
        if (mounted) setState(() => _kilitle('Süre doldu; güvenlik için yeniden şifre isteniyor.'));
      });
      _odenenleriYenile();
    } on ApiHata catch (e) {
      if (mounted) setState(() => _kilitHata = e.kod == 403 ? 'Bu bölüm kasa yönetimine açıktır.' : e.mesaj);
    }
  }

  void _kilitle([String? hata]) {
    _kilit = null;
    _odenenler = null;
    _kilitHata = hata;
    _kilitSayaci?.cancel();
  }

  Future<void> _odenenleriYenile() async {
    final k = _kilit;
    if (k == null) return;
    try {
      final r = await _api.get('/api/v1/kasa/bugun-odenenler', sorgu: {'kilit': k});
      if (mounted && r is Map) setState(() => _odenenler = r.cast<String, dynamic>());
    } on ApiHata catch (e) {
      if (!mounted) return;
      if (e.kod == 423) {
        setState(() => _kilitle('Süre doldu; yeniden şifre girin.'));
      } else {
        context.bildir2('Liste yüklenemedi', e.mesaj, hata: true);
      }
    }
  }

  /* ═════════════ Görünüm ═════════════ */

  String _baslik(AdisyonOzet a) {
    final t = a.masaAdi ?? a.cariAdi ?? a.musteri ?? a.kanalEtiket;
    return a.bagliMasalar.isEmpty ? t : [t, ...a.bagliMasalar].join(' + ');
  }

  String _sure(String? iso) {
    if (iso == null) return '—';
    final dk = gecenDakika(iso, saatFarki: _o.saatFarki);
    return dk < 60 ? '$dk dk' : '${dk ~/ 60} sa ${dk % 60} dk';
  }

  _KartDurum _kartDurum(AdisyonOzet a) {
    if (a.odenen > 0 && a.kalan <= 0) return _KartDurum.odendi;
    if (a.odenen > 0) return _KartDurum.kismi;
    if (a.durum == 'bill_requested') return _KartDurum.hesap;
    return _KartDurum.acik;
  }

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final genis = g >= 1024;
    final tahsilat = _sekme == 'debts' ? _borclu != null : _secili != null;

    Widget govde;
    if (!tahsilat) {
      govde = _secimKipi(g);
    } else {
      final dokum = _borclu != null ? _borcDokumu() : _adisyonDokumu(genis);
      final odeme = _borclu != null ? _borcOdemeBolmesi(g) : _odemeBolmesi(g);
      if (genis) {
        final sag = g >= 1536 ? 440.0 : 380.0;
        govde = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: odeme),
          Container(width: 1, color: Renk.cizgi),
          SizedBox(width: sag, child: dokum),
        ]);
      } else {
        govde = Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(12), children: [
              _kart(dokum),
              const SizedBox(height: 12),
              _kart(odeme),
            ]),
          ),
          if (_borclu == null && _secili != null && _kalan > 0) _mobilOdemeCubugu(),
        ]);
      }
    }

    return Focus(
      focusNode: _odak,
      autofocus: true,
      onKeyEvent: _klavye,
      child: ColoredBox(color: Renk.yuzey, child: govde),
    );
  }

  Widget _kart(Widget c) => Container(
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: c,
      );

  /* ── §1.3 seçim kipi ── */

  Widget _secimKipi(double g) {
    final borcluListe = _gorunenBorclular;
    Widget sekme(String k, IconData ikon, String ad, {int? sayi, bool kilit = false}) => Expanded(
          child: InkWell(
            onTap: () {
              setState(() => _sekme = k);
              if (k == 'debts' && _borclular.isEmpty) _borclulariYukle();
            },
            child: Container(
              height: 48,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _sekme == k ? Renk.yazi : Renk.cizgi, width: _sekme == k ? 2 : 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ikon, size: 18, color: _sekme == k ? Renk.marka : Renk.ikinci),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(ad,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _sekme == k ? Renk.marka : Renk.yazi)),
                ),
                if (sayi != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
                    child: Text('$sayi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Renk.yazi)),
                  ),
                ],
                if (kilit) Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.lock_outline_rounded, size: 13, color: Renk.soluk)),
              ]),
            ),
          ),
        );

    final Widget icerik = switch (_sekme) {
      'debts' => _borclarSekmesi(g, borcluListe),
      'paid' => _odenenlerSekmesi(g),
      _ => _adisyonlarSekmesi(g),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        sekme('orders', Icons.content_paste_rounded, 'Adisyonlar', sayi: _adisyonlar.length),
        sekme('debts', Icons.inbox_outlined, 'Borçlar', sayi: _borclular.isEmpty ? null : borcluListe.length),
        sekme('paid', Icons.check_circle_outline_rounded, 'Bugün ödenenler', kilit: true),
      ]),
      Expanded(child: icerik),
    ]);
  }

  int _sutun(double g) => g >= 1536 ? 7 : (g >= 1280 ? 6 : (g >= 1024 ? 5 : (g >= 768 ? 4 : (g >= 640 ? 3 : 2))));

  Widget _izgara(double g, List<Widget> kartlar) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _sutun(g),
          mainAxisSpacing: g >= 640 ? 10 : 8,
          crossAxisSpacing: g >= 640 ? 10 : 8,
          mainAxisExtent: g >= 480 ? 200 : 270,
        ),
        itemCount: kartlar.length,
        itemBuilder: (_, i) => kartlar[i],
      );

  Widget _bos(IconData ikon, String baslik, String aciklama) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(ikon, size: 36, color: Renk.soluk),
            const SizedBox(height: 8),
            Text(baslik, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(aciklama, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
          ]),
        ),
      );

  Widget _adisyonlarSekmesi(double g) {
    if (_yukleniyor) return Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    if (_adisyonlar.isEmpty) return _bos(Icons.check_circle_outline_rounded, 'Bekleyen adisyon yok', 'Açık ve ödenmemiş adisyonlar burada listelenir.');
    final toplam = _adisyonlar.fold<int>(0, (t, a) => t + a.kalan);
    final kismi = _adisyonlar.where((a) => a.odenen > 0 && a.kalan > 0).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${_adisyonlar.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' adisyon · bekleyen '),
            TextSpan(text: para(toplam), style: TextStyle(fontWeight: FontWeight.w700, color: Renk.hata)),
            if (kismi > 0) TextSpan(text: ' · $kismi kısmi ödendi', style: TextStyle(color: Renk.uyari)),
          ]),
          style: TextStyle(fontSize: 13, color: Renk.ikinci),
        ),
      ),
      Expanded(child: _izgara(g, [for (final a in _adisyonlar) _adisyonKarti(a, g)])),
    ]);
  }

  Widget _adisyonKarti(AdisyonOzet a, double g) {
    final d = _kartDurum(a);
    final (govde, kenar, hap, vurgu, etiket) = switch (d) {
      _KartDurum.acik => (Renk.hataZemin, Renk.hataKenar, Renk.hata, Renk.hata, 'Açık adisyon'),
      _KartDurum.kismi => (Renk.uyariZemin, Renk.uyariKenar, Renk.uyari, Renk.uyari, 'Kısmi ödendi'),
      _KartDurum.odendi => (Renk.basariZemin, Renk.basari.withValues(alpha: .55), Renk.basari, Renk.basari, 'Ödendi'),
      _KartDurum.hesap => (Renk.markaAcik.carp(.4), Renk.marka.withValues(alpha: .55), Renk.marka, Renk.marka, 'Hesap istendi'),
    };
    final baslik = _baslik(a);
    final borc = a.ham['receivable_id'] != null ? tamSayi(a.ham['receivable_balance_minor']) : 0;
    final ciz = Container(height: 1, color: kenar.withValues(alpha: .6));
    final tutar = Column(children: [
      Text('Adisyon', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text.rich(TextSpan(children: [
          TextSpan(text: para(a.kalan, simge: false), style: TextStyle(fontSize: g >= 1280 ? 17 : 16, fontWeight: FontWeight.w800, color: vurgu)),
          TextSpan(text: ' ₺', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: vurgu)),
        ])),
      ),
    ]);
    final sure = Column(children: [
      Text('Süre', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      Text(_sure(a.ham['created_at']?.toString()), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
    ]);
    return Semantics(
      label: '$baslik — ${para(a.kalan, simge: false)} lira · $etiket',
      button: true,
      child: Material(
        color: govde,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: kenar)),
        elevation: 1,
        shadowColor: const Color(0x140F172A),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _sec(a),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              child: Column(children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: hap, shape: BoxShape.circle),
                  child: Icon(kasaSimge(a.ham['channel_icon']?.toString()), size: 16, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: g >= 640 ? 13 : 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(etiket.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: vurgu, letterSpacing: .3)),
              ]),
            ),
            ciz,
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (g >= 480)
                  Row(children: [Expanded(child: tutar), Expanded(child: sure)])
                else ...[
                  tutar,
                  const SizedBox(height: 4),
                  sure,
                ],
                if (borc > 0)
                  Tooltip(
                    message: '${a.cariAdi ?? 'Şahıs'} — defterdeki açık borcu',
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 11, color: Renk.uyari),
                        const SizedBox(width: 3),
                        Text('Borç ${para(borc)}', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.uyari)),
                      ]),
                    ),
                  ),
              ]),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: ciz),
            SizedBox(
              height: 30,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (a.kalemSayisi > 0) ...[
                  Icon(Icons.restaurant_rounded, size: 12, color: Renk.soluk),
                  const SizedBox(width: 3),
                  Text('${a.kalemSayisi}', style: TextStyle(fontSize: 11, color: Renk.ikinci)),
                ],
                if (d == _KartDurum.kismi) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.account_balance_wallet_outlined, size: 12, color: Renk.uyari),
                  const SizedBox(width: 3),
                  Text('${para(a.odenen)} alındı', style: TextStyle(fontSize: 11, color: Renk.uyari)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  List<Json> get _gorunenBorclular {
    final n = _borcArama.toLowerCase();
    return _borclular.where((d) {
      if (tamSayi(d['balance_minor']) <= 0) return false;
      if (n.isEmpty) return true;
      return '${d['name'] ?? ''} ${d['phone'] ?? ''}'.toLowerCase().contains(n);
    }).toList();
  }

  Widget _borclarSekmesi(double g, List<Json> liste) {
    final enYuksek = liste.fold<int>(0, (m, d) => tamSayi(d['balance_minor']) > m ? tamSayi(d['balance_minor']) : m);
    final toplam = liste.fold<int>(0, (t, d) => t + tamSayi(d['balance_minor']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: TextField(
          decoration: const InputDecoration(hintText: 'Şahıs adı veya telefon…', prefixIcon: Icon(Icons.search_rounded, size: 18)),
          onChanged: (v) => setState(() => _borcArama = v.trim()),
        ),
      ),
      if (liste.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(children: [
            Text('Toplam borç', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
            const Spacer(),
            Text(para(toplam), style: TextStyle(fontWeight: FontWeight.w700, color: Renk.hata)),
          ]),
        ),
      Expanded(
        child: _borcYukleniyor && _borclular.isEmpty
            ? Center(child: Text('Şahıslar yükleniyor…', style: TextStyle(color: Renk.ikinci)))
            : liste.isEmpty
                ? _bos(Icons.check_circle_outline_rounded, 'Borçlu şahıs yok', 'Adisyon borca taşındığında ya da elle şahıs eklendiğinde burada listelenir.')
                : _izgara(g, [for (final d in liste) _borcluKarti(d, enYuksek)]),
      ),
    ]);
  }

  Widget _borcluKarti(Json d, int enYuksek) {
    final bakiye = tamSayi(d['balance_minor']);
    final ad = '${d['name'] ?? ''}';
    final harf = ad.isEmpty ? '?' : ad.characters.first.replaceAll('i', 'İ').toUpperCase();
    final Widget? rozet = bakiye == enYuksek && bakiye > 0
        ? Tooltip(message: 'Listedeki en yüksek borç', child: Rozet('En yüksek borç', renk: Renk.hata, dolu: true, ikon: Icons.warning_amber_rounded))
        : bakiye >= 1000000
            ? Tooltip(message: 'Borcu 10.000,00 ₺ üzerinde', child: Rozet('Yüksek borç', renk: Renk.uyari, ikon: Icons.error_outline_rounded))
            : null;
    final son = d['last_payment_at']?.toString();
    return Material(
      color: Renk.markaAcik.carp(.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Renk.marka.withValues(alpha: .45))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _borcluSec(d),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Renk.marka, shape: BoxShape.circle),
                child: Text(harf, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text('BORÇLU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.marka)),
                ]),
              ),
            ]),
            if (rozet != null) Padding(padding: const EdgeInsets.only(top: 6), child: Align(alignment: Alignment.centerLeft, child: rozet)),
            const Spacer(),
            Wrap(spacing: 6, runSpacing: 4, children: [
              Rozet('Borç ${para(bakiye)}', renk: Renk.uyari),
              if (tamSayi(d['open_debt_orders_count']) > 0) Rozet('${d['open_debt_orders_count']} adisyon', ikon: Icons.receipt_outlined),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.schedule_rounded, size: 12, color: Renk.soluk),
              const SizedBox(width: 3),
              Expanded(
                child: Text(son == null ? 'ödeme yok' : '${_gunAy(son)} ${saatMetni(son)}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Renk.ikinci)),
              ),
              if (d['phone'] != null) ...[
                Icon(Icons.phone_outlined, size: 12, color: Renk.soluk),
                const SizedBox(width: 3),
                Text('${d['phone']}', style: TextStyle(fontSize: 11, color: Renk.ikinci)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  static const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

  String _gunAy(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : '${t.day} ${_aylar[t.month - 1]}';
  }

  String _tarihSaat(String? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return t == null ? '' : '${t.day} ${_aylar[t.month - 1]} ${t.year} · ${saatMetni(iso)}';
  }

  Widget _odenenlerSekmesi(double g) {
    // Web: yetkisiz ve terminal değilse kapalı; uygulama her zaman terminal
    // olduğundan PIN formu gösterilir (yetkiyi PIN sahibinde sunucu denetler).
    final o = _odenenler;
    if (_kilit == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: Renk.uyariZemin, shape: BoxShape.circle),
                child: Icon(Icons.lock_outline_rounded, color: Renk.uyari, size: 26),
              ),
              const SizedBox(height: 10),
              const Text('Bugün ödenenler', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text("Kasa yönetimi yetkisi olan personelin PIN'i gerekir.", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.ikinci)),
              if (_kilitHata != null) ...[
                const SizedBox(height: 8),
                Text(_kilitHata!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Renk.hata)),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: _kilidiAc, icon: const Icon(Icons.lock_open_rounded, size: 16), label: const Text('PIN ile aç')),
            ]),
          ),
        ),
      );
    }
    if (o == null) return Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    final satirlar = (o['rows'] as List? ?? const []).whereType<Map>().toList();
    final yontemler = (o['yontemler'] as List? ?? const []).whereType<Map>().toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 0),
        child: Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${o['adisyon_adet'] ?? satirlar.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const TextSpan(text: ' adisyon · '),
                TextSpan(text: para(tamSayi(o['toplam_minor'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              ])),
              for (final y in yontemler) Rozet('${y['label']} ${para(tamSayi(y['amount_minor']))}'),
            ]),
          ),
          TextButton.icon(onPressed: () => setState(_kilitle), icon: const Icon(Icons.lock_outline_rounded, size: 15), label: const Text('Kilitle')),
        ]),
      ),
      Expanded(
        child: satirlar.isEmpty
            ? _bos(Icons.account_balance_wallet_outlined, 'Bugün ödeme alınmış adisyon yok', 'Gün sonu alınmamış açık gündeki ödemeler burada listelenir.')
            : _izgara(g, [
                for (final r in satirlar)
                  _odenenKarti(r.cast<String, dynamic>()),
              ]),
      ),
    ]);
  }

  Widget _odenenKarti(Json r) {
    final o = r['order'] is Map ? (r['order'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final a = AdisyonOzet(o);
    final y = (r['yontemler'] as List? ?? const []).whereType<Map>().toList();
    return Material(
      color: Renk.basariZemin,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Renk.basari.withValues(alpha: .55))),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() => _sekme = 'orders');
          _sec(a);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a.masaAdi ?? a.cariAdi ?? 'Adisyon #${a.id}'} #${a.id}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(para(tamSayi(r['odenen_minor'])), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Renk.basari)),
            const Spacer(),
            Text(saatMetni(r['son_odeme_at']?.toString()), style: TextStyle(fontSize: 11, color: Renk.ikinci)),
            Wrap(spacing: 4, runSpacing: 2, children: [
              for (final m in y)
                Text('${m['label']} ${para(tamSayi(m['amount_minor']))}${tamSayi(m['count']) > 1 ? ' (${m['count']})' : ''}',
                    style: TextStyle(fontSize: 11, color: Renk.ikinci)),
            ]),
            if (tamSayi(r['iptal_adet']) > 0) Text('${r['iptal_adet']} ödeme kaldırıldı', style: TextStyle(fontSize: 11, color: Renk.hata)),
            if (a.kalan > 0) Text('kalan ${para(a.kalan)}', style: TextStyle(fontSize: 11, color: Renk.uyari)),
          ]),
        ),
      ),
    );
  }

  /* ── §1.4 adisyon dökümü (sağ panel) ── */

  Widget _adisyonDokumu(bool genis) {
    final s = _secili!;
    final d = _detay;
    final h = d?.ham ?? s.ham;
    final bagli = s.bagliMasalar.length;
    final indirimVar = tamSayi(h['discount_minor']) > 0;
    final servisVar = tamSayi(h['service_charge_minor']) > 0;

    Widget kucuk(String ad, IconData ikon, VoidCallback? bas, {Color? renk, bool vurgu = false}) => Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: vurgu ? Colors.white : (renk ?? Renk.yazi),
              backgroundColor: vurgu ? Renk.marka : null,
              side: BorderSide(color: vurgu ? Renk.marka : Renk.cizgi),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            onPressed: bas,
            icon: Icon(ikon, size: 15),
            label: Text(ad),
          ),
        );

    final ust = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: _baslik(s), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                TextSpan(text: '  #${s.id}', style: TextStyle(fontSize: 13, color: Renk.soluk, fontWeight: FontWeight.w600)),
              ])),
              if (bagli > 0) Rozet('${bagli + 1} masa birleşik', renk: Renk.marka, ikon: Icons.merge_rounded),
              if (s.odenen > 0 && s.kalan > 0) Rozet('Kısmi ödendi', renk: Renk.uyari),
            ]),
          ),
          Rozet(_sure(s.ham['created_at']?.toString()), ikon: Icons.schedule_rounded),
        ]),
        const SizedBox(height: 2),
        Wrap(spacing: 10, children: [
          if ((d?.kisi ?? s.kisi) != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline_rounded, size: 13, color: Renk.ikinci),
              const SizedBox(width: 3),
              Text('${d?.kisi ?? s.kisi} kişi', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            ]),
          Text('${s.kalemSayisi} kalem', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          if (s.odenen > 0) Text('${para(s.odenen)} ödendi', style: TextStyle(fontSize: 12, color: Renk.basari)),
        ]),
        const SizedBox(height: 8),
        Wrap(children: [
          if (d != null && (_kalemDuzenler || _ikramEder) && _duzenlenebilir)
            kucuk(_duzelt ? 'Düzenlemeyi bitir' : 'Düzelt', Icons.edit_outlined, () => setState(() {
                  _duzelt = !_duzelt;
                  _kalemSecim.clear();
                }), vurgu: _duzelt),
          kucuk('Hesap yazdır', Icons.print_outlined, () => _fisYazdir('bill')),
          if (s.odenen > 0) kucuk('Fiş', Icons.receipt_outlined, () => _fisYazdir('payment'), renk: Renk.basari),
          Builder(
            builder: (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: IconButton(
                tooltip: 'Diğer işlemler',
                onPressed: () => _digerMenu(c, indirimVar: indirimVar, servisVar: servisVar),
                icon: const Icon(Icons.more_vert_rounded, size: 20),
              ),
            ),
          ),
        ]),
      ]),
    );

    Widget sekme(String k, IconData ikon, String ad, int sayi) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _sagSekme = k),
            child: Container(
              height: 44,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _sagSekme == k ? Renk.marka : Renk.cizgi, width: _sagSekme == k ? 2 : 1))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ikon, size: 17, color: _sagSekme == k ? Renk.marka : Renk.ikinci),
                const SizedBox(width: 6),
                Text(ad, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _sagSekme == k ? Renk.marka : Renk.yazi)),
                const SizedBox(width: 6),
                Rozet('$sayi'),
              ]),
            ),
          ),
        );

    final icerik = _sagSekme == 'payments' ? _odemelerListesi() : _kalemlerSekmesi();

    final alt = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.kalan == 0)
        Container(
          color: Renk.basariZemin,
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            Icon(Icons.check_circle_outline_rounded, color: Renk.basari, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Adisyon tamamen ödendi — fiş verip kapatabilirsiniz.', style: TextStyle(color: Renk.basari, fontWeight: FontWeight.w600, fontSize: 13))),
          ]),
        ),
      Container(
        color: Renk.ic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          _toplamHucre('Seçilen', para(_kalemSecim.isNotEmpty ? _seciliToplam : _tutarMinor), Renk.marka),
          _toplamHucre('Ödenen', para(s.odenen), Renk.basari),
          _toplamHucre('Kalan', para(s.kalan), s.kalan > 0 ? Renk.yazi : Renk.basari),
          _toplamHucre('Toplam', para(s.toplam), Renk.yazi),
        ]),
      ),
    ]);

    final govde = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: genis ? MainAxisSize.max : MainAxisSize.min, children: [
      ust,
      Row(children: [
        sekme('items', Icons.shopping_cart_outlined, 'Kalemler', _gorunenKalemler.length),
        sekme('payments', Icons.account_balance_wallet_outlined, 'Ödemeler', _odemeler.length),
      ]),
      if (genis) Expanded(child: icerik) else ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .45), child: icerik),
      alt,
    ]);
    return govde;
  }

  Widget _toplamHucre(String e, String d, Color renk) => Expanded(
        child: Column(children: [
          Text(e.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, child: Text(d, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: renk))),
        ]),
      );

  Future<void> _digerMenu(BuildContext c, {required bool indirimVar, required bool servisVar}) async {
    final s = _secili!;
    final kutu = c.findRenderObject() as RenderBox;
    final p = kutu.localToGlobal(Offset.zero);
    PopupMenuItem<String> oge(String d, IconData i, String ad, {bool etkin = true}) => PopupMenuItem<String>(
          value: d,
          enabled: etkin,
          height: 40,
          child: Row(children: [Icon(i, size: 17, color: etkin ? Renk.yazi : Renk.soluk), const SizedBox(width: 10), Text(ad, style: const TextStyle(fontSize: 13.5))]),
        );
    final secim = await _penceredeyken(() => showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(p.dx - 240, p.dy + kutu.size.height, 16, 0),
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Renk.cizgi)),
          items: [
            oge('yazici', Icons.print_outlined, 'Fiş yazıcısı · ${_yaziciAdi ?? 'seçilmedi'}'),
            oge('onBill', Icons.receipt_outlined, 'Hesap fişini önizle'),
            if (s.odenen > 0) oge('onPay', Icons.receipt_outlined, 'Ödeme fişini önizle'),
            if (_indirimYetkisi) oge('indirim', Icons.sell_outlined, indirimVar ? 'İndirimi kaldır' : 'İndirim uygula', etkin: _detay != null),
            if (_kalemDuzenler) oge('servis', Icons.add_rounded, servisVar ? 'Servis bedeli kaldır' : 'Servis bedeli ekle'),
            if (s.kalan > 0 && s.durum == 'bill_requested' && _odemeYetkisi) oge('geri', Icons.arrow_back_rounded, 'Tekrar siparişe gönder', etkin: !_mesgul),
            if (s.kalan > 0) oge('borc', Icons.inbox_outlined, 'Borca yaz (şahıs)'),
          ],
        ));
    switch (secim) {
      case 'yazici':
        _yaziciSec();
      case 'onBill':
        _fisOnizle('bill');
      case 'onPay':
        _fisOnizle('payment');
      case 'indirim':
        _indirimDiyalogu();
      case 'servis':
        _servisBedeli();
      case 'geri':
        _sipariseGeriGonder();
      case 'borc':
        _borcaYaz();
    }
  }

  Widget _kalemlerSekmesi() {
    final s = _secili!;
    final d = _detay;
    if (_detayYasak) {
      return Padding(
        padding: EdgeInsets.all(16),
        child: Text('Kalem dökümünü görme yetkiniz yok; alttaki tutar özeti üzerinden tahsilat yapabilirsiniz.', style: TextStyle(color: Renk.ikinci)),
      );
    }
    if (d == null) return Center(child: Text('Kalemler yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    final kalemler = _gorunenKalemler;
    final h = d.ham;
    final cocuklar = <Widget>[];

    if (!_duzelt && kalemler.isNotEmpty && s.kalan > 0) {
      cocuklar.add(_kalemSecim.isNotEmpty
          ? Container(
              color: Renk.markaAcik,
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              child: Row(children: [
                Expanded(
                  child: Text('${_kalemSecim.length} kalem seçili · ${para(_seciliToplam)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: Renk.marka, fontSize: 13)),
                ),
                TextButton(onPressed: () => setState(_kalemSecim.clear), child: const Text('Temizle')),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: _seciminiYaz,
                  child: const Text('Tutara yaz'),
                ),
              ]),
            )
          : Container(
              color: Renk.ic,
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 15, color: Renk.ikinci),
                SizedBox(width: 6),
                Expanded(child: Text('Kişi kendi kalemlerini ödeyecekse kalemlere dokunup seçin.', style: TextStyle(fontSize: 12.5, color: Renk.ikinci))),
              ]),
            ));
    }

    if (kalemler.isEmpty) {
      cocuklar.add(_bos(Icons.shopping_cart_outlined, 'Kalem yok', ''));
    } else if (h['aktif_parti'] != null) {
      final aktif = tamSayi(h['aktif_parti'], 1);
      final adlar = h['parti_adlari'] is Map ? h['parti_adlari'] as Map : const {};
      final gruplar = <int, List<Kalem>>{};
      for (final k in kalemler) {
        (gruplar[k.ham['parti_no'] == null ? aktif : tamSayi(k.ham['parti_no'])] ??= []).add(k);
      }
      for (final no in gruplar.keys.toList()..sort()) {
        cocuklar.add(_partiBasligi(no, gruplar[no]!, no == aktif, adlar['$no']?.toString()));
        cocuklar.addAll(gruplar[no]!.map(_kalemSatiri));
      }
    } else {
      cocuklar.addAll(kalemler.map(_kalemSatiri));
    }

    final iskonto = tamSayi(h['iskonto_minor']);
    if (iskonto > 0) {
      cocuklar.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
        child: Row(children: [
          Icon(Icons.sell_outlined, size: 16, color: Renk.uyari),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('İskonto', style: TextStyle(fontWeight: FontWeight.w700)),
              Text(h['iskonto_reason']?.toString() ?? 'Kasada tutar düşümü', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            ]),
          ),
          Text('−${para(iskonto)}', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.uyari)),
          if (_indirimYetkisi && _duzenlenebilir)
            IconButton(tooltip: 'İskontoyu kaldır', onPressed: _mesgul ? null : _iskontoKaldir, icon: const Icon(Icons.close_rounded, size: 16)),
        ]),
      ));
    }

    if (_duzelt) {
      cocuklar.add(Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Text('Değişiklikler anında adisyona ve kalan tutara işler. Bittiğinde “Düzenlemeyi bitir”e basın.', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
      ));
    }
    if (_kalemDuzenler && _duzenlenebilir) {
      cocuklar.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(onPressed: _mesgul ? null : _urunEkle, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Adisyona ürün ekle')),
          const SizedBox(height: 4),
          Text('Adisyonda eksik/unutulmuş ürün varsa buradan ekleyin; tutar anında güncellenir.', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        ]),
      ));
    }
    if (_duzenlenebilir) {
      cocuklar.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(
            onPressed: _indirimYetkisi ? _indirimPaneliAc : null,
            icon: const Icon(Icons.sell_outlined, size: 16),
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              const Text('İndirim / İskonto uygula'),
              Icon(_indirimPaneli ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
            ]),
          ),
          if (!_indirimYetkisi)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Bu işlem için yetkiniz yok. Kasaya ya da yöneticiye bildirerek işlemi yaptırabilirsiniz.', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
            ),
          if (_indirimPaneli && _indirimYetkisi) _indirimPaneliGovde(h),
        ]),
      ));
    }
    cocuklar.add(_tutarDokumu(h, kalemler));
    return ListView(padding: EdgeInsets.zero, children: cocuklar);
  }

  Widget _indirimPaneliGovde(Json h) {
    final indirim = tamSayi(h['discount_minor']);
    final iskonto = tamSayi(h['iskonto_minor']);
    final hazir = _hazirIndirimler;
    Widget kutu(String metin, VoidCallback kaldir) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.uyariKenar)),
          child: Row(children: [
            Expanded(child: Text(metin, style: TextStyle(color: Renk.uyari, fontWeight: FontWeight.w600, fontSize: 13))),
            TextButton(onPressed: _mesgul ? null : kaldir, child: const Text('Kaldır')),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('İndirim (hazır tanım)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        if (indirim > 0)
          kutu('${h['discount_reason'] ?? 'İndirim'}${h['discount_percent'] != null ? ' (%${h['discount_percent']})' : ''} −${para(indirim)}', _indirimKaldir)
        else if (hazir == null)
          Text('Tanımlar yükleniyor…', style: TextStyle(fontSize: 12, color: Renk.ikinci))
        else if (hazir.isEmpty)
          Text('Tanımlı hazır indirim yok. İndirim Tanımları ekranından ekleyin.', style: TextStyle(fontSize: 12, color: Renk.ikinci))
        else
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width >= 640 ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 2.4,
            children: [
              for (final p in hazir)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(6)),
                  onPressed: _mesgul ? null : () => _hazirIndirim(p),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.yazi)),
                    Text('${p['value_label']}', style: TextStyle(fontWeight: FontWeight.w800, color: Renk.marka)),
                  ]),
                ),
            ],
          ),
        const SizedBox(height: 12),
        const Text('İskonto (tutar yaz)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 6),
        if (iskonto > 0)
          kutu('−${para(iskonto)} iskonto uygulandı', _iskontoKaldir)
        else ...[
          TextField(
            controller: _iskontoMetin,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Tutar (₺)', hintText: 'ör. 45,00'),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _mesgul ? null : () => _iskontoUygula(hedefKip: false), child: const Text('İndir'))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton(onPressed: _mesgul ? null : () => _iskontoUygula(hedefKip: true), child: const Text('Hesabı buna indir'))),
          ]),
        ],
      ]),
    );
  }

  Widget _partiBasligi(int no, List<Kalem> ks, bool acik, String? ad) {
    final odenmemis = ks.where((k) => !k.odendi && !k.ikram).toList();
    final tamOdendi = odenmemis.isEmpty;
    final kalan = odenmemis.fold<int>(0, (t, k) => t + k.tutar);
    return Tooltip(
      message: tamOdendi ? 'Bu parti ödendi' : '$no. parti${ad != null ? ' · $ad' : ''} — tahsil için seç',
      child: InkWell(
        onTap: tamOdendi || _duzelt
            ? null
            : () {
                setState(() {
                  _kalemSecim
                    ..clear()
                    ..addAll(odenmemis.map((k) => k.id));
                });
                _seciminiYaz();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: tamOdendi ? Renk.basariZemin.carp(.4) : (acik ? Renk.markaAcik.carp(.6) : Renk.ic),
          child: Row(children: [
            Text('$no. parti', style: TextStyle(fontWeight: FontWeight.w700, color: acik ? Renk.marka : Renk.yazi)),
            if (ad != null) ...[
              const SizedBox(width: 6),
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Rozet(ad, renk: Renk.marka)),
            ],
            const SizedBox(width: 6),
            if (acik)
              Rozet('SÜRÜYOR', renk: Renk.marka, dolu: true)
            else if (tamOdendi)
              Rozet('ÖDENDİ', renk: Renk.basari, dolu: true),
            const Spacer(),
            if (!tamOdendi && !_duzelt) Padding(padding: EdgeInsets.only(right: 6), child: Text('tahsil et', style: TextStyle(fontSize: 11, color: Renk.ikinci))),
            Text(para(kalan), style: TextStyle(fontWeight: FontWeight.w700, color: tamOdendi ? Renk.basari : null)),
          ]),
        ),
      ),
    );
  }

  Widget _kalemSatiri(Kalem k) {
    final secili = _kalemSecim.contains(k.id);
    final soluk = k.odendi;
    final meta = [
      if (k.varyant != null) k.varyant!,
      ...k.secenekler,
      if (k.not != null && k.not!.isNotEmpty) '“${k.not}”',
    ];
    final oran = (k.ham['tax_rate'] is num) ? (k.ham['tax_rate'] as num).toDouble() : double.tryParse('${k.ham['tax_rate']}') ?? 0;
    final duzenle = _duzelt && _duzenlenebilir;
    return Material(
      color: secili ? Renk.markaAcik : Renk.ic,
      child: InkWell(
        onTap: !_duzelt && !k.ikram && !k.odendi ? () => _kalemDokun(k) : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${k.adet}×', style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: ' ${k.ad}'),
                      ]),
                      style: TextStyle(fontSize: 15, decoration: soluk ? TextDecoration.lineThrough : null, color: soluk ? Renk.soluk : Renk.yazi),
                    ),
                    if (k.odendi) Rozet('Ödendi', renk: Renk.basari),
                    if (k.ikram) Rozet('İkram', renk: Renk.bilgi),
                  ]),
                  if (meta.isNotEmpty) Text(meta.join(' · '), style: TextStyle(fontSize: 12, color: Renk.soluk)),
                  if (!k.ikram && oran > 0)
                    Text('KDV ${_oran(oran)} dahil', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(para(k.tutar),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: k.ikram || soluk ? TextDecoration.lineThrough : null,
                      color: k.ikram || soluk ? Renk.soluk : Renk.yazi,
                    )),
                Text('${para(k.birimFiyat)} / adet', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
              ]),
            ]),
            if (duzenle)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
                child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (_kalemDuzenler && !k.ikram) ...[
                    Container(
                      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: k.adet <= 1 || _mesgul ? null : () => _adet(k, k.adet - 1),
                          icon: const Icon(Icons.remove_rounded, size: 16),
                        ),
                        Text('${k.adet}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: k.adet >= 100 || _mesgul ? null : () => _adet(k, k.adet + 1),
                          icon: const Icon(Icons.add_rounded, size: 16),
                        ),
                      ]),
                    ),
                    TextButton.icon(onPressed: _mesgul ? null : () => _kalemDegistir(k), icon: const Icon(Icons.edit_outlined, size: 15), label: const Text('Değiştir')),
                  ],
                  if (_ikramEder && !k.ikram)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Renk.bilgi),
                      onPressed: _mesgul ? null : () => _ikram(k),
                      icon: const Icon(Icons.sell_outlined, size: 15),
                      label: const Text('İkram yap'),
                    ),
                  if (_kalemDuzenler && !k.ikram)
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Renk.hata),
                      onPressed: _mesgul ? null : () => _cikar(k),
                      icon: const Icon(Icons.delete_outline_rounded, size: 15),
                      label: const Text('Çıkar'),
                    ),
                  if (k.ikram) ...[
                    Text('İkram · ${k.ikramNedeni ?? ''}', style: TextStyle(fontSize: 12, color: Renk.bilgi)),
                    if (_ikramEder)
                      TextButton.icon(onPressed: _mesgul ? null : () => _ikramKaldir(k), icon: const Icon(Icons.undo_rounded, size: 15), label: const Text('İkramı kaldır')),
                  ],
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _tutarDokumu(Json h, List<Kalem> kalemler) {
    Widget satir(String e, String t, {Color? renk, double boy = 13.5}) => Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Text(e, style: TextStyle(fontSize: boy, color: (renk ?? Renk.yazi) == Renk.yazi ? Renk.ikinci : (renk ?? Renk.yazi))),
            const Spacer(),
            Text(t, style: TextStyle(fontSize: boy, color: (renk ?? Renk.yazi), fontWeight: FontWeight.w500)),
          ]),
        );
    final ikram = tamSayi(h['comp_total_minor']);
    final indirim = tamSayi(h['discount_minor']);
    final iskonto = tamSayi(h['iskonto_minor']);
    final servis = tamSayi(h['service_charge_minor']);
    final yuvarlama = tamSayi(h['rounding_minor']);
    final kdv = tamSayi(h['vat_total_minor']);
    final iade = tamSayi(h['refunded_minor']);

    // Kırılım: aktif + ikramsız + oranı olan kalemler; ±2 kuruş güvenilirlik.
    final kirilim = <double, ({int net, int kdv})>{};
    for (final k in kalemler.where((k) => !k.ikram)) {
      final o = (k.ham['tax_rate'] is num) ? (k.ham['tax_rate'] as num).toDouble() : double.tryParse('${k.ham['tax_rate']}') ?? 0;
      if (o <= 0) continue;
      final net = (k.tutar / (1 + o / 100)).round();
      final e = kirilim[o];
      kirilim[o] = (net: (e?.net ?? 0) + net, kdv: (e?.kdv ?? 0) + k.tutar - net);
    }
    final kirilimToplam = kirilim.values.fold<int>(0, (t, x) => t + x.kdv);
    final guvenilir = kirilim.isNotEmpty && (kirilimToplam - kdv).abs() <= 2;
    final oranlar = kirilim.keys.toList()..sort((a, b) => b.compareTo(a));

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        satir('Kalem toplamı', para(tamSayi(h['items_total_minor']))),
        if (ikram > 0) satir('İkram', '−${para(ikram)}', renk: Renk.bilgi),
        if (indirim > 0) satir('İndirim', '−${para(indirim)}', renk: Renk.hata),
        if (iskonto > 0) satir('İskonto', '−${para(iskonto)}', renk: Renk.uyari),
        if (servis > 0) satir('Servis bedeli', para(servis)),
        if (yuvarlama != 0) satir('Yuvarlama', '${yuvarlama > 0 ? '+' : '−'}${para(yuvarlama.abs())}'),
        if (kdv > 0) satir('KDV (dahil)', para(kdv), renk: Renk.ikinci, boy: 12),
        if (guvenilir)
          for (final o in oranlar) satir('KDV ${_oran(o)} (matrah ${para(kirilim[o]!.net)})', para(kirilim[o]!.kdv), renk: Renk.soluk, boy: 11.5),
        if (iade > 0) satir('İade edilen', para(iade), renk: Renk.hata),
      ]),
    );
  }

  Widget _odemelerListesi() {
    if (_odemeler.isEmpty) return _bos(Icons.account_balance_wallet_outlined, 'Henüz ödeme yok', '');
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _odemeler.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _odemeler[i];
        final iadeMi = p['kind'] == 'refund';
        final durum = '${p['status'] ?? ''}';
        final tutar = tamSayi(p['amount_minor']);
        final iadeToplam = tamSayi(p['refunded_total_minor']);
        final bahsis = tamSayi(p['tip_minor']);
        final renk = switch ('${p['status_variant']}') {
          'success' => Renk.basari,
          'warning' => Renk.uyari,
          'danger' => Renk.hata,
          'info' => Renk.bilgi,
          _ => Renk.ikinci,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(kasaSimge(p['method_icon']?.toString()), size: 18, color: Renk.ikinci),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${iadeMi ? 'İade — ' : ''}${p['method_label'] ?? ''}  '),
                  TextSpan(text: '${iadeMi ? '−' : ''}${para(tutar)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (bahsis > 0) TextSpan(text: ' (+${para(bahsis)} bahşiş)', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                ])),
                Text('${p['cashier'] ?? '—'} · ${saatMetni(p['created_at']?.toString())}${p['reason'] != null ? ' · ${p['reason']}' : ''}',
                    style: TextStyle(fontSize: 12, color: Renk.soluk)),
                if (p['suspect'] == true)
                  Row(children: [
                    Icon(Icons.warning_amber_rounded, size: 13, color: Renk.hata),
                    const SizedBox(width: 3),
                    Flexible(child: Text('${p['suspect_reason'] ?? ''}', style: TextStyle(fontSize: 12, color: Renk.hata))),
                  ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Rozet('${p['status_label'] ?? durum}', renk: renk, ikon: kasaSimge(p['status_icon']?.toString())),
              Wrap(spacing: 2, children: [
                if (durum == 'pending' && _odemeYetkisi) TextButton(onPressed: () => _sorgula(p), child: const Text('Sorgula')),
                if (_iadeYetkisi && p['kind'] == 'payment' && durum == 'succeeded' && iadeToplam == 0)
                  TextButton(onPressed: _mesgul ? null : () => _void(p), child: const Text('İptal (void)')),
                if (_iadeYetkisi && p['kind'] == 'payment' && (durum == 'succeeded' || durum == 'partially_refunded') && iadeToplam < tutar)
                  TextButton(onPressed: _mesgul ? null : () => _iade(p), child: const Text('İade')),
              ]),
            ]),
          ]),
        );
      },
    );
  }

  /* ── §1.5 ödeme bölmesi (adisyon) ── */

  Widget _odemeBolmesi(double g) {
    final s = _secili!;
    final genis = g >= 1024;
    if (s.kalan == 0) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 24),
          Icon(Icons.check_circle_outline_rounded, size: 56, color: Renk.basari),
          const SizedBox(height: 10),
          const Text('Adisyon tamamen ödendi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Toplam ${para(s.toplam)} tahsil edildi.', style: TextStyle(color: Renk.ikinci)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => _fisYazdir('payment'),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Ödeme fişi yazdır'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _secimeDon,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Masalara dön'),
            ),
          ]),
          const SizedBox(height: 20),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 512), child: _yapilanOdemeler()),
        ]),
      );
    }

    final nakit = _yontem == 'cash';
    final ust = _paraUstu;
    final kismi = _tutarMinor > 0 && _tutarMinor < s.kalan;

    final baslik = Row(children: [
      TextButton.icon(
        onPressed: _secimeDon,
        icon: const Icon(Icons.arrow_back_rounded, size: 18),
        label: Text(g >= 640 ? 'Masalar' : ''),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ödeme İşlemleri', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          Text('${_baslik(s)} · #${s.id}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (kismi)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline_rounded, size: 13, color: Renk.uyari),
            const SizedBox(width: 3),
            Text('Sonrası kalan ${para(s.kalan - _tutarMinor)}', style: TextStyle(fontSize: 12, color: Renk.uyari)),
          ]),
        Text('KALAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
        Text(para(s.kalan), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
    ]);

    final tutarKutusu = _girdiKutusu(
      etiket: 'Tahsil edilecek (₺)',
      hedef: 'amount',
      metin: _tutar,
      buyuk: true,
    );
    final verilenKutusu = _girdiKutusu(
      etiket: 'Verilen para (₺)',
      hedef: 'tendered',
      metin: _verilen,
      sag: Text('Para üstü: ${ust == null ? '—' : para(ust, simge: false)} ₺',
          style: TextStyle(fontSize: 12, color: (ust ?? 0) > 0 ? Renk.basari : Renk.ikinci, fontWeight: (ust ?? 0) > 0 ? FontWeight.w700 : null)),
    );

    final presetler = _nakitPresetleri(s.kalan);

    final ogeler = <Widget>[
      baslik,
      const SizedBox(height: 10),
      if (nakit && g >= 640)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: tutarKutusu), const SizedBox(width: 10), Expanded(child: verilenKutusu)])
      else ...[
        tutarKutusu,
        if (nakit) ...[const SizedBox(height: 8), verilenKutusu],
      ],
      if (nakit) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final p in presetler)
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
              onPressed: () => setState(() {
                _verilen = paraGirdisi(p);
                _hedef = 'tendered';
              }),
              child: Text(para(p)),
            ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(value: _yuvarla, onChanged: (v) => setState(() => _yuvarla = v ?? false)),
            Text('Kalanı ${tamSayi(25)} kuruşa yuvarla', style: const TextStyle(fontSize: 12.5)),
          ]),
        ]),
      ],
      const SizedBox(height: 10),
      if (g >= 768) ...[
        _numpad(borc: false),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Klavye de çalışır: rakamlar '),
            TextSpan(text: _hedef == 'tendered' ? 'verilen paraya' : 'tahsil tutarına', style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' yazar · Backspace siler · Enter tahsil eder.'),
          ]),
          style: TextStyle(fontSize: 12, color: Renk.ikinci),
        ),
      ] else
        Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton(onPressed: () => _hizliTutar(1), child: const Text('Tamamı')),
          OutlinedButton(onPressed: () => _hizliTutar(1 / 2), child: const Text('½')),
          OutlinedButton(onPressed: () => _hizliTutar(1 / 3), child: const Text('⅓')),
          if ((_detay?.kisi ?? s.kisi ?? 0) > 1)
            OutlinedButton(
              onPressed: () => _tutarYaz((s.kalan / (_detay?.kisi ?? s.kisi)!).ceil()),
              child: Text('Kişi başı (${_detay?.kisi ?? s.kisi})'),
            ),
        ]),
      if (_bahsisAcik) ...[
        const SizedBox(height: 10),
        FormAlani(
          etiket: 'Bahşiş (₺)',
          ipucu: 'Adisyona işlemez; Z raporunda ayrı izlenir',
          child: TextField(
            controller: _bahsis,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '0,00'),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
      const SizedBox(height: 10),
      _yapilanOdemeler(),
      const SizedBox(height: 10),
      const Divider(height: 1),
      const SizedBox(height: 10),
      _yontemIzgarasi(),
      if (_terminalYontemi) ...[const SizedBox(height: 8), _posKutusu()],
      if (genis) ...[const SizedBox(height: 10), _odemeDugmesi(yukseklik: 56, buyuk: true)],
    ];

    final icerik = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: ogeler);
    return genis ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: icerik) : Padding(padding: const EdgeInsets.all(12), child: icerik);
  }

  List<int> _nakitPresetleri(int taban) {
    final l = <int>[taban];
    for (final adim in const [5000, 10000, 20000, 50000]) {
      final y = (taban / adim).ceil() * adim;
      if (y > taban && !l.contains(y)) l.add(y);
    }
    return l.take(4).toList();
  }

  Widget _girdiKutusu({required String etiket, required String hedef, required String metin, bool buyuk = false, Widget? sag, Color? vurgu}) {
    final aktif = _hedef == hedef;
    final renk = vurgu ?? Renk.marka;
    return InkWell(
      borderRadius: koseYuvarlak,
      onTap: () => setState(() {
        _hedef = hedef;
      }),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: aktif ? (vurgu == null ? Renk.markaAcik : Renk.uyariZemin) : Renk.yuzey,
          borderRadius: koseYuvarlak,
          border: Border.all(color: aktif ? renk : Renk.cizgiKoyu, width: aktif ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(etiket, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Renk.ikinci))),
            ?sag,
          ]),
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(metin.isEmpty ? '0,00' : metin,
                  style: TextStyle(fontSize: buyuk ? 24 : 20, fontWeight: FontWeight.w800, color: metin.isEmpty ? Renk.soluk : Renk.yazi)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _numpad({required bool borc}) {
    Widget tus(String etiket, VoidCallback bas, {bool hizli = false, bool sil = false, String? ipucu}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Tooltip(
              message: ipucu ?? '',
              child: Material(
                color: hizli ? Renk.markaAcik : Renk.ic,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: hizli ? Renk.markaKenar : Renk.cizgi)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: bas,
                  child: SizedBox(
                    height: 54,
                    child: Center(
                      child: Text(etiket,
                          style: TextStyle(
                            fontSize: hizli ? 17 : (sil ? 18 : 24),
                            fontWeight: FontWeight.w600,
                            color: sil ? Renk.hata : (hizli ? Renk.marka : Renk.yazi),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    void rakam(String k) => borc ? _borcTus(k) : _tus(k);
    final hizli1 = borc ? () => _borcHizli(1) : () => _hizliTutar(1);
    final hizli2 = borc ? () => _borcHizli(1 / 2) : () => _hizliTutar(1 / 2);
    final hizli3 = borc ? () => _borcHizli(1 / 3) : () => _hizliTutar(1 / 3);
    return Column(children: [
      Row(children: [tus('1', () => rakam('1')), tus('2', () => rakam('2')), tus('3', () => rakam('3')), tus('Tamamı', hizli1, hizli: true)]),
      Row(children: [tus('4', () => rakam('4')), tus('5', () => rakam('5')), tus('6', () => rakam('6')), tus('1/2', hizli2, hizli: true)]),
      Row(children: [tus('7', () => rakam('7')), tus('8', () => rakam('8')), tus('9', () => rakam('9')), tus('1/3', hizli3, hizli: true)]),
      Row(children: [
        tus('Sil', () => rakam('del'), sil: true),
        tus('0', () => rakam('0')),
        tus(',', () => rakam(',')),
        borc ? tus('Temizle', _borcTemizle, hizli: true, ipucu: 'Seçili kutuyu temizle') : tus('1/n', _bolPenceresi, hizli: true, ipucu: 'Kalanı n kişiye böl'),
      ]),
    ]);
  }

  Widget _yontemIzgarasi() {
    final g = MediaQuery.sizeOf(context).width;
    final sutun = g >= 768 ? 4 : 2;
    return GridView.count(
      crossAxisCount: sutun,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: g >= 1024 ? 2.2 : 2.6,
      children: [
        for (final y in kasaYontemleri) _yontemKutusu(y.$1, y.$2, kasaSimge(y.$3), _yontem == y.$1, () => setState(() => _yontem = y.$1)),
      ],
    );
  }

  Widget _yontemKutusu(String kod, String ad, IconData ikon, bool secili, VoidCallback bas, {String? ton}) {
    final t = yontemTonu(ton ?? kod);
    return Material(
      color: secili ? t.zemin : Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: secili ? t.kenar : Renk.cizgi, width: 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: bas,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(ikon, size: 26, color: secili ? t.yazi : t.ikon),
          const SizedBox(height: 4),
          Text(ad, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: secili ? t.yazi : Renk.yazi)),
        ]),
      ),
    );
  }

  Widget _posKutusu() {
    final manuel = _posManuel;
    final p = _pos;
    final String metin;
    if ((p?['simulated'] ?? true) == true) {
      metin = 'Fiziksel kart okuyucu bağlı değil — bu sağlayıcı test/simülasyon amaçlıdır, GERÇEK tahsilat yapmaz. Kartı harici POS cihazınızdan siz okutup tutarı burada manuel onaylayın.';
    } else if (p?['online'] != true) {
      metin = 'Terminal şu an çevrimdışı görünüyor${p?['message'] != null ? ' (${p!['message']})' : ''} — gönderim beklemede kalabilir, tutarı manuel doğrulayın.';
    } else {
      metin = 'Tutar POS terminaline gönderilir; tahsilat yalnız doğrulanmış terminal onayıyla tamamlanır${p?['terminal_id'] != null ? ' (terminal ${p!['terminal_id']})' : ''}.';
    }
    final renk = manuel ? Renk.uyari : Renk.basari;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: manuel ? Renk.uyariZemin : Renk.basariZemin,
        borderRadius: koseYuvarlak,
        border: Border.all(color: manuel ? Renk.uyariKenar : Renk.basariKenar),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(manuel ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded, size: 18, color: renk),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kart POS: ${p?['provider_label'] ?? 'Durum okunuyor…'}', style: TextStyle(fontWeight: FontWeight.w700, color: renk, fontSize: 13)),
            Text(metin, style: TextStyle(fontSize: 12, color: renk)),
          ]),
        ),
      ]),
    );
  }

  Widget _odemeDugmesi({double yukseklik = 48, bool buyuk = false}) {
    if (!_odemeYetkisi) return const SizedBox.shrink();
    if (_yontem == null) {
      return Container(
        height: yukseklik,
        alignment: Alignment.center,
        decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          RotatedBox(quarterTurns: 3, child: Icon(Icons.arrow_forward_rounded, size: 16, color: Renk.ikinci)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(buyuk ? 'Tahsilat için önce yukarıdan ödeme yöntemini seçin' : 'Önce ödeme yöntemini seçin',
                textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(minimumSize: Size.fromHeight(yukseklik), textStyle: TextStyle(fontSize: buyuk ? 18 : 16, fontWeight: FontWeight.w800)),
      onPressed: _odeniyor ? null : _ode,
      child: _odeniyor
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : FittedBox(fit: BoxFit.scaleDown, child: Text('$_odemeDugmeMetni — ${para(_tutarMinor)}')),
    );
  }

  Widget _mobilOdemeCubugu() {
    final y = kasaYontemleri.where((e) => e.$1 == _yontem).firstOrNull;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Renk.yuzey,
        border: Border(top: BorderSide(color: Renk.cizgi)),
        boxShadow: [BoxShadow(color: Color(0x1A0F172A), blurRadius: 12, offset: Offset(0, -2))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Kalan '),
            TextSpan(text: para(_kalan), style: const TextStyle(fontWeight: FontWeight.w800)),
          ])),
          const Spacer(),
          if (y != null) ...[
            Icon(kasaSimge(y.$3), size: 16, color: Renk.ikinci),
            const SizedBox(width: 4),
            Text(y.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
          ] else
            Text('Yöntem seçilmedi', style: TextStyle(color: Renk.uyari, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        _odemeDugmesi(),
      ]),
    );
  }

  /// OdemeListesi: "Yapılan ödemeler".
  Widget _yapilanOdemeler() {
    final basarili = _odemeler.where((p) => p['kind'] == 'payment' && p['status'] == 'succeeded').toList();
    final iptal = _odemeler.where((p) => p['kind'] == 'payment' && p['status'] == 'cancelled').length;
    if (basarili.isEmpty) return const SizedBox.shrink();
    final toplam = basarili.fold<int>(0, (t, p) => t + tamSayi(p['amount_minor']));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 15, color: Renk.ikinci),
          const SizedBox(width: 6),
          Text('YAPILAN ÖDEMELER', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Renk.ikinci, letterSpacing: .4)),
          const Spacer(),
          Text('${basarili.length} ödeme · ${para(toplam)}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        ]),
        for (final p in basarili) ...[
          const Divider(height: 14),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Ödeme · '),
                  TextSpan(text: para(tamSayi(p['amount_minor'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (tamSayi(p['tip_minor']) > 0) TextSpan(text: ' (+${para(tamSayi(p['tip_minor']))} bahşiş)'),
                ]), style: const TextStyle(fontSize: 13)),
                Row(children: [
                  Icon(kasaSimge(p['method_icon']?.toString()), size: 13, color: Renk.soluk),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text.rich(
                      TextSpan(children: [
                        const TextSpan(text: 'Ödeme yöntemi: '),
                        TextSpan(text: '${p['method_label'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' · ${saatMetni(p['created_at']?.toString())} · ${p['cashier'] ?? ''}'),
                      ]),
                      style: TextStyle(fontSize: 12, color: Renk.ikinci),
                    ),
                  ),
                ]),
              ]),
            ),
            if (_iadeYetkisi) ...[
              if (const ['cash', 'card_present', 'mock', 'demo', null].contains(p['provider']) && tamSayi(p['refunded_total_minor']) == 0)
                IconButton(tooltip: 'Yöntemi değiştir', onPressed: _mesgul ? null : () => _yontemDegistir(p), icon: const Icon(Icons.sync_rounded, size: 17))
              else
                Tooltip(
                  message: 'Terminal/sanal POS onaylı ödeme; iptal edip yeniden alın.',
                  child: Text('terminal onaylı', style: TextStyle(fontSize: 11, color: Renk.soluk)),
                ),
              if (tamSayi(p['refunded_total_minor']) == 0)
                IconButton(
                  tooltip: 'Ödemeyi kaldır',
                  onPressed: _mesgul ? null : () => _void(p),
                  icon: Icon(Icons.delete_outline_rounded, size: 17, color: Renk.hata),
                ),
            ],
          ]),
        ],
        if (iptal > 0) ...[
          const SizedBox(height: 6),
          Text('$iptal ödeme kaldırıldı — ayrıntısı "Ödemeler" sekmesinde.', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
        ],
      ]),
    );
  }

  /* ── §1.6 borç: döküm + ödeme bölmesi ── */

  Widget _borcDokumu() {
    final b = _borclu!;
    Widget segment(String k, String ad) => Expanded(
          child: InkWell(
            borderRadius: koseYuvarlak,
            onTap: () => setState(() => _borcSag = k),
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _borcSag == k ? Renk.marka : Renk.ic, borderRadius: koseYuvarlak),
              child: Text(ad, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _borcSag == k ? Colors.white : Renk.yazi)),
            ),
          ),
        );
    final icerik = _borcSag == 'hareket' ? _hareketListesi() : _borcAdisyonlari();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          segment('dokum', 'Adisyon dökümü'),
          const SizedBox(width: 6),
          segment('hareket', 'Hareketler(${_hareketler.length})'),
          const SizedBox(width: 10),
          Flexible(child: Text('${b['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
      const Divider(height: 1),
      if (MediaQuery.sizeOf(context).width >= 1024)
        Expanded(child: icerik)
      else
        ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .45), child: icerik),
    ]);
  }

  Widget _hareketListesi() {
    if (_dokumYukleniyor && _hareketler.isEmpty) return Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    if (_hareketler.isEmpty) return Center(child: Text('Hareket yok.', style: TextStyle(color: Renk.ikinci)));
    String yAd(Object? m) => switch ('$m') { 'cash' => 'Nakit', 'card' => 'Kart', 'transfer' => 'Havale/EFT', 'other' => 'Diğer', _ => '' };
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _hareketler.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final t = _hareketler[i];
        final tur = '${t['type']}';
        final geriAlma = t['reverses_id'] != null;
        final etiket = geriAlma
            ? 'İskonto geri alındı'
            : switch (tur) { 'payment' => 'Tahsilat', 'discount' => 'Borç iskontosu', 'debt_transfer' => 'Adisyon borcu', 'opening' => 'Devir borcu', _ => 'Düzeltme' };
        final tutar = tamSayi(t['amount_minor']);
        final yontem = yAd(t['method']);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('$etiket${t['order_id'] != null ? ' · #${t['order_id']}' : ''}${yontem.isNotEmpty ? ' · $yontem' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (t['reversed'] == true) const Rozet('geri alındı'),
                ]),
                Text('${_tarihSaat(t['created_at']?.toString())}${t['performed_by'] != null ? ' · ${t['performed_by']}' : ''}',
                    style: TextStyle(fontSize: 12, color: Renk.soluk)),
                if (!geriAlma && t['note'] != null) Text('${t['note']}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                if (_borcIskontoAcik && tur == 'discount' && !geriAlma && t['reversed'] != true)
                  t['locked'] == true
                      ? Text('Sonrasında ödeme alındı · değiştirilemez', style: TextStyle(fontSize: 11.5, color: Renk.soluk))
                      : Wrap(spacing: 6, children: [
                          OutlinedButton(onPressed: () => _borcIskontoGeriAl(tamSayi(t['id']), tutar.abs(), degistir: true), child: const Text('Değiştir')),
                          OutlinedButton(onPressed: () => _borcIskontoGeriAl(tamSayi(t['id']), tutar.abs(), degistir: false), child: const Text('Kaldır')),
                        ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${tutar > 0 ? '+' : ''}${para(tutar)}', style: TextStyle(fontWeight: FontWeight.w700, color: tutar > 0 ? Renk.hata : Renk.basari)),
              Text('kalan ${para(tamSayi(t['balance_after_minor']))}', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
            ]),
          ]),
        );
      },
    );
  }

  Widget _borcAdisyonlari() {
    final d = _dokum;
    if (d == null) return Center(child: Text('Yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    final siparisler = (d['orders'] as List? ?? const []).whereType<Map>().toList();
    if (siparisler.isEmpty) {
      return _bos(Icons.receipt_outlined, 'Açık adisyon borcu yok',
          'Ödenmemiş adisyon borcu görünmüyor: borç elle girilmiş, adisyonu silinmiş ya da tamamı tahsil edilmiş olabilir. Hareket geçmişi Hareketler sekmesinde.');
    }
    Widget satir(String a, String b, {Color? renk, bool kalin = false, bool cizik = false}) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontSize: 12.5, color: (renk ?? Renk.yazi) == Renk.yazi ? Renk.ikinci : (renk ?? Renk.yazi)))),
            Text(b,
                style: TextStyle(fontSize: 13, color: (renk ?? Renk.yazi), fontWeight: kalin ? FontWeight.w700 : FontWeight.w500, decoration: cizik ? TextDecoration.lineThrough : null)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(10), children: [
      for (final o in siparisler)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Adisyon #${o['order_id']}${o['table'] != null ? ' · ${o['table']}' : ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(_tarihSaat(o['at']?.toString()), style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
            ]),
            const SizedBox(height: 6),
            if ((o['items'] as List? ?? const []).isEmpty) Text('Kalem bilgisi yok (adisyon silinmiş olabilir).', style: TextStyle(fontSize: 12, color: Renk.soluk)),
            for (final k in (o['items'] as List? ?? const []).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 6, children: [
                        Text('${k['qty']}× ${k['name']}', style: const TextStyle(fontSize: 13)),
                        if (k['is_comp'] == true) Rozet('İkram', renk: Renk.bilgi),
                      ]),
                      Text('${para(tamSayi(k['unit_minor']))} / adet · KDV ${_oran(k['tax_rate'])} dahil', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
                    ]),
                  ),
                  Text(para(tamSayi(k['line_total_minor'])),
                      style: TextStyle(fontWeight: FontWeight.w600, decoration: k['is_comp'] == true ? TextDecoration.lineThrough : null)),
                ]),
              ),
            if (tamSayi(o['discount_minor']) > 0) satir('İndirim', '−${para(tamSayi(o['discount_minor']))}', renk: Renk.hata),
            if (tamSayi(o['iskonto_minor']) > 0) satir('Adisyon iskontosu', '−${para(tamSayi(o['iskonto_minor']))}', renk: Renk.uyari),
            const Divider(height: 14),
            satir('Borca yazılan', para(tamSayi(o['amount_minor'])), renk: o['partial'] == true ? Renk.soluk : Renk.hata, kalin: true, cizik: o['partial'] == true),
            for (final i in (o['borc_iskontolari'] as List? ?? const []).whereType<Map>())
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Renk.uyariZemin, borderRadius: koseYuvarlak),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        'Borç iskontosu${tamSayi(i['applied_minor']) != tamSayi(i['amount_minor']) ? ' (toplam ${para(tamSayi(i['amount_minor']))} iskontonun payı)' : ''}',
                        style: TextStyle(fontSize: 12, color: Renk.uyari)),
                  ),
                  Text('−${para(tamSayi(i['applied_minor']))}', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.uyari)),
                  if (_borcIskontoAcik)
                    i['locked'] == true
                        ? Padding(padding: EdgeInsets.only(left: 6), child: Text('ödeme sonrası · kilitli', style: TextStyle(fontSize: 11, color: Renk.soluk)))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            TextButton(onPressed: () => _borcIskontoGeriAl(tamSayi(i['id']), tamSayi(i['amount_minor']), degistir: true), child: const Text('Değiştir')),
                            TextButton(onPressed: () => _borcIskontoGeriAl(tamSayi(i['id']), tamSayi(i['amount_minor']), degistir: false), child: const Text('Kaldır')),
                          ]),
                ]),
              ),
            if (tamSayi(o['tahsil_minor']) > 0) satir('Tahsil edilen', '−${para(tamSayi(o['tahsil_minor']))}', renk: Renk.basari),
            if (o['partial'] == true) satir('Kalan borç', para(tamSayi(o['remaining_minor'])), renk: Renk.hata, kalin: true),
          ]),
        ),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
        child: Column(children: [
          satir('Toplam KDV (fiyatlara dahil)', para(tamSayi(d['vat_total_minor']))),
          satir('Güncel borç', para(tamSayi(d['balance_minor'] ?? _bakiye)), renk: Renk.hata, kalin: true),
        ]),
      ),
    ]);
  }

  void _borcTus(String k) {
    if (_hedef != 'iskonto' && _hedef != 'debtTendered') _hedef = 'debt';
    _tus(k);
  }

  void _borcHizli(double oran) => setState(() {
        _borcTutar = paraGirdisi(oran >= 1 ? _bakiye : (_bakiye * oran).ceil());
        _hedef = 'debt';
        _taze = true;
      });

  void _borcTemizle() => setState(() {
        if (_hedef == 'iskonto') {
          _borcIskonto = '';
        } else if (_hedef == 'debtTendered') {
          _borcVerilen = '';
        } else {
          _borcTutar = '';
        }
      });

  Widget _borcOdemeBolmesi(double g) {
    final b = _borclu!;
    final ad = '${b['name'] ?? ''}';
    final f = _sonBorcFisi;
    final genis = g >= 1024;

    if (f != null && _bakiye == 0) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 24),
          Icon(Icons.check_circle_outline_rounded, size: 56, color: Renk.basari),
          const SizedBox(height: 10),
          const Text('Borç tamamen kapandı', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$ad — ${para(f.tahsil)} tahsil edildi.', style: TextStyle(color: Renk.ikinci)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            OutlinedButton.icon(onPressed: _borcFisi, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Tahsilat fişi yazdır')),
            OutlinedButton.icon(onPressed: () => _borcFisi(onizle: true), icon: const Icon(Icons.receipt_outlined, size: 18), label: const Text('Önizle')),
            FilledButton.icon(onPressed: _secimeDon, icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Şahıslara dön')),
          ]),
        ]),
      );
    }

    final nakit = _borcYontem == 'cash';
    final verilen = paraCoz(_borcVerilen);
    final ust = nakit && verilen != null ? (verilen - _borcTutarMinor).clamp(0, 1 << 40) : null;
    final kismi = _borcTutarMinor > 0 && _borcTutarMinor < _bakiye;
    final iskonto = paraCoz(_borcIskonto) ?? 0;
    final iskontoGecerli = iskonto > 0 && iskonto <= _bakiye;

    final ogeler = <Widget>[
      Row(children: [
        TextButton.icon(onPressed: _secimeDon, icon: const Icon(Icons.arrow_back_rounded, size: 18), label: Text(g >= 640 ? 'Şahıslar' : '')),
        const SizedBox(width: 4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Borç Tahsilatı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            Text([ad, if (b['phone'] != null) '${b['phone']}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (kismi) Text('Sonrası kalan ${para(_bakiye - _borcTutarMinor)}', style: TextStyle(fontSize: 12, color: Renk.uyari)),
          Text('KALAN BORÇ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
          Text(para(_bakiye), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Renk.hata)),
        ]),
      ]),
      if (f != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Renk.basariZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.basariKenar)),
          child: Row(children: [
            Expanded(child: Text('${para(f.tahsil)} tahsil edildi · kalan ${para(f.kalan)}', style: TextStyle(color: Renk.basari, fontWeight: FontWeight.w600))),
            TextButton(onPressed: _borcFisi, child: const Text('Fiş yazdır')),
            TextButton(onPressed: () => _borcFisi(onizle: true), child: const Text('Önizle')),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      _girdiKutusu(etiket: 'Tahsil edilecek (₺)', hedef: 'debt', metin: _borcTutar, buyuk: true),
      if (nakit) ...[
        const SizedBox(height: 8),
        _girdiKutusu(
          etiket: 'Verilen para (₺)',
          hedef: 'debtTendered',
          metin: _borcVerilen,
          sag: Text('Para üstü: ${ust == null ? '—' : para(ust, simge: false)} ₺',
              style: TextStyle(fontSize: 12, color: (ust ?? 0) > 0 ? Renk.basari : Renk.ikinci, fontWeight: (ust ?? 0) > 0 ? FontWeight.w700 : null)),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in _nakitPresetleri(_borcTutarMinor > 0 ? _borcTutarMinor : _bakiye))
            OutlinedButton(
              onPressed: () => setState(() {
                _borcVerilen = paraGirdisi(p);
                _hedef = 'debtTendered';
              }),
              child: Text(para(p)),
            ),
        ]),
      ],
      const SizedBox(height: 10),
      if (g >= 768) ...[
        _numpad(borc: true),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Numpad '),
            TextSpan(
                text: _hedef == 'iskonto' ? 'iskonto tutarına' : (_hedef == 'debtTendered' ? 'verilen paraya' : 'tahsil tutarına'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const TextSpan(text: ' yazar · yazmak istediğiniz kutuya dokunun.'),
          ]),
          style: TextStyle(fontSize: 12, color: Renk.ikinci),
        ),
      ] else
        Wrap(spacing: 6, children: [
          OutlinedButton(onPressed: () => _borcHizli(1), child: const Text('Tamamı')),
          OutlinedButton(onPressed: () => _borcHizli(1 / 2), child: const Text('½')),
          OutlinedButton(onPressed: () => _borcHizli(1 / 3), child: const Text('⅓')),
        ]),
      if (_borcIskontoAcik) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _hedef == 'iskonto' ? Renk.uyariZemin : null,
            borderRadius: koseYuvarlak,
            border: Border.all(color: _hedef == 'iskonto' ? Renk.uyari : Renk.cizgiKoyu),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: _girdiKutusu(etiket: 'İskonto (₺)', hedef: 'iskonto', metin: _borcIskonto, vurgu: Renk.uyari)),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Renk.uyari, minimumSize: const Size(0, 48)),
                onPressed: iskontoGecerli && !_mesgul ? _borcIskontoYap : null,
                child: const Text('İndir'),
              ),
            ]),
            const SizedBox(height: 4),
            if (_borcIskonto.isNotEmpty)
              iskontoGecerli
                  ? Row(children: [
                      Text('−${para(iskonto)} düşülür', style: TextStyle(fontSize: 12, color: Renk.uyari)),
                      const Spacer(),
                      Text('kalan borç ${para(_bakiye - iskonto)}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                    ])
                  : Text("Tutar 0'dan büyük olmalı, borcu (${para(_bakiye)}) aşamaz.", style: TextStyle(fontSize: 12, color: Renk.hata)),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Renk.bilgiZemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.bilgiKenar)),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Bu tahsilat bir adisyona bağlı değildir. '),
            TextSpan(text: 'Nakit', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' seçilirse kasa çekmecesine ve Z raporuna düşer; kart/havale POS akışına girmez.'),
          ]),
          style: TextStyle(fontSize: 12.5, color: Renk.bilgi),
        ),
      ),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: g >= 1024 ? 1.8 : 1.3,
        children: [
          for (final (k, a, i) in const [
            ('cash', 'Nakit', Icons.account_balance_wallet_outlined),
            ('card', 'Kart', Icons.credit_card_rounded),
            ('transfer', 'Havale', Icons.arrow_forward_rounded),
            ('other', 'Diğer', Icons.more_vert_rounded),
          ])
            _yontemKutusu(k, a, i, _borcYontem == k, () => setState(() => _borcYontem = k), ton: k == 'card' ? 'diger' : k),
        ],
      ),
      const SizedBox(height: 10),
      if (_borcYontem == null)
        Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
          child: Text('Tahsilat için önce yukarıdan ödeme yöntemini seçin', style: TextStyle(color: Renk.ikinci, fontWeight: FontWeight.w600)),
        )
      else
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          onPressed: _borcTutarMinor <= 0 || _mesgul ? null : _borcTahsil,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
                '${switch (_borcYontem) { 'cash' => 'Nakit', 'card' => 'Kart', 'transfer' => 'Havale', _ => 'Diğer' }} tahsilatı al — ${para(_borcTutarMinor)}'),
          ),
        ),
    ];

    final icerik = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: ogeler);
    return genis ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: icerik) : Padding(padding: const EdgeInsets.all(12), child: icerik);
  }
}
