// Persistence for the user-chosen backend URL.
//
// The Settings screen lets the user point Librefy at a different
// librefyd instance. That choice must survive app restarts — otherwise
// every relaunch resets to the build-time default and the user has to
// re-enter the URL every time.
//
// We keep this in shared_preferences because it's a single short string
// and we don't need anything fancier. The store is read once on app
// startup (see main.dart bootstrap) and written every time the user
// presses "Apply" in Settings.
import 'package:shared_preferences/shared_preferences.dart';

class ApiBaseUrlStore {
  ApiBaseUrlStore(this._prefs);
  static const _key = 'librefy.apiBaseUrl.v1';

  final SharedPreferences _prefs;

  String? load() => _prefs.getString(_key);

  Future<void> save(String url) async {
    await _prefs.setString(_key, url);
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
