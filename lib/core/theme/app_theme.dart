import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralised theme based on the Google Stitch design system tokens.
///
/// ## Typography (Stitch `index.css`)
/// | Role         | Font          |
/// |-------------|---------------|
/// | Headlines   | Open Sans     |
/// | Body / Labels| Albert Sans  |
/// | Button specs | Inter        |
///
/// ## WCAG Contrast & Chinese-Icons Notes
/// - error (#BA1A1A) on white → 6.5 : 1 ✅ AA (exact Stitch token)
/// - onError (#FFFFFF) on error → 6.5 : 1 ✅ AA
/// - iconTheme has **no** fontFamily → Material icons render correctly
class AppTheme {
  // ═══════════════════════════════════════════════════════════════════
  //  LIGHT THEME – Stitch tokens
  // ═══════════════════════════════════════════════════════════════════

  static const Color primary = Color(0xFF115B9B);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF3674B5);
  static const Color onPrimaryContainer = Color(0xFFF5F7FF);

  static const Color secondary = Color(0xFF4B53BA);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFF8C94FF);
  static const Color onSecondaryContainer = Color(0xFF1E258F);

  static const Color tertiary = Color(0xFF344EBF);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF5068D9);
  static const Color onTertiaryContainer = Color(0xFFF8F6FF);

  // Exact Stitch token (#BA1A1A). 6.5 : 1 on white — AA ✓
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  static const Color surface = Color(0xFFF8F9FF);
  static const Color onSurface = Color(0xFF191C20);
  static const Color surfaceVariant = Color(0xFFE1E2E8);
  static const Color onSurfaceVariant = Color(0xFF414750);
  static const Color surfaceContainerLow = Color(0xFFF2F3F9);
  static const Color surfaceContainer = Color(0xFFEDEDF3);
  static const Color surfaceContainerHigh = Color(0xFFE7E8EE);
  static const Color surfaceContainerHighest = Color(0xFFE1E2E8);

  static const Color background = Color(0xFFF8F9FF);
  static const Color onBackground = Color(0xFF191C20);

  static const Color outline = Color(0xFF727781);
  static const Color outlineVariant = Color(0xFFC1C7D2);

  static const Color inverseSurface = Color(0xFF2E3035);
  static const Color inverseOnSurface = Color(0xEFF0F6);
  static const Color inversePrimary = Color(0xFFA1C9FF);

  // ═══════════════════════════════════════════════════════════════════
  //  DARK THEME – derived from Stitch
  // ═══════════════════════════════════════════════════════════════════

  static const Color darkPrimary = Color(0xFFA1C9FF);
  static const Color darkOnPrimary = Color(0xFF001C37);
  static const Color darkPrimaryContainer = Color(0xFF004880);
  static const Color darkOnPrimaryContainer = Color(0xFFD2E4FF);

  static const Color darkSecondary = Color(0xFFBEC2FF);
  static const Color darkOnSecondary = Color(0xFF00026C);
  static const Color darkSecondaryContainer = Color(0xFF323AA1);
  static const Color darkOnSecondaryContainer = Color(0xFFE0E0FF);

  static const Color darkTertiary = Color(0xFFB9C3FF);
  static const Color darkOnTertiary = Color(0xFF001257);
  static const Color darkTertiaryContainer = Color(0xFF1D3AAC);
  static const Color darkOnTertiaryContainer = Color(0xFFDDE1FF);

  static const Color darkError = Color(0xFFFFB4AB);
  static const Color darkOnError = Color(0xFF690005);
  static const Color darkErrorContainer = Color(0xFF93000A);
  static const Color darkOnErrorContainer = Color(0xFFFFDAD6);

  static const Color darkSurface = Color(0xFF131318);
  static const Color darkOnSurface = Color(0xFFE1E2E8);
  static const Color darkSurfaceVariant = Color(0xFF414750);
  static const Color darkOnSurfaceVariant = Color(0xFFC1C7D2);
  static const Color darkSurfaceContainerLow = Color(0xFF1B1C22);
  static const Color darkSurfaceContainer = Color(0xFF202127);
  static const Color darkSurfaceContainerHigh = Color(0xFF2B2C32);
  static const Color darkSurfaceContainerHighest = Color(0xFF36373D);

  static const Color darkBackground = Color(0xFF131318);
  static const Color darkOnBackground = Color(0xFFE1E2E8);

  static const Color darkOutline = Color(0xFF8B909B);
  static const Color darkOutlineVariant = Color(0xFF414750);

  static const Color darkInverseSurface = Color(0xFFE1E2E8);
  static const Color darkInverseOnSurface = Color(0xFF2E3035);
  static const Color darkInversePrimary = Color(0xFF115B9B);

  // ═══════════════════════════════════════════════════════════════════
  //  PRIVATE HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Builds the Stitch `TextTheme` by assigning each Material-3 text key
  /// to the correct Google Fonts source:
  ///
  /// - Open Sans:   displayLarge/Medium/Small, headlineLarge/Medium/Small
  ///                titleLarge
  /// - Albert Sans: bodyLarge/Medium/Small, labelLarge/Medium/Small
  ///                titleMedium, titleSmall
  ///
  /// Any keys missing from the source theme fall back to [fallback].
  static TextTheme _stitchTextTheme({
    required TextTheme openSans,
    required TextTheme albertSans,
    TextStyle? Function(TextStyle?)? fallback,
  }) {
    return TextTheme(
      // ── Open Sans ────────────────────────────────────────────────
      displayLarge:
          fallback?.call(openSans.displayLarge) ?? openSans.displayLarge,
      displayMedium:
          fallback?.call(openSans.displayMedium) ?? openSans.displayMedium,
      displaySmall:
          fallback?.call(openSans.displaySmall) ?? openSans.displaySmall,
      headlineLarge:
          fallback?.call(openSans.headlineLarge) ?? openSans.headlineLarge,
      headlineMedium:
          fallback?.call(openSans.headlineMedium) ?? openSans.headlineMedium,
      headlineSmall:
          fallback?.call(openSans.headlineSmall) ?? openSans.headlineSmall,
      titleLarge: fallback?.call(openSans.titleLarge) ?? openSans.titleLarge,

      // ── Albert Sans ──────────────────────────────────────────────
      titleMedium:
          fallback?.call(albertSans.titleMedium) ?? albertSans.titleMedium,
      titleSmall:
          fallback?.call(albertSans.titleSmall) ?? albertSans.titleSmall,
      bodyLarge: fallback?.call(albertSans.bodyLarge) ?? albertSans.bodyLarge,
      bodyMedium:
          fallback?.call(albertSans.bodyMedium) ?? albertSans.bodyMedium,
      bodySmall: fallback?.call(albertSans.bodySmall) ?? albertSans.bodySmall,
      labelLarge:
          fallback?.call(albertSans.labelLarge) ?? albertSans.labelLarge,
      labelMedium:
          fallback?.call(albertSans.labelMedium) ?? albertSans.labelMedium,
      labelSmall:
          fallback?.call(albertSans.labelSmall) ?? albertSans.labelSmall,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  THEME DATA BUILDERS
  // ═══════════════════════════════════════════════════════════════════

  static ThemeData light() {
    final cs = ColorScheme.light(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer,
      error: error,
      onError: onError,
      errorContainer: errorContainer,
      onErrorContainer: onErrorContainer,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      inverseSurface: inverseSurface,
      inversePrimary: inversePrimary,
      surfaceTint: primary,
    );

    // Google Fonts sources – Open Sans for headlines, Albert Sans for body
    final openSans = GoogleFonts.openSansTextTheme();
    final albert = GoogleFonts.albertSansTextTheme();
    final inter =
        GoogleFonts.interTextTheme(); // Inter used for button weight spec

    // Weight/letter-spacing overrides applied to every style after the
    // source font family has been locked in by _stitchTextTheme.
    TextStyle? weightOverride(TextStyle? s) {
      if (s == null) return null;
      return s.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      scaffoldBackgroundColor: surface,

      // ── Icon Theme ──────────────────────────────────────────────
      // CRITICAL: No fontFamily here.  Material Icons always use their
      // own font; the Inter font set on text widgets must NOT cascade
      // into icon glyphs (causes Chinese-character rendering bug).
      iconTheme: const IconThemeData(
        color: onSurface,
        size: 24.0,
        opacity: 1.0,
        fill: 1.0,
      ),

      // ── Text Theme ──────────────────────────────────────────────
      textTheme: _stitchTextTheme(
        openSans: openSans,
        albertSans: albert,
        fallback: weightOverride,
      ),

      // ── AppBar ──────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: inter.titleLarge?.copyWith(
          color: onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Card ────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outlineVariant.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // ── Filled Button ───────────────────────────────────────────
      // Pill shape + generous padding = Stitch primary CTA
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: onSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Text Button ─────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Outlined Button ─────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurfaceVariant,
          side: const BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Input Decoration ────────────────────────────────────────
      // Pill-shaped fields matching Stitch form inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: error, width: 2),
        ),
        labelStyle: inter.bodyMedium?.copyWith(
          color: onSurface,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: inter.bodyMedium?.copyWith(
          color: onSurface.withValues(alpha: 0.48),
        ),
        prefixIconColor: onSurfaceVariant,
        suffixIconColor: onSurfaceVariant,
        floatingLabelStyle: inter.bodyMedium?.copyWith(
          color: primary,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Chip ────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primaryContainer,
        disabledColor: surfaceContainerHighest,
        labelStyle: inter.labelMedium ?? const TextStyle(),
        secondaryLabelStyle: inter.labelMedium ?? const TextStyle(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outlineVariant),
        ),
      ),

      // ── Bottom Navigation Bar ───────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceContainerLow,
        selectedItemColor: primary,
        unselectedItemColor: onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: inter.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: inter.labelSmall,
      ),

      // ── Navigation Rail ─────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primaryContainer,
        selectedIconTheme: const IconThemeData(
          color: onPrimaryContainer,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: inter.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        unselectedLabelTextStyle: inter.labelSmall?.copyWith(
          color: onSurfaceVariant,
        ),
      ),

      // ── Dialog ──────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: inter.headlineSmall?.copyWith(
          color: onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Divider ─────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      // ── Snackbar ────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: inverseSurface,
        contentTextStyle: inter.bodyMedium?.copyWith(
          color: inverseOnSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Popup Menu ──────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 3,
      ),
    );
  }

  static ThemeData dark() {
    final cs = ColorScheme.dark(
      primary: darkPrimary,
      onPrimary: darkOnPrimary,
      primaryContainer: darkPrimaryContainer,
      onPrimaryContainer: darkOnPrimaryContainer,
      secondary: darkSecondary,
      onSecondary: darkOnSecondary,
      secondaryContainer: darkSecondaryContainer,
      onSecondaryContainer: darkOnSecondaryContainer,
      tertiary: darkTertiary,
      onTertiary: darkOnTertiary,
      tertiaryContainer: darkTertiaryContainer,
      onTertiaryContainer: darkOnTertiaryContainer,
      error: darkError,
      onError: darkOnError,
      errorContainer: darkErrorContainer,
      onErrorContainer: darkOnErrorContainer,
      surface: darkSurface,
      onSurface: darkOnSurface,
      surfaceContainerHighest: darkSurfaceVariant,
      onSurfaceVariant: darkOnSurfaceVariant,
      outline: darkOutline,
      outlineVariant: darkOutlineVariant,
      inverseSurface: darkInverseSurface,
      inversePrimary: darkInversePrimary,
      surfaceTint: darkPrimary,
    );

    final openSans = GoogleFonts.openSansTextTheme(ThemeData.dark().textTheme);
    final albert = GoogleFonts.albertSansTextTheme(ThemeData.dark().textTheme);
    final inter = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    TextStyle? weightOverride(TextStyle? s) {
      if (s == null) return null;
      return s.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: darkSurface,

      // ── Icon Theme (same fix – no fontFamily) ───────────────────
      iconTheme: const IconThemeData(
        color: darkOnSurface,
        size: 24.0,
        opacity: 1.0,
        fill: 1.0,
      ),

      // ── Text Theme ──────────────────────────────────────────────
      textTheme: _stitchTextTheme(
        openSans: openSans,
        albertSans: albert,
        fallback: weightOverride,
      ),

      // ── AppBar ──────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkOnSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: inter.titleLarge?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Card ────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: darkSurfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: darkOutlineVariant.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // ── Filled Button ───────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          disabledBackgroundColor: darkOnSurface.withValues(alpha: 0.12),
          disabledForegroundColor: darkOnSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),

      // ── Text Button ─────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Outlined Button ─────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkOnSurface,
          side: BorderSide(color: darkOutline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Input Decoration ────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkOutlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: darkError, width: 2),
        ),
        labelStyle: inter.bodyMedium?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: inter.bodyMedium?.copyWith(
          color: darkOnSurface.withValues(alpha: 0.48),
        ),
        prefixIconColor: darkOnSurfaceVariant,
        suffixIconColor: darkOnSurfaceVariant,
        floatingLabelStyle: inter.bodyMedium?.copyWith(
          color: darkPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Chip ────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceContainer,
        selectedColor: darkPrimaryContainer,
        disabledColor: darkSurfaceContainerHighest,
        labelStyle: inter.labelMedium ?? const TextStyle(),
        secondaryLabelStyle: inter.labelMedium ?? const TextStyle(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: darkOutlineVariant),
        ),
      ),

      // ── Bottom Navigation ───────────────────────────────────────
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: darkSurfaceContainerLow,
        selectedItemColor: darkPrimary,
        unselectedItemColor: darkOnSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: inter.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: inter.labelSmall,
      ),

      // ── Navigation Rail ─────────────────────────────────────────
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        indicatorColor: darkPrimaryContainer,
        selectedIconTheme: const IconThemeData(
          color: darkOnPrimaryContainer,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: darkOnSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: inter.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: darkOnSurface,
        ),
        unselectedLabelTextStyle: inter.labelSmall?.copyWith(
          color: darkOnSurfaceVariant,
        ),
      ),

      // ── Dialog ──────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: inter.headlineSmall?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Divider ─────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: darkOutlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      // ── Snackbar ────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkInverseSurface,
        contentTextStyle: inter.bodyMedium?.copyWith(
          color: darkInverseOnSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Popup Menu ──────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 3,
      ),
    );
  }
}
