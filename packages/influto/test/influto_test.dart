import 'dart:convert';

import 'package:flutter/material.dart';
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

  test('setReferralCode falls back to the user stored by identifyUser',
      () async {
    final sent = <Map<String, dynamic>>[];
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/set-referral-code')) {
        sent.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"success":true,"code":"FREE1"}', 200);
      }
      return http.Response('{}', 200);
    });

    await InfluTo.instance
        .initialize(InfluToConfig(apiKey: 'k', httpClient: mock));
    await InfluTo.instance.setReferralCode('free1');
    expect(sent.last.containsKey('app_user_id'), isFalse);

    await InfluTo.instance.identifyUser('user_42');
    await InfluTo.instance.setReferralCode('free1');
    expect(sent.last['app_user_id'], 'user_42');

    await InfluTo.instance.setReferralCode('free1', appUserId: 'explicit');
    expect(sent.last['app_user_id'], 'explicit');
  });

  test(
      'a rejected code is not stored or tagged; an accepted one stores the '
      'canonical code', () async {
    Map<String, String>? rcAttrs;
    var mode = 'notFound';
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/set-referral-code')) {
        switch (mode) {
          case 'notFound':
            return http.Response(
                '{"detail":"Referral code not found or inactive"}', 404,);
          case 'missingUser':
            return http.Response(
              '{"success":false,"code":"FREE1","error_code":"MISSING_USER_ID"}',
              200,
            );
          default:
            return http.Response('{"success":true,"code":"FITGURU30"}', 200);
        }
      }
      return http.Response('{}', 200);
    });

    await InfluTo.instance.initialize(InfluToConfig(
      apiKey: 'k',
      httpClient: mock,
      revenueCatHook: (a) async => rcAttrs = a,
    ),);

    final notFound = await InfluTo.instance.setReferralCode('NOPE');
    expect(notFound.success, isFalse);
    mode = 'missingUser';
    final missingUser = await InfluTo.instance.setReferralCode('FREE1');
    expect(missingUser.success, isFalse);
    expect(await InfluTo.instance.getReferralCode(), isNull);
    expect(await InfluTo.instance.getPrefilledCode(), isNull);
    expect(rcAttrs, isNull);

    mode = 'accept';
    final ok = await InfluTo.instance.setReferralCode(' fitgur030 ');
    expect(ok.success, isTrue);
    expect(await InfluTo.instance.getReferralCode(), 'FITGURU30');
    expect(await InfluTo.instance.getPrefilledCode(), 'FITGURU30');
    expect(rcAttrs?['influto_code'], 'FITGURU30');
  });

  testWidgets(
      'ReferralCodeInput keeps "_" and fires onApplied only when applied',
      (tester) async {
    var accept = false;
    final applied = <CodeValidationResult>[];
    final mock = client((req) async {
      if (req.url.path.endsWith('/sdk/init')) {
        return http.Response('{"initialized":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/validate-code')) {
        return http.Response('{"valid":true}', 200);
      }
      if (req.url.path.endsWith('/sdk/set-referral-code')) {
        return accept
            ? http.Response('{"success":true}', 200)
            : http.Response(
                '{"success":false,"error_code":"MISSING_USER_ID"}', 200,);
      }
      return http.Response('{}', 200);
    });
    await tester.runAsync(() => InfluTo.instance
        .initialize(InfluToConfig(apiKey: 'k', httpClient: mock)),);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReferralCodeInput(autoPrefill: false, onApplied: applied.add),
      ),
    ),);

    Future<void> enterAndApply(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 500)); // debounce
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
    }

    await enterAndApply('fit_guru');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'FIT_GURU',
    );
    expect(applied, isEmpty); // valid, but the server did not apply it

    accept = true;
    await enterAndApply('fit_guru2');
    expect(applied, hasLength(1));
    expect(applied.single.applied, isTrue);
  });
}
