import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
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
            tooltip: '刷新',
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
            AppEmptyView(
              title: '暂无流水记录',
              message: '交易、还款或余额调整后会自动生成账户流水。',
              icon: Icons.receipt_long_outlined,
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
            _AccountSummaryCard(account: account),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '共 $_total 条流水记录',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final group in groups) ...[
            _DateHeader(date: group.date),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < group.logs.length; index++) ...[
                    _AccountLogTile(
                      log: group.logs[index],
                      showAccount: account == null,
                    ),
                    if (index != group.logs.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_hasMore)
            OutlinedButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(_loadingMore ? '加载中...' : '加载更多'),
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
    return Card(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.18),
              child: Text(account.icon.isEmpty ? '💰' : account.icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前余额 ${_formatMoney(account.currentBalance)}',
                    style: Theme.of(context).textTheme.bodyMedium,
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

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        _formatGroupDate(date),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

class _AccountLogTile extends StatelessWidget {
  const _AccountLogTile({required this.log, required this.showAccount});

  final AccountLogItem log;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final typeStyle = _typeStyle(log.type);
    final change = log.balanceChange;
    final changeColor = change > 0
        ? Colors.green.shade700
        : change < 0
        ? Colors.red.shade700
        : Theme.of(context).colorScheme.outline;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: typeStyle.color.withValues(alpha: 0.14),
        child: Icon(typeStyle.icon, color: typeStyle.color),
      ),
      title: Row(
        children: [
          Text(log.type.label),
          if (showAccount && log.account != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                log.account!.name,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_formatMoney(log.balanceBefore)} -> ${_formatMoney(log.balanceAfter)}',
          ),
          if (log.remark.isNotEmpty)
            Text(log.remark, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(_formatTime(log.createdAt)),
        ],
      ),
      trailing: Text(
        _formatSignedMoney(change),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: changeColor,
          fontWeight: FontWeight.bold,
        ),
      ),
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

_TypeStyle _typeStyle(AccountLogType type) {
  return switch (type) {
    AccountLogType.income => _TypeStyle(
      icon: Icons.trending_up,
      color: Colors.green.shade700,
    ),
    AccountLogType.expense => _TypeStyle(
      icon: Icons.trending_down,
      color: Colors.red.shade700,
    ),
    AccountLogType.transferIn => _TypeStyle(
      icon: Icons.swap_horiz,
      color: Colors.blue.shade700,
    ),
    AccountLogType.transferOut => _TypeStyle(
      icon: Icons.swap_horiz,
      color: Colors.orange.shade700,
    ),
    AccountLogType.rollback => _TypeStyle(
      icon: Icons.undo,
      color: Colors.purple.shade700,
    ),
    AccountLogType.adjustment => _TypeStyle(
      icon: Icons.auto_fix_high,
      color: Colors.grey.shade700,
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
