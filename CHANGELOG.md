# Changelog

## 1.0.0

Initial release of the InfluTo Flutter SDK.

### Added
- Full influencer attribution API: `initialize`, `checkAttribution`,
  `identifyUser`, `trackEvent`, `getActiveCampaigns`, `validateCode`,
  `setReferralCode`, `applyCode`, `getReferralCode`, `getPrefilledCode`,
  `clearAttribution` — matching the canonical cross-platform contract (wire 1.0.0).
- Store-direct purchase validation via `reportPurchase` (StoreKit 2 JWS on iOS,
  Play purchase token on Android), posting to `/sdk/purchase`.
- Optional RevenueCat integration through a host-supplied `revenueCatHook`
  callback — no hard dependency on `purchases_flutter`.
- `ReferralCodeInput` widget with live debounced validation; `showCampaignName`
  and `showReferrerName` both default to `false` (influencer name hidden unless
  explicitly opted in).
- Pure Dart implementation — only `http` and `shared_preferences`. Fail-soft
  behavior on all methods except `initialize` and `reportPurchase`.
