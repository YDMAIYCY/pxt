import 'package:flutter/material.dart';

// ========== 颜色系统 ==========
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF14B8A6);
  static const Color primaryDark = Color(0xFF0EA5A4);
  static const Color primarySoft = Color(0xFFE8F8F5);
  static const Color primaryLight = Color(0xFFCCFBF1);

  static const Color secondaryBlue = Color(0xFF4FA3FF);
  static const Color secondaryPurple = Color(0xFF9B7BFF);
  static const Color accentOrange = Color(0xFFFF8A3D);

  static const Color background = Color(0xFFF7FCFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF0FDFA);

  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF0F1F3);
  static const Color divider = Color(0xFFE7E1DA);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color success = Color(0xFF2FBF71);
  static const Color warning = Color(0xFFF4A261);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF4D96FF);
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

  static const double card = 24;
  static const double cardSmall = 20;
  static const double button = 18;
  static const double input = 16;
  static const double sheet = 32;
  static const double chip = 999;
  static const double iconBox = 14;
}

// ========== 阴影系统 ==========
class AppShadows {
  AppShadows._();

  static BoxShadow get cardSoft => BoxShadow(
        color: const Color(0xFF111827).withValues(alpha: 0.06),
        blurRadius: 24,
        offset: const Offset(0, 8),
      );

  static BoxShadow get cardMedium => BoxShadow(
        color: const Color(0xFF111827).withValues(alpha: 0.08),
        blurRadius: 32,
        offset: const Offset(0, 12),
      );

  static BoxShadow get float => BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.18),
        blurRadius: 48,
        offset: const Offset(0, 18),
      );

  static BoxShadow get nav => BoxShadow(
        color: const Color(0xFF111827).withValues(alpha: 0.08),
        blurRadius: 28,
        offset: const Offset(0, 10),
      );

  static List<BoxShadow> get cardSoftList => [cardSoft];
  static List<BoxShadow> get cardMediumList => [cardMedium];
  static List<BoxShadow> get floatList => [float];
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
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .black
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
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
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
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
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
    );
  }
}
