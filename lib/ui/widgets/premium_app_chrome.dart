import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ========== Page Chrome ==========
// Shared visual primitives for the premium study-app surface.

class PremiumPageBackground extends StatelessWidget {
  const PremiumPageBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2F7FF), AppColors.background, Color(0xFFF9FBFF)],
          stops: [0, 0.34, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            top: -160,
            right: -130,
            child: _AtmosphericOrb(
              size: 340,
              color: Color(0xFFBFDBFE),
              opacity: 0.18,
            ),
          ),
          const Positioned(
            top: 180,
            left: -180,
            child: _AtmosphericOrb(
              size: 300,
              color: Color(0xFFE0F2FE),
              opacity: 0.28,
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = AppRadii.card,
    this.backgroundColor,
    this.borderColor,
    this.shadow = true,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppColors.borderLight.withValues(alpha: 0.92),
        ),
        boxShadow: shadow ? AppShadows.cardSoftList : null,
      ),
      child: child,
    );
  }
}

class PremiumHeroPanel extends StatelessWidget {
  const PremiumHeroPanel({
    required this.child,
    this.asset,
    this.icon,
    this.padding = const EdgeInsets.fromLTRB(20, 22, 18, 22),
    super.key,
  });

  final Widget child;
  final String? asset;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFFFFF), Color(0xFFF2F7FF), Color(0xFFEAF7F8)],
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -64,
            top: -72,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFDBEAFE).withValues(alpha: 0.60),
              ),
            ),
          ),
          Positioned(
            left: -80,
            bottom: -120,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFCCFBF1).withValues(alpha: 0.38),
              ),
            ),
          ),
          if (icon != null)
            Positioned(
              right: -12,
              bottom: -18,
              child: Icon(
                icon,
                size: 132,
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _GridGlowPainter()),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.h3(context).copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.1,
                ),
              ),
              if (subtitle?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: AppTextStyles.caption(context).copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class PremiumStatusPanel extends StatelessWidget {
  const PremiumStatusPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return PremiumPageBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PremiumSurface(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, size: 30, color: AppColors.primary),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h2(
                    context,
                  ).copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall(context),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => onPressed(),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PremiumLoadingPanel extends StatelessWidget {
  const PremiumLoadingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PremiumPageBackground(
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AtmosphericOrb extends StatelessWidget {
  const _AtmosphericOrb({
    required this.size,
    required this.color,
    required this.opacity,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }
}

class _GridGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.05)
      ..strokeWidth = 0.7;
    const gap = 26.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
