import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/hareket.dart';
import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import 'ortak.dart';

/// TESLİMAT PANOSU — web /panel/teslimat (Delivery/Board.vue) birebiri.
/// Şartname: /root/work/spec/teslimat.md.
/// Beş durum sütunu; kurye atama ve durum güncelleme "Yönet" penceresinde.
/// Yoklama yok — yalnız elle Yenile; atama/durum yanıtı listeyi yerinde günceller.
class TeslimatEkrani extends StatefulWidget {
  const TeslimatEkrani({super.key});

  @override
  State<TeslimatEkrani> createState() => _TeslimatEkraniState();
}

const _durumlar = <(String, String)>[
  ('pending', 'Bekliyor'),
  ('assigned', 'Atandı'),
  ('on_the_way', 'Yolda'),
  ('delivered', 'Teslim'),
  ('failed', 'Başarısız'),
];

(Color, Color) _durumRenk(String? d) => switch (d) {
      'assigned' => (Renk.bilgi, Renk.bilgiZemin),
      'on_the_way' => (Renk.marka, Renk.markaAcik),
      'delivered' => (Renk.basari, Renk.basariZemin),
      'failed' => (Renk.hata, Renk.hataZemin),
      _ => (Renk.ikinci, Renk.ic),
    };

const _aylarKisa = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

/// "26 Eki 14:32"
String _dt(Object? iso) {
  final t = iso == null ? null : DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  return '${t.day} ${_aylarKisa[t.month - 1]} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _TeslimatEkraniState extends State<TeslimatEkrani> {
  List<Map<String, dynamic>> _liste = const [];
  List<Map<String, dynamic>> _kuryeler = const [];
  bool _yukleniyor = true;
  late final Api _api = context.api;

  bool get _gorur => context.durum.oturum!.yetki('delivery.view');
  bool get _yonetir => context.durum.oturum!.yetki('delivery.manage');

  @override
  void initState() {
    super.initState();
    if (_gorur) {
      _yukle();
    } else {
      _yukleniyor = false;
    }
  }

  Future<void> _yukle() async {
    setState(() => _yukleniyor = true);
    try {
      final r = await _api.get('/api/v1/deliveries');
      if (!mounted) return;
      final m = r is Map ? r : const {};
      setState(() {
        _liste = (m['deliveries'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _kuryeler = (m['couriers'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      });
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Teslimatlar yüklenemedi', e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _yansit(dynamic r) {
    final d = r is Map ? r['delivery'] : null;
    if (d is! Map || !mounted) return;
    final yeni = d.cast<String, dynamic>();
    setState(() {
      final i = _liste.indexWhere((x) => tamSayi(x['order_id']) == tamSayi(yeni['order_id']));
      _liste = [..._liste];
      if (i >= 0) {
        _liste[i] = yeni;
      } else {
        _liste.add(yeni);
      }
    });
  }

  Future<void> _yonet(Map<String, dynamic> d) => pencereAc<void>(
        context: context,
        builder: (_) => _Yonet(teslimat: d, kuryeler: _kuryeler, api: _api, yansit: _yansit),
      );

  @override
  Widget build(BuildContext context) {
    if (!_gorur) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: 34, color: Renk.soluk),
            SizedBox(height: 8),
            Text('Erişim yok', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('Teslimat panosunu görüntülemek için yetkiniz bulunmuyor.', textAlign: TextAlign.center, style: TextStyle(color: Renk.ikinci)),
          ]),
        ),
      );
    }

    final g = MediaQuery.sizeOf(context).width;
    final sutun = g >= 1280 ? 5 : (g >= 768 ? 2 : 1);

    Widget icerik;
    if (_yukleniyor && _liste.isEmpty) {
      icerik = _izgara(sutun, [
        for (var i = 0; i < 5; i++) Container(height: 160, decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak)),
      ]);
    } else if (_liste.isEmpty) {
      icerik = Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          Icon(Icons.inventory_2_outlined, size: 34, color: Renk.soluk),
          SizedBox(height: 8),
          Text('Teslimat yok', style: TextStyle(fontWeight: FontWeight.w700)),
          Text('Paket siparişi geldiğinde burada listelenir.', style: TextStyle(color: Renk.ikinci)),
        ]),
      );
    } else {
      icerik = _izgara(sutun, [
        for (final (k, ad) in _durumlar) _sutun(ad, _liste.where((d) => d['status'] == k).toList()),
      ]);
    }

    return ColoredBox(
      color: Renk.zemin,
      child: RefreshIndicator(
        onRefresh: _yukle,
        child: ListView(
          padding: EdgeInsets.fromLTRB(g >= 640 ? 16 : 12, g >= 640 ? 16 : 12, g >= 640 ? 16 : 12, g >= 1024 ? 16 : 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [
                    Text('Paket siparişlerin teslimatını takip edin ve kurye atayın.', style: TextStyle(fontSize: 14, color: Renk.ikinci)),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
                      onPressed: _yukleniyor ? null : _yukle,
                      icon: _yukleniyor
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.inventory_2_outlined, size: 16),
                      label: const Text('Yenile'),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  icerik,
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _izgara(int sutun, List<Widget> ogeler) {
    if (sutun == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < ogeler.length; i++) ...[if (i > 0) const SizedBox(height: 16), ogeler[i]],
      ]);
    }
    final satirlar = <Widget>[];
    for (var i = 0; i < ogeler.length; i += sutun) {
      if (i > 0) satirlar.add(const SizedBox(height: 16));
      satirlar.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = i; j < i + sutun; j++) ...[
            if (j > i) const SizedBox(width: 16),
            Expanded(child: j < ogeler.length ? ogeler[j] : const SizedBox()),
          ],
        ]),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: satirlar);
  }

  Widget _sutun(String ad, List<Map<String, dynamic>> ks) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Renk.zemin, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(ad, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: Renk.ic, borderRadius: BorderRadius.circular(999)),
              child: Text('${ks.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Renk.ikinci)),
            ),
          ]),
          const SizedBox(height: 12),
          if (ks.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Kayıt yok', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Renk.soluk)),
            )
          else
            for (var i = 0; i < ks.length; i++) ...[if (i > 0) const SizedBox(height: 12), _kart(ks[i])],
        ]),
      );

  Widget _kart(Map<String, dynamic> d) {
    final o = d['order'] is Map ? d['order'] as Map : const {};
    final (renk, zemin) = _durumRenk(d['status']?.toString());
    final tel = o['customer_phone']?.toString();
    final adres = d['address']?.toString();
    final not = d['note']?.toString();
    final ucret = tamSayi(d['fee_minor']);
    final kurye = d['courier'] is Map ? (d['courier'] as Map)['name']?.toString() : null;
    final bitti = d['delivered_at'];
    final kucuk = TextStyle(fontSize: 12, color: Renk.ikinci);

    Widget bilgi(IconData ikon, Widget c) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(ikon, size: 13, color: Renk.soluk)),
            const SizedBox(width: 6),
            Expanded(child: c),
          ]),
        );

    return Opacity(
      opacity: d['status'] == 'delivered' ? .7 : 1,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Renk.yuzey, borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi), boxShadow: kartGolge),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text('${(o['customer_name']?.toString().isNotEmpty ?? false) ? o['customer_name'] : 'Müşteri'}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Rozet('${d['status_label'] ?? ''}', renk: renk, zemin: zemin),
          ]),
          if (tel != null && tel.isNotEmpty)
            bilgi(
              Icons.person_outline_rounded,
              InkWell(
                onTap: () => launchUrl(Uri.parse('tel:${tel.replaceAll(' ', '')}')),
                child: Text(tel, style: kucuk.copyWith(color: Renk.marka)),
              ),
            ),
          if (adres != null && adres.isNotEmpty) bilgi(Icons.storefront_outlined, Text(adres, maxLines: 2, overflow: TextOverflow.ellipsis, style: kucuk)),
          if (not != null && not.isNotEmpty)
            bilgi(Icons.info_outline_rounded, Text(not, maxLines: 2, overflow: TextOverflow.ellipsis, style: kucuk.copyWith(color: Renk.soluk))),
          const SizedBox(height: 8),
          Row(children: [
            Text(para(tamSayi(o['total_minor'])), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (ucret > 0) Text('+${para(ucret)} teslimat', style: kucuk),
          ]),
          if (kurye != null || bitti != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(spacing: 12, children: [
                if (kurye != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline_rounded, size: 13, color: Renk.soluk),
                    const SizedBox(width: 4),
                    Text(kurye, style: kucuk),
                  ]),
                if (bitti != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline_rounded, size: 13, color: Renk.basari),
                    const SizedBox(width: 4),
                    Text(_dt(bitti), style: kucuk),
                  ]),
              ]),
            ),
          if (_yonetir)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Renk.cizgi))),
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _yonet(d),
                icon: const Icon(Icons.settings_outlined, size: 15),
                label: const Text('Yönet'),
              ),
            ),
        ]),
      ),
    );
  }
}

/* ═════════════ Yönet penceresi (§4) ═════════════ */

class _Yonet extends StatefulWidget {
  const _Yonet({required this.teslimat, required this.kuryeler, required this.api, required this.yansit});
  final Map<String, dynamic> teslimat;
  final List<Map<String, dynamic>> kuryeler;
  final Api api;
  final void Function(dynamic) yansit;

  @override
  State<_Yonet> createState() => _YonetState();
}

class _YonetState extends State<_Yonet> {
  late int? _kurye = widget.teslimat['courier'] is Map ? tamSayi((widget.teslimat['courier'] as Map)['id']) : null;
  late String _durum = widget.teslimat['status']?.toString() ?? 'pending';
  bool _atiyor = false;
  bool _guncelliyor = false;

  int get _siparis => tamSayi(widget.teslimat['order_id']);

  Future<void> _ata() async {
    if (_kurye == null) return;
    setState(() => _atiyor = true);
    try {
      final r = await widget.api.post('/api/v1/deliveries/$_siparis/assign', {'courier_id': _kurye});
      widget.yansit(r);
      if (!mounted) return;
      context.bildir2('Kurye atandı', '');
      Navigator.pop(context);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Kurye atanamadı', e.mesaj.isEmpty ? 'Lütfen tekrar deneyin.' : e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _atiyor = false);
    }
  }

  Future<void> _guncelle() async {
    setState(() => _guncelliyor = true);
    try {
      final r = await widget.api.post('/api/v1/deliveries/$_siparis/status', {'status': _durum});
      widget.yansit(r);
      if (!mounted) return;
      context.bildir2('Durum güncellendi', '');
      Navigator.pop(context);
    } on ApiHata catch (e) {
      if (mounted) context.bildir2('Durum güncellenemedi', e.mesaj.isEmpty ? 'Lütfen tekrar deneyin.' : e.mesaj, hata: true);
    } finally {
      if (mounted) setState(() => _guncelliyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.teslimat;
    final o = d['order'] is Map ? d['order'] as Map : const {};
    final ad = (o['customer_name']?.toString().isNotEmpty ?? false) ? '${o['customer_name']}' : 'Teslimat';
    final adres = d['address']?.toString();

    return AlertDialog(
      title: Text(ad),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Renk.ic, borderRadius: koseYuvarlak),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (adres != null && adres.isNotEmpty) Text(adres, style: const TextStyle(fontSize: 13)),
                Text(para(tamSayi(o['total_minor'])), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Kurye',
              child: Row(children: [
                Expanded(
                  child: Secici<int>(
                    deger: _kurye,
                    yerTutucu: 'Kurye seçin',
                    secenekler: [for (final k in widget.kuryeler) (tamSayi(k['id']), '${k['name'] ?? ''}')],
                    degisti: (v) => setState(() => _kurye = v),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _kurye == null || _atiyor ? null : _ata, child: const Text('Ata')),
              ]),
            ),
            const SizedBox(height: 14),
            FormAlani(
              etiket: 'Durum',
              child: Row(children: [
                Expanded(
                  child: Secici<String>(
                    deger: _durum,
                    secenekler: _durumlar,
                    degisti: (v) => setState(() => _durum = v ?? _durum),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _guncelliyor ? null : _guncelle, child: const Text('Güncelle')),
              ]),
            ),
          ]),
        ),
      ),
      actions: [OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat'))],
    );
  }
}
