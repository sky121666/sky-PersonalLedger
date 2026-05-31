import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeSettings>(
      (ref) => ThemeController()..load(),
    );

enum AppThemeMode { system, light, dark }

class AppThemeSettings {
  const AppThemeSettings({
    this.mode = AppThemeMode.system,
    this.palette = AppThemePalette.teal,
  });

  final AppThemeMode mode;
  final AppThemePalette palette;

  AppThemeSettings copyWith({AppThemeMode? mode, AppThemePalette? palette}) {
    return AppThemeSettings(
      mode: mode ?? this.mode,
      palette: palette ?? this.palette,
    );
  }
}

class ThemeController extends StateNotifier<AppThemeSettings> {
  ThemeController() : super(const AppThemeSettings());

  static const _modeKey = 'app_theme_mode';
  static const _paletteKey = 'app_theme_palette';

  /// 读取本机保存的主题偏好。
  Future<void> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final mode = _themeModeFromName(preferences.getString(_modeKey));
      final palette = AppThemePalette.fromId(
        preferences.getString(_paletteKey),
      );
      state = AppThemeSettings(mode: mode, palette: palette);
    } catch (_) {
      state = const AppThemeSettings();
    }
  }

  /// 切换应用主题模式。
  Future<void> setThemeMode(AppThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _save(_modeKey, mode.name);
  }

  /// 切换应用主题色模板。
  Future<void> setPalette(AppThemePalette palette) async {
    state = state.copyWith(palette: palette);
    await _save(_paletteKey, palette.id);
  }

  Future<void> _save(String key, String value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
    } catch (_) {
      // Theme preferences are non-critical; keep the in-memory state usable.
    }
  }

  AppThemeMode _themeModeFromName(String? value) {
    return AppThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => AppThemeMode.system,
    );
  }
}
