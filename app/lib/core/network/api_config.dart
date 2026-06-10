// API base URL resolution.
//
// Resolution order:
//   1. Build-time override:
//        flutter build linux --dart-define=LIBREFY_API=https://your.host
//   2. Debug builds → local backend (Android emulator host on Android,
//      127.0.0.1 elsewhere). This is what `flutter run` developers see.
//   3. Release builds → the public demo backend so a freshly-installed
//      APK has tracks on first launch. Users can change it from
//      Settings → Backend URL.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();

  /// Public, libre-only demo backend run by the Librefy project.
  /// Plain HTTP because the host has no domain yet; the Android manifest
  /// whitelists this IP in network_security_config.xml.
  static const publicDemoBaseUrl = 'http://194.31.223.9:8088';

  static String defaultBaseUrl() {
    const override = String.fromEnvironment('LIBREFY_API');
    if (override.isNotEmpty) return override;

    if (kReleaseMode) return publicDemoBaseUrl;

    if (Platform.isAndroid) {
      // Android emulator's loopback to host machine.
      return 'http://10.0.2.2:8080';
    }
    return 'http://127.0.0.1:8080';
  }
}
