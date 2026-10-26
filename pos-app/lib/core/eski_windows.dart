import 'dart:io';

import 'package:flutter/services.dart';

/// Windows 7 / 8 / 8.1 mi? (Platform.operatingSystemVersion örn.
/// '"Windows 7 Professional" 6.1 (Build 7601: Service Pack 1)').
final bool eskiWindows = () {
  if (!Platform.isWindows) return false;
  final m = RegExp(r'(\d+)\.(\d+)\s*\(Build').firstMatch(Platform.operatingSystemVersion);
  return m != null && int.parse(m.group(1)!) < 10;
}();

/// Eski Windows'ta kök sertifika deposu güncel olmayabilir (Windows Update
/// kapalı kasa bilgisayarları). Uygulama kendi kök listesini (Mozilla,
/// assets/kok-sertifikalar.pem) kullanır; Windows 10+ sistem deposuyla kalır.
Future<void> eskiWindowsHazirla() async {
  if (!eskiWindows) return;
  try {
    final pem = (await rootBundle.load('assets/kok-sertifikalar.pem')).buffer.asUint8List();
    HttpOverrides.global = _KokSertifikalar(pem);
  } catch (_) {
    // Liste okunamazsa sistem deposuyla devam.
  }
}

class _KokSertifikalar extends HttpOverrides {
  _KokSertifikalar(this._pem);
  final List<int> _pem;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(_pem));
}
