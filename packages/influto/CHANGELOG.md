# Changelog

## 1.1.1

### Fixed
- `setReferralCode()` / `applyCode()` fall back to the user stored by
  `identifyUser()` when `appUserId` isn't passed. Without it the backend
  rejected free-access codes with `MISSING_USER_ID`.
- `setReferralCode()` stores the code (and the `manual_entry` attribution
  record) and calls the `revenueCatHook` only after the backend answers
  `success == true`, using the canonical code it returns. A rejected code is
  no longer stored or tagged. Still fail-soft.
- `ReferralCodeInput`: the field no longer drops `_` (codes allow
  `[A-Z0-9_-]`), and `onApplied` fires only when the code was actually applied
  (`applied == true`), not merely valid.

## 1.1.0

### Fixed
- `checkAttribution()` no longer re-fires `/sdk/track-install` on every cold
  start for organic users: the organic (non-attributed) result is now persisted
  like the attributed one (contract 1.6.0). A failed request still retries on
  the next launch.

### Added
- Persisted per-install UUID (`@influto/install_id`) sent as `device_id`, so
  the backend counts unique devices instead of launches. No permissions, no
  fingerprinting; resets on reinstall by design.
- Deterministic `eventId` for once-only monetization events (`trial_started`,
  `subscription_purchased`, `subscription_renewed`) derived from
  (event type, user, properties) — cross-launch re-fires collapse server-side.

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
