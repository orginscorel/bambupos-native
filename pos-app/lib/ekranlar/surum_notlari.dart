import 'package:flutter/material.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'ortak.dart';

/// Alt şeritteki sürüm rozetine dokununca açılan "Sürüm notları" penceresi
/// (web: /panel/surum-notlari). Kaynak sunucuda config/native_changelog.php
/// (uygulama) + config/changelog.php (panel) → GET /api/v1/changelog/notlar.
Future<void> surumNotlariAc(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720), child: const _SurumNotlari()),
    ),
  );
}

class _SurumNotlari extends StatefulWidget {
  const _SurumNotlari();

  @override
  State<_SurumNotlari> createState() => _SurumNotlariState();
}

class _SurumNotlariState extends State<_SurumNotlari> {
  Map<String, dynamic>? _veri;
  String? _hata;
  bool _panel = false;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  Future<void> _yukle() async {
    try {
      final r = await context.api.get('/api/v1/changelog/notlar');
      if (mounted && r is Map) setState(() => _veri = r.cast<String, dynamic>());
    } on ApiHata catch (e) {
      if (mounted) setState(() => _hata = e.mesaj);
    }
  }

  @override
  Widget build(BuildContext context) {
    final yerel = context.durum.surum;
    final kume = _veri?[_panel ? 'panel' : 'uygulama'];
    final girdiler = (kume is Map ? kume['entries'] as List? : null) ?? const [];

    Widget sekme(String ad, bool panel) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _panel = panel),
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _panel == panel ? Renk.ic : null,
                border: Border(bottom: BorderSide(color: _panel == panel ? Renk.marka : Colors.transparent, width: 2)),
              ),
              child: Text(ad, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _panel == panel ? Renk.marka : Renk.yazi)),
            ),
          ),
        );

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sürüm notları', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Renk.yazi)),
              Text('Bu cihazdaki uygulama: v$yerel', style: TextStyle(fontSize: 12.5, color: Renk.ikinci)),
            ]),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(borderRadius: koseYuvarlak, border: Border.all(color: Renk.cizgi)),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          sekme('Uygulama${_veri?['uygulama']?['version'] != null ? ' · v${_veri!['uygulama']['version']}' : ''}', false),
          sekme('Panel${_veri?['panel']?['version'] != null ? ' · v${_veri!['panel']['version']}' : ''}', true),
        ]),
      ),
      Flexible(
        child: _hata != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_hata!, textAlign: TextAlign.center, style: TextStyle(color: Renk.hata)))
            : _veri == null
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                : ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), children: [
                    for (final g in girdiler.whereType<Map>()) _Girdi(g, guncel: !_panel && '${g['version']}' == yerel),
                    if (girdiler.isEmpty) Text('Kayıt yok.', style: TextStyle(color: Renk.soluk)),
                  ]),
      ),
    ]);
  }
}

class _Girdi extends StatelessWidget {
  const _Girdi(this.g, {required this.guncel});
  final Map g;
  final bool guncel;

  @override
  Widget build(BuildContext context) {
    final degisiklikler = (g['changes'] as List? ?? const []).whereType<Map>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('v${g['version'] ?? ''}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Renk.marka)),
          const SizedBox(width: 8),
          Text('${g['date'] ?? ''}', style: TextStyle(fontSize: 12, color: Renk.soluk)),
          if (guncel) ...[const SizedBox(width: 8), Rozet('Bu cihazda', renk: Renk.basari)],
        ]),
        if (g['title'] != null) Text('${g['title']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Renk.yazi)),
        const SizedBox(height: 6),
        for (final d in degisiklikler)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Tur('${d['type'] ?? ''}'),
              const SizedBox(width: 8),
              Expanded(child: Text('${d['text'] ?? ''}', style: TextStyle(fontSize: 13, color: Renk.ikinci, height: 1.35))),
            ]),
          ),
      ]),
    );
  }
}

class _Tur extends StatelessWidget {
  const _Tur(this.tur);
  final String tur;

  @override
  Widget build(BuildContext context) {
    final (ad, renk) = switch (tur) {
      'new' => ('Yeni', Renk.basari),
      'fixed' => ('Düzeltme', Renk.uyari),
      _ => ('İyileştirme', Renk.bilgi),
    };
    return SizedBox(width: 86, child: Rozet(ad, renk: renk));
  }
}
