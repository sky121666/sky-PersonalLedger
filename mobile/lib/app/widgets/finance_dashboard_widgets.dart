import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'animated_money_text.dart';
import 'premium_surface.dart';

class FinanceHeroCard extends StatelessWidget {
  const FinanceHeroCard({
    required this.label,
    required this.amount,
    required this.metrics,
    this.accentColor,
    this.semanticLabel,
    super.key,
  });

  final String label;
  final double amount;
  final List<FinanceMetricData> metrics;
  final Color? accentColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAccentColor =
        accentColor ?? AppTheme.financeColors(context).asset;
    return Semantics(
      label: semanticLabel,
      child: PremiumSurface(
        accentColor: effectiveAccentColor,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedMoneyText(
              amount: amount,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                for (final entry in metrics.indexed) ...[
                  MetricPill(
                    label: entry.$2.label,
                    value: entry.$2.value,
                    icon: entry.$2.icon,
                    color: entry.$2.color,
                  ),
                  if (entry.$1 != metrics.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MetricPill extends StatelessWidget {
  const MetricPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.expanded = false,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );

    if (!expanded) {
      return content;
    }
    return Expanded(child: content);
  }
}

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    required this.value,
    required this.color,
    required this.center,
    this.size = 86,
    super.key,
  });

  final double value;
  final Color color;
  final Widget center;
  final double size;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _ProgressRingPainter(
              value: clamped,
              color: color,
              trackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          center,
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge({
    required this.icon,
    required this.color,
    this.size = 42,
    this.iconSize = 22,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(
          alpha: Theme.of(context).brightness == Brightness.dark ? 0.20 : 0.12,
        ),
        borderRadius: BorderRadius.circular(size * 0.34),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

class RoundedBarChart extends StatelessWidget {
  const RoundedBarChart({
    required this.items,
    required this.maxValue,
    this.height = 164,
    this.semanticLabel,
    super.key,
  });

  final List<RoundedBarChartItem> items;
  final double maxValue;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Semantics(
      container: true,
      label: semanticLabel ?? _defaultSemanticLabel,
      child: SizedBox(
        height: height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _RoundedBarChartColumn(
                    item: item,
                    maxValue: maxValue,
                    height: height,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String get _defaultSemanticLabel {
    final values = items
        .map((item) {
          final primary = item.primaryValue.toStringAsFixed(0);
          final secondary = item.secondaryValue.toStringAsFixed(0);
          return '${item.label}，主值 $primary，副值 $secondary';
        })
        .join('；');
    return '柱状图，$values';
  }
}

class RoundedBarChartItem {
  const RoundedBarChartItem({
    required this.label,
    required this.primaryValue,
    required this.secondaryValue,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final String label;
  final double primaryValue;
  final double secondaryValue;
  final Color primaryColor;
  final Color secondaryColor;
}

class CategoryRankTile extends StatelessWidget {
  const CategoryRankTile({
    required this.name,
    required this.icon,
    required this.amount,
    required this.percentage,
    required this.count,
    required this.color,
    this.rank,
    super.key,
  });

  final String name;
  final String icon;
  final String amount;
  final double percentage;
  final int count;
  final Color color;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final progress = (percentage / 100).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    final displayName = name.isEmpty ? '未分类' : name;
    return Semantics(
      label:
          '${rank == null ? '' : '第$rank名，'}$displayName，$amount，${percentage.toStringAsFixed(1)}%，$count 笔',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              color.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.14
                    : 0.07,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    if (rank != null) ...[
                      _RankBadge(rank: rank!, color: color),
                      const SizedBox(width: 10),
                    ],
                    IconBadge(
                      icon: _categoryIconData(icon),
                      color: color,
                      size: 40,
                      iconSize: 21,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 7,
                            runSpacing: 6,
                            children: [
                              _RankMetaPill(
                                icon: Icons.receipt_long_outlined,
                                label: '$count 笔',
                                color: color,
                              ),
                              _RankMetaPill(
                                icon: Icons.donut_large_outlined,
                                label: '${percentage.toStringAsFixed(1)}%',
                                color: colorScheme.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      amount,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.color});

  final int rank;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        '#$rank',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RankMetaPill extends StatelessWidget {
  const _RankMetaPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 24, maxWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.09),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FinanceMetricData {
  const FinanceMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _RoundedBarChartColumn extends StatelessWidget {
  const _RoundedBarChartColumn({
    required this.item,
    required this.maxValue,
    required this.height,
  });

  final RoundedBarChartItem item;
  final double maxValue;
  final double height;

  @override
  Widget build(BuildContext context) {
    final chartHeight = height - 28;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _RoundedChartBar(
                    value: item.primaryValue,
                    maxValue: maxValue,
                    color: item.primaryColor,
                    chartHeight: chartHeight,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _RoundedChartBar(
                    value: item.secondaryValue,
                    maxValue: maxValue,
                    color: item.secondaryColor,
                    chartHeight: chartHeight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundedChartBar extends StatelessWidget {
  const _RoundedChartBar({
    required this.value,
    required this.maxValue,
    required this.color,
    required this.chartHeight,
  });

  final double value;
  final double maxValue;
  final Color color;
  final double chartHeight;

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = maxValue <= 0 || value <= 0
        ? 5.0
        : math.max(value / maxValue * chartHeight, 8.0);
    return Container(
      height: effectiveHeight,
      decoration: BoxDecoration(
        color: value <= 0
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

IconData _categoryIconData(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'food' || 'restaurant' || '餐饮' || '🍽️' => Icons.restaurant_outlined,
    'transport' || 'car' || '交通' || '🚗' => Icons.directions_car_outlined,
    'shopping' || 'cart' || '购物' || '🛒' => Icons.shopping_bag_outlined,
    'home' || 'house' || '住房' || '🏠' => Icons.home_outlined,
    'salary' || 'income' || '工资' || '💰' => Icons.payments_outlined,
    'medical' || 'health' || '医疗' => Icons.medical_services_outlined,
    'education' || '学习' => Icons.school_outlined,
    _ => Icons.category_outlined,
  };
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = math.max(size.width * 0.10, 7.0);
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2;
    final arcRect = rect.deflate(inset);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2, false, track);
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * value, false, progress);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}
