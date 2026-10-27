import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bambumpos_pos/ekranlar/ortak.dart';

String duz(List<InlineSpan> s) => s.map((e) => (e as TextSpan).text).join();

void main() {
  test('porsiyon eki ayrılır, metin aynı kalır', () {
    final y = urunAdiParcalari('Köri Soslu Tavuk Yarım Porsiyon');
    expect(y.length, 2);
    expect((y[1] as TextSpan).text, 'Yarım Porsiyon');
    expect(duz(y), 'Köri Soslu Tavuk Yarım Porsiyon');
    final t = urunAdiParcalari('Et Şiş Tam Porsiyon');
    expect((t[1] as TextSpan).text, 'Tam Porsiyon');
    expect((t[1] as TextSpan).style!.color, isNot((y[1] as TextSpan).style!.color));
  });
  test('eşleşmeyen ad tek parça', () {
    expect(urunAdiParcalari('Bardak Çay').length, 1);
    expect(urunAdiParcalari('Tamtam Kek').length, 1);
    expect(urunAdiParcalari('Tam').length, 1);
  });
}
