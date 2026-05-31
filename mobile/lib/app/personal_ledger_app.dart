import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_controller.dart';

class PersonalLedgerApp extends ConsumerWidget {
  const PersonalLedgerApp({super.key});

  /// 构建个人记账应用入口并接入主题模式。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeControllerProvider);
    return MaterialApp.router(
      title: '个人记账',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(themeSettings.palette),
      darkTheme: AppTheme.darkTheme(themeSettings.palette),
      themeAnimationDuration: AppTheme.themeAnimationDuration,
      themeAnimationCurve: AppTheme.themeAnimationCurve,
      themeMode: switch (themeSettings.mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
