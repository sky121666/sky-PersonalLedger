import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
import '../data/api_token_repository.dart';

const _expiryOptions = [
  _ExpiryOption(0, '永不过期'),
  _ExpiryOption(30, '30 天'),
  _ExpiryOption(90, '90 天'),
  _ExpiryOption(365, '1 年'),
];

class ApiTokenPage extends ConsumerStatefulWidget {
  const ApiTokenPage({super.key});

  @override
  ConsumerState<ApiTokenPage> createState() => _ApiTokenPageState();
}

class _ApiTokenPageState extends ConsumerState<ApiTokenPage> {
  final _nameController = TextEditingController();

  var _tokens = <ApiTokenItem>[];
  var _expiryDays = 0;
  var _loading = true;
  var _submitting = false;
  Object? _error;
  String? _createdToken;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadTokens);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadTokens() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() => _tokens = tokens);
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

  Future<bool> _createToken() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入令牌名称')));
      return false;
    }

    setState(() {
      _submitting = true;
      _createdToken = null;
    });
    try {
      final result = await ref
          .read(apiTokenRepositoryProvider)
          .create(
            ApiTokenCreateRequest(name: name, expiresInDays: _expiryDays),
          );
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return false;
      }
      setState(() {
        _createdToken = result.token;
        _tokens = tokens;
        _nameController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('令牌创建成功，请立即复制保存')));
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _openCreateSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: _CreateTokenCard(
              nameController: _nameController,
              expiryDays: _expiryDays,
              submitting: _submitting,
              onExpiryChanged: (value) {
                final next = value ?? _expiryDays;
                setState(() => _expiryDays = next);
                setSheetState(() {});
              },
              onCreate: () async {
                final created = await _createToken();
                if (created && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                } else {
                  setSheetState(() {});
                }
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteToken(ApiTokenItem token) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '删除令牌',
      message: '删除后使用此令牌的 App 或 API 将无法访问。',
      confirmText: '删除',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(apiTokenRepositoryProvider).delete(token.id);
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return;
      }
      setState(() => _tokens = tokens);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('令牌已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _copyCreatedToken() async {
    final token = _createdToken;
    if (token == null || token.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: token));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('访问令牌'),
        actions: [
          IconButton(
            onPressed: _loadTokens,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新访问令牌',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('api-token-add'),
        onPressed: _submitting ? null : _openCreateSheet,
        tooltip: '新增令牌',
        child: const Icon(Icons.add),
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _tokens.isEmpty) {
      return const AppLoadingView(message: '令牌加载中...');
    }
    final error = _error;
    if (error != null && _tokens.isEmpty) {
      return AppErrorView(message: error.toString(), onRetry: _loadTokens);
    }

    return RefreshIndicator(
      onRefresh: _loadTokens,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_createdToken != null) ...[
            StaggeredEntrance(
              index: 0,
              child: _CreatedTokenCard(
                token: _createdToken!,
                onCopy: _copyCreatedToken,
              ),
            ),
            const SizedBox(height: 12),
          ],
          StaggeredEntrance(
            index: _createdToken == null ? 0 : 1,
            child: _TokenListHeader(tokenCount: _tokens.length),
          ),
          const SizedBox(height: 8),
          StaggeredEntrance(
            index: _createdToken == null ? 1 : 2,
            child: _tokens.isEmpty
                ? const PremiumSurface(
                    padding: EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                    child: AppEmptyView(
                      title: '暂无令牌',
                      icon: Icons.vpn_key_outlined,
                    ),
                  )
                : PremiumSurface(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < _tokens.length;
                          index++
                        ) ...[
                          _TokenTile(
                            token: _tokens[index],
                            deleting: _submitting,
                            onDelete: () => _deleteToken(_tokens[index]),
                          ),
                          if (index != _tokens.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TokenListHeader extends StatelessWidget {
  const _TokenListHeader({required this.tokenCount});

  final int tokenCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconBadge(
          icon: Icons.key_outlined,
          color: colorScheme.primary,
          size: 34,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已创建的令牌',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 2),
              Text(
                tokenCount == 0 ? '尚未创建' : '$tokenCount 个',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.color,
    this.iconKey,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Key? iconKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconBadge(
          key: iconKey,
          icon: icon,
          color: color,
          size: 42,
          iconSize: 21,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateTokenCard extends StatelessWidget {
  const _CreateTokenCard({
    required this.nameController,
    required this.expiryDays,
    required this.submitting,
    required this.onExpiryChanged,
    required this.onCreate,
  });

  final TextEditingController nameController;
  final int expiryDays;
  final bool submitting;
  final ValueChanged<int?> onExpiryChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.secondary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: Icons.add_moderator_outlined,
            title: '创建新令牌',
            color: colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('api-token-name'),
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '令牌名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '有效期',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _expiryOptions)
                ChoiceChip(
                  label: Text(option.label),
                  selected: expiryDays == option.days,
                  onSelected: submitting
                      ? null
                      : (_) => onExpiryChanged(option.days),
                ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: submitting ? null : onCreate,
            icon: const Icon(Icons.add),
            label: Text(submitting ? '处理中...' : '创建令牌'),
          ),
        ],
      ),
    );
  }
}

class _CreatedTokenCard extends StatelessWidget {
  const _CreatedTokenCard({required this.token, required this.onCopy});

  final String token;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final successColor = AppTheme.financeColors(context).income;
    return PremiumSurface(
      accentColor: successColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            icon: Icons.check_circle_outline,
            iconKey: const ValueKey('api-token-created-success-icon'),
            title: '令牌创建成功',
            color: successColor,
          ),
          const SizedBox(height: 12),
          Semantics(
            label: '一次性完整令牌',
            textField: true,
            child: Container(
              key: const ValueKey('api-token-created-value'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: SelectableText(
                token,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy),
            label: const Text('复制令牌'),
          ),
        ],
      ),
    );
  }
}

class _TokenTile extends StatelessWidget {
  const _TokenTile({
    required this.token,
    required this.deleting,
    required this.onDelete,
  });

  final ApiTokenItem token;
  final bool deleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Semantics(
      label: '${token.name}，${_tokenSubtitle(token)}',
      button: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.46),
          ),
        ),
        child: Row(
          children: [
            IconBadge(
              icon: Icons.smartphone_outlined,
              color: colorScheme.primary,
              size: 34,
              iconSize: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          token.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _tokenSubtitle(token),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              onPressed: deleting ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: deleting ? '正在处理' : '删除令牌 ${token.name}',
              style: IconButton.styleFrom(
                foregroundColor: financeColors.expense,
                backgroundColor: financeColors.expense.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryOption {
  const _ExpiryOption(this.days, this.label);

  final int days;
  final String label;
}

String _tokenSubtitle(ApiTokenItem token) {
  final parts = <String>[
    '${token.tokenPrefix}...',
    token.lastUsedAt == null
        ? '未使用'
        : '最后使用 ${_formatDateTime(token.lastUsedAt!)}',
    token.expiresAt == null ? '永不过期' : '${_formatDate(token.expiresAt!)} 过期',
  ];
  return parts.join(' · ');
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${_formatDate(value)} ${two(value.hour)}:${two(value.minute)}';
}
