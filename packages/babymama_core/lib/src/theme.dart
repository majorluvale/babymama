import 'package:flutter/material.dart';

class BmColors {
  static const primary = Color(0xFF0E7C7B); // teal
  static const accent = Color(0xFFF28C6B); // coral
  static const ink = Color(0xFF1F2933);
  static const muted = Color(0xFF6B7280);
  static const surface = Color(0xFFF6F4F1);
  static const line = Color(0xFFE7E2DA);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);
  static const danger = Color(0xFFDC2626);
}

/// Content width of the website on large screens; the page background shows on both sides.
const kSiteMaxWidth = 1200.0;

/// Below this width the apps use the phone layout (bottom navigation, app bar).
const kWideBreakpoint = 900.0;

ThemeData bmTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BmColors.primary,
    primary: BmColors.primary,
    secondary: BmColors.accent,
  );
  final radius = BorderRadius.circular(10);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: BmColors.ink,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: BmColors.surface,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: const BorderSide(color: BmColors.primary)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}
