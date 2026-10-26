import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/tema.dart';
import '../core/api.dart';
import '../core/eski_windows.dart';
import 'ortak.dart';

/// UYGULAMA İÇİ GÜNCELLEME (mağaza dışı dağıtım).
///
/// Yeni sürüm bambumpos.com/indir/pos/surum.json'da ilan edilir (GitHub
/// sürümü yayımlanınca aynı dosya güncellenir). Uygulama her açılışta ve
/// 6 saatte bir bakar; yeni sürüm varsa üstte şerit çıkar:
///   • Android: APK uygulamanın içinde iner ve AYNI İMZAYLA mevcut kurulumun
///     üstüne kurulur — silip yeniden kurmak gerekmez, cihaz eşlemesi ve
///     oturum korunur.
///   • Windows / macOS: kurulum dosyası iner ve açılır (üzerine kurulur).
///   • iOS: indirme sayfası açılır.
class GuncellemeSeridi extends StatefulWidget {
  const GuncellemeSeridi({super.key});

  @override
  State<GuncellemeSeridi> createState() => _GuncellemeSeridiState();
}

class _GuncellemeSeridiState extends State<GuncellemeSeridi> {
  static ({String surum, String adres, String? notlar})? _bulunan;
  static DateTime? _sonBakis;
  bool _gizli = false;
  double? _ilerleme;
  String? _mesaj;
  StreamSubscription<OtaEvent>? _ota;

  @override
  void initState() {
    super.initState();
    _bak();
  }

  @override
  void dispose() {
    _ota?.cancel();
    super.dispose();
  }

  static String get _platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        // Windows 7 / 8.1: ayrı paket (uyumluluk katmanlı).
        TargetPlatform.windows => eskiWindows ? 'windows7' : 'windows',
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
      if (dahaYeni(yeni, context.durum.surum)) {
        setState(() => _bulunan = (surum: yeni, adres: adres, notlar: r['notlar']?.toString()));
      }
    } on ApiHata {
      // Sürüm dosyasına ulaşılamazsa sessiz geç.
    }
  }

  @visibleForTesting
  static bool dahaYeni(String a, String b) {
    List<int> p(String s) => s.split(RegExp(r'[.+-]')).take(3).map((e) => int.tryParse(e) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
      if (xi != yi) return xi > yi;
    }
    return false;
  }

  Future<void> _guncelle() async {
    final b = _bulunan!;
    if (Platform.isAndroid) return _android(b.adres, b.surum);
    if (Platform.isWindows || Platform.isMacOS) return _masaustu(b.adres);
    await launchUrl(Uri.parse(b.adres), mode: LaunchMode.externalApplication);
  }

  void _android(String adres, String surum) {
    setState(() {
      _ilerleme = 0;
      _mesaj = 'İndiriliyor…';
    });
    _ota?.cancel();
    _ota = OtaUpdate().execute(adres, destinationFilename: 'BamBumPOS-$surum.apk').listen(
      (e) {
        if (!mounted) return;
        setState(() {
          switch (e.status) {
            case OtaStatus.DOWNLOADING:
              _ilerleme = (double.tryParse(e.value ?? '') ?? 0) / 100;
              _mesaj = 'İndiriliyor… %${e.value ?? 0}';
            case OtaStatus.INSTALLING:
            case OtaStatus.INSTALLATION_DONE:
              _ilerleme = 1;
              _mesaj = 'Kurulum ekranı açılıyor — “Güncelle”ye dokunun';
            case OtaStatus.INSTALLATION_ERROR:
            case OtaStatus.DOWNLOAD_ERROR:
            case OtaStatus.CHECKSUM_ERROR:
            case OtaStatus.INTERNAL_ERROR:
              _ilerleme = null;
              _mesaj = 'Güncelleme tamamlanamadı (${e.value ?? e.status.name}). Tekrar deneyin.';
            case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
              _ilerleme = null;
              _mesaj = 'Bu uygulamaya “bilinmeyen uygulamaları yükleme” izni verin, sonra tekrar deneyin.';
            case OtaStatus.ALREADY_RUNNING_ERROR:
              _mesaj = 'Güncelleme zaten sürüyor…';
            case OtaStatus.CANCELED:
              _ilerleme = null;
              _mesaj = 'Güncelleme iptal edildi.';
          }
        });
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _ilerleme = null;
            _mesaj = 'Güncelleme tamamlanamadı: $e';
          });
        }
      },
    );
  }

  Future<void> _masaustu(String adres) async {
    setState(() {
      _ilerleme = 0;
      _mesaj = 'İndiriliyor…';
    });
    try {
      final dizin = await getTemporaryDirectory();
      final dosya = File('${dizin.path}${Platform.pathSeparator}${Uri.parse(adres).pathSegments.last}');
      final istemci = HttpClient();
      final yanit = await (await istemci.getUrl(Uri.parse(adres))).close();
      if (yanit.statusCode != 200) throw 'HTTP ${yanit.statusCode}';
      final toplam = yanit.contentLength;
      var inen = 0;
      final yaz = dosya.openWrite();
      await for (final parca in yanit) {
        yaz.add(parca);
        inen += parca.length;
        if (toplam > 0 && mounted) {
          setState(() {
            _ilerleme = inen / toplam;
            _mesaj = 'İndiriliyor… %${(inen * 100 / toplam).round()}';
          });
        }
      }
      await yaz.close();
      istemci.close();
      if (!mounted) return;
      setState(() => _mesaj = 'Kurulum açılıyor — bitince uygulamayı yeniden başlatın');
      if (Platform.isWindows) {
        await Process.start(dosya.path, const [], mode: ProcessStartMode.detached);
      } else {
        await Process.run('open', [dosya.path]);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ilerleme = null;
          _mesaj = 'İndirilemedi: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _bulunan;
    if (b == null || _gizli) return const SizedBox.shrink();
    return Material(
      color: Renk.markaAcik,
      child: Container(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Renk.markaKenar))),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.system_update_rounded, color: Renk.marka, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _mesaj ?? 'Yeni sürüm hazır: ${b.surum}${b.notlar != null ? ' — ${b.notlar}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            if (_ilerleme == null)
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 34)),
                onPressed: _guncelle,
                child: const Text('Güncelle'),
              ),
            if (_ilerleme == null)
              IconButton(onPressed: () => setState(() => _gizli = true), icon: const Icon(Icons.close_rounded, size: 18)),
          ]),
          if (_ilerleme != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: _ilerleme, minHeight: 4, backgroundColor: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}
