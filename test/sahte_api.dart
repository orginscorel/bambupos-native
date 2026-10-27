import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Test sunucusu: yol → (durum, gövde). Eşleşme yoksa 404.
class SahteSunucu implements HttpClientAdapter {
  SahteSunucu(this.yanitlar, {this.basliklar = const {}});

  final Map<String, (int, Object?)> yanitlar;
  final Map<String, Map<String, List<String>>> basliklar;
  final istekler = <String>[];

  /// Yazma isteklerinin gövdeleri ("POST /yol" → gövde).
  final govdeler = <String, Object?>{};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    istekler.add('${o.method} ${o.path}');
    if (o.method != 'GET') govdeler['${o.method} ${o.path}'] = o.data;
    // Önce "YÖNTEM /yol", yoksa yalnız "/yol".
    final y = yanitlar['${o.method} ${o.path}'] ?? yanitlar[o.path];
    final (kod, govde) = y ?? (404, {'message': 'Bulunamadı'});
    return ResponseBody.fromString(jsonEncode(govde), kod, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...?basliklar[o.path],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// Hiç yanıt vermeyen sunucu (açılış "bekliyor" hâlinde kalır).
class BekleyenSunucu implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) => Completer<ResponseBody>().future;
  @override
  void close({bool force = false}) {}
}
