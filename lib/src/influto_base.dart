import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;

import 'api_client.dart';
import 'config.dart';
import 'models.dart';
import 'storage.dart';
import 'uuid.dart';

/// InfluTo Flutter SDK — influencer attribution + store-direct purchase validation.
///
/// Singleton; mirrors the React Native SDK's public surface and behaviors. Fail-soft:
/// only [initialize] and [reportPurchase] throw.
///
/// ```dart
/// await InfluTo.instance.initialize(InfluToConfig(apiKey: 'it_...'));
/// final attr = await InfluTo.instance.checkAttribution();
/// ```
class InfluTo {
  InfluTo._();

  /// The shared singleton instance.
  static final InfluTo instance = InfluTo._();

  static const String _sdkVersion = '1.0.0';

  InfluToConfig? _config;
  ApiClient? _api;
  Storage? _storage;
  bool _initialized = false;

  bool get _debug => _config?.debug ?? false;
  void _log(String msg) {
    if (_debug) debugPrint('[InfluTo] $msg');
  }

  String _platform() {
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {}
    return 'android';
  }

  Map<String, dynamic> _deviceInfo() {
    final info = <String, dynamic>{'platform': _platform()};
    try {
      info['os_version'] = Platform.operatingSystemVersion;
    } catch (_) {}
    try {
      info['language'] = Platform.localeName;
    } catch (_) {}
    try {
      info['timezone'] = DateTime.now().timeZoneName;
    } catch (_) {}
    return info;
  }

  // ------------------------------------------------------------------ initialize

  /// Call once at startup. POST `/sdk/init`. Throws on failure.
  Future<void> initialize(InfluToConfig config) async {
    _config = config;
    _storage = await Storage.create();
    _api = ApiClient(
        baseUrl: config.apiUrl,
        apiKey: config.apiKey,
        client: config.httpClient,);
    try {
      final resp = await _api!.postObject('/sdk/init', {
        'app_version': config.appVersion ?? 'unknown',
        'sdk_version': _sdkVersion,
        'platform': _platform(),
      });
      if (resp['initialized'] == true) {
        _initialized = true;
        await _storage!.putString(Storage.initialized, 'true');
        _log('SDK initialized');
      }
    } catch (e) {
      _log('Initialization failed: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------- checkAttribution

  /// Track install + resolve IP/fingerprint attribution. Fail-soft → `attributed:false`.
  Future<AttributionResult> checkAttribution() async {
    if (!_initialized) {
      throw InfluToException(
          message: 'SDK not initialized. Call initialize() first.',);
    }
    try {
      final stored = _storage!.getString(Storage.attribution);
      if (stored != null) {
        return AttributionResult.fromStored(
            jsonDecode(stored) as Map<String, dynamic>,);
      }
      final resp = await _api!.postObject('/sdk/track-install', _deviceInfo());
      final code = resp['referral_code'] as String?;
      if (resp['attributed'] == true && code != null) {
        final attribution = AttributionResult.fromResponse(resp);
        await _storage!
            .putString(Storage.attribution, jsonEncode(attribution.toStored()));
        await _storage!.putString(Storage.influtoCode, code);
        await _setRevenueCatAttributes(code);
        return attribution;
      }
      return AttributionResult(
        attributed: false,
        message: resp['message'] as String? ?? 'No attribution found',
      );
    } catch (e) {
      _log('checkAttribution error: $e');
      return const AttributionResult(
          attributed: false, message: 'Error checking attribution',);
    }
  }

  // ----------------------------------------------------------------- identifyUser

  /// Persist app_user_id + POST `/sdk/identify`. Fail-soft (no throw).
  Future<void> identifyUser(String appUserId,
      {Map<String, dynamic>? properties,}) async {
    if (!_initialized) {
      _log('SDK not initialized');
      return;
    }
    await _storage!.putString(Storage.appUserId, appUserId);
    try {
      await _api!.postObject('/sdk/identify', {
        'app_user_id': appUserId,
        'properties': properties ?? <String, dynamic>{},
      });
    } catch (e) {
      _log('identify error: $e');
    }
  }

  // ------------------------------------------------------------------- trackEvent

  /// POST `/sdk/event`. Auto-generates a UUID v4 eventId if absent. Fail-soft.
  Future<void> trackEvent(TrackEventOptions options) async {
    if (!_initialized) {
      _log('SDK not initialized');
      return;
    }
    try {
      await _api!.postObject('/sdk/event', {
        'eventType': options.eventType,
        'appUserId': options.appUserId,
        if (options.properties != null) 'properties': options.properties,
        if (options.referralCode != null) 'referralCode': options.referralCode,
        'eventId': options.eventId ?? generateUuidV4(),
      });
    } catch (e) {
      _log('trackEvent error: $e');
    }
  }

  // ------------------------------------------------------------ getActiveCampaigns

  /// GET `/sdk/campaigns`. Fail-soft → `[]`.
  Future<List<Campaign>> getActiveCampaigns() async {
    if (!_initialized) return [];
    try {
      final list = await _api!.getList('/sdk/campaigns');
      return list
          .whereType<Map<String, dynamic>>()
          .map(Campaign.fromJson)
          .toList(growable: false);
    } catch (e) {
      _log('campaigns error: $e');
      return [];
    }
  }

  // ----------------------------------------------------------- local read helpers

  /// Local read of the stored referral code.
  Future<String?> getReferralCode() async =>
      _storage?.getString(Storage.influtoCode);

  /// Local: stored code only if the stored attribution is `attributed`.
  Future<String?> getPrefilledCode() async {
    final stored = _storage?.getString(Storage.attribution);
    if (stored == null) return null;
    try {
      final a = AttributionResult.fromStored(
          jsonDecode(stored) as Map<String, dynamic>,);
      return a.attributed ? a.referralCode : null;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------- validateCode

  /// POST `/sdk/validate-code` with a normalized (trim + UPPERCASE) code. Fail-soft.
  Future<CodeValidationResult> validateCode(String code) async {
    if (!_initialized) {
      return const CodeValidationResult(
        valid: false,
        error: 'SDK not initialized',
        errorCode: 'NETWORK_ERROR',
      );
    }
    try {
      final resp = await _api!.postObject(
          '/sdk/validate-code', {'code': code.trim().toUpperCase()},);
      return CodeValidationResult.fromJson(resp);
    } catch (e) {
      _log('validateCode error: $e');
      return const CodeValidationResult(
        valid: false,
        error: 'Network error or invalid response',
        errorCode: 'NETWORK_ERROR',
      );
    }
  }

  // --------------------------------------------------------------- setReferralCode

  /// Persist code + attribution, set RC attributes, POST `/sdk/set-referral-code`.
  Future<SetCodeResult> setReferralCode(String code,
      {String? appUserId,}) async {
    if (!_initialized) {
      return const SetCodeResult(
          success: false, message: 'SDK not initialized',);
    }
    final normalized = code.trim().toUpperCase();
    try {
      await _storage!.putString(Storage.influtoCode, normalized);
      final attribution = AttributionResult(
        attributed: true,
        referralCode: normalized,
        attributionMethod: 'manual_entry',
        clickedAt: DateTime.now().toUtc().toIso8601String(),
        message: 'Manually entered code',
      );
      await _storage!
          .putString(Storage.attribution, jsonEncode(attribution.toStored()));
      await _setRevenueCatAttributes(normalized);
      if (appUserId != null) {
        await _storage!.putString(Storage.appUserId, appUserId);
      }

      final resp = await _api!.postObject('/sdk/set-referral-code', {
        'code': normalized,
        if (appUserId != null) 'app_user_id': appUserId,
      });
      return SetCodeResult.fromJson(resp);
    } catch (e) {
      _log('setReferralCode error: $e');
      return SetCodeResult(success: false, message: 'Failed to set code: $e');
    }
  }

  // ------------------------------------------------------------------- applyCode

  /// [validateCode] then [setReferralCode] if valid; sets `applied`.
  Future<CodeValidationResult> applyCode(String code,
      {String? appUserId,}) async {
    final validation = await validateCode(code);
    if (!validation.valid) return validation.copyWith(applied: false);
    final set = await setReferralCode(code, appUserId: appUserId);
    return validation.copyWith(applied: set.success);
  }

  // --------------------------------------------------------------- reportPurchase

  /// Store-direct purchase report (no RevenueCat). The host obtains the proof from its
  /// own IAP layer (`in_app_purchase` / `purchases_flutter`) and passes it in:
  /// iOS → [signedTransaction] (StoreKit2 JWS), Android → [purchaseToken].
  /// Throws on failure ([InfluToException.retryable] is true for a 503 FX miss).
  Future<PurchaseResult> reportPurchase({
    required String platform,
    String? signedTransaction,
    String? purchaseToken,
    String? appUserId,
    String? referralCode,
  }) async {
    if (!_initialized) throw InfluToException(message: 'SDK not initialized');
    final code = referralCode ?? _storage!.getString(Storage.influtoCode);
    final user = appUserId ?? _storage!.getString(Storage.appUserId);
    final resp = await _api!.postObject('/sdk/purchase', {
      'platform': platform.toLowerCase(),
      if (signedTransaction != null) 'signedTransaction': signedTransaction,
      if (purchaseToken != null) 'purchaseToken': purchaseToken,
      if (code != null) 'referralCode': code,
      if (user != null) 'appUserId': user,
    });
    _log('purchase reported: ${resp['validated']}');
    return PurchaseResult.fromJson(resp);
  }

  // ------------------------------------------------------------- clearAttribution

  /// Local clear of attribution / code / app_user_id.
  Future<void> clearAttribution() async {
    await _storage
        ?.remove([Storage.attribution, Storage.influtoCode, Storage.appUserId]);
  }

  // ------------------------------------------------------------------- internals

  Future<void> _setRevenueCatAttributes(String code) async {
    final hook = _config?.revenueCatHook;
    if (hook == null) return;
    try {
      await hook({'influto_code': code, 'influto_referral': 'true'});
    } catch (e) {
      _log('RevenueCat hook error: $e');
    }
  }
}
