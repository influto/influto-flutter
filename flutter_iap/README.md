# influto_iap

Automatic store-purchase capture for the [InfluTo](https://influ.to) Flutter SDK
([`influto`](https://pub.dev/packages/influto)).

Add this companion to a **store-direct** app (one that validates purchases via Apple/Google
directly, not RevenueCat) and InfluTo reports purchases for you — no manual `reportPurchase`
calls. It listens to [`in_app_purchase`](https://pub.dev/packages/in_app_purchase)'s
`purchaseStream`, extracts the store-signed proof (StoreKit 2 JWS on iOS / Play purchase token
on Android), and forwards each **new** purchase to `InfluTo.instance.reportPurchase`, deduped so
a purchase is never reported twice. `enable()` also runs a one-time back-sync of existing
purchases.

It **self-gates**: if the app isn't store-direct (or `InfluToConfig.autoCapture` is `false`),
the observer is a no-op — so RevenueCat apps stay silent even if it's wired in.

## Install

```yaml
dependencies:
  influto: ^1.0.0
  influto_iap: ^1.0.0
```

## Usage

Call `enable()` once at startup, after `InfluTo.instance.initialize(...)`:

```dart
import 'package:influto_iap/influto_iap.dart';

final observer = InfluToPurchaseObserver(
  // Android one-time / consumable SKUs — listing them routes those purchases to one-time
  // (NON_RENEWING) validation. Omit if you only sell subscriptions; iOS needs nothing.
  oneTimeProductIds: {'coins_100', 'remove_ads'},
);

final result = await observer.enable(); // listens + back-syncs existing purchases
print('back-synced ${result.sent}/${result.fetched} (${result.failed} failed)');

// later, on teardown:
observer.dispose();
```

Use exactly **one** reporting path per app: either this companion, a manual `reportPurchase`,
or a RevenueCat webhook — never more than one.

## License

MIT — see [LICENSE](LICENSE).
