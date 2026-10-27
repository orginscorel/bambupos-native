import 'package:bambumpos_patron/core/api.dart';
import 'package:bambumpos_patron/core/bicim.dart';
import 'package:bambumpos_patron/ekranlar/rapor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  test('para: kuruş → Türk lirası', () {
    expect(Bicim.para(123450), '₺1.234,50');
    expect(Bicim.para(0), '₺0,00');
    expect(Bicim.para(-9900), '-₺99,00');
    expect(Bicim.para(12345678, tam: true), '₺123.457');
  });

  test('kısa para ve sayılar', () {
    expect(Bicim.paraKisa(95000), '₺950');
    expect(Bicim.paraKisa(1240000), '₺12,4 B');
    expect(Bicim.paraKisa(123000000), '₺1,2 Mn');
    expect(Bicim.sayi(1234567), '1.234.567');
    expect(Bicim.yuzde(12.5), '%12,5');
    expect(Bicim.dakika(135), '2 sa 15 dk');
    expect(Bicim.dakika(40), '40 dk');
  });

  test('tarih aralığı', () {
    expect(Bicim.aralik(DateTime(2026, 10, 27), DateTime(2026, 10, 27)), '27 Ekim');
    expect(Bicim.aralik(DateTime(2026, 10, 21), DateTime(2026, 10, 27)), '21 – 27 Ekim');
    expect(Bicim.iso(DateTime(2026, 3, 5)), '2026-03-05');
  });

  test('rapor hücreleri', () {
    expect(hucreYaz('revenue_minor', 250000), '₺2.500,00');
    expect(hucreYaz('qty', 1200), '1.200');
    expect(hucreYaz('share', 33.3), '%33,3');
    expect(hucreYaz('hour', 9), '09:00');
    expect(hucreYaz('after_served', true), 'Evet');
    expect(hucreYaz('name', null), '—');
    expect(hucreYaz('date', '2026-10-27'), '27 Ekim');
  });

  test('429 bekleme süresi', () {
    expect(Api.beklemeCoz('42', null), const Duration(seconds: 42));
    expect(Api.beklemeCoz(null, 'Çok fazla istek. 120 sn sonra tekrar deneyin.'), const Duration(seconds: 120));
    expect(Api.beklemeCoz(null, null), const Duration(seconds: 30));
    expect(Api.beklemeCoz('1', null), const Duration(seconds: 5));
  });
}
