import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/ledger_icon.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../core/formatters/money_formatter.dart';
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
  var _groups = <_LogGroup>[];
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
        _groups = _groupLogsByDate(result.list);
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
      final logs = [..._logs, ...result.list];
      setState(() {
        _logs = logs;
        _groups = _groupLogsByDate(logs);
        _total = result.total;
        _page = result.page;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('明细加载失败')));
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
        title: Text(account == null ? '账户明细' : '${account.name}明细'),
      ),
      body: AdaptivePageContainer(child: _buildBody(account)),
    );
  }

  Widget _buildBody(Account? account) {
    if (_loading && _logs.isEmpty) {
      return const AppLoadingView(message: '明细加载中...');
    }
    final error = _error;
    if (error != null && _logs.isEmpty) {
      return AppErrorView(message: '明细加载失败', onRetry: _loadFirstPage);
    }
    if (_logs.isEmpty) {
      const rows = [
        _AccountLogEmptyRow(SizedBox(height: 96)),
        _AccountLogEmptyRow(_AccountLogEmptyState(), 0),
      ];
      return RefreshIndicator(
        onRefresh: _loadFirstPage,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            return Padding(
              padding: EdgeInsets.only(
                bottom: index == rows.length - 1 ? 0 : row.bottomSpacing,
              ),
              child: row.child,
            );
          },
        ),
      );
    }

    final groupStartIndex = account == null ? 0 : 2;
    final loadMoreIndex = groupStartIndex + _groups.length;
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: loadMoreIndex + 1,
        itemBuilder: (context, index) {
          if (account != null) {
            if (index == 0) {
              return _AccountSummaryCard(account: account);
            }
            if (index == 1) {
              return const SizedBox(height: 12);
            }
          }
          if (index == loadMoreIndex) {
            return _LoadMoreFooter(
              hasMore: _hasMore,
              loading: _loadingMore,
              onLoadMore: _loadMore,
            );
          }
          final group = _groups[index - groupStartIndex];
          return _AccountLogGroupCard(
            group: group,
            showAccount: account == null,
          );
        },
      ),
    );
  }
}

class _AccountLogEmptyState extends StatelessWidget {
  const _AccountLogEmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox.square(
              dimension: 42,
              child: Icon(
                Icons.receipt_long_outlined,
                size: 20,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '还没有明细',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '记一笔后会在这里出现',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountLogEmptyRow {
  const _AccountLogEmptyRow(this.child, [this.bottomSpacing = 0]);

  final Widget child;
  final double bottomSpacing;
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
  });

  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore) {
      return const SizedBox(height: 4);
    }
    return FilledButton.tonal(
      onPressed: loading ? null : onLoadMore,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.expand_more),
          const SizedBox(width: 8),
          Text(loading ? '加载中' : '加载更多'),
        ],
      ),
    );
  }
}

class _AccountLogGroupCard extends StatelessWidget {
  const _AccountLogGroupCard({required this.group, required this.showAccount});

  final _LogGroup group;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DateHeader(
            date: group.date,
            count: group.logs.length,
            totalChange: group.totalChange,
          ),
          const SizedBox(height: 8),
          PremiumSurface(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Column(
              children: [
                for (var index = 0; index < group.logs.length; index++)
                  _AccountLogTile(
                    key: ValueKey('account-log-tile-${group.logs[index].id}'),
                    log: group.logs[index],
                    showAccount: showAccount,
                    isLast: index == group.logs.length - 1,
                  ),
              ],
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  const _DateHeader({
    required this.date,
    required this.count,
    required this.totalChange,
  });

  final DateTime date;
  final int count;
  final double totalChange;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final totalColor = totalChange > 0
        ? financeColors.income
        : totalChange < 0
        ? financeColors.expense
        : colorScheme.outline;
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
              const SizedBox(width: 8),
              Text(
                _formatSignedMoney(totalChange),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: totalColor,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountLogTile extends StatefulWidget {
  const _AccountLogTile({
    super.key,
    required this.log,
    required this.showAccount,
    required this.isLast,
  });

  final AccountLogItem log;
  final bool showAccount;
  final bool isLast;

  @override
  State<_AccountLogTile> createState() => _AccountLogTileState();
}

class _AccountLogTileState extends State<_AccountLogTile> {
  bool _showRemark = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final typeStyle = _typeStyle(context, log.type);
    final change = log.balanceChange;
    final isLast = widget.isLast;
    final showAccount = widget.showAccount;
    final financeColors = AppTheme.financeColors(context);
    final changeColor = change > 0
        ? financeColors.income
        : change < 0
        ? financeColors.expense
        : Theme.of(context).colorScheme.outline;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(
              icon: typeStyle.icon,
              color: typeStyle.color,
              size: 34,
              iconSize: 17,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    log.type.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (showAccount && log.account != null) log.account!.name,
                      _formatTime(log.createdAt),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_showRemark && log.remark.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      log.remark,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                _formatSignedMoney(change),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: changeColor,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (log.remark.isNotEmpty)
              IconButton(
                key: ValueKey('account-log-remark-toggle-${log.id}'),
                onPressed: () => setState(() {
                  _showRemark = !_showRemark;
                }),
                icon: Icon(_showRemark ? Icons.remove : Icons.add, size: 20),
                tooltip: _showRemark ? '收起账户变动备注' : '展开账户变动备注',
              ),
          ],
        ),
      ),
    );
  }
}

class _LogGroup {
  const _LogGroup({required this.date, required this.logs});

  final DateTime date;
  final List<AccountLogItem> logs;

  double get totalChange => logs.fold(0, (sum, log) => sum + log.balanceChange);
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
  return formatMoney(value);
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
