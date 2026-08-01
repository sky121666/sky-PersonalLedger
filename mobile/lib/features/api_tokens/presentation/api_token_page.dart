import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../data/api_token_repository.dart';

const _expiryOptions = [
  _ExpiryOption(30, '30 天'),
  _ExpiryOption(90, '90 天'),
  _ExpiryOption(365, '1 年'),
  _ExpiryOption(0, '持续有效'),
];

const _scopeOptions = [
  _ScopeOption('ledger:read', '读取账本', '查看账户、交易与分类'),
  _ScopeOption('ledger:write', '修改账本', '新增、编辑与删除账本数据'),
  _ScopeOption('report:read', '查看报表', '读取统计与导出结果'),
  _ScopeOption('upload:read', '下载附件', '读取头像与交易附件'),
  _ScopeOption('upload:write', '管理附件', '上传或删除附件'),
];

class ApiTokenPage extends ConsumerStatefulWidget {
  const ApiTokenPage({super.key});

  @override
  ConsumerState<ApiTokenPage> createState() => _ApiTokenPageState();
}

class _ApiTokenPageState extends ConsumerState<ApiTokenPage> {
  final _nameController = TextEditingController();

  var _tokens = <ApiTokenItem>[];
  var _expiryDays = 90;
  final _selectedScopes = <String>{...apiTokenDefaultScopes};
  var _loading = true;
  var _submitting = false;
  Object? _error;
  ApiTokenCreateResult? _createdToken;

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
      ).showSnackBar(const SnackBar(content: Text('请输入设备名称')));
      return false;
    }
    if (_selectedScopes.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一项访问权限')));
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
            ApiTokenCreateRequest(
              name: name,
              expiresInDays: _expiryDays,
              scopes: _selectedScopes.toList(growable: false),
            ),
          );
      final tokens = await ref.read(apiTokenRepositoryProvider).list();
      if (!mounted) {
        return false;
      }
      setState(() {
        _createdToken = result;
        _tokens = tokens;
        _nameController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加入码已生成')));
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('授权生成失败')));
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
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: _CreateTokenCard(
              nameController: _nameController,
              expiryDays: _expiryDays,
              selectedScopes: _selectedScopes,
              submitting: _submitting,
              onExpiryChanged: (value) {
                final next = value ?? _expiryDays;
                setState(() => _expiryDays = next);
                setSheetState(() {});
              },
              onScopeChanged: (scope, selected) {
                setState(() {
                  if (selected) {
                    _selectedScopes.add(scope);
                  } else {
                    _selectedScopes.remove(scope);
                  }
                });
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
      title: '删除授权',
      message: '删除「${token.name}」？',
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
      ).showSnackBar(const SnackBar(content: Text('授权已删除')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('授权删除失败')));
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _copyCreatedToken() async {
    final token = _createdToken?.token;
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
        title: const Text('设备授权'),
        actions: [
          IconButton(
            key: const ValueKey('api-token-add'),
            onPressed: _submitting ? null : _openCreateSheet,
            tooltip: '添加授权',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading && _tokens.isEmpty) {
      return const AppLoadingView(message: '授权加载中...');
    }
    final error = _error;
    if (error != null && _tokens.isEmpty) {
      return AppErrorView(message: '设备授权加载失败', onRetry: _loadTokens);
    }
    final rows = _buildTokenRows();

    return RefreshIndicator(
      onRefresh: _loadTokens,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final bottom = index == rows.length - 1 ? 0.0 : row.bottomSpacing;
          return Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: switch (row.kind) {
              _ApiTokenRowKind.created => _CreatedTokenCard(
                token: _createdToken!.token,
                scopes: _createdToken!.scopes,
                onCopy: _copyCreatedToken,
              ),
              _ApiTokenRowKind.header => _TokenListHeader(
                tokenCount: _tokens.length,
              ),
              _ApiTokenRowKind.empty => const _EmptyTokenState(
                title: '还没有授权',
                message: '右上角添加',
                icon: Icons.vpn_key_outlined,
              ),
              _ApiTokenRowKind.token => _TokenTile(
                token: row.token!,
                deleting: _submitting,
                onDelete: () => _deleteToken(row.token!),
              ),
            },
          );
        },
      ),
    );
  }

  List<_ApiTokenRow> _buildTokenRows() {
    return [
      if (_createdToken != null) const _ApiTokenRow.created(),
      if (_tokens.isEmpty)
        const _ApiTokenRow.empty()
      else ...[
        const _ApiTokenRow.header(),
        for (final token in _tokens) _ApiTokenRow.token(token),
      ],
    ];
  }
}

enum _ApiTokenRowKind { created, header, empty, token }

class _ApiTokenRow {
  const _ApiTokenRow.created()
    : kind = _ApiTokenRowKind.created,
      token = null,
      bottomSpacing = 12;

  const _ApiTokenRow.header()
    : kind = _ApiTokenRowKind.header,
      token = null,
      bottomSpacing = 8;

  const _ApiTokenRow.empty()
    : kind = _ApiTokenRowKind.empty,
      token = null,
      bottomSpacing = 0;

  const _ApiTokenRow.token(this.token)
    : kind = _ApiTokenRowKind.token,
      bottomSpacing = 8;

  final _ApiTokenRowKind kind;
  final ApiTokenItem? token;
  final double bottomSpacing;
}

class _TokenListHeader extends StatelessWidget {
  const _TokenListHeader({required this.tokenCount});

  final int tokenCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: colorScheme.primary,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '授权设备',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  tokenCount == 0 ? '未启用' : '$tokenCount 个可用',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.key_outlined, size: 18, color: colorScheme.primary),
        ],
      ),
    );
  }
}

class _EmptyTokenState extends StatelessWidget {
  const _EmptyTokenState({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      accentColor: colorScheme.primary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: icon,
            color: colorScheme.primary,
            size: 34,
            iconSize: 17,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
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

class _CreateTokenCard extends StatelessWidget {
  const _CreateTokenCard({
    required this.nameController,
    required this.expiryDays,
    required this.selectedScopes,
    required this.submitting,
    required this.onExpiryChanged,
    required this.onScopeChanged,
    required this.onCreate,
  });

  final TextEditingController nameController;
  final int expiryDays;
  final Set<String> selectedScopes;
  final bool submitting;
  final ValueChanged<int?> onExpiryChanged;
  final void Function(String scope, bool selected) onScopeChanged;
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
            title: '新增设备授权',
            color: colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('api-token-name'),
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '设备名称',
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
          if (expiryDays == 0) ...[
            const SizedBox(height: 8),
            Text(
              '持续有效授权风险更高，建议只用于受控设备。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '访问权限',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            key: const ValueKey('api-token-scope-surface'),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < _scopeOptions.length; index++) ...[
                  CheckboxListTile(
                    key: ValueKey(
                      'api-token-scope-${_scopeOptions[index].value}',
                    ),
                    value: selectedScopes.contains(_scopeOptions[index].value),
                    onChanged: submitting
                        ? null
                        : (selected) => onScopeChanged(
                            _scopeOptions[index].value,
                            selected ?? false,
                          ),
                    title: Text(_scopeOptions[index].label),
                    subtitle: Text(_scopeOptions[index].description),
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  if (index != _scopeOptions.length - 1)
                    Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: submitting || selectedScopes.isEmpty ? null : onCreate,
            icon: const Icon(Icons.add),
            label: Text(submitting ? '处理中' : '生成授权'),
          ),
        ],
      ),
    );
  }
}

class _CreatedTokenCard extends StatelessWidget {
  const _CreatedTokenCard({
    required this.token,
    required this.scopes,
    required this.onCopy,
  });

  final String token;
  final List<String> scopes;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final successColor = AppTheme.financeColors(context).income;
    return PremiumSurface(
      accentColor: successColor,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '一次性加入码',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconBadge(
                key: const ValueKey('api-token-created-success-icon'),
                icon: Icons.check_circle_outline,
                color: successColor,
                size: 30,
                iconSize: 16,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '一次性加入码',
            textField: true,
            child: SelectableText(
              token,
              key: const ValueKey('api-token-created-value'),
              maxLines: 1,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final scope in scopes)
                _ScopeChip(label: _apiTokenScopeLabel(scope)),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('复制加入码'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 12),
        Icon(icon, size: 18, color: color),
      ],
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
      label: '${token.name}，${_tokenStatus(token)}',
      button: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.46),
          ),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SizedBox.square(
                dimension: 34,
                child: Icon(
                  Icons.smartphone_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
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
                    _tokenStatus(token),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final scope in token.scopes)
                        _ScopeChip(label: _apiTokenScopeLabel(scope)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              key: ValueKey('api-token-delete-${token.id}'),
              onPressed: deleting ? null : onDelete,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(44, 44),
                visualDensity: VisualDensity.compact,
                foregroundColor: financeColors.expense,
              ),
              child: const Text('删除'),
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

class _ScopeOption {
  const _ScopeOption(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _apiTokenScopeLabel(String scope) {
  for (final option in _scopeOptions) {
    if (option.value == scope) {
      return option.label;
    }
  }
  return scope;
}

String _tokenStatus(ApiTokenItem token) {
  if (token.expiresAt == null) {
    return token.lastUsedAt == null ? '未启用 · 持续有效' : '最近使用 · 持续有效';
  }
  final expiry = '有效至 ${_formatDate(token.expiresAt!)}';
  return token.lastUsedAt == null ? '未启用 · $expiry' : '最近使用 · $expiry';
}

String _formatDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}
