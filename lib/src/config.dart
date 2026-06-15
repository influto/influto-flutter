import 'package:http/http.dart' as http;

import 'revenuecat_hook.dart';

/// Configuration for [InfluTo.initialize].
class InfluToConfig {
  /// Your InfluTo API key (from the dashboard).
  final String apiKey;

  /// Enable debug logging.
  final bool debug;

  /// Base API URL. Defaults to `https://influ.to/api` (override for testing).
  final String apiUrl;

  /// Your app's version string, reported on `/sdk/init` for telemetry.
  final String? appVersion;

  /// Automatically capture + report store purchases (store-direct apps only). Default `true`.
  /// The companion `influto_iap` package's `InfluToPurchaseObserver` self-gates on this and on
  /// the backend's store-direct flag — so RevenueCat apps are unaffected. Set `false` to manage
  /// purchase reporting yourself. (The core package has no IAP dependency, so the observer must
  /// be added via `influto_iap`; it then respects this flag.)
  final bool autoCapture;

  /// OPTIONAL RevenueCat hook. If the host uses RevenueCat, wire this to
  /// `(attrs) => Purchases.setAttributes(attrs)`. The SDK calls it with
  /// `{influto_code, influto_referral: "true"}` on attribution / setReferralCode.
  final RevenueCatHook? revenueCatHook;

  /// OPTIONAL injectable HTTP client (for tests / custom transport).
  final http.Client? httpClient;

  const InfluToConfig({
    required this.apiKey,
    this.debug = false,
    this.apiUrl = 'https://influ.to/api',
    this.appVersion,
    this.autoCapture = true,
    this.revenueCatHook,
    this.httpClient,
  });
}
