import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../../../core/config/server_config_service.dart';
import '../../../core/config/local_http_transport_policy.dart';
import '../../auth/application/auth_controller.dart';

class ServerConfigPage extends ConsumerStatefulWidget {
  const ServerConfigPage({super.key});

  @override
  ConsumerState<ServerConfigPage> createState() => _ServerConfigPageState();
}

class _ServerConfigPageState extends ConsumerState<ServerConfigPage> {
  final TextEditingController _serverUrlController = TextEditingController();
  final FocusNode _serverUrlFocusNode = FocusNode();
  String? _localValidationError;

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
    final input = _serverUrlController.text;
    var acknowledgeInsecureLocalHttp = false;
    if (_localValidationError != null) {
      setState(() => _localValidationError = null);
    }
    if (ServerConfigService.requiresInsecureLocalHttpConfirmation(input)) {
      final cleartextPermitted = await ref
          .read(localHttpTransportPolicyProvider)
          .isCleartextTrafficPermitted();
      if (!mounted) {
        return;
      }
      if (!cleartextPermitted) {
        setState(() {
          _localValidationError =
              '当前 Android 构建未启用明文 HTTP。请改用 HTTPS，或使用明确启用局域网 HTTP 的开发/私有构建。';
        });
        return;
      }
      FocusScope.of(context).unfocus();
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: '局域网 HTTP 风险',
        message: '该地址使用未加密的 HTTP。仅在你信任的私有局域网内继续；登录信息和账本数据可能被同网设备截获。',
        cancelText: '返回修改',
        confirmText: '继续连接',
        isDanger: true,
      );
      if (!confirmed || !mounted) {
        return;
      }
      acknowledgeInsecureLocalHttp = true;
    }
    await ref
        .read(authControllerProvider.notifier)
        .connectServer(
          input,
          acknowledgeInsecureLocalHttp: acknowledgeInsecureLocalHttp,
        );
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
          autofocus: false,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.url],
          textCapitalization: TextCapitalization.none,
          decoration: authFlowInputDecoration(
            context,
            labelText: '账本地址',
            hintText: 'https://你的账本域名',
            errorText: _localValidationError ?? authState.errorMessage,
            prefixIcon: const Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => isLoading ? null : _submitServerUrl(),
          onChanged: (_) {
            if (_localValidationError != null) {
              setState(() => _localValidationError = null);
            }
          },
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
