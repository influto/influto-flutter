/// Thrown by the throwing methods (`initialize`, `reportPurchase`) on failure.
class InfluToException implements Exception {
  final int? statusCode;
  final String? body;
  final String? message;

  InfluToException({this.statusCode, this.body, this.message});

  /// True for a 503 (FX rate momentarily unavailable) / 5xx — the caller should retry.
  bool get retryable =>
      statusCode == 503 || (statusCode != null && statusCode! >= 500);

  /// True for a 400 — the app is not configured for store-direct on this platform.
  bool get notConfigured => statusCode == 400;

  @override
  String toString() =>
      'InfluToException(${statusCode ?? message ?? 'unknown'}${body != null ? ': $body' : ''})';
}

/// Result of [InfluTo.checkAttribution].
class AttributionResult {
  final bool attributed;
  final String? referralCode;
  final String? attributionMethod;
  final String? clickedAt;
  final double? confidence;
  final String? message;

  const AttributionResult({
    required this.attributed,
    this.referralCode,
    this.attributionMethod,
    this.clickedAt,
    this.confidence,
    this.message,
  });

  /// From the `/sdk/track-install` response (snake_case).
  factory AttributionResult.fromResponse(Map<String, dynamic> j) =>
      AttributionResult(
        attributed: j['attributed'] == true,
        referralCode: j['referral_code'] as String?,
        attributionMethod: j['attribution_method'] as String?,
        clickedAt: j['clicked_at'] as String?,
        confidence: (j['confidence'] as num?)?.toDouble(),
        message: j['message'] as String?,
      );

  /// From the locally-stored attribution blob (camelCase, matching RN persistence).
  factory AttributionResult.fromStored(Map<String, dynamic> j) =>
      AttributionResult(
        attributed: j['attributed'] == true,
        referralCode: j['referralCode'] as String?,
        attributionMethod: j['attributionMethod'] as String?,
        clickedAt: j['clickedAt'] as String?,
        message: j['message'] as String?,
      );

  Map<String, dynamic> toStored() => {
        'attributed': attributed,
        if (referralCode != null) 'referralCode': referralCode,
        if (attributionMethod != null) 'attributionMethod': attributionMethod,
        if (clickedAt != null) 'clickedAt': clickedAt,
        if (message != null) 'message': message,
      };
}

/// A campaign from `/sdk/campaigns`.
class Campaign {
  final String id;
  final String name;
  final String? description;
  final double? commissionPercentage;

  const Campaign({
    required this.id,
    required this.name,
    this.description,
    this.commissionPercentage,
  });

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
        id: j['id']?.toString() ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        commissionPercentage: (j['commission_percentage'] as num?)?.toDouble(),
      );
}

/// Campaign details nested in validate/set results.
class CampaignInfo {
  final String id;
  final String name;
  final String? description;
  final double? commissionPercentage;
  final String? campaignType;

  const CampaignInfo({
    required this.id,
    required this.name,
    this.description,
    this.commissionPercentage,
    this.campaignType,
  });

  factory CampaignInfo.fromJson(Map<String, dynamic> j) => CampaignInfo(
        id: j['id']?.toString() ?? '',
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        commissionPercentage: (j['commission_percentage'] as num?)?.toDouble(),
        campaignType: j['campaign_type'] as String?,
      );
}

/// Influencer details, when available.
class Influencer {
  final String name;
  final String? socialHandle;
  final int? followerCount;

  const Influencer({required this.name, this.socialHandle, this.followerCount});

  factory Influencer.fromJson(Map<String, dynamic> j) => Influencer(
        name: j['name'] as String? ?? '',
        socialHandle: j['social_handle'] as String?,
        followerCount: (j['follower_count'] as num?)?.toInt(),
      );
}

/// Options for [InfluTo.trackEvent].
class TrackEventOptions {
  final String eventType;
  final String appUserId;
  final Map<String, dynamic>? properties;
  final String? referralCode;

  /// Optional idempotency key; the SDK auto-generates a UUID v4 when omitted.
  final String? eventId;

  const TrackEventOptions({
    required this.eventType,
    required this.appUserId,
    this.properties,
    this.referralCode,
    this.eventId,
  });
}

/// Result of [InfluTo.validateCode] / [InfluTo.applyCode].
class CodeValidationResult {
  final bool valid;
  final String? code;
  final CampaignInfo? campaign;
  final Influencer? influencer;
  final Map<String, dynamic>? customData;
  final String? message;
  final String? error;

  /// 'INVALID_FORMAT' | 'CODE_NOT_FOUND' | 'CODE_EXPIRED' | 'NETWORK_ERROR'.
  final String? errorCode;

  /// Populated by [InfluTo.applyCode].
  final bool? applied;

  const CodeValidationResult({
    required this.valid,
    this.code,
    this.campaign,
    this.influencer,
    this.customData,
    this.message,
    this.error,
    this.errorCode,
    this.applied,
  });

  factory CodeValidationResult.fromJson(Map<String, dynamic> j) =>
      CodeValidationResult(
        valid: j['valid'] == true,
        code: j['code'] as String?,
        campaign: j['campaign'] is Map<String, dynamic>
            ? CampaignInfo.fromJson(j['campaign'] as Map<String, dynamic>)
            : null,
        influencer: j['influencer'] is Map<String, dynamic>
            ? Influencer.fromJson(j['influencer'] as Map<String, dynamic>)
            : null,
        customData: j['custom_data'] as Map<String, dynamic>?,
        message: j['message'] as String?,
        error: j['error'] as String?,
        errorCode: j['error_code'] as String?,
      );

  CodeValidationResult copyWith({bool? applied}) => CodeValidationResult(
        valid: valid,
        code: code,
        campaign: campaign,
        influencer: influencer,
        customData: customData,
        message: message,
        error: error,
        errorCode: errorCode,
        applied: applied ?? this.applied,
      );
}

/// Result of [InfluTo.setReferralCode].
class SetCodeResult {
  final bool success;
  final String? code;
  final String? message;
  final CampaignInfo? campaign;

  /// True when this code is a developer free-access (comp) code.
  final bool? freeAccess;
  /// True when the backend granted native premium access for this redemption.
  final bool? grantsAccess;
  /// Granted entitlement id/lookup-key, if any.
  final String? entitlement;
  /// ISO-8601 expiry, or null for open-ended.
  final String? expiresAt;

  const SetCodeResult({
    required this.success,
    this.code,
    this.message,
    this.campaign,
    this.freeAccess,
    this.grantsAccess,
    this.entitlement,
    this.expiresAt,
  });

  factory SetCodeResult.fromJson(Map<String, dynamic> j) => SetCodeResult(
        success: j['success'] == true,
        code: j['code'] as String?,
        message: j['message'] as String?,
        campaign: j['campaign'] is Map<String, dynamic>
            ? CampaignInfo.fromJson(j['campaign'] as Map<String, dynamic>)
            : null,
        freeAccess: j['free_access'] as bool?,
        grantsAccess: j['grants_access'] as bool?,
        entitlement: j['entitlement'] as String?,
        expiresAt: j['expires_at'] as String?,
      );
}

/// Result of [InfluTo.checkAccess] — server-authoritative premium access (platform-independent comp).
class AccessResult {
  final bool hasAccess;
  final String? source;
  final String? entitlement;
  final String? expiresAt;
  final String? code;

  const AccessResult({
    required this.hasAccess,
    this.source,
    this.entitlement,
    this.expiresAt,
    this.code,
  });

  factory AccessResult.fromJson(Map<String, dynamic> j) => AccessResult(
        hasAccess: j['has_access'] == true,
        source: j['source'] as String?,
        entitlement: j['entitlement'] as String?,
        expiresAt: j['expires_at'] as String?,
        code: j['code'] as String?,
      );
}

/// Result of [InfluTo.reportPurchase] (store-direct).
class PurchaseResult {
  final bool success;

  /// The provider that validated the purchase: 'apple' | 'google' (a STRING).
  final String? validated;
  final String? environment;
  final String? eventType;
  final Map<String, dynamic>? result;

  const PurchaseResult({
    required this.success,
    this.validated,
    this.environment,
    this.eventType,
    this.result,
  });

  factory PurchaseResult.fromJson(Map<String, dynamic> j) => PurchaseResult(
        success: j['success'] == true,
        validated: j['validated'] as String?,
        environment: j['environment'] as String?,
        eventType: j['event_type'] as String?,
        result: j['result'] as Map<String, dynamic>?,
      );
}
