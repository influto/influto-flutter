# Changelog

## 1.0.0

Initial release of the InfluTo Flutter SDK.

### Added
- Full influencer attribution API: `initialize`, `checkAttribution`,
  `identifyUser`, `trackEvent`, `getActiveCampaigns`, `validateCode`,
  `setReferralCode`, `applyCode`, `getReferralCode`, `getPrefilledCode`,
  `clearAttribution` — matching the canonical cross-platform contract (wire 1.0.0).
- Store-direct purchase validation via `reportPurchase` (StoreKit 2 JWS on iOS,
  Play purchase token on Android), posting to `/sdk/purchase`. Supports one-time /
  consumable products via `productId`/`price`/`currency` (NON_RENEWING validation).
- `checkAccess` — server-authoritative premium-access check powering
  platform-independent comp (free-access codes that grant entitlement without a
  purchase); works for both RevenueCat and store-direct apps. Positive results are
  cached in memory and persisted across cold starts (~5-min TTL).
- Default-on automatic purchase capture for store-direct apps via the companion
  `influto_iap` package (`InfluToPurchaseObserver`) — listens to `in_app_purchase`
  and auto-reports purchases; RevenueCat apps stay silent. Declare one-time SKUs via
  `oneTimeProductIds`. Configurable through `InfluToConfig.autoCapture`.
- Optional RevenueCat integration through a host-supplied `revenueCatHook`
  callback — no hard dependency on `purchases_flutter`.
- `ReferralCodeInput` widget with live debounced validation; `showCampaignName`
  and `showReferrerName` both default to `false` (influencer name hidden unless
  explicitly opted in).
- Pure Dart implementation — only `http` and `shared_preferences`. Fail-soft
  behavior on all methods except `initialize` and `reportPurchase`.
