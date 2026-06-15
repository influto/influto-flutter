# Changelog

## 1.0.0

Initial release of `influto_iap`, the automatic store-purchase capture companion for
the [`influto`](https://pub.dev/packages/influto) Flutter SDK.

### Added
- `InfluToPurchaseObserver` — listens to `in_app_purchase`'s `purchaseStream` and
  auto-reports each new store purchase to InfluTo (StoreKit 2 JWS on iOS, Play purchase
  token on Android), plus a one-time historical back-sync via `enable()`.
- Self-gates on store-direct apps (no-op for RevenueCat apps), deduped per store
  identity; the backend is the final idempotency anchor.
- `oneTimeProductIds` — declare your Android one-time / consumable SKUs so their
  purchases route to NON_RENEWING validation (iOS needs nothing; the JWS carries the type).
