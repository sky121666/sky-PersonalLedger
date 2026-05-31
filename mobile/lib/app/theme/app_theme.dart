import 'package:flutter/material.dart';

enum AppThemePalette {
  teal(
    id: 'teal',
    label: '静谧墨绿',
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
    label: '石墨蓝',
    signature: '冷静仪表',
    description: '更冷静的高级仪表盘气质。',
    seedColor: Color(0xFF334155),
    incomeColor: Color(0xFF10B981),
    expenseColor: Color(0xFFEF4444),
    assetColor: Color(0xFF0EA5E9),
    warningColor: Color(0xFFEAB308),
  ),
  indigo(
    id: 'indigo',
    label: '深海靛蓝',
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
    label: '翡翠绿',
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
    label: '琥珀金',
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
    label: '冰川青',
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
    label: '星云紫',
    signature: '高端设备',
    description: '更强 AI 和高端设备感。',
    seedColor: Color(0xFF7C3AED),
    incomeColor: Color(0xFF10B981),
    expenseColor: Color(0xFFFB7185),
    assetColor: Color(0xFF38BDF8),
    warningColor: Color(0xFFF59E0B),
  ),
  rose(
    id: 'rose',
    label: '曜石玫瑰',
    signature: '精致暗调',
    description: '更精致的暗色高级感。',
    seedColor: Color(0xFFBE185D),
    incomeColor: Color(0xFF22C55E),
    expenseColor: Color(0xFFE11D48),
    assetColor: Color(0xFF6366F1),
    warningColor: Color(0xFFF59E0B),
  ),
  slate(
    id: 'slate',
    label: '钛金灰',
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
    label: '极光青',
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
    label: '黑曜蓝',
    signature: '旗舰暗色',
    description: '深蓝底色与高亮资产色，适合夜间重度使用。',
    seedColor: Color(0xFF1E3A8A),
    incomeColor: Color(0xFF34D399),
    expenseColor: Color(0xFFF87171),
    assetColor: Color(0xFF60A5FA),
    warningColor: Color(0xFFFBBF24),
  ),
  plasma(
    id: 'plasma',
    label: '电浆蓝',
    signature: '动效先锋',
    description: '蓝紫主轴搭配明亮资产色，更适合高动效界面。',
    seedColor: Color(0xFF2563EB),
    incomeColor: Color(0xFF22C55E),
    expenseColor: Color(0xFFEC4899),
    assetColor: Color(0xFF06B6D4),
    warningColor: Color(0xFFF59E0B),
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

  static AppThemePalette fromId(String? id) {
    return AppThemePalette.values.firstWhere(
      (palette) => palette.id == id,
      orElse: () => AppThemePalette.teal,
    );
  }
}

class AppTheme {
  static const Color seedColor = Color(0xFF0F766E);
  static const Color incomeColor = Color(0xFF059669);
  static const Color expenseColor = Color(0xFFDC2626);
  static const Color assetColor = Color(0xFF2563EB);
  static const Color warningColor = Color(0xFFF59E0B);
  static const double surfaceRadius = 20;

  /// 构建浅色主题。
  static ThemeData lightTheme([
    AppThemePalette palette = AppThemePalette.teal,
  ]) {
    final colorScheme = ColorScheme.fromSeed(seedColor: palette.seedColor);
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _scaffoldBackgroundColor(colorScheme, palette),
      extensions: [AppFinanceColors.fromPalette(palette)],
      useMaterial3: true,
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }

  /// 构建深色主题。
  static ThemeData darkTheme([AppThemePalette palette = AppThemePalette.teal]) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.seedColor,
      brightness: Brightness.dark,
    );
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _scaffoldBackgroundColor(colorScheme, palette),
      extensions: [AppFinanceColors.fromPalette(palette)],
      useMaterial3: true,
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }

  static AppFinanceColors financeColors(BuildContext context) {
    return Theme.of(context).extension<AppFinanceColors>() ??
        AppFinanceColors.fromPalette(AppThemePalette.teal);
  }

  static Color _scaffoldBackgroundColor(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final tintAlpha = colorScheme.brightness == Brightness.dark ? 0.10 : 0.05;
    final baseColor = colorScheme.brightness == Brightness.dark
        ? colorScheme.surface
        : colorScheme.surfaceContainerLowest;
    return Color.alphaBlend(
      palette.seedColor.withValues(alpha: tintAlpha),
      baseColor,
    );
  }

  static InputDecorationThemeData _inputDecorationTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final fillAlpha = isDark ? 0.12 : 0.055;
    final borderAlpha = isDark ? 0.28 : 0.16;
    final fillColor = Color.alphaBlend(
      palette.seedColor.withValues(alpha: fillAlpha),
      colorScheme.surfaceContainerHighest,
    );
    final enabledColor = Color.alphaBlend(
      palette.seedColor.withValues(alpha: borderAlpha),
      colorScheme.outlineVariant,
    );
    final baseBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: enabledColor),
    );

    return InputDecorationThemeData(
      filled: true,
      fillColor: fillColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: baseBorder,
      enabledBorder: baseBorder,
      disabledBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: palette.seedColor, width: 1.6),
      ),
      errorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: baseBorder.copyWith(
        borderSide: BorderSide(color: colorScheme.error, width: 1.6),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      floatingLabelStyle: TextStyle(
        color: palette.seedColor,
        fontWeight: FontWeight.w600,
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
    final backgroundColor = Color.alphaBlend(
      palette.seedColor.withValues(alpha: isDark ? 0.18 : 0.08),
      isDark ? colorScheme.surfaceContainerHigh : colorScheme.inverseSurface,
    );
    final foregroundColor = isDark
        ? colorScheme.onSurface
        : colorScheme.onInverseSurface;

    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      showCloseIcon: true,
      backgroundColor: backgroundColor,
      closeIconColor: foregroundColor.withValues(alpha: 0.82),
      actionTextColor: palette.seedColor,
      disabledActionTextColor: foregroundColor.withValues(alpha: 0.45),
      contentTextStyle: TextStyle(
        color: foregroundColor,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      actionOverflowThreshold: 0.42,
    );
  }

  static SegmentedButtonThemeData _segmentedButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final selectedFill = Color.alphaBlend(
      palette.seedColor.withValues(
        alpha: colorScheme.brightness == Brightness.dark ? 0.24 : 0.12,
      ),
      colorScheme.surface,
    );
    final hoveredFill = Color.alphaBlend(
      palette.seedColor.withValues(
        alpha: colorScheme.brightness == Brightness.dark ? 0.14 : 0.07,
      ),
      colorScheme.surface,
    );

    return SegmentedButtonThemeData(
      selectedIcon: const Icon(Icons.check_rounded, size: 18),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 44)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w800),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          final focused = states.contains(WidgetState.focused);
          return BorderSide(
            color: selected || focused
                ? palette.seedColor
                : colorScheme.outlineVariant,
            width: selected || focused ? 1.4 : 1,
          );
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colorScheme.onSurface.withValues(alpha: 0.38);
          }
          if (states.contains(WidgetState.selected)) {
            return palette.seedColor;
          }
          return colorScheme.onSurfaceVariant;
        }),
        iconColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return palette.seedColor;
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
          return colorScheme.surface;
        }),
        overlayColor: WidgetStatePropertyAll(
          palette.seedColor.withValues(alpha: 0.08),
        ),
      ),
    );
  }

  static ChipThemeData _chipTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final isDark = colorScheme.brightness == Brightness.dark;
    final baseBackground = Color.alphaBlend(
      palette.seedColor.withValues(alpha: isDark ? 0.10 : 0.045),
      colorScheme.surfaceContainerHighest,
    );
    final selectedBackground = Color.alphaBlend(
      palette.seedColor.withValues(alpha: isDark ? 0.24 : 0.13),
      colorScheme.surface,
    );
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
      showCheckmark: true,
      checkmarkColor: palette.seedColor,
      deleteIconColor: colorScheme.onSurfaceVariant,
      side: BorderSide(color: palette.seedColor.withValues(alpha: 0.16)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      labelStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
      secondaryLabelStyle: TextStyle(
        color: palette.seedColor,
        fontWeight: FontWeight.w900,
      ),
      iconTheme: IconThemeData(size: 18, color: palette.seedColor),
      brightness: colorScheme.brightness,
    );
  }

  static AppBarThemeData _appBarTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    final foregroundColor = colorScheme.onSurface;
    final isDark = colorScheme.brightness == Brightness.dark;
    final backgroundColor = Color.alphaBlend(
      palette.seedColor.withValues(alpha: isDark ? 0.10 : 0.045),
      colorScheme.surface,
    );

    return AppBarThemeData(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 16,
      toolbarHeight: 60,
      iconTheme: IconThemeData(color: foregroundColor, size: 22),
      actionsIconTheme: IconThemeData(color: palette.seedColor, size: 22),
      titleTextStyle: TextStyle(
        color: foregroundColor,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
      toolbarTextStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 14,
        fontWeight: FontWeight.w700,
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
          return palette.seedColor;
        }
        return colorScheme.surface;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.selected)) {
          return palette.seedColor.withValues(alpha: 0.26);
        }
        return inactiveTrack;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return palette.seedColor.withValues(alpha: 0.42);
        }
        return colorScheme.outlineVariant;
      }),
      trackOutlineWidth: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? 1.2 : 1;
      }),
      overlayColor: WidgetStatePropertyAll(
        palette.seedColor.withValues(alpha: 0.10),
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
          return palette.seedColor;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll(colorScheme.onPrimary),
      overlayColor: WidgetStatePropertyAll(
        palette.seedColor.withValues(alpha: 0.10),
      ),
    );
  }

  static FloatingActionButtonThemeData _floatingActionButtonTheme(
    ColorScheme colorScheme,
    AppThemePalette palette,
  ) {
    return FloatingActionButtonThemeData(
      backgroundColor: palette.seedColor,
      foregroundColor: colorScheme.onPrimary,
      focusColor: palette.seedColor.withValues(alpha: 0.16),
      hoverColor: palette.seedColor.withValues(alpha: 0.12),
      splashColor: colorScheme.onPrimary.withValues(alpha: 0.16),
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 6,
      highlightElevation: 8,
      disabledElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      enableFeedback: true,
      iconSize: 24,
      extendedIconLabelSpacing: 10,
      extendedPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w900),
      mouseCursor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.disabled)
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click;
      }),
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
      brand: palette.seedColor,
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
