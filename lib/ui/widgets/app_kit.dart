import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// ========== App Kit ==========
// The single source of truth for repeated surface patterns.
//
// Before this file the app carried ~8 near-identical empty/error panels, ~12
// copy-pasted snackbar helpers, 49 bare centred spinners and 38 hand-rolled
// bottom-sheet shells. Every page should build from these instead, so the
// product reads as one surface and a change here lands everywhere.

/// One card primitive with explicit, intentional variants.
///
/// The variants exist so pages stop reaching for "white rounded box" by
/// default. Pick the variant that matches the content's role:
///   plain    – a normal content group
///   outlined – dense lists, where a shadow would look muddy
///   tinted   – a group belonging to one category/colour
///   ink      – the single hero surface at the top of a page
///   glass    – content laid over an image
enum AppCardTone { plain, outlined, tinted, ink, glass }

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.tone = AppCardTone.plain,
    this.accent = AppColors.primary,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = AppRadii.card,
    this.onTap,
    this.gradient,
    super.key,
  });

  /// A normal content group: white, soft shadow, hairline border.
  const AppCard.plain({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = AppRadii.card,
    this.onTap,
    super.key,
  }) : tone = AppCardTone.plain,
       accent = AppColors.primary,
       gradient = null;

  /// A dense list group: no shadow, just a border. Use inside scroll lists.
  const AppCard.outlined({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadii.cardSmall,
    this.onTap,
    super.key,
  }) : tone = AppCardTone.outlined,
       accent = AppColors.primary,
       gradient = null;

  /// A group owned by one accent colour (a subject, a status, a category).
  const AppCard.tinted({
    required this.child,
    required this.accent,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadii.cardSmall,
    this.onTap,
    super.key,
  }) : tone = AppCardTone.tinted,
       gradient = null;

  /// The page hero. At most one per page.
  const AppCard.ink({
    required this.child,
    this.accent = AppColors.primary,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 18, 20),
    this.borderRadius = AppRadii.card,
    this.onTap,
    this.gradient,
    super.key,
  }) : tone = AppCardTone.ink;

  /// Translucent, for sitting over imagery.
  const AppCard.glass({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = AppRadii.cardSmall,
    this.onTap,
    super.key,
  }) : tone = AppCardTone.glass,
       accent = AppColors.primary,
       gradient = null;

  final Widget child;
  final AppCardTone tone;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final List<Color>? gradient;

  @override
  Widget build(BuildContext context) {
    final decoration = _decoration();
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: decoration,
      // Decorative children (corner glows, oversized glyphs) must stay inside
      // the rounded shape instead of spilling onto the page behind it.
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          decoration: decoration,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }

  BoxDecoration _decoration() {
    switch (tone) {
      case AppCardTone.plain:
        return BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: AppShadows.cardTightList,
        );
      case AppCardTone.outlined:
        return BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: AppColors.border),
        );
      case AppCardTone.tinted:
        return BoxDecoration(
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.09),
            AppColors.surface,
          ),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: accent.withValues(alpha: 0.20)),
        );
      case AppCardTone.ink:
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient ?? [accent, AppColors.primaryDeep],
          ),
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: AppShadows.heroList,
        );
      case AppCardTone.glass:
        return BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
        );
    }
  }
}

/// Section heading used inside a page body.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.accent,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// When set, draws a small colour bar before the title so a section can
  /// carry its category colour without tinting the whole card.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final hasSubtitle = subtitle?.trim().isNotEmpty == true;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (accent != null) ...[
          Container(
            width: 3,
            height: hasSubtitle ? 34 : 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.section(context)),
              if (hasSubtitle) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: AppColors.textSecondary),
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

/// Icon + value + label metric. The workhorse of every stats row.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.accent = AppColors.primary,
    this.muted = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  /// "Nothing to do here". The icon keeps its identity colour — colour says
  /// *which metric this is*, so greying the icon made a zero tile look like a
  /// failed image load. The quiet signal belongs on the number instead.
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tintOf(accent, 0.12),
            borderRadius: BorderRadius.circular(AppRadii.chipSmall),
            border: Border.all(color: AppColors.tintOf(accent, 0.18)),
          ),
          child: Icon(icon, size: 19, color: accent),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.metric(context).copyWith(
            color: muted ? AppColors.textQuiet : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: AppTextStyles.labelSmall(
            context,
          ).copyWith(color: AppColors.textQuiet, fontWeight: FontWeight.w500),
        ),
      ],
    );

    if (onTap == null) return column;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: column,
      ),
    );
  }
}

/// A stats row: several [AppStatTile]s separated by hairline rules.
class AppStatRow extends StatelessWidget {
  const AppStatRow({required this.tiles, super.key});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0)
            Container(
              width: 1,
              height: 52,
              color: AppColors.divider.withValues(alpha: 0.7),
            ),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

/// Leading icon box + title + subtitle + trailing. Replaces the many
/// hand-built "icon box + text + chevron" rows.
class AppListRow extends StatelessWidget {
  const AppListRow({
    required this.title,
    this.subtitle,
    this.icon,
    this.accent = AppColors.primary,
    this.trailing,
    this.onTap,
    this.leading,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    this.dense = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accent;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? leading;
  final EdgeInsetsGeometry padding;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null)
          leading!
        else if (icon != null)
          Container(
            width: dense ? 34 : 40,
            height: dense ? 34 : 40,
            decoration: BoxDecoration(
              color: AppColors.tintOf(accent, 0.11),
              borderRadius: BorderRadius.circular(
                dense ? AppRadii.chipSmall : AppRadii.iconBox,
              ),
            ),
            child: Icon(icon, size: dense ? 18 : 21, color: accent),
          ),
        if (leading != null || icon != null) const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.title(context),
              ),
              if (subtitle?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 10),
          trailing!,
        ] else if (onTap != null) ...[
          const SizedBox(width: 6),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
            size: 20,
          ),
        ],
      ],
    );

    if (onTap == null) {
      return Padding(padding: padding, child: row);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        child: Padding(padding: padding, child: row),
      ),
    );
  }
}

/// Small status/label chip. Distinct from a Material Chip: no tap target,
/// no elevation, one accent.
class AppTag extends StatelessWidget {
  const AppTag({
    required this.label,
    this.accent = AppColors.primary,
    this.icon,
    this.filled = true,
    super.key,
  });

  final String label;
  final Color accent;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? AppColors.tintOf(accent, 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        border: filled
            ? null
            : Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: accent),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTextStyles.labelSmall(context).copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

/// How an [AppSegmented] is drawn.
enum AppSegmentedVariant {
  /// One quiet track with a lifted pill. For a small switch inside a card
  /// (登录/注册、今日推荐/薄弱提升).
  track,

  /// Separate outlined pills. For a group of peer options
  /// (面试模式、难度、题量).
  pill,
}

/// One choice in an [AppSegmented].
class AppSegmentedOption<T> {
  const AppSegmentedOption(this.value, this.label, {this.segmentKey});

  final T value;
  final String label;

  /// Optional key on the tappable segment, so widget tests can target one
  /// option without depending on the label text.
  final Key? segmentKey;
}

/// The one segmented control. Replaces the three private copies on the home,
/// interview and login pages, which had drifted into two different visuals for
/// the same interaction.
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    required this.options,
    required this.value,
    required this.onChanged,
    this.variant = AppSegmentedVariant.track,
    this.enabled = true,
    super.key,
  });

  final List<AppSegmentedOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final AppSegmentedVariant variant;
  final bool enabled;

  @override
  Widget build(BuildContext context) => switch (variant) {
    AppSegmentedVariant.track => Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.chipSmall + 4),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(child: _segment(context, option, track: true)),
        ],
      ),
    ),
    AppSegmentedVariant.pill => Row(
      children: [
        for (final option in options) ...[
          Expanded(child: _segment(context, option, track: false)),
          if (option != options.last) const SizedBox(width: AppSpacing.sm),
        ],
      ],
    ),
  };

  Widget _segment(
    BuildContext context,
    AppSegmentedOption<T> option, {
    required bool track,
  }) {
    final selected = option.value == value;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: option.segmentKey,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          onTap: enabled ? () => onChanged(option.value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOut,
            constraints: BoxConstraints(minHeight: track ? 40 : 44),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            alignment: Alignment.center,
            decoration: track
                ? BoxDecoration(
                    color: selected ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.chipSmall),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppColors.ink.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  )
                : BoxDecoration(
                    color: selected
                        ? AppColors.primarySoft
                        : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
            child: Text(
              option.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label(context).copyWith(
                color: selected
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The header for a tab-level page: one title size and one subtitle treatment,
/// so switching tabs no longer jumps the title between 22/23/26/27px.
///
/// 首页 (personal greeting) and 我的 (gradient hero) keep their own treatments
/// on purpose — they carry identity, not just a page name.
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
        // Below the action row, not inside it: a subtitle squeezed next to two
        // trailing buttons wraps mid-phrase ("一起进/步").
        if (subtitle?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 5),
          Text(subtitle!, style: AppTextStyles.bodySmall(context)),
        ],
      ],
    );
  }
}

/// The one empty state. Replaces the eight hand-rolled variants.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    this.description,
    this.icon = Icons.inbox_rounded,
    this.accent = AppColors.primary,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? description;
  final IconData icon;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 32,
          vertical: compact ? 20 : 36,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 52 : 64,
              height: compact ? 52 : 64,
              decoration: BoxDecoration(
                // A tinted chip with a lit top edge reads as a designed icon
                // slot; a flat 10% fill looked like a placeholder.
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.tintOf(accent, compact ? 0.16 : 0.18),
                    AppColors.tintOf(accent, compact ? 0.07 : 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(
                  compact ? AppRadii.cardSmall : AppRadii.card,
                ),
                border: Border.all(color: AppColors.tintOf(accent, 0.20)),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, size: compact ? 26 : 32, color: accent),
            ),
            SizedBox(height: compact ? 12 : 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.title(context).copyWith(fontSize: 16),
            ),
            if (description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall(context),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The one error state. `onRetry` is optional so it also covers
/// "something is unavailable, nothing to retry".
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.title,
    this.description,
    this.onRetry,
    this.retryLabel = '重试',
    this.icon = Icons.cloud_off_rounded,
    super.key,
  });

  final String title;
  final String? description;
  final Future<void> Function()? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      accent: AppColors.error,
      title: title,
      description: description,
      actionLabel: onRetry == null ? null : retryLabel,
      onAction: onRetry == null ? null : () => onRetry!(),
    );
  }
}

/// The one loading state. Prefer [AppSkeletonList] for content that has a
/// known shape — a spinner should not be the default.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({this.label, super.key});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: AppTextStyles.caption(context)),
          ],
        ],
      ),
    );
  }
}

/// A shimmering placeholder block. Use to hold layout while data loads.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    this.width,
    this.height = 14,
    this.borderRadius = AppRadii.chipSmall,
    super.key,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: const [
                AppColors.surfaceMuted,
                Color(0xFFF3F6FB),
                AppColors.surfaceMuted,
              ],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

/// A skeleton shaped like a typical card list, so a loading page keeps the
/// final layout instead of collapsing to a spinner.
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({this.items = 3, this.height = 84, super.key});

  final int items;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          for (var i = 0; i < items; i++) ...[
            AppSkeleton(height: height, borderRadius: AppRadii.card),
            if (i < items - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Bottom-sheet shell: drag handle, optional title/subtitle, scrollable body.
/// Replaces the 38 hand-rolled sheet containers.
class AppSheet extends StatelessWidget {
  const AppSheet({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 22),
    this.maxHeightFactor = 0.86,
    this.scrollable = true,
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final double maxHeightFactor;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 42,
            height: 5,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
          ),
        ),
        Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title!, style: AppTextStyles.h2(context)),
                          if (subtitle?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Text(
                              subtitle!,
                              style: AppTextStyles.bodySmall(context),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              if (title != null) const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * maxHeightFactor,
        ),
        child: scrollable ? SingleChildScrollView(child: body) : body,
      ),
    );
  }
}

/// A glass action pill, for buttons that sit on top of imagery.
class AppGlassPill extends StatelessWidget {
  const AppGlassPill({required this.label, this.onTap, this.icon, super.key});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(AppRadii.chip),
            border: Border.all(color: Colors.white.withValues(alpha: 0.48)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: AppColors.onImage),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: AppColors.onImage,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled progress bar. Used for mastery, import progress and goals.
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    required this.value,
    this.accent = AppColors.primary,
    this.height = 7,
    this.track,
    super.key,
  });

  /// 0..1
  final double value;
  final Color accent;
  final double height;
  final Color? track;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.chip),
      child: Stack(
        children: [
          Container(
            height: height,
            color: track ?? AppColors.surfaceMuted.withValues(alpha: 0.8),
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.75), accent],
                ),
                borderRadius: BorderRadius.circular(AppRadii.chip),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One place to raise a transient message. Replaces the ~12 per-page
/// `_showMessage`/`_toast` helpers and keeps the styling identical.
void showAppToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
