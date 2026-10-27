import 'dart:convert';
import 'dart:typed_data';

import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/bildirim_merkezi.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Zil implements HttpClientAdapter {
  List<Map<String, dynamic>> liste = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async =>
      ResponseBody.fromString(
        jsonEncode({'unread_count': liste.where((n) => n['read'] != true).length, 'items': liste}),
        200,
        headers: {Headers.contentTypeHeader: ['application/json']},
      );

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _n(int id, String tur, {bool okundu = false}) =>
    {'id': id, 'type': tur, 'title': 'B$id', 'body': null, 'url': '/panel/siparisler', 'read': okundu};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ilk yüklemede baloncuk yok; yeni bildirim baloncuk olur, sipariş olmaz', () async {
    SharedPreferences.setMockInitialValues({});
    final zil = _Zil()..liste = [_n(1, 'service_call')];
    final m = BildirimMerkezi(Api.bellekte(zil), await SharedPreferences.getInstance());

    await m.yenile();
    expect(m.okunmamis, 1);
    expect(m.baloncuklar, isEmpty, reason: 'ilk yükleme çalmaz / baloncuk açmaz');

    zil.liste = [_n(3, 'order_placed'), _n(2, 'item_ready'), ...zil.liste];
    await m.yenile();
    expect(m.baloncuklar.map((b) => b.tur), ['item_ready'], reason: 'order_placed baloncuksuz (web POS gibi)');

    // Aynı bildirim ikinci yoklamada yeniden çıkmaz.
    await m.yenile();
    expect(m.baloncuklar.length, 1);
  });

  test('kalıcı tip (SLA) ilk yüklemede de gösterilir', () async {
    SharedPreferences.setMockInitialValues({});
    final zil = _Zil()..liste = [_n(9, 'delivery_sla_breach')];
    final m = BildirimMerkezi(Api.bellekte(zil), await SharedPreferences.getInstance());
    await m.yenile();
    expect(m.baloncuklar.single.kalici, isTrue);
  });
}
