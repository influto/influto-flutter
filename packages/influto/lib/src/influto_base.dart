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

  static const String _sdkVersion = '1.1.1';

  InfluToConfig? _config;
  ApiClient? _api;
  Storage? _storage;
  bool _initialized = false;
  bool _storeDirect = false;

  /// True when auto-capture should run: the app is store-direct (per `/sdk/init`) AND the
  /// host hasn't opted out via `InfluToConfig.autoCapture: false`. The `influto_iap`
  /// `InfluToPurchaseObserver` reads this so RevenueCat apps are never captured.
  bool get autoCaptureEnabled => _storeDirect && (_config?.autoCapture ?? true);

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
        _storeDirect = resp['store_direct'] == true;
        await _storage!.putString(Storage.initialized, 'true');
        _log('SDK initialized');
      }
    } catch (e) {
      _log('Initialization failed: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------- checkAttribution

  /// Track install + resolve install attribution. Fail-soft → `attributed:false`.
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
      final body = _deviceInfo();
      body['device_id'] = await _installId();
      final resp = await _api!.postObject('/sdk/track-install', body);
      final code = resp['referral_code'] as String?;
      if (resp['attributed'] == true && code != null) {
        final attribution = AttributionResult.fromResponse(resp);
        await _storage!
            .putString(Storage.attribution, jsonEncode(attribution.toStored()));
        await _storage!.putString(Storage.influtoCode, code);
        await _setRevenueCatAttributes(code);
        return attribution;
      }
      final organic = AttributionResult(
        attributed: false,
        message: resp['message'] as String? ?? 'No attribution found',
      );
      // Persist the ORGANIC result too (contract 1.6.0): persisting only
      // attributed results made every organic user re-POST track-install on
      // every cold start. A thrown request (catch) persists nothing, so a
      // failed attempt retries on the next launch.
      await _storage!
          .putString(Storage.attribution, jsonEncode(organic.toStored()));
      return organic;
    } catch (e) {
      _log('checkAttribution error: $e');
      return const AttributionResult(
          attributed: false, message: 'Error checking attribution',);
    }
  }

  /// Per-install UUID, generated once and persisted (shared preferences).
  Future<String> _installId() async {
    final existing = _storage!.getString(Storage.installId);
    if (existing != null) return existing;
    final fresh = generateUuidV4();
    await _storage!.putString(Storage.installId, fresh);
    return fresh;
  }

  /// Once-only monetization events get a DETERMINISTIC id from
  /// (type, user, sorted properties) so cross-launch re-fires collapse
  /// server-side; other events get a random uuid.
  static String _defaultEventId(
    String eventType,
    String appUserId,
    Map<String, dynamic>? properties,
  ) {
    const onceOnly = {
      'trial_started',
      'subscription_purchased',
      'subscription_renewed',
    };
    if (!onceOnly.contains(eventType)) return generateUuidV4();
    final entries = (properties ?? const <String, dynamic>{})
        .entries
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort();
    final canonical = entries.join('&');
    var h = 0x811c9dc5;
    for (final byte in canonical.codeUnits) {
      h ^= byte;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    final hex = h.toRadixString(16).padLeft(8, '0');
    return 'det:$eventType:$appUserId:$hex';
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
        'eventId': options.eventId ??
            _defaultEventId(
                options.eventType, options.appUserId, options.properties,),
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

  /// POST `/sdk/set-referral-code`; only once the backend accepts the code
  /// (`success == true`) persist it + the attribution record and set the RC
  /// attributes, so a rejected code is never stored or tagged. [appUserId]
  /// defaults to the user stored by [identifyUser] — free-access codes need one
  /// (`MISSING_USER_ID` otherwise). Fail-soft.
  Future<SetCodeResult> setReferralCode(String code,
      {String? appUserId,}) async {
    if (!_initialized) {
      return const SetCodeResult(
          success: false, message: 'SDK not initialized',);
    }
    final normalized = code.trim().toUpperCase();
    try {
      if (appUserId != null) {
        await _storage!.putString(Storage.appUserId, appUserId);
      }
      final uid = appUserId ?? _storage!.getString(Storage.appUserId);

      final resp = await _api!.postObject('/sdk/set-referral-code', {
        'code': normalized,
        if (uid != null) 'app_user_id': uid,
      });
      final result = SetCodeResult.fromJson(resp);
      if (result.success) {
        // Prefer the canonical (matched) code the backend returns over the input.
        final returned = result.code;
        final accepted =
            (returned != null && returned.isNotEmpty) ? returned : normalized;
        await _storage!.putString(Storage.influtoCode, accepted);
        final attribution = AttributionResult(
          attributed: true,
          referralCode: accepted,
          attributionMethod: 'manual_entry',
          clickedAt: DateTime.now().toUtc().toIso8601String(),
          message: 'Manually entered code',
        );
        await _storage!.putString(
            Storage.attribution, jsonEncode(attribution.toStored()),);
        await _setRevenueCatAttributes(accepted);
      }
      return result;
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

  // ------------------------------------------------------------------- checkAccess

  AccessResult? _accessCache;
  String? _accessCacheUid;
  int _accessCacheTs = 0;

  /// Server-authoritative premium-access check (platform-independent comp). Works for BOTH
  /// RevenueCat and store-direct apps. Fail-soft → `AccessResult(hasAccess:false)`; caches a
  /// positive result ~5 min. Gate premium on
  /// `rcEntitlementActive || (await InfluTo.instance.checkAccess(uid)).hasAccess`.
  Future<AccessResult> checkAccess({String? appUserId}) async {
    if (!_initialized) return const AccessResult(hasAccess: false);
    final uid = appUserId ?? _storage?.getString(Storage.appUserId);
    if (uid == null) return const AccessResult(hasAccess: false);

    final now = DateTime.now().millisecondsSinceEpoch;
    if (_accessCache != null &&
        _accessCacheUid == uid &&
        _accessCache!.hasAccess &&
        now - _accessCacheTs < 300000) {
      return _accessCache!;
    }
    // Persisted positive cache survives cold starts (same 5-min TTL as the in-memory one).
    final persisted = _loadPersistedAccess(uid, now);
    if (persisted != null) return persisted;
    try {
      final escaped = Uri.encodeQueryComponent(uid);
      final resp = await _api!.getObject('/sdk/access?app_user_id=$escaped');
      final result = AccessResult.fromJson(resp);
      if (result.hasAccess) await _persistAccess(uid, result, now);
      return result;
    } catch (e) {
      _log('checkAccess error: $e');
      return const AccessResult(hasAccess: false);
    }
  }

  /// Cache a positive access result in memory + persist it under [Storage.access].
  Future<void> _persistAccess(String uid, AccessResult result, int now) async {
    _accessCache = result;
    _accessCacheUid = uid;
    _accessCacheTs = now;
    try {
      final env = {
        'uid': uid,
        'ts': now,
        'access': {
          'has_access': result.hasAccess,
          'source': result.source,
          'entitlement': result.entitlement,
          'expires_at': result.expiresAt,
          'code': result.code,
        },
      };
      await _storage?.putString(Storage.access, jsonEncode(env));
    } catch (_) {/* best-effort; server is the backstop */}
  }

  /// Read a still-valid (~5 min) persisted positive access result for [uid], else null.
  AccessResult? _loadPersistedAccess(String uid, int now) {
    final raw = _storage?.getString(Storage.access);
    if (raw == null) return null;
    try {
      final env = jsonDecode(raw);
      if (env is! Map || env['uid'] != uid) return null;
      final ts = (env['ts'] as num?)?.toInt() ?? 0;
      if (now - ts >= 300000) return null;
      final result =
          AccessResult.fromJson(Map<String, dynamic>.from(env['access'] as Map));
      if (!result.hasAccess) return null;
      _accessCache = result;
      _accessCacheUid = uid;
      _accessCacheTs = ts;
      return result;
    } catch (_) {
      return null;
    }
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
    String? productId,
    double? price,
    String? currency,
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
      // One-time products only: productId routes to products.get; price is what the user paid.
      if (productId != null) 'productId': productId,
      if (price != null) 'price': price,
      if (currency != null) 'currency': currency,
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
