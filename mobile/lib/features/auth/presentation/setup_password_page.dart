import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../application/auth_controller.dart';

/// Initial provisioning uses the browser flow, which accepts the deployment's
/// setup token and database settings. The mobile app connects after that step.
class SetupPasswordPage extends ConsumerWidget {
  const SetupPasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.stage == AuthStage.checking;
    final serverUrl = authState.serverUrl;

    return AuthFlowShell(
      icon: Icons.admin_panel_settings_outlined,
      title: '先在浏览器初始化',
      subtitle: '完成首次设置后，再回来登录账本',
      primaryLabel: '首次使用',
      serverUrl: serverUrl,
      accentColor: AppTheme.financeColors(context).warning,
      footer: TextButton.icon(
        onPressed: isLoading
            ? null
            : ref.read(authControllerProvider.notifier).changeServer,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('更换账本'),
      ),
      children: [
        const Text('请在浏览器中打开部署时提供的初始化链接（包含初始化令牌），完成账本密码等首次设置。手机端暂不支持这一步。'),
        const SizedBox(height: 12),
        const Text('如果不是你部署的账本，请联系管理员完成初始化。'),
        if (serverUrl != null && serverUrl.isNotEmpty) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('auth-setup-copy-address'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: serverUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('账本地址已复制')));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('复制账本地址'),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('auth-setup-recheck-button'),
          onPressed: isLoading
              ? null
              : ref.read(authControllerProvider.notifier).bootstrap,
          child: Text(isLoading ? '正在检查…' : '已完成，重新检查'),
        ),
      ],
    );
  }
}
