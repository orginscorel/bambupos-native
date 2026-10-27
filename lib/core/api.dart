import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Sunucudan dönen hata. Mesaj DOĞRUDAN kullanıcıya gösterilir (Laravel
/// doğrulama mesajları zaten Türkçe).
class ApiHata implements Exception {
  ApiHata(this.kod, this.mesaj, [this.govde, this.bekle]);

  /// HTTP durum kodu; null = sunucuya hiç ulaşılamadı.
  final int? kod;
  final String mesaj;
  final Map<String, dynamic>? govde;

  /// 429'da sunucunun önerdiği bekleme (Retry-After ya da mesajdaki "N sn").
  final Duration? bekle;

  bool get baglantiYok => kod == null;
  bool get oturumYok => kod == 401;
  bool get yetkiYok => kod == 403;
  bool get cokIstek => kod == 429;

  /// Sahip konsoldan bu telefonun eşlemesini kaldırdı.
  bool get eslesmeKaldirildi => kod == 401 && govde?['eslesme'] == 'kaldirildi';

  @override
  String toString() => mesaj;
}

/// Sunucuya son ulaşma durumu.
final ValueNotifier<bool> sunucuBagli = ValueNotifier<bool>(true);

/// BamBumPOS Patron sunucu istemcisi (patron.bambumpos.com).
///
/// Personel uygulamasıyla AYNI desen: Laravel oturum çerezi + "beni hatırla"
/// çerezi diskte kalıcı tutulur; uygulama kapanıp açılınca eşleme düşmez.
/// Yazma isteklerinde Laravel'in XSRF-TOKEN çerezi X-XSRF-TOKEN başlığına
/// konur; 419 gelirse /eslestir sayfası çağrılıp çerez tazelenir ve istek
/// bir kez yeniden denenir.
class Api {
  Api._(this._dio, this._jar, this.taban);

  static const varsayilanTaban = 'https://patron.bambumpos.com';

  final Dio _dio;
  final CookieJar _jar;
  final Uri taban;

  /// 401 gelince (oturum düştü / eşleme kaldırıldı) uygulama eşleme ekranına döner.
  void Function(ApiHata hata)? oturumDustu;

  static Future<Api> kur({String tabanUrl = varsayilanTaban, required String kullaniciAjani}) async {
    final dizin = await getApplicationSupportDirectory();
    final jar = PersistCookieJar(
      storage: FileStorage('${dizin.path}${Platform.pathSeparator}cerezler${Platform.pathSeparator}'),
    );
    return _kur(tabanUrl, kullaniciAjani, jar);
  }

  /// Test: istekler gerçek ağa değil verilen bağdaştırıcıya gider.
  @visibleForTesting
  static Api bellekte(HttpClientAdapter bagdastirici, {String tabanUrl = varsayilanTaban}) =>
      _kur(tabanUrl, 'BamBumPOS-Patron-Test', CookieJar()).._dio.httpClientAdapter = bagdastirici;

  static Api _kur(String tabanUrl, String kullaniciAjani, CookieJar jar) {
    final dio = Dio(BaseOptions(
      baseUrl: tabanUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(seconds: 20),
      responseType: ResponseType.json,
      // Durum kodunu kendimiz yorumluyoruz (401, 419, 422, 429 … anlamlı).
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
      await _dio.get<dynamic>('/eslestir',
          options: Options(headers: {'Accept': 'text/html'}, responseType: ResponseType.plain, followRedirects: false));
    } on DioException {
      // Bağlantı yoksa asıl istek zaten anlamlı hatayı verecek.
    }
  }

  /// Eşleme kaldırıldığında eski oturum çerezlerini siler.
  Future<void> cerezleriSil() => _jar.deleteAll();

  Future<dynamic> get(String yol, {Map<String, dynamic>? sorgu, Duration? zamanAsimi}) =>
      _istek('GET', yol, sorgu: sorgu, zamanAsimi: zamanAsimi);

  Future<dynamic> post(String yol, [Object? govde]) => _istek('POST', yol, govde: govde ?? const {});

  Future<dynamic> _istek(String yontem, String yol, {Map<String, dynamic>? sorgu, Object? govde, Duration? zamanAsimi}) async {
    var r = await _gonder(yontem, yol, sorgu: sorgu, govde: govde, zamanAsimi: zamanAsimi);

    // 419 = XSRF çerezi yok/bayat: bir kez tazeleyip yeniden dene.
    if (r.statusCode == 419) {
      await _xsrfTazele();
      r = await _gonder(yontem, yol, sorgu: sorgu, govde: govde, zamanAsimi: zamanAsimi);
    }

    _denetle(r);
    return r.data;
  }

  Future<Response<dynamic>> _gonder(String yontem, String yol,
      {Map<String, dynamic>? sorgu, Object? govde, Duration? zamanAsimi}) async {
    try {
      final r = await _dio.request<dynamic>(
        yol,
        data: govde,
        queryParameters: sorgu,
        options: Options(method: yontem, receiveTimeout: zamanAsimi),
      );
      sunucuBagli.value = true;
      return r;
    } on DioException catch (e) {
      sunucuBagli.value = false;
      final zaman = e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout;
      throw ApiHata(null, zaman ? 'Sunucu yanıt vermedi. Bağlantınızı kontrol edin.' : 'Sunucuya ulaşılamıyor. İnternet bağlantısını kontrol edin.');
    }
  }

  void _denetle(Response<dynamic> r) {
    final kod = r.statusCode ?? 0;
    if (kod >= 200 && kod < 300) return;

    final govde = r.data is Map ? Map<String, dynamic>.from(r.data as Map) : null;
    Duration? bekle;
    if (kod == 429) bekle = beklemeCoz(r.headers.value('retry-after'), govde?['message']?.toString());
    final hata = ApiHata(kod, mesajCoz(kod, govde), govde, bekle);
    if (kod == 401) oturumDustu?.call(hata);
    throw hata;
  }

  /// 429 yanıtından bekleme süresi: önce Retry-After, sonra mesajdaki "N sn".
  /// Hiçbiri yoksa 30 sn. En az 5 sn, en çok 10 dk.
  static Duration beklemeCoz(String? retryAfter, String? mesaj) {
    var sn = int.tryParse(retryAfter?.trim() ?? '');
    if (sn == null && mesaj != null) {
      final m = RegExp(r'(\d+)\s*sn').firstMatch(mesaj);
      if (m != null) sn = int.tryParse(m.group(1)!);
    }
    return Duration(seconds: (sn ?? 30).clamp(5, 600));
  }

  static String mesajCoz(int kod, Map<String, dynamic>? govde) {
    final hatalar = govde?['errors'];
    if (hatalar is Map && hatalar.isNotEmpty) {
      final ilk = hatalar.values.first;
      if (ilk is List && ilk.isNotEmpty) return ilk.first.toString();
    }
    final m = govde?['message']?.toString();
    if (m != null && m.isNotEmpty && m != 'Server Error' && m != 'Unauthenticated.') return m;
    return switch (kod) {
      401 => 'Oturum kapandı. Telefonu yeniden eşleyin.',
      403 => 'Bu bölüm için yetkiniz yok.',
      404 => 'Bu bölüm işletmenizde açık değil.',
      429 => 'Çok fazla istek. Biraz sonra tekrar deneyin.',
      >= 500 => 'Sunucuda geçici bir sorun var. Birazdan tekrar deneyin.',
      _ => 'İşlem tamamlanamadı ($kod).',
    };
  }
}
