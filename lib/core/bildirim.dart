import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ortak/ortak.dart';
import 'api.dart';
import 'bicim.dart';
import 'durum.dart';

/// BİLDİRİMLER (yalın): uygulama açıkken 60 sn'de bir /api/v1/notifications
/// yoklanır; yeni okunmamışlar üstte kısa bildirim + titreşim olarak çıkar,
/// "Daha fazla" sekmesinde sayaç görünür. Arka plan / sistem bildirimi YOK
/// (sunucunun patron uygulaması için APNs/FCM gönderimi yok).
class BildirimMerkezi {
  static final okunmamis = ValueNotifier<int>(0);
  static final liste = ValueNotifier<List<Map<String, dynamic>>>(const []);
  static Timer? _zaman;
  static bool _mesgul = false;

  static void basla() {
    unawaited(yokla(ilk: true));
    _zaman?.cancel();
    _zaman = Timer.periodic(const Duration(seconds: 60), (_) => yokla());
  }

  static void durdur() {
    _zaman?.cancel();
    _zaman = null;
  }

  static Future<void> yokla({bool ilk = false}) async {
    if (_mesgul) return;
    _mesgul = true;
    try {
      final r = await Uyg.api.get('/api/v1/notifications');
      if (r is! Map) return;
      final items = r.l('items');
      okunmamis.value = r.i('unread_count');
      liste.value = items;
      final p = Uyg.tercih;
      final sonId = p.getInt('son_bildirim_id') ?? 0;
      if (items.isNotEmpty) {
        await p.setInt('son_bildirim_id', items.map((n) => n.i('id')).reduce((a, b) => a > b ? a : b));
      }
      if (!ilk && sonId > 0) {
        final yeniler = items.where((n) => n.i('id') > sonId && !n.b('read')).take(2);
        for (final n in yeniler) {
          bildir(n.s('title', 'Bildirim'), mesaj: n.s('body'), tur: BildirimTur.bilgi);
          HapticFeedback.mediumImpact();
        }
      }
    } on ApiHata {
      // Sessiz: sonraki turda.
    } finally {
      _mesgul = false;
    }
  }

  static Future<void> okundu(int id) async {
    try {
      await Uyg.api.post('/api/v1/notifications/$id/read');
    } on ApiHata {
      return;
    }
    await yokla(ilk: true);
  }

  static Future<void> hepsiOkundu() async {
    try {
      await Uyg.api.post('/api/v1/notifications/read-all');
    } on ApiHata {
      return;
    }
    await yokla(ilk: true);
  }
}
