// API base URL resolution.
//
// On Android emulator localhost = 10.0.2.2. On Linux desktop the app
// talks to a backend running on the same host. Override either at
// build time via --dart-define=LIBREFY_API=https://your.host or by
// editing the user-visible setting in the Settings screen (TODO).
import 'dart:io' show Platform;

class ApiConfig {
  const ApiConfig._();

  static String defaultBaseUrl() {
    const override = String.fromEnvironment('LIBREFY_API');
    if (override.isNotEmpty) return override;

    if (Platform.isAndroid) {
      // Android emulator's loopback to host machine.
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }
}
