import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Thin REST client over `package:http`. Bearer auth + JSON; throws
/// [InfluToException] on non-2xx or transport failure.
class ApiClient {
  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  ApiClient({required this.baseUrl, required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> postObject(
      String path, Map<String, dynamic> body,) async {
    final http.Response resp;
    try {
      resp = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: _headers,
        body: jsonEncode(body),
      );
    } catch (e) {
      throw InfluToException(message: 'transport: $e');
    }
    _ensureOk(resp);
    final decoded = jsonDecode(resp.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Future<List<dynamic>> getList(String path) async {
    final http.Response resp;
    try {
      resp = await _client.get(Uri.parse('$baseUrl$path'), headers: _headers);
    } catch (e) {
      throw InfluToException(message: 'transport: $e');
    }
    _ensureOk(resp);
    final decoded = jsonDecode(resp.body);
    return decoded is List ? decoded : <dynamic>[];
  }

  void _ensureOk(http.Response resp) {
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw InfluToException(statusCode: resp.statusCode, body: resp.body);
    }
  }
}
