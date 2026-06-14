import 'dart:convert';
import 'dart:io';

/// Calls the SDK-key-authed `GET /sdk/recent-conversions` feedback endpoint so the
/// sample can confirm in-app that a purchase landed in InfluTo (and attributed).
class SampleBackend {
  static Future<String> recentConversionsSummary({
    required String baseUrl,
    required String apiKey,
    required String appUserId,
  }) async {
    final uri = Uri.parse('$baseUrl/sdk/recent-conversions').replace(
      queryParameters: {'app_user_id': appUserId, 'limit': '10'},
    );
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return 'HTTP ${resp.statusCode}: $body';
      }
      return _summarize(body);
    } catch (e) {
      return "Couldn't check: $e";
    } finally {
      client.close();
    }
  }

  static String _summarize(String body) {
    final obj = jsonDecode(body) as Map<String, dynamic>;
    final convs = (obj['conversions'] as List?) ?? const [];
    if (convs.isEmpty) return 'No purchase recorded yet for this user.';
    final first = convs.first as Map<String, dynamic>;
    final code = first['referral_code'] ?? '—';
    return '✅ ${obj['count']} event(s) · ${obj['attributed_count']} attributed.\n'
        "Latest: ${first['event_type']} · ${first['environment']} · code=$code";
  }
}
