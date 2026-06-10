// API base URL resolution.
//
// Resolution order:
//   1. Build-time override (escape hatch for local development):
//        flutter build linux --dart-define=LIBREFY_API=http://127.0.0.1:8080
//   2. Otherwise: the public Librefy demo backend on the VPS, both in
//      debug and release builds. This keeps a freshly-cloned checkout
//      playable on first launch without any extra wiring.
//
// The user can still point Librefy at a self-hosted librefyd from the
// Settings screen — that choice is persisted via [ApiBaseUrlStore].

class ApiConfig {
  const ApiConfig._();

  /// Public, libre-only demo backend run by the Librefy project.
  /// Plain HTTP because the host has no domain yet; the Android manifest
  /// whitelists this IP in network_security_config.xml.
  static const publicDemoBaseUrl = 'http://194.31.223.9:8088';

  static String defaultBaseUrl() {
    const override = String.fromEnvironment('LIBREFY_API');
    if (override.isNotEmpty) return override;
    return publicDemoBaseUrl;
  }
}
