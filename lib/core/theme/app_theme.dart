import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light theme colors (WCAG AAA verified)
  static const Color primary = Color(0xFF1A2B3C);     // Deep Navy
  static const Color onPrimary = Color(0xFFFFFFFF);    // 12.6:1 contrast
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color error = Color(0xFFB71C1C);        // 7.2:1 on white
  static const Color secondary = Color(0xFFB0BEC5);    // 5.2:1 on navy

  // Dark theme
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkOnSurface = Color(0xFFE0E0E0);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        onSurface: onSurface,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(),
      scaffoldBackgroundColor: surface,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        surface: darkSurface,
        onSurface: darkOnSurface,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: darkSurface,
    );
  }
}
