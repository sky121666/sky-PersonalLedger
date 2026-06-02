import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../../accounts/data/account.dart';
import '../data/account_log_repository.dart';

class AccountLogPage extends ConsumerStatefulWidget {
  const AccountLogPage({super.key, this.accountId, this.account});

  final String? accountId;
  final Account? account;

  @override
  ConsumerState<AccountLogPage> createState() => _AccountLogPageState();
}

class AccountLogPageAccount {
  const AccountLogPageAccount(this.account);

  final Account account;
}

class _AccountLogPageState extends ConsumerState<AccountLogPage> {
  static const _pageSize = 50;

  var _logs = <AccountLogItem>[];
  var _page = 1;
  var _total = 0;
  var _loading = true;
  var _loadingMore = false;
  Object? _error;

  bool get _hasMore => _logs.length < _total;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadFirstPage);
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final result = await _fetchPage(1);
      if (!mounted) {
        return;
      }
      setState(() {
        _logs = result.list;
        _total = result.total;
        _page = result.page;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final result = await _fetchPage(_page + 1);
      if (!mounted) {
        return;
      }
      setState(() {
        _logs = [..._logs, ...result.list];
        _total = result.total;
        _page = result.page;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<AccountLogListResult> _fetchPage(int page) {
    final repository = ref.read(accountLogRepositoryProvider);
    final accountId = widget.accountId;
    if (accountId == null || accountId.isEmpty) {
      return repository.list(page: page, pageSize: _pageSize);
    }
    return repository.listByAccountId(
      accountId,
      page: page,
      pageSize: _pageSize,
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Scaffold(
      appBar: AppBar(
        title: Text(account == null ? '账户流水' : '${account.name}流水'),
        actions: [
          IconButton(
            onPressed: _loadFirstPage,
            icon: const Icon(Icons.refresh),
            tooltip: account == null ? '刷新账户流水' : '刷新${account.name}流水',
          ),
        ],
      ),
      body: AdaptivePageContainer(child: _buildBody(account)),
    );
  }

  Widget _buildBody(Account? account) {
    if (_loading && _logs.isEmpty) {
      return const AppLoadingView(message: '流水加载中...');
    }
    final error = _error;
    if (error != null && _logs.isEmpty) {
      return AppErrorView(message: error.toString(), onRetry: _loadFirstPage);
    }
    if (_logs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 96),
            StaggeredEntrance(
              index: 0,
              child: AppEmptyView(
                title: '暂无流水记录',
                icon: Icons.receipt_long_outlined,
              ),
            ),
          ],
        ),
      );
    }

    final groups = _groupLogsByDate(_logs);
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (account != null) ...[
            StaggeredEntrance(
              index: 0,
              child: _AccountSummaryCard(account: account),
            ),
            const SizedBox(height: 12),
          ],
          for (final entry in groups.indexed) ...[
            StaggeredEntrance(
              index: (account == null ? 0 : 1) + entry.$1 * 2,
              child: _DateHeader(
                date: entry.$2.date,
                count: entry.$2.logs.length,
              ),
            ),
            const SizedBox(height: 8),
            StaggeredEntrance(
              index: (account == null ? 1 : 2) + entry.$1 * 2,
              child: PremiumSurface(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    for (var index = 0; index < entry.$2.logs.length; index++)
                      _AccountLogTile(
                        log: entry.$2.logs[index],
                        showAccount: account == null,
                        isLast: index == entry.$2.logs.length - 1,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_hasMore)
            FilledButton.tonal(
              onPressed: _loadingMore ? null : _loadMore,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loadingMore)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.expand_more),
                  const SizedBox(width: 8),
                  Text(_loadingMore ? '加载中...' : '加载更多'),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  '没有更多了',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(
      account.color,
      Theme.of(context).colorScheme.primary,
    );
    return PremiumSurface(
      accentColor: color,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Center(
                  child: LedgerIcon(
                    icon: account.icon.isEmpty ? account.type : account.icon,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _accountTypeLabel(account.type),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatMoney(account.currentBalance),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date, required this.count});

  final DateTime date;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 15,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _formatGroupDate(date),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Text(
                '$count 条',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountLogTile extends StatelessWidget {
  const _AccountLogTile({
    required this.log,
    required this.showAccount,
    required this.isLast,
  });

  final AccountLogItem log;
  final bool showAccount;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final typeStyle = _typeStyle(context, log.type);
    final change = log.balanceChange;
    final financeColors = AppTheme.financeColors(context);
    final changeColor = change > 0
        ? financeColors.income
        : change < 0
        ? financeColors.expense
        : Theme.of(context).colorScheme.outline;
    final colorScheme = Theme.of(context).colorScheme;
    final directionIcon = change > 0
        ? Icons.arrow_downward_rounded
        : change < 0
        ? Icons.arrow_upward_rounded
        : Icons.drag_handle_rounded;
    final directionLabel = change > 0
        ? '余额增加'
        : change < 0
        ? '余额减少'
        : '余额不变';

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            typeStyle.color.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0.11
                  : 0.06,
            ),
            colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: typeStyle.color.withValues(alpha: 0.14)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconBadge(
                      icon: typeStyle.icon,
                      color: typeStyle.color,
                      size: 42,
                      iconSize: 21,
                    ),
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: changeColor.withValues(alpha: 0.26),
                          ),
                        ),
                        child: Icon(
                          directionIcon,
                          color: changeColor,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _LedgerMicroChip(
                            icon: typeStyle.icon,
                            label: log.type.label,
                            color: typeStyle.color,
                          ),
                          if (showAccount && log.account != null)
                            _LedgerMicroChip(
                              icon: Icons.account_balance_wallet_outlined,
                              label: log.account!.name,
                              color: colorScheme.primary,
                            ),
                          _LedgerMicroChip(
                            icon: Icons.schedule_outlined,
                            label: _formatTime(log.createdAt),
                            color: colorScheme.secondary,
                          ),
                        ],
                      ),
                      if (log.remark.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Text(
                          log.remark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatSignedMoney(change),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: changeColor,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      directionLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  changeColor.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.14
                        : 0.07,
                  ),
                  colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: changeColor.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _BalanceTracePoint(
                      label: '变动前',
                      value: _formatMoney(log.balanceBefore),
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(
                      width: 34,
                      height: 24,
                      decoration: BoxDecoration(
                        color: changeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        Icons.arrow_forward_rounded,
                        color: changeColor,
                        size: 16,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _BalanceTracePoint(
                      label: '变动后',
                      value: _formatMoney(log.balanceAfter),
                      color: changeColor,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedgerMicroChip extends StatelessWidget {
  const _LedgerMicroChip({
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
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.18
                : 0.09,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceTracePoint extends StatelessWidget {
  const _BalanceTracePoint({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _LogGroup {
  const _LogGroup({required this.date, required this.logs});

  final DateTime date;
  final List<AccountLogItem> logs;
}

class _TypeStyle {
  const _TypeStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

List<_LogGroup> _groupLogsByDate(List<AccountLogItem> logs) {
  final groups = <_LogGroup>[];
  for (final log in logs) {
    final date = DateTime(
      log.createdAt.year,
      log.createdAt.month,
      log.createdAt.day,
    );
    if (groups.isEmpty || groups.last.date != date) {
      groups.add(_LogGroup(date: date, logs: [log]));
    } else {
      groups.last.logs.add(log);
    }
  }
  return groups;
}

_TypeStyle _typeStyle(BuildContext context, AccountLogType type) {
  final financeColors = AppTheme.financeColors(context);
  return switch (type) {
    AccountLogType.income => _TypeStyle(
      icon: Icons.trending_up,
      color: financeColors.income,
    ),
    AccountLogType.expense => _TypeStyle(
      icon: Icons.trending_down,
      color: financeColors.expense,
    ),
    AccountLogType.transferIn => _TypeStyle(
      icon: Icons.swap_horiz,
      color: financeColors.asset,
    ),
    AccountLogType.transferOut => _TypeStyle(
      icon: Icons.swap_horiz,
      color: financeColors.warning,
    ),
    AccountLogType.rollback => _TypeStyle(
      icon: Icons.undo,
      color: Theme.of(context).colorScheme.tertiary,
    ),
    AccountLogType.adjustment => _TypeStyle(
      icon: Icons.auto_fix_high,
      color: Theme.of(context).colorScheme.outline,
    ),
  };
}

String _formatMoney(double value) {
  return '¥${value.toStringAsFixed(2)}';
}

String _formatSignedMoney(double value) {
  if (value == 0) {
    return _formatMoney(value);
  }
  final sign = value > 0 ? '+' : '-';
  return '$sign${_formatMoney(value.abs())}';
}

String _accountTypeLabel(String value) {
  return switch (value) {
    'cash' => '现金',
    'bank_card' => '银行卡',
    'credit_card' => '信用卡',
    'alipay' => '支付宝',
    'wechat' => '微信',
    _ => value.isEmpty ? '账户' : value,
  };
}

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}

String _formatGroupDate(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final date = DateTime(value.year, value.month, value.day);
  if (date == today) {
    return '今天';
  }
  if (date == yesterday) {
    return '昨天';
  }
  String two(int number) => number.toString().padLeft(2, '0');
  if (date.year == today.year) {
    return '${value.month}月${value.day}日';
  }
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

Color _parseColor(String value, Color fallback) {
  final hex = value.replaceFirst('#', '');
  final colorValue = int.tryParse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
  return colorValue == null ? fallback : Color(colorValue);
}
