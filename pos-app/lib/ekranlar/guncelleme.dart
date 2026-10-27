import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/tema.dart';
import '../core/api.dart';
import 'ortak.dart';

/// UYGULAMA İÇİ GÜNCELLEME (mağaza dışı dağıtım).
///
/// Yeni sürüm bambumpos.com/indir/pos/surum.json'da ilan edilir (GitHub
/// sürümü yayımlanınca aynı dosya güncellenir). Uygulama açılışta, öne her
/// gelişte ve açık kaldıkça 20 dakikada bir bakar (kasalar gün boyu açık
/// kalıyor; eskiden 6 saatte bir ve yalnız açılışta bakıyordu — Android ve
/// masaüstüne güncelleme geç düşüyordu, 2026-10-27). Yeni sürüm varsa şerit çıkar:
///   • Android: APK uygulamanın içinde iner ve AYNI İMZAYLA mevcut kurulumun
///     üstüne kurulur — silip yeniden kurmak gerekmez, cihaz eşlemesi ve
///     oturum korunur.
///   • Windows / macOS: kurulum dosyası iner ve açılır (üzerine kurulur).
///   • iOS: indirme sayfası açılır.
///
/// MAĞAZA KURULUMU (App Store / TestFlight / Mac App Store): şerit HİÇ çıkmaz,
/// surum.json'a bakılmaz. Güncellemeyi mağaza verir (Apple kuralı 2.4.5 / 2.5.2:
/// mağaza dışı güncelleme ve indirme yönlendirmesi yasak). Siteden kurulumlar
/// (Android, Windows, Ad Hoc iPhone, DMG'den Mac) eskisi gibi.
class GuncellemeSeridi extends StatefulWidget {
  const GuncellemeSeridi({super.key});

  @override
  State<GuncellemeSeridi> createState() => _GuncellemeSeridiState();
}

class _GuncellemeSeridiState extends State<GuncellemeSeridi> with WidgetsBindingObserver {
  static ({String surum, String adres, String? notlar})? _bulunan;
  static DateTime? _sonBakis;
  bool _gizli = false;
  double? _ilerleme;
  String? _mesaj;
  StreamSubscription<OtaEvent>? _ota;
  Timer? _saat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _saat = Timer.periodic(const Duration(minutes: 20), (_) => _bak());
    _bak();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _bak();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saat?.cancel();
    _ota?.cancel();
    super.dispose();
  }

  static String get _platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        // pos-win7 dalı (Flutter 3.19 eski Windows derlemesi): hangi Windows'ta
        // açılırsa açılsın kendi kanalından güncellenir; surum.json'da bu
        // anahtar yoksa güncelleme önerilmez (Windows 10/11 paketine geçmez).
        TargetPlatform.windows => 'windows7_legacy',
        TargetPlatform.macOS => 'macos',
        _ => 'diger',
      };

  /// Uygulama Apple mağazasından mı kuruldu?
  ///   • iOS: siteden (Ad Hoc) kurulumda paket içinde embedded.mobileprovision
  ///     bulunur; TestFlight / App Store kurulumunda Apple bu dosyayı kaldırır.
  ///   • macOS: Mac App Store kurulumunda Contents/_MASReceipt/receipt bulunur;
  ///     DMG ile kurulan uygulamada yoktur.
  static final bool magazaKurulumu = _magazaKurulumuMu();

  static bool _magazaKurulumuMu() {
    try {
      final exe = File(Platform.resolvedExecutable);
      if (Platform.isIOS) return !File('${exe.parent.path}/embedded.mobileprovision').existsSync();
      if (Platform.isMacOS) return File('${exe.parent.parent.path}/_MASReceipt/receipt').existsSync();
    } catch (_) {}
    return false;
  }

  Future<void> _bak() async {
    if (magazaKurulumu) return;
    if (_sonBakis != null && DateTime.now().difference(_sonBakis!) < const Duration(minutes: 15)) return;
    _sonBakis = DateTime.now();
    try {
      final r = await context.api.get('/indir/pos/surum.json', sorgu: {'t': DateTime.now().millisecondsSinceEpoch ~/ 60000});
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
              _ilerleme = 1;
              _mesaj = 'Kurulum ekranı açılıyor — “Güncelle”ye dokunun';
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

  /// MAC KENDİ KENDİNE GÜNCELLEME (2026-10-27 işletme talebi: "her güncellemede
  /// Applications'a tekrar sürüklemek zorunda kalıyoruz").
  /// DMG arka planda bağlanır, içindeki .app bulunur; küçük bir betik bu uygulama
  /// kapanınca eski .app'i yenisiyle değiştirir (başarısızsa eskisini geri koyar),
  /// karantina işaretini temizler, DMG'yi ayırır ve uygulamayı yeniden açar.
  /// Uygulama klasörüne yazma izni yoksa macOS bir kez yönetici parolası sorar.
  Future<void> _macKendiniGuncelle(File dmg) async {
    final exe = File(Platform.resolvedExecutable); // …/BamBumPOS.app/Contents/MacOS/BamBumPOS
    final app = exe.parent.parent.parent.path;
    if (!app.endsWith('.app')) throw 'uygulama yolu bulunamadı';
    final gecici = await Directory.systemTemp.createTemp('bbp-guncelle');
    final mnt = '${gecici.path}/mnt';
    final bagla = await Process.run('hdiutil', ['attach', '-nobrowse', '-noautoopen', '-noverify', '-mountpoint', mnt, dmg.path]);
    if (bagla.exitCode != 0) throw 'DMG bağlanamadı';
    final yeni = Directory(mnt)
        .listSync(followLinks: false)
        .whereType<Directory>()
        .firstWhere((d) => d.path.endsWith('.app'), orElse: () => throw 'DMG içinde uygulama yok');
    String q(String v) => "'${v.replaceAll("'", "'\\''")}'";
    final betik = File('${gecici.path}/kur.sh');
    await betik.writeAsString([
      '#!/bin/bash',
      '# BamBumPOS Mac güncelleyici — uygulama kapanınca çalışır.',
      'APP=${q(app)}; YENI=${q(yeni.path)}; MNT=${q(mnt)}; GECICI=${q(gecici.path)}',
      'while kill -0 $pid 2>/dev/null; do sleep 0.3; done',
      r'rm -rf "$APP.eski"',
      r'if mv "$APP" "$APP.eski" && ditto "$YENI" "$APP"; then',
      r'  rm -rf "$APP.eski"',
      'else',
      r'  rm -rf "$APP"; mv "$APP.eski" "$APP"',
      'fi',
      r'xattr -dr com.apple.quarantine "$APP" 2>/dev/null',
      r'hdiutil detach "$MNT" -quiet -force',
      r'open "$APP"',
      r'rm -rf "$GECICI"',
      '',
    ].join('\n'));
    final yazilabilir = (await Process.run('test', ['-w', File(app).parent.path])).exitCode == 0 &&
        (await Process.run('test', ['-w', app])).exitCode == 0;
    if (mounted) setState(() => _mesaj = 'Güncelleme kuruluyor — uygulama birkaç saniye içinde yeniden açılacak');
    if (yazilabilir) {
      await Process.start('/bin/bash', [betik.path], mode: ProcessStartMode.detached);
    } else {
      await Process.start(
        'osascript',
        ['-e', 'do shell script "/bin/bash ${betik.path}" with administrator privileges with prompt "BamBumPOS güncellemesi kurulacak."'],
        mode: ProcessStartMode.detached,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
    exit(0);
  }

  Future<void> _masaustu(String adres) async {
    setState(() {
      _ilerleme = 0;
      _mesaj = 'İndiriliyor…';
    });
    try {
      // macOS'ta ~/Library/Caches/<paket> klasörü ilk kurulumda YOK olabiliyor
      // (PathNotFoundException) → önce oluştur; olmazsa İndirilenler'e düş.
      var dizin = await getTemporaryDirectory();
      try {
        await dizin.create(recursive: true);
      } catch (_) {
        dizin = (await getDownloadsDirectory()) ?? dizin;
      }
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
        // Mac: DMG'yi elle sürüklemek YOK — uygulama kendini değiştirip yeniden açılır.
        // Olmazsa (beklenmedik DMG yapısı vb.) eski yol: DMG açılır.
        try {
          await _macKendiniGuncelle(dosya);
        } catch (_) {
          if (mounted) setState(() => _mesaj = 'Kurulum açılıyor — BamBumPOS\'u Uygulamalar klasörüne sürükleyin');
          await Process.run('open', [dosya.path]);
        }
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
    if (b == null || _gizli || magazaKurulumu) return const SizedBox.shrink();
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
