import 'package:flutter_test/flutter_test.dart';
import 'package:bambumpos_pos/core/bicim.dart';
import 'package:bambumpos_pos/core/modeller.dart';
import 'package:bambumpos_pos/ekranlar/adet_kartlari.dart';

void main() {
  const s1 = '2026-10-30T11:02:10+00:00';
  const s2 = '2026-10-30T11:20:00+00:00';

  test('her ekleme saat + personel; aynı dakika/kişi birleşir', () {
    final k = Kalem({
      'id': 1,
      'qty': 3,
      'dokum': [
        {'saat': s1, 'kisi': 'Ahmet Yılmaz', 'adet': 1, 'devir': false},
        {'saat': s1, 'kisi': 'Ahmet Yılmaz', 'adet': 1, 'devir': false},
        {'saat': s2, 'kisi': 'Ayşe Kaya', 'adet': 1, 'devir': false},
      ],
    });
    expect(ekleyenOzeti(k), '2× ${saatMetni(s1)} Ahmet Yılmaz · ${saatMetni(s2)} Ayşe Kaya');
  });

  test('tek ekleme: adet öneki yok', () {
    final k = Kalem({
      'id': 2,
      'qty': 2,
      'dokum': [
        {'saat': s1, 'kisi': 'Ahmet Yılmaz', 'adet': 2, 'devir': false},
      ],
    });
    expect(ekleyenOzeti(k), '${saatMetni(s1)} Ahmet Yılmaz');
  });

  test('döküm yoksa boş', () {
    expect(ekleyenOzeti(Kalem({'id': 3, 'qty': 1})), '');
  });
}
