import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
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

  Future<void> _createToken() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入令牌名称')));
      return;
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
        return;
      }
      setState(() {
        _createdToken = result.token;
        _tokens = tokens;
        _nameController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('令牌创建成功，请立即复制保存')));
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
        title: const Text('API Token'),
        actions: [
          IconButton(
            onPressed: _loadTokens,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
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
          _InfoCard(),
          const SizedBox(height: 16),
          _CreateTokenCard(
            nameController: _nameController,
            expiryDays: _expiryDays,
            submitting: _submitting,
            onExpiryChanged: (value) =>
                setState(() => _expiryDays = value ?? _expiryDays),
            onCreate: _createToken,
          ),
          if (_createdToken != null) ...[
            const SizedBox(height: 16),
            _CreatedTokenCard(token: _createdToken!, onCopy: _copyCreatedToken),
          ],
          const SizedBox(height: 16),
          Text('已创建的令牌', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_tokens.isEmpty)
            const AppEmptyView(
              title: '暂无令牌',
              message: '创建令牌后可用于 App 或 API 访问。',
              icon: Icons.vpn_key_outlined,
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < _tokens.length; index++) ...[
                    _TokenTile(
                      token: _tokens[index],
                      deleting: _submitting,
                      onDelete: () => _deleteToken(_tokens[index]),
                    ),
                    if (index != _tokens.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.vpn_key_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'API Token 可用于 App 或外部 API 访问。完整令牌只会在创建成功后显示一次。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('创建新令牌', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('api-token-name'),
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '令牌名称',
                hintText: '例如：我的手机',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: expiryDays,
              decoration: const InputDecoration(
                labelText: '有效期',
                border: OutlineInputBorder(),
              ),
              items: _expiryOptions
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.days,
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
              onChanged: submitting ? null : onExpiryChanged,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: submitting ? null : onCreate,
              icon: const Icon(Icons.add),
              label: Text(submitting ? '处理中...' : '创建令牌'),
            ),
          ],
        ),
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
    return Card(
      color: Colors.green.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Text('令牌创建成功', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '请立即复制并保存，此令牌只显示一次。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SelectableText(
              token,
              key: const ValueKey('api-token-created-value'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy),
              label: const Text('复制令牌'),
            ),
          ],
        ),
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
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.smartphone_outlined)),
      title: Text(token.name),
      subtitle: Text(_tokenSubtitle(token)),
      trailing: IconButton(
        onPressed: deleting ? null : onDelete,
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除令牌',
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
