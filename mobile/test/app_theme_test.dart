import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('浅色页面背景跟随主题模板', () {
      final teal = AppTheme.lightTheme(AppThemePalette.teal);
      final graphite = AppTheme.lightTheme(AppThemePalette.graphite);

      expect(
        teal.scaffoldBackgroundColor,
        isNot(graphite.scaffoldBackgroundColor),
      );
      expect(
        graphite.scaffoldBackgroundColor,
        Color.alphaBlend(
          AppThemePalette.graphite.seedColor.withValues(alpha: 0.05),
          graphite.colorScheme.surfaceContainerLowest,
        ),
      );
    });

    test('深色页面背景跟随主题模板', () {
      final teal = AppTheme.darkTheme(AppThemePalette.teal);
      final graphite = AppTheme.darkTheme(AppThemePalette.graphite);

      expect(
        teal.scaffoldBackgroundColor,
        isNot(graphite.scaffoldBackgroundColor),
      );
      expect(
        graphite.scaffoldBackgroundColor,
        Color.alphaBlend(
          AppThemePalette.graphite.seedColor.withValues(alpha: 0.10),
          graphite.colorScheme.surface,
        ),
      );
    });

    test('财务语义色扩展来自主题模板', () {
      final theme = AppTheme.lightTheme(AppThemePalette.graphite);
      final financeColors = theme.extension<AppFinanceColors>();

      expect(financeColors?.asset, AppThemePalette.graphite.assetColor);
      expect(financeColors?.income, AppThemePalette.graphite.incomeColor);
      expect(financeColors?.expense, AppThemePalette.graphite.expenseColor);
      expect(financeColors?.warning, AppThemePalette.graphite.warningColor);
    });

    test('主题模板标识唯一并覆盖高端色板', () {
      final ids = AppThemePalette.values.map((palette) => palette.id).toSet();
      final labels = AppThemePalette.values.map((palette) => palette.label);

      expect(ids.length, AppThemePalette.values.length);
      expect(labels, containsAll(['冰川青', '星云紫', '曜石玫瑰', '钛金灰']));
    });
  });
}
