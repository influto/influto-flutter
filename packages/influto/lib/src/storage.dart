import 'package:shared_preferences/shared_preferences.dart';

/// Local key-value persistence over `shared_preferences` (the AsyncStorage analog).
/// Keys mirror the React Native SDK's `@influto/` prefix byte-for-byte.
class Storage {
  static const String attribution = '@influto/attribution';
  static const String influtoCode = '@influto/influto_code';
  static const String appUserId = '@influto/app_user_id';
  static const String initialized = '@influto/initialized';
  static const String access = '@influto/access';

  final SharedPreferences _prefs;
  Storage._(this._prefs);

  static Future<Storage> create() async =>
      Storage._(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString(key);

  Future<void> putString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> remove(List<String> keys) async {
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}
