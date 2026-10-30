import 'dart:async';

import 'package:flutter/material.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'adisyon_ekrani.dart';
import 'gecmis_ekrani.dart';
import 'ortak.dart';

/// SELF SATIŞ (2026-10-30) — web /panel/self (Panel/Self/Index.vue) birebiri.
/// Gel-al / telefon siparişleri: masasız, aynı anda birden çok açık self.
///  - "Açık self": yeni self kartı + açık self kartları (masa kartı düzeni).
///    Dokununca bildik adisyon ekranı açılır; çıkınca buraya dönülür.
///  - "Kapalı self": gün sonundan beri ödenen / iptal edilenler (gri);
///    dokununca Önceki adisyonlar detayı (fiş yeniden basılabilir).
///  - Bardak / paket etiketi: açık kartta yazıcı düğmesi + "Etiket ayarı".
/// Kaynak GET /api/v1/self; ekran açıkken 10 sn'de bir sessiz yoklama.
/// Eklenti (self_satis) kapanınca ekran şeritten ve "Tümü"nden kalkar.
class SelfEkrani extends StatefulWidget {
  const SelfEkrani({super.key});

  @override
  State<SelfEkrani> createState() => _SelfEkraniState();
}

class _SelfEkraniState extends State<SelfEkrani> {
  late final Api _api = context.api;
  Map<String, dynamic> _veri = const {};
  bool _yukleniyor = true;
  bool _kapaliSekme = false;
  int? _basiliyor;
  bool _aciliyor = false;
  Timer? _yoklama;

  List<Map<String, dynamic>> _liste(String ad) =>
      (_veri[ad] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  Map<String, dynamic> get _ozet => _veri['ozet'] is Map ? (_veri['ozet'] as Map).cast<String, dynamic>() : const {};

  bool _yetki(String a) => context.durum.oturum?.yetki(a) ?? false;
  Duration get _fark => context.durum.oturum?.saatFarki ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    _yukle();
    _yoklama = Timer.periodic(const Duration(seconds: 10), (_) => _yukle(sessiz: true));
  }

  @override
  void dispose() {
    _yoklama?.cancel();
    super.dispose();
  }

  Future<void> _yukle({bool sessiz = false}) async {
    if (!sessiz && mounted) setState(() => _yukleniyor = true);
    try {
      final r = await _api.get('/api/v1/self');
      if (mounted && r is Map) setState(() => _veri = r.cast<String, dynamic>());
    } on ApiHata catch (e) {
      if (!sessiz && mounted) context.bildir2('Self listesi alınamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _adisyonuAc(int id) async {
    _yoklama?.cancel();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdisyonEkrani(adisyonId: id)));
    if (!mounted) return;
    _yoklama = Timer.periodic(const Duration(seconds: 10), (_) => _yukle(sessiz: true));
    await _yukle(sessiz: true);
  }

  Future<void> _yeniSelf() async {
    if (_aciliyor) return;
    final bilgi = await pencereAc<Map<String, String?>>(
      context: context,
      builder: (_) => _YeniSelf(siradakiNo: _veri['siradaki_no'] is num ? tamSayi(_veri['siradaki_no']) : null),
    );
    if (bilgi == null || !mounted) return;
    setState(() => _aciliyor = true);
    try {
      final r = await _api.post('/api/v1/orders', {
        'channel': 'pickup',
        'customer_name': bilgi['ad'],
        'customer_phone': bilgi['telefon'],
        'note': bilgi['not'],
      });
      final id = tamSayi(((r as Map)['order'] as Map)['id']);
      if (mounted && id > 0) await _adisyonuAc(id);
    } on ApiHata catch (e) {
      if (mounted) {
        context.bildir2('Self adisyon açılamadı', e.mesaj, hata: true);
        context.durum.islemHatasi(e);
      }
    } finally {
      if (mounted) setState(() => _aciliyor = false);
    }
  }

  Future<void> _etiketBas(Map<String, dynamic> k) async {
    if (_basiliyor != null) return;
    final id = tamSayi(k['id']);
    setState(() => _basiliyor = id);
    try {
      final r = await _api.post('/api/v1/self/$id/etiket', const <String, dynamic>{});
      final m = r is Map ? r : const {};
      final n = tamSayi(m['basilan']);
      final sinir = m['sinir'];
      if (mounted) {
        context.bildir2('Etiket gönderildi',
            sinir != null ? '$n etiket gönderildi (en fazla ${tamSayi(sinir)}).' : '$n etiket yazıcıya gönderildi.');
      }
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Etiket gönderilemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _basiliyor = null);
    }
  }

  Future<void> _etiketAyari() async {
    final kaydedildi = await pencereAc<bool>(context: context, builder: (_) => _EtiketAyari(api: _api));
    if (kaydedildi == true && mounted) {
      context.bildir2('Etiket ayarı kaydedildi', '');
      _yukle(sessiz: true);
    }
  }

  /* ───────── Görünüm ───────── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final yan = g >= 640 ? 16.0 : 12.0;
    final acik = _liste('acik');
    final kapanan = _liste('kapanan');

    return ColoredBox(
      color: Renk.zemin,
      child: RefreshIndicator(
        onRefresh: _yukle,
        child: ListView(
          padding: EdgeInsets.fromLTRB(yan, yan, yan, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _sekmeler(acik.length, kapanan.length),
                  const SizedBox(height: 12),
                  if (_yukleniyor && acik.isEmpty && kapanan.isEmpty && _veri.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
                  else if (!_kapaliSekme)
                    ..._acikBolum(acik)
                  else
                    ..._kapaliBolum(kapanan),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Siparişler panosundaki sekme şeridiyle aynı: seçili = iç zemin + altta marka çizgisi.
  Widget _sekmeler(int acik, int kapali) {
    Widget sekme(bool kapaliMi, IconData ikon, String ad, int sayi) {
      final secili = _kapaliSekme == kapaliMi;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _kapaliSekme = kapaliMi),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: secili ? Renk.ic : Colors.transparent,
              border: Border(bottom: BorderSide(color: secili ? Renk.marka : Colors.transparent, width: 2)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(ikon, size: 15, color: secili ? Renk.yazi : Renk.ikinci),
              const SizedBox(width: 6),
              Flexible(
                child: Text(ad,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: secili ? Renk.yazi : Renk.ikinci)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(color: secili ? Renk.marka : Renk.ic, borderRadius: BorderRadius.circular(6)),
                child: Text('$sayi', style: TextStyle(fontSize: 12, color: secili ? Colors.white : Renk.soluk)),
              ),
            ]),
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sekme(false, Icons.shopping_bag_outlined, 'Açık self', acik),
          VerticalDivider(width: 1, color: Renk.cizgi),
          sekme(true, Icons.check_circle_outline_rounded, 'Kapalı self', kapali),
        ]),
      ),
    );
  }

  Widget _baslik({required IconData ikon, required Color renk, required Color zemin, required String ad, required String alt, required List<Widget> sag}) =>
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 6, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: zemin, borderRadius: koseYuvarlak),
          child: Icon(ikon, size: 16, color: renk),
        ),
        Text(ad, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text('· $alt', style: TextStyle(fontSize: 12, color: Renk.soluk)),
        ...sag,
      ]);

  Widget _nokta(Color c, String metin) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(metin, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]);

  Widget _izgara(List<Widget> kartlar) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 215,
          mainAxisExtent: 186,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: kartlar.length,
        itemBuilder: (_, i) => Belirme(sira: i, child: kartlar[i]),
      );

  List<Widget> _acikBolum(List<Map<String, dynamic>> acik) => [
        _baslik(
          ikon: Icons.shopping_bag_outlined,
          renk: Renk.marka,
          zemin: Renk.markaAcik,
          ad: 'Self adisyonlar',
          alt: 'gel-al ve telefon siparişleri',
          sag: [
            _nokta(Renk.hata, '${acik.length} açık'),
            Text('${para(tamSayi(_ozet['acik_tutar_minor']))} bekliyor', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (_yetki('settings.manage'))
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 10)),
                onPressed: _etiketAyari,
                icon: const Icon(Icons.print_outlined, size: 15),
                label: const Text('Etiket ayarı'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _izgara([_yeniKart(), for (final k in acik) _acikKart(k)]),
      ];

  List<Widget> _kapaliBolum(List<Map<String, dynamic>> kapanan) => [
        _baslik(
          ikon: Icons.check_circle_outline_rounded,
          renk: Renk.basari,
          zemin: Renk.basariZemin,
          ad: 'Kapalı self adisyonlar',
          alt: 'gün sonundan beri',
          sag: [
            _nokta(Renk.basari, '${tamSayi(_ozet['odenen_adet'])} ödendi'),
            if (tamSayi(_ozet['iptal_adet']) > 0) _nokta(Renk.soluk, '${tamSayi(_ozet['iptal_adet'])} iptal'),
            Text(para(tamSayi(_ozet['odenen_tutar_minor'])), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        if (kapanan.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Icon(Icons.check_circle_outline_rounded, size: 34, color: Renk.soluk),
              const SizedBox(height: 8),
              const Text('Henüz kapalı self adisyon yok', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('Kasada ödemesi alınan self adisyonlar burada görünür.',
                  textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci)),
            ]),
          )
        else
          _izgara([for (final k in kapanan) _kapaliKart(k)]),
      ];

  /* ───────── Kartlar (masa kartıyla aynı iskelet) ───────── */

  Widget _kartKabugu({
    required Color zemin,
    required Color kenar,
    required Widget ust,
    required Widget alt,
    VoidCallback? bas,
    Widget? sagUst,
  }) =>
      Stack(children: [
        Positioned.fill(
          child: Material(
            color: zemin,
            borderRadius: kartYuvarlak,
            child: InkWell(
              borderRadius: kartYuvarlak,
              onTap: bas,
              child: Container(
                decoration: BoxDecoration(borderRadius: kartYuvarlak, border: Border.all(color: kenar)),
                child: Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(8, 10, 8, 8), child: ust),
                  Divider(height: 1, color: kenar.withValues(alpha: .6)),
                  Expanded(child: alt),
                ]),
              ),
            ),
          ),
        ),
        if (sagUst != null) Positioned(top: 6, right: 6, child: sagUst),
      ]);

  Widget _hap(String no, {required Color zemin, required Color yazi, bool cizili = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: zemin, borderRadius: koseYuvarlak),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Self'),
            TextSpan(text: '  #$no', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: yazi.withValues(alpha: .7))),
          ]),
          style: TextStyle(
            color: yazi,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            decoration: cizili ? TextDecoration.lineThrough : null,
          ),
        ),
      );

  Widget _kucukSatir(IconData ikon, String metin) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ikon, size: 12, color: Renk.soluk),
        const SizedBox(width: 3),
        Flexible(child: Text(metin, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Renk.soluk))),
      ]);

  Widget _iki(String sol, String solDeger, Color solRenk, String sag, String sagDeger, {bool cizili = false}) => Row(children: [
        Expanded(
          child: Column(children: [
            Text(sol, style: TextStyle(fontSize: 11.5, color: Renk.ikinci)),
            Text(solDeger,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: solRenk,
                  decoration: cizili ? TextDecoration.lineThrough : null,
                )),
          ]),
        ),
        Expanded(
          child: Column(children: [
            Text(sag, style: TextStyle(fontSize: 11.5, color: Renk.ikinci)),
            Text(sagDeger, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]);

  Widget _yeniKart() {
    final acabilir = _yetki('orders.create');
    final no = _veri['siradaki_no'];
    return Opacity(
      opacity: acabilir ? 1 : .5,
      child: _kartKabugu(
        zemin: Renk.basariZemin,
        kenar: Renk.basari.withValues(alpha: .55),
        bas: acabilir && !_aciliyor ? _yeniSelf : null,
        ust: Column(mainAxisSize: MainAxisSize.min, children: [
          _hap(no is num ? '${no.toInt()}' : '—', zemin: Renk.basari, yazi: Renk.durumUstu),
          const SizedBox(height: 3),
          Text('YENİ', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.basari, letterSpacing: .4)),
          _kucukSatir(Icons.phone_outlined, 'gel-al · telefon'),
        ]),
        alt: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _aciliyor
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.add_rounded, color: Renk.basari, size: 22),
          Text(acabilir ? 'Adisyon aç' : 'Yetkiniz yok', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Renk.basari)),
        ]),
      ),
    );
  }

  Widget _acikKart(Map<String, dynamic> k) {
    final id = tamSayi(k['id']);
    final odenen = tamSayi(k['paid_minor']);
    final tutar = odenen > 0 ? tamSayi(k['remaining_minor']) : tamSayi(k['total_minor']);
    final acilis = k['created_at']?.toString();
    final tel = '${k['customer_phone'] ?? ''}';
    final ad = '${k['customer_name'] ?? ''}';
    final urun = tamSayi(k['urun_adedi']);
    final not = '${k['note'] ?? ''}';

    return _kartKabugu(
      zemin: Renk.hataZemin,
      kenar: Renk.hataKenar,
      bas: () => _adisyonuAc(id),
      sagUst: urun > 0
          ? Material(
              color: Renk.yuzey,
              borderRadius: koseYuvarlak,
              child: InkWell(
                borderRadius: koseYuvarlak,
                onTap: _basiliyor == id ? null : () => _etiketBas(k),
                child: Tooltip(
                  message: 'Bardak / paket etiketi bas',
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
                    child: _basiliyor == id
                        ? const Padding(padding: EdgeInsets.all(7), child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.print_outlined, size: 14, color: Renk.ikinci),
                  ),
                ),
              ),
            )
          : null,
      ust: Column(mainAxisSize: MainAxisSize.min, children: [
        _hap('${k['self_no'] ?? id}', zemin: Renk.hata, yazi: Renk.durumUstu),
        const SizedBox(height: 3),
        Text(odenen > 0 ? 'KISMİ ÖDENDİ' : 'AÇIK ADİSYON',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.hata, letterSpacing: .4)),
        _kucukSatir(Icons.person_outline_rounded, ad.isNotEmpty ? ad : 'İsimsiz'),
      ]),
      alt: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _iki('Adisyon', para(tutar), Renk.hata, 'Süre', sureMetni(gecenDakika(acilis, saatFarki: _fark))),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.center, spacing: 9, runSpacing: 2, children: [
            _kucukSatir(Icons.schedule_rounded, saatMetni(acilis)),
            _kucukSatir(Icons.restaurant_rounded, '$urun'),
            if (tel.isNotEmpty) _kucukSatir(Icons.phone_outlined, tel),
            if (not.isNotEmpty) Tooltip(message: not, child: Icon(Icons.sticky_note_2_outlined, size: 12, color: Renk.soluk)),
          ]),
        ]),
      ),
    );
  }

  Widget _kapaliKart(Map<String, dynamic> k) {
    final id = tamSayi(k['id']);
    final iptal = k['status'] == 'cancelled';
    final ad = '${k['customer_name'] ?? ''}';
    final tel = '${k['customer_phone'] ?? ''}';
    final odenen = tamSayi(k['paid_minor']);
    final tutar = iptal ? tamSayi(k['total_minor']) : (odenen > 0 ? odenen : tamSayi(k['total_minor']));
    final kapanis = saatMetni(k['closed_at']?.toString());

    return _kartKabugu(
      // Ödenen ile iptal ayrı gri tonlarda (web: bg-strong/40 · bg-strong/75).
      zemin: Renk.cizgiKoyu.withValues(alpha: iptal ? .75 : .4),
      kenar: Renk.cizgiKoyu,
      bas: () => oncekiAdisyonDetayi(context, id),
      ust: Column(mainAxisSize: MainAxisSize.min, children: [
        _hap('${k['self_no'] ?? id}',
            zemin: iptal ? Renk.yuzey : Renk.ikinci, yazi: iptal ? Renk.ikinci : Renk.durumUstu, cizili: iptal),
        const SizedBox(height: 3),
        Text('KAPALI SELF', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Renk.ikinci, letterSpacing: .4)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(color: iptal ? Renk.hataZemin : Renk.basariZemin, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(iptal ? Icons.cancel_outlined : Icons.check_circle_outline_rounded, size: 11, color: iptal ? Renk.hata : Renk.basari),
            const SizedBox(width: 3),
            Text(iptal ? 'İptal edildi' : 'Ödendi',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: iptal ? Renk.hata : Renk.basari)),
          ]),
        ),
        _kucukSatir(Icons.person_outline_rounded, ad.isNotEmpty ? ad : 'İsimsiz'),
      ]),
      alt: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _iki(iptal ? 'Tutar' : 'Tahsil', para(tutar), iptal ? Renk.ikinci : Renk.basari, 'Kapanış', kapanis.isEmpty ? '—' : kapanis,
              cizili: iptal),
          const SizedBox(height: 4),
          Wrap(alignment: WrapAlignment.center, spacing: 9, children: [
            _kucukSatir(Icons.restaurant_rounded, '${tamSayi(k['urun_adedi'])}'),
            if (tel.isNotEmpty) _kucukSatir(Icons.phone_outlined, tel),
          ]),
        ]),
      ),
    );
  }
}

/* ═════════════ Yeni self penceresi ═════════════ */

class _YeniSelf extends StatefulWidget {
  const _YeniSelf({required this.siradakiNo});
  final int? siradakiNo;

  @override
  State<_YeniSelf> createState() => _YeniSelfState();
}

class _YeniSelfState extends State<_YeniSelf> {
  final _ad = TextEditingController();
  final _tel = TextEditingController();
  final _not = TextEditingController();
  static const _hazir = ['Gelip alacak', 'Telefonla sipariş', 'Paket yapılsın', '15 dk sonra'];

  @override
  void dispose() {
    _ad.dispose();
    _tel.dispose();
    _not.dispose();
    super.dispose();
  }

  void _notEkle(String n) {
    final m = _not.text.trim();
    if (m.contains(n)) return;
    setState(() => _not.text = m.isEmpty ? n : '$m, $n');
  }

  String? _bosIse(String s) => s.trim().isEmpty ? null : s.trim();

  void _ac() => Navigator.pop(context, {
        'ad': _bosIse(_ad.text),
        'telefon': _bosIse(_tel.text),
        'not': _bosIse(_not.text),
      });

  @override
  Widget build(BuildContext context) {
    final genis = MediaQuery.sizeOf(context).width >= 560;
    final ad = FormAlani(
      etiket: 'Müşteri adı',
      child: TextField(controller: _ad, autofocus: true, maxLength: 120, decoration: const InputDecoration(hintText: 'ör. Ahmet Yılmaz', counterText: '')),
    );
    final tel = FormAlani(
      etiket: 'Telefon',
      child: TextField(
        controller: _tel,
        keyboardType: TextInputType.phone,
        maxLength: 32,
        decoration: const InputDecoration(hintText: '05xx xxx xx xx', counterText: ''),
      ),
    );

    return AlertDialog(
      title: Text(widget.siradakiNo != null ? 'Yeni self adisyon · #${widget.siradakiNo}' : 'Yeni self adisyon'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Gel-al ya da telefon siparişi. Ad ve telefon isteğe bağlı; adisyon açılınca ürün eklenir.',
                style: TextStyle(fontSize: 13, color: Renk.ikinci)),
            const SizedBox(height: 14),
            if (genis)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: ad),
                const SizedBox(width: 12),
                Expanded(child: tel),
              ])
            else ...[
              ad,
              const SizedBox(height: 12),
              tel,
            ],
            const SizedBox(height: 12),
            FormAlani(
              etiket: 'Not',
              child: TextField(controller: _not, maxLines: 2, maxLength: 500, decoration: const InputDecoration(hintText: 'ör. 15 dk sonra alacak', counterText: '')),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in _hazir) ActionChip(label: Text(n), onPressed: () => _notEkle(n)),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton.icon(onPressed: _ac, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Adisyon aç')),
      ],
    );
  }
}

/* ═════════════ Bardak / paket etiketi ayarı ═════════════ */

class _EtiketAyari extends StatefulWidget {
  const _EtiketAyari({required this.api});
  final Api api;

  @override
  State<_EtiketAyari> createState() => _EtiketAyariState();
}

class _EtiketAyariState extends State<_EtiketAyari> {
  List<Map<String, dynamic>> _yazicilar = const [];
  bool _destekli = true;
  bool _yukleniyor = true;
  bool _kaydediliyor = false;
  int _yazici = 0; // 0 = etiket yazıcısı yok
  int _mod = 1;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await widget.api.get('/api/v1/self/etiket-ayar');
      final m = r is Map ? r : const {};
      final l = (m['yazicilar'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      final secili = l.where((y) => tamSayi(y['etiket']) > 0).firstOrNull;
      if (!mounted) return;
      setState(() {
        _yazicilar = l;
        _destekli = m['destekli'] != false;
        _yazici = secili == null ? 0 : tamSayi(secili['id']);
        _mod = secili != null && tamSayi(secili['etiket']) == 2 ? 2 : 1;
      });
    } on ApiHata catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      context.bildir2('Yazıcılar alınamadı', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  Future<void> _kaydet() async {
    setState(() => _kaydediliyor = true);
    try {
      await widget.api.post('/api/v1/self/etiket-ayar', {'printer_id': _yazici == 0 ? null : _yazici, 'mod': _mod});
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Kaydedilemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _kaydediliyor = false);
    }
  }

  Future<void> _dene() async {
    if (_yazici == 0) return;
    try {
      await widget.api.post('/api/v1/self/etiket-dene', {'printer_id': _yazici});
      if (mounted) context.bildir2('Örnek etiket gönderildi', '');
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Gönderilemedi', e.mesaj, hata: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bardak / paket etiketi'),
      content: SizedBox(
        width: 420,
        child: _yukleniyor
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (!_destekli)
                  Text('Etiket ayarı bu sunucuda henüz kullanılamıyor.', style: TextStyle(color: Renk.uyari))
                else ...[
                  Text('Her ürün adedi için bir etiket basılır (en çok 60).', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
                  const SizedBox(height: 12),
                  FormAlani(
                    etiket: 'Etiket yazıcısı',
                    child: Secici<int>(
                      deger: _yazici,
                      secenekler: [
                        (0, 'Etiket yazıcısı yok (elle basımda kasa yazıcısı)'),
                        for (final y in _yazicilar) (tamSayi(y['id']), '${y['ad'] ?? ''} · ${y['istasyon'] ?? ''}'),
                      ],
                      degisti: (v) => setState(() => _yazici = v ?? 0),
                    ),
                  ),
                  if (_yazici != 0) ...[
                    const SizedBox(height: 12),
                    FormAlani(
                      etiket: 'Basım',
                      child: Secici<int>(
                        deger: _mod,
                        secenekler: const [(1, 'Yalnız elle bas'), (2, 'Mutfağa gidince otomatik bas')],
                        degisti: (v) => setState(() => _mod = v ?? 1),
                      ),
                    ),
                  ],
                ],
              ]),
      ),
      actions: [
        if (_yazici != 0 && _destekli) TextButton(onPressed: _dene, child: const Text('Örnek bas')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: _yukleniyor || _kaydediliyor || !_destekli ? null : _kaydet, child: const Text('Kaydet')),
      ],
    );
  }
}
