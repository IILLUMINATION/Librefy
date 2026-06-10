// Librefy app entry point.
//
// Responsibilities:
//   - Initialise media_kit (must happen BEFORE any Player() instance).
//     media_kit ships its own libmpv via media_kit_libs_*, so the app
//     works out-of-the-box on every supported platform — no apt/brew
//     dependencies required.
//   - Build the MaterialApp with MD3 + dynamic colour when available.
//   - Hand control to go_router.
//
// Cold-start budget: we deliberately do NOT await SharedPreferences (or
// any other I/O) before runApp(). The first frame is a lightweight
// MaterialApp showing a splash; once shared_preferences resolves the
// real app tree mounts. Doing it the other way around — `await prefs;
// runApp(...)` — synchronously holds back the first frame by ~100–300ms
// on Android and is the main reason the Linux build saw "Davey!
// duration=5561ms" / "Skipped 325 frames!" warnings on cold start.
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'application/audio/audio_providers.dart';
import 'application/library/user_library.dart';
import 'application/state/locale_provider.dart';
import 'application/state/providers.dart';
import 'core/network/api_base_url_store.dart';
import 'core/router/app_router.dart';
import 'core/theme/librefy_theme.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // Wires the bundled libmpv binaries into the process. Safe & idempotent.
  // Synchronous and cheap on first call (~ms); subsequent calls are no-ops.
  MediaKit.ensureInitialized();

  // Kick SharedPreferences off without awaiting — we'll let the splash
  // widget block on this Future. By starting it before runApp() we use
  // the gap between MediaKit init and the engine attaching to gather
  // prefs in parallel; in practice the future is already done by the
  // time the first frame rasterises.
  final prefsFuture = SharedPreferences.getInstance();

  runApp(_RootBootstrap(prefsFuture: prefsFuture));
}

/// Bootstraps the real Riverpod tree once SharedPreferences is ready.
/// Shows a minimal Material splash in the meantime so the first frame
/// goes out the door immediately.
class _RootBootstrap extends StatelessWidget {
  const _RootBootstrap({required this.prefsFuture});
  final Future<SharedPreferences> prefsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: prefsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            snap.data == null) {
          // Splash. Plain MaterialApp so theming / textDirection work,
          // but no router and no provider scope yet — keeps the first
          // frame as cheap as possible.
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme:
                  ColorScheme.fromSeed(seedColor: librefySeedColor),
              useMaterial3: true,
            ),
            home: const _SplashScreen(),
          );
        }
        final prefs = snap.data!;
        final urlStore = ApiBaseUrlStore(prefs);
        return ProviderScope(
          overrides: [
            apiBaseUrlStoreProvider.overrideWithValue(urlStore),
            sharedPreferencesProvider.overrideWithValue(prefs),
            localeProvider.overrideWith((_) => LocaleNotifier(prefs)),
          ],
          child: const LibrefyApp(),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_rounded,
                size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Librefy',
                style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}

class LibrefyApp extends ConsumerStatefulWidget {
  const LibrefyApp({super.key});

  @override
  ConsumerState<LibrefyApp> createState() => _LibrefyAppState();
}

class _LibrefyAppState extends ConsumerState<LibrefyApp> {
  @override
  void initState() {
    super.initState();
    // Eagerly warm up the native libtorrent session so the first
    // "play" tap on a magnet-backed track doesn't have to wait for
    // dlopen + lt_create. Safe to fire from the UI isolate now because
    // LibtorrentService dispatches the blocking FFI calls onto a
    // worker isolate (Isolate.run); doing this synchronously on the UI
    // isolate previously caused ANRs.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ignore: discarded_futures
      ref.read(torrentServiceProvider.future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final locale = ref.watch(localeProvider);
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
          // null locale = follow system; otherwise force the user choice.
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        );
      },
    );
  }
}
