import 'package:flutter/material.dart';

const safeGreen = Color(0xFF147D64);
const warningAmber = Color(0xFFC78112);
const dangerousOrange = Color(0xFFD65F32);
const criticalRed = Color(0xFFBE3F51);
const ink = Color(0xFF182420);
const mutedInk = Color(0xFF60706A);
const appBackground = Color(0xFFF1F5F3);
const surface = Color(0xFFFBFCFB);
const softSurface = Color(0xFFE8EFEC);
const outline = Color(0xFFD6E0DC);
const accent = Color(0xFF176B5B);

Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'safe':
    case 'fresh':
    case 'info':
      return safeGreen;
    case 'warning':
    case 'ripe':
      return warningAmber;
    case 'dangerous':
    case 'deteriorating':
      return dangerousOrange;
    case 'danger':
    case 'critical':
    case 'spoiled':
      return criticalRed;
    default:
      return mutedInk;
  }
}

ThemeData buildTheme() {
  const scheme = ColorScheme.light(
    primary: accent,
    onPrimary: Colors.white,
    secondary: Color(0xFF536F67),
    onSecondary: Colors.white,
    error: criticalRed,
    onError: Colors.white,
    surface: surface,
    onSurface: ink,
    outline: Color(0xFF82918B),
    outlineVariant: outline,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF6F9F7),
    surfaceContainer: softSurface,
    surfaceContainerHigh: Color(0xFFE0E8E4),
  );

  const textTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 34,
      height: 1.1,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    headlineLarge: TextStyle(
      fontSize: 30,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    headlineSmall: TextStyle(
      fontSize: 21,
      height: 1.25,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: ink,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: ink,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: mutedInk,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      height: 1.2,
      fontWeight: FontWeight.w700,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w700,
      color: mutedInk,
    ),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: appBackground,
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    cardTheme: const CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: outline),
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: appBackground,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 0,
      backgroundColor: surface,
      indicatorColor: accent.withValues(alpha: 0.12),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight:
              states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
          color: states.contains(WidgetState.selected) ? accent : mutedInk,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? accent : mutedInk,
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: outline,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected)
                ? accent
                : const Color(0xFFC8D3CE),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}
