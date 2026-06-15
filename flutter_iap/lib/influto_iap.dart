/// InfluTo IAP — opt-in automatic store-purchase capture + historical back-sync.
///
/// Companion to the zero-dependency `influto` core. Subscribes to
/// `InAppPurchase.instance.purchaseStream`, extracts the store-signed proof
/// (iOS StoreKit 2 JWS / Android purchaseToken), and calls
/// `InfluTo.instance.reportPurchase` for every NEW purchase — deduped so a purchase
/// is never reported twice across re-emits or relaunches. `syncExisting()` runs a
/// one-time back-sync over restored purchases.
///
/// Use ONLY for store-direct apps that do NOT already report via a RevenueCat webhook
/// or a manual reportPurchase. One reporting path per app.
///
/// ```dart
/// final observer = InfluToPurchaseObserver(
///   // Android one-time / consumable SKUs (omit if you only sell subscriptions; iOS needs none).
///   oneTimeProductIds: {'coins_100', 'remove_ads'},
/// );
/// final r = await observer.enable(); // listens + back-syncs
/// print('back-synced ${r.sent}/${r.fetched} (${r.failed} failed)');
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:influto/influto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counters returned by a back-sync ([InfluToPurchaseObserver.syncExisting] and the
/// sweep run by [InfluToPurchaseObserver.enable]).
///
/// [fetched] — purchases the store returned.
/// [sent]    — newly reported to InfluTo (excludes already-deduped purchases).
/// [failed]  — purchases whose reportPurchase call threw.
class PurchaseSyncResult {
  final int fetched;
  final int sent;
  final int failed;

  const PurchaseSyncResult({
    required this.fetched,
    required this.sent,
    required this.failed,
  });

  static const PurchaseSyncResult empty =
      PurchaseSyncResult(fetched: 0, sent: 0, failed: 0);

  @override
  String toString() =>
      'PurchaseSyncResult(fetched: $fetched, sent: $sent, failed: $failed)';
}

/// Opt-in controller for automatic purchase capture. Construct one, call [enable]
/// once at startup (after `InfluTo.instance.initialize`), and [dispose] on teardown.
/// Every method is no-throw; failures are logged when [debug] is true.
class InfluToPurchaseObserver {
  InfluToPurchaseObserver({
    InAppPurchase? iap,
    Set<String> oneTimeProductIds = const <String>{},
    this.debug = false,
  })  : _iap = iap ?? InAppPurchase.instance,
        _oneTimeProductIds = oneTimeProductIds;

  /// Local key for the deduped set of reported purchase ids (additive — NOT part of
  /// the byte-identical cross-SDK persistence set).
  static const String _reportedKey = '@influto/reported_purchases';

  /// Cap the persisted dedup set so it can't grow without bound.
  static const int _maxReported = 500;

  final InAppPurchase _iap;
  final bool debug;

  /// Host-declared one-time / consumable Android product ids. A Play purchase carries no
  /// product TYPE, so a one-time product can only be routed to one-time validation (vs
  /// subscription) if its id is listed here. iOS needs nothing — the JWS carries the type.
  final Set<String> _oneTimeProductIds;

  /// Queried one-time [ProductDetails] cached by id, for `rawPrice`/`currencyCode`
  /// (the Android `PurchaseDetails` carries no price).
  final Map<String, ProductDetails> _oneTimeProducts = <String, ProductDetails>{};

  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _enabled = false;

  bool get isEnabled => _enabled;

  void _log(String msg) {
    if (debug) debugPrint('[InfluToIAP] $msg');
  }

  /// Begin listening to the purchase stream + (by default) run a one-time back-sync.
  /// No-op safe to call once. Returns the back-sync counters (zeros if [backSync] is
  /// false).
  Future<PurchaseSyncResult> enable({bool backSync = true}) async {
    if (_enabled) {
      _log('already enabled');
      return PurchaseSyncResult.empty;
    }
    // Self-gate: only run for store-direct apps that haven't opted out. Keeps RevenueCat apps
    // silent even if the observer is wired. (Mirrors the default auto-capture on the other SDKs.)
    if (!InfluTo.instance.autoCaptureEnabled) {
      _log('auto-capture not enabled (app is not store-direct, or autoCapture:false) — no-op');
      return PurchaseSyncResult.empty;
    }
    // SK2 is the default on iOS 15+; be explicit so we get the JWS, not the SK1 receipt.
    if (Platform.isIOS) {
      InAppPurchaseStoreKitPlatform.enableStoreKit2();
    }
    // Cache one-time product details (Android only) so we can attach price/currency to a
    // captured one-time purchase — the PurchaseDetails carries no price. Fail-soft.
    if (Platform.isAndroid && _oneTimeProductIds.isNotEmpty) {
      try {
        final resp = await _iap.queryProductDetails(_oneTimeProductIds);
        for (final p in resp.productDetails) {
          _oneTimeProducts[p.id] = p;
        }
        _log('cached ${_oneTimeProducts.length} one-time product(s)');
      } catch (e) {
        _log('queryProductDetails failed: $e');
      }
    }
    _enabled = true;
    _sub = _iap.purchaseStream.listen(
      _onUpdate,
      onError: (Object e) => _log('purchase stream error: $e'),
    );
    _log('enabled');
    if (!backSync) return PurchaseSyncResult.empty;
    return syncExisting();
  }

  /// Stop listening. Does NOT clear the dedup set.
  void disable() {
    _sub?.cancel();
    _sub = null;
    _enabled = false;
    _log('disabled');
  }

  /// Alias for [disable] for lifecycle symmetry.
  void dispose() => disable();

  /// One-time sweep of EXISTING purchases via `restorePurchases()`. The restored
  /// purchases arrive on the SAME purchaseStream, so to return deterministic counters
  /// we collect the restored batch on a dedicated short-lived subscription, then report
  /// it. Safe to call repeatedly — dedup makes re-runs cheap no-ops.
  Future<PurchaseSyncResult> syncExisting() async {
    if (!await _iap.isAvailable()) {
      _log('store unavailable — back-sync skipped');
      return PurchaseSyncResult.empty;
    }

    final completer = Completer<List<PurchaseDetails>>();
    final collected = <PurchaseDetails>[];
    Timer? settle;
    late final StreamSubscription<List<PurchaseDetails>> tmp;
    tmp = _iap.purchaseStream.listen((list) {
      collected.addAll(list.where((d) =>
          d.status == PurchaseStatus.purchased ||
          d.status == PurchaseStatus.restored));
      for (final d in list) {
        if (d.pendingCompletePurchase) {
          _iap.completePurchase(d);
        }
      }
      settle?.cancel();
      settle = Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) completer.complete(collected);
      });
    });

    try {
      await _iap.restorePurchases();
    } catch (e) {
      _log('restorePurchases failed: $e');
    }
    // Safety timeout if no purchases are restored at all.
    settle ??= Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) completer.complete(collected);
    });

    final restored = await completer.future;
    await tmp.cancel();
    settle?.cancel();

    var sent = 0;
    var failed = 0;
    final reported = await _loadReported();
    for (final d in restored) {
      final proof = _extract(d);
      if (proof == null) continue;
      if (reported.contains(proof.dedupId)) continue;
      try {
        await _report(proof);
        reported.add(proof.dedupId);
        sent += 1;
      } catch (e) {
        failed += 1;
        _log('back-sync report failed: $e');
      }
    }
    await _saveReported(reported);
    final r =
        PurchaseSyncResult(fetched: restored.length, sent: sent, failed: failed);
    _log('back-sync complete: $r');
    return r;
  }

  // ----------------------------------------------------------------- live stream

  Future<void> _onUpdate(List<PurchaseDetails> purchases) async {
    final reported = await _loadReported();
    var changed = false;
    for (final d in purchases) {
      if (d.status == PurchaseStatus.purchased ||
          d.status == PurchaseStatus.restored) {
        final proof = _extract(d);
        if (proof != null && !reported.contains(proof.dedupId)) {
          try {
            await _report(proof);
            reported.add(proof.dedupId);
            changed = true;
          } catch (e) {
            _log('live report failed: $e');
          }
        }
      }
      // ALWAYS complete or the store re-delivers / Play auto-refunds.
      if (d.pendingCompletePurchase) {
        await _iap.completePurchase(d);
      }
    }
    if (changed) await _saveReported(reported);
  }

  // -------------------------------------------------------------------- extract

  _Proof? _extract(PurchaseDetails d) {
    if (Platform.isIOS) {
      final jws = d.verificationData.serverVerificationData; // SK2 JWS
      if (jws.isEmpty) return null;
      final dedupId = (d.purchaseID != null && d.purchaseID!.isNotEmpty)
          ? d.purchaseID!
          : jws;
      return _Proof(
        dedupId: dedupId,
        platform: 'ios',
        signedTransaction: jws,
      );
    } else {
      final token = (d is GooglePlayPurchaseDetails)
          ? d.billingClientPurchase.purchaseToken
          : d.verificationData.serverVerificationData;
      if (token.isEmpty) return null;
      // A declared one-time product routes to one-time (NON_RENEWING) validation + carries its
      // price from the cached ProductDetails. Subscriptions send only the token.
      final isOneTime = _oneTimeProductIds.contains(d.productID);
      final product = isOneTime ? _oneTimeProducts[d.productID] : null;
      return _Proof(
        dedupId: token,
        platform: 'android',
        purchaseToken: token,
        productId: isOneTime ? d.productID : null,
        price: product?.rawPrice,
        currency: product?.currencyCode,
      );
    }
  }

  Future<PurchaseResult> _report(_Proof p) => InfluTo.instance.reportPurchase(
        platform: p.platform,
        signedTransaction: p.signedTransaction,
        purchaseToken: p.purchaseToken,
        productId: p.productId,
        price: p.price,
        currency: p.currency,
      );

  // --------------------------------------------------------------------- dedup

  Future<Set<String>> _loadReported() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_reportedKey);
      if (raw == null) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toSet();
      }
      return <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveReported(Set<String> set) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = set.toList();
      if (list.length > _maxReported) {
        list = list.sublist(list.length - _maxReported);
      }
      await prefs.setString(_reportedKey, jsonEncode(list));
    } catch (_) {
      // best-effort; backend idempotency is the backstop.
    }
  }
}

/// Internal normalized proof from a [PurchaseDetails].
class _Proof {
  final String dedupId;
  final String platform; // 'ios' | 'android'
  final String? signedTransaction;
  final String? purchaseToken;

  /// Android one-time products only (routes to one-time validation).
  final String? productId;
  final double? price;
  final String? currency;

  const _Proof({
    required this.dedupId,
    required this.platform,
    this.signedTransaction,
    this.purchaseToken,
    this.productId,
    this.price,
    this.currency,
  });
}
