// Librefy app entry point.
//
// Responsibilities:
//   - Bootstrap audio_session + background-audio plumbing for Android.
//   - Build the MaterialApp with MD3 + dynamic colour when available.
//   - Hand control to go_router.
import 'dart:io' show Platform;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'core/router/app_router.dart';
import 'core/theme/librefy_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // Background playback service. Safe to call on every platform; the
  // package no-ops on platforms where it isn't supported.
  if (Platform.isAndroid || Platform.isIOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.librefy.audio',
      androidNotificationChannelName: 'Librefy playback',
      androidNotificationOngoing: true,
    );
  }

  runApp(const ProviderScope(child: LibrefyApp()));
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
