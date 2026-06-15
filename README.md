# influto (Flutter)

Influencer attribution + store-direct purchase validation for Flutter. Pure Dart —
only `http` + `shared_preferences`. Mirrors the [InfluTo React Native SDK](https://github.com/influto/influto-react-native)
and the [canonical contract](./CONTRACT.md).

## Prerequisites

You need a free **InfluTo account** — sign up at [https://influ.to](https://influ.to), create your
app in the dashboard, and copy your API key (it starts with `it_`). For store-direct purchase
validation / auto-capture, also add your Apple/Google store credentials to the app in the dashboard.

## Install

```yaml
dependencies:
  influto: ^1.0.0
```

## Quick start

```dart
import 'package:influto/influto.dart';

await InfluTo.instance.initialize(const InfluToConfig(
  apiKey: 'it_live_...',
  debug: true,
  // OPTIONAL: wire RevenueCat (no hard dependency). The SDK calls it with
  // {influto_code, influto_referral:"true"} on attribution / setReferralCode.
  // revenueCatHook: (attrs) => Purchases.setAttributes(attrs),
));

final attr = await InfluTo.instance.checkAttribution();
if (attr.attributed) print('Referred by ${attr.referralCode}');

await InfluTo.instance.identifyUser('user_123');
await InfluTo.instance.trackEvent(
  const TrackEventOptions(eventType: 'paywall_viewed', appUserId: 'user_123'),
);

// Manual promo-code entry
final res = await InfluTo.instance.applyCode('FITGURU30', appUserId: 'user_123');

// Store-direct purchase (only if NOT using RevenueCat). The host obtains the proof
// from its own IAP layer (in_app_purchase / purchases_flutter) and passes it in:
//   iOS:     signedTransaction = details.verificationData.serverVerificationData  // StoreKit2 JWS
//   Android: purchaseToken     = details.verificationData.serverVerificationData  // Play token
await InfluTo.instance.reportPurchase(platform: 'android', purchaseToken: token);
```

`reportPurchase` defaults `referralCode` to the SDK-stored `influto_code`, so the first
transaction binds to the referral. For renewals/refunds to attribute, also set
StoreKit2 `appAccountToken` (iOS) / Play `obfuscatedAccountId` (Android) at purchase time.

## Build & test

```bash
# Static gates + unit tests (run on Windows or WSL2):
dart analyze
dart format --set-exit-if-changed .
flutter test                       # the MockClient-backed contract tests

# Run the example on a device / AVD (Android builds on your Windows host):
cd example
flutter create --platforms=android .   # one-time: generate the android/ runner
flutter pub get
# Pass your API key at build/run time via --dart-define (never committed; the example
# defaults to a harmless "it_TEST_KEY" the backend rejects with 401). Get the key from
# the dashboard → your app → API key:
flutter run -d <android-device-id> --dart-define=INFLUTO_API_KEY=it_live_your_real_key
```

> **iOS** builds require **macOS + Xcode** (Flutter-iOS can't be compiled on Windows/WSL2).
> The pure-Dart logic is fully unit-tested on any host with `flutter test`; only the
> on-device iOS smoke test (and `reportPurchase` with a real StoreKit2 JWS) needs a Mac.

## Verify on the backend

After a sample run, `GET /api/apps/{id}/events/recent`:
- `sdk_events[]` shows each `trackEvent` once (dedup) with the right `referral_code` + `platform`;
- `webhooks[]` shows the purchase with `"attributed": true` + the matching `referral_code`.

## Publish (pub.dev)

```bash
dart pub publish --dry-run    # check pub points / layout
dart pub publish              # or via GitHub Actions OIDC (no long-lived token)
```
