import 'package:flutter/material.dart';

// ========== 颜色系统 ==========
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1E40AF);
  static const Color primarySoft = Color(0xFFEFF6FF);
  static const Color primaryLight = Color(0xFFBFDBFE);

  static const Color secondaryBlue = Color(0xFF0EA5E9);
  static const Color secondaryPurple = Color(0xFF7C3AED);
  static const Color accentOrange = Color(0xFFF97316);

  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF1F5F9);
  static const Color surfaceMuted = Color(0xFFE2E8F0);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkSoft = Color(0xFF1E293B);
  static const Color chrome = Color(0xFF111827);

  static const Color border = Color(0xFFDDE4EE);
  static const Color borderLight = Color(0xFFEAF0F7);
  static const Color divider = Color(0xFFD8E1EC);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFE11D48);
  static const Color info = Color(0xFF0284C7);

  // ---- Primary ramp ----
  // Deep end of the brand blue, for gradient anchors and pressed states.
  static const Color primaryDeep = Color(0xFF1B3A8F);

  // ---- Paper neutrals ----
  // Slightly warmed off-whites so surfaces read as paper rather than glass.
  static const Color paper = Color(0xFFFCFDFF);
  static const Color paperEdge = Color(0xFFE7EDF6);

  // ---- Quiet slate ----
  // Promoted from the values most often hand-written across pages.
  static const Color textQuiet = Color(0xFF8A94A6);
  static const Color slate = Color(0xFF475569);

  // ---- Categorical accents ----
  // One coherent set for metrics, tags and category icons, replacing the
  // ad-hoc hexes that were repeated per page.
  static const Color accentFlame = Color(0xFFFF8556);
  static const Color accentSky = Color(0xFF51A5FF);
  static const Color accentMint = Color(0xFF21BF94);
  static const Color accentViolet = Color(0xFF9573FF);
  static const Color accentAmber = Color(0xFFFFB827);
  static const Color accentRose = Color(0xFFFF4380);

  // ---- Content over imagery ----
  // For text and icons laid directly on a photo or cover, where no surface
  // token can guarantee contrast.
  static const Color onImage = Color(0xFFFFFFFF);
  static const Color onImageMuted = Color(0xE6FFFFFF);
  static const Color scrimStrong = Color(0x66000000);
  static const Color scrimSoft = Color(0x40000000);

  // ---- Accent tints ----
  // A tint is the accent at ~10% for icon boxes and selected chips.
  static Color tintOf(Color accent, [double alpha = 0.10]) =>
      accent.withValues(alpha: alpha);
}

// ========== 文字样式 ==========
class AppTextStyles {
  AppTextStyles._();

  static TextStyle display(BuildContext context) =>
      Theme.of(context).textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.2,
      ) ??
      const TextStyle();

  static TextStyle h1(BuildContext context) =>
      Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.25,
      ) ??
      const TextStyle();

  static TextStyle h2(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      ) ??
      const TextStyle();

  static TextStyle h3(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      ) ??
      const TextStyle();

  static TextStyle body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.5,
      ) ??
      const TextStyle();

  static TextStyle bodySmall(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.45,
      ) ??
      const TextStyle();

  static TextStyle caption(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textTertiary,
        height: 1.4,
      ) ??
      const TextStyle();

  /// Section heading inside a page body (18/w800).
  static TextStyle section(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.3,
        letterSpacing: -0.2,
      ) ??
      const TextStyle();

  /// Card and list-row title (15/w700).
  static TextStyle title(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.35,
      ) ??
      const TextStyle();

  /// Control and field label (13/w600).
  static TextStyle label(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.35,
      ) ??
      const TextStyle();

  /// Dense metadata: tag text, trailing counts, footnotes (11/w600).
  static TextStyle labelSmall(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
        height: 1.3,
      ) ??
      const TextStyle();

  /// The big number in a metric tile (22/w800, tabular).
  static TextStyle metric(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
        height: 1.1,
        letterSpacing: -0.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      ) ??
      const TextStyle();

  /// Category label above a value, or a group eyebrow (11/w700, tracked).
  static TextStyle overline(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textTertiary,
        height: 1.2,
        letterSpacing: 0.8,
      ) ??
      const TextStyle();
}

// ========== 间距系统 (4 的倍数) ==========
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  static const double pageH = 16;
  static const double cardInner = 16;
  static const double cardGap = 12;
  static const double sectionGap = 20;
}

// ========== 圆角系统 ==========
class AppRadii {
  AppRadii._();

  static const double card = 22;
  static const double cardSmall = 18;
  static const double cardLarge = 26;
  static const double button = 16;
  static const double tile = 16;
  static const double input = 14;
  static const double chipSmall = 12;
  static const double sheet = 28;
  static const double chip = 999;
  static const double iconBox = 13;
}

// ========== 阴影系统 ==========
class AppShadows {
  AppShadows._();

  static BoxShadow get cardSoft => BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.07),
    blurRadius: 30,
    offset: const Offset(0, 14),
  );

  static BoxShadow get cardMedium => BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.11),
    blurRadius: 42,
    offset: const Offset(0, 22),
  );

  static BoxShadow get float => BoxShadow(
    color: AppColors.primary.withValues(alpha: 0.20),
    blurRadius: 54,
    offset: const Offset(0, 24),
  );

  static BoxShadow get nav => BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.12),
    blurRadius: 32,
    offset: const Offset(0, 18),
  );

  /// Tight shadow for dense list rows and inline tiles, where `cardSoft`
  /// would look loose and muddy.
  static BoxShadow get cardTight => BoxShadow(
    color: const Color(0xFF0F172A).withValues(alpha: 0.05),
    blurRadius: 16,
    offset: const Offset(0, 6),
  );

  /// Brand-tinted lift for the single hero surface at the top of a page.
  /// Kept soft: at full strength it reads as a second grey band under the card.
  static BoxShadow get hero => BoxShadow(
    color: AppColors.primaryDeep.withValues(alpha: 0.15),
    blurRadius: 28,
    offset: const Offset(0, 12),
  );

  static List<BoxShadow> get cardSoftList => [cardSoft];
  static List<BoxShadow> get cardMediumList => [cardMedium];
  static List<BoxShadow> get floatList => [float];
  static List<BoxShadow> get navList => [nav];
  static List<BoxShadow> get cardTightList => [cardTight];
  static List<BoxShadow> get heroList => [hero];
}

// ========== 统一主题 ==========
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    const primary = AppColors.primary;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: AppColors.secondaryBlue,
      tertiary: AppColors.secondaryPurple,
      error: AppColors.error,
      surface: AppColors.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: null,
      textTheme: Typography.material2021(platform: TargetPlatform.android).black
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.primarySoft,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        side: const BorderSide(color: AppColors.border),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.input),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      // ---- Below: component themes that were previously left on raw
      // Material defaults. The app has ~250 call sites on these widgets, so
      // theming here is what makes the whole surface read as one product.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        iconColor: AppColors.textSecondary,
        minVerticalPadding: 10,
        titleTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          iconSize: 21,
          highlightColor: AppColors.primarySoft,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: AppColors.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 0,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.chrome.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppRadii.chipSmall),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        waitDuration: const Duration(milliseconds: 500),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : AppColors.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : AppColors.surfaceMuted,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : Colors.transparent,
        ),
        side: const BorderSide(color: AppColors.border, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: AppColors.surfaceMuted,
        thumbColor: Colors.white,
        overlayColor: primary.withValues(alpha: 0.12),
        trackHeight: 6,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primary,
        selectionColor: AppColors.primaryLight,
        selectionHandleColor: primary,
      ),
    );
  }
}
