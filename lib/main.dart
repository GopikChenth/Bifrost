import 'package:flutter/material.dart';
import 'package:bifrost/Pages/bifrost_dashboard.dart';
import 'package:bifrost/Utils/app_colors.dart';
import 'package:bifrost/Utils/settings_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SettingsRepository settingsRepo = const SettingsRepository();
  AppSettings.disableAnimations = await settingsRepo.loadDisableAnimations();
  AppSettings.themeNotifier.value = await settingsRepo.loadAppTheme();
  runApp(const BifrostApp());
}

class BifrostApp extends StatelessWidget {
  const BifrostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppSettings.themeNotifier,
      builder: (BuildContext context, String currentTheme, Widget? child) {
        final bool isTealTheme = currentTheme == 'teal';
        final bool isFrostTheme = currentTheme == 'frost';

        final ColorScheme colorScheme = isTealTheme
            ? ColorScheme.fromSeed(
                seedColor: const Color(0xFF00838F),
                brightness: Brightness.dark,
              )
            : isFrostTheme
                ? ColorScheme(
                    brightness: Brightness.dark,
                    primary: const Color(0xFF8FA3B8),
                    onPrimary: const Color(0xFF182B3D),
                    primaryContainer: const Color(0xFF253D62),
                    onPrimaryContainer: const Color(0xFFC1C1C1),
                    secondary: const Color(0xFF5F7082),
                    onSecondary: const Color(0xFF182B3D),
                    secondaryContainer: const Color(0xFF253D62),
                    onSecondaryContainer: const Color(0xFFC1C1C1),
                    surface: const Color(0xFF182B3D),
                    onSurface: const Color(0xFFC1C1C1),
                    onSurfaceVariant: const Color(0xFF8FA3B8),
                    outline: const Color(0xFF494D5F),
                    outlineVariant: const Color(0xFF494D5F),
                    error: const Color(0xFFE97152),
                    onError: const Color(0xFFFFFFFF),
                    surfaceContainerLowest: const Color(0xFF182B3D),
                    surfaceContainerLow: const Color(0xFF253D62),
                    surfaceContainer: const Color(0xFF253D62),
                    surfaceContainerHigh: const Color(0xFF253D62),
                    surfaceContainerHighest: const Color(0xFF494D5F),
                  )
                : ColorScheme(
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

        final Color? scaffoldBackgroundColor = isTealTheme
            ? null
            : isFrostTheme
                ? const Color(0xFF182B3D)
                : AppColors.backgroundDark;

        return MaterialApp(
          title: 'Bifrost',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: scaffoldBackgroundColor,

        // ── Page transitions ────────────────────────────────────
        pageTransitionsTheme: PageTransitionsTheme(
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
      ),
      home: const HomePage(),
        );
      },
    );
  }
}
