import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../../auth/application/auth_controller.dart';

class ServerConfigPage extends ConsumerStatefulWidget {
  const ServerConfigPage({super.key});

  @override
  ConsumerState<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends ConsumerState<ServerConfigPage> {
  final TextEditingController _serverUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final serverUrl = ref.read(authControllerProvider).serverUrl;
    if (serverUrl != null) {
      _serverUrlController.text = serverUrl;
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _submitServerUrl() async {
    await ref
        .read(authControllerProvider.notifier)
        .connectServer(_serverUrlController.text);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.stage == AuthStage.checking;

    final accentColor = AppTheme.financeColors(context).brand;
    return AuthFlowShell(
      icon: Icons.account_balance_wallet_outlined,
      title: '连接服务器',
      subtitle: '请输入自托管个人记账服务地址，连接后会自动判断是否需要首次初始化。',
      primaryLabel: '自托管入口',
      accentColor: accentColor,
      children: [
        TextField(
          controller: _serverUrlController,
          enabled: !isLoading,
          decoration: InputDecoration(
            labelText: '服务器地址',
            hintText: 'example.com:8080',
            border: const OutlineInputBorder(),
            errorText: authState.errorMessage,
            prefixIcon: const Icon(Icons.dns_outlined),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => isLoading ? null : _submitServerUrl(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: isLoading ? null : _submitServerUrl,
          icon: isLoading
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.arrow_forward),
          label: const Text('连接'),
        ),
      ],
    );
  }
}
