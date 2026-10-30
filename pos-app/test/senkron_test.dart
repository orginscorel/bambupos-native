import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/senkron_merkezi.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// /api/v1/orders/degisim taklidi: sıradaki yanıtları verir, istekleri kaydeder.
class _Sunucu implements HttpClientAdapter {
  _Sunucu(this.yanitlar);
  final List<(int, Object?)> yanitlar;
  final istekler = <Uri>[];
  final _bekleyen = Completer<void>();

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    istekler.add(o.uri);
    if (yanitlar.isEmpty) {
      await _bekleyen.future; // uzun yoklama: test bitene kadar asılı kalır
      return ResponseBody.fromString('', 204);
    }
    final (kod, govde) = yanitlar.removeAt(0);
    return ResponseBody.fromString(govde == null ? '' : jsonEncode(govde), kod,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ilk çağrı imleç alır, değişim haberi yayınlanır, imleç ilerler', () async {
    final s = _Sunucu([
      (200, {'imlec': 100, 'ilk': true, 'degisen_adisyonlar': [], 'olaylar': []}),
      (200, {
        'imlec': 103,
        'degisen_adisyonlar': [7, 9],
        'olaylar': [
          {'id': 101, 'order_id': 7, 'tur': 'merged_into', 'hedef_adisyon_id': 9},
          {'id': 102, 'order_id': 9, 'tur': 'merged_from'},
        ],
        'tasma': false,
      }),
    ]);
    final m = SenkronMerkezi(Api.bellekte(s));
    final gelen = <SenkronDegisimi>[];
    final abone = m.degisimler.listen(gelen.add);
    m.baslat();
    await pumpEventQueue(times: 50);

    expect(gelen, hasLength(1));
    expect(gelen.single.adisyonlar, {7, 9});
    expect(gelen.single.birlesmeHedefi(7), 9);
    expect(gelen.single.birlesmeHedefi(9), isNull);
    expect(gelen.single.ilgilendirir(9), isTrue);
    expect(gelen.single.ilgilendirir(5), isFalse);
    expect(s.istekler[0].queryParameters.containsKey('imlec'), isFalse);
    expect(s.istekler[1].queryParameters['imlec'], '100');
    expect(s.istekler[2].queryParameters['imlec'], '103');

    await abone.cancel();
    m.dispose();
  });

  test('imleç sıfırlanınca "tam" haber gider', () async {
    final s = _Sunucu([
      (200, {'imlec': 50, 'ilk': true}),
      (200, {'imlec': 3, 'sifirlandi': true, 'degisen_adisyonlar': [], 'olaylar': []}),
    ]);
    final m = SenkronMerkezi(Api.bellekte(s));
    final gelen = <SenkronDegisimi>[];
    final abone = m.degisimler.listen(gelen.add);
    m.baslat();
    await pumpEventQueue(times: 50);
    expect(gelen.single.tam, isTrue);
    expect(gelen.single.ilgilendirir(123), isTrue);
    expect(s.istekler.last.queryParameters['imlec'], '3');
    await abone.cancel();
    m.dispose();
  });

  test('eski sunucu (404): sessizce devre dışı, yerel haberler sürer', () async {
    final s = _Sunucu([(404, {'message': 'Not Found'})]);
    final m = SenkronMerkezi(Api.bellekte(s));
    final gelen = <SenkronDegisimi>[];
    final abone = m.degisimler.listen(gelen.add);
    m.baslat();
    await pumpEventQueue(times: 50);
    expect(m.devreDisi, isTrue);
    expect(s.istekler, hasLength(1), reason: 'bir daha denenmez');

    m.yerelDegisim(adisyonlar: [42]);
    await pumpEventQueue();
    expect(gelen.single.yerel, isTrue);
    expect(gelen.single.adisyonlar, {42});
    await abone.cancel();
    m.dispose();
  });

  test('sayaçlı başlat/durdur: kabuk yeniden kurulurken döngü düşmez', () async {
    final s = _Sunucu([(200, {'imlec': 1, 'ilk': true})]);
    final m = SenkronMerkezi(Api.bellekte(s));
    m.baslat(); // eski kabuk
    m.baslat(); // yeni kabuk (eskinin dispose'undan önce)
    m.durdur(); // eski kabuk gider
    await pumpEventQueue(times: 50);
    expect(s.istekler.length, greaterThanOrEqualTo(2), reason: 'döngü sürüyor');
    m.dispose();
  });
}
