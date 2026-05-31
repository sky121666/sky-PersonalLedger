import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
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
