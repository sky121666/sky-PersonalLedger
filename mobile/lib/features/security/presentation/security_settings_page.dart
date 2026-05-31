import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
import '../../../app/widgets/staggered_entrance.dart';
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
        StaggeredEntrance(
          index: 0,
          child: _SecurityOverviewCard(entryPath: _entryPath),
        ),
        const SizedBox(height: 16),
        StaggeredEntrance(
          index: 1,
          child: _PasswordCard(
            oldPasswordController: _oldPasswordController,
            newPasswordController: _newPasswordController,
            confirmPasswordController: _confirmPasswordController,
            submitting: _passwordSubmitting,
            onSubmit: _changePassword,
          ),
        ),
        const SizedBox(height: 16),
        StaggeredEntrance(
          index: 2,
          child: _EntryPathCard(
            entryPath: _entryPath,
            controller: _entryPathController,
            submitting: _entrySubmitting,
            onSave: _saveEntryPath,
            onGenerate: _generateEntryPath,
            onDisable: _disableEntryPath,
            onToggle: _toggleEntryPath,
          ),
        ),
      ],
    );
  }
}

class _SecurityOverviewCard extends StatelessWidget {
  const _SecurityOverviewCard({required this.entryPath});

  final SecurityEntryPath entryPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final accent = entryPath.enabled
        ? financeColors.asset
        : financeColors.warning;
    final securityPosture = entryPath.enabled ? 1.0 : 0.5;
    return PremiumSurface(
      accentColor: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.admin_panel_settings_outlined,
                color: accent,
                size: 46,
                iconSize: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '安全控制台',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entryPath.enabled ? '安全入口已启用' : '安全入口未启用',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accent.withValues(alpha: 0.14),
                    colorScheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.22)),
                ),
                child: Text(
                  entryPath.enabled ? 'Protected' : 'Open',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SecurityMetric(
                  icon: Icons.route_outlined,
                  label: '入口路径',
                  value: entryPath.enabled ? entryPath.displayPath : '未启用',
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecurityMetric(
                  icon: Icons.password_outlined,
                  label: '密码策略',
                  value: '8 位以上',
                  color: financeColors.expense,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SecurityMetric(
                  icon: Icons.radar_outlined,
                  label: '安全态势',
                  value: entryPath.enabled ? '已隔离 · 改密退出' : '待启用 · 改密退出',
                  color: colorScheme.tertiary,
                  progress: securityPosture,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecurityMetric extends StatelessWidget {
  const _SecurityMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.progress,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          if (progress != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 5,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
          ],
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
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return PremiumSurface(
      accentColor: financeColors.expense,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SecuritySectionHeader(
            icon: Icons.lock_outline,
            color: financeColors.expense,
            title: '修改密码',
            subtitle: '修改后会退出当前登录态',
          ),
          const SizedBox(height: 12),
          _SecurityFlowStrip(
            items: [
              _SecurityFlowItem(
                icon: Icons.password_outlined,
                label: '验证旧密码',
                value: '当前态',
                color: financeColors.asset,
              ),
              _SecurityFlowItem(
                icon: Icons.enhanced_encryption_outlined,
                label: '设置新密码',
                value: '8 位以上',
                color: financeColors.expense,
              ),
              _SecurityFlowItem(
                icon: Icons.logout_outlined,
                label: '会话处理',
                value: '自动退出',
                color: colorScheme.tertiary,
              ),
            ],
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

class _SecurityFlowItem {
  const _SecurityFlowItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
}

class _SecurityFlowStrip extends StatelessWidget {
  const _SecurityFlowStrip({required this.items});

  final List<_SecurityFlowItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          Expanded(child: _SecurityFlowTile(item: items[index])),
          if (index != items.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _SecurityFlowTile extends StatelessWidget {
  const _SecurityFlowTile({required this.item});

  final _SecurityFlowItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          item.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(item.icon, size: 17, color: item.color),
          const SizedBox(height: 6),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 1),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
    final financeColors = AppTheme.financeColors(context);
    final stateColor = entryPath.enabled
        ? financeColors.asset
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
          const SizedBox(height: 12),
          _SecurityFlowStrip(
            items: [
              _SecurityFlowItem(
                icon: Icons.route_outlined,
                label: '入口模式',
                value: entryPath.enabled ? '隔离' : '直达',
                color: stateColor,
              ),
              _SecurityFlowItem(
                icon: Icons.auto_fix_high_outlined,
                label: '生成策略',
                value: '随机',
                color: financeColors.asset,
              ),
              _SecurityFlowItem(
                icon: Icons.block_outlined,
                label: '关闭保护',
                value: entryPath.enabled ? '需确认' : '已关闭',
                color: entryPath.enabled
                    ? colorScheme.error
                    : colorScheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _EntryGuardrailPanel(entryPath: entryPath),
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

class _EntryGuardrailPanel extends StatelessWidget {
  const _EntryGuardrailPanel({required this.entryPath});

  final SecurityEntryPath entryPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final accent = entryPath.enabled
        ? financeColors.asset
        : colorScheme.outline;
    return AnimatedContainer(
      key: const ValueKey('security-entry-guardrail-panel'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.075,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.security_update_good_outlined,
                color: accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '入口守护策略',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _EntryGuardrailPill(
                label: entryPath.enabled ? '隔离中' : '未隔离',
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _EntryGuardrailTile(
                  icon: Icons.route_outlined,
                  label: '入口路径',
                  value: entryPath.enabled ? entryPath.displayPath : '直达登录',
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EntryGuardrailTile(
                  icon: Icons.auto_fix_high_outlined,
                  label: '生成方式',
                  value: '随机可换',
                  color: financeColors.asset,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _EntryGuardrailTile(
                  icon: Icons.privacy_tip_outlined,
                  label: '关闭影响',
                  value: entryPath.enabled ? '需确认' : '开放',
                  color: entryPath.enabled
                      ? colorScheme.error
                      : financeColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryGuardrailTile extends StatelessWidget {
  const _EntryGuardrailTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryGuardrailPill extends StatelessWidget {
  const _EntryGuardrailPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 28, maxWidth: 118),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
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
