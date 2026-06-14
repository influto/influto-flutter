/// Called by the SDK when an `influto_code` is established (attribution or manual
/// entry). The host implements it with one line of `purchases_flutter`, keeping the
/// RevenueCat dependency in the APP — never in this SDK:
///
/// ```dart
/// revenueCatHook: (attrs) => Purchases.setAttributes(attrs),
/// ```
///
/// The SDK always calls it with `{influto_code: <code>, influto_referral: "true"}`
/// (the value is the literal string `"true"`, which RevenueCat Targeting matches on).
typedef RevenueCatHook = Future<void> Function(Map<String, String> attributes);
