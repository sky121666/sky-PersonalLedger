import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../application/auth_controller.dart';

class SetupPasswordPage extends ConsumerStatefulWidget {
  const SetupPasswordPage({super.key});

  @override
  ConsumerState<SetupPasswordPage> createState() => _SetupPasswordPageState();
}

class _SetupPasswordPageState extends ConsumerState<SetupPasswordPage> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _localError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (password.length < 8) {
      setState(() => _localError = '密码至少需要 8 位');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _localError = '两次输入的密码不一致');
      return;
    }

    setState(() => _localError = null);
    await ref.read(authControllerProvider.notifier).setupPassword(password);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.stage == AuthStage.checking;
    final errorText = _localError ?? authState.errorMessage;

    final accentColor = AppTheme.financeColors(context).warning;
    return AuthFlowShell(
      icon: Icons.admin_panel_settings_outlined,
      title: '首次设置密码',
      subtitle: '当前服务器尚未初始化，请只在第一次部署时创建管理员密码。',
      primaryLabel: '初始化保护',
      serverUrl: authState.serverUrl,
      accentColor: accentColor,
      footer: TextButton.icon(
        onPressed: isLoading
            ? null
            : ref.read(authControllerProvider.notifier).changeServer,
        icon: const Icon(Icons.dns_outlined),
        label: const Text('更换服务器'),
      ),
      children: [
        _SetupAssuranceRail(accentColor: accentColor),
        const SizedBox(height: 14),
        _SetupPasswordSignalDeck(
          passwordController: _passwordController,
          confirmPasswordController: _confirmPasswordController,
          accentColor: accentColor,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          enabled: !isLoading,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: '密码',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.password_outlined),
            suffixIcon: IconButton(
              onPressed: () => setState(() {
                _obscurePassword = !_obscurePassword;
              }),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _confirmPasswordController,
          enabled: !isLoading,
          obscureText: _obscureConfirmPassword,
          decoration: InputDecoration(
            labelText: '确认密码',
            border: const OutlineInputBorder(),
            errorText: errorText,
            prefixIcon: const Icon(Icons.verified_user_outlined),
            suffixIcon: IconButton(
              onPressed: () => setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              }),
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility
                    : Icons.visibility_off,
              ),
            ),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => isLoading ? null : _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: isLoading ? null : _submit,
          icon: isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('完成设置'),
        ),
      ],
    );
  }
}

class _SetupPasswordSignalDeck extends StatelessWidget {
  const _SetupPasswordSignalDeck({
    required this.passwordController,
    required this.confirmPasswordController,
    required this.accentColor,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        passwordController,
        confirmPasswordController,
      ]),
      builder: (context, _) {
        final password = passwordController.text;
        final confirmPassword = confirmPasswordController.text;
        final lengthReady = password.length >= 8;
        final matched =
            password.isNotEmpty &&
            confirmPassword.isNotEmpty &&
            password == confirmPassword;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              accentColor.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? 0.14
                    : 0.07,
              ),
              colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(
                    icon: Icons.admin_panel_settings_outlined,
                    color: matched ? financeColors.income : accentColor,
                    size: 38,
                    iconSize: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '初始化密钥策略',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          matched ? '管理员密码已满足初始化条件' : '长度达标并二次确认后才能初始化',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SetupSignalTile(
                      icon: Icons.password_outlined,
                      label: '长度',
                      value: lengthReady ? '已达标' : '${password.length}/8',
                      color: lengthReady
                          ? financeColors.income
                          : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SetupSignalTile(
                      icon: matched
                          ? Icons.verified_user_outlined
                          : Icons.rule_outlined,
                      label: '确认',
                      value: matched ? '一致' : '待确认',
                      color: matched ? financeColors.income : accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SetupSignalTile(
                      icon: Icons.looks_one_outlined,
                      label: '初始化',
                      value: '一次性',
                      color: financeColors.asset,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SetupSignalTile extends StatelessWidget {
  const _SetupSignalTile({
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 62),
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
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
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

class _SetupAssuranceRail extends StatelessWidget {
  const _SetupAssuranceRail({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _SetupAssuranceTile(
            icon: Icons.looks_one_outlined,
            label: '只初始化一次',
            color: accentColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SetupAssuranceTile(
            icon: Icons.admin_panel_settings_outlined,
            label: '管理员保护',
            color: financeColors.asset,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SetupAssuranceTile(
            icon: Icons.lock_reset_outlined,
            label: '改密退出',
            color: financeColors.income,
          ),
        ),
      ],
    );
  }
}

class _SetupAssuranceTile extends StatelessWidget {
  const _SetupAssuranceTile({
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBadge(icon: icon, color: color, size: 30, iconSize: 16),
          const SizedBox(height: 5),
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
