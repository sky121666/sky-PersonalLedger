import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
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
      title: '设置密码',
      subtitle: '',
      primaryLabel: '账本保护',
      serverUrl: authState.serverUrl,
      accentColor: accentColor,
      footer: TextButton.icon(
        onPressed: isLoading
            ? null
            : ref.read(authControllerProvider.notifier).changeServer,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('更换账本'),
      ),
      children: [
        TextField(
          controller: _passwordController,
          enabled: !isLoading,
          obscureText: _obscurePassword,
          decoration: authFlowInputDecoration(
            context,
            labelText: '密码',
            prefixIcon: const Icon(Icons.password_outlined),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
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
          decoration: authFlowInputDecoration(
            context,
            labelText: '确认密码',
            errorText: errorText,
            prefixIcon: const Icon(Icons.verified_user_outlined),
            suffixIcon: IconButton(
              tooltip: _obscureConfirmPassword ? '显示确认密码' : '隐藏确认密码',
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
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: isLoading ? null : _submit,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('完成设置'),
          ),
        ),
      ],
    );
  }
}
