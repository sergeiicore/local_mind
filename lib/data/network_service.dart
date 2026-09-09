import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiException implements Exception {
  const ApiException(this.message, {this.status});
  final String message;
  final int? status;
  bool get retryable =>
      status == null || status == 429 || (status! >= 500 && status! < 600);
  @override
  String toString() => message;
}

class NetworkService {
  Future<dynamic> post(
    Uri uri,
    Map<String, dynamic> body, {
    String? token,
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        if (token != null && token.isNotEmpty) {
          request.headers.set('Authorization', 'Bearer $token');
        }
        headers.forEach(request.headers.set);
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiException(
            'Сервис ответил HTTP ${response.statusCode}',
            status: response.statusCode,
          );
        }
        if (response.statusCode == 204) return null;
        var size = 0;
        final bytes = <int>[];
        await for (final chunk in response) {
          size += chunk.length;
          if (size > 2000000) {
            throw const ApiException(
              'Ответ сервиса слишком большой',
              status: 413,
            );
          }
          bytes.addAll(chunk);
        }
        return jsonDecode(utf8.decode(bytes));
      })().timeout(const Duration(seconds: 75));
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('Сервис не ответил вовремя');
    } on SocketException {
      throw const ApiException('Нет соединения с сервисом');
    } on HandshakeException {
      throw const ApiException('Не удалось установить защищённое соединение');
    } on FormatException {
      throw const ApiException('Сервис вернул некорректный JSON', status: 422);
    } finally {
      client.close(force: true);
    }
  }
}
