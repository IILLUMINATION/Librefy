// Locale preference for the Librefy UI.
//
// State holds:
//   - null  → follow the system locale (default)
//   - en    → force English
//   - ru    → force Russian
//
// Persisted in SharedPreferences under [_kLocaleKey] so the choice
// survives app restart. The actual MaterialApp.locale binding lives in
// LibrefyApp's build method.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocaleKey = 'librefy.locale.v1';

/// Supported app locales. Order is what the settings UI shows.
const supportedLocales = <Locale>[
  Locale('en'),
  Locale('ru'),
];

class LocaleNotifier extends StateNotifier<Locale?> {
  LocaleNotifier(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static Locale? _load(SharedPreferences prefs) {
    final raw = prefs.getString(_kLocaleKey);
    if (raw == null || raw.isEmpty) return null;
    return Locale(raw);
  }

  /// [code] is "en" / "ru" / null (system default).
  Future<void> set(String? code) async {
    if (code == null || code.isEmpty) {
      await _prefs.remove(_kLocaleKey);
      state = null;
      return;
    }
    await _prefs.setString(_kLocaleKey, code);
    state = Locale(code);
  }
}

/// Riverpod entry-point. Wired in main.dart with a SharedPreferences
/// override; never read before bootstrap completes.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  throw UnimplementedError(
      'localeProvider must be overridden in main() once SharedPreferences resolves');
});
