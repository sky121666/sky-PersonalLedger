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

    test('输入框视觉跟随主题模板', () {
      final theme = AppTheme.lightTheme(AppThemePalette.plasma);
      final inputTheme = theme.inputDecorationTheme;
      final focusedBorder = inputTheme.focusedBorder as OutlineInputBorder;

      expect(inputTheme.filled, isTrue);
      expect(inputTheme.fillColor, isNotNull);
      expect(focusedBorder.borderRadius, BorderRadius.circular(16));
      expect(focusedBorder.borderSide.color, AppThemePalette.plasma.seedColor);
      expect(focusedBorder.borderSide.width, 1.6);
    });

    test('深色输入框填充与浅色区分', () {
      final light = AppTheme.lightTheme(AppThemePalette.aurora);
      final dark = AppTheme.darkTheme(AppThemePalette.aurora);

      expect(
        light.inputDecorationTheme.fillColor,
        isNot(dark.inputDecorationTheme.fillColor),
      );
      expect(dark.inputDecorationTheme.filled, isTrue);
    });

    test('反馈浮层使用主题化高端样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.rose);
      final snackBarTheme = theme.snackBarTheme;

      expect(snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(snackBarTheme.showCloseIcon, isTrue);
      expect(snackBarTheme.elevation, 0);
      expect(snackBarTheme.actionTextColor, AppThemePalette.rose.seedColor);
      expect(snackBarTheme.shape, isA<RoundedRectangleBorder>());
      expect(
        snackBarTheme.insetPadding,
        const EdgeInsets.fromLTRB(16, 0, 16, 18),
      );
    });

    test('分段控件跟随主题模板并保留触控尺寸', () {
      final theme = AppTheme.lightTheme(AppThemePalette.cyan);
      final segmentedTheme = theme.segmentedButtonTheme;
      final selectedColor = segmentedTheme.style?.foregroundColor?.resolve({
        WidgetState.selected,
      });
      final minimumSize = segmentedTheme.style?.minimumSize?.resolve({});

      expect(selectedColor, AppThemePalette.cyan.seedColor);
      expect(minimumSize, const Size(48, 44));
      expect(segmentedTheme.selectedIcon, isA<Icon>());
      expect(
        segmentedTheme.style?.shape?.resolve({}),
        isA<RoundedRectangleBorder>(),
      );
    });

    test('主题模板标识唯一并覆盖高端色板', () {
      final ids = AppThemePalette.values.map((palette) => palette.id).toSet();
      final labels = AppThemePalette.values.map((palette) => palette.label);

      expect(ids.length, AppThemePalette.values.length);
      expect(labels, containsAll(['冰川青', '星云紫', '曜石玫瑰', '钛金灰']));
    });
  });
}
