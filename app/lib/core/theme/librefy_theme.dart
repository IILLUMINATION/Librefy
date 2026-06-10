// Librefy Material 3 theme.
//
// Single seed colour drives both light and dark schemes. On Android 12+,
// the app may upgrade to a dynamic-colour scheme derived from the user's
// wallpaper (wired up at the MaterialApp level via dynamic_color).
//
// Typography uses Inter (via google_fonts) on top of the MD3 type scale —
// it reads better than Roboto at small sizes used for track titles.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Default seed colour when dynamic colour is unavailable.
const Color librefySeedColor = Color(0xFF6750A4);

class LibrefyTheme {
  const LibrefyTheme._();

  /// Builds the light ThemeData from a [ColorScheme]. Pass the dynamic
  /// scheme on supported Android versions, fall back to a seed-based one.
  static ThemeData light(ColorScheme scheme) => _base(scheme, Brightness.light);

  /// Builds the dark ThemeData from a [ColorScheme].
  static ThemeData dark(ColorScheme scheme) => _base(scheme, Brightness.dark);

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final textTheme = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        scrolledUnderElevation: 2,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide.none,
        labelStyle: textTheme.labelMedium,
        shape: const StadiumBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}
