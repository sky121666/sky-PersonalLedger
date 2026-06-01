import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/premium_surface.dart';
import '../../data/home_repository.dart';

class QuickHomeActionCard extends StatelessWidget {
  const QuickHomeActionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return PremiumSurface(
      accentColor: Theme.of(context).colorScheme.primary,
      onTap: () => context.push(AppRoutePaths.quickTransaction),
      semanticLabel: '快速记账',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快速记账',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '记录一笔新的收入、支出或转账',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.add,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
          ),
          const SizedBox(width: 10),
          const _HomeActionEvidenceRail(),
        ],
      ),
    );
  }
}

class FamilyHomeSummaryCard extends StatelessWidget {
  const FamilyHomeSummaryCard({required this.summary, super.key});

  final FamilyHomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final topMembers = summary.members.take(3).toList();
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      key: const Key('family-home-summary-card'),
      accentColor: financeColors.income,
      onTap: () => context.push(AppRoutePaths.family),
      semanticLabel: '查看家庭支出详情',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '家庭支出',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _formatCurrency(summary.totalExpense),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (topMembers.isEmpty)
            Text(
              '暂无家庭成员支出',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            )
          else
            ...topMembers.map(
              (member) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(member.name)),
                    Text(_formatCurrency(member.expenseTotal)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          _FamilyHomeEvidenceRail(
            totalExpense: summary.totalExpense,
            memberCount: summary.members.length,
            visibleCount: topMembers.length,
          ),
        ],
      ),
    );
  }
}

class _HomeActionEvidenceRail extends StatelessWidget {
  const _HomeActionEvidenceRail();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Container(
      key: const ValueKey('quick-home-action-evidence-rail'),
      constraints: const BoxConstraints(minWidth: 94),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          financeColors.asset.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: financeColors.asset.withValues(alpha: 0.15)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fact_check_outlined, color: financeColors.asset, size: 17),
          const SizedBox(height: 5),
          Text(
            '入口证据',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '三类交易',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyHomeEvidenceRail extends StatelessWidget {
  const _FamilyHomeEvidenceRail({
    required this.totalExpense,
    required this.memberCount,
    required this.visibleCount,
  });

  final double totalExpense;
  final int memberCount;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final hasFamilyData = memberCount > 0;
    final hasExpense = totalExpense > 0;
    final completed = [
      hasFamilyData,
      hasExpense,
      visibleCount > 0,
    ].where((item) => item).length;
    final stateColor = completed == 3
        ? financeColors.income
        : colorScheme.outline;
    return Container(
      key: const ValueKey('family-home-evidence-rail'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          stateColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: stateColor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(Icons.groups_2_outlined, color: stateColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '家庭证据 $completed/3',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _FamilyEvidencePill(
            label: hasFamilyData ? '$memberCount 人在线' : '成员待接入',
            color: stateColor,
          ),
        ],
      ),
    );
  }
}

class _FamilyEvidencePill extends StatelessWidget {
  const _FamilyEvidencePill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _formatCurrency(double value) {
  return '¥${value.toStringAsFixed(2)}';
}
