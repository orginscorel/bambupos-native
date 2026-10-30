import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bambumpos_pos/core/api.dart';
import 'package:bambumpos_pos/core/durum.dart';
import 'package:bambumpos_pos/core/kalici_dosya.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yol → sıradaki yanıtlar. `null` kod = bağlantı hatası. Liste biterse son yanıt tekrarlanır.
class _Sunucu implements HttpClientAdapter {
  _Sunucu(this.yanitlar);
  final Map<String, List<(int?, Object?)>> yanitlar;
  final istekler = <String>[];

  int sayi(String yol) => istekler.where((i) => i == yol).length;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? _) async {
    final yol = o.uri.path;
    istekler.add(yol);
    final liste = yanitlar[yol];
    if (liste == null || liste.isEmpty) return ResponseBody.fromString('{}', 200, headers: _json);
    final (kod, govde) = liste.length > 1 ? liste.removeAt(0) : liste.first;
    if (kod == null) throw DioException.connectionError(requestOptions: o, reason: 'test: ağ yok');
    return ResponseBody.fromString(govde == null ? '' : jsonEncode(govde), kod, headers: _json);
  }

  static final _json = {Headers.contentTypeHeader: ['application/json']};

  @override
  void close({bool force = false}) {}
}

const _oturum = {
  'cihaz': {'id': 58, 'ad': 'KASA', 'istasyon': 'kasa', 'para': true, 'kilitli': false},
  'isletme': {'id': 15, 'ad': 'Test', 'kod': 'ABC123'},
  'operator': null,
  'yetkiler': <String>[],
};

final _anahtar = 'K' * 64;

/// Gerçek dosya G/Ç'si olay döngüsünün dışında biter: koşul tutana kadar bekle.
Future<void> _bekle(bool Function() kosul, {int ms = 3000}) async {
  final son = DateTime.now().add(Duration(milliseconds: ms));
  while (!kosul() && DateTime.now().isBefore(son)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _biraz() => Future<void>.delayed(const Duration(milliseconds: 250));

Future<(UygulamaDurumu, _Sunucu, String)> _kur(Map<String, List<(int?, Object?)>> yanitlar, {bool anahtarVar = true}) async {
  SharedPreferences.setMockInitialValues({});
  final dizin = Directory.systemTemp.createTempSync('bbpos_kurtarma').path;
  if (anahtarVar) await KurtarmaDeposu(dizin).yaz(KurtarmaAnahtari(58, _anahtar));
  final s = _Sunucu(yanitlar);
  final d = UygulamaDurumu.test(Api.bellekte(s), await SharedPreferences.getInstance(), dizin);
  d.kurtarmaBekleme = const Duration(milliseconds: 300);
  return (d, s, dizin);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AtomikDosya', () {
    late String yol;
    setUp(() => yol = '${Directory.systemTemp.createTempSync('bbpos_atomik').path}/bambumpos.com');

    test('yazınca asıl + .bak oluşur, .tmp kalmaz', () async {
      await AtomikDosya.yaz(yol, '{"a":1}');
      expect(File(yol).readAsStringSync(), '{"a":1}');
      expect(File('$yol.bak').readAsStringSync(), '{"a":1}');
      expect(File('$yol.tmp').existsSync(), isFalse);
    });

    test('asıl dosya BOŞ kalmışsa (yazarken kapandı) .bak okunur ve hiçbir şey silinmez', () async {
      await AtomikDosya.yaz(yol, '{"oturum":"iyi"}');
      File(yol).writeAsStringSync(''); // FileStorage'ın kesilen yazması
      expect(await AtomikDosya.oku(yol), '{"oturum":"iyi"}');
      expect(File(yol).existsSync(), isTrue);
      expect(File('$yol.bak').readAsStringSync(), '{"oturum":"iyi"}');
    });

    test('asıl dosya yarım JSON ise .bak okunur', () async {
      await AtomikDosya.yaz(yol, '{"oturum":"iyi"}');
      File(yol).writeAsStringSync('{"oturum":"iy');
      expect(await AtomikDosya.oku(yol), '{"oturum":"iyi"}');
    });

    test('asıl dosya yoksa .bak; .bak da yoksa taşınamamış .tmp', () async {
      await AtomikDosya.yaz(yol, '[1,2]');
      File(yol).deleteSync();
      expect(await AtomikDosya.oku(yol), '[1,2]');
      File('$yol.bak').renameSync('$yol.tmp');
      expect(await AtomikDosya.oku(yol), '[1,2]');
      File('$yol.tmp').deleteSync();
      expect(await AtomikDosya.oku(yol), isNull);
    });

    test('art arda eşzamanlı yazmalar en son içerikte biter', () async {
      await Future.wait([for (var i = 0; i < 20; i++) AtomikDosya.yaz(yol, '{"i":$i}')]);
      expect(await AtomikDosya.oku(yol), '{"i":19}');
      expect(File('$yol.bak').readAsStringSync(), '{"i":19}');
    });
  });

  group('DayanikliCerezDeposu', () {
    final uri = Uri.parse('https://bambumpos.com/');
    List<Cookie> cerezler() => [
          Cookie('laravel_session', 'oturum-degeri')..expires = DateTime.now().add(const Duration(days: 365)),
          Cookie('XSRF-TOKEN', 'xsrf')..expires = DateTime.now().add(const Duration(hours: 2)),
        ];

    test('çerez dosyası boş kalınca yeni açılışta çerezler .bak dosyasından gelir', () async {
      final kok = '${Directory.systemTemp.createTempSync('bbpos_cerez').path}/cerezler/';
      final depo = DayanikliCerezDeposu(kok);
      final jar = PersistCookieJar(storage: depo, deleteHostCookiesWhenLoadFailed: false);
      await jar.saveFromResponse(uri, cerezler());

      // Uygulama yazarken kapandı: host dosyası ve dizin dosyası boş.
      File('${depo.gecerliDizin}bambumpos.com').writeAsStringSync('');
      File('${depo.gecerliDizin}.index').writeAsStringSync('');

      final yeni = PersistCookieJar(storage: DayanikliCerezDeposu(kok), deleteHostCookiesWhenLoadFailed: false);
      final gelen = await yeni.loadForRequest(uri);
      expect(gelen.map((c) => c.name), containsAll(['laravel_session', 'XSRF-TOKEN']));
    });

    test('eski sürümün (FileStorage) yazdığı çerezleri aynen okur', () async {
      final kok = '${Directory.systemTemp.createTempSync('bbpos_cerez_eski').path}/cerezler/';
      final eski = PersistCookieJar(storage: FileStorage(kok));
      await eski.saveFromResponse(uri, cerezler());

      final yeni = PersistCookieJar(storage: DayanikliCerezDeposu(kok), deleteHostCookiesWhenLoadFailed: false);
      final gelen = await yeni.loadForRequest(uri);
      expect(gelen.map((c) => c.name), containsAll(['laravel_session', 'XSRF-TOKEN']));
    });

    test('bilinçli silme (cerezleriSil) her şeyi siler', () async {
      final kok = '${Directory.systemTemp.createTempSync('bbpos_cerez_sil').path}/cerezler/';
      final jar = PersistCookieJar(storage: DayanikliCerezDeposu(kok), deleteHostCookiesWhenLoadFailed: false);
      await jar.saveFromResponse(uri, cerezler());
      await jar.deleteAll();
      final yeni = PersistCookieJar(storage: DayanikliCerezDeposu(kok), deleteHostCookiesWhenLoadFailed: false);
      expect(await yeni.loadForRequest(uri), isEmpty);
    });
  });

  group('KurtarmaDeposu', () {
    test('bozuk anahtar dosyasında .bak kullanılır', () async {
      final dizin = Directory.systemTemp.createTempSync('bbpos_anahtar').path;
      final d = KurtarmaDeposu(dizin);
      await d.yaz(KurtarmaAnahtari(7, _anahtar));
      File(d.yol).writeAsStringSync('{"terminal_id":7,"anah');
      final a = await d.oku();
      expect(a?.terminalId, 7);
      expect(a?.anahtar, _anahtar);
    });
  });

  group('Kurtarma akışı', () {
    test('401 → kurtar başarılı → aktivasyona GİDİLMEZ, PIN ekranı gelir', () async {
      final (d, s, _) = await _kur({
        '/api/v1/uygulama/oturum': [(401, {'message': 'Unauthenticated.'}), (200, _oturum)],
        '/api/v1/uygulama/kurtar': [(200, {'ok': true})],
      });
      final asamalar = <Asama>[];
      d.addListener(() => asamalar.add(d.asama));

      await d.oturumuYenile(ilk: true);
      await _bekle(() => d.asama == Asama.pin);
      await _biraz();

      expect(s.sayi('/api/v1/uygulama/kurtar'), 1);
      expect(asamalar, isNot(contains(Asama.aktivasyon)));
      expect(d.asama, Asama.pin);
      expect((await d.kurtarmaAnahtari())?.anahtar, _anahtar, reason: 'anahtar korunur');
    });

    test('kurtar 422 → aktivasyon ekranı ve anahtar silinir', () async {
      final (d, s, _) = await _kur({
        '/api/v1/uygulama/oturum': [(401, {'message': 'Unauthenticated.'})],
        '/api/v1/uygulama/kurtar': [(422, {'message': 'Cihaz doğrulanamadı.'})],
      });
      await d.oturumuYenile(ilk: true);
      await _bekle(() => d.asama == Asama.aktivasyon);
      await _biraz();

      expect(s.sayi('/api/v1/uygulama/kurtar'), 1);
      expect(d.asama, Asama.aktivasyon);
      expect(await d.kurtarmaAnahtari(), isNull);
    });

    test('kurtar sırasında ağ yok → bağlantı bekleniyor, anahtar korunur, sonra kendiliğinden kurtarır', () async {
      final (d, s, _) = await _kur({
        '/api/v1/uygulama/oturum': [(401, {}), (401, {}), (200, _oturum)],
        '/api/v1/uygulama/kurtar': [(null, null), (200, {'ok': true})],
      });
      final asamalar = <Asama>[];
      d.addListener(() => asamalar.add(d.asama));

      await d.oturumuYenile(ilk: true);
      await _bekle(() => d.asama == Asama.baglantiYok);
      expect(d.asama, Asama.baglantiYok);
      expect((await d.kurtarmaAnahtari())?.anahtar, _anahtar);

      await _bekle(() => d.asama == Asama.pin);
      expect(s.sayi('/api/v1/uygulama/kurtar'), 2);
      expect(d.asama, Asama.pin);
      expect(asamalar, isNot(contains(Asama.aktivasyon)));
    });

    test('kilitli cihaz (423) → aktivasyona gidilmez, anahtar korunur', () async {
      final (d, _, _) = await _kur({
        '/api/v1/uygulama/oturum': [(401, {})],
        '/api/v1/uygulama/kurtar': [(423, {'message': 'Bu cihaz yönetici tarafından kilitlendi.'})],
      });
      d.kurtarmaBekleme = const Duration(hours: 1);
      await d.oturumuYenile(ilk: true);
      await _bekle(() => d.asama == Asama.baglantiYok);
      expect(d.asama, Asama.baglantiYok);
      expect(d.sonHata, contains('kilitlendi'));
      expect(await d.kurtarmaAnahtari(), isNotNull);
      d.dispose();
    });

    test('anahtar yoksa 401 eskisi gibi aktivasyona gider', () async {
      final (d, s, _) = await _kur({
        '/api/v1/uygulama/oturum': [(401, {})],
      }, anahtarVar: false);
      await d.oturumuYenile(ilk: true);
      await _bekle(() => d.asama == Asama.aktivasyon);
      expect(s.sayi('/api/v1/uygulama/kurtar'), 0);
      expect(d.asama, Asama.aktivasyon);
    });

    test('403 (yönetici cihazı kaldırdı) → aktivasyon + anahtar silinir, kurtarma denenmez', () async {
      final (d, s, _) = await _kur({
        '/api/v1/uygulama/oturum': [(403, {'message': 'Cihaz kaydı bulunamadı.'})],
      });
      await d.oturumuYenile(ilk: true);
      await _bekle(() => d.asama == Asama.aktivasyon);
      expect(s.sayi('/api/v1/uygulama/kurtar'), 0);
      expect(d.asama, Asama.aktivasyon);
      expect(await d.kurtarmaAnahtari(), isNull);
    });

    test('aynı anda gelen birden çok 401 tek kurtarma isteği yapar', () async {
      final (d, s, _) = await _kur({
        '/api/v1/uygulama/oturum': [(401, {}), (200, _oturum)],
        '/terminal/heartbeat': [(401, {})],
        '/api/v1/uygulama/kurtar': [(200, {'ok': true})],
      });
      await Future.wait([
        d.oturumuYenile(ilk: true),
        d.api.post('/terminal/heartbeat').then((_) {}, onError: (_) {}),
        d.api.post('/terminal/heartbeat').then((_) {}, onError: (_) {}),
      ]);
      await _bekle(() => d.asama == Asama.pin);
      await _biraz();
      expect(s.sayi('/api/v1/uygulama/kurtar'), 1);
      expect(d.asama, Asama.pin);
    });

    test('anahtarı olmayan oturumlu cihaz bir kez anahtar alır ve diske yazar', () async {
      final (d, s, dizin) = await _kur({
        '/api/v1/uygulama/oturum': [(200, _oturum)],
        '/api/v1/uygulama/kurtarma-anahtari': [(200, {'terminal_id': 58, 'anahtar': 'Y' * 64})],
      }, anahtarVar: false);
      await d.oturumuYenile(ilk: true);
      await _bekle(() => File('$dizin/kurtarma.json').existsSync());
      await _biraz();
      await d.oturumuYenile();
      await _biraz();

      expect(s.sayi('/api/v1/uygulama/kurtarma-anahtari'), 1);
      final a = await d.kurtarmaAnahtari();
      expect(a?.terminalId, 58);
      expect(a?.anahtar, 'Y' * 64);
    });

    test('anahtarı başka terminale aitse (yeniden aktive edilmiş) yenisi alınır', () async {
      final (d, s, dizin) = await _kur({
        '/api/v1/uygulama/oturum': [(200, _oturum)],
        '/api/v1/uygulama/kurtarma-anahtari': [(200, {'terminal_id': 58, 'anahtar': 'Z' * 64})],
      }, anahtarVar: false);
      await KurtarmaDeposu(dizin).yaz(KurtarmaAnahtari(12, _anahtar));
      await d.oturumuYenile(ilk: true);
      await _bekle(() => s.sayi('/api/v1/uygulama/kurtarma-anahtari') == 1);
      await _biraz();
      expect(s.sayi('/api/v1/uygulama/kurtarma-anahtari'), 1);
      expect((await d.kurtarmaAnahtari())?.terminalId, 58);
    });
  });
}
