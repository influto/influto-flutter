<!-- Vendored copy of the canonical InfluTo SDK wire contract (v1.0.0). Keep this in sync across the InfluTo SDKs — edit the canonical source, not this copy. -->

# InfluTo SDK — Canonical Cross-Platform Contract

**This is the single source of truth every InfluTo SDK (React Native, iOS/Swift,
Android/Kotlin, Flutter, future Web) must obey byte-for-byte.** Shapes come from the
InfluTo backend; behaviors that OpenAPI can't express are pinned here.

Wire version: **1.0.0**

---

## 1. Transport

- Base URL: `https://influ.to/api` (overridable via config for internal testing).
- Auth: header `Authorization: Bearer <apiKey>` on every request.
- `Content-Type: application/json`, `Accept: application/json`. JSON bodies.
- The server reads the client **IP** and **User-Agent** from headers — never send them in the body.

## 2. Endpoints

| Method | Path | Request | Response |
|---|---|---|---|
| POST | `/sdk/init` | `{app_version, sdk_version, platform:"ios"\|"android"}` | `{app_id, app_name, attribution_window_hours, campaigns[], store_direct, initialized}` |
| POST | `/sdk/track-install` | `{platform, device_id?, device_brand?, device_model?, os_version?, screen_resolution?, timezone?, language?}` | `{attributed, referral_code?, attribution_method?, clicked_at?, message}` |
| POST | `/sdk/identify` | `{app_user_id, properties?}` | `{identified, app_user_id}` |
| POST | `/sdk/event` | `{eventType, appUserId, properties?, referralCode?, eventId?}` (camelCase on the wire — see §4) | `{tracked, event_id, duplicate?, dedup_reason?}` |
| GET | `/sdk/campaigns` | — | `[{id, name, description, commission_percentage}]` |
| POST | `/sdk/validate-code` | `{code}` | `{valid, code?, campaign?{id,name,description,commission_percentage,campaign_type}, influencer?{name,social_handle,follower_count}, custom_data?, message?, error?, error_code?}` |
| POST | `/sdk/set-referral-code` | `{code, app_user_id?}` | `{success, code?, message, campaign?{id,name}, free_access?, grants_access?, entitlement?, expires_at?}` |
| POST | `/sdk/purchase` | `{platform, app_user_id?, signedTransaction?, purchaseToken?, productId?, price?, currency?, referralCode?}` (store-direct) | `{success, validated:"apple"\|"google", environment, event_type, duplicate, recorded, result}` |
| GET | `/sdk/attribution?app_user_id=` | — | attribution data |
| GET | `/sdk/access?app_user_id=` | — | `{has_access, source:"comp"\|null, entitlement?, expires_at?, code?}` |

The backend accepts BOTH snake_case and camelCase on `/sdk/event` and `/sdk/purchase`
(Pydantic `AliasChoices`). To match the reference RN SDK, send **camelCase** for
`/sdk/event` and `/sdk/purchase`, **snake_case** for everything else.

**Privacy — names OFF by default:** `/sdk/validate-code` returns `campaign.name`,
`influencer.name` (the influencer's PERSONAL name), and may echo the influencer name in
`message`. Every SDK ships a configurable `ReferralCodeInput` UI component — RN
`ReferralCodeInput` (the `/ui` subpath), iOS `InfluToReferralCodeInput` (SwiftUI), Flutter
`ReferralCodeInput` (widget), Android `InfluToReferralCodeInput` (in the SEPARATE
`to.influ:android-sdk-ui` Compose artifact, so the core `android-sdk` stays zero-dep).
By default the component shows ONLY the field + a valid/invalid state; **both
`showCampaignName` and `showReferrerName` are opt-in (default `false`)**. The `influencer`
object stays in the response + SDK types for back-compat — it just isn't shown by default.

## 3. Public API (per platform, idiomatic)

| Canonical method | Behavior |
|---|---|
| `initialize(config)` | POST `/sdk/init`; persist `@influto/initialized=true`. **THROWS on failure** (the only init-time throw). |
| `checkAttribution()` | Return cached `@influto/attribution` if present; else POST `/sdk/track-install`, persist on `attributed`, set RC attributes. Fail-soft → `{attributed:false}`. |
| `identifyUser(appUserId, properties?)` | Persist `@influto/app_user_id`; POST `/sdk/identify`. Fail-soft (no throw). |
| `trackEvent({eventType, appUserId, properties?, referralCode?, eventId?})` | Auto-generate `eventId` (uuid v4) if absent; POST `/sdk/event`. Fail-soft. |
| `getActiveCampaigns()` | GET `/sdk/campaigns`. Fail-soft → `[]`. |
| `getReferralCode()` | Local read of `@influto/influto_code`. |
| `getPrefilledCode()` | Local: stored code only if `attribution.attributed`. |
| `validateCode(code)` | Normalize (trim + UPPERCASE); POST `/sdk/validate-code`. Fail-soft → `{valid:false, error_code:"NETWORK_ERROR"}`. |
| `setReferralCode(code, appUserId?)` | Normalize; persist code + a `manual_entry` attribution record; set RC attributes; POST `/sdk/set-referral-code`. Fail-soft → `{success:false}`. |
| `applyCode(code, appUserId?)` | `validateCode` then `setReferralCode` if valid; adds `applied`. |
| `clearAttribution()` | Local clear of the 3 keys. |
| **`reportPurchase({platform, signedTransaction?, purchaseToken?, productId?, price?, currency?, appUserId?, referralCode?})`** | **NEW.** Store-direct. `productId`/`price`/`currency` are for Android **one-time** products only (route to NON_RENEWING validation; omit for subscriptions — see §9). Default `referralCode` to stored `@influto/influto_code`. POST `/sdk/purchase`. **THROWS on failure**; a **503** means FX-unavailable → caller should retry. |
| **`enableAutoPurchaseCapture(opts?)` / `disableAutoPurchaseCapture()`** | Auto-`reportPurchase` per NEW store purchase + back-sync, deduped. **ON BY DEFAULT for store-direct apps** — `initialize` starts it when `/sdk/init` returns `store_direct:true` AND config `autoCapture` isn't `false` (RevenueCat apps stay silent). RN/iOS run in-core (RN dynamic-requires `expo-iap`→`react-native-iap`, Expo-Go-safe; iOS observes StoreKit2 `Transaction.updates`). Android: `initialize` reflectively starts the SEPARATE `to.influ:android-sdk-billing` artifact if present. Flutter: the SEPARATE `influto_iap` `InfluToPurchaseObserver` (self-gates on `store_direct`). The explicit methods remain for manual control. |
| **`syncExistingPurchases()` → `{fetched, sent, failed}`** | One-shot back-sync of EXISTING/unfinished store transactions; reports each not-yet-sent one. Idempotent via the dedup set. |
| **`checkAccess(appUserId?)` → `{hasAccess, source?, entitlement?, expiresAt?, code?}`** | **NEW.** Server-authoritative premium access (platform-independent comp — works for RC AND store-direct apps). GET `/sdk/access`. Fail-soft → `{hasAccess:false}`. Caches a positive result ~5 min (`@influto/access`); a negative result is never cached. Recommended premium gate: `RC-entitlement OR checkAccess().hasAccess`. |

## 4. Behavioral invariants (the part OpenAPI can't express)

1. **Idempotency.** `trackEvent` MUST generate a UUID v4 `eventId` when the caller omits
   one. The backend dedups on it (plus once-only-type + 60s-window fallbacks). Without it,
   accidental double-fires create duplicate rows.
2. **Code normalization.** `validateCode` / `setReferralCode` / `applyCode` MUST
   `trim().toUpperCase()` the code client-side before sending (so local cache keys agree
   with the backend, which also uppercases).
3. **Local persistence.** All local keys live under the prefix `@influto/`, exactly:
   `@influto/attribution` (JSON), `@influto/influto_code`, `@influto/app_user_id`,
   `@influto/initialized`. Byte-identical across SDKs.
4. **Fail-soft.** Network/parse errors return a benign value and NEVER throw to the host —
   EXCEPT `initialize` and `reportPurchase`, which throw. Fallback shapes:
   `checkAttribution → {attributed:false}`, `getActiveCampaigns → []`,
   `validateCode → {valid:false, error_code:"NETWORK_ERROR"}`, `setReferralCode → {success:false}`.
5. **RevenueCat attributes.** On attribution found AND on
   `setReferralCode`/`applyCode`, set these RevenueCat subscriber attributes (if the host
   uses RevenueCat). The backend's RC webhook + Targeting rules read them:

   | key | value |
   |---|---|
   | `influto_code` | the referral code (already uppercased) |
   | `influto_referral` | the literal **string** `"true"` (NOT a boolean) |

   A boolean `true` breaks Targeting silently. RevenueCat integration MUST be OPTIONAL — no
   hard dependency. Recommended cross-platform pattern: a **caller-injected attribute-setter
   callback** the host wires to `Purchases.setAttributes(...)`. (RN keeps its `require()`
   auto-detect for back-compat.)
6. **Store-direct attribution binding.** `reportPurchase` MUST send the stored
   `influto_code` on the FIRST transaction so the conversion (keyed on the store identity —
   Apple `originalTransactionId` / Google `purchaseToken`) binds to a referral. The host
   should additionally set StoreKit2 `appAccountToken` (iOS) / Play `obfuscatedAccountId`
   (Android) at purchase time so the store identity is stable across renewals.
7. **`/sdk/purchase` gating.** Returns **400** unless the app is configured for store-direct
   on that platform (`ios_validation_provider='apple'` / `android_validation_provider='google'`),
   so it's safe to ship dormant. Returns **503** on an FX-rate miss (retryable). `validated`
   is a **string** (`"apple"`/`"google"`), not a boolean. The response also carries top-level
   `duplicate` / `recorded` booleans so the auto-capture back-sync can build its counters.
8. **Default-on auto-capture + dedup.** Auto-capture is ON BY
   DEFAULT for store-direct apps: `initialize` starts it when `/sdk/init` returns `store_direct:true`
   AND config `autoCapture` is not `false`. It NEVER runs for RevenueCat apps (`store_direct:false`),
   so it can't double-report against the RC-webhook path. A store-direct host that wires manual
   `reportPurchase` itself should set `autoCapture:false` (use exactly ONE reporting path). Each
   reported purchase's store-stable id is persisted in a sent-set and skipped on subsequent
   launches/back-syncs.
   The dedup key is the SAME identity the backend keys conversions on (§6): iOS
   `Transaction.originalID` (Apple `originalTransactionId`), Android `Purchase.purchaseToken`.
   The backend is the FINAL dedup anchor (repeated reports are idempotent).
   `PurchaseSyncResult` is `{fetched, sent, failed}` on every platform: `fetched` = store
   returned, `sent` = newly reported (excludes dedup skips), `failed` = report threw. The
   sent-set key (RN/Flutter `@influto/reported_purchases`, iOS `@influto/sent_purchases`,
   Android prefs `influto_billing_sync_prefs`) is additive — NOT part of the §4.3 4-key set,
   and NOT cleared by `clearAttribution` (a returning user must not re-report old purchases).
9. **One-time / consumable purchases.** Apple consumable / non-consumable / non-renewing
   transactions and Google one-time products route to `NON_RENEWING_PURCHASE` (one conversion
   PER purchase — each distinct `transactionId`/`orderId` is its own conversion). iOS needs no
   extra fields (the JWS carries the type). Android one-time products MUST send `productId`
   (Google `products.get` needs it) and SHOULD send `price`+`currency` from `ProductDetails`
   (a one-time `ProductPurchase` has no price). Omit `productId` for subscriptions.
10. **Server-authoritative comp (platform-independent free access).** Free-access (comp) codes
   grant a native `FreeCodeRedemption` row UNCONDITIONALLY (the RevenueCat grant is a best-effort
   add-on for RC apps only). `checkAccess` reads ONLY server state — the client holds a code,
   never a grant. Premium gate = `RC-entitlement OR checkAccess().hasAccess`. The `@influto/access`
   cache is additive (NOT in §4.3) and is NOT cleared by `clearAttribution` (a comp survives logout).
   Seat caps + expiry are server-enforced; a later-blocked/expired code revokes access for all
   holders on the next `checkAccess`. `setReferralCode`/`applyCode` also return
   `free_access`/`grants_access`/`entitlement`/`expires_at` so the app can unlock immediately.

## 5. Verification

Each SDK's unit suite replays the `fixtures/*.json` golden request/response pairs through a
mocked HTTP layer and asserts the SDK maps identical wire bytes to identical public types.
A live backend can additionally be checked with Schemathesis against `/openapi.json`.

Backend end-to-end check after a sample-app run:
`GET /api/apps/{id}/events/recent` →
- `sdk_events[]` shows each `trackEvent` exactly once (dedup) with the right `referral_code` + `platform`;
- `webhooks[]` shows a `reportPurchase` with `"attributed": true` + the matching `referral_code`
  (organic shows `"organic": true`, `referral_code: null`).
