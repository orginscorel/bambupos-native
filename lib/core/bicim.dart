import 'package:intl/intl.dart';

/// Türkçe sayı / para / tarih biçimleri (tr_TR). Sunucu tutarları KURUŞ
/// (`*_minor`) gönderir; ekrana TL olarak yazılır.
abstract final class Bicim {
  static final _para = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  static final _paraTam = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
  static final _sayi = NumberFormat.decimalPattern('tr_TR');
  static final _ondalik = NumberFormat('#,##0.#', 'tr_TR');
  static final _gunAy = DateFormat('d MMMM', 'tr_TR');
  static final _gunAyKisa = DateFormat('d MMM', 'tr_TR');
  static final _gunAyYil = DateFormat('d MMMM y', 'tr_TR');
  static final _saat = DateFormat('HH:mm', 'tr_TR');
  static final _tarihSaat = DateFormat('d MMM HH:mm', 'tr_TR');
  static final _gunAdi = DateFormat('EEEE', 'tr_TR');

  /// Kuruş → "₺1.234,50". [tam] = kuruş haneleri yazılmaz ("₺1.235").
  static String para(num? kurus, {bool tam = false}) {
    final tl = (kurus ?? 0) / 100;
    return (tam ? _paraTam : _para).format(tl);
  }

  /// Kuruş → kısa para: ₺950 · ₺12,4 B · ₺1,2 Mn (grafik ekseni / dar alan).
  static String paraKisa(num? kurus) {
    final tl = (kurus ?? 0) / 100;
    final m = tl.abs();
    String k(double v) => _ondalik.format(v);
    if (m >= 1000000) return '₺${k(tl / 1000000)} Mn';
    if (m >= 10000) return '₺${k(tl / 1000)} B';
    return _paraTam.format(tl);
  }

  static String sayi(num? n) => _sayi.format(n ?? 0);

  static String ondalik(num? n) => _ondalik.format(n ?? 0);

  /// 12.5 → "%12,5"
  static String yuzde(num? n) => '%${_ondalik.format(n ?? 0)}';

  static String dakika(num? dk) {
    final m = (dk ?? 0).round();
    final s = m ~/ 60;
    final k = m % 60;
    if (s > 0 && k > 0) return '$s sa $k dk';
    if (s > 0) return '$s sa';
    return '$k dk';
  }

  static String gunAy(DateTime d) => _gunAy.format(d);
  static String gunAyKisa(DateTime d) => _gunAyKisa.format(d);
  static String gunAyYil(DateTime d) => _gunAyYil.format(d);
  static String saat(DateTime d) => _saat.format(d.toLocal());
  static String tarihSaat(DateTime d) => _tarihSaat.format(d.toLocal());
  static String gunAdi(DateTime d) => _gunAdi.format(d);

  /// Y-m-d
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "2026-10-27" → DateTime (yerel gün, saat 00:00).
  static DateTime? gunCoz(String? s) {
    if (s == null || s.length < 10) return null;
    final d = DateTime.tryParse(s.substring(0, 10));
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// İki tarih arası aralık yazısı: "27 Ekim" · "21 – 27 Ekim" · "28 Eyl – 3 Eki".
  static String aralik(DateTime a, DateTime b) {
    if (a.year == b.year && a.month == b.month && a.day == b.day) return gunAy(a);
    if (a.year == b.year && a.month == b.month) return '${a.day} – ${gunAy(b)}';
    return '${gunAyKisa(a)} – ${gunAyKisa(b)}';
  }

  static const gunKisa = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
}

/// JSON gezinme yardımcıları — sunucu alanı yoksa/biçimi farklıysa çökmez.
extension JsonX on Map {
  Map<String, dynamic> m(String k) {
    final v = this[k];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> l(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int i(String k) {
    final v = this[k];
    if (v is num) return v.round();
    if (v is String) return num.tryParse(v)?.round() ?? 0;
    return 0;
  }

  double? d(String k) {
    final v = this[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  String s(String k, [String yoksa = '']) {
    final v = this[k];
    if (v == null) return yoksa;
    final t = v.toString();
    return t.isEmpty ? yoksa : t;
  }

  bool b(String k) => this[k] == true || this[k] == 1;
}
