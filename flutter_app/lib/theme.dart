import 'package:flutter/material.dart';

// The original code-drawn jacket keeps its own print-inspired palette.
const ink = Color(0xFF193E36);
const paper = Color(0xFFF6F5EF);
const muted = Color(0xFF727A72);

ThemeData novelTheme(Brightness brightness, {bool ereader = false}) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8F76B5),
    brightness: brightness,
    dynamicSchemeVariant: ereader
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
  );
  final colors = ereader
      ? base.copyWith(
          surface: dark ? Colors.black : Colors.white,
          primary: dark ? Colors.white : Colors.black,
          onSurface: dark ? Colors.white : Colors.black,
          onSurfaceVariant: dark
              ? const Color(0xFFDDDDDD)
              : const Color(0xFF333333),
          surfaceContainerLow: dark
              ? const Color(0xFF101010)
              : const Color(0xFFF9F9F9),
          surfaceContainer: dark
              ? const Color(0xFF171717)
              : const Color(0xFFF1F1F1),
          outline: dark ? const Color(0xFFCCCCCC) : const Color(0xFF444444),
        )
      : base;
  return ThemeData(
    pageTransitionsTheme: ereader
        ? PageTransitionsTheme(
            builders: {
              for (final platform in TargetPlatform.values)
                platform: const _StillPageTransition(),
            },
          )
        : const PageTransitionsTheme(),
    splashFactory: ereader ? NoSplash.splashFactory : InkSparkle.splashFactory,
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    fontFamily: 'DM Sans',
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      centerTitle: false,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surfaceContainerLow,
      indicatorColor: colors.secondaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: .45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

class _StillPageTransition extends PageTransitionsBuilder {
  const _StillPageTransition();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
