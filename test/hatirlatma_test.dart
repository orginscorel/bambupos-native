import 'package:bambumpos_personel/core/hatirlatma.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Shift başına 4 hatırlatma; geçmiş anlar ve 7 gün sonrası atlanır', () {
    final simdi = DateTime(2026, 10, 27, 9, 5);
    String iso(DateTime d) => d.toUtc().toIso8601String();
    final l = MesaiHatirlatma.anlar([
      {'id': 1, 'starts_at': iso(DateTime(2026, 10, 27, 9)), 'ends_at': iso(DateTime(2026, 10, 27, 17))}, // sürüyor → 2
      {'id': 2, 'starts_at': iso(DateTime(2026, 10, 28, 9)), 'ends_at': iso(DateTime(2026, 10, 28, 17))}, // 4
      {'id': 3, 'starts_at': iso(DateTime(2026, 11, 10, 9)), 'ends_at': iso(DateTime(2026, 11, 10, 17))}, // 7 gün dışı
    ], simdi);
    expect(l.length, 6);
    expect(l.first.baslik, MesaiHatirlatma.baslikBitiyor10);
    expect(l.first.zaman, DateTime(2026, 10, 27, 16, 50));
    expect(l[2].baslik, MesaiHatirlatma.baslikBasliyor10);
    expect(l[2].govde, contains('09:00'));
    expect(l.map((e) => e.id).toSet().length, 6);
    expect(l.every((e) => e.id > 1600000000 && e.id < 2147483647), isTrue);
    expect(MesaiHatirlatma.baslikMi('Mesain bitti — çıkış QR\'ını okut'), isTrue);
    expect(MesaiHatirlatma.baslikMi('Yeni görev'), isFalse);
  });

  test('Saat dilimli ISO (sunucu +03:00) doğru ana çevrilir; gövdede YEREL saat', () {
    final l = MesaiHatirlatma.anlar([
      {'id': 9, 'starts_at': '2026-10-28T09:00:00+03:00', 'ends_at': '2026-10-28T17:00:00+03:00'},
    ], DateTime.utc(2026, 10, 27));
    expect(l.length, 4);
    expect(l[1].zaman.toUtc(), DateTime.utc(2026, 10, 28, 6));
    final yerel = DateTime.utc(2026, 10, 28, 6).toLocal();
    final hm = '${yerel.hour.toString().padLeft(2, '0')}:${yerel.minute.toString().padLeft(2, '0')}';
    expect(l[1].govde, contains(hm));
  });
}
