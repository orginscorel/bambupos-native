import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Sunucudan dönen hata. Mesaj DOĞRUDAN kullanıcıya gösterilir (Laravel
/// doğrulama mesajları zaten Türkçe).
class ApiHata implements Exception {
  ApiHata(this.kod, this.mesaj, [this.govde]);

  /// HTTP durum kodu; null = sunucuya hiç ulaşılamadı.
  final int? kod;
  final String mesaj;
  final Map<String, dynamic>? govde;

  bool get baglantiYok => kod == null;
  bool get oturumYok => kod == 401;
  bool get yetkiYok => kod == 403;

  @override
  String toString() => mesaj;
}

/// BamBumPOS sunucusu istemcisi.
///
/// Web paneliyle AYNI oturumu kullanır: Laravel oturum çerezi + "beni
/// hatırla" çerezi + cihaz kilidi çerezi diskte kalıcı tutulur; uygulama
/// kapanıp açılınca cihaz eşleşmesi düşmez. Yazma isteklerinde Laravel'in
/// XSRF-TOKEN çerezi X-XSRF-TOKEN başlığına konur.
class Api {
  Api._(this._dio, this._jar, this.taban);

  static const varsayilanTaban = 'https://bambumpos.com';

  final Dio _dio;
  final CookieJar _jar;
  final Uri taban;
  final _uuid = const Uuid();

  /// 401 gelince (oturum düştü / cihaz kaldırıldı) kabuk aktivasyona döner.
  void Function()? oturumDustu;

  static Future<Api> kur({
    String tabanUrl = varsayilanTaban,
    required String kullaniciAjani,
  }) async {
    final dizin = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(
      storage: FileStorage('${dizin.path}${Platform.pathSeparator}cerezler${Platform.pathSeparator}'),
    );

    return _kur(tabanUrl, kullaniciAjani, jar);
  }

  /// Test: istekler gerçek ağa değil verilen bağdaştırıcıya gider.
  @visibleForTesting
  static Api bellekte(HttpClientAdapter bagdastirici, {String tabanUrl = varsayilanTaban}) =>
      _kur(tabanUrl, 'BamBumPOS-Test', CookieJar()).._dio.httpClientAdapter = bagdastirici;

  static Api _kur(String tabanUrl, String kullaniciAjani, CookieJar jar) {
    final dio = Dio(BaseOptions(
      baseUrl: tabanUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      // Durum kodunu kendimiz yorumluyoruz (304, 409, 422 ... anlamlı).
      validateStatus: (_) => true,
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': kullaniciAjani,
      },
    ));

    final api = Api._(dio, jar, Uri.parse(tabanUrl));
    dio.interceptors.add(CookieManager(jar));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
      if (o.method != 'GET') {
        final xsrf = await api._xsrf();
        if (xsrf != null) o.headers['X-XSRF-TOKEN'] = xsrf;
      }
      h.next(o);
    }));
    return api;
  }

  Future<String?> _xsrf() async {
    final cerezler = await _jar.loadForRequest(taban);
    for (final c in cerezler) {
      if (c.name == 'XSRF-TOKEN') return Uri.decodeComponent(c.value);
    }
    return null;
  }

  /// İlk açılışta / çerez süresi dolunca XSRF çerezini tazeler.
  Future<void> _xsrfTazele() async {
    try {
      await _dio.get<dynamic>('/cihaz-aktivasyon',
          options: Options(headers: {'Accept': 'text/html'}, responseType: ResponseType.plain));
    } on DioException {
      // Bağlantı yoksa asıl istek zaten anlamlı hatayı verecek.
    }
  }

  /// Cihaz kaldırıldığında / yeniden eşlemede eski oturumu siler.
  Future<void> cerezleriSil() => _jar.deleteAll();

  String yeniIslemKimligi() => _uuid.v4();

  Future<dynamic> get(String yol, {Map<String, dynamic>? sorgu, Duration? zamanAsimi}) =>
      _istek('GET', yol, sorgu: sorgu, zamanAsimi: zamanAsimi);

  Future<dynamic> post(String yol, [Object? govde, Map<String, String>? basliklar]) =>
      _istek('POST', yol, govde: govde ?? const {}, basliklar: basliklar);

  Future<dynamic> put(String yol, [Object? govde]) => _istek('PUT', yol, govde: govde ?? const {});

  Future<dynamic> delete(String yol, [Object? govde]) => _istek('DELETE', yol, govde: govde);

  /// ETag'li GET: değişmediyse (304) null döner, çağıran elindekini kullanır.
  Future<({dynamic veri, String? etag})?> getEtagli(String yol, String? etag,
      {Map<String, dynamic>? sorgu}) async {
    final r = await _gonder('GET', yol,
        sorgu: sorgu, basliklar: {'If-None-Match': ?etag});
    if (r.statusCode == 304) return null;
    _denetle(r);
    return (veri: r.data, etag: r.headers.value('etag'));
  }

  Future<dynamic> _istek(String yontem, String yol,
      {Map<String, dynamic>? sorgu, Object? govde, Map<String, String>? basliklar, Duration? zamanAsimi}) async {
    var r = await _gonder(yontem, yol, sorgu: sorgu, govde: govde, basliklar: basliklar, zamanAsimi: zamanAsimi);

    // 419 = XSRF çerezi yok/bayat: bir kez tazeleyip yeniden dene.
    if (r.statusCode == 419) {
      await _xsrfTazele();
      r = await _gonder(yontem, yol, sorgu: sorgu, govde: govde, basliklar: basliklar, zamanAsimi: zamanAsimi);
    }

    _denetle(r);
    return r.data;
  }

  Future<Response<dynamic>> _gonder(String yontem, String yol,
      {Map<String, dynamic>? sorgu, Object? govde, Map<String, String>? basliklar, Duration? zamanAsimi}) async {
    try {
      return await _dio.request<dynamic>(
        yol,
        data: govde,
        queryParameters: sorgu,
        options: Options(method: yontem, headers: basliklar, receiveTimeout: zamanAsimi),
      );
    } on DioException catch (e) {
      final zaman = e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout;
      throw ApiHata(null, zaman ? 'Sunucu yanıt vermedi. Bağlantınızı kontrol edin.' : 'Sunucuya ulaşılamıyor. İnternet bağlantısını kontrol edin.');
    }
  }

  void _denetle(Response<dynamic> r) {
    final kod = r.statusCode ?? 0;
    if (kod >= 200 && kod < 300) return;

    final govde = r.data is Map<String, dynamic> ? r.data as Map<String, dynamic> : null;
    if (kod == 401) oturumDustu?.call();
    throw ApiHata(kod, _mesaj(kod, govde), govde);
  }

  static String _mesaj(int kod, Map<String, dynamic>? govde) {
    final hatalar = govde?['errors'];
    if (hatalar is Map && hatalar.isNotEmpty) {
      final ilk = hatalar.values.first;
      if (ilk is List && ilk.isNotEmpty) return ilk.first.toString();
    }
    final m = govde?['message']?.toString();
    if (m != null && m.isNotEmpty && m != 'Server Error') return m;
    return switch (kod) {
      401 => 'Cihaz oturumu sona erdi.',
      403 => 'Bu işlem için yetkiniz yok.',
      404 => 'Kayıt bulunamadı.',
      409 => 'Kayıt başka bir cihazda değişti. Ekran yenilendi, tekrar deneyin.',
      423 => 'Bu cihaz kilitli. Yöneticinize başvurun.',
      429 => 'Çok fazla istek. Biraz sonra tekrar deneyin.',
      >= 500 => 'Sunucuda geçici bir sorun var. Birazdan tekrar deneyin.',
      _ => 'İşlem tamamlanamadı ($kod).',
    };
  }
}
