import 'dart:async';
import 'dart:io';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:influto/influto.dart';

/// Minimal `in_app_purchase` wrapper — the best-practice reference. Buy → extract the
/// raw store proof (iOS StoreKit 2 JWS / Android purchaseToken) → InfluTo.reportPurchase
/// → complete. NEVER calls enableStoreKit1() (that returns the SK1 receipt, not a JWS).
class PurchaseManager {
  PurchaseManager({
    required this.appUserId,
    required this.referralCode,
    required this.onResult,
  });

  final String Function() appUserId;
  final String? Function() referralCode;
  final void Function(String) onResult;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> start() async {
    if (Platform.isIOS) {
      // SK2 is already the default on iOS 15+; be explicit so we never get the SK1 receipt.
      InAppPurchaseStoreKitPlatform.enableStoreKit2();
    }
    _sub = _iap.purchaseStream.listen(
      _onUpdate,
      onDone: () => _sub?.cancel(),
      onError: (Object e) => onResult('stream error: $e'),
    );
  }

  Future<void> buy(String productId) async {
    if (!await _iap.isAvailable()) {
      onResult('Store not available on this device.');
      return;
    }
    final resp = await _iap.queryProductDetails({productId});
    if (resp.productDetails.isEmpty) {
      onResult("Product '$productId' not found. Define it in the store + join a test track.");
      return;
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: resp.productDetails.first),
    );
  }

  Future<void> _onUpdate(List<PurchaseDetails> purchases) async {
    for (final d in purchases) {
      if (d.status == PurchaseStatus.pending) {
        onResult('⏳ pending…');
        continue;
      }
      if (d.status == PurchaseStatus.error) {
        onResult('❌ ${d.error?.message ?? 'purchase error'}');
      } else if (d.status == PurchaseStatus.purchased ||
          d.status == PurchaseStatus.restored) {
        await _report(d);
      }
      // ALWAYS complete, or the store re-delivers / Play auto-refunds.
      if (d.pendingCompletePurchase) {
        await _iap.completePurchase(d);
      }
    }
  }

  Future<void> _report(PurchaseDetails d) async {
    try {
      final PurchaseResult r;
      if (Platform.isIOS) {
        // StoreKit 2 JWS (== SK2PurchaseDetails.jwsRepresentation).
        final jws = d.verificationData.serverVerificationData;
        r = await InfluTo.instance.reportPurchase(
          platform: 'ios',
          signedTransaction: jws,
          appUserId: appUserId(),
          referralCode: referralCode(),
        );
      } else {
        final token = (d as GooglePlayPurchaseDetails)
            .billingClientPurchase
            .purchaseToken;
        r = await InfluTo.instance.reportPurchase(
          platform: 'android',
          purchaseToken: token,
          appUserId: appUserId(),
          referralCode: referralCode(),
        );
      }
      onResult(
        r.success
            ? '✅ reported · validated=${r.validated} env=${r.environment}'
            : '⚠️ reportPurchase success=false',
      );
    } catch (e) {
      onResult('❌ reportPurchase: $e');
    }
  }

  void dispose() => _sub?.cancel();
}
