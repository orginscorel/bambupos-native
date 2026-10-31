import 'package:flutter/widgets.dart';

/// PERSONEL DÜŞÜNCE AÇIK SAYFALAR KAPANIR (1.2.45, Roka bildirimi).
///
/// Adisyon / ödeme ekranları ve pencereler kök gezginin ÜSTÜNE açılır;
/// aşama "çalışma"dan çıkınca (başka cihazda giriş, 3 dk boşta kilit, çıkış,
/// aktivasyona düşme) alttaki ekran PIN'e dönse bile üstteki sayfa onu
/// örtüyordu: personel adisyonda takılı kalıyor, eklediği her ürün
/// reddediliyordu. Bu bekçi aşama çalışmadan çıktığı anda kök gezgini ilk
/// sayfaya kadar boşaltır.
class GezginTemizleyici {
  GezginTemizleyici({required this.dinle, required this.calismada, required this.gezgin}) {
    _onceki = calismada();
    dinle.addListener(_degisti);
  }

  final Listenable dinle;
  final bool Function() calismada;
  final GlobalKey<NavigatorState> gezgin;
  late bool _onceki;

  void _degisti() {
    final simdi = calismada();
    final dustu = _onceki && !simdi;
    _onceki = simdi;
    if (!dustu) return;
    // Bildirim bir derleme sırasında gelmiş olabilir: kare bitince boşalt.
    WidgetsBinding.instance.addPostFrameCallback((_) => temizle());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @visibleForTesting
  void temizle() {
    final g = gezgin.currentState;
    if (g == null || calismada()) return;
    g.popUntil((r) => r.isFirst);
  }

  void dispose() => dinle.removeListener(_degisti);
}
