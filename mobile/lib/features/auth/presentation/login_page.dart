import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../application/auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _localError;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _localError = '密码至少需要 6 位');
      return;
    }

    setState(() => _localError = null);
    await ref.read(authControllerProvider.notifier).login(password);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.stage == AuthStage.checking;
    final errorText = _localError ?? authState.errorMessage;

    final accentColor = AppTheme.financeColors(context).asset;
    return AuthFlowShell(
      icon: Icons.lock_outline,
      title: '欢迎回来',
      subtitle: '解锁你的私人财务工作台，继续查看收支、预算、家庭和 AI 分析。',
      primaryLabel: '安全登录',
      serverUrl: authState.serverUrl ?? '个人记账',
      accentColor: accentColor,
      footer: TextButton.icon(
        onPressed: isLoading
            ? null
            : ref.read(authControllerProvider.notifier).changeServer,
        icon: const Icon(Icons.dns_outlined),
        label: const Text('更换服务器'),
      ),
      children: [
        _LoginAssuranceRail(accentColor: accentColor),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          enabled: !isLoading,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: '密码',
            border: const OutlineInputBorder(),
            errorText: errorText,
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
              : const Icon(Icons.login),
          label: const Text('登录'),
        ),
      ],
    );
  }
}

class _LoginAssuranceRail extends StatelessWidget {
  const _LoginAssuranceRail({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    return Row(
      children: [
        Expanded(
          child: _LoginAssuranceTile(
            icon: Icons.dns_outlined,
            label: '私有部署',
            color: accentColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LoginAssuranceTile(
            icon: Icons.devices_other_outlined,
            label: '设备会话',
            color: financeColors.income,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LoginAssuranceTile(
            icon: Icons.account_balance_wallet_outlined,
            label: '财务数据',
            color: financeColors.asset,
          ),
        ),
      ],
    );
  }
}

class _LoginAssuranceTile extends StatelessWidget {
  const _LoginAssuranceTile({
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
