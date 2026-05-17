import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';
import '../../auth/application/auth_controller.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  /// 构建我的页和主题设置入口。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: AdaptivePageContainer(
        child: ListView(
          children: [
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: const Text('个人记账'),
                subtitle: const Text('Flutter 原生移动端'),
                trailing: IconButton(
                  onPressed: () => _confirmLogout(context, ref),
                  icon: const Icon(Icons.logout),
                  tooltip: '退出登录',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('账户管理'),
                    subtitle: const Text('新增、编辑、归档和删除账户'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.accounts),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('账户流水'),
                    subtitle: const Text('查看全部账户余额变动记录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.accountLogs),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('分类管理'),
                    subtitle: const Text('维护收入和支出分类'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.categories),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.savings_outlined),
                    title: const Text('预算管理'),
                    subtitle: const Text('设置总预算和分类预算提醒线'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.budgets),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('负债管理'),
                    subtitle: const Text('查看还款提醒和上岸进度'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.reminders),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('借贷往来'),
                    subtitle: const Text('管理借出、借入和还款记录'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.lendings),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_none_outlined),
                    title: const Text('通知设置'),
                    subtitle: const Text('配置提醒通道和通知类型'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.notifications),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('数据管理'),
                    subtitle: const Text('备份、恢复和导出交易数据'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.dataManagement),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.summarize_outlined),
                    title: const Text('年度报告'),
                    subtitle: const Text('查看年度收支、结余和分类排行'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.yearlyReport),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('更换服务器'),
                subtitle: const Text('清除本机登录态并重新连接服务地址'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _confirmChangeServer(context, ref),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: RadioGroup<AppThemeMode>(
                groupValue: themeMode,
                onChanged: (value) => _setThemeMode(ref, value),
                child: const Column(
                  children: [
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.system,
                      title: Text('跟随系统'),
                    ),
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.light,
                      title: Text('浅色模式'),
                    ),
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.dark,
                      title: Text('深色模式'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 更新主题模式。
  void _setThemeMode(WidgetRef ref, AppThemeMode? value) {
    if (value == null) {
      return;
    }
    ref.read(themeModeControllerProvider.notifier).setThemeMode(value);
  }

  /// 展示退出确认弹窗。
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '确认退出',
      message: '退出后需要重新输入密码登录。',
      confirmText: '退出',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authControllerProvider.notifier).logout();
  }

  /// 展示更换服务器确认弹窗。
  Future<void> _confirmChangeServer(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: '更换服务器',
      message: '这会清除当前服务器地址和本机登录态，之后需要重新连接。',
      confirmText: '更换',
      isDanger: true,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(authControllerProvider.notifier).changeServer();
  }
}
