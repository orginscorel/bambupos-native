/// Kuruş (minor) → "1.234,50 ₺". Sunucu tutarları her zaman minor tutar.
String para(int minor, {bool simge = true}) {
  final negatif = minor < 0;
  final mutlak = minor.abs();
  final lira = (mutlak ~/ 100).toString();
  final kurus = (mutlak % 100).toString().padLeft(2, '0');

  final b = StringBuffer();
  for (var i = 0; i < lira.length; i++) {
    if (i > 0 && (lira.length - i) % 3 == 0) b.write('.');
    b.write(lira[i]);
  }

  return '${negatif ? '-' : ''}$b,$kurus${simge ? ' ₺' : ''}';
}

/// ISO zamandan bu yana geçen dakika (sunucu saatiyle düzeltilmiş).
int gecenDakika(String? iso, {Duration saatFarki = Duration.zero}) {
  if (iso == null) return 0;
  final t = DateTime.tryParse(iso);
  if (t == null) return 0;
  final simdi = DateTime.now().add(saatFarki);
  return simdi.difference(t).inMinutes.clamp(0, 99999);
}

String sureMetni(int dakika) {
  if (dakika < 60) return '$dakika dk';
  final s = dakika ~/ 60;
  final d = dakika % 60;
  return d == 0 ? '$s sa' : '$s sa $d dk';
}

String saatMetni(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

const _aylar = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const _gunler = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

/// "2026-11-07" → "7 Kasım 2026 Cumartesi" (iş günü başlığı).
String gunBasligi(String? ymd) {
  final t = ymd == null ? null : DateTime.tryParse(ymd);
  if (t == null) return '';
  return '${t.day} ${_aylar[t.month - 1]} ${t.year} ${_gunler[t.weekday - 1]}';
}

/// ISO an → "07 Kas" (yerel saat).
String kisaTarih(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  return '${t.day.toString().padLeft(2, '0')} ${_aylar[t.month - 1].substring(0, 3)}';
}

/// Türkçe büyük/küçük harf duyarsız arama (İ/ı, I/i doğru eşleşsin).
String aramaAnahtari(String s) => s
    .replaceAll('İ', 'i')
    .replaceAll('I', 'ı')
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ş', 's')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');

int tamSayi(Object? v, [int vars = 0]) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? vars,
      _ => vars,
    };
