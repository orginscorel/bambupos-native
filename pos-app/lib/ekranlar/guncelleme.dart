import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'ortak.dart';

/// Mağaza dışı dağıtım: yeni sürüm bambumpos.com/indir/pos/surum.json'da
/// ilan edilir. Uygulama günde bir kez bakar; yeni sürüm varsa üstte ince
/// bir şerit çıkar, dokununca o platformun kurulum dosyası iner.
class GuncellemeSeridi extends StatefulWidget {
  const GuncellemeSeridi({super.key});

  @override
  State<GuncellemeSeridi> createState() => _GuncellemeSeridiState();
}

class _GuncellemeSeridiState extends State<GuncellemeSeridi> {
  static ({String surum, String adres, String? notlar})? _bulunan;
  static DateTime? _sonBakis;
  bool _gizli = false;

  @override
  void initState() {
    super.initState();
    _bak();
  }

  static String get _platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        TargetPlatform.windows => 'windows',
        TargetPlatform.macOS => 'macos',
        _ => 'diger',
      };

  Future<void> _bak() async {
    if (_sonBakis != null && DateTime.now().difference(_sonBakis!) < const Duration(hours: 6)) return;
    _sonBakis = DateTime.now();
    try {
      final r = await context.api.get('/indir/pos/surum.json');
      if (r is! Map) return;
      final yeni = r['surum']?.toString() ?? '';
      final adres = (r['indir'] is Map ? (r['indir'] as Map)[_platform] : null)?.toString();
      if (!mounted || adres == null || adres.isEmpty) return;
      if (_dahaYeni(yeni, context.durum.surum)) {
        setState(() => _bulunan = (surum: yeni, adres: adres, notlar: r['notlar']?.toString()));
      }
    } on ApiHata {
      // Sürüm dosyasına ulaşılamazsa sessiz geç.
    }
  }

  static bool _dahaYeni(String a, String b) {
    List<int> p(String s) => s.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final b = _bulunan;
    if (b == null || _gizli) return const SizedBox.shrink();
    return Material(
      color: Renk.markaAcik,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          const Icon(Icons.system_update_rounded, color: Renk.marka, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Yeni sürüm hazır: ${b.surum}${b.notlar != null ? ' — ${b.notlar}' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => launchUrl(Uri.parse(b.adres), mode: LaunchMode.externalApplication),
            child: const Text('İndir'),
          ),
          IconButton(onPressed: () => setState(() => _gizli = true), icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
      ),
    );
  }
}
