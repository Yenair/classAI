import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralised theme based on the Google Stitch design system tokens.
///
/// ## Design Tokens (from Stitch `tailwind.config`)
/// | Token        | Value        |
/// |-------------|-------------|
/// | BorderRadius: DEFAULT | 0.125rem (2px) |
/// | BorderRadius: lg      | 0.25rem (4px)  | buttons, inputs, tags
/// | BorderRadius: xl      | 0.5rem (8px)   | cards, containers
/// | BorderRadius: full    | 0.75rem (12px) | nav items, decorative
/// | Spacing base          | 8px            |
/// | Touch target          | 48px           |
/// | Margin mobile         | 16px           |
/// | Margin tablet         | 24px           |
///
/// ## Typography (from Stitch HTML / DESIGN.md)
/// All text roles in the rendered HTML map to **Inter** via the Tailwind
/// config's `fontFamily` overrides.  Open Sans (headlines) and Albert Sans
/// (body) are declared in the DESIGN.md but the HTML classes that are actually
/// used (`font-headline-lg`, `font-body-md`, etc.) all resolve to Inter.
///
/// ## WCAG Contrast
/// | Pair                | Ratio |
/// |---------------------|-------|
/// | primary (#115B9B) on white | 5.5:1 ✅ AA |
/// | error (#BA1A1A) on white   | 6.5:1 ✅ AA |
class AppTheme {
  // ═══════════════════════════════════════════════════════════════════
  //  STITCH BORDER RADIUS TOKENS
  // ═══════════════════════════════════════════════════════════════════

  /// 0.25rem → buttons, inputs, tags, chips (Stitch `rounded-lg`)
  static const double radiusLg = 4.0;

  /// 0.5rem → cards, containers, dialogs (Stitch `rounded-xl`)
  static const double radiusXl = 8.0;

  /// 0.75rem → nav items, decorative rounding (Stitch `rounded-full`)
  static const double radiusFull = 12.0;

  /// 0.125rem → fine details (Stitch default)
  static const double radiusDefault = 2.0;

  // ═══════════════════════════════════════════════════════════════════
  //  STITCH SPACING TOKENS
  // ═══════════════════════════════════════════════════════════════════

  static const double spacingBase = 8.0;
  static const double spacingGutter = 16.0;
  static const double spacingMarginMobile = 16.0;
  static const double spacingMarginTablet = 24.0;
  static const double touchTarget = 48.0;

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
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceBright = Color(0xFFF8F9FF);
  static const Color surfaceDim = Color(0xFFD9DAE0);

  static const Color background = Color(0xFFF8F9FF);
  static const Color onBackground = Color(0xFF191C20);

  static const Color outline = Color(0xFF727781);
  static const Color outlineVariant = Color(0xFFC1C7D2);

  static const Color inverseSurface = Color(0xFF2E3035);
  static const Color inverseOnSurface = Color(0xEFF0F6);
  static const Color inversePrimary = Color(0xFFA1C9FF);

  // Secondary-fixed tokens used for active nav items
  static const Color secondaryFixed = Color(0xFFE0E0FF);
  static const Color onSecondaryFixed = Color(0xFF00026C);
  static const Color secondaryFixedDim = Color(0xFFBEC2FF);

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
  static const Color darkSurfaceContainerLowest = Color(0xFF0E0E14);
  static const Color darkSurfaceBright = Color(0xFF3A3B42);
  static const Color darkSurfaceDim = Color(0xFF0B0B10);

  static const Color darkBackground = Color(0xFF131318);
  static const Color darkOnBackground = Color(0xFFE1E2E8);

  static const Color darkOutline = Color(0xFF8B909B);
  static const Color darkOutlineVariant = Color(0xFF414750);

  static const Color darkInverseSurface = Color(0xFFE1E2E8);
  static const Color darkInverseOnSurface = Color(0xFF2E3035);
  static const Color darkInversePrimary = Color(0xFF115B9B);

  // ═══════════════════════════════════════════════════════════════════
  //  TYPOGRAPHY HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Builds the Stitch `TextTheme` mapping each Material-3 key to Inter
  /// (the font family used by all text roles in the rendered HTML).
  ///
  /// Sizes and weights follow the DESIGN.md spec:
  /// | Role              | Size  | Weight |
  /// |-------------------|-------|--------|
  /// | displayLarge      | 48px  | 700    |
  /// | headlineLarge     | 32px  | 600    |
  /// | headlineMedium    | 28px  | 600    | (headline-lg-mobile)
  /// | titleLarge        | 22px  | 500    |
  /// | bodyLarge         | 18px  | 400    |
  /// | bodyMedium        | 16px  | 400    |
  /// | labelLarge        | 14px  | 500    |
  /// | labelMedium       | 12px  | 500    |
  static TextTheme _stitchTextTheme(TextTheme inter) {
    return TextTheme(
      // ── Display ─────────────────────────────────────────────────
      displayLarge: inter.displayLarge?.copyWith(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02,
        height: 56 / 48,
      ),
      displayMedium: inter.displayMedium?.copyWith(
        fontSize: 40,
        fontWeight: FontWeight.w600,
      ),
      displaySmall: inter.displaySmall?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w500,
      ),

      // ── Headline ────────────────────────────────────────────────
      headlineLarge: inter.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        height: 40 / 32,
      ),
      headlineMedium: inter.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 36 / 28,
      ),
      headlineSmall: inter.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w500,
      ),

      // ── Title ───────────────────────────────────────────────────
      titleLarge: inter.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        height: 28 / 22,
      ),
      titleMedium: inter.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      titleSmall: inter.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),

      // ── Body ────────────────────────────────────────────────────
      bodyLarge: inter.bodyLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w400,
        height: 28 / 18,
      ),
      bodyMedium: inter.bodyMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 24 / 16,
      ),
      bodySmall: inter.bodySmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),

      // ── Label ───────────────────────────────────────────────────
      labelLarge: inter.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 20 / 14,
        letterSpacing: 0.1,
      ),
      labelMedium: inter.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
      ),
      labelSmall: inter.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
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

    final inter = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: cs,
      scaffoldBackgroundColor: background,

      // ── Icon Theme ──────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: onSurface,
        size: 24.0,
        opacity: 1.0,
      ),

      // ── Text Theme ──────────────────────────────────────────────
      textTheme: _stitchTextTheme(inter),

      // ── AppBar ──────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: surface,
        titleTextStyle: inter.titleLarge?.copyWith(
          color: onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Card ────────────────────────────────────────────────────
      // Stitch `rounded-xl` (8px), subtle border, no elevation
      cardTheme: CardThemeData(
        color: surfaceContainerLowest,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: BorderSide(color: outlineVariant.withValues(alpha: 0.3)),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Filled Button ───────────────────────────────────────────
      // Stitch `rounded-lg` (4px), 48px touch-target height.
      //
      // The minimum is `Size(0, touchTarget)`, never `Size.fromHeight(...)`:
      // an infinite minimum width is only valid when the parent hands down a
      // bounded width. Inside a `Row` (unbounded main axis) or a horizontal
      // scroll view it resolves to `BoxConstraints(w=Infinity, …)`, which
      // throws and leaves the button — and every ancestor — unlaid out with
      // "RenderBox was not laid out". Buttons that should fill the available
      // width say so explicitly with `SizedBox(width: double.infinity)`.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: onSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          minimumSize: const Size(0, touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Text Button ─────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Outlined Button ─────────────────────────────────────────
      // Finite minimum width — see the Filled Button note above.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurfaceVariant,
          side: const BorderSide(color: outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          minimumSize: const Size(0, touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Input Decoration ────────────────────────────────────────
      // Stitch: outlined style, no fill, `rounded-lg` (4px)
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
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
      // Stitch `rounded-lg` (4px)
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        selectedColor: primaryContainer,
        disabledColor: surfaceContainerHighest,
        labelStyle: inter.labelMedium ?? const TextStyle(),
        secondaryLabelStyle: inter.labelMedium ?? const TextStyle(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: outlineVariant),
        ),
      ),

      // ── Bottom Navigation Bar ───────────────────────────────────
      // Stitch: rounded-t-full (12px) top corners
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
      // Stitch: items use `rounded-full` (12px)
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: secondaryFixed,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        selectedIconTheme: const IconThemeData(
          color: onSecondaryFixed,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: inter.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: onSecondaryFixed,
        ),
        unselectedLabelTextStyle: inter.labelSmall?.copyWith(
          color: onSurfaceVariant,
        ),
      ),

      // ── Dialog ──────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
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
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Popup Menu ──────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
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

    final inter =
        GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: cs,
      scaffoldBackgroundColor: darkBackground,

      // ── Icon Theme ──────────────────────────────────────────────
      iconTheme: const IconThemeData(
        color: darkOnSurface,
        size: 24.0,
        opacity: 1.0,
      ),

      // ── Text Theme ──────────────────────────────────────────────
      textTheme: _stitchTextTheme(inter),

      // ── AppBar ──────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkOnSurface,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        surfaceTintColor: darkSurface,
        titleTextStyle: inter.titleLarge?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w600,
        ),
      ),

      // ── Card ────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: darkSurfaceContainerLowest,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          side: BorderSide(
              color: darkOutlineVariant.withValues(alpha: 0.3)),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // ── Filled Button ───────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          disabledBackgroundColor:
              darkOnSurface.withValues(alpha: 0.12),
          disabledForegroundColor:
              darkOnSurface.withValues(alpha: 0.38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          // Finite minimum width — an infinite one breaks in unbounded
          // parents (Rows, horizontal scroll views). See the light theme.
          minimumSize: const Size(0, touchTarget),
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ── Text Button ─────────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            borderRadius: BorderRadius.circular(radiusLg),
          ),
          // Finite minimum width — see the light theme.
          minimumSize: const Size(0, touchTarget),
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: inter.labelLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Input Decoration ────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(color: darkOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(color: darkOutlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide:
              BorderSide(color: darkPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          borderSide: BorderSide(color: darkError),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLg),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
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
        indicatorColor: darkSecondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
        selectedIconTheme: const IconThemeData(
          color: darkOnSecondaryContainer,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: darkOnSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: inter.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: darkOnSecondaryContainer,
        ),
        unselectedLabelTextStyle: inter.labelSmall?.copyWith(
          color: darkOnSurfaceVariant,
        ),
      ),

      // ── Dialog ──────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
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
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── Popup Menu ──────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
        elevation: 3,
      ),
    );
  }
}
