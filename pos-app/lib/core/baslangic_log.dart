import 'dart:io';

/// pos-win7 dalı — AÇILIŞ GÜNLÜĞÜ (Dart tarafı).
///
/// Windows'ta %LOCALAPPDATA%\BamBumPOS\logs\baslangic.log dosyasına zaman
/// damgalı satır ekler. Aynı dosyaya native taraf (windows/runner/
/// baslangic_log.cpp) motor başlamadan önce yazar; böylece uygulama hangi
/// adımda takıldıysa dosyanın son satırı onu gösterir.
///
/// Günlük yazılamazsa sessizce geçilir — günlük, uygulamayı ASLA durdurmaz.
class BaslangicLog {
  BaslangicLog._();

  static File? _dosya;
  static bool _denendi = false;

  static File? get _hedef {
    if (_denendi) return _dosya;
    _denendi = true;
    try {
      if (!Platform.isWindows) return null;
      final yerel = Platform.environment['LOCALAPPDATA'];
      final kok = (yerel != null && yerel.isNotEmpty)
          ? '$yerel\\BamBumPOS'
          : File(Platform.resolvedExecutable).parent.path;
      final dizin = Directory('$kok\\logs')..createSync(recursive: true);
      _dosya = File('${dizin.path}\\baslangic.log');
    } catch (_) {
      _dosya = null;
    }
    return _dosya;
  }

  /// Günlük dosyasının yolu (Windows dışında null).
  static String? get yol => _hedef?.path;

  static String _iki(int n) => n.toString().padLeft(2, '0');

  /// Tek satır yazar (eşzamanlı: çökmeden hemen önceki satır da diske gider).
  static void yaz(String mesaj) {
    final f = _hedef;
    if (f == null) return;
    try {
      final t = DateTime.now();
      final zaman = '${t.year}-${_iki(t.month)}-${_iki(t.day)} ${_iki(t.hour)}:${_iki(t.minute)}:${_iki(t.second)}.'
          '${t.millisecond.toString().padLeft(3, '0')}';
      f.writeAsStringSync('$zaman [dart] $mesaj\r\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // Günlük yazılamadı — uygulama devam eder.
    }
  }

  /// Hata + yığın izi.
  static void hata(String nerede, Object hata, StackTrace? iz) {
    yaz('HATA ($nerede): $hata');
    if (iz != null) {
      final satirlar = iz.toString().split('\n').where((s) => s.trim().isNotEmpty).take(25);
      for (final s in satirlar) {
        yaz('    $s');
      }
    }
  }
}
