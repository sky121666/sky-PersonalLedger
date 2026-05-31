import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../auth/application/auth_controller.dart';
import '../data/security_repository.dart';

class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  ConsumerState<SecuritySettingsPage> createState() =>
      _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _entryPathController = TextEditingController();

  var _entryPath = const SecurityEntryPath.disabled();
  var _loading = true;
  var _entrySubmitting = false;
  var _passwordSubmitting = false;
  Object? _error;

  bool get _isBusy => _entrySubmitting || _passwordSubmitting;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadEntryPath);
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _entryPathController.dispose();
    super.dispose();
  }

  Future<void> _loadEntryPath() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entryPath = await ref
          .read(securityRepositoryProvider)
          .getEntryPath();
      if (!mounted) {
        return;
      }
      setState(() {
        _entryPath = entryPath;
        _entryPathController.text = entryPath.entryPath;
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

  Future<void> _changePassword() async {
    final oldPassword = _oldPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (oldPassword.isEmpty) {
      _showMessage('请输入当前密码');
      return;
    }
    if (newPassword.length < 8) {
      _showMessage('新密码至少需要 8 位');
      return;
    }
    if (newPassword != confirmPassword) {
      _showMessage('两次输入的新密码不一致');
      return;
    }

    setState(() => _passwordSubmitting = true);
    try {
      await ref
          .read(securityRepositoryProvider)
          .changePassword(oldPassword: oldPassword, newPassword: newPassword);
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) {
        return;
      }
      _showMessage('密码已修改，请重新登录');
      await ref.read(authControllerProvider.notifier).logout();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _passwordSubmitting = false);
      }
    }
  }

  Future<void> _saveEntryPath() async {
    final value = _entryPathController.text.trim();
    if (value.isEmpty) {
      _showMessage('请输入入口路径，或点击禁用入口');
      return;
    }
    await _runEntryPathAction(
      () => ref.read(securityRepositoryProvider).setEntryPath(value),
      '安全入口已保存',
    );
  }

  Future<void> _generateEntryPath() async {
    await _runEntryPathAction(
      ref.read(securityRepositoryProvider).generateEntryPath,
      '已生成随机入口',
    );
  }

  Future<void> _disableEntryPath() async {
    if (!_entryPath.enabled) {
      _entryPathController.clear();
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '禁用安全入口',
      message: '禁用后可直接访问登录页。确认继续？',
      confirmText: '禁用',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runEntryPathAction(
      ref.read(securityRepositoryProvider).disableEntryPath,
      '安全入口已禁用',
    );
  }

  Future<void> _toggleEntryPath(bool enabled) async {
    if (enabled) {
      if (_entryPathController.text.trim().isEmpty) {
        await _generateEntryPath();
      } else {
        await _saveEntryPath();
      }
      return;
    }
    await _disableEntryPath();
  }

  Future<void> _runEntryPathAction(
    Future<SecurityEntryPath> Function() action,
    String message,
  ) async {
    setState(() => _entrySubmitting = true);
    try {
      final entryPath = await action();
      if (!mounted) {
        return;
      }
      setState(() {
        _entryPath = entryPath;
        _entryPathController.text = entryPath.entryPath;
      });
      _showMessage(message);
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _entrySubmitting = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号安全'),
        actions: [
          IconButton(
            onPressed: _isBusy ? null : _loadEntryPath,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: AdaptivePageContainer(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoadingView(message: '安全设置加载中...');
    }
    final error = _error;
    if (error != null) {
      return AppErrorView(message: error.toString(), onRetry: _loadEntryPath);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _PasswordCard(
          oldPasswordController: _oldPasswordController,
          newPasswordController: _newPasswordController,
          confirmPasswordController: _confirmPasswordController,
          submitting: _passwordSubmitting,
          onSubmit: _changePassword,
        ),
        const SizedBox(height: 16),
        _EntryPathCard(
          entryPath: _entryPath,
          controller: _entryPathController,
          submitting: _entrySubmitting,
          onSave: _saveEntryPath,
          onGenerate: _generateEntryPath,
          onDisable: _disableEntryPath,
          onToggle: _toggleEntryPath,
        ),
      ],
    );
  }
}

class _PasswordCard extends StatelessWidget {
  const _PasswordCard({
    required this.oldPasswordController,
    required this.newPasswordController,
    required this.confirmPasswordController,
    required this.submitting,
    required this.onSubmit,
  });

  final TextEditingController oldPasswordController;
  final TextEditingController newPasswordController;
  final TextEditingController confirmPasswordController;
  final bool submitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: AppTheme.expenseColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SecuritySectionHeader(
            icon: Icons.lock_outline,
            color: AppTheme.expenseColor,
            title: '修改密码',
            subtitle: '修改后会退出当前登录态',
          ),
          const SizedBox(height: 16),
          _SecurityPasswordField(
            keyValue: 'security-old-password',
            controller: oldPasswordController,
            label: '当前密码',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _SecurityPasswordField(
            keyValue: 'security-new-password',
            controller: newPasswordController,
            label: '新密码',
            hint: '至少 8 位',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          _SecurityPasswordField(
            keyValue: 'security-confirm-password',
            controller: confirmPasswordController,
            label: '确认新密码',
            onSubmitted: (_) => submitting ? null : onSubmit(),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer.withValues(alpha: 0.44),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.logout_outlined, color: colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '密码修改成功后会立即退出登录，需要使用新密码重新进入。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('security-change-password-submit'),
            onPressed: submitting ? null : onSubmit,
            icon: submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(submitting ? '修改中...' : '确认修改'),
          ),
        ],
      ),
    );
  }
}

class _SecurityPasswordField extends StatelessWidget {
  const _SecurityPasswordField({
    required this.keyValue,
    required this.controller,
    required this.label,
    this.hint,
    this.textInputAction,
    this.onSubmitted,
  });

  final String keyValue;
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey(keyValue),
      controller: controller,
      obscureText: true,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _EntryPathCard extends StatelessWidget {
  const _EntryPathCard({
    required this.entryPath,
    required this.controller,
    required this.submitting,
    required this.onSave,
    required this.onGenerate,
    required this.onDisable,
    required this.onToggle,
  });

  final SecurityEntryPath entryPath;
  final TextEditingController controller;
  final bool submitting;
  final VoidCallback onSave;
  final VoidCallback onGenerate;
  final VoidCallback onDisable;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stateColor = entryPath.enabled
        ? AppTheme.incomeColor
        : colorScheme.outline;
    return PremiumSurface(
      accentColor: stateColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SecuritySectionHeader(
                  icon: Icons.shield_outlined,
                  color: stateColor,
                  title: '安全入口',
                  subtitle: entryPath.enabled ? entryPath.entryPath : '未启用',
                ),
              ),
              Switch(
                value: entryPath.enabled,
                onChanged: submitting ? null : onToggle,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('security-entry-path'),
            controller: controller,
            enabled: !submitting,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: InputDecoration(
              labelText: '入口路径',
              hintText: '/ledger',
              helperText: '启用后，登录页需要先经过该入口路径。',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('security-entry-save'),
                onPressed: submitting ? null : onSave,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(submitting ? '保存中...' : '保存入口'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('security-entry-generate'),
                onPressed: submitting ? null : onGenerate,
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: const Text('随机生成'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('security-entry-disable'),
                onPressed: submitting || !entryPath.enabled ? null : onDisable,
                icon: const Icon(Icons.block_outlined),
                label: const Text('禁用入口'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                stateColor.withValues(alpha: entryPath.enabled ? 0.12 : 0.08),
                colorScheme.surface,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: stateColor.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Icon(
                  entryPath.enabled
                      ? Icons.verified_user_outlined
                      : Icons.info_outline,
                  color: stateColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entryPath.enabled
                        ? '当前入口：${entryPath.displayPath}'
                        : '安全入口未启用',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
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

class _SecuritySectionHeader extends StatelessWidget {
  const _SecuritySectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBadge(icon: icon, color: color),
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
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
