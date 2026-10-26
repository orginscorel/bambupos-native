import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/bicim.dart';
import '../core/modeller.dart';
import 'ortak.dart';

/// Hazırlık (mutfak / barista / nargile) ve servis (komi) ekranı.
///
/// `GET /api/v1/kds/updates?cursor=` uzun-yoklamadır: değişiklik yoksa
/// sunucu ~20 sn bekleyip 204 döner, değişiklik olunca HEMEN tam kuyruğu
/// gönderir. Böylece sipariş düştüğü an ekranda görünür, boşta ağ yükü
/// yoktur.
class KdsEkrani extends StatefulWidget {
  const KdsEkrani({super.key, required this.kip, this.serit});

  /// 'kitchen' (hazırlık) | 'runner' (komi/servis)
  final String kip;

  /// kitchen | barista | nargile (yalnız hazırlık kipinde).
  final String? serit;

  @override
  State<KdsEkrani> createState() => _KdsEkraniState();
}

class _KdsEkraniState extends State<KdsEkrani> {
  Json? _veri;
  int _imlec = 0;
  bool _calisiyor = true;
  bool _baglantiYok = false;
  final Set<int> _gonderiliyor = {};
  Timer? _saat;

  bool get _runner => widget.kip == 'runner';

  Map<String, dynamic> get _sorgu => {
        'mode': widget.kip,
        if (!_runner && widget.serit != null) 'lane': widget.serit,
      };

  @override
  void initState() {
    super.initState();
    _dongu();
    // Bekleme süreleri dakikada bir güncellensin.
    _saat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _calisiyor = false;
    _saat?.cancel();
    super.dispose();
  }

  Future<void> _tam() async {
    final r = await _api.get('/api/v1/kds/queue', sorgu: _sorgu);
    _isle(r);
  }

  void _isle(dynamic r) {
    if (r is! Map || !mounted) return;
    setState(() {
      _veri = r.cast<String, dynamic>();
      _imlec = tamSayi(r['cursor'], _imlec);
      _baglantiYok = false;
    });
  }

  late final Api _api = context.api;

  Future<void> _dongu() async {
    var bekleme = 1;
    while (_calisiyor && mounted) {
      try {
        if (_veri == null) {
          await _tam();
        } else {
          final r = await _api.get('/api/v1/kds/updates',
              sorgu: {..._sorgu, 'cursor': _imlec}, zamanAsimi: const Duration(seconds: 45));
          // 204 → gövde boş; değişiklik yok, hemen yeniden bekle.
          if (r is Map) _isle(r);
        }
        bekleme = 1;
      } on ApiHata catch (e) {
        if (!mounted) return;
        setState(() => _baglantiYok = e.baglantiYok);
        if (e.yetkiYok) {
          setState(() => _veri = {'_yetki': e.mesaj});
          return;
        }
        await Future<void>.delayed(Duration(seconds: bekleme));
        bekleme = (bekleme * 2).clamp(1, 15);
      }
    }
  }

  Future<void> _kalemDurumu(Json kalem, String hedef, {int? surum}) async {
    final id = tamSayi(kalem['id']);
    if (_gonderiliyor.contains(id)) return;
    HapticFeedback.lightImpact();
    setState(() => _gonderiliyor.add(id));
    await context.islem(() => context.api.post('/api/v1/kds/items/$id/status', {
          'to': hedef,
          'expected_version': ?surum,
        }));
    if (mounted) {
      setState(() => _gonderiliyor.remove(id));
      // Uzun-yoklama zaten yakalar; anında görünmesi için tam kuyruğu da çek.
      _tam().catchError((_) {});
    }
  }

  Future<void> _hepsiHazir(Json kart) async {
    final id = tamSayi(kart['id']);
    HapticFeedback.mediumImpact();
    if (widget.serit == null || widget.serit == 'kitchen' || widget.serit == 'barista') {
      await context.islem(() => context.api.post('/api/v1/kds/orders/$id/station-ready', {
            'station': null,
            'lane': widget.serit,
            'expected_version': tamSayi(kart['version']),
          }));
    } else {
      // Toplu uç yalnız mutfak/barista şeridini tanır; diğer şeritte kartta
      // görünen (yani bu şeride ait) kalemler tek tek hazır yapılır.
      final api = context.api;
      for (final x in (kart['items'] as List? ?? const []).whereType<Map>()) {
        if (x['status'] == 'ready' || x['status'] == 'served') continue;
        if (!mounted) return;
        final ok = await context.islem(() => api.post('/api/v1/kds/items/${tamSayi(x['id'])}/status', {'to': 'ready'}));
        if (ok == null) break;
      }
    }
    if (mounted) _tam().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final v = _veri;
    if (v == null) {
      return Column(children: [
        BaglantiSeridi(gorunur: _baglantiYok),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ]);
    }
    if (v['_yetki'] != null) {
      return Center(child: Text(v['_yetki'].toString(), style: const TextStyle(color: Renk.soluk)));
    }

    return Column(children: [
      BaglantiSeridi(gorunur: _baglantiYok),
      Expanded(child: _runner ? _servis(v) : _hazirlik(v)),
    ]);
  }

  /* ───────── Hazırlık ───────── */

  Widget _hazirlik(Json v) {
    final kartlar = (v['orders'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (kartlar.isEmpty) return _bos('Bekleyen sipariş yok');
    final saatFarki = context.durum.oturum?.saatFarki ?? Duration.zero;

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 340,
        mainAxisExtent: 360,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: kartlar.length,
      itemBuilder: (_, i) {
        final k = kartlar[i];
        final kalemler = (k['items'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        final dk = gecenDakika(k['placed_at']?.toString(), saatFarki: saatFarki);
        final hedef = kalemler.fold<int>(0, (t, x) => tamSayi(x['target_minutes']) > t ? tamSayi(x['target_minutes']) : t);
        final gec = hedef > 0 && dk > hedef;
        final baslik = k['table_name']?.toString() ?? k['receivable_name']?.toString() ?? k['customer_name']?.toString() ?? k['channel_label']?.toString() ?? '#${k['id']}';

        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: gec ? Renk.hata : Renk.marka,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(baslik, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(
                      [k['service_type_label'], k['waiter']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ]),
                ),
                Text(sureMetni(dk), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
            if (k['note'] != null && '${k['note']}'.isNotEmpty)
              Container(
                color: Renk.uyari.withValues(alpha: .12),
                padding: const EdgeInsets.all(8),
                child: Text('Not: ${k['note']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: kalemler.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, j) => _KdsKalem(
                  kalem: kalemler[j],
                  mesgul: _gonderiliyor.contains(tamSayi(kalemler[j]['id'])),
                  bas: () {
                    final x = kalemler[j];
                    final sonraki = switch (x['status']) {
                      'placed' || 'sent_to_station' => 'preparing',
                      'accepted' => 'preparing',
                      'preparing' => 'ready',
                      _ => null,
                    };
                    if (sonraki != null) _kalemDurumu(x, sonraki, surum: tamSayi(k['version']));
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Renk.basari, minimumSize: const Size.fromHeight(48)),
                onPressed: () => _hepsiHazir(k),
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('Hepsi hazır'),
              ),
            ),
          ]),
        );
      },
    );
  }

  /* ───────── Servis (komi) ───────── */

  Widget _servis(Json v) {
    final satirlar = (v['items'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    if (satirlar.isEmpty) return _bos('Servis bekleyen ürün yok');
    final saatFarki = context.durum.oturum?.saatFarki ?? Duration.zero;

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: satirlar.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = satirlar[i];
        final id = tamSayi(s['id']);
        final masa = s['table_name']?.toString() ?? s['receivable_name']?.toString() ?? s['channel_label']?.toString() ?? '';
        final dk = gecenDakika((s['ready_at'] ?? s['updated_at'])?.toString(), saatFarki: saatFarki);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 84,
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Renk.markaAcik, borderRadius: koseYuvarlak),
                child: Text(masa, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, color: Renk.marka)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s['qty'] ?? 1} × ${s['name'] ?? ''}${s['variant_name'] != null ? ' (${s['variant_name']})' : ''}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                    [s['station_label'], 'Hazır · ${sureMetni(dk)}', s['waiter']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                    style: const TextStyle(color: Renk.soluk, fontSize: 12),
                  ),
                ]),
              ),
              FilledButton.icon(
                onPressed: _gonderiliyor.contains(id) ? null : () => _kalemDurumu(s, 'served', surum: tamSayi(s['order_version'])),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Teslim'),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _bos(String metin) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline_rounded, size: 56, color: Renk.soluk),
          const SizedBox(height: 10),
          Text(metin, style: const TextStyle(color: Renk.soluk, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _KdsKalem extends StatelessWidget {
  const _KdsKalem({required this.kalem, required this.bas, required this.mesgul});
  final Json kalem;
  final VoidCallback bas;
  final bool mesgul;

  @override
  Widget build(BuildContext context) {
    final k = kalem;
    final durum = k['status']?.toString();
    final renk = switch (durum) {
      'preparing' => Renk.uyari,
      'ready' => Renk.basari,
      _ => Renk.soluk,
    };
    final secenekler = (k['options'] as List? ?? const [])
        .map((o) => o is Map ? (o['option_name'] ?? o['name'] ?? '').toString() : o.toString())
        .where((s) => s.isNotEmpty)
        .join(', ');

    return InkWell(
      onTap: mesgul ? null : bas,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${k['qty'] ?? 1}×', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${k['name'] ?? ''}${k['variant_name'] != null ? ' (${k['variant_name']})' : ''}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      decoration: durum == 'ready' ? TextDecoration.lineThrough : null)),
              if (secenekler.isNotEmpty) Text(secenekler, style: const TextStyle(fontSize: 13, color: Renk.soluk)),
              if (k['note'] != null && '${k['note']}'.isNotEmpty)
                Text('“${k['note']}”', style: const TextStyle(fontSize: 13, color: Renk.hata, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (mesgul)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: renk.withValues(alpha: .12), borderRadius: BorderRadius.circular(4)),
              child: Text(k['status_label']?.toString() ?? '', style: TextStyle(color: renk, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}
