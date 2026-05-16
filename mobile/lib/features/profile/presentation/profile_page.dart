import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_route_paths.dart';
import '../../../app/theme/theme_mode_controller.dart';
import '../../../app/widgets/adaptive_page_container.dart';
import '../../../app/widgets/app_state_views.dart';

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
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout),
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
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('分类管理'),
                    subtitle: const Text('维护收入和支出分类'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutePaths.categories),
                  ),
                ],
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
  Future<void> _confirmLogout(BuildContext context) async {
    await showAppConfirmDialog(
      context: context,
      title: '确认退出',
      message: '当前认证流程尚未接入，后续会在这里清理登录态。',
      confirmText: '知道了',
    );
  }
}
