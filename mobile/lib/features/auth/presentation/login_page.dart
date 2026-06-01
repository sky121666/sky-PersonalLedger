import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/auth_flow_shell.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
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
        const SizedBox(height: 14),
        _LoginAccessMatrix(
          controller: _passwordController,
          accentColor: accentColor,
        ),
        const SizedBox(height: 14),
        _LoginSessionSignalDeck(
          controller: _passwordController,
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
            errorText: errorText,
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

class _LoginAccessMatrix extends StatelessWidget {
  const _LoginAccessMatrix({
    required this.controller,
    required this.accentColor,
  });

  final TextEditingController controller;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ready = controller.text.length >= 6;
        final stateColor = ready ? financeColors.income : colorScheme.outline;
        final tiles = [
          _LoginAccessTileData(
            icon: Icons.dns_outlined,
            title: '私有服务',
            value: '已绑定',
            caption: '独立数据源',
            color: accentColor,
          ),
          _LoginAccessTileData(
            icon: Icons.phonelink_lock_outlined,
            title: '本设备',
            value: '会话解锁',
            caption: '本机安全态',
            color: financeColors.asset,
          ),
          _LoginAccessTileData(
            icon: ready ? Icons.verified_outlined : Icons.lock_clock_outlined,
            title: '密码闸门',
            value: ready ? '可登录' : '${controller.text.length}/6',
            caption: '输入校验',
            color: stateColor,
          ),
        ];
        return PremiumSurface(
          key: const ValueKey('login-access-matrix'),
          accentColor: stateColor,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                key: const ValueKey('login-session-evidence-rail'),
                children: [
                  IconBadge(
                    icon: Icons.grid_view_rounded,
                    color: stateColor,
                    size: 38,
                    iconSize: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '访问控制矩阵',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _LoginMatrixPill(
                    label: ready ? '就绪' : '待解锁',
                    color: stateColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final entry in tiles.indexed) ...[
                    Expanded(child: _LoginAccessTile(data: entry.$2)),
                    if (entry.$1 != tiles.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LoginAccessTileData {
  const _LoginAccessTileData({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String caption;
  final Color color;
}

class _LoginAccessTile extends StatelessWidget {
  const _LoginAccessTile({required this.data});

  final _LoginAccessTileData data;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          data.color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(data.icon, color: data.color, size: 18),
          const SizedBox(height: 6),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            data.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          _LoginMatrixPill(label: data.caption, color: data.color),
        ],
      ),
    );
  }
}

class _LoginMatrixPill extends StatelessWidget {
  const _LoginMatrixPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 26, maxWidth: 108),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
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

class _LoginSessionSignalDeck extends StatelessWidget {
  const _LoginSessionSignalDeck({
    required this.controller,
    required this.accentColor,
  });

  final TextEditingController controller;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final length = controller.text.length;
        final ready = length >= 6;
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
                    icon: Icons.key_outlined,
                    color: ready ? financeColors.income : accentColor,
                    size: 38,
                    iconSize: 19,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '会话解锁信号',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ready ? '密码长度就绪，可发起登录' : '输入 6 位以上密码后解锁',
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
                    child: _LoginSignalTile(
                      icon: ready
                          ? Icons.verified_outlined
                          : Icons.lock_clock_outlined,
                      label: '密码状态',
                      value: ready ? '可登录' : '$length/6',
                      color: ready ? financeColors.income : colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LoginSignalTile(
                      icon: Icons.visibility_off_outlined,
                      label: '屏幕保护',
                      value: '默认隐藏',
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _LoginSignalTile(
                      icon: Icons.devices_other_outlined,
                      label: '登录范围',
                      value: '本设备会话',
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

class _LoginSignalTile extends StatelessWidget {
  const _LoginSignalTile({
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
