import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.lock_outline)),
              title: const Text('修改密码'),
              subtitle: const Text('修改后会退出当前登录态'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('security-old-password'),
              controller: oldPasswordController,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '当前密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('security-new-password'),
              controller: newPasswordController,
              obscureText: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '新密码',
                hintText: '至少 8 位',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('security-confirm-password'),
              controller: confirmPasswordController,
              obscureText: true,
              onSubmitted: (_) => submitting ? null : onSubmit(),
              decoration: const InputDecoration(
                labelText: '确认新密码',
                border: OutlineInputBorder(),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const CircleAvatar(child: Icon(Icons.shield_outlined)),
              title: const Text('安全入口'),
              subtitle: Text(entryPath.enabled ? entryPath.entryPath : '未启用'),
              value: entryPath.enabled,
              onChanged: submitting ? null : onToggle,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('security-entry-path'),
              controller: controller,
              enabled: !submitting,
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(
                labelText: '入口路径',
                hintText: '/ledger',
                helperText: '启用后，登录页需要先经过该入口路径。',
                border: OutlineInputBorder(),
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
                  onPressed: submitting || !entryPath.enabled
                      ? null
                      : onDisable,
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('禁用入口'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: entryPath.enabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    entryPath.enabled
                        ? Icons.verified_user_outlined
                        : Icons.info_outline,
                    color: entryPath.enabled
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entryPath.enabled
                          ? '当前入口：${entryPath.displayPath}'
                          : '安全入口未启用',
                      style: TextStyle(
                        color: entryPath.enabled
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
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
