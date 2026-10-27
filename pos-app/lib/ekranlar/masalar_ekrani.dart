import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'ortak.dart';

/// MASALAR — web'deki /panel/masalar (Venue/Tables.vue) birebiri.
/// Belge: /root/work/spec/masalar.md. Yoklama yok (web'de de yok); liste
/// açılışta, süzgeç/sayfa değişiminde ve her yazmadan sonra yenilenir.

/// TableStatus (sıra = enum sırası). varyant: info/warning → DOLU.
const _durumlar = <(String, String, String)>[
  ('available', 'Boş', 'success'),
  ('occupied', 'Oturuluyor', 'info'),
  ('awaiting_order', 'Sipariş bekliyor', 'warning'),
  ('order_taken', 'Sipariş alındı', 'info'),
  ('preparing', 'Hazırlanıyor', 'warning'),
  ('awaiting_service', 'Servis bekliyor', 'warning'),
  ('served', 'Servis edildi', 'info'),
  ('bill_requested', 'Hesap istendi', 'warning'),
  ('partially_paid', 'Kısmi ödendi', 'warning'),
  ('paid', 'Ödendi', 'success'),
  ('cleaning', 'Temizleniyor', 'neutral'),
  ('reserved', 'Rezerve', 'primary'),
  ('reservation_late', 'Rezervasyon gecikti', 'danger'),
  ('out_of_service', 'Kullanım dışı', 'neutral'),
];

const _sekiller = <(String, String)>[
  ('square', 'Kare'),
  ('rectangle', 'Dikdörtgen'),
  ('round', 'Yuvarlak'),
  ('oval', 'Oval'),
  ('bar_stool', 'Bar taburesi'),
  ('booth', 'Loca / sedir'),
];

class MasalarEkrani extends StatefulWidget {
  const MasalarEkrani({super.key});

  @override
  State<MasalarEkrani> createState() => _MasalarEkraniState();
}

class _MasalarEkraniState extends State<MasalarEkrani> {
  List<Json> _subeler = const [];
  List<Json> _alanlar = const [];
  List<Json> _satirlar = const [];
  int _sayfa = 1, _sonSayfa = 1, _toplam = 0;
  bool _yukleniyor = true;
  final Set<int> _secili = {};
  bool _topluMesgul = false;
  String? _topluDurum;
  int? _topluAlan;

  // Süzgeçler
  final _ara = TextEditingController();
  int? _fSube;
  String? _fAlan; // int metni | 'none'
  String? _fDurum;
  String? _fAktif; // '1' | '0'

  bool get _canCreate => context.durum.oturum!.yetki('tables.create');
  bool get _canUpdate => context.durum.oturum!.yetki('tables.update');
  bool get _canDelete => context.durum.oturum!.yetki('tables.delete');
  bool get _canBulk => _canUpdate || _canDelete;
  int get _suzgecSayisi => [_fSube, _fAlan, _fDurum, _fAktif].where((e) => e != null).length;

  @override
  void initState() {
    super.initState();
    _sozlukleriYukle();
    _yukle();
  }

  @override
  void dispose() {
    _ara.dispose();
    super.dispose();
  }

  Future<void> _sozlukleriYukle() async {
    // Web ikisini birlikte ister ve biri hata verirse ikisini de boşaltır;
    // burada BAĞIMSIZ (garson/terminal şube listesini göremez ama alanları görür).
    final api = context.api;
    try {
      final r = await api.get('/api/v1/venue/branches');
      if (mounted) setState(() => _subeler = _liste((r as Map)['branches']));
    } on ApiHata {
      // Şube listesi yetkisi yok: süzgeç gizli kalır.
    }
    try {
      final r = await api.get('/api/v1/venue/areas');
      if (mounted) setState(() => _alanlar = _liste((r as Map)['areas']));
    } on ApiHata {
      // Alan listesi alınamazsa yalnız "— Alansız —" seçilebilir.
    }
  }

  static List<Json> _liste(Object? v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await context.api.get('/api/v1/venue/tables', sorgu: {
        'page': _sayfa,
        'area_id': ?_fAlan,
        'status': ?_fDurum,
        'active': ?_fAktif,
        if (_ara.text.trim().isNotEmpty) 'q': _ara.text.trim(),
      });
      final t = (r as Map)['tables'] as Map;
      if (!mounted) return;
      setState(() {
        _satirlar = _liste(t['data']);
        _sayfa = tamSayi(t['current_page'], 1);
        _sonSayfa = tamSayi(t['last_page'], 1);
        _toplam = tamSayi(t['total']);
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Masalar yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _suzgecDegisti() {
    _secili.clear();
    _sayfa = 1;
    _yukle();
  }

  static bool _dolu(Json m) => const {'info', 'warning'}.contains(m['status_variant']);

  List<(String, String)> _alanSecenekleri({int? subeId, bool alansiz = false}) => [
        if (alansiz) ('none', '— Alansız —'),
        for (final a in _alanlar)
          if (subeId == null || tamSayi(a['branch_id']) == subeId)
            ('${a['id']}', a['floor_name'] != null ? '${a['name']} (${a['floor_name']})' : '${a['name']}'),
      ];

  /* ───────── Toplu işlemler ───────── */

  Future<void> _topluCalistir(String eylem, [Map<String, dynamic> ek = const {}]) async {
    if (_topluMesgul || _secili.isEmpty) return;
    setState(() => _topluMesgul = true);
    try {
      final r = (await context.api.post('/api/v1/venue/tables/bulk-action', {'table_ids': _secili.toList(), 'action': eylem, ...ek}) as Map);
      if (!mounted) return;
      final atlanan = (r['skipped_open_order_ids'] as List?)?.length ?? 0;
      if (atlanan > 0) {
        context.bildir2('$atlanan masa atlandı',
            'Açık adisyonu olan $atlanan masa deaktive/silinemedi/durumu değiştirilemedi; önce adisyonu kapatın.',
            hata: true);
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      }
      if (mounted) context.bildir2('Toplu işlem tamamlandı', '${tamSayi(r['affected'])} masa güncellendi.');
      _secili.clear();
      _yukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Toplu işlem başarısız', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _topluMesgul = false);
    }
  }

  Future<void> _topluQr() async {
    if (_topluMesgul || _secili.isEmpty) return;
    setState(() => _topluMesgul = true);
    try {
      final r = (await context.api.post('/api/v1/venue/qr/rotate-bulk', {'table_ids': _secili.toList()}) as Map);
      if (!mounted) return;
      context.bildir2('QR kodları yenilendi',
          '${tamSayi(r['rotated'])} masanın eski QR kodu geçersiz kılındı. Yeni kartları yazdırmayı unutmayın.');
      _secili.clear();
      _yukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('QR yenileme başarısız', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _topluMesgul = false);
    }
  }

  /* ───────── Tekil işlemler ───────── */

  Future<void> _qrYenile(Json m) async {
    final ok = await onayla(context, 'QR kodunu yenile',
        '${m['name']} masasının QR kodu yenilenecek; masadaki basılı eski kod anında geçersiz olacak. Yeni kartı yazdırıp masaya koymadan eski kod çalışmayacaktır.',
        onay: 'Yenile', tehlikeli: true);
    if (!ok || !mounted) return;
    try {
      await context.api.post('/api/v1/venue/tables/${m['id']}/qr-rotate');
      if (mounted) context.bildir2('QR kodu yenilendi', '${m['name']} masasının eski QR kodu artık geçersiz. Yeni kartı yazdırın.');
      _yukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('QR yenilenemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _sil(Json m) async {
    final ok = await onayla(context, 'Masayı sil', '${m['name']} masası ve QR kodu kalıcı olarak silinecek. Bu işlem geri alınamaz.',
        onay: 'Sil', tehlikeli: true);
    if (!ok || !mounted) return;
    try {
      await context.api.delete('/api/v1/venue/tables/${m['id']}');
      if (mounted) context.bildir2('Masa silindi', '${m['name']} kaldırıldı.');
      _secili.remove(tamSayi(m['id']));
      _yukle();
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Silinemedi', e.mesaj, hata: true);
    }
  }

  Future<Uint8List?> _qrBayt(Json m, String bicim) async {
    final r = await context.api.indir('/api/v1/venue/tables/${m['id']}/qr-image', sorgu: {'format': bicim});
    return r;
  }

  Future<void> _qrIndir(Json m, String bicim) async {
    try {
      final bayt = await _qrBayt(m, bicim);
      if (bayt == null || !mounted) return;
      final ad = 'qr-masa-${m['number'] ?? m['id']}.$bicim';
      final dizin = Platform.isAndroid || Platform.isIOS ? await getTemporaryDirectory() : (await getDownloadsDirectory() ?? await getTemporaryDirectory());
      final dosya = File('${dizin.path}${Platform.pathSeparator}$ad');
      await dosya.writeAsBytes(bayt, flush: true);
      if (Platform.isAndroid || Platform.isIOS) {
        await SharePlus.instance.share(ShareParams(files: [XFile(dosya.path, mimeType: bicim == 'png' ? 'image/png' : 'image/svg+xml')], title: ad));
      } else if (mounted) {
        context.bildir2('QR indirildi', dosya.path);
      }
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('QR indirilemedi', e.mesaj, hata: true);
    }
  }

  Future<void> _qrOnizle(Json m) async {
    await pencereAc<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('QR önizleme — ${m['name']}'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 224,
              height: 224,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
              child: FutureBuilder<Uint8List?>(
                future: _qrBayt(m, 'png'),
                builder: (_, s) => s.hasData && s.data != null
                    ? Image.memory(s.data!, fit: BoxFit.contain)
                    : s.hasError
                        ? Center(child: Text('Görsel alınamadı', style: TextStyle(color: Renk.hata)))
                        : const Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 12),
            Text('Müşteri bu kodu okutunca masanın menüsü açılır. Yazdırmak için indirin.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ]),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Kapat')),
          TextButton.icon(onPressed: () => _qrIndir(m, 'png'), icon: const Icon(Icons.qr_code_2_rounded, size: 16), label: const Text('PNG indir')),
          TextButton.icon(onPressed: () => _qrIndir(m, 'svg'), icon: const Icon(Icons.qr_code_2_rounded, size: 16), label: const Text('SVG indir')),
        ],
      ),
    );
  }

  /* ───────── Çekmeceler ───────── */

  Future<void> _masaFormu([Json? m]) async {
    final yeni = m == null;
    final kaydedildi = await cekmeceAc<bool>(
      context,
      baslik: yeni ? 'Yeni masa' : 'Masayı düzenle',
      icerik: (ctx) => _MasaFormu(
        masa: m,
        subeler: _subeler,
        alanSecenekleri: (s) => _alanSecenekleri(subeId: s),
        varsayilanSube: _fSube ?? (_subeler.isNotEmpty ? tamSayi(_subeler.first['id']) : null),
      ),
    );
    if (kaydedildi == true) _yukle();
  }

  Future<void> _topluFormu() async {
    final kaydedildi = await cekmeceAc<bool>(
      context,
      baslik: 'Toplu masa oluştur',
      icerik: (ctx) => _TopluFormu(
        subeler: _subeler,
        alanSecenekleri: (s) => _alanSecenekleri(subeId: s),
        varsayilanSube: _fSube ?? (_subeler.isNotEmpty ? tamSayi(_subeler.first['id']) : null),
      ),
    );
    if (kaydedildi == true) _yukle();
  }

  /* ───────── Görünüm ───────── */

  @override
  Widget build(BuildContext context) {
    final g = MediaQuery.sizeOf(context).width;
    final sutun = g >= 1280 ? 5 : g >= 1024 ? 4 : g >= 640 ? 3 : 2;

    // Gruplar: "{şube}:{alan|none}", ilk görülme sırasıyla.
    final gruplar = <String, List<Json>>{};
    for (final m in _satirlar) {
      (gruplar['${m['branch_id']}:${m['area_id'] ?? 'none'}'] ??= []).add(m);
    }

    return Column(children: [
      _aracCubugu(g),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _yukle,
          child: ListView(
            padding: EdgeInsets.fromLTRB(g >= 640 ? 16 : 12, 12, g >= 640 ? 16 : 12, 16),
            children: [
              if (_canBulk && _secili.isNotEmpty) _topluCubuk(),
              if (_yukleniyor && _satirlar.isEmpty)
                _izgara(sutun, List.generate(10, (_) => Container(decoration: BoxDecoration(color: Renk.ic, borderRadius: kartYuvarlak))))
              else if (gruplar.isEmpty)
                _bosDurum()
              else
                for (final e in gruplar.entries) _grup(e.value, sutun),
              const SizedBox(height: 8),
              Row(children: [
                if (_canBulk)
                  InkWell(
                    onTap: () => setState(() {
                      final hepsi = _satirlar.isNotEmpty && _satirlar.every((m) => _secili.contains(tamSayi(m['id'])));
                      for (final m in _satirlar) {
                        hepsi ? _secili.remove(tamSayi(m['id'])) : _secili.add(tamSayi(m['id']));
                      }
                    }),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Checkbox(
                        value: _satirlar.isNotEmpty && _satirlar.every((m) => _secili.contains(tamSayi(m['id']))),
                        onChanged: (_) {},
                      ),
                      const Text('Sayfadakilerin tümünü seç', style: TextStyle(fontSize: 13)),
                    ]),
                  ),
                const Spacer(),
                if (_sonSayfa > 1) ...[
                  IconButton(onPressed: _sayfa > 1 ? () { _sayfa--; _yukle(); } : null, icon: const Icon(Icons.chevron_left_rounded)),
                  Text('$_sayfa / $_sonSayfa · $_toplam masa', style: TextStyle(fontSize: 13, color: Renk.ikinci)),
                  IconButton(onPressed: _sayfa < _sonSayfa ? () { _sayfa++; _yukle(); } : null, icon: const Icon(Icons.chevron_right_rounded)),
                ],
              ]),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _aracCubugu(double g) => Container(
        padding: EdgeInsets.symmetric(horizontal: g >= 640 ? 24 : 16, vertical: 8),
        decoration: BoxDecoration(color: Renk.yuzey, border: Border(bottom: BorderSide(color: Renk.cizgi))),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: 192, maxWidth: g >= 640 ? 448 : g - 140),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _ara,
                onSubmitted: (_) => _suzgecDegisti(),
                onChanged: (_) => _suzgecDegisti(),
                decoration: InputDecoration(
                  hintText: 'Masa adı veya no…',
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: Renk.soluk),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10),
                ),
              ),
            ),
          ),
          _suzgecDugmesi(g),
          if (_canCreate) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
              onPressed: _topluFormu,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: g >= 640 ? const Text('Toplu oluştur') : const SizedBox.shrink(),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 36)),
              onPressed: () => _masaFormu(),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Yeni masa'),
            ),
          ],
        ]),
      );

  Widget _suzgecDugmesi(double g) {
    final n = _suzgecSayisi;
    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 256,
            child: StatefulBuilder(
              builder: (ctx, yenile) {
                void degis(VoidCallback f) {
                  setState(f);
                  yenile(() {});
                  _suzgecDegisti();
                }

                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_subeler.length > 1) ...[
                    FormAlani(
                      etiket: 'Şube',
                      child: Secici<int>(
                        deger: _fSube,
                        yerTutucu: 'Tümü',
                        secenekler: [for (final s in _subeler) (tamSayi(s['id']), '${s['name']}')],
                        degisti: (v) => degis(() => _fSube = v),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FormAlani(
                    etiket: 'Alan',
                    child: Secici<String>(
                      deger: _fAlan,
                      yerTutucu: 'Tümü',
                      secenekler: _alanSecenekleri(subeId: _fSube, alansiz: true),
                      degisti: (v) => degis(() => _fAlan = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FormAlani(
                    etiket: 'Durum',
                    child: Secici<String>(
                      deger: _fDurum,
                      yerTutucu: 'Tümü',
                      secenekler: [for (final d in _durumlar) (d.$1, d.$2)],
                      degisti: (v) => degis(() => _fDurum = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FormAlani(
                    etiket: 'Aktiflik',
                    child: Secici<String>(
                      deger: _fAktif,
                      yerTutucu: 'Tümü',
                      secenekler: const [('1', 'Aktif'), ('0', 'Pasif')],
                      degisti: (v) => degis(() => _fAktif = v),
                    ),
                  ),
                  if (_suzgecSayisi > 0) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => degis(() {
                        _fSube = null;
                        _fAlan = null;
                        _fDurum = null;
                        _fAktif = null;
                      }),
                      child: const Text('Filtreleri temizle'),
                    ),
                  ],
                ]);
              },
            ),
          ),
        ),
      ],
      builder: (ctx, c, _) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: n > 0 ? Renk.markaAcik : Renk.yuzey,
          side: BorderSide(color: n > 0 ? Renk.marka : Renk.cizgi),
          foregroundColor: n > 0 ? Renk.marka : Renk.yazi,
        ),
        onPressed: () => c.isOpen ? c.close() : c.open(),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.filter_alt_outlined, size: 16),
          if (g >= 1024) ...[const SizedBox(width: 6), const Text('Filtre')],
          if (n > 0) ...[
            const SizedBox(width: 6),
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Renk.marka, shape: BoxShape.circle),
              child: Text('$n', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _topluCubuk() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: kartYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${_secili.length} masa seçili', style: const TextStyle(fontWeight: FontWeight.w500)),
          if (_canUpdate) ...[
            SizedBox(
              width: 180,
              child: Secici<String>(
                deger: _topluDurum,
                yerTutucu: 'Durum seç…',
                secenekler: [for (final d in _durumlar) (d.$1, d.$2)],
                degisti: (v) => setState(() => _topluDurum = v),
              ),
            ),
            OutlinedButton(
              onPressed: _topluDurum == null || _topluMesgul ? null : () => _topluCalistir('set_status', {'status': _topluDurum}),
              child: const Text('Durumu ata'),
            ),
            SizedBox(
              width: 180,
              child: Secici<String>(
                deger: _topluAlan?.toString(),
                yerTutucu: 'Alan seç…',
                secenekler: _alanSecenekleri(subeId: _fSube),
                degisti: (v) => setState(() => _topluAlan = v == null ? null : int.tryParse(v)),
              ),
            ),
            OutlinedButton(
              onPressed: _topluAlan == null || _topluMesgul ? null : () => _topluCalistir('set_area', {'area_id': _topluAlan}),
              child: const Text('Alana taşı'),
            ),
            OutlinedButton(onPressed: _topluMesgul ? null : () => _topluCalistir('activate'), child: const Text('Aktifleştir')),
            OutlinedButton(onPressed: _topluMesgul ? null : () => _topluCalistir('deactivate'), child: const Text('Pasifleştir')),
            OutlinedButton.icon(
                onPressed: _topluMesgul ? null : _topluQr, icon: const Icon(Icons.qr_code_2_rounded, size: 15), label: const Text('QR yenile')),
          ],
          if (_canDelete)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Renk.hata),
              onPressed: _topluMesgul
                  ? null
                  : () async {
                      final ok = await onayla(context, 'Seçili masaları sil',
                          '${_secili.length} masa ve QR kodları kalıcı olarak silinecek. Bu işlem geri alınamaz.',
                          onay: 'Sil', tehlikeli: true);
                      if (ok) _topluCalistir('delete');
                    },
              icon: const Icon(Icons.delete_outline_rounded, size: 15),
              label: const Text('Sil'),
            ),
        ]),
      );

  Widget _bosDurum() => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: kartYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Column(children: [
          Icon(Icons.dashboard_outlined, size: 40, color: Renk.soluk),
          const SizedBox(height: 10),
          const Text('Masa bulunamadı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Seçili filtrelerle eşleşen masa yok. Filtreleri temizleyin ya da yeni masa oluşturun.',
              textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci)),
          if (_canCreate) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _topluFormu, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Toplu oluştur')),
              FilledButton.icon(onPressed: () => _masaFormu(), icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Yeni masa')),
            ]),
          ],
        ]),
      );

  Widget _izgara(int sutun, List<Widget> cocuklar) => GridView.count(
        crossAxisCount: sutun,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: .92,
        children: cocuklar,
      );

  Widget _grup(List<Json> l, int sutun) {
    final ilk = l.first;
    final baslik = ilk['area_name']?.toString() ?? 'Alansız masalar';
    final alt = [if (ilk['floor_name'] != null) '${ilk['floor_name']}', if (_subeler.length > 1 && ilk['branch_name'] != null) '${ilk['branch_name']}'].join(' · ');
    final dolu = l.where(_dolu).length;
    final hepsiSecili = l.every((m) => _secili.contains(tamSayi(m['id'])));

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            if (_canBulk)
              Checkbox(
                value: hepsiSecili,
                onChanged: (v) => setState(() {
                  for (final m in l) {
                    v == true ? _secili.add(tamSayi(m['id'])) : _secili.remove(tamSayi(m['id']));
                  }
                }),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(baslik, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                if (alt.isNotEmpty) Text(alt, style: TextStyle(fontSize: 12, color: Renk.soluk)),
              ]),
            ),
            Text.rich(TextSpan(children: [
              TextSpan(text: '$dolu', style: TextStyle(fontWeight: FontWeight.w700, color: Renk.yazi)),
              TextSpan(text: ' / ${l.length} dolu'),
            ]), style: TextStyle(fontSize: 12, color: Renk.ikinci)),
          ]),
        ),
        _izgara(sutun, [for (final m in l) _kart(m)]),
      ]),
    );
  }

  Widget _kart(Json m) {
    final id = tamSayi(m['id']);
    final dolu = _dolu(m);
    final secili = _secili.contains(id);
    final aktif = m['is_active'] != false;
    final kenar = secili ? Renk.marka : (dolu ? Renk.hataKenar : Renk.basariKenar);
    final zemin = secili ? Renk.markaAcik.carp(.25) : (dolu ? Renk.hataZemin : Renk.basariZemin.carp(.5));
    final renk = dolu ? Renk.hata : Renk.basari;

    return Opacity(
      opacity: aktif ? 1 : .6,
      child: Container(
        decoration: BoxDecoration(
          color: zemin,
          borderRadius: kartYuvarlak,
          border: Border.all(color: kenar, width: secili ? 2 : 1),
          boxShadow: kartGolge,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Üst bant (web: TablePreview3D — burada şekle göre simge).
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: dolu ? Renk.hataZemin : Renk.basariZemin,
                border: Border(bottom: BorderSide(color: dolu ? Renk.hataKenar : Renk.basariKenar)),
              ),
              child: Icon(_sekilSimge(m['shape']?.toString()), size: 34, color: renk.withValues(alpha: .7)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: dolu ? Renk.hata : Renk.basariZemin, borderRadius: BorderRadius.circular(10)),
                  child: Text('${m['number'] ?? '—'}',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: dolu ? Colors.white : Renk.basari)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${m['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Row(children: [
                      Icon(Icons.people_outline_rounded, size: 13, color: Renk.ikinci),
                      const SizedBox(width: 3),
                      Text('${m['capacity']} kişi', style: TextStyle(fontSize: 12, color: Renk.ikinci)),
                    ]),
                  ]),
                ),
              ]),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 6),
              child: Row(children: [
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 4, children: [
                    Rozet(dolu ? 'Dolu' : 'Boş', renk: renk, dolu: dolu, ikon: Icons.circle),
                    if (!dolu && m['status'] != 'available') Rozet('${m['status_label']}', renk: Renk.soluk, zemin: Renk.yuzey),
                    if (!aktif) Rozet('Pasif', renk: Renk.soluk, zemin: Renk.yuzey),
                  ]),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Masa işlemleri',
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  onSelected: (s) => switch (s) {
                    'duzenle' => _masaFormu(m),
                    'onizle' => _qrOnizle(m),
                    'png' => _qrIndir(m, 'png'),
                    'svg' => _qrIndir(m, 'svg'),
                    'yenile' => _qrYenile(m),
                    'sil' => _sil(m),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    if (_canUpdate) const PopupMenuItem(value: 'duzenle', child: _MenuSatir(Icons.edit_outlined, 'Düzenle')),
                    const PopupMenuItem(value: 'onizle', child: _MenuSatir(Icons.search_rounded, 'QR önizle')),
                    const PopupMenuItem(value: 'png', child: _MenuSatir(Icons.qr_code_2_rounded, 'QR indir (PNG)')),
                    const PopupMenuItem(value: 'svg', child: _MenuSatir(Icons.qr_code_2_rounded, 'QR indir (SVG)')),
                    if (_canUpdate) const PopupMenuItem(value: 'yenile', child: _MenuSatir(Icons.warning_amber_rounded, 'QR kodunu yenile')),
                    if (_canDelete) const PopupMenuItem(value: 'sil', child: _MenuSatir(Icons.delete_outline_rounded, 'Masayı sil', tehlikeli: true)),
                  ],
                ),
              ]),
            ),
          ]),
          if (_canBulk)
            Positioned(
              top: 2,
              right: 2,
              child: Checkbox(
                value: secili,
                onChanged: (v) => setState(() => v == true ? _secili.add(id) : _secili.remove(id)),
              ),
            ),
        ]),
      ),
    );
  }

  static IconData _sekilSimge(String? s) => switch (s) {
        'round' || 'oval' => Icons.circle_outlined,
        'bar_stool' => Icons.chair_alt_outlined,
        'booth' => Icons.weekend_outlined,
        'rectangle' => Icons.crop_landscape_rounded,
        _ => Icons.crop_square_rounded,
      };
}

class _MenuSatir extends StatelessWidget {
  const _MenuSatir(this.ikon, this.metin, {this.tehlikeli = false});
  final IconData ikon;
  final String metin;
  final bool tehlikeli;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(ikon, size: 18, color: tehlikeli ? Renk.hata : Renk.ikinci),
        const SizedBox(width: 10),
        Text(metin, style: TextStyle(color: tehlikeli ? Renk.hata : Renk.yazi)),
      ]);
}

/* ───────── Tekil masa formu ───────── */

class _MasaFormu extends StatefulWidget {
  const _MasaFormu({required this.masa, required this.subeler, required this.alanSecenekleri, required this.varsayilanSube});
  final Json? masa;
  final List<Json> subeler;
  final List<(String, String)> Function(int?) alanSecenekleri;
  final int? varsayilanSube;

  @override
  State<_MasaFormu> createState() => _MasaFormuState();
}

class _MasaFormuState extends State<_MasaFormu> {
  late final Json? m = widget.masa;
  late int? _sube = m != null ? tamSayi(m!['branch_id']) : widget.varsayilanSube;
  late String? _alan = m?['area_id']?.toString();
  late final _ad = TextEditingController(text: m?['name']?.toString() ?? '');
  late final _no = TextEditingController(text: m?['number']?.toString() ?? '');
  late final _kapasite = TextEditingController(text: '${m?['capacity'] ?? 4}');
  late String _sekil = m?['shape']?.toString() ?? 'square';
  late String _durum = m?['status']?.toString() ?? 'available';
  late final _not = TextEditingController(text: m?['notes']?.toString() ?? '');
  late bool _birlesir = m?['is_joinable'] != false;
  late bool _aktif = m?['is_active'] != false;
  Map<String, String> _hatalar = {};
  bool _mesgul = false;

  @override
  void dispose() {
    _ad.dispose();
    _no.dispose();
    _kapasite.dispose();
    _not.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hatalar = {};
    });
    final govde = <String, dynamic>{
      'name': _ad.text.trim(),
      'capacity': int.tryParse(_kapasite.text) ?? 4,
      'shape': _sekil,
      'is_joinable': _birlesir,
      'notes': _not.text.trim().isEmpty ? null : _not.text.trim(),
      'is_active': _aktif,
      'area_id': _alan == null ? null : int.tryParse(_alan!),
      if (_no.text.trim().isNotEmpty) 'number': int.tryParse(_no.text.trim()),
      if (m == null) 'branch_id': _sube ?? 0,
    };
    final api = context.api;
    try {
      if (m == null) {
        await api.post('/api/v1/venue/tables', govde);
        if (mounted) context.bildir2('Masa oluşturuldu', '${_ad.text.trim()} eklendi; QR kodu hazır.');
      } else {
        await api.put('/api/v1/venue/tables/${m!['id']}', govde);
        // Durum AYRI uçtan, meta kaydından sonra (dolu masa formdan boşaltılamasın).
        if (_durum != m!['status']) {
          await api.put('/api/v1/venue/tables/${m!['id']}/status', {'status': _durum});
        }
        if (mounted) context.bildir2('Masa güncellendi', '${_ad.text.trim()} kaydedildi.');
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiHata catch (e) {
      final h = e.govde?['errors'];
      if (h is Map && h.isNotEmpty) {
        setState(() => _hatalar = {for (final k in h.keys) '$k': ((h[k] as List?)?.first ?? '').toString()});
      } else if (mounted) {
        context.bildir2('Kaydedilemedi', e.mesaj, hata: true);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sayi = TextInputType.number;
    return ListView(padding: const EdgeInsets.all(18), children: [
      if (m == null) ...[
        FormAlani(
          etiket: 'Şube',
          zorunlu: true,
          hata: _hatalar['branch_id'],
          child: Secici<int>(
            deger: _sube,
            yerTutucu: 'Şube seçin',
            secenekler: [for (final s in widget.subeler) (tamSayi(s['id']), '${s['name']}')],
            degisti: (v) => setState(() => _sube = v),
          ),
        ),
        const SizedBox(height: 16),
      ],
      FormAlani(
        etiket: 'Masa adı / etiketi',
        zorunlu: true,
        ipucu: 'Şube içinde tekildir (ör. Teras 4, Pencere Kenarı)',
        hata: _hatalar['name'],
        child: TextField(controller: _ad, decoration: const InputDecoration(hintText: 'ör. Teras 4')),
      ),
      const SizedBox(height: 16),
      FormAlani(
        etiket: 'Masa no',
        ipucu: 'Boş bırakılırsa sıradaki numara verilir; şube içinde tekildir',
        hata: _hatalar['number'],
        child: TextField(controller: _no, keyboardType: sayi, decoration: const InputDecoration(hintText: 'Otomatik')),
      ),
      const SizedBox(height: 16),
      FormAlani(
        etiket: 'Alan',
        hata: _hatalar['area_id'],
        child: Secici<String>(
          deger: _alan,
          yerTutucu: 'Alansız',
          secenekler: widget.alanSecenekleri(_sube),
          degisti: (v) => setState(() => _alan = v),
        ),
      ),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: FormAlani(
            etiket: 'Kapasite',
            hata: _hatalar['capacity'],
            child: TextField(controller: _kapasite, keyboardType: sayi),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FormAlani(
            etiket: 'Şekil',
            hata: _hatalar['shape'],
            child: Secici<String>(deger: _sekil, secenekler: _sekiller, degisti: (v) => setState(() => _sekil = v ?? 'square')),
          ),
        ),
      ]),
      if (m != null) ...[
        const SizedBox(height: 16),
        FormAlani(
          etiket: 'Durum',
          hata: _hatalar['status'],
          child: Secici<String>(
            deger: _durum,
            secenekler: [for (final d in _durumlar) (d.$1, d.$2)],
            degisti: (v) => setState(() => _durum = v ?? _durum),
          ),
        ),
      ],
      const SizedBox(height: 16),
      FormAlani(
        etiket: 'Not',
        hata: _hatalar['notes'],
        child: TextField(controller: _not, decoration: const InputDecoration(hintText: 'İsteğe bağlı not')),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _birlesir,
        onChanged: (v) => setState(() => _birlesir = v),
        title: const Text('Birleştirilebilir', style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: const Text('Yan masalarla birleştirilerek büyük grup ağırlayabilir', style: TextStyle(fontSize: 12)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _aktif,
        onChanged: (v) => setState(() => _aktif = v),
        title: const Text('Aktif', style: TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(_hatalar['is_active'] ?? 'Pasif masalar public menüde ve operasyonda görünmez',
            style: TextStyle(fontSize: 12, color: _hatalar['is_active'] != null ? Renk.hata : null)),
      ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _mesgul ? null : _kaydet,
          child: _mesgul
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(m == null ? 'Oluştur' : 'Kaydet'),
        ),
      ]),
    ]);
  }
}

/* ───────── Toplu oluşturma formu ───────── */

class _TopluFormu extends StatefulWidget {
  const _TopluFormu({required this.subeler, required this.alanSecenekleri, required this.varsayilanSube});
  final List<Json> subeler;
  final List<(String, String)> Function(int?) alanSecenekleri;
  final int? varsayilanSube;

  @override
  State<_TopluFormu> createState() => _TopluFormuState();
}

class _TopluFormuState extends State<_TopluFormu> {
  late int? _sube = widget.varsayilanSube;
  String? _alan;
  final _onek = TextEditingController();
  final _bas = TextEditingController(text: '1');
  final _bit = TextEditingController(text: '10');
  final _kapasite = TextEditingController(text: '4');
  String _sekil = 'square';
  Map<String, String> _hatalar = {};
  bool _mesgul = false;

  @override
  void dispose() {
    _onek.dispose();
    _bas.dispose();
    _bit.dispose();
    _kapasite.dispose();
    super.dispose();
  }

  Future<void> _kaydet() async {
    setState(() {
      _mesgul = true;
      _hatalar = {};
    });
    try {
      final r = (await context.api.post('/api/v1/venue/tables/bulk', {
        'branch_id': _sube ?? 0,
        'area_id': _alan == null ? null : int.tryParse(_alan!),
        'name_prefix': _onek.text.trim(),
        'start': int.tryParse(_bas.text) ?? 1,
        'end': int.tryParse(_bit.text) ?? 1,
        'capacity': int.tryParse(_kapasite.text) ?? 4,
        'shape': _sekil,
      }) as Map);
      if (!mounted) return;
      context.bildir2('Masalar oluşturuldu', '${tamSayi(r['created_count'])} masa QR kodlarıyla birlikte eklendi.');
      Navigator.pop(context, true);
    } on ApiHata catch (e) {
      final h = e.govde?['errors'];
      if (h is Map && h.isNotEmpty) {
        setState(() => _hatalar = {for (final k in h.keys) '$k': ((h[k] as List?)?.first ?? '').toString()});
      } else if (mounted) {
        context.bildir2('Oluşturulamadı', e.mesaj, hata: true);
      }
    } finally {
      if (mounted) setState(() => _mesgul = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const sayi = TextInputType.number;
    return ListView(padding: const EdgeInsets.all(18), children: [
      Text.rich(
        TextSpan(children: [
          TextSpan(text: '"Önek + numara aralığı" ile tek seferde en fazla 200 masa oluşturur; her masa kendi QR koduyla gelir. Örnek: önek '),
          TextSpan(text: 'Teras', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ', aralık '),
          TextSpan(text: '1–20', style: TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: ' → Teras 1 … Teras 20.'),
        ]),
        style: TextStyle(fontSize: 14, color: Renk.ikinci),
      ),
      const SizedBox(height: 16),
      FormAlani(
        etiket: 'Şube',
        zorunlu: true,
        hata: _hatalar['branch_id'],
        child: Secici<int>(
          deger: _sube,
          yerTutucu: 'Şube seçin',
          secenekler: [for (final s in widget.subeler) (tamSayi(s['id']), '${s['name']}')],
          degisti: (v) => setState(() => _sube = v),
        ),
      ),
      const SizedBox(height: 16),
      FormAlani(
        etiket: 'Alan',
        hata: _hatalar['area_id'],
        child: Secici<String>(deger: _alan, yerTutucu: 'Alansız', secenekler: widget.alanSecenekleri(_sube), degisti: (v) => setState(() => _alan = v)),
      ),
      const SizedBox(height: 16),
      FormAlani(
        etiket: 'Ad öneki',
        zorunlu: true,
        hata: _hatalar['name_prefix'],
        child: TextField(controller: _onek, decoration: const InputDecoration(hintText: 'ör. Teras')),
      ),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: FormAlani(etiket: 'Başlangıç no', zorunlu: true, hata: _hatalar['start'], child: TextField(controller: _bas, keyboardType: sayi))),
        const SizedBox(width: 12),
        Expanded(child: FormAlani(etiket: 'Bitiş no', zorunlu: true, hata: _hatalar['end'], child: TextField(controller: _bit, keyboardType: sayi))),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: FormAlani(etiket: 'Kapasite', hata: _hatalar['capacity'], child: TextField(controller: _kapasite, keyboardType: sayi))),
        const SizedBox(width: 12),
        Expanded(
          child: FormAlani(
            etiket: 'Şekil',
            hata: _hatalar['shape'],
            child: Secici<String>(deger: _sekil, secenekler: _sekiller, degisti: (v) => setState(() => _sekil = v ?? 'square')),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _mesgul ? null : _kaydet,
          child: _mesgul
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Masaları oluştur'),
        ),
      ]),
    ]);
  }
}
