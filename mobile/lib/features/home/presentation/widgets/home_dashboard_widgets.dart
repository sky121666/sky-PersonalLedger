import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/widgets/premium_surface.dart';
import '../../data/home_repository.dart';

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
              '还没有家庭支出',
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
        ],
      ),
    );
  }
}

String _formatCurrency(double value) {
  return '¥${value.toStringAsFixed(2)}';
}
