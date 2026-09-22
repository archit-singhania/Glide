import 'package:flutter/material.dart';

import '../shared/glide_glass.dart';

const Color _seed = Color(0xFF6E7BFF);

/// Glide's premium, glassmorphism-styled Material 3 theme for [brightness].
///
/// The look is built from two layers:
/// - Material 3's own [ColorScheme], seeded from one accent colour, which
///   drives text/icon colours and component defaults.
/// - [GlideTokens], a [ThemeExtension] with the extra colours the glass
///   surfaces in `shared/glide_glass.dart` need (background gradient, glow
///   blobs, frosted fills). Screens read these via `glideTokens(context)`
///   instead of hard-coding colours, so the whole look can be re-tuned here.
ThemeData glideTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final tokens = isDark ? GlideTokens.dark : GlideTokens.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );
  final radius = BorderRadius.circular(16);
  final borderSide = BorderSide(color: tokens.glassBorder);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: tokens.backgroundGradient.first,
    extensions: <ThemeExtension<dynamic>>[tokens],
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    textTheme: _textTheme(isDark),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
        color: colorScheme.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        side: borderSide,
        foregroundColor: colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        backgroundColor: tokens.glassFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: borderSide,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.glassFill,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      border: OutlineInputBorder(borderRadius: radius, borderSide: borderSide),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: borderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colorScheme.error),
      ),
    ),
    dividerTheme: DividerThemeData(color: tokens.glassBorder, space: 24),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tokens.backgroundGradient.first,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: tokens.glassFill,
    ),
  );
}

TextTheme _textTheme(bool isDark) {
  const base = Typography.blackMountainView;
  var theme = isDark ? Typography.whiteMountainView : base;
  theme = theme.copyWith(
    titleLarge: theme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: theme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleSmall: theme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: theme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    ),
    bodyMedium: theme.bodyMedium?.copyWith(height: 1.4),
  );
  return theme;
}
