import 'package:flutter/material.dart';

enum AppThemePalette {
  teal(
    id: 'teal',
    label: '静谧墨绿',
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
    description: '更温暖，但保留金融产品克制感。',
    seedColor: Color(0xFFB45309),
    incomeColor: Color(0xFF15803D),
    expenseColor: Color(0xFFB91C1C),
    assetColor: Color(0xFF2563EB),
    warningColor: Color(0xFFF59E0B),
  );

  const AppThemePalette({
    required this.id,
    required this.label,
    required this.description,
    required this.seedColor,
    required this.incomeColor,
    required this.expenseColor,
    required this.assetColor,
    required this.warningColor,
  });

  final String id;
  final String label;
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
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      extensions: [AppFinanceColors.fromPalette(palette)],
      useMaterial3: true,
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
      scaffoldBackgroundColor: const Color(0xFF020617),
      extensions: [AppFinanceColors.fromPalette(palette)],
      useMaterial3: true,
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
