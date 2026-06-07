import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
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
        _showMessage('密码修改失败');
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
      _showMessage('请输入登录入口');
      return;
    }
    await _runEntryPathAction(
      () => ref.read(securityRepositoryProvider).setEntryPath(value),
      '登录保护已保存',
    );
  }

  Future<void> _generateEntryPath() async {
    await _runEntryPathAction(
      ref.read(securityRepositoryProvider).generateEntryPath,
      '登录入口已生成',
    );
  }

  Future<void> _disableEntryPath() async {
    if (!_entryPath.enabled) {
      _entryPathController.clear();
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '禁用登录保护',
      message: '关闭登录保护？',
      confirmText: '禁用',
      isDanger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _runEntryPathAction(
      ref.read(securityRepositoryProvider).disableEntryPath,
      '登录保护已禁用',
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
        _showMessage('登录保护保存失败');
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
            key: const ValueKey('security-entry-refresh'),
            onPressed: _isBusy ? null : _loadEntryPath,
            icon: const Icon(Icons.refresh),
            tooltip: null,
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
      return AppErrorView(message: '安全设置加载失败', onRetry: _loadEntryPath);
    }

    final rows = [
      _SecurityRow(
        _PasswordSummaryCard(
          submitting: _passwordSubmitting,
          onTap: _openPasswordSheet,
        ),
      ),
      _SecurityRow(
        _EntryPathCard(
          entryPath: _entryPath,
          controller: _entryPathController,
          submitting: _entrySubmitting,
          onSave: _saveEntryPath,
          onGenerate: _generateEntryPath,
          onDisable: _disableEntryPath,
          onToggle: _toggleEntryPath,
        ),
        0,
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
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
    );
  }

  Future<void> _openPasswordSheet() async {
    if (_isBusy) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: _PasswordCard(
              oldPasswordController: _oldPasswordController,
              newPasswordController: _newPasswordController,
              confirmPasswordController: _confirmPasswordController,
              submitting: _passwordSubmitting,
              onSubmit: _changePassword,
            ),
          ),
        );
      },
    );
  }
}

class _SecurityRow {
  const _SecurityRow(this.child, [this.bottomSpacing = 12]);

  final Widget child;
  final double bottomSpacing;
}

class _PasswordSummaryCard extends StatelessWidget {
  const _PasswordSummaryCard({required this.submitting, required this.onTap});

  final bool submitting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    return PremiumSurface(
      accentColor: financeColors.expense,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '密码',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '下次登录生效',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.lock_outline, size: 18, color: financeColors.expense),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const ValueKey('security-open-password-sheet'),
            onPressed: submitting ? null : onTap,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('修改'),
          ),
        ],
      ),
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
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.expense,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SecuritySectionHeader(
            icon: Icons.lock_outline,
            color: financeColors.expense,
            title: '修改密码',
          ),
          const SizedBox(height: 12),
          _SecurityPasswordField(
            keyValue: 'security-old-password',
            controller: oldPasswordController,
            label: '当前密码',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _SecurityPasswordField(
            keyValue: 'security-new-password',
            controller: newPasswordController,
            label: '新密码',
            hint: '至少 8 位',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          _SecurityPasswordField(
            keyValue: 'security-confirm-password',
            controller: confirmPasswordController,
            label: '确认新密码',
            onSubmitted: (_) => submitting ? null : onSubmit(),
          ),
          const SizedBox(height: 12),
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
            label: Text(submitting ? '修改中' : '确认修改'),
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
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final stateColor = entryPath.enabled
        ? financeColors.asset
        : colorScheme.outline;
    return PremiumSurface(
      accentColor: stateColor,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _SecuritySectionHeader(
                  icon: Icons.shield_outlined,
                  color: stateColor,
                  title: '登录保护',
                ),
              ),
              Semantics(
                key: const ValueKey('security-entry-enabled-semantics'),
                label: '启用登录保护',
                toggled: entryPath.enabled,
                enabled: !submitting,
                child: Switch(
                  value: entryPath.enabled,
                  onChanged: submitting ? null : onToggle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('security-entry-path'),
            controller: controller,
            enabled: !submitting,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: InputDecoration(
              labelText: '登录入口',
              hintText: '/my-ledger',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('security-entry-save'),
                  onPressed: submitting ? null : onSave,
                  icon: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(submitting ? '保存中' : '保存'),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: '生成登录入口',
                button: true,
                child: IconButton.filledTonal(
                  key: const ValueKey('security-entry-generate'),
                  onPressed: submitting ? null : onGenerate,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  tooltip: null,
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: '禁用登录保护',
                button: true,
                child: IconButton.outlined(
                  key: const ValueKey('security-entry-disable'),
                  onPressed: submitting || !entryPath.enabled
                      ? null
                      : onDisable,
                  icon: const Icon(Icons.block_outlined),
                  tooltip: null,
                ),
              ),
            ],
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
  });

  final IconData icon;
  final Color color;
  final String title;

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
        Icon(icon, size: 18, color: color),
      ],
    );
  }
}
