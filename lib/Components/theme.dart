import 'package:flutter/material.dart';
import 'package:bifrost/Utils/app_colors.dart';

class AppTheme {
  static Color getThemeColor(String theme) {
    if (theme == 'teal') return const Color(0xFF00838F);
    if (theme == 'frost') return const Color(0xFF5F7082);
    return const Color(0xFF52A435);
  }

  static ColorScheme getColorScheme(String currentTheme) {
    final bool isTealTheme = currentTheme == 'teal';
    final bool isFrostTheme = currentTheme == 'frost';

    if (isTealTheme) {
      return ColorScheme.fromSeed(
        seedColor: const Color(0xFF00838F),
        brightness: Brightness.dark,
      );
    } else if (isFrostTheme) {
      return const ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF8FA3B8),
        onPrimary: Color(0xFF182B3D),
        primaryContainer: Color(0xFF253D62),
        onPrimaryContainer: Color(0xFFC1C1C1),
        secondary: Color(0xFF5F7082),
        onSecondary: Color(0xFF182B3D),
        secondaryContainer: Color(0xFF253D62),
        onSecondaryContainer: Color(0xFFC1C1C1),
        surface: Color(0xFF182B3D),
        onSurface: Color(0xFFC1C1C1),
        onSurfaceVariant: Color(0xFF8FA3B8),
        outline: Color(0xFF494D5F),
        outlineVariant: Color(0xFF494D5F),
        error: Color(0xFFE97152),
        onError: Color(0xFFFFFFFF),
        surfaceContainerLowest: Color(0xFF182B3D),
        surfaceContainerLow: Color(0xFF253D62),
        surfaceContainer: Color(0xFF253D62),
        surfaceContainerHigh: Color(0xFF253D62),
        surfaceContainerHighest: Color(0xFF494D5F),
      );
    } else {
      return ColorScheme(
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.textPrimary,
        primaryContainer: AppColors.primaryLight,
        onPrimaryContainer: AppColors.backgroundDark,
        secondary: AppColors.primaryLight,
        onSecondary: AppColors.backgroundDark,
        secondaryContainer: AppColors.primaryDark,
        onSecondaryContainer: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        error: const Color(0xFFE97152),
        onError: AppColors.textPrimary,
        errorContainer: const Color(0xFF351C18),
        onErrorContainer: const Color(0xFFE97152),
        tertiary: AppColors.accent,
        onTertiary: AppColors.backgroundDark,
        tertiaryContainer: AppColors.accent.withValues(alpha: 0.2),
        onTertiaryContainer: AppColors.accent,
        surfaceContainerLowest: AppColors.backgroundDark,
        surfaceContainerLow: AppColors.surface,
        surfaceContainer: AppColors.surface,
        surfaceContainerHigh: AppColors.surface,
        surfaceContainerHighest: AppColors.border,
      );
    }
  }

  static Color? getScaffoldBackgroundColor(String currentTheme) {
    if (currentTheme == 'teal') return null;
    if (currentTheme == 'frost') return const Color(0xFF182B3D);
    return AppColors.backgroundDark;
  }

  static ThemeData buildTheme(String currentTheme) {
    final ColorScheme colorScheme = getColorScheme(currentTheme);
    final Color? scaffoldBackgroundColor = getScaffoldBackgroundColor(currentTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,

      // ── Page transitions ────────────────────────────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),

      // ── Splash ──────────────────────────────────────────────
      splashFactory: InkSparkle.splashFactory,

      // ── AppBar ──────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: colorScheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),

      // ── Cards ───────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
      ),

      // ── Filled buttons ──────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // ── Outlined buttons ────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          side: BorderSide(color: colorScheme.outline),
        ),
      ),

      // ── Text buttons ────────────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),

      // ── FAB ─────────────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),

      // ── Dialogs ─────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),

      // ── Bottom sheets ───────────────────────────────────────
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        showDragHandle: true,
      ),

      // ── Navigation drawer ───────────────────────────────────
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        indicatorColor: colorScheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) {
            final bool selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurfaceVariant,
            );
          },
        ),
      ),

      // ── Snack bars ──────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: colorScheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
      ),

      // ── Input fields ────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),

      // ── Switches ────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.selected)) {
              return const Icon(Icons.check_rounded, size: 16);
            }
            return null;
          },
        ),
      ),

      // ── Sliders ─────────────────────────────────────────────
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withValues(alpha: 0.12),
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
      ),

      // ── Dividers ────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),

      // ── Progress indicators ─────────────────────────────────
      progressIndicatorTheme: ProgressIndicatorThemeData(
        linearTrackColor: colorScheme.surfaceContainerHighest,
        color: colorScheme.primary,
        linearMinHeight: 6,
        borderRadius: BorderRadius.circular(99),
      ),

      // ── Chips ───────────────────────────────────────────────
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}
