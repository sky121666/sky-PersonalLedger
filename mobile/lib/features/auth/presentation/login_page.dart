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
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
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

    return AuthFlowShell(
      icon: Icons.lock_outline,
      title: '账本解锁',
      subtitle: '',
      primaryLabel: '登录',
      serverUrl: authState.serverUrl,
      accentColor: AppTheme.financeColors(context).asset,
      footer: TextButton.icon(
        onPressed: isLoading
            ? null
            : ref.read(authControllerProvider.notifier).changeServer,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('更换账本'),
      ),
      children: [
        TextField(
          key: const ValueKey('auth-login-password-field'),
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          autofocus: false,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          obscureText: _obscurePassword,
          decoration: authFlowInputDecoration(
            context,
            labelText: '密码',
            errorText: errorText,
            prefixIcon: const Icon(Icons.password_outlined),
            suffixIcon: IconButton(
              key: const ValueKey('auth-login-password-visibility-toggle'),
              tooltip: null,
              onPressed: () => setState(() {
                _obscurePassword = !_obscurePassword;
              }),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ),
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => isLoading ? null : _submit(),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('auth-login-submit-button'),
            onPressed: isLoading ? null : _submit,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('登录'),
          ),
        ),
      ],
    );
  }
}
