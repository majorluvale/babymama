import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Thin JSON client for the Babymama API. Errors come back translated by the server
/// (the Accept-Language header follows the app language).
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = (baseUrl ?? BmConfig.apiUrl).replaceAll(RegExp(r'/$'), '');

  final String baseUrl;
  final http.Client _http = http.Client();
  String? token;
  String locale = 'en';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': locale,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$baseUrl/api$path');
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null && '$value'.isNotEmpty) params[key] = '$value';
    });
    return params.isEmpty ? base : base.replace(queryParameters: params);
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(uri(path, query), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => _http.post(uri(path), headers: _headers, body: jsonEncode(body ?? const {})));

  Future<dynamic> patch(String path, [Object? body]) =>
      _send(() => _http.patch(uri(path), headers: _headers, body: jsonEncode(body ?? const {})));

  Future<dynamic> put(String path, [Object? body]) =>
      _send(() => _http.put(uri(path), headers: _headers, body: jsonEncode(body ?? const {})));

  Future<dynamic> delete(String path) => _send(() => _http.delete(uri(path), headers: _headers));

  /// Uploads an image and returns its public URL.
  Future<String> uploadImage(List<int> bytes, String filename) async {
    final request = http.MultipartRequest('POST', uri('/uploads'));
    request.headers.addAll({
      'Accept-Language': locale,
      if (token != null) 'Authorization': 'Bearer $token',
    });
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final body = await _send(() async => http.Response.fromStream(await request.send()));
    return (body as Map<String, dynamic>)['url'] as String;
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 40));
    } on TimeoutException {
      throw ApiException(0, 'timeout', locale == 'fr' ? 'Le serveur ne répond pas.' : 'The server is not responding.');
    } catch (_) {
      throw ApiException(
          0, 'network_error', locale == 'fr' ? 'Pas de connexion internet.' : 'No internet connection.');
    }
    final text = utf8.decode(res.bodyBytes);
    dynamic body;
    if (text.isNotEmpty) {
      try {
        body = jsonDecode(text);
      } catch (_) {
        body = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final map = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    throw ApiException(
      res.statusCode,
      '${map['error'] ?? 'error'}',
      '${map['message'] ?? 'Request failed (${res.statusCode})'}',
    );
  }
}
