import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeControllerProvider =
    StateNotifierProvider<ThemeModeController, AppThemeMode>(
      (ref) => ThemeModeController(),
    );

enum AppThemeMode { system, light, dark }

class ThemeModeController extends StateNotifier<AppThemeMode> {
  ThemeModeController() : super(AppThemeMode.system);

  /// 切换应用主题模式。
  void setThemeMode(AppThemeMode mode) {
    state = mode;
  }
}
