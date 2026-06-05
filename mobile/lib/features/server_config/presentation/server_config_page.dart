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
  final FocusNode _serverUrlFocusNode = FocusNode();

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
    _serverUrlFocusNode.dispose();
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
      title: '连接账本',
      subtitle: '',
      primaryLabel: '个人账本',
      accentColor: accentColor,
      children: [
        TextField(
          key: const ValueKey('server-url-field'),
          controller: _serverUrlController,
          focusNode: _serverUrlFocusNode,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.url],
          textCapitalization: TextCapitalization.none,
          decoration: authFlowInputDecoration(
            context,
            labelText: '账本地址',
            hintText: 'https://你的账本域名',
            errorText: authState.errorMessage,
            prefixIcon: const Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => isLoading ? null : _submitServerUrl(),
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const ValueKey('server-connect-button'),
            onPressed: isLoading ? null : _submitServerUrl,
            icon: isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: const Text('进入账本'),
          ),
        ),
      ],
    );
  }
}
