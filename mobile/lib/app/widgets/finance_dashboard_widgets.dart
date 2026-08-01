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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AnimatedMoneyText(
              amount: amount,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
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
                  if (entry.$1 != metrics.length - 1) const Divider(indent: 24),
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
                fontWeight: FontWeight.w500,
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
              fontWeight: FontWeight.w600,
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
    final colorScheme = Theme.of(context).colorScheme;
    final fill = colorScheme.surfaceContainerHigh;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size <= 34 ? 9 : 10),
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

class CashFlowLineChart extends StatelessWidget {
  const CashFlowLineChart({
    required this.items,
    this.height = 188,
    this.semanticLabel,
    super.key,
  });

  final List<CashFlowLineChartItem> items;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label:
          semanticLabel ??
          '收支趋势，${items.map((item) => '${item.label}收入${item.income.toStringAsFixed(0)}支出${item.expense.toStringAsFixed(0)}').join('；')}',
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _CashFlowLineChartPainter(
            items: items,
            incomeColor: financeColors.income,
            expenseColor: financeColors.expense,
            gridColor: colorScheme.outlineVariant.withValues(alpha: 0.58),
            labelColor: colorScheme.onSurfaceVariant,
            labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
            surfaceColor: colorScheme.surface,
          ),
        ),
      ),
    );
  }
}

class CashFlowLineChartItem {
  const CashFlowLineChartItem({
    required this.label,
    required this.income,
    required this.expense,
  });

  final String label;
  final double income;
  final double expense;
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
    final effectiveColor = colorScheme.primary;
    final displayName = name.isEmpty ? '未分类' : name;
    return Semantics(
      label:
          '${rank == null ? '' : '第$rank名，'}$displayName，$amount，${percentage.toStringAsFixed(1)}%，$count 笔',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            children: [
              Row(
                children: [
                  if (rank != null) ...[
                    _RankBadge(rank: rank!, color: effectiveColor),
                    const SizedBox(width: 8),
                  ],
                  IconBadge(
                    icon: _categoryIconData(icon),
                    color: effectiveColor,
                    size: 34,
                    iconSize: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count 笔 · ${percentage.toStringAsFixed(1)}%',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    amount,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: effectiveColor,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
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
    return SizedBox(
      width: 24,
      child: Center(
        child: Text(
          '$rank',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
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

class _CashFlowLineChartPainter extends CustomPainter {
  const _CashFlowLineChartPainter({
    required this.items,
    required this.incomeColor,
    required this.expenseColor,
    required this.gridColor,
    required this.labelColor,
    required this.labelStyle,
    required this.surfaceColor,
  });

  final List<CashFlowLineChartItem> items;
  final Color incomeColor;
  final Color expenseColor;
  final Color gridColor;
  final Color labelColor;
  final TextStyle? labelStyle;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    const leftInset = 38.0;
    const rightInset = 8.0;
    const topInset = 8.0;
    const bottomInset = 24.0;
    final chartRect = Rect.fromLTRB(
      leftInset,
      topInset,
      size.width - rightInset,
      size.height - bottomInset,
    );
    final maxValue = items.fold<double>(0, (current, item) {
      return math.max(current, math.max(item.income, item.expense));
    });
    final axisMax = maxValue <= 0 ? 1.0 : maxValue * 1.08;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.6;

    for (var index = 0; index < 4; index += 1) {
      final ratio = index / 3;
      final y = chartRect.bottom - chartRect.height * ratio;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
      final label = _compactAxisValue(axisMax * ratio);
      _paintText(
        canvas,
        label,
        Offset(0, y - 7),
        width: leftInset - 8,
        textAlign: TextAlign.right,
      );
    }

    final incomePoints = _pointsFor(chartRect, axisMax, (item) => item.income);
    final expensePoints = _pointsFor(
      chartRect,
      axisMax,
      (item) => item.expense,
    );
    _drawSeries(canvas, chartRect, incomePoints, incomeColor, fill: true);
    _drawSeries(canvas, chartRect, expensePoints, expenseColor, fill: false);

    for (var index = 0; index < items.length; index += 1) {
      final x = incomePoints[index].dx;
      final width = math.min(52.0, chartRect.width / items.length);
      _paintText(
        canvas,
        items[index].label,
        Offset(x - width / 2, chartRect.bottom + 7),
        width: width,
        textAlign: TextAlign.center,
      );
    }
  }

  List<Offset> _pointsFor(
    Rect rect,
    double axisMax,
    double Function(CashFlowLineChartItem item) valueOf,
  ) {
    final divisor = math.max(items.length - 1, 1);
    return [
      for (var index = 0; index < items.length; index += 1)
        Offset(
          rect.left + rect.width * index / divisor,
          rect.bottom -
              rect.height * (valueOf(items[index]).clamp(0, axisMax) / axisMax),
        ),
    ];
  }

  void _drawSeries(
    Canvas canvas,
    Rect rect,
    List<Offset> points,
    Color color, {
    required bool fill,
  }) {
    if (points.isEmpty) {
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(points.last.dx, rect.bottom)
        ..lineTo(points.first.dx, rect.bottom)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.07));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final pointFill = Paint()..color = surfaceColor;
    final pointStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in points) {
      canvas
        ..drawCircle(point, 4, pointFill)
        ..drawCircle(point, 4, pointStroke);
    }
  }

  void _paintText(
    Canvas canvas,
    String value,
    Offset offset, {
    required double width,
    required TextAlign textAlign,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style:
            labelStyle ??
            TextStyle(
              color: labelColor,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  String _compactAxisValue(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(value >= 100000 ? 0 : 1)}万';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _CashFlowLineChartPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.incomeColor != incomeColor ||
        oldDelegate.expenseColor != expenseColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.surfaceColor != surfaceColor;
  }
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
