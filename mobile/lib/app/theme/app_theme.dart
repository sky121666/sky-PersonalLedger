import 'package:flutter/material.dart';

import 'motion_tokens.dart';

enum AppThemePalette {
  teal(
    id: 'teal',
    label: '绿色',
    signature: '默认稳健',
    description: '默认金融色，稳定、克制、耐看。',
    seedColor: Color(0xFF0F766E),
    incomeColor: Color(0xFF059669),
    expenseColor: Color(0xFFDC2626),
    assetColor: Color(0xFF2563EB),
    warningColor: Color(0xFFF59E0B),
  ),
  graphite(
    id: 'graphite',
    label: '灰色',
    signature: '冷静仪表',
    description: '低饱和蓝灰，适合长期查看账本。',
    seedColor: Color(0xFF334155),
    incomeColor: Color(0xFF10B981),
    expenseColor: Color(0xFFEF4444),
    assetColor: Color(0xFF0EA5E9),
    warningColor: Color(0xFFEAB308),
  ),
  indigo(
    id: 'indigo',
    label: '蓝色',
    signature: 'AI 科技',
    description: '更偏科技和 AI 分析场景。',
    seedColor: Color(0xFF4338CA),
    incomeColor: Color(0xFF22C55E),
    expenseColor: Color(0xFFF43F5E),
    assetColor: Color(0xFF0284C7),
    warningColor: Color(0xFFF59E0B),
  ),
  emerald(
    id: 'emerald',
    label: '绿色',
    signature: '轻量日常',
    description: '更清爽，适合轻量日常记账。',
    seedColor: Color(0xFF047857),
    incomeColor: Color(0xFF16A34A),
    expenseColor: Color(0xFFE11D48),
    assetColor: Color(0xFF0891B2),
    warningColor: Color(0xFFD97706),
  ),
  amber(
    id: 'amber',
    label: '橙色',
    signature: '温暖克制',
    description: '更温暖，但保留金融产品克制感。',
    seedColor: Color(0xFFB45309),
    incomeColor: Color(0xFF15803D),
    expenseColor: Color(0xFFB91C1C),
    assetColor: Color(0xFF2563EB),
    warningColor: Color(0xFFF59E0B),
  ),
  cyan(
    id: 'cyan',
    label: '青色',
    signature: '数据看板',
    description: '更清透的科技感，适合数据看板。',
    seedColor: Color(0xFF0891B2),
    incomeColor: Color(0xFF14B8A6),
    expenseColor: Color(0xFFE11D48),
    assetColor: Color(0xFF2563EB),
    warningColor: Color(0xFFF97316),
  ),
  violet(
    id: 'violet',
    label: '紫色',
    signature: '柔和紫色',
    description: '偏紫色的强调色，适合深色和浅色模式。',
    seedColor: Color(0xFF7C3AED),
    incomeColor: Color(0xFF10B981),
    expenseColor: Color(0xFFFB7185),
    assetColor: Color(0xFF38BDF8),
    warningColor: Color(0xFFF59E0B),
  ),
  rose(
    id: 'rose',
    label: '紫色',
    signature: '精致暗调',
    description: '玫瑰色强调，适合夜间低亮度使用。',
    seedColor: Color(0xFFBE185D),
    incomeColor: Color(0xFF22C55E),
    expenseColor: Color(0xFFE11D48),
    assetColor: Color(0xFF6366F1),
    warningColor: Color(0xFFF59E0B),
  ),
  slate(
    id: 'slate',
    label: '灰色',
    signature: '商务低饱和',
    description: '低饱和商务风，适合长期使用。',
    seedColor: Color(0xFF475569),
    incomeColor: Color(0xFF16A34A),
    expenseColor: Color(0xFFDC2626),
    assetColor: Color(0xFF0284C7),
    warningColor: Color(0xFFEAB308),
  ),
  aurora(
    id: 'aurora',
    label: '青色',
    signature: '前卫清透',
    description: '青蓝高光与冷绿色，强化数据流动感。',
    seedColor: Color(0xFF0E7490),
    incomeColor: Color(0xFF2DD4BF),
    expenseColor: Color(0xFFF43F5E),
    assetColor: Color(0xFF3B82F6),
    warningColor: Color(0xFFF97316),
  ),
  obsidian(
    id: 'obsidian',
    label: '蓝色',
    signature: '夜间深蓝',
    description: '深蓝底色与高亮资产色，适合夜间重度使用。',
    seedColor: Color(0xFF1E3A8A),
    incomeColor: Color(0xFF34D399),
    expenseColor: Color(0xFFF87171),
    assetColor: Color(0xFF60A5FA),
    warningColor: Color(0xFFFBBF24),
  ),
  plasma(
    id: 'plasma',
    label: '蓝色',
    signature: '明亮蓝色',
    description: '蓝色主轴搭配明亮资产色。',
    seedColor: Color(0xFF2563EB),
    incomeColor: Color(0xFF22C55E),
    expenseColor: Color(0xFFEC4899),
    assetColor: Color(0xFF06B6D4),
    warningColor: Color(0xFFF59E0B),
  ),
  kinetic(
    id: 'kinetic',
    label: '青色',
    signature: '青橙对比',
    description: '青色主轴与橙色提示，适合需要醒目提醒的账本。',
    seedColor: Color(0xFF0D9488),
    incomeColor: Color(0xFF65A30D),
    expenseColor: Color(0xFFF43F5E),
    assetColor: Color(0xFF2563EB),
    warningColor: Color(0xFFEA580C),
  ),
  titanium(
    id: 'titanium',
    label: '灰色',
    signature: '银蓝低饱和',
    description: '银蓝低饱和底色，适合克制的日常使用。',
    seedColor: Color(0xFF64748B),
    incomeColor: Color(0xFF059669),
    expenseColor: Color(0xFFE11D48),
    assetColor: Color(0xFF0284C7),
    warningColor: Color(0xFFD97706),
  ),
  solaris(
    id: 'solaris',
    label: '橙色',
    signature: '复盘高光',
    description: '暖橙主轴搭配冷蓝资产色，适合周报和预算复盘。',
    seedColor: Color(0xFFEA580C),
    incomeColor: Color(0xFF16A34A),
    expenseColor: Color(0xFFDC2626),
    assetColor: Color(0xFF2563EB),
    warningColor: Color(0xFFF59E0B),
  ),
  luxe(
    id: 'luxe',
    label: '橙色',
    signature: '深色暗金',
    description: '深色底色搭配暖色强调，适合夜间使用。',
    seedColor: Color(0xFF854D0E),
    incomeColor: Color(0xFF22C55E),
    expenseColor: Color(0xFFF43F5E),
    assetColor: Color(0xFF38BDF8),
    warningColor: Color(0xFFFBBF24),
  );

  const AppThemePalette({
    required this.id,
    required this.label,
    required this.signature,
    required this.description,
    required this.seedColor,
    required this.incomeColor,
    required this.expenseColor,
    required this.assetColor,
    required this.warningColor,
  });

  final String id;
  final String label;
  final String signature;
  final String description;
  final Color seedColor;
  final Color incomeColor;
  final Color expenseColor;
  final Color assetColor;
  final Color warningColor;

  static const selectableValues = [
    teal,
    plasma,
    cyan,
    violet,
    solaris,
    graphite,
  ];

  bool get isSelectable => selectableValues.contains(this);

  static AppThemePalette fromId(String? id) {
    return AppThemePalette.values
        .firstWhere(
          (palette) => palette.id == id,
          orElse: () => AppThemePalette.teal,
        )
        .selectableEquivalent;
  }
}

extension AppThemePaletteCuration on AppThemePalette {
  Color get displayAccentColor {
    return switch (selectableEquivalent) {
      AppThemePalette.teal => const Color(0xFF0F766E),
      AppThemePalette.plasma => const Color(0xFF2563EB),
      AppThemePalette.cyan => const Color(0xFF0891B2),
      AppThemePalette.violet => const Color(0xFF7C3AED),
      AppThemePalette.solaris => const Color(0xFFEA580C),
      AppThemePalette.graphite => const Color(0xFF475569),
      _ => seedColor,
    };
  }

  AppThemePalette get selectableEquivalent {
    return switch (this) {
      AppThemePalette.teal || AppThemePalette.emerald => AppThemePalette.teal,
      AppThemePalette.graphite ||
      AppThemePalette.slate ||
      AppThemePalette.titanium => AppThemePalette.graphite,
      AppThemePalette.indigo ||
      AppThemePalette.obsidian ||
      AppThemePalette.plasma => AppThemePalette.plasma,
      AppThemePalette.amber ||
      AppThemePalette.solaris ||
      AppThemePalette.luxe => AppThemePalette.solaris,
      AppThemePalette.cyan ||
      AppThemePalette.aurora ||
      AppThemePalette.kinetic => AppThemePalette.cyan,
      AppThemePalette.violet || AppThemePalette.rose => AppThemePalette.violet,
    };
  }

  String get sceneLabel {
    return switch (this) {
      AppThemePalette.teal => '长期稳健记账',
      AppThemePalette.graphite => '专业资产面板',
      AppThemePalette.indigo => 'AI 分析场景',
      AppThemePalette.emerald => '轻量家庭日常',
      AppThemePalette.amber => '温暖账本复盘',
      AppThemePalette.cyan => '清透数据看板',
      AppThemePalette.violet => '柔和紫色',
      AppThemePalette.rose => '精致暗调记录',
      AppThemePalette.slate => '商务低饱和',
      AppThemePalette.aurora => '前卫数据流',
      AppThemePalette.obsidian => '夜间深蓝',
      AppThemePalette.plasma => '明亮蓝色',
      AppThemePalette.kinetic => '青橙对比',
      AppThemePalette.titanium => '银蓝低饱和',
      AppThemePalette.solaris => '周报预算复盘',
      AppThemePalette.luxe => '夜间资产展示',
    };
  }

  String get platformCue {
    return switch (this) {
      AppThemePalette.teal => '默认',
      AppThemePalette.graphite => '桌面感',
      AppThemePalette.indigo => 'AI',
      AppThemePalette.emerald => '家庭',
      AppThemePalette.amber => '复盘',
      AppThemePalette.cyan => '看板',
      AppThemePalette.violet => 'iOS',
      AppThemePalette.rose => '暗调',
      AppThemePalette.slate => '商务',
      AppThemePalette.aurora => '清透',
      AppThemePalette.obsidian => '夜间',
      AppThemePalette.plasma => '明亮',
      AppThemePalette.kinetic => '手势',
      AppThemePalette.titanium => '原生',
      AppThemePalette.solaris => '复盘',
      AppThemePalette.luxe => '暗金',
    };
  }
}

class AppTheme {
  static const Color seedColor = Color(0xFF0F766E);
  static const Color incomeColor = Color(0xFF059669);
  static const Color expenseColor = Color(0xFFDC2626);
  static const Color assetColor = Color(0xFF2563EB);
  static const Color warningColor = Color(0xFFF59E0B);
  static const double surfaceRadius = 16;
  static const Duration themeAnimationDuration = MotionTokens.long;
  static const Curve themeAnimationCurve = MotionTokens.curveEmphasized;

  /// 构建浅色主题。
  static ThemeData lightTheme([
    AppThemePalette selectedPalette = AppThemePalette.teal,
  ]) {
    const palette = AppThemePalette.teal;
    final colorScheme = _colorScheme(Brightness.light);
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _scaffoldBackgroundColor(colorScheme, palette),
      extensions: [AppFinanceColors.fromPalette(selectedPalette)],
      useMaterial3: true,
      textTheme: _textTheme(colorScheme),
      inputDecorationTheme: _inputDecorationTheme(colorScheme, palette),
      snackBarTheme: _snackBarTheme(colorScheme, palette),
      segmentedButtonTheme: _segmentedButtonTheme(colorScheme, palette),
      chipTheme: _chipTheme(colorScheme, palette),
      appBarTheme: _appBarTheme(colorScheme, palette),
      switchTheme: _switchTheme(colorScheme, palette),
      checkboxTheme: _checkboxTheme(colorScheme, palette),
      floatingActionButtonTheme: _floatingActionButtonTheme(
        colorScheme,
        palette,
      ),
      listTileTheme: _listTileTheme(colorScheme, palette),
      popupMenuTheme: _popupMenuTheme(colorScheme, palette),
      progressIndicatorTheme: _progressIndicatorTheme(colorScheme, palette),
      dividerTheme: _dividerTheme(colorScheme, palette),
      dialogTheme: _dialogTheme(colorScheme, palette),
      bottomSheetTheme: _bottomSheetTheme(colorScheme, palette),
      datePickerTheme: _datePickerTheme(colorScheme, palette),
      timePickerTheme: _timePickerTheme(colorScheme, palette),
      dropdownMenuTheme: _dropdownMenuTheme(colorScheme, palette),
      menuTheme: _menuTheme(colorScheme, palette),
      menuButtonTheme: _menuButtonTheme(colorScheme, palette),
      textSelectionTheme: _textSelectionTheme(colorScheme, palette),
      scrollbarTheme: _scrollbarTheme(colorScheme, palette),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(surfaceRadius)),
        ),
      ),
      filledButtonTheme: _filledButtonTheme(colorScheme, palette),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme, palette),
      textButtonTheme: _textButtonTheme(colorScheme, palette),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme, palette),
      iconButtonTheme: _iconButtonTheme(colorScheme, palette),
    );
  }

  /// 构建深色主题。
  static ThemeData darkTheme([
    AppThemePalette selectedPalette = AppThemePalette.teal,
  ]) {
    const palette = AppThemePalette.teal;
    final colorScheme = _colorScheme(Brightness.dark);
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _scaffoldBackgroundColor(colorScheme, palette),
      extensions: [AppFinanceColors.fromPalette(selectedPalette)],
      useMaterial3: true,
      textTheme: _textTheme(colorScheme),
      inputDecorationTheme: _inputDecorationTheme(colorScheme, palette),
      snackBarTheme: _snackBarTheme(colorScheme, palette),
      segmentedButtonTheme: _segmentedButtonTheme(colorScheme, palette),
      chipTheme: _chipTheme(colorScheme, palette),
      appBarTheme: _appBarTheme(colorScheme, palette),
      switchTheme: _switchTheme(colorScheme, palette),
      checkboxTheme: _checkboxTheme(colorScheme, palette),
      floatingActionButtonTheme: _floatingActionButtonTheme(
        colorScheme,
        palette,
      ),
      listTileTheme: _listTileTheme(colorScheme, palette),
      popupMenuTheme: _popupMenuTheme(colorScheme, palette),
      progressIndicatorTheme: _progressIndicatorTheme(colorScheme, palette),
      dividerTheme: _dividerTheme(colorScheme, palette),
      dialogTheme: _dialogTheme(colorScheme, palette),
      bottomSheetTheme: _bottomSheetTheme(colorScheme, palette),
      datePickerTheme: _datePickerTheme(colorScheme, palette),
      timePickerTheme: _timePickerTheme(colorScheme, palette),
      dropdownMenuTheme: _dropdownMenuTheme(colorScheme, palette),
      menuTheme: _menuTheme(colorScheme, palette),
      menuButtonTheme: _menuButtonTheme(colorScheme, palette),
      textSelectionTheme: _textSelectionTheme(colorScheme, palette),
      scrollbarTheme: _scrollbarTheme(colorScheme, palette),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(surfaceRadius)),
        ),
      ),
      filledButtonTheme: _filledButtonTheme(colorScheme, palette),
      outlinedButtonTheme: _outlinedButtonTheme(colorScheme, palette),
      textButtonTheme: _textButtonTheme(colorScheme, palette),
      elevatedButtonTheme: _elevatedButtonTheme(colorScheme, palette),
      iconButtonTheme: _iconButtonTheme(colorScheme, palette),
    );
  }

  static AppFinanceColors financeColors(BuildContext context) {
    return Theme.of(context).extension<AppFinanceColors>() ??
        AppFinanceColors.fromPalette(AppThemePalette.teal);
  }

  static ColorScheme _colorScheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF45C7B8) : seedColor,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? const Color(0xFF153F3A)
          : const Color(0xFFD9F1EE),
      onPrimaryContainer: isDark
          ? const Color(0xFFB7F2EB)
          : const Color(0xFF0A4A43),
      surface: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      onSurface: isDark ? const Color(0xFFF5F5F7) : const Color(0xFF111111),
      surfaceContainerLowest: isDark ? Colors.black : const Color(0xFFF2F2F7),
      surfaceContainerLow: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceContainer: isDark
          ? const Color(0xFF242426)
          : const Color(0xFFF7F7F8),
      surfaceContainerHigh: isDark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFFF2F2F7),
      surfaceContainerHighest: isDark
          ? const Color(0xFF3A3A3C)
          : const Color(0xFFE5E5EA),
      onSurfaceVariant: isDark
          ? const Color(0xFFA1A1A6)
          : const Color(0xFF6E6E73),
      outline: isDark ? const Color(0xFF636366) : const Color(0xFF8E8E93),
      outlineVariant: isDark
          ? const Color(0xFF38383A)
          : const Color(0xFFC6C6C8),
      error: isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30),
    );
  }

  static Color _scaffoldBackgroundColor(
    ColorScheme colorScheme,
    AppThemePalette _,
  ) {
    return colorScheme.surfaceContainerLowest;
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    final baseColor = colorScheme.onSurface;
    final mutedColor = colorScheme.onSurfaceVariant;
    return TextTheme(
      displaySmall: TextStyle(
        color: baseColor,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        color: baseColor,
        fontSize: 27,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        color: baseColor,
        fontSize: 23,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        color: baseColor,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: baseColor,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: TextStyle(
        color: baseColor,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: baseColor,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.42,
      ),
      bodyMedium: TextStyle(
        color: baseColor,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.38,
      ),
      bodySmall: TextStyle(
        color: mutedColor,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.32,
      ),
      labelLarge: TextStyle(
        color: baseColor,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      labelMedium: TextStyle(
        color: mutedColor,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      labelSmall: TextStyle(
        color: mutedColor,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.12);
          }
          return palette.seedColor;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return colorScheme.onPrimary;
        }),
        overlayColor: WidgetStatePropertyAll(
          colorScheme.onPrimary.withValues(alpha: 0.12),
        ),
        elevation: const WidgetStatePropertyAll(0),
        enableFeedback: true,
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return palette.seedColor;
        }),
        side: WidgetStateProperty.resolveWith((states) {
          final disabled = states.contains(WidgetState.disabled);
          final focused = states.contains(WidgetState.focused);
          return BorderSide(
            color: disabled
                ? colorScheme.outlineVariant
                : focused
                ? colorScheme.primary
                : colorScheme.outlineVariant,
            width: focused ? 1.2 : 1,
          );
        }),
        overlayColor: WidgetStatePropertyAll(
          palette.seedColor.withValues(alpha: 0.08),
        ),
        backgroundColor: WidgetStatePropertyAll(colorScheme.surface),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return TextButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return palette.seedColor;
        }),
        overlayColor: WidgetStatePropertyAll(
          palette.seedColor.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return ElevatedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHigh,
        ),
        foregroundColor: WidgetStatePropertyAll(palette.seedColor),
        elevation: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return 0;
          }
          return 0;
        }),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    );
  }

  static IconButtonThemeData _iconButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: WidgetStatePropertyAll(const CircleBorder()),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return colorScheme.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.seedColor.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return palette.seedColor.withValues(alpha: 0.08);
          }
          return Colors.transparent;
        }),
        overlayColor: WidgetStatePropertyAll(
          palette.seedColor.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  static InputDecorationThemeData _inputDecorationTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final fillColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.62);
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );

    return InputDecorationThemeData(
      filled: true,
      fillColor: fillColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: baseBorder,
      enabledBorder: baseBorder,
      disabledBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
      ),
      errorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 1.2),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      ),
      helperStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.78),
      ),
      errorStyle: TextStyle(color: colorScheme.error),
      prefixIconColor: colorScheme.onSurfaceVariant,
      suffixIconColor: colorScheme.onSurfaceVariant,
    );
  }

  static SnackBarThemeData _snackBarTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.inverseSurface;
    final foregroundColor = isDark
        ? colorScheme.onSurface
        : colorScheme.onInverseSurface;

    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      showCloseIcon: true,
      backgroundColor: backgroundColor,
      closeIconColor: foregroundColor.withValues(alpha: 0.82),
      actionTextColor: colorScheme.primary,
      disabledActionTextColor: foregroundColor.withValues(alpha: 0.45),
      contentTextStyle: TextStyle(
        color: foregroundColor,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      actionOverflowThreshold: 0.42,
    );
  }

  static SegmentedButtonThemeData _segmentedButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final selectedFill = colorScheme.surface;
    final hoveredFill = colorScheme.surfaceContainerHigh;

    return SegmentedButtonThemeData(
      selectedIcon: const SizedBox.shrink(),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        side: const WidgetStatePropertyAll(BorderSide.none),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return selectedFill;
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return hoveredFill;
          }
          return colorScheme.surfaceContainerHighest;
        }),
        overlayColor: WidgetStatePropertyAll(
          colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  static ChipThemeData _chipTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final baseBackground = colorScheme.surfaceContainerHigh;
    final selectedBackground = isDark
        ? colorScheme.primaryContainer
        : colorScheme.primaryContainer.withValues(alpha: 0.72);
    final disabledBackground = Color.alphaBlend(
      colorScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
      colorScheme.surface,
    );

    return ChipThemeData(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return disabledBackground;
        }
        if (states.contains(WidgetState.selected)) {
          return selectedBackground;
        }
        return baseBackground;
      }),
      backgroundColor: baseBackground,
      selectedColor: selectedBackground,
      secondarySelectedColor: selectedBackground,
      disabledColor: disabledBackground,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      showCheckmark: false,
      checkmarkColor: colorScheme.primary,
      deleteIconColor: colorScheme.onSurfaceVariant,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      labelStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(size: 18, color: colorScheme.primary),
      brightness: colorScheme.brightness,
    );
  }

  static AppBarThemeData _appBarTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final foregroundColor = colorScheme.onSurface;
    return AppBarThemeData(
      backgroundColor: colorScheme.surfaceContainerLowest,
      foregroundColor: foregroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 16,
      toolbarHeight: 64,
      iconTheme: IconThemeData(color: foregroundColor, size: 22),
      actionsIconTheme: IconThemeData(color: colorScheme.primary, size: 22),
      titleTextStyle: TextStyle(
        color: foregroundColor,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      toolbarTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static SwitchThemeData _switchTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final inactiveTrack = Color.alphaBlend(
      colorScheme.onSurfaceVariant.withValues(alpha: 0.14),
      colorScheme.surfaceContainerHighest,
    );
    return SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.38);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return colorScheme.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary.withValues(alpha: 0.26);
        }
        return inactiveTrack;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary.withValues(alpha: 0.42);
        }
        return colorScheme.outlineVariant;
      }),
      trackOutlineWidth: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? 1.2 : 1;
      }),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.primary.withValues(alpha: 0.10),
      ),
      thumbIcon: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Icon(
            Icons.check_rounded,
            size: 14,
            color: colorScheme.surface,
          );
        }
        return null;
      }),
    );
  }

  static CheckboxThemeData _checkboxTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      splashRadius: 22,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: colorScheme.outlineVariant, width: 1.3),
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
      overlayColor: WidgetStatePropertyAll(
        colorScheme.primary.withValues(alpha: 0.10),
      ),
    );
  }

  static FloatingActionButtonThemeData _floatingActionButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return FloatingActionButtonThemeData(
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      focusColor: palette.seedColor.withValues(alpha: 0.16),
      hoverColor: palette.seedColor.withValues(alpha: 0.12),
      splashColor: colorScheme.onPrimary.withValues(alpha: 0.16),
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      shape: const CircleBorder(),
      enableFeedback: true,
      iconSize: 24,
      extendedIconLabelSpacing: 10,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600),
      mouseCursor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click;
      }),
    );
  }

  static ListTileThemeData _listTileTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return ListTileThemeData(
      dense: false,
      style: ListTileStyle.list,
      selectedColor: colorScheme.primary,
      iconColor: colorScheme.onSurfaceVariant,
      textColor: colorScheme.onSurface,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      leadingAndTrailingTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: const RoundedRectangleBorder(),
      horizontalTitleGap: 12,
      minVerticalPadding: 6,
      minLeadingWidth: 32,
      minTileHeight: 52,
      enableFeedback: true,
      visualDensity: VisualDensity.standard,
      mouseCursor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click;
      }),
    );
  }

  static PopupMenuThemeData _popupMenuTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return PopupMenuThemeData(
      color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      menuPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      textStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final disabled = states.contains(WidgetState.disabled);
        return TextStyle(
          color: disabled
              ? colorScheme.onSurface.withValues(alpha: 0.38)
              : colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        );
      }),
      iconColor: colorScheme.primary,
      iconSize: 20,
      enableFeedback: true,
      position: PopupMenuPosition.under,
      mouseCursor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click;
      }),
    );
  }

  static ProgressIndicatorThemeData _progressIndicatorTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final trackColor = colorScheme.surfaceContainerHighest;
    return ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: trackColor,
      circularTrackColor: trackColor,
      refreshBackgroundColor: colorScheme.surface,
      linearMinHeight: 4,
      strokeWidth: 3,
      strokeCap: StrokeCap.round,
      borderRadius: BorderRadius.circular(999),
      stopIndicatorColor: colorScheme.primary,
      stopIndicatorRadius: 3,
      trackGap: 3,
      circularTrackPadding: const EdgeInsets.all(1),
    );
  }

  static DividerThemeData _dividerTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return DividerThemeData(
      color: colorScheme.outlineVariant.withValues(
        alpha: colorScheme.brightness == Brightness.dark ? 0.76 : 0.68,
      ),
      space: 1,
      thickness: 0.6,
      radius: BorderRadius.circular(1),
    );
  }

  static DialogThemeData _dialogTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;

    return DialogThemeData(
      backgroundColor: backgroundColor,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.42 : 0.14),
      surfaceTintColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.42),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      iconColor: colorScheme.primary,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;

    return BottomSheetThemeData(
      backgroundColor: backgroundColor,
      modalBackgroundColor: backgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.36 : 0.12),
      modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.58 : 0.38),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      showDragHandle: true,
      dragHandleColor: colorScheme.outline.withValues(alpha: 0.52),
      dragHandleSize: const Size(36, 5),
      clipBehavior: Clip.antiAlias,
    );
  }

  static DatePickerThemeData _datePickerTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final surface = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;
    final selectedForeground = colorScheme.onPrimary;
    final stateOverlay = WidgetStatePropertyAll(
      colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
    );

    return DatePickerThemeData(
      backgroundColor: surface,
      elevation: 0,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.42 : 0.14),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      headerBackgroundColor: surface,
      headerForegroundColor: colorScheme.onSurface,
      headerHeadlineStyle: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      headerHelpStyle: const TextStyle(fontWeight: FontWeight.w500),
      weekdayStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      dayStyle: const TextStyle(fontWeight: FontWeight.w500),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.32);
        }
        if (states.contains(WidgetState.selected)) {
          return selectedForeground;
        }
        return colorScheme.onSurface;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused)) {
          return colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10);
        }
        return Colors.transparent;
      }),
      dayOverlayColor: stateOverlay,
      dayShape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      todayForegroundColor: WidgetStatePropertyAll(colorScheme.primary),
      todayBackgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      todayBorder: BorderSide(color: colorScheme.primary, width: 1.2),
      yearStyle: const TextStyle(fontWeight: FontWeight.w500),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return selectedForeground;
        }
        return colorScheme.onSurface;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return Colors.transparent;
      }),
      yearOverlayColor: stateOverlay,
      yearShape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerColor: colorScheme.outlineVariant,
      toggleButtonTextStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
      subHeaderForegroundColor: colorScheme.onSurfaceVariant,
      cancelButtonStyle: _textButtonTheme(colorScheme, palette).style,
      confirmButtonStyle: _filledButtonTheme(colorScheme, palette).style,
    );
  }

  static TimePickerThemeData _timePickerTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final surface = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;
    final controlFill = colorScheme.surfaceContainerHighest;

    return TimePickerThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      entryModeIconColor: colorScheme.primary,
      helpTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      hourMinuteColor: controlFill,
      hourMinuteTextColor: colorScheme.onSurface,
      hourMinuteTextStyle: const TextStyle(
        fontSize: 48,
        fontWeight: FontWeight.w700,
      ),
      hourMinuteShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      timeSelectorSeparatorColor: WidgetStatePropertyAll(
        colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
      ),
      timeSelectorSeparatorTextStyle: WidgetStatePropertyAll(
        TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      dayPeriodColor: controlFill,
      dayPeriodTextColor: colorScheme.primary,
      dayPeriodTextStyle: const TextStyle(fontWeight: FontWeight.w600),
      dayPeriodBorderSide: BorderSide(color: colorScheme.outlineVariant),
      dayPeriodShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      dialBackgroundColor: colorScheme.surfaceContainerHighest,
      dialHandColor: colorScheme.primary,
      dialTextColor: colorScheme.onSurface,
      dialTextStyle: const TextStyle(fontWeight: FontWeight.w500),
      cancelButtonStyle: _textButtonTheme(colorScheme, palette).style,
      confirmButtonStyle: _filledButtonTheme(colorScheme, palette).style,
    );
  }

  static DropdownMenuThemeData _dropdownMenuTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return DropdownMenuThemeData(
      textStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      inputDecorationTheme: _inputDecorationTheme(colorScheme, palette),
      menuStyle: _menuStyle(colorScheme, palette),
      disabledColor: colorScheme.onSurface.withValues(alpha: 0.38),
    );
  }

  static MenuThemeData _menuTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return MenuThemeData(style: _menuStyle(colorScheme, palette));
  }

  static MenuButtonThemeData _menuButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600),
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          return colorScheme.onSurface;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return colorScheme.primary.withValues(
              alpha: colorScheme.brightness == Brightness.dark ? 0.14 : 0.08,
            );
          }
          return Colors.transparent;
        }),
        overlayColor: WidgetStatePropertyAll(
          colorScheme.primary.withValues(alpha: 0.10),
        ),
        iconColor: WidgetStatePropertyAll(colorScheme.primary),
        enableFeedback: true,
      ),
    );
  }

  static MenuStyle _menuStyle(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surface;

    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(backgroundColor),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(
        Colors.black.withValues(alpha: isDark ? 0.34 : 0.12),
      ),
      elevation: const WidgetStatePropertyAll(6),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(180, 44)),
      maximumSize: const WidgetStatePropertyAll(Size(420, 420)),
      side: WidgetStatePropertyAll(
        BorderSide(color: colorScheme.outlineVariant),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      mouseCursor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click;
      }),
    );
  }

  static TextSelectionThemeData _textSelectionTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return TextSelectionThemeData(
      cursorColor: colorScheme.primary,
      selectionColor: colorScheme.primary.withValues(
        alpha: isDark ? 0.34 : 0.22,
      ),
      selectionHandleColor: colorScheme.primary,
    );
  }

  static ScrollbarThemeData _scrollbarTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    return ScrollbarThemeData(
      radius: const Radius.circular(999),
      interactive: true,
      crossAxisMargin: 3,
      mainAxisMargin: 8,
      minThumbLength: 48,
      thumbVisibility: const WidgetStatePropertyAll(false),
      trackVisibility: const WidgetStatePropertyAll(false),
      thickness: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged) ||
            states.contains(WidgetState.hovered)) {
          return 7;
        }
        return 4;
      }),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        final active =
            states.contains(WidgetState.dragged) ||
            states.contains(WidgetState.hovered);
        return colorScheme.primary.withValues(
          alpha: active ? (isDark ? 0.66 : 0.46) : (isDark ? 0.38 : 0.24),
        );
      }),
      trackColor: WidgetStatePropertyAll(
        colorScheme.primary.withValues(alpha: isDark ? 0.10 : 0.06),
      ),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

class AppFinanceColors extends ThemeExtension<AppFinanceColors> {
  const AppFinanceColors({
    required this.brand,
    required this.income,
    required this.expense,
    required this.asset,
    required this.warning,
  });

  final Color brand;
  final Color income;
  final Color expense;
  final Color asset;
  final Color warning;

  factory AppFinanceColors.fromPalette(AppThemePalette palette) {
    return AppFinanceColors(
      brand: AppTheme.seedColor,
      income: palette.incomeColor,
      expense: palette.expenseColor,
      asset: palette.assetColor,
      warning: palette.warningColor,
    );
  }

  @override
  AppFinanceColors copyWith({
    Color? brand,
    Color? income,
    Color? expense,
    Color? asset,
    Color? warning,
  }) {
    return AppFinanceColors(
      brand: brand ?? this.brand,
      income: income ?? this.income,
      expense: expense ?? this.expense,
      asset: asset ?? this.asset,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppFinanceColors lerp(ThemeExtension<AppFinanceColors>? other, double t) {
    if (other is! AppFinanceColors) {
      return this;
    }
    return AppFinanceColors(
      brand: Color.lerp(brand, other.brand, t)!,
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      asset: Color.lerp(asset, other.asset, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
