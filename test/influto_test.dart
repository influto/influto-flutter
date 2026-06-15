import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:influto/influto.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  MockClient client(Future<http.Response> Function(http.Request) handler) =>
      MockClient((req) => handler(req));

  test('initialize + checkAttribution maps the wire response + persists code',
      () async {
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/track-install')) {
        return http.Response(
          jsonEncode({
            'attributed': true,
            'referral_code': 'FITGURU30',
            'attribution_method': 'ip_device_match',
            'message': 'ok',
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    await InfluTo.instance
        .initialize(InfluToConfig(apiKey: 'k', httpClient: mock));
    final attr = await InfluTo.instance.checkAttribution();
    expect(attr.attributed, isTrue);
    expect(attr.referralCode, 'FITGURU30');
    expect(await InfluTo.instance.getReferralCode(), 'FITGURU30');
  });

  test('validateCode normalizes (trim+UPPER) and maps not-found', () async {
    String? sentCode;
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/validate-code')) {
        sentCode =
            (jsonDecode(req.body) as Map<String, dynamic>)['code'] as String?;
        return http.Response(
          '{"valid":false,"error":"Code not found or inactive","error_code":"CODE_NOT_FOUND"}',
          200,
        );
      }
      return http.Response('{}', 200);
    });

    await InfluTo.instance
        .initialize(InfluToConfig(apiKey: 'k', httpClient: mock));
    final r = await InfluTo.instance.validateCode('  fitguru30 ');
    expect(sentCode, 'FITGURU30');
    expect(r.valid, isFalse);
    expect(r.errorCode, 'CODE_NOT_FOUND');
  });

  test(
      'reportPurchase sends platform/token + defaults referralCode from stored code',
      () async {
    Map<String, dynamic>? sentBody;
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/set-referral-code')) {
        return http.Response('{"success":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/purchase')) {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          '{"success":true,"validated":"google","environment":"PRODUCTION","event_type":"INITIAL_PURCHASE"}',
          200,
        );
      }
      return http.Response('{}', 200);
    });

    await InfluTo.instance
        .initialize(InfluToConfig(apiKey: 'k', httpClient: mock));
    await InfluTo.instance.setReferralCode('FITGURU30');
    final r = await InfluTo.instance
        .reportPurchase(platform: 'android', purchaseToken: 'tok123');
    expect(r.success, isTrue);
    expect(r.validated, 'google');
    expect(sentBody?['platform'], 'android');
    expect(sentBody?['purchaseToken'], 'tok123');
    expect(sentBody?['referralCode'], 'FITGURU30');
  });

  test(
      'revenueCatHook receives influto_code + influto_referral="true" (string)',
      () async {
    Map<String, String>? rcAttrs;
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/set-referral-code')) {
        return http.Response('{"success":true}', 200);
      }
      return http.Response('{}', 200);
    });

    await InfluTo.instance.initialize(InfluToConfig(
      apiKey: 'k',
      httpClient: mock,
      revenueCatHook: (a) async => rcAttrs = a,
    ),);
    await InfluTo.instance.setReferralCode('FITGURU30');
    expect(rcAttrs?['influto_code'], 'FITGURU30');
    expect(rcAttrs?['influto_referral'], 'true');
  });
}
