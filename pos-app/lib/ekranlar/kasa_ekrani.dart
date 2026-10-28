import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/katalog_deposu.dart';
import '../core/modeller.dart';
import '../core/pos_cihaz.dart';
import 'adet_kartlari.dart';
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

/// Son seçilen manuel kart POS cihazı (uygulama oturumu boyunca hatırlanır).
int? _secilenPosCihazi;

/// Ethernet'li kart POS'larına bağlantı denemeleri (uygulama boyunca ortak).
final _posErisim = PosErisimOnbellegi();

/// Aktif personelin işlem için yetkisi yok mu (sunucu: 403 ya da 422
/// `errors.operator` — TerminalPinGate::actorOrOperator)? Öyleyse yetkili
/// personelin PIN'iyle yeniden denenebilir.
bool personelYetkiReddi(ApiHata e) {
  if (e.kod == 403) return true;
  if (e.kod != 422) return false;
  final h = e.govde?['errors'];
  return h is Map && h.containsKey('operator');
}

/// Kart durumu (§1.3 kartDurum).
enum _KartDurum { acik, kismi, odendi, hesap }

class _KasaEkraniState extends State<KasaEkrani> with WidgetsBindingObserver {
  late final Api _api;
  Timer? _tur;

  /// CANLI ADİSYON (1.2.19): açık adisyonun kalemleri ve ödemeleri 3 sn'de bir
  /// ETag'le sorulur; değişmediyse (304 / aynı gövde) hiçbir şey çizilmez.
  Timer? _canli;
  bool _canliCalisiyor = false;
  String? _detayEtag;
  String? _detayImza;
  String? _odemeEtag;

  /// Canlı güncellemeyle yeni gelen satırlar kısa süre hafif vurgulanır.
  Set<int> _yeniKalemler = const {};
  Timer? _yeniSayaci;
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
  bool _duzelt = false;
  /// Kalem seçimi (adet adet): satırlar yalnız bunu dinler, bütün ekran
  /// yeniden çizilmez (zayıf tablet — Lenovo TB-X606F).
  final _secim = _KalemSecimi();

  /// Adedi birden fazla olan, açılmış (adet seçicisi görünen) satır.
  final _acikKalem = ValueNotifier<int?>(null);
  late final Listenable _satirDinle = Listenable.merge([_secim, _acikKalem]);

  /// Ödeme bölmesini (sol) seçimden gelen tutarla yeniden çizer.
  final _odemeTetik = _Tetik();
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
    _canli = Timer.periodic(const Duration(seconds: 3), (_) => _canliTazele());
    WidgetsBinding.instance.addObserver(this);
    _secim.addListener(_secimDegisti);
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
    _canli?.cancel();
    _yeniSayaci?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    kasaBorcIstegi.removeListener(_borcIstegi);
    _kilitSayaci?.cancel();
    _odak.dispose();
    _bahsis.dispose();
    _secim.dispose();
    _acikKalem.dispose();
    _odemeTetik.dispose();
    super.dispose();
  }

  /* ═════════════ Yükleme / yoklama (§6) ═════════════ */

  void _kasaTuru() {
    if (!mounted || _modal > 0 || _duzelt || !context.yoklamaUygun) return;
    _yukle(sessiz: true);
    _posDurumu(sessiz: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Öne gelince beklemeden tazele (arka planda yoklama yapılmaz).
    if (s == AppLifecycleState.resumed) _canliTazele();
  }

  /// Açık adisyonu başka cihazlardaki değişikliklerle eşitler (garson 1 çay
  /// daha ekledi → kasada çıkıp girmeden görünür). Pencere açıkken, işlem
  /// sürerken ya da uygulama arka plandayken atlanır.
  Future<void> _canliTazele() async {
    if (!mounted || _secili == null || _canliCalisiyor || _modal > 0 || _mesgul || _odeniyor || !context.yoklamaUygun) return;
    _canliCalisiyor = true;
    try {
      await Future.wait([_seciliyiTazele(canli: true), _detayiTazele(canli: true)]);
    } finally {
      _canliCalisiyor = false;
    }
  }

  Future<void> _yukle({bool sessiz = false}) async {
    try {
      final r = await _api.get('/api/v1/payments/pending-orders', sorgu: {'q': ''});
      final l = (r is Map ? r['orders'] as List? : null) ?? const [];
      final yl = r is Map ? r['odeme_yontemleri'] : null;
      if (!mounted) return;
      setState(() {
        if (yl is List) {
          acikKasaYontemleri = yl.map((e) => '$e').toSet();
          // Seçili yöntem az önce kapatıldıysa seçim bırakılır.
          if (_yontem != null && !acikKasaYontemleri!.contains(_yontem)) _yontem = null;
        }
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
      _detayEtag = _detayImza = _odemeEtag = null;
      _duzelt = false;
      _secim.temizle();
      _acikKalem.value = null;
      _borclu = null;
    });
    _formuSifirla();
    await Future.wait([_seciliyiTazele(hataGoster: true), _detayiTazele()]);
    _formuSifirla();
  }

  Future<void> _seciliyiTazele({bool hataGoster = false, bool canli = false}) async {
    final s = _secili;
    if (s == null) return;
    try {
      final y = await _api.getEtagli('/api/v1/orders/${s.id}/payments', _odemeEtag);
      if (y == null) return; // 304: değişmedi
      final r = y.veri;
      if (!mounted || _secili?.id != s.id || r is! Map) return;
      final oncekiKalan = _kalan;
      setState(() {
        _odemeEtag = y.etag;
        if (r['order'] is Map) _secili = AdisyonOzet((r['order'] as Map).cast<String, dynamic>());
        _odemeler = (r['payments'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      });
      // Kalan değişti ve kasiyer tutara dokunmadıysa tutar kendiliğinden güncellenir.
      if (canli && _kalan != oncekiKalan) _tutariEsitle();
    } on ApiHata catch (e) {
      if (hataGoster && mounted) context.bildir2('Adisyon yüklenemedi', e.mesaj, hata: true);
    }
  }

  /// Canlı güncelleme sonrası: kasiyer tutarı elle yazmadıysa (taze) tutar
  /// kalan/seçime göre yeniden kurulur.
  void _tutariEsitle() {
    if (!mounted || _secili == null || !_taze || _hedef != 'amount') return;
    _tutar = _kalan > 0 ? paraGirdisi(_secim.bos ? _kalan : _seciliToplam.clamp(0, _kalan)) : '';
    _odemeTetik.tetikle();
  }

  Future<void> _detayiTazele({bool canli = false}) async {
    final s = _secili;
    if (s == null) return;
    if (!(_kalemDuzenler || _ikramEder || _can('orders.view'))) {
      if (!_detayYasak) setState(() => _detayYasak = true);
      return;
    }
    try {
      final y = await _api.getEtagli('/api/v1/orders/${s.id}', _detay == null ? null : _detayEtag);
      if (y == null) return; // 304: değişmedi
      final r = y.veri;
      if (!mounted || _secili?.id != s.id || r is! Map || r['order'] is! Map) return;
      final ham = (r['order'] as Map).cast<String, dynamic>();
      _detayEtag = y.etag;
      // ETag'siz eski sunucu: gövde aynıysa hiçbir şey yeniden çizilmez.
      final imza = jsonEncode(ham);
      if (_detay != null && imza == _detayImza) return;
      _detayImza = imza;
      final yeni = Adisyon(ham);
      final eskiIdler = _detay?.kalemler.map((k) => k.id).toSet();
      setState(() {
        if (canli && eskiIdler != null) {
          final gelen = {for (final k in yeni.aktifKalemler) if (!eskiIdler.contains(k.id)) k.id};
          if (gelen.isNotEmpty) {
            _yeniKalemler = gelen;
            _yeniSayaci?.cancel();
            _yeniSayaci = Timer(const Duration(milliseconds: 2500), () {
              if (mounted) setState(() => _yeniKalemler = const {});
            });
          }
        }
        _detay = yeni;
      });
      // Ödenmiş / çıkarılmış / adedi düşmüş satırların seçimi düşer
      // (kalan seçim satırın ödenmemiş adedine kırpılır).
      final secimDegisti = _secim.ayikla(yeni.aktifKalemler.where(_secilebilir));
      if (_acikKalem.value != null && !yeni.aktifKalemler.any((k) => k.id == _acikKalem.value && _secilebilir(k) && k.adet > 1)) {
        _acikKalem.value = null;
      }
      if (canli) {
        _tutariEsitle();
        if (secimDegisti && mounted) context.bildir2('Adisyon güncellendi', 'Başka bir cihazdaki değişiklik nedeniyle seçiminiz güncellendi.');
      }
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
        _detayEtag = _detayImza = _odemeEtag = null;
        _borclu = null;
        _duzelt = false;
        _secim.temizle();
        _acikKalem.value = null;
        _sonBorcFisi = null;
      });

  /// Kalem/indirim/iskonto değişikliği sonrası (§4.9 afterItemChange).
  /// [yanit]: işlemin döndürdüğü güncel adisyon (`{order}` — kalemleriyle);
  /// varsa ekran ondan kurulur, ödemeler + detay GET'i atılmaz.
  Future<void> _degisimSonrasi({bool liste = true, dynamic yanit}) async {
    if (!_yanittanGuncelle(yanit)) await Future.wait([_seciliyiTazele(), _detayiTazele()]);
    if (liste) _yukle(sessiz: true);
    if (mounted) {
      setState(() {
        _tutar = _kalan > 0 ? paraGirdisi(_secim.bos ? _kalan : _seciliToplam.clamp(0, _kalan)) : '';
        _taze = true;
      });
    }
  }

  /// İşlem yanıtındaki güncel adisyonu (detay biçimi: özet + `items`)
  /// ekrana basar. Kalemsiz / başka adisyona ait / boş yanıtta false döner
  /// (çağıran GET ile tazeler).
  bool _yanittanGuncelle(dynamic r) {
    final s = _secili;
    if (!mounted || s == null || r is! Map || r['order'] is! Map) return false;
    final ham = (r['order'] as Map).cast<String, dynamic>();
    if (tamSayi(ham['id']) != s.id || ham['items'] is! List) return false;
    final yeni = Adisyon(ham);
    final ozet = Map<String, dynamic>.from(ham)
      ..remove('items')
      ..remove('events');
    setState(() {
      _secili = AdisyonOzet({...s.ham, ...ozet});
      _detay = yeni;
      _detayImza = jsonEncode(ham);
    });
    _secim.ayikla(yeni.aktifKalemler.where(_secilebilir));
    if (_acikKalem.value != null && !yeni.aktifKalemler.any((k) => k.id == _acikKalem.value && _secilebilir(k) && k.adet > 1)) {
      _acikKalem.value = null;
    }
    return true;
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

  /* ── Masaüstü sıkı düzen (1.2.20): kasa bilgisayarında (1366×768 …) her şey
     kaydırmadan sığsın. Tablet / telefon düzeni DEĞİŞMEZ. ── */
  static bool get _masaustu =>
      defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux;

  /// Sağ döküm: masaüstünde ekran yüksekliği 1000 px'ten azsa sık satırlar.
  bool get _sikSag {
    final b = MediaQuery.sizeOf(context);
    return _masaustu && b.width >= 1024 && b.height < 1000;
  }

  /// Sol ödeme bölmesinin o anki ölçüsü (_odemeBolmesiIc ayarlar).
  bool _sikSol = false;
  bool _masaustuSol = false;
  double _tusYuksekligi = 54;

  bool get _terminalYontemi => kasaYontemleri.any((y) => y.$1 == _yontem && y.$4);
  bool get _posManuel => (_pos?['simulated'] ?? true) == true || (_pos?['online'] ?? false) != true;

  /// Konsolda tanımlı, etkin manuel kart POS cihazları (sunucu
  /// `terminal-status.manuel_cihazlar`). Alan yoksa / boşsa eski davranış.
  List<Json> get _manuelCihazlar => ((_pos?['manuel_cihazlar'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .where((e) => e['id'] != null)
      .toList();

  /// Kart okutulacak manuel cihaz (yalnız entegre terminal yokken).
  Json? get _posCihazi {
    if (!_posManuel) return null;
    final l = _manuelCihazlar;
    if (l.isEmpty) return null;
    return l.where((c) => tamSayi(c['id']) == _secilenPosCihazi).firstOrNull ?? l.first;
  }

  String get _odemeDugmeMetni {
    if (_terminalYontemi && _posCihazi != null) return 'Kartla ödendi — onayla';
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
      };
      // KISMİ ADET (2026-10-27): seçilen her satır {id, qty}; sunucu satırı
      // böler (4× çaydan 2'si ödendi → 2 ödenmiş + 2 açık satır).
      final cihaz = _terminalYontemi ? _posCihazi : null;
      if (cihaz != null) govde['pos_cihaz_id'] = tamSayi(cihaz['id']);
      final secilenler = _seciliKalemler;
      if (secilenler.isNotEmpty) govde['items'] = [for (final x in secilenler) {'id': x.kalem.id, 'qty': x.adet}];
      dynamic r;
      try {
        r = await _api.post('/api/v1/orders/${s.id}/payments', govde, {'Idempotency-Key': _api.yeniIslemKimligi()});
      } on ApiHata catch (e) {
        if (secilenler.isEmpty || !_itemsReddi(e)) rethrow;
        // Eski sunucu `items` alanını tanımıyor: yalnız bütün satırlar
        // seçiliyse eski `item_ids` ile denenir; kısmi adet gönderilemez.
        if (secilenler.any((x) => x.adet < x.kalem.adet)) {
          throw ApiHata(422, 'Sunucu kısmi ödemeyi henüz desteklemiyor. Satırın tamamını seçin ya da tutarı elle girin.');
        }
        govde
          ..remove('items')
          ..['item_ids'] = [for (final x in secilenler) x.kalem.id];
        r = await _api.post('/api/v1/orders/${s.id}/payments', govde, {'Idempotency-Key': _api.yeniIslemKimligi()});
      }
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
      // Sunucu satırları böldü: seçim temizlenir, güncel hali yüklenir.
      _secim.temizle();
      _acikKalem.value = null;
      await Future.wait([_seciliyiTazele(), _detayiTazele()]);
      _yukle(sessiz: true);
      _formuSifirla();
    } on ApiHata catch (e) {
      if (mounted) {
        if (e.kod == 409 || (e.kod == 422 && _cakisma(e))) {
          // Başka bir kasa/garson aynı anda ödeme aldı ya da adisyon değişti.
          context.bildir2('Adisyon değişti',
              '${e.mesaj.isNotEmpty ? '${e.mesaj} ' : ''}Başka bir cihazda işlem yapılmış olabilir; güncel hali yüklendi — seçimi kontrol edip tekrar deneyin.',
              hata: true);
          _secim.temizle();
          _acikKalem.value = null;
          await Future.wait([_seciliyiTazele(), _detayiTazele()]);
          _formuSifirla();
        } else {
          context.bildir2('Ödeme alınamadı', e.mesaj, hata: true);
          _seciliyiTazele();
        }
      }
    } finally {
      _odeniyor = false;
      if (mounted) setState(() {});
    }
  }

  /// 0 ₺ ADİSYONU KAPAT: tüm kalemleri ikram edilmiş (alınacak para
  /// kalmamış) açık adisyon. Ödeme ucu 0 ₺ kabul etmez; sunucu
  /// `sifir-kapat` adisyonu "Ödendi" kapatır, masayı boşaltır. Ödeme gibi
  /// aktif personele atfedilir (PIN gönderilmez); kilit `_odeniyor`.
  Future<void> _sifirKapat() async {
    final s = _secili;
    if (s == null || _odeniyor) return;
    final surum = _surum;
    _odeniyor = true; // senkron kilit: çift dokunuş ikinci istek atmaz
    setState(() {});
    try {
      final r = await _api.post('/api/v1/orders/${s.id}/sifir-kapat', {'expected_version': surum}, {'Idempotency-Key': _api.yeniIslemKimligi()});
      if (!mounted) return;
      context.bildir2('Adisyon kapatıldı', 'Tahsil edilecek tutar yoktu; masa boşaltıldı.');
      _secim.temizle();
      _acikKalem.value = null;
      // Yanıt güncel özeti taşır: ödemeler yeniden sorulmaz, yalnız kalemler.
      final o = r is Map && r['order'] is Map ? (r['order'] as Map).cast<String, dynamic>() : null;
      final simdiki = _secili;
      if (o != null && simdiki != null && simdiki.id == s.id && tamSayi(o['id']) == s.id) {
        setState(() => _secili = AdisyonOzet({...simdiki.ham, ...o}..remove('items')..remove('events')));
        await _detayiTazele();
      } else {
        await Future.wait([_seciliyiTazele(), _detayiTazele()]);
      }
      _yukle(sessiz: true);
      _formuSifirla();
    } on ApiHata catch (e) {
      if (mounted) {
        context.bildir2('Adisyon kapatılamadı', e.mesaj, hata: true);
        await Future.wait([_seciliyiTazele(), _detayiTazele()]);
      }
    } finally {
      _odeniyor = false;
      if (mounted) setState(() {});
    }
  }

  /* ═════════════ Kalem seçimi (§4.4) — adet adet ═════════════ */

  List<Kalem> get _gorunenKalemler => _detay?.aktifKalemler ?? const [];

  /// Parası alınabilecek satır: ikram değil, ödenmemiş, adedi var.
  bool _secilebilir(Kalem k) => !k.ikram && !k.odendi && k.odenmemisAdet > 0;

  /// Seçili satırlar ve seçilen adetleri (adet ≤ satırın ödenmemiş adedi).
  List<({Kalem kalem, int adet})> get _seciliKalemler => [
    for (final k in _gorunenKalemler)
      if (_secilebilir(k) && _secim.adet(k.id) > 0) (kalem: k, adet: _secim.adet(k.id).clamp(1, k.odenmemisAdet)),
  ];

  /// Satırın n adedinin tutarı (satır toplamından orantılı; tamamı = satır toplamı).
  static int _payTutari(Kalem k, int n) => n >= k.adet ? k.tutar : (k.adet == 0 ? 0 : (k.tutar * n / k.adet).round());

  int get _seciliToplam => _seciliKalemler.fold(0, (t, x) => t + _payTutari(x.kalem, x.adet));
  int get _seciliAdet => _seciliKalemler.fold(0, (t, x) => t + x.adet);

  /// Seçim değişince tahsil tutarı canlı güncellenir — yalnız ödeme
  /// bölmesi yeniden çizilir (setState YOK).
  void _secimDegisti() {
    if (_secili == null) return;
    _tutar = paraGirdisi(_secim.bos ? _kalan : _seciliToplam.clamp(0, _kalan));
    _hedef = 'amount';
    _taze = true;
    _odemeTetik.tetikle();
  }

  /// Satıra dokunma: tek adetli satır seçilir/bırakılır; çok adetli satır açılır.
  void _kalemDokun(Kalem k) {
    if (_duzelt || !_secilebilir(k)) return;
    HapticFeedback.selectionClick();
    if (k.adet > 1) {
      _acikKalem.value = _acikKalem.value == k.id ? null : k.id;
    } else {
      _secim.satirDegistir(k);
    }
  }

  /// Başlık kutusu: satırın ödenmemiş adetlerinin TAMAMINI seç / bırak
  /// (kısmi seçiliyken tamamlar — web sipariş detayındaki ana kutu gibi).
  void _kalemKutusu(Kalem k) {
    if (_duzelt || !_secilebilir(k)) return;
    HapticFeedback.selectionClick();
    _secim.satirDegistir(k);
  }

  /// "Tutara yaz": elle değiştirilmiş tutarı seçime geri döndürür.
  void _seciminiYaz() => _secimDegisti();

  /// Sunucu `items` alanını tanımadı mı (eski sürüm doğrulaması)?
  bool _itemsReddi(ApiHata e) {
    if (e.kod != 422) return false;
    final hatalar = e.govde?['errors'];
    if (hatalar is Map && hatalar.keys.any((k) => '$k' == 'items' || '$k'.startsWith('items.'))) return true;
    final m = e.mesaj.toLowerCase();
    return m.contains('items') && !m.contains('item_ids');
  }

  /// 422 ama asıl sebep eşzamanlılık mı (satır zaten ödenmiş / sürüm eski)?
  bool _cakisma(ApiHata e) {
    final m = aramaAnahtari(e.mesaj);
    return m.contains('odenmis') || m.contains('zaten') || m.contains('degisti') || m.contains('version') || m.contains('surum');
  }

  /* ═════════════ Adisyon üzerinde işlemler ═════════════ */

  /// [yanittan]: uç güncel adisyonu `{order}` olarak döndürüyor (ikram /
  /// ikram kaldırma); ekran yanıttan güncellenir, ayrıca GET atılmaz.
  Future<bool> _islem(Future<dynamic> Function() f,
      {String? ok, String okMetin = '', String hataBaslik = 'İşlem tamamlanamadı', bool liste = true, bool yanittan = false}) async {
    if (_mesgul) return false;
    setState(() => _mesgul = true);
    try {
      final r = await f();
      if (ok != null && mounted) context.bildir2(ok, okMetin);
      await _degisimSonrasi(liste: liste, yanit: yanittan ? r : null);
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
  /// Bilinen adisyon sürümü; bilinmiyorsa null (sahte 0 gönderilmez).
  int? get _surum => _versiyon(_detay?.ham) ?? _versiyon(_secili?.ham);
  static int? _versiyon(Json? h) => h == null || h['version'] == null ? null : tamSayi(h['version']);

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

  /// Düzelt kipindeki "İkram yap": satırın TAMAMI (adet pencerede görünür,
  /// `qty` her zaman açıkça gider). Sürüm pencere açılmadan alınır.
  Future<void> _ikram(Kalem k) async {
    if (k.odendi || k.ikram) return;
    final surum = _surum;
    final n = k.adet;
    final neden = await _penceredeyken(() => ikramPenceresi(context, '$n × ${k.ad}'));
    if (neden == null || !mounted) return;
    await _ikramlariIsle([(kalem: k, adet: n)], neden, surum);
  }

  /// web canOrPin('orders.comp'): uygulama her zaman terminal oturumudur;
  /// yetkiyi sunucu işlemi yapan personelde denetler (adisyon ekranı gibi).
  /// Aktif personelin yetkisi yoksa yetkili personelin PIN'i sorulur
  /// (_yetkiliIstek).
  bool get _ikramGorunur => true;

  /// Seçim şeridindeki "İkram et": bir ya da birden çok satır. Tek neden
  /// sorulur; her satır SIRAYLA, seçilen adet kadar (`qty` her zaman açık)
  /// ikram edilir. Seçim, adetler ve sürüm pencere açılmadan alınır —
  /// pencere açıkken gelen bir yenileme seçilenden fazlasını ikram ettiremez.
  Future<void> _seciliIkram() async {
    if (_mesgul || !(_detay?.acik ?? false)) return;
    // _seciliKalemler yalnız ücretli satırları verir (ödenmiş / ikram hariç).
    final secim = [
      for (final x in _seciliKalemler)
        if (!x.kalem.odendi && !x.kalem.ikram) (kalem: x.kalem, adet: x.adet.clamp(1, x.kalem.adet)),
    ];
    if (secim.isEmpty) return;
    final surum = _surum;
    final ad = secim.map((x) => '${x.adet} × ${x.kalem.ad}').join(', ');
    final kalir = secim.fold<int>(0, (t, x) => t + x.kalem.adet - x.adet);
    final neden = await _penceredeyken(() => ikramPenceresi(context, ad, kalir: kalir));
    if (neden == null || !mounted) return;
    await _ikramlariIsle(secim, neden, surum);
  }

  /// Satırları sırayla ikram eder; her çağrı bir öncekinin döndürdüğü
  /// sürümle gider. Hata olursa durur: kaç satırın işlendiği söylenir,
  /// adisyon yeniden yüklenir, seçim temizlenir. Liste bir kez tazelenir.
  Future<void> _ikramlariIsle(List<({Kalem kalem, int adet})> secim, String neden, int? surum) async {
    final s = _secili;
    if (s == null || _mesgul || secim.isEmpty) return;
    setState(() => _mesgul = true);
    final yol = '/api/v1/orders/${s.id}';
    final pin = <String, dynamic>{};
    var guncelSurum = surum;
    var islenen = 0;
    dynamic son;
    try {
      for (final x in secim) {
        final k = x.kalem;
        final v = guncelSurum;
        son = await _yetkiliIstek((p) => _api.post('$yol/items/${k.id}/comp', {'reason': neden, 'expected_version': v, 'qty': x.adet, ...p}), pin);
        islenen++;
        final o = son is Map && son['order'] is Map ? son['order'] as Map : null;
        guncelSurum = o == null ? null : _versiyon(o.cast<String, dynamic>());
      }
      if (!mounted) return;
      _secim.temizle();
      _acikKalem.value = null;
      context.bildir2('İkram işlendi',
          secim.length == 1 ? '${secim.single.adet} × ${secim.single.kalem.ad} ücretsiz' : '${secim.length} kalem ücretsiz');
      // Seçim temizlenince tahsil tutarı kalan tutara döner.
      await _degisimSonrasi(yanit: son);
    } on ApiHata catch (e) {
      if (!mounted) return;
      _secim.temizle();
      _acikKalem.value = null;
      context.bildir2(
          'İkram edilemedi', islenen > 0 ? '${e.mesaj} ($islenen / ${secim.length} kalem ikram edildi; kalanlar işlenmedi.)' : e.mesaj,
          hata: true);
      await _degisimSonrasi();
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  Future<void> _ikramKaldir(Kalem k) {
    final surum = _surum;
    return _islem(() => _yetkiliIstek((p) => _api.delete('$_oyol/items/${k.id}/comp', {'expected_version': surum, ...p}), <String, dynamic>{}),
        ok: 'İkram kaldırıldı', okMetin: '${k.ad} yeniden ücretli', hataBaslik: 'İşlenemedi', yanittan: true);
  }

  /// İstek yetki reddiyle dönerse yetkili personelin PIN'i sorulur ve istek
  /// PIN'le BİR KEZ yinelenir (ödeme kaldırma / iade ile aynı personelPinSor).
  /// [pin] çağrılar arasında paylaşılır: toplu ikramda PIN bir kez sorulur.
  Future<dynamic> _yetkiliIstek(Future<dynamic> Function(Map<String, dynamic> pin) f, Map<String, dynamic> pin) async {
    try {
      return await f(pin);
    } on ApiHata catch (e) {
      if (pin.isNotEmpty || !personelYetkiReddi(e) || !mounted) rethrow;
      final p = await _penceredeyken(() => personelPinSor(context));
      if (p == null || !mounted) rethrow;
      pin.addAll(p);
      return await f(pin);
    }
  }

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
    final s = await _penceredeyken(() => urunSecimiAc(context, u, ilkNot: k.not));
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
    final u = await _penceredeyken(() => urunSecPenceresi(context, katalog, kanal: _secili?.kanal ?? 'table'));
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
    final s = _secili;
    if (s == null || !_indirimYetkisi) return;
    final d = _detay ?? Adisyon(s.ham);
    final degisti = await _penceredeyken(() => indirimPenceresi(context, d, manuel: _o.manuelIskonto));
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
    final ucretli = _gorunenKalemler.where(_secilebilir).toList();
    final secim = _seciliKalemler;
    if (secim.any((x) => x.adet < x.kalem.adet)) {
      context.bildir2('Kısmi adet borca yazılamaz', 'Borca yazmak için satırların tamamını seçin (ya da önce seçili adetlerin ödemesini alın).', hata: true);
      return;
    }
    final seciliUcretli = secim.map((x) => x.kalem).toList();
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
        _secim.temizle();
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

  /* ── indirim / iskonto (§4.6) — tek pencere, HAZIR varsayılan ── */

  Future<void> _indirimKaldir() => _islem(() => _api.delete('$_oyol/discount', {'expected_version': _surum}),
      ok: 'İndirim kaldırıldı', okMetin: 'Tutar yeniden hesaplandı.', hataBaslik: 'İndirim kaldırılamadı');

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

  // 1.2.34: kasada iade düğmesi yok (sağ Ödemeler sekmesi kalktı); yeri
  // işletme kararıyla belirlenecek, işlev hazır dursun.
  // ignore: unused_element
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
      // Ödeme bölmesi seçimden gelen tutarla kendi başına yenilenir.
      final odeme = _borclu != null
          ? _borcOdemeBolmesi(g)
          : RepaintBoundary(child: ListenableBuilder(listenable: _odemeTetik, builder: (_, _) => _odemeBolmesi(g)));
      if (genis) {
        // Masaüstü (1.2.34): sağ döküm genişliğin ~%34'ü (440–560 px; önce
        // %40 / 640) — tahsilat bölmesine daha çok yer. Tablet eski sabit genişlikte.
        final sag = _masaustu ? (g * .34).clamp(440.0, 560.0) : (g >= 1536 ? 440.0 : 380.0);
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
          if (_borclu == null && _secili != null && _kalan > 0) ListenableBuilder(listenable: _odemeTetik, builder: (_, _) => _mobilOdemeCubugu()),
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
      // Web kasayla aynı (1.2.34): gri kutuda toplam borç.
      if (liste.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
          child: Row(children: [
            Text('Toplam borç', style: TextStyle(fontSize: 13.5, color: Renk.ikinci)),
            const Spacer(),
            Text(para(toplam), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.hata, fontFeatures: const [FontFeature.tabularFigures()])),
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
    final adisyon = tamSayi(d['open_debt_orders_count']);
    // Web kasadaki şahıs kartının birebir düzeni (1.2.34): ortalı madalyon + ad
    // + rozet + "BORÇLU" · ortada turuncu borç etiketi · altta son ödeme ve telefon.
    return Material(
      color: Renk.markaAcik.carp(.3),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: Renk.marka.withValues(alpha: .45))),
      child: InkWell(
        key: ValueKey('borclu-${d['id']}'),
        onTap: () => _borcluSec(d),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
            child: Column(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Renk.marka, shape: BoxShape.circle),
                child: Text(harf, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              if (rozet != null) Padding(padding: const EdgeInsets.only(top: 3), child: rozet),
              const SizedBox(height: 2),
              Text('BORÇLU', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.ikinci, letterSpacing: .4)),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Rozet('Borç ${para(bakiye)}', renk: Renk.uyari, ikon: Icons.account_balance_wallet_outlined),
                ),
                if (adisyon > 0) ...[
                  const SizedBox(height: 5),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.receipt_long_outlined, size: 12, color: Renk.soluk),
                    const SizedBox(width: 3),
                    Text('$adisyon adisyon', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Renk.ikinci)),
                  ]),
                ],
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
            child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 3, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule_rounded, size: 12, color: Renk.soluk),
                const SizedBox(width: 3),
                Text(son == null ? 'ödeme yok' : '${_gunAy(son)} ${saatMetni(son)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Renk.ikinci)),
              ]),
              if (d['phone'] != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.phone_outlined, size: 12, color: Renk.soluk),
                  const SizedBox(width: 3),
                  Text('${d['phone']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Renk.ikinci)),
                ]),
            ]),
          ),
        ]),
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

  /* ── adisyon dökümü (sağ panel) — adisyon ekranı gibi hafif renkli ── */

  Widget _adisyonDokumu(bool genis) {
    final s = _secili!;
    final d = _detay;
    final h = d?.ham ?? s.ham;
    final bagli = s.bagliMasalar.length;
    final indirimVar = tamSayi(h['discount_minor']) > 0;
    final servisVar = tamSayi(h['service_charge_minor']) > 0;
    final urunAdedi = d?.aktifKalemler.fold<int>(0, (t, k) => t + k.adet);

    final sik = genis && _sikSag;
    Widget hucre(String baslik, String deger, {Color? renk, Color? zemin, bool son = false}) => Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: sik ? 3 : 6),
            decoration: BoxDecoration(color: zemin, border: son ? null : Border(right: BorderSide(color: Renk.cizgi))),
            child: Column(children: [
              Text(baslik.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
              const SizedBox(height: 1),
              FittedBox(fit: BoxFit.scaleDown, child: Text(deger, style: TextStyle(fontSize: sik ? 14 : 15, fontWeight: FontWeight.w700, color: renk ?? Renk.yazi))),
            ]),
          ),
        );

    final kunye = Container(
      padding: EdgeInsets.fromLTRB(12, sik ? 6 : 10, 12, sik ? 6 : 10),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: _baslik(s), style: TextStyle(fontSize: sik ? 16 : 19, fontWeight: FontWeight.w800)),
                TextSpan(text: '  #${s.id}', style: TextStyle(fontSize: 13, color: Renk.soluk, fontWeight: FontWeight.w700)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (bagli > 0) ...[_Etiket('${bagli + 1} masa', renk: Renk.marka, ikon: Icons.merge_rounded), const SizedBox(width: 6)],
          if (s.odenen > 0 && s.kalan > 0)
            _Etiket('Kısmi ödendi', renk: Renk.uyari, ikon: Icons.timelapse_rounded)
          else if (s.kalan == 0 && s.acik)
            _Etiket('Kapatılmadı', renk: Renk.uyari, ikon: Icons.info_outline_rounded)
          else if (s.kalan == 0)
            _Etiket('Ödendi', renk: Renk.basari, ikon: Icons.check_rounded)
          else if (s.hesapIstendi)
            _Etiket('Hesap istendi', renk: Renk.marka, ikon: Icons.receipt_long_outlined),
        ]),
        if (s.acan != null || s.servisTuruEtiket.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text([if (s.servisTuruEtiket.isNotEmpty) s.servisTuruEtiket, if (s.acan != null) s.acan!].join(' · '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Renk.ikinci)),
          ),
        SizedBox(height: sik ? 5 : 8),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              hucre('Açılış', saatMetni(s.ham['created_at']?.toString()).isEmpty ? '—' : saatMetni(s.ham['created_at']?.toString())),
              hucre('Süre', _sure(s.ham['created_at']?.toString()), renk: Renk.bilgi),
              hucre('Kişi', '${d?.kisi ?? s.kisi ?? '—'}'),
              hucre('Ürün', '${urunAdedi ?? s.kalemSayisi}', renk: Renk.marka, zemin: Renk.markaAcik.carp(.7), son: true),
            ]),
          ),
        ),
      ]),
    );

    // Araç çubuğu: adisyon ekranındaki gibi renkli kare düğmeler (8px köşe).
    final indirimToplam = tamSayi(h['discount_minor']) + tamSayi(h['iskonto_minor']);
    final indirimEtkin = _indirimYetkisi && _duzenlenebilir && !_mesgul;
    // Araç çubuğu (1.2.19): tek satır, eşit genişlikte kare düğmeler (simge
    // üstte, ad altta; 8px köşe). Hesap · İndirim · Ürün ekle yan yana; dar
    // ekranda ad küçülür, satır asla taşmaz.
    final araclarListesi = <_AracDugmesi>[
      if (d != null && (_kalemDuzenler || _ikramEder) && _duzenlenebilir)
        _AracDugmesi(
          sik: sik,
          key: const ValueKey('kasa-duzelt'),
          ikon: _duzelt ? Icons.check_rounded : Icons.edit_outlined,
          ad: _duzelt ? 'Bitir' : 'Düzelt',
          ipucu: _duzelt ? 'Düzenlemeyi bitir' : 'Kalemleri düzelt (adet, ikram, çıkar)',
          renk: _duzelt ? Renk.durumUstu : Renk.ikinci,
          zemin: _duzelt ? Renk.marka : Renk.ic,
          kenar: _duzelt ? Renk.marka : Renk.cizgi,
          bas: () {
            _secim.temizle();
            _acikKalem.value = null;
            setState(() => _duzelt = !_duzelt);
          },
        ),
      _AracDugmesi(
        sik: sik,
        key: const ValueKey('kasa-hesap'),
        ikon: Icons.print_outlined,
        ad: 'Hesap',
        ipucu: 'Hesap fişi yazdır',
        renk: Renk.bilgi,
        zemin: Renk.bilgiZemin,
        kenar: Renk.bilgiKenar,
        bas: () => _fisYazdir('bill'),
      ),
      // İNDİRİM: Hesap'ın hemen yanında; hazır indirim / manuel iskonto
      // penceresini açar. Uygulanmışsa düğme turuncu, tutar altta satırda.
      if (_indirimYetkisi || indirimToplam > 0)
        _AracDugmesi(
          sik: sik,
          key: const ValueKey('kasa-iskonto'),
          ikon: Icons.local_offer_outlined,
          ad: 'İndirim',
          ipucu: indirimToplam > 0
              ? 'Uygulanan: −${para(indirimToplam)}'
              : (_o.manuelIskonto ? 'Hazır indirim ya da manuel iskonto' : 'Hazır indirim uygula'),
          renk: indirimToplam > 0 ? Renk.uyari : Renk.ikinci,
          zemin: indirimToplam > 0 ? Renk.uyariZemin : Renk.ic,
          kenar: indirimToplam > 0 ? Renk.uyariKenar : Renk.cizgi,
          bas: indirimEtkin ? _indirimDiyalogu : null,
        ),
      // Adisyona ürün ekle: İndirim'in yanında (eskiden kalem listesinin altındaydı).
      if (d != null && _kalemDuzenler && _duzenlenebilir)
        _AracDugmesi(
          sik: sik,
          key: const ValueKey('kasa-urun-ekle'),
          ikon: Icons.add_shopping_cart_outlined,
          ad: 'Ürün ekle',
          ipucu: 'Adisyona ürün ekle',
          renk: Renk.marka,
          zemin: Renk.markaAcik,
          kenar: Renk.markaKenar,
          bas: _mesgul ? null : _urunEkle,
        ),
      if (s.odenen > 0)
        _AracDugmesi(
          sik: sik,
          key: const ValueKey('kasa-fis'),
          ikon: Icons.receipt_long_outlined,
          ad: 'Fiş',
          ipucu: 'Ödeme fişi yazdır',
          renk: Renk.basari,
          zemin: Renk.basariZemin,
          kenar: Renk.basariKenar,
          bas: () => _fisYazdir('payment'),
        ),
    ];
    // Masaüstü (1.2.22): eşit genişlikte, aynı boyda düğmeler (simge üstte,
    // kısa ad altta); dar panelde (<460 px) Fiş ⋮ menüsüne geçer, yazı kırpılmaz.
    final masaustuArac = genis && _masaustu;
    final araclar = masaustuArac
        ? LayoutBuilder(builder: (c0, k) {
            final fisMenude = k.maxWidth < 460 && araclarListesi.any((w) => w.key == const ValueKey('kasa-fis'));
            final l = [
              for (final w in araclarListesi)
                if (!(fisMenude && w.key == const ValueKey('kasa-fis'))) w.dikey(sik ? 46 : 54),
            ];
            return Container(
              key: const ValueKey('kasa-araclar'),
              padding: EdgeInsets.fromLTRB(12, sik ? 6 : 8, 12, sik ? 6 : 8),
              decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
              child: Row(children: [
                for (final (i, w) in l.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: w),
                ],
                const SizedBox(width: 6),
                SizedBox(
                  width: 44,
                  child: Builder(
                    builder: (c) => _AracDugmesi(
                      key: const ValueKey('kasa-diger'),
                      yukseklik: sik ? 46 : 54,
                      ikon: Icons.more_vert_rounded,
                      ipucu: 'Diğer işlemler',
                      renk: Renk.ikinci,
                      zemin: Renk.ic,
                      kenar: Renk.cizgi,
                      bas: () => _digerMenu(c, indirimVar: indirimVar, servisVar: servisVar, fis: fisMenude),
                    ),
                  ),
                ),
              ]),
            );
          })
        : Container(
      key: const ValueKey('kasa-araclar'),
      padding: EdgeInsets.fromLTRB(12, sik ? 5 : 8, 12, sik ? 5 : 8),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Row(children: [
        for (final (i, w) in araclarListesi.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          // Uzun adlı düğme ("Ürün ekle") biraz geniş: yazı küçülmeden sığar.
          Expanded(flex: (w.ad?.length ?? 0) >= 8 ? 5 : 4, child: w),
        ],
        const SizedBox(width: 6),
        SizedBox(
          width: 40,
          child: Builder(
            builder: (c) => _AracDugmesi(
              sik: sik,
              ikon: Icons.more_vert_rounded,
              ipucu: 'Diğer işlemler',
              renk: Renk.ikinci,
              zemin: Renk.ic,
              kenar: Renk.cizgi,
              bas: () => _digerMenu(c, indirimVar: indirimVar, servisVar: servisVar),
            ),
          ),
        ),
      ]),
    );

    // 1.2.34: "Ödemeler" sekmesi kaldırıldı — ödeme geçmişi sol bölümde.
    final sekmeler = Container(
      height: sik ? 36 : 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Row(children: [
        Icon(Icons.receipt_long_outlined, size: 18, color: Renk.ikinci),
        const SizedBox(width: 6),
        const Text('Kalemler', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(6)),
          child: Text('${_gorunenKalemler.length}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Renk.ikinci)),
        ),
      ]),
    );

    final icerik = _kalemlerSekmesi();

    final alt = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.kalan == 0)
        Container(
          color: Renk.basariZemin,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            Icon(Icons.check_circle_outline_rounded, color: Renk.basari, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  s.acik
                      ? 'Tahsil edilecek tutar yok — adisyonu ödeme bölmesinden kapatın.'
                      : (s.toplam == 0 && s.odenen == 0 ? 'Adisyon kapatıldı — tüm kalemler ikram.' : 'Adisyon tamamen ödendi — fiş verip kapatabilirsiniz.'),
                  style: TextStyle(color: Renk.basari, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ]),
        ),
      RepaintBoundary(
        child: ListenableBuilder(
          listenable: _odemeTetik,
          builder: (_, _) => _toplamSeridi(s),
        ),
      ),
    ]);

    return ColoredBox(
      color: Renk.ic,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: genis ? MainAxisSize.max : MainAxisSize.min, children: [
        kunye,
        araclar,
        _indirimSeridi(h),
        sekmeler,
        if (genis)
          Expanded(child: RepaintBoundary(child: icerik))
        else
          ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .5), child: RepaintBoundary(child: icerik)),
        alt,
      ]),
    );
  }

  /// Uygulanmış indirim / iskonto: yalnız varsa, araç çubuğunun altında
  /// ince satır(lar) — ad, tutar ve tek dokunuşla kaldır.
  Widget _indirimSeridi(Json h) {
    final indirim = tamSayi(h['discount_minor']);
    final iskonto = tamSayi(h['iskonto_minor']);
    if (indirim <= 0 && iskonto <= 0) return const SizedBox.shrink();
    final yuzde = h['discount_percent'];
    final etkin = _indirimYetkisi && _duzenlenebilir && !_mesgul;

    Widget kalem(Key key, IconData ikon, String ad, int tutar, VoidCallback kaldir) => SizedBox(
          key: key,
          height: 34,
          child: Row(children: [
            Icon(ikon, size: 15, color: Renk.uyari),
            const SizedBox(width: 8),
            Expanded(child: Text(ad, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
            Text('−${para(tutar)}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Renk.uyari)),
            if (etkin)
              Tooltip(
                message: 'Kaldır',
                child: InkWell(
                  borderRadius: koseYuvarlak,
                  onTap: kaldir,
                  child: SizedBox(width: 34, height: 34, child: Icon(Icons.close_rounded, size: 16, color: Renk.ikinci)),
                ),
              )
            else
              const SizedBox(width: 4),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (indirim > 0)
          kalem(const ValueKey('kasa-indirim-satiri'), Icons.local_offer_outlined,
              '${h['discount_reason'] ?? 'İndirim'}${yuzde != null ? ' (%${_oran(yuzde).substring(1)})' : ''}', indirim, _indirimKaldir),
        if (iskonto > 0)
          kalem(const ValueKey('kasa-iskonto-satiri'), Icons.percent_rounded, h['iskonto_reason']?.toString() ?? 'İskonto', iskonto, _iskontoKaldir),
      ]),
    );
  }

  /// Alt şerit: Seçilen · Ödenen · Kalan · Toplam (adisyon ekranındaki renkli hücreler).
  Widget _toplamSeridi(AdisyonOzet s) {
    final secimVar = !_secim.bos;
    final genis = MediaQuery.sizeOf(context).width >= 640;
    Widget hucre(IconData ikon, String baslik, String deger, Color renk, Color zemin, {bool son = false}) => Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(vertical: _sikSag ? 5 : 8),
            decoration: BoxDecoration(color: zemin.carp(.55), border: son ? null : Border(right: BorderSide(color: Renk.cizgi))),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ikon, size: 12, color: Renk.soluk),
                const SizedBox(width: 3),
                Text(baslik.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Renk.soluk, letterSpacing: .4)),
              ]),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text(deger, style: TextStyle(fontSize: genis ? 15 : 14, fontWeight: FontWeight.w700, color: renk))),
            ]),
          ),
        );
    final kalanVar = s.kalan > 0;
    return Container(
      decoration: BoxDecoration(color: Renk.yuzey, border: Border(top: BorderSide(color: Renk.cizgi))),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (kalanVar)
            hucre(secimVar ? Icons.check_box_outlined : Icons.edit_outlined, secimVar ? 'Seçilen' : 'Tahsil', para(secimVar ? _seciliToplam : _tutarMinor), Renk.marka,
                Renk.markaAcik),
          hucre(Icons.check_circle_outline_rounded, 'Ödenen', para(s.odenen), Renk.basari, Renk.basariZemin),
          hucre(Icons.account_balance_wallet_outlined, 'Kalan', para(s.kalan), kalanVar ? Renk.uyari : Renk.basari, kalanVar ? Renk.uyariZemin : Renk.basariZemin),
          hucre(Icons.receipt_outlined, 'Toplam', para(s.toplam), Renk.yazi, Renk.ic, son: true),
        ]),
      ),
    );
  }

  Future<void> _digerMenu(BuildContext c, {required bool indirimVar, required bool servisVar, bool fis = false}) async {
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
            if (fis && s.odenen > 0) oge('fis', Icons.receipt_long_outlined, 'Ödeme fişi yazdır'),
            oge('yazici', Icons.print_outlined, 'Fiş yazıcısı · ${_yaziciAdi ?? 'seçilmedi'}'),
            oge('onBill', Icons.preview_outlined, 'Hesap fişini önizle'),
            if (s.odenen > 0) oge('onPay', Icons.preview_outlined, 'Ödeme fişini önizle'),
            if (_indirimYetkisi) oge('indirim', Icons.sell_outlined, 'İndirim / iskonto', etkin: _duzenlenebilir),
            if (_kalemDuzenler) oge('servis', Icons.room_service_outlined, servisVar ? 'Servis bedeli kaldır' : 'Servis bedeli ekle'),
            if (s.kalan > 0 && s.durum == 'bill_requested' && _odemeYetkisi) oge('geri', Icons.arrow_back_rounded, 'Tekrar siparişe gönder', etkin: !_mesgul),
            if (s.kalan > 0) oge('borc', Icons.person_add_alt_outlined, 'Borca yaz (şahıs)'),
          ],
        ));
    switch (secim) {
      case 'fis':
        _fisYazdir('payment');
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
        padding: const EdgeInsets.all(16),
        child: Text('Kalem dökümünü görme yetkiniz yok; alttaki tutar özeti üzerinden tahsilat yapabilirsiniz.', style: TextStyle(color: Renk.ikinci)),
      );
    }
    if (d == null) return Center(child: Text('Kalemler yükleniyor…', style: TextStyle(color: Renk.ikinci)));
    final kalemler = _gorunenKalemler;
    final h = d.ham;

    // Satırlar ListView.builder ile — yalnız görünenler kurulur.
    final ogeler = <Widget Function()>[];
    if (!_duzelt && kalemler.isNotEmpty && s.kalan > 0) {
      ogeler.add(() => RepaintBoundary(child: ListenableBuilder(listenable: _secim, builder: (_, _) => _secimSeridi())));
    }
    Widget satir(Kalem k) => ListenableBuilder(listenable: _satirDinle, builder: (_, _) => _kalemSatiri(k));
    if (kalemler.isEmpty) {
      ogeler.add(() => _bos(Icons.receipt_long_outlined, 'Kalem yok', ''));
    } else if (h['aktif_parti'] != null) {
      final aktif = tamSayi(h['aktif_parti'], 1);
      final adlar = h['parti_adlari'] is Map ? h['parti_adlari'] as Map : const {};
      final gruplar = <int, List<Kalem>>{};
      for (final k in kalemler) {
        (gruplar[k.ham['parti_no'] == null ? aktif : tamSayi(k.ham['parti_no'])] ??= []).add(k);
      }
      for (final no in gruplar.keys.toList()..sort()) {
        ogeler.add(() => _partiBasligi(no, gruplar[no]!, no == aktif, adlar['$no']?.toString()));
        for (final k in gruplar[no]!) {
          ogeler.add(() => satir(k));
        }
      }
    } else {
      for (final k in kalemler) {
        ogeler.add(() => satir(k));
      }
    }

    if (_duzelt) {
      ogeler.add(() => Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text('Değişiklikler anında adisyona ve kalan tutara işler. Bittiğinde “Bitir”e basın.', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ));
    }
    ogeler.add(() => _tutarDokumu(h, kalemler));
    return ListView.builder(padding: EdgeInsets.zero, itemCount: ogeler.length, itemBuilder: (_, i) => ogeler[i]());
  }

  /// Seçim özeti: "3 adet seçili · 2 üründen · 75,00 ₺" + Temizle / Tutara yaz.
  Widget _secimSeridi() {
    if (_secim.bos) {
      final sik = _sikSag;
      return Container(
        padding: EdgeInsets.fromLTRB(12, sik ? 5 : 9, 12, sik ? 5 : 9),
        decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
        child: Row(children: [
          Icon(Icons.touch_app_outlined, size: 16, color: Renk.ikinci),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                sik
                    ? 'Kişi kendi payını ödeyecekse kalemlere dokunun.'
                    : 'Kişi kendi payını ödeyecekse kalemlere dokunun; adedi birden fazla olanlar açılır, istediğiniz kadarını seçin.',
                maxLines: sik ? 1 : null,
                overflow: sik ? TextOverflow.ellipsis : null,
                style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ),
        ]),
      );
    }
    final secim = _seciliKalemler;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: BoxDecoration(color: Renk.markaAcik, border: Border(bottom: BorderSide(color: Renk.markaKenar))),
      child: Row(children: [
        Icon(Icons.check_box_rounded, size: 18, color: Renk.marka),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '$_seciliAdet adet', style: const TextStyle(fontWeight: FontWeight.w700)),
              if (secim.length > 1) TextSpan(text: ' · ${secim.length} üründen'),
              const TextSpan(text: ' · '),
              TextSpan(text: para(_seciliToplam), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13.5, color: Renk.marka),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 10)),
          onPressed: () {
            _secim.temizle();
            _acikKalem.value = null;
          },
          child: const Text('Temizle'),
        ),
        if (_ikramGorunur && (_detay?.acik ?? false))
          TextButton.icon(
            key: const ValueKey('kasa-secim-ikram'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 10), foregroundColor: Renk.bilgi),
            onPressed: secim.isNotEmpty && !_mesgul ? _seciliIkram : null,
            icon: const Icon(Icons.card_giftcard_rounded, size: 16),
            label: Text(secim.length > 1 ? 'İkram et (${secim.length})' : 'İkram et'),
          ),
        const SizedBox(width: 2),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
          onPressed: _seciminiYaz,
          child: const Text('Tutara yaz'),
        ),
      ]),
    );
  }

  Widget _partiBasligi(int no, List<Kalem> ks, bool acik, String? ad) {
    final odenmemis = ks.where(_secilebilir).toList();
    final tamOdendi = odenmemis.isEmpty;
    final kalan = odenmemis.fold<int>(0, (t, k) => t + k.tutar);
    return Tooltip(
      message: tamOdendi ? 'Bu parti ödendi' : '$no. parti${ad != null ? ' · $ad' : ''} — tahsil için seç',
      child: InkWell(
        onTap: tamOdendi || _duzelt ? null : () => _secim.hepsiniSec(odenmemis),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tamOdendi ? Renk.basariZemin.carp(.6) : (acik ? Renk.markaAcik.carp(.7) : Renk.yuzey),
            border: Border(bottom: BorderSide(color: Renk.cizgi)),
          ),
          child: Row(children: [
            Icon(Icons.layers_outlined, size: 16, color: acik ? Renk.marka : Renk.ikinci),
            const SizedBox(width: 6),
            Text('$no. parti', style: TextStyle(fontWeight: FontWeight.w700, color: acik ? Renk.marka : Renk.yazi)),
            if (ad != null) ...[
              const SizedBox(width: 6),
              Flexible(child: _Etiket(ad, renk: Renk.marka)),
            ],
            const SizedBox(width: 6),
            if (acik)
              _Etiket('Sürüyor', renk: Renk.marka)
            else if (tamOdendi)
              _Etiket('Ödendi', renk: Renk.basari, ikon: Icons.check_rounded),
            const Spacer(),
            if (!tamOdendi && !_duzelt) Padding(padding: const EdgeInsets.only(right: 6), child: Text('tümünü seç', style: TextStyle(fontSize: 11.5, color: Renk.ikinci))),
            Text(para(kalan), style: TextStyle(fontWeight: FontWeight.w700, color: tamOdendi ? Renk.basari : null)),
          ]),
        ),
      ),
    );
  }

  Widget _kalemSatiri(Kalem k) {
    final sikSatir = _sikSag;
    final secilebilir = _secilebilir(k) && !_duzelt;
    final secAdet = secilebilir ? _secim.adet(k.id).clamp(0, k.odenmemisAdet) : 0;
    final tam = secAdet > 0 && secAdet >= k.odenmemisAdet;
    final kismi = secAdet > 0 && !tam;
    final cokAdet = k.adet > 1 && secilebilir;
    final acik = cokAdet && _acikKalem.value == k.id;
    final soluk = k.odendi;
    final meta = [
      if (k.varyant != null) k.varyant!,
      ...k.secenekler,
    ];
    final oran = (k.ham['tax_rate'] is num) ? (k.ham['tax_rate'] as num).toDouble() : double.tryParse('${k.ham['tax_rate']}') ?? 0;
    // Ödenmiş satır düzeltilemez (adet / değiştir / çıkar / ikram yok).
    final duzenle = _duzelt && _duzenlenebilir && !k.odendi;

    // Sol kutu: ödendi ✓ · ikram 🎁 · seçim (boş / kısmi − / tam ✓).
    final Widget kutu;
    if (k.odendi) {
      kutu = Tooltip(message: 'Ödendi', child: SizedBox(width: 32, child: Icon(Icons.check_circle_rounded, size: 22, color: Renk.basari)));
    } else if (k.ikram) {
      kutu = Tooltip(message: 'İkram', child: SizedBox(width: 32, child: Icon(Icons.card_giftcard_rounded, size: 20, color: Renk.bilgi)));
    } else if (secilebilir) {
      kutu = Tooltip(
        message: tam ? 'Seçimi kaldır' : 'Tamamını seç (${k.odenmemisAdet} adet)',
        child: InkWell(
          key: ValueKey('kasa-kutu-${k.id}'),
          borderRadius: koseYuvarlak,
          onTap: () => _kalemKutusu(k),
          child: SizedBox(
            width: 32,
            height: 40,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: secAdet > 0 ? Renk.marka : Renk.yuzey,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: secAdet > 0 ? Renk.marka : Renk.cizgiKoyu, width: 1.5),
                ),
                child: secAdet > 0 ? Icon(kismi ? Icons.remove_rounded : Icons.check_rounded, size: 16, color: Renk.durumUstu) : null,
              ),
            ),
          ),
        ),
      );
    } else {
      kutu = const SizedBox(width: 32);
    }

    // Adet rozeti: seçim kısmiyse "2/4".
    final rozet = Container(
      constraints: const BoxConstraints(minWidth: 34),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: secAdet > 0 ? Renk.markaAcik : Renk.yuzey,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: secAdet > 0 ? Renk.markaKenar : Renk.cizgi),
      ),
      child: Text('${k.adet}×',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: secAdet > 0 ? Renk.marka : (soluk ? Renk.soluk : Renk.yazi))),
    );

    final ust = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      kutu,
      const SizedBox(width: 6),
      rozet,
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UrunAdi(k.ad,
              maxLines: sikSatir ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: sikSatir ? 14 : 15,
                fontWeight: FontWeight.w600,
                decoration: soluk ? TextDecoration.lineThrough : null,
                decorationColor: Renk.soluk,
                color: soluk ? Renk.soluk : Renk.yazi,
              )),
          if (meta.isNotEmpty) Text(meta.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          if (k.not != null && k.not!.trim().isNotEmpty) KalemNotu(k.not!),
          if (secilebilir && k.odenmemisAdet < k.adet)
            Text('${k.adet - k.odenmemisAdet} adet ödendi${secAdet > 0 ? ' · $secAdet seçili' : ''}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secAdet > 0 ? Renk.marka : Renk.basari))
          else if (kismi)
            Text('$secAdet / ${k.adet} adet seçili', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.marka))
          else if (k.odendi)
            Text('Ödendi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.basari))
          else if (k.ikram)
            Row(children: [
              Flexible(
                child: Text('İkram${k.ikramNedeni != null && k.ikramNedeni!.isNotEmpty ? ' · ${k.ikramNedeni}' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Renk.bilgi)),
              ),
              // Düzelt kipinde alt çubukta zaten var; burada sade küçük düğme.
              if (!_duzelt && _ikramGorunur && (_detay?.acik ?? false)) ...[
                const SizedBox(width: 6),
                TextButton(
                  key: ValueKey('kasa-ikram-kaldir-${k.id}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _mesgul ? null : () => _ikramKaldir(k),
                  child: const Text('İkramı kaldır'),
                ),
              ],
            ])
          else if (oran > 0)
            Text('KDV ${_oran(oran)} dahil', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
        ]),
      ),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(para(k.ikram ? k.birimFiyat * k.adet : k.tutar),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              decoration: k.ikram || soluk ? TextDecoration.lineThrough : null,
              decorationColor: Renk.soluk,
              color: k.ikram || soluk ? Renk.soluk : Renk.yazi,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        if (k.adet > 1 || k.ikram)
          Text('${para(k.birimFiyat)} / adet', style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
      ]),
      if (cokAdet)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: AnimatedRotation(
            turns: acik ? .5 : 0,
            duration: const Duration(milliseconds: 150),
            child: Icon(Icons.expand_more_rounded, size: 20, color: acik ? Renk.marka : Renk.soluk),
          ),
        ),
    ]);

    return Material(
      color: secAdet > 0 ? Renk.markaAcik.carp(.55) : (soluk ? Renk.ic : (_yeniKalemler.contains(k.id) ? Renk.markaAcik.carp(.35) : Renk.yuzey)),
      child: InkWell(
        onTap: secilebilir ? () => _kalemDokun(k) : null,
        child: Container(
          padding: EdgeInsets.fromLTRB(8, sikSatir ? 2 : 6, 12, sikSatir ? 2 : 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: secAdet > 0 ? Renk.marka : Colors.transparent, width: 3),
              bottom: BorderSide(color: Renk.cizgi),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ConstrainedBox(constraints: BoxConstraints(minHeight: sikSatir ? 36 : 44), child: ust),
            if (acik) _birimKartlari(k),
            if (duzenle) _duzeltCubugu(k),
          ]),
        ),
      ),
    );
  }

  /// Çok adetli satır açılınca: her adet ayrı kart — kutu · saat · ürün ·
  /// siparişi giren · birim fiyat (web sipariş detayındaki parça dökümü).
  /// Ödenmiş adetler "Ödendi" görünür, seçilemez.
  Widget _birimKartlari(Kalem k) => AdetKartlari(
        kalem: k,
        secili: _secim.birimler(k.id),
        odenmis: k.adet - k.odenmemisAdet,
        degistir: (i) => _secim.birimDegistir(k, i),
        sik: _sikSag,
        anahtar: 'kasa-birim',
      );

  Widget _duzeltCubugu(Kalem k) => Container(
        margin: const EdgeInsets.only(top: 6, left: 38),
        padding: const EdgeInsets.only(top: 6),
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
          if (_ikramEder && !k.ikram && !k.odendi)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Renk.bilgi),
              onPressed: _mesgul ? null : () => _ikram(k),
              icon: const Icon(Icons.card_giftcard_rounded, size: 15),
              label: const Text('İkram yap'),
            ),
          if (_kalemDuzenler && !k.ikram)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Renk.hata),
              onPressed: _mesgul ? null : () => _cikar(k),
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: const Text('Çıkar'),
            ),
          if (k.ikram && _ikramEder)
            TextButton.icon(onPressed: _mesgul ? null : () => _ikramKaldir(k), icon: const Icon(Icons.undo_rounded, size: 15), label: const Text('İkramı kaldır')),
        ]),
      );

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

  /* ── §1.5 ödeme bölmesi (adisyon) ── */

  Widget _odemeBolmesi(double g) {
    if (g >= 1024 && _masaustu) {
      return LayoutBuilder(builder: (_, k) => _odemeBolmesiIc(g, k.maxHeight.isFinite ? k.maxHeight : null));
    }
    return _odemeBolmesiIc(g, null);
  }

  /// [h]: masaüstünde bölmenin yüksekliği (null = tablet / telefon, eski düzen).
  Widget _odemeBolmesiIc(double g, double? h) {
    final s = _secili!;
    final genis = g >= 1024;
    // Masaüstü (1.2.22): tuş takımı ile ödeme yöntemleri yan yana, boyları
    // pencereye göre; tahsil düğmesi altta sabit. Kısa pencerede sık.
    final sik = h != null && h < 700;
    _sikSol = sik;
    _masaustuSol = h != null;
    _tusYuksekligi = 54;
    final ara = sik ? 6.0 : 10.0;
    if (s.kalan == 0) {
      // Kalan 0 ama adisyon AÇIK (ör. tüm kalemler ikram): kapatılmadıkça
      // masa dolu kalır — "Adisyonu kapat (0 ₺)" sunucuda kapatır.
      final acikKaldi = s.acik;
      final hepsiIkram = s.toplam == 0 && s.odenen == 0;
      final (String baslikMetni, String aciklama) = acikKaldi
          ? (
              'Tahsil edilecek tutar yok',
              s.odenen > 0
                  ? 'Toplam ${para(s.toplam)} tahsil edildi; adisyon henüz kapanmadı. Kapatınca masa boşalır.'
                  : 'Tüm kalemler ikram edildi; adisyon henüz kapanmadı. Kapatınca masa boşalır.',
            )
          : hepsiIkram
              ? ('Adisyon kapatıldı', 'Tüm kalemler ikram — tahsilat yapılmadı.')
              : ('Adisyon tamamen ödendi', 'Toplam ${para(s.toplam)} tahsil edildi.');
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const SizedBox(height: 24),
          Icon(acikKaldi ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded, size: 56, color: acikKaldi ? Renk.marka : Renk.basari),
          const SizedBox(height: 10),
          Text(baslikMetni, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(aciklama, textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            if (s.odenen > 0)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () => _fisYazdir('payment'),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Ödeme fişi yazdır'),
              ),
            if (acikKaldi && _odemeYetkisi) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _secimeDon,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Masalara dön'),
              ),
              FilledButton.icon(
                key: const ValueKey('kasa-sifir-kapat'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _odeniyor ? null : _sifirKapat,
                icon: _odeniyor
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Adisyonu kapat (0 ₺)'),
              ),
            ] else
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
      if (g >= 640)
        TextButton.icon(onPressed: _secimeDon, icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Masalar'))
      else
        IconButton(tooltip: 'Masalar', onPressed: _secimeDon, icon: const Icon(Icons.arrow_back_rounded, size: 20)),
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
    if (genis && h != null) return _masaustuSolBolme(baslik: baslik, tutarKutusu: tutarKutusu, verilenKutusu: verilenKutusu, presetler: presetler, nakit: nakit);

    final ogeler = <Widget>[
      baslik,
      SizedBox(height: ara),
      if (nakit && g >= 640)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: tutarKutusu), const SizedBox(width: 10), Expanded(child: verilenKutusu)])
      else ...[
        tutarKutusu,
        if (nakit) ...[const SizedBox(height: 8), verilenKutusu],
      ],
      if (nakit) ...[
        SizedBox(height: sik ? 4 : 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final p in presetler)
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: Size(0, sik ? 30 : 34)),
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
      SizedBox(height: ara),
      if (g >= 768) ...[
        _numpad(borc: false),
        if (!sik) const SizedBox(height: 6),
        if (!sik)
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
          OutlinedButton(onPressed: () => _hizliTutar(1 / 2), child: const Text('1/2')),
          OutlinedButton(onPressed: () => _hizliTutar(1 / 3), child: const Text('1/3')),
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
      // Tablet / telefon: ödeme geçmişi (1.2.34; sağ "Ödemeler" sekmesi kalktı).
      if (_odemeler.isNotEmpty) ...[
        SizedBox(height: sik ? 6 : 12),
        SizedBox(height: (70.0 + _odemeler.length * 62).clamp(132.0, 260.0), child: _odemeGecmisi()),
      ],
      SizedBox(height: sik ? 8 : 14),
      _bolumBasligi(Icons.wallet_outlined, 'Ödeme yöntemi', sag: _yontem == null ? Text('seçilmedi', style: TextStyle(fontSize: 12, color: Renk.uyari, fontWeight: FontWeight.w600)) : null),
      SizedBox(height: sik ? 6 : 8),
      _yontemIzgarasi(),
      if (_terminalYontemi) ...[SizedBox(height: sik ? 6 : 8), _posKutusu()],
      // Masaüstünde ödeme düğmesi aşağıda SABİT (aşağıda); tablette akışta.
      if (genis && h == null) ...[const SizedBox(height: 10), _odemeDugmesi(yukseklik: 56, buyuk: true)],
    ];

    final icerik = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: ogeler);
    return genis ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: icerik) : Padding(padding: const EdgeInsets.all(12), child: icerik);
  }

  /// Masaüstü sol bölme: üstte başlık + tutar kutuları; ortada tuş takımı
  /// (≈%55) ile ödeme yöntemleri (≈%45) yan yana, pencere boyuna göre
  /// büyür / küçülür; en altta tahsil düğmesi HER ZAMAN görünür.
  Widget _masaustuSolBolme({
    required Widget baslik,
    required Widget tutarKutusu,
    required Widget verilenKutusu,
    required List<int> presetler,
    required bool nakit,
  }) {
    final sik = _sikSol;
    final ara = sik ? 8.0 : 12.0;
    // 1.2.32: tuş takımının yanında ödeme geçmişi (parçalı ödemeler bir
    // bakışta); ödeme yöntemleri aşağıda yan yana (web kasayla aynı düzen).
    final orta = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(flex: 55, child: _numpad(borc: false, doldur: true)),
      const SizedBox(width: 14),
      Expanded(flex: 45, child: _odemeGecmisi()),
    ]);
    return Padding(
      key: const ValueKey('kasa-masaustu-sol'),
      padding: EdgeInsets.fromLTRB(16, sik ? 8 : 14, 16, sik ? 10 : 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        baslik,
        SizedBox(height: sik ? 6 : 10),
        if (nakit)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: tutarKutusu), const SizedBox(width: 10), Expanded(child: verilenKutusu)])
        else
          tutarKutusu,
        if (nakit) ...[
          SizedBox(height: sik ? 4 : 8),
          SizedBox(
            height: sik ? 30 : 34,
            child: Row(children: [
              for (final p in presetler) ...[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: Size(0, sik ? 30 : 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: () => setState(() {
                    _verilen = paraGirdisi(p);
                    _hedef = 'tendered';
                  }),
                  child: Text(para(p)),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Checkbox(value: _yuvarla, visualDensity: VisualDensity.compact, onChanged: (v) => setState(() => _yuvarla = v ?? false)),
              Text('Kalanı ${tamSayi(25)} kuruşa yuvarla', style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
        ],
        SizedBox(height: ara),
        // Orta bölüm boşluğu doldurur; çok uzun pencerede tuşlar dev olmasın
        // diye en çok 520 px (kalan boşluk üst-alt eşit dağılır).
        Expanded(
          child: LayoutBuilder(
            builder: (_, k) => Center(child: SizedBox(height: k.maxHeight.clamp(0.0, 520.0), child: orta)),
          ),
        ),
        SizedBox(height: ara),
        _yontemSirasi(),
        if (_terminalYontemi) ...[SizedBox(height: ara), _posKutusu()],
        if (_bahsisAcik) ...[
          SizedBox(height: ara),
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
        SizedBox(height: ara),
        _odemeDugmesi(yukseklik: sik ? 50 : 58, buyuk: true),
      ]),
    );
  }

  /// Tek ödeme yöntemi düğmesi: çerçeveli, renkli simge kutusu + ad;
  /// seçili olan yöntem renginde. Boyu bulunduğu kutuya göre ayarlanır.
  Widget _yontemDugmesi((String, String, String, bool) y) {
    final secili = _yontem == y.$1;
    final t = yontemTonu(y.$1);
    return Material(
      color: secili ? t.zemin : Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? t.kenar : Renk.cizgiKoyu, width: secili ? 2 : 1)),
      child: InkWell(
        key: ValueKey('kasa-yontem-${y.$1}'),
        customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
        onTap: () => setState(() => _yontem = y.$1),
        child: LayoutBuilder(builder: (_, k) {
          // Uzun pencerede düğme büyür: simge ve yazı da büyür.
          final iri = k.maxHeight >= 84;
          // Çok kısa pencerede (ör. %125 ölçekli 1366×768): ince, tek satır.
          final ince = k.maxHeight < 46;
          final ad = Text(y.$2,
              maxLines: ince ? 1 : 2,
              overflow: ince ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(fontSize: iri ? 16 : (ince ? 13 : 14), height: 1.15, fontWeight: FontWeight.w600, color: secili ? t.yazi : Renk.yazi));
          final kutu = iri ? 44.0 : (ince ? 26.0 : 34.0);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: iri ? 14 : (ince ? 6 : 10)),
            child: Row(children: [
              Container(
                width: kutu,
                height: kutu,
                decoration: BoxDecoration(color: secili ? Renk.yuzey : t.zemin, borderRadius: koseYuvarlak),
                child: Icon(yontemSimgesi(y.$1, y.$3), size: iri ? 24 : (ince ? 16 : 20), color: t.ikon),
              ),
              SizedBox(width: iri ? 12 : (ince ? 6 : 10)),
              Expanded(child: ince ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: ad) : ad),
              if (secili) Icon(Icons.check_circle_rounded, size: iri ? 20 : (ince ? 16 : 18), color: t.yazi),
            ]),
          );
        }),
      ),
    );
  }

  /// Kısa pencere için dar yöntem düğmesi: simge üstte, ad altta.
  Widget _yontemDugmesiDikey((String, String, String, bool) y) {
    final secili = _yontem == y.$1;
    final t = yontemTonu(y.$1);
    return Material(
      color: secili ? t.zemin : Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? t.kenar : Renk.cizgiKoyu, width: secili ? 2 : 1)),
      child: InkWell(
        key: ValueKey('kasa-yontem-${y.$1}'),
        customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
        onTap: () => setState(() => _yontem = y.$1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(yontemSimgesi(y.$1, y.$3), size: 18, color: t.ikon),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(y.$2, maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: secili ? t.yazi : Renk.yazi)),
            ),
          ]),
        ),
      ),
    );
  }

  /// Masaüstü ödeme yöntemleri (1.2.32): tuş takımının ALTINDA yan yana;
  /// yalnız işletmede açık olanlar. 4'e kadar tek sıra, fazlası iki sıra.
  Widget _yontemSirasi() {
    final l = kasadaGorunenYontemler;
    if (l.isEmpty) return const SizedBox.shrink();
    // Kısa pencerede (sık düzen) tek sıra: simge üstte, ad altta — tuş
    // takımına yer kalsın.
    final tekSira = _sikSol;
    final sutun = tekSira || l.length <= 4 ? l.length : (l.length / 2).ceil();
    final satir = (l.length / sutun).ceil();
    final boy = tekSira ? 50.0 : 54.0;
    return Column(key: const ValueKey('kasa-yontemler'), children: [
      for (var r = 0; r < satir; r++)
        SizedBox(
          height: boy,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var c = 0; c < sutun; c++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: r * sutun + c >= l.length
                      ? const SizedBox.shrink()
                      : (tekSira ? _yontemDugmesiDikey(l[r * sutun + c]) : _yontemDugmesi(l[r * sutun + c])),
                ),
              ),
          ]),
        ),
    ]);
  }

  /// ÖDEME GEÇMİŞİ (1.2.32): tuş takımının yanında, sağdaki "Ödemeler"
  /// sekmesinin içeriği. Boşsa "Ödeme yok". İşlemler (1.2.33) satırın 3 nokta
  /// menüsünde: sorgula, yöntem değiştir, iptal. İade burada YOK (Ödemeler sekmesi).
  Widget _odemeGecmisi() {
    final basarili = _odemeler.where((p) => p['kind'] == 'payment' && p['status'] == 'succeeded').toList();
    final toplam = basarili.fold<int>(0, (t, p) => t + tamSayi(p['amount_minor']));
    PopupMenuItem<VoidCallback> oge(IconData ikon, String ad, VoidCallback bas, {bool tehlike = false}) => PopupMenuItem<VoidCallback>(
          value: bas,
          height: 40,
          child: Row(children: [
            Icon(ikon, size: 18, color: tehlike ? Renk.hata : Renk.ikinci),
            const SizedBox(width: 10),
            Text(ad, style: TextStyle(fontSize: 14, color: tehlike ? Renk.hata : Renk.yazi)),
          ]),
        );
    return Container(
      key: const ValueKey('kasa-odeme-gecmisi'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.cizgi))),
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, size: 16, color: Renk.ikinci),
            const SizedBox(width: 6),
            const Text('Ödeme geçmişi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (basarili.isNotEmpty) Text('${basarili.length} ödeme · ${para(toplam)}', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ]),
        ),
        Expanded(
          child: _odemeler.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.account_balance_wallet_outlined, size: 24, color: Renk.soluk),
                    const SizedBox(height: 6),
                    Text('Ödeme yok', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Renk.soluk)),
                  ]),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _odemeler.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = _odemeler[i];
                    final iadeMi = p['kind'] == 'refund';
                    final durum = '${p['status'] ?? ''}';
                    final tutar = tamSayi(p['amount_minor']);
                    final iadeToplam = tamSayi(p['refunded_total_minor']);
                    final renk = switch ('${p['status_variant']}') {
                      'success' => Renk.basari,
                      'warning' => Renk.uyari,
                      'danger' => Renk.hata,
                      'info' => Renk.bilgi,
                      _ => Renk.ikinci,
                    };
                    final yontemDegisir = !iadeMi && durum == 'succeeded' && iadeToplam == 0 &&
                        const ['cash', 'card_present', 'mock', 'demo', null].contains(p['provider']);
                    final menu = <PopupMenuItem<VoidCallback>>[
                      if (durum == 'pending' && _odemeYetkisi) oge(Icons.sync_rounded, 'Durumu sorgula', () => _sorgula(p)),
                      if (_iadeYetkisi && !iadeMi && yontemDegisir) oge(Icons.swap_horiz_rounded, 'Yöntemi değiştir', () => _yontemDegistir(p)),
                      if (_iadeYetkisi && !iadeMi && durum == 'succeeded' && iadeToplam == 0)
                        oge(Icons.delete_outline_rounded, 'Ödemeyi iptal et', () => _void(p), tehlike: true),
                    ];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Icon(yontemSimgesi(p['method']?.toString(), p['method_icon']?.toString()), size: 16, color: Renk.ikinci),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text('${iadeMi ? 'İade — ' : ''}${p['method_label'] ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Text('${iadeMi ? '−' : ''}${para(tutar)}',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                          if (menu.isEmpty)
                            const SizedBox(width: 30)
                          else
                            SizedBox(
                              width: 30,
                              height: 26,
                              child: PopupMenuButton<VoidCallback>(
                                key: ValueKey('odeme-menu-${p['id']}'),
                                tooltip: 'Ödeme işlemleri',
                                padding: EdgeInsets.zero,
                                enabled: !_mesgul,
                                icon: Icon(Icons.more_vert_rounded, size: 18, color: Renk.ikinci),
                                shape: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                                onSelected: (f) => f(),
                                itemBuilder: (_) => menu,
                              ),
                            ),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: [
                          const SizedBox(width: 23),
                          Icon(Icons.schedule_rounded, size: 12, color: Renk.soluk),
                          const SizedBox(width: 2),
                          Text(saatMetni(p['created_at']?.toString()), style: TextStyle(fontSize: 11.5, color: Renk.soluk)),
                          const SizedBox(width: 6),
                          Rozet('${p['status_label'] ?? durum}', renk: renk),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              [
                                if (p['cashier'] != null) '${p['cashier']}',
                                if (tamSayi(p['tip_minor']) > 0) '+${para(tamSayi(p['tip_minor']))} bahşiş',
                                if (p['reason'] != null) '${p['reason']}',
                                if (p['suspect'] == true) '⚠ ${p['suspect_reason'] ?? ''}',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: p['suspect'] == true ? Renk.hata : Renk.ikinci),
                            ),
                          ),
                        ]),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _bolumBasligi(IconData ikon, String ad, {Widget? sag}) => Row(children: [
        Icon(ikon, size: 16, color: Renk.ikinci),
        const SizedBox(width: 6),
        Text(ad.toUpperCase(), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Renk.ikinci, letterSpacing: .5)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: Renk.cizgi)),
        if (sag != null) ...[const SizedBox(width: 8), sag],
      ]);

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
        padding: EdgeInsets.fromLTRB(12, _sikSol ? 5 : 8, 12, _sikSol ? 5 : 8),
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
            height: _sikSol ? 32 : 40,
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

  Widget _numpad({required bool borc, bool doldur = false}) {
    // Masaüstü: tuşlar bölmenin boyunu doldurur, yazı sığmazsa küçülür.
    Widget dolanTus(String etiket, VoidCallback bas, {bool hizli = false, bool sil = false, String? ipucu}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Tooltip(
              message: ipucu ?? '',
              child: Material(
                color: hizli ? Renk.markaAcik : Renk.ic,
                shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: hizli ? Renk.markaKenar : Renk.cizgi)),
                child: InkWell(
                  borderRadius: koseYuvarlak,
                  onTap: bas,
                  child: LayoutBuilder(
                    // Uzun pencerede tuş büyür, yazı da (orantılı) büyür.
                    builder: (_, k) => Padding(
                      padding: const EdgeInsets.all(4),
                      child: Center(child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(etiket,
                            style: TextStyle(
                              fontSize: (hizli || sil ? .66 : 1) * (k.maxHeight * .30).clamp(20.0, 30.0),
                              fontWeight: FontWeight.w600,
                              color: sil ? Renk.hata : (hizli ? Renk.marka : Renk.yazi),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            )),
                      )),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget tus(String etiket, VoidCallback bas, {bool hizli = false, bool sil = false, String? ipucu}) => doldur
        ? dolanTus(etiket, bas, hizli: hizli, sil: sil, ipucu: ipucu)
        : Expanded(
          child: Padding(
            padding: EdgeInsets.all(_sikSol ? 2 : 3),
            child: Tooltip(
              message: ipucu ?? '',
              child: Material(
                color: hizli ? Renk.markaAcik : Renk.ic,
                shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: hizli ? Renk.markaKenar : Renk.cizgi)),
                child: InkWell(
                  borderRadius: koseYuvarlak,
                  onTap: bas,
                  child: SizedBox(
                    height: _tusYuksekligi,
                    child: Center(
                      child: Text(etiket,
                          style: TextStyle(
                            fontSize: (hizli ? 17 : (sil ? 18 : 24)) * (_tusYuksekligi < 48 ? .88 : 1),
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
    final satirlar = [
      Row(children: [tus('1', () => rakam('1')), tus('2', () => rakam('2')), tus('3', () => rakam('3')), tus('Tamamı', hizli1, hizli: true)]),
      Row(children: [tus('4', () => rakam('4')), tus('5', () => rakam('5')), tus('6', () => rakam('6')), tus('1/2', hizli2, hizli: true)]),
      Row(children: [tus('7', () => rakam('7')), tus('8', () => rakam('8')), tus('9', () => rakam('9')), tus('1/3', hizli3, hizli: true)]),
      Row(children: [
        tus('Sil', () => rakam('del'), sil: true),
        tus('0', () => rakam('0')),
        tus(',', () => rakam(',')),
        borc ? tus('Temizle', _borcTemizle, hizli: true, ipucu: 'Seçili kutuyu temizle') : tus('1/n', _bolPenceresi, hizli: true, ipucu: 'Kalanı n kişiye böl'),
      ]),
    ];
    if (doldur) {
      return Column(children: [
        for (final r in satirlar) Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: r.children)),
      ]);
    }
    return Column(children: satirlar);
  }

  Widget _yontemIzgarasi() {
    final g = MediaQuery.sizeOf(context).width;
    final sutun = g >= 768 ? 4 : 2;
    if (_sikSol) {
      // Kısa masaüstü ekranı: 4 sütun, simge + ad tek satır.
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 6, crossAxisSpacing: 6, mainAxisExtent: 40),
        itemCount: kasadaGorunenYontemler.length,
        itemBuilder: (_, i) {
          final y = kasadaGorunenYontemler[i];
          return _yontemKutusu(y.$1, y.$2, yontemSimgesi(y.$1, y.$3), _yontem == y.$1, () => setState(() => _yontem = y.$1), tekSatir: true);
        },
      );
    }
    if (_masaustuSol) {
      // Geniş masaüstü ekranı: kutular enine uzasa da boyu sabit (yer kaplamasın).
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, mainAxisExtent: 64),
        itemCount: kasadaGorunenYontemler.length,
        itemBuilder: (_, i) {
          final y = kasadaGorunenYontemler[i];
          return _yontemKutusu(y.$1, y.$2, yontemSimgesi(y.$1, y.$3), _yontem == y.$1, () => setState(() => _yontem = y.$1));
        },
      );
    }
    return GridView.count(
      crossAxisCount: sutun,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: g >= 1024 ? 2.1 : 2.3,
      children: [
        for (final y in kasadaGorunenYontemler) _yontemKutusu(y.$1, y.$2, yontemSimgesi(y.$1, y.$3), _yontem == y.$1, () => setState(() => _yontem = y.$1)),
      ],
    );
  }

  Widget _yontemKutusu(String kod, String ad, IconData ikon, bool secili, VoidCallback bas, {String? ton, bool tekSatir = false}) {
    final t = yontemTonu(ton ?? kod);
    if (tekSatir) {
      return Material(
        color: secili ? t.zemin : Renk.yuzey,
        shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? t.kenar : Renk.cizgi, width: secili ? 2 : 1)),
        child: InkWell(
          key: ValueKey('kasa-yontem-$kod'),
          borderRadius: koseYuvarlak,
          onTap: bas,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              Icon(secili ? Icons.check_circle_rounded : ikon, size: 18, color: secili ? t.yazi : t.ikon),
              const SizedBox(width: 6),
              Expanded(
                child: Text(ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: secili ? t.yazi : Renk.yazi)),
              ),
            ]),
          ),
        ),
      );
    }
    return Material(
      color: secili ? t.zemin : Renk.yuzey,
      shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? t.kenar : Renk.cizgi, width: secili ? 2 : 1)),
      child: InkWell(
        borderRadius: koseYuvarlak,
        onTap: bas,
        child: Stack(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: secili ? Renk.yuzey : t.zemin, borderRadius: koseYuvarlak),
                  child: Icon(ikon, size: 20, color: t.ikon),
                ),
                const SizedBox(height: 5),
                Text(ad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secili ? t.yazi : Renk.yazi)),
              ]),
            ),
          ),
          if (secili) Positioned(top: 6, right: 6, child: Icon(Icons.check_circle_rounded, size: 18, color: t.yazi)),
        ]),
      ),
    );
  }

  Widget _posKutusu() {
    final cihaz = _posCihazi;
    if (cihaz != null) return _manuelPosKutusu(cihaz);
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

  /// Konsolda tanımlı manuel kart POS'u: simülasyon uyarısı yerine sade bilgi
  /// kutusu; birden çok cihaz varsa küçük seçici (oturum boyunca hatırlanır).
  /// Ethernet POS'u seçilince arka planda TCP denemesi (ödemeyi bekletmez).
  void _posErisimDenetle(Json c) {
    final a = posAdres(c);
    if (a == null || _posErisim.tazeMi(a.ip, a.port)) return;
    _posErisim.denetle(a.ip, a.port, posDenetimSuresi(c['zaman_asimi_ms'])).then((ok) {
      if (!mounted) return;
      setState(() {});
      // IP değişmiş olabilir: ağ taraması sunucuya yeni adresi bildirir (10 dk'da en çok bir).
      if (!ok) context.durum.ajan?.posUlasilamadi();
    });
  }

  /// "POS bağlı" / "ulaşılamıyor" / USB durumu satırı (yoksa null).
  (String, Color)? _posBaglantiDurumu(Json c) {
    switch (posBaglanti(c)) {
      case 'ethernet':
        final a = posAdres(c);
        if (a == null) return null;
        return switch (_posErisim.durum(a.ip, a.port)) {
          true => ('POS bağlı', Renk.basari),
          false => ('POS\'a ulaşılamıyor — IP değişmiş olabilir', Renk.uyari),
          null => ('POS bağlantısı denetleniyor…', Renk.ikinci),
        };
      case 'usb':
        final ajan = context.durum.ajan;
        if (ajan == null || !ajan.usbDestekli) return ('USB', Renk.ikinci);
        final seri = c['seri_no']?.toString().trim() ?? '';
        final poslar = ajan.usbCihazlar.where((u) => u.tur == 'pos');
        final bagli = seri.isNotEmpty && ajan.usbCihazlar.any((u) => u.seri == seri) || poslar.isNotEmpty;
        return bagli ? ('USB · POS bağlı', Renk.basari) : ('USB · POS bu cihaza takılı görünmüyor', Renk.uyari);
    }
    return null;
  }

  Widget _manuelPosKutusu(Json cihaz) {
    final l = _manuelCihazlar;
    _posErisimDenetle(cihaz);
    String ad(Json c) => posCihazAdi(c);
    String alt(Json c) => [
          if (posAdres(c) case final a?) a.ip,
          if (posBaglanti(c) == 'usb') 'USB',
          if (c['banka'] != null && '${c['banka']}' != ad(c)) '${c['banka']}',
          if (c['terminal_no'] != null && '${c['terminal_no']}'.isNotEmpty) 'T: ${c['terminal_no']}',
        ].join(' · ');
    final baglanti = _posBaglantiDurumu(cihaz);
    final adres = posAdres(cihaz);
    return Container(
      key: const ValueKey('kasa-manuel-pos'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgiKoyu)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.point_of_sale_outlined, size: 18, color: Renk.bilgi),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Kartı '),
                TextSpan(text: ad(cihaz), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (adres != null) TextSpan(text: ' · ${adres.ip}', style: TextStyle(color: Renk.ikinci)),
                const TextSpan(text: ' cihazında okutun; onaylandıktan sonra tutarı burada onaylayın.'),
              ]),
              style: TextStyle(fontSize: 12.5, color: Renk.yazi),
            ),
          ),
        ]),
        if (baglanti != null)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 4),
            child: Text(baglanti.$1,
                key: const ValueKey('kasa-pos-baglanti'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: baglanti.$2)),
          ),
        if (l.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in l)
              Builder(builder: (_) {
                final secili = tamSayi(c['id']) == tamSayi(cihaz['id']);
                final a = alt(c);
                return Material(
                  color: secili ? Renk.markaAcik : Renk.ic,
                  shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: secili ? Renk.marka : Renk.cizgi)),
                  child: InkWell(
                    key: ValueKey('kasa-pos-cihaz-${c['id']}'),
                    customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
                    onTap: () => setState(() => _secilenPosCihazi = tamSayi(c['id'])),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(ad(c), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: secili ? Renk.marka : Renk.yazi)),
                        if (a.isNotEmpty) Text(a, style: TextStyle(fontSize: 11, color: Renk.ikinci)),
                      ]),
                    ),
                  ),
                );
              }),
          ]),
        ],
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
            Icon(yontemSimgesi(y.$1, y.$3), size: 16, color: Renk.ikinci),
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

  /// Kısa ekranda tek satırlık özet; dokununca liste açılır.
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
                  Icon(yontemSimgesi(p['method']?.toString(), p['method_icon']?.toString()), size: 13, color: Renk.soluk),
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
    _sikSol = false;
    _masaustuSol = false;
    _tusYuksekligi = 54;
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
            ('cash', 'Nakit', Icons.payments_outlined),
            ('card', 'Kart', Icons.credit_card_rounded),
            ('transfer', 'Havale', Icons.swap_horiz_rounded),
            ('other', 'Diğer', Icons.more_horiz_rounded),
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


/* ───────── Kasa yardımcıları ───────── */

/// Kalem seçimi: satır → seçili ADET sıraları (0..adet-1, satırın kendi
/// dökümündeki sırayla; ilk `adet - ödenmemiş` adet ödenmiş sayılır).
/// Sunucuya yalnız adet gider; sıralar ekranda hangi adet kartının
/// işaretli olduğunu göstermek için tutulur.
class _KalemSecimi extends ChangeNotifier {
  final Map<int, Set<int>> _birimler = {};

  bool get bos => _birimler.isEmpty;
  int adet(int id) => _birimler[id]?.length ?? 0;
  Set<int> birimler(int id) => _birimler[id] ?? const {};

  /// Satırın seçilebilir (ödenmemiş) adet sıraları.
  static Iterable<int> odenmemisSiralar(Kalem k) sync* {
    for (var i = k.adet - k.odenmemisAdet; i < k.adet; i++) {
      yield i;
    }
  }

  /// Tek adedi seç / bırak (ödenmiş adet seçilemez).
  void birimDegistir(Kalem k, int i) {
    if (i < k.adet - k.odenmemisAdet || i >= k.adet) return;
    final s = _birimler.putIfAbsent(k.id, () => <int>{});
    if (!s.remove(i)) s.add(i);
    if (s.isEmpty) _birimler.remove(k.id);
    notifyListeners();
  }

  /// Satırın ödenmemiş adetlerinin tamamı seçili mi?
  bool tamami(Kalem k) => k.odenmemisAdet > 0 && adet(k.id) >= k.odenmemisAdet;

  /// Başlık kutusu: tamamı seçiliyse bırak, değilse (hiç / kısmi) tamamını seç.
  void satirDegistir(Kalem k) {
    if (tamami(k)) {
      _birimler.remove(k.id);
    } else {
      _birimler[k.id] = odenmemisSiralar(k).toSet();
    }
    notifyListeners();
  }

  /// Seçimi baştan kurar (parti başlığı: partinin tamamı).
  void hepsiniSec(Iterable<Kalem> ks) {
    _birimler.clear();
    for (final k in ks) {
      final s = odenmemisSiralar(k).toSet();
      if (s.isNotEmpty) _birimler[k.id] = s;
    }
    notifyListeners();
  }

  void temizle() {
    if (_birimler.isEmpty) return;
    _birimler.clear();
    notifyListeners();
  }

  /// Güncel satırlara göre ayıklar: ödenmiş/çıkmış satır düşer; artık
  /// ödenmiş görünen ya da satırdan çıkmış adetler bırakılır, seçili adet
  /// sayısı korunur ama ödenmemiş adede kırpılır.
  bool ayikla(Iterable<Kalem> secilebilir) {
    if (_birimler.isEmpty) return false;
    final satirlar = {for (final k in secilebilir) k.id: k};
    var degisti = false;
    for (final id in _birimler.keys.toList()) {
      final k = satirlar[id];
      if (k == null || k.odenmemisAdet <= 0) {
        _birimler.remove(id);
        degisti = true;
        continue;
      }
      final eski = _birimler[id]!;
      final ilk = k.adet - k.odenmemisAdet;
      final n = eski.length.clamp(0, k.odenmemisAdet);
      final yeni = eski.where((i) => i >= ilk && i < k.adet).toSet();
      for (final i in odenmemisSiralar(k)) {
        if (yeni.length >= n) break;
        yeni.add(i);
      }
      while (yeni.length > n) {
        yeni.remove(yeni.reduce((a, b) => a > b ? a : b));
      }
      if (yeni.length != eski.length || !yeni.containsAll(eski)) {
        degisti = true;
        if (yeni.isEmpty) {
          _birimler.remove(id);
        } else {
          _birimler[id] = yeni;
        }
      }
    }
    if (degisti) notifyListeners();
    return degisti;
  }
}

/// Elle tetiklenen dinlenebilir (ödeme bölmesini setState'siz yeniler).
class _Tetik extends ChangeNotifier {
  void tetikle() => notifyListeners();
}

/// Küçük durum etiketi (8px kuralı: hap değil, köşeli).
class _Etiket extends StatelessWidget {
  const _Etiket(this.metin, {required this.renk, this.ikon});
  final String metin;
  final Color renk;
  final IconData? ikon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: renk.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ikon != null) ...[Icon(ikon, size: 13, color: renk), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              metin,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: renk, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Araç çubuğu düğmesi: renkli zemin + simge (+ isteğe bağlı yazı), 36 px.
class _AracDugmesi extends StatelessWidget {
  const _AracDugmesi(
      {super.key,
      required this.ikon,
      this.ad,
      required this.ipucu,
      required this.renk,
      required this.zemin,
      required this.kenar,
      required this.bas,
      this.sik = false,
      this.yukseklik = 52});
  final IconData ikon;

  /// Simge üstte, ad altta düzende düğme boyu.
  final double yukseklik;

  /// Aynı düğme, simge üstte / ad altta, verilen boyda (masaüstü satırı).
  _AracDugmesi dikey(double h) =>
      _AracDugmesi(key: key, ikon: ikon, ad: ad, ipucu: ipucu, renk: renk, zemin: zemin, kenar: kenar, bas: bas, yukseklik: h);

  /// Kısa masaüstü ekranı: simge + ad yan yana, ince düğme.
  final bool sik;
  final String? ad;
  final String ipucu;
  final Color renk;
  final Color zemin;
  final Color kenar;
  final VoidCallback? bas;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ipucu,
      child: Opacity(
        opacity: bas == null ? .5 : 1,
        child: Material(
          color: zemin,
          shape: RoundedRectangleBorder(borderRadius: koseYuvarlak, side: BorderSide(color: kenar)),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: koseYuvarlak),
            onTap: bas,
            child: sik
                ? SizedBox(
                    height: 36,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(ikon, size: 17, color: renk),
                      if (ad != null) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(ad!, maxLines: 1, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: renk)),
                          ),
                        ),
                      ],
                    ]),
                  )
                : SizedBox(
              height: yukseklik,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(ikon, size: yukseklik >= 54 ? 21 : 20, color: renk),
                if (ad != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(3, 3, 3, 0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(ad!, maxLines: 1, style: TextStyle(fontSize: yukseklik >= 54 ? 12.5 : 12, fontWeight: FontWeight.w600, color: renk, height: 1.1)),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
