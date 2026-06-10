// Librefy app entry point.
//
// Responsibilities:
//   - Initialise media_kit (must happen BEFORE any Player() instance).
//     media_kit ships its own libmpv via media_kit_libs_*, so the app
//     works out-of-the-box on every supported platform — no apt/brew
//     dependencies required.
//   - Build the MaterialApp with MD3 + dynamic colour when available.
//   - Hand control to go_router.
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/state/providers.dart';
import 'core/network/api_base_url_store.dart';
import 'core/router/app_router.dart';
import 'core/theme/librefy_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // Wires the bundled libmpv binaries into the process. Safe & idempotent.
  MediaKit.ensureInitialized();

  // SharedPreferences must be ready before the first widget that
  // consumes apiBaseUrlProvider builds, otherwise we'd flash the
  // build-time default before swapping to the persisted value.
  final prefs = await SharedPreferences.getInstance();
  final urlStore = ApiBaseUrlStore(prefs);

  runApp(
    ProviderScope(
      overrides: [
        apiBaseUrlStoreProvider.overrideWithValue(urlStore),
      ],
      child: const LibrefyApp(),
    ),
  );
}

class LibrefyApp extends ConsumerWidget {
  const LibrefyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return DynamicColorBuilder(
      builder: (lightDyn, darkDyn) {
        final lightScheme = lightDyn ??
            ColorScheme.fromSeed(seedColor: librefySeedColor, brightness: Brightness.light);
        final darkScheme = darkDyn ??
            ColorScheme.fromSeed(seedColor: librefySeedColor, brightness: Brightness.dark);
        return MaterialApp.router(
          title: 'Librefy',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: LibrefyTheme.light(lightScheme),
          darkTheme: LibrefyTheme.dark(darkScheme),
          routerConfig: router,
        );
      },
    );
  }
}
