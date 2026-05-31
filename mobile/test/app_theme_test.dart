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

    test('筛选标签使用主题色状态样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.emerald);
      final chipTheme = theme.chipTheme;
      final selectedColor = chipTheme.color?.resolve({WidgetState.selected});
      final disabledColor = chipTheme.color?.resolve({WidgetState.disabled});

      expect(chipTheme.showCheckmark, isTrue);
      expect(chipTheme.checkmarkColor, AppThemePalette.emerald.seedColor);
      expect(chipTheme.elevation, 0);
      expect(chipTheme.pressElevation, 0);
      expect(chipTheme.shape, isA<RoundedRectangleBorder>());
      expect(selectedColor, chipTheme.selectedColor);
      expect(disabledColor, chipTheme.disabledColor);
    });

    test('顶部导航栏使用轻量主题化样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.obsidian);
      final appBarTheme = theme.appBarTheme;

      expect(appBarTheme.elevation, 0);
      expect(appBarTheme.scrolledUnderElevation, 0);
      expect(appBarTheme.surfaceTintColor, Colors.transparent);
      expect(
        appBarTheme.actionsIconTheme?.color,
        AppThemePalette.obsidian.seedColor,
      );
      expect(appBarTheme.titleTextStyle?.fontWeight, FontWeight.w900);
      expect(appBarTheme.toolbarHeight, 60);
    });

    test('开关和复选框使用主题化交互状态', () {
      final theme = AppTheme.lightTheme(AppThemePalette.violet);
      final switchTheme = theme.switchTheme;
      final checkboxTheme = theme.checkboxTheme;

      expect(
        switchTheme.thumbColor?.resolve({WidgetState.selected}),
        AppThemePalette.violet.seedColor,
      );
      expect(
        checkboxTheme.fillColor?.resolve({WidgetState.selected}),
        AppThemePalette.violet.seedColor,
      );
      expect(checkboxTheme.shape, isA<RoundedRectangleBorder>());
      expect(switchTheme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(checkboxTheme.materialTapTargetSize, MaterialTapTargetSize.padded);
    });

    test('浮动操作按钮使用主题化高级样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.plasma);
      final fabTheme = theme.floatingActionButtonTheme;

      expect(fabTheme.backgroundColor, AppThemePalette.plasma.seedColor);
      expect(fabTheme.foregroundColor, theme.colorScheme.onPrimary);
      expect(fabTheme.enableFeedback, isTrue);
      expect(fabTheme.elevation, 4);
      expect(fabTheme.shape, isA<RoundedRectangleBorder>());
      expect(fabTheme.extendedTextStyle?.fontWeight, FontWeight.w900);
    });

    test('按钮体系使用统一触控尺寸和主题色状态', () {
      final theme = AppTheme.lightTheme(AppThemePalette.cyan);
      final filledStyle = theme.filledButtonTheme.style;
      final outlinedStyle = theme.outlinedButtonTheme.style;
      final textStyle = theme.textButtonTheme.style;
      final elevatedStyle = theme.elevatedButtonTheme.style;
      final iconStyle = theme.iconButtonTheme.style;

      expect(filledStyle?.minimumSize?.resolve({}), const Size(48, 48));
      expect(
        filledStyle?.backgroundColor?.resolve({}),
        AppThemePalette.cyan.seedColor,
      );
      expect(outlinedStyle?.minimumSize?.resolve({}), const Size(48, 48));
      expect(textStyle?.minimumSize?.resolve({}), const Size(44, 44));
      expect(elevatedStyle?.elevation?.resolve({}), 2);
      expect(iconStyle?.minimumSize?.resolve({}), const Size(48, 48));
      expect(
        iconStyle?.backgroundColor?.resolve({WidgetState.selected}),
        AppThemePalette.cyan.seedColor.withValues(alpha: 0.14),
      );
    });

    test('列表和弹出菜单使用主题化信息层级', () {
      final theme = AppTheme.lightTheme(AppThemePalette.rose);
      final listTileTheme = theme.listTileTheme;
      final popupMenuTheme = theme.popupMenuTheme;

      expect(listTileTheme.selectedColor, AppThemePalette.rose.seedColor);
      expect(listTileTheme.minTileHeight, 56);
      expect(listTileTheme.shape, isA<RoundedRectangleBorder>());
      expect(listTileTheme.tileColor, isNull);
      expect(listTileTheme.selectedTileColor, isNull);
      expect(popupMenuTheme.iconColor, AppThemePalette.rose.seedColor);
      expect(popupMenuTheme.position, PopupMenuPosition.under);
      expect(popupMenuTheme.surfaceTintColor, Colors.transparent);
      expect(popupMenuTheme.shape, isA<RoundedRectangleBorder>());
    });

    test('进度反馈和分隔线使用主题化数据质感', () {
      final theme = AppTheme.lightTheme(AppThemePalette.aurora);
      final progressTheme = theme.progressIndicatorTheme;
      final dividerTheme = theme.dividerTheme;

      expect(progressTheme.color, AppThemePalette.aurora.seedColor);
      expect(progressTheme.linearMinHeight, 7);
      expect(progressTheme.strokeWidth, 3);
      expect(progressTheme.strokeCap, StrokeCap.round);
      expect(progressTheme.borderRadius, BorderRadius.circular(999));
      expect(dividerTheme.thickness, 1);
      expect(dividerTheme.space, 1);
      expect(dividerTheme.radius, BorderRadius.circular(999));
    });

    test('对话框和底部弹层使用主题化高级表面', () {
      final theme = AppTheme.darkTheme(AppThemePalette.plasma);
      final dialogTheme = theme.dialogTheme;
      final bottomSheetTheme = theme.bottomSheetTheme;

      expect(dialogTheme.backgroundColor, isNotNull);
      expect(dialogTheme.elevation, 0);
      expect(dialogTheme.surfaceTintColor, Colors.transparent);
      expect(dialogTheme.shape, isA<RoundedRectangleBorder>());
      expect(dialogTheme.iconColor, AppThemePalette.plasma.seedColor);
      expect(dialogTheme.titleTextStyle?.fontWeight, FontWeight.w900);
      expect(dialogTheme.clipBehavior, Clip.antiAlias);

      expect(bottomSheetTheme.backgroundColor, isNotNull);
      expect(bottomSheetTheme.modalBackgroundColor, isNotNull);
      expect(bottomSheetTheme.elevation, 0);
      expect(bottomSheetTheme.modalElevation, 0);
      expect(bottomSheetTheme.surfaceTintColor, Colors.transparent);
      expect(bottomSheetTheme.shape, isA<RoundedRectangleBorder>());
      expect(bottomSheetTheme.showDragHandle, isTrue);
      expect(bottomSheetTheme.dragHandleSize, const Size(44, 5));
      expect(bottomSheetTheme.clipBehavior, Clip.antiAlias);
    });

    test('日期和时间选择器使用主题化数据录入样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.cyan);
      final datePickerTheme = theme.datePickerTheme;
      final timePickerTheme = theme.timePickerTheme;

      expect(datePickerTheme.backgroundColor, isNotNull);
      expect(datePickerTheme.elevation, 0);
      expect(datePickerTheme.surfaceTintColor, Colors.transparent);
      expect(
        datePickerTheme.headerBackgroundColor,
        AppThemePalette.cyan.seedColor,
      );
      expect(datePickerTheme.headerHeadlineStyle?.fontWeight, FontWeight.w900);
      expect(
        datePickerTheme.dayShape?.resolve({}),
        isA<RoundedRectangleBorder>(),
      );
      expect(
        datePickerTheme.dayBackgroundColor?.resolve({WidgetState.selected}),
        AppThemePalette.cyan.seedColor,
      );
      expect(
        datePickerTheme.todayForegroundColor?.resolve({}),
        AppThemePalette.cyan.seedColor,
      );
      expect(datePickerTheme.confirmButtonStyle, isNotNull);

      expect(timePickerTheme.backgroundColor, isNotNull);
      expect(timePickerTheme.elevation, 0);
      expect(timePickerTheme.shape, isA<RoundedRectangleBorder>());
      expect(
        timePickerTheme.entryModeIconColor,
        AppThemePalette.cyan.seedColor,
      );
      expect(
        timePickerTheme.hourMinuteTextColor,
        AppThemePalette.cyan.seedColor,
      );
      expect(timePickerTheme.dialHandColor, AppThemePalette.cyan.seedColor);
      expect(timePickerTheme.dayPeriodShape, isA<RoundedRectangleBorder>());
      expect(timePickerTheme.confirmButtonStyle, isNotNull);
    });

    test('主题模板标识唯一并覆盖高端色板', () {
      final ids = AppThemePalette.values.map((palette) => palette.id).toSet();
      final labels = AppThemePalette.values.map((palette) => palette.label);

      expect(ids.length, AppThemePalette.values.length);
      expect(labels, containsAll(['冰川青', '星云紫', '曜石玫瑰', '钛金灰']));
    });
  });
}
