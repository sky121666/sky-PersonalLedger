import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('浅色页面背景保持中性一致', () {
      final teal = AppTheme.lightTheme(AppThemePalette.teal);
      final graphite = AppTheme.lightTheme(AppThemePalette.graphite);

      expect(teal.scaffoldBackgroundColor, graphite.scaffoldBackgroundColor);
      expect(
        graphite.scaffoldBackgroundColor,
        graphite.colorScheme.surfaceContainerLowest,
      );
    });

    test('深色页面背景保持中性一致', () {
      final teal = AppTheme.darkTheme(AppThemePalette.teal);
      final graphite = AppTheme.darkTheme(AppThemePalette.graphite);

      expect(teal.scaffoldBackgroundColor, graphite.scaffoldBackgroundColor);
      expect(
        graphite.scaffoldBackgroundColor,
        graphite.colorScheme.surfaceContainerLowest,
      );
    });

    test('财务语义色扩展来自主题模板', () {
      final theme = AppTheme.lightTheme(AppThemePalette.graphite);
      final financeColors = theme.extension<AppFinanceColors>();

      expect(financeColors?.brand, AppTheme.seedColor);
      expect(financeColors?.asset, AppThemePalette.graphite.assetColor);
      expect(financeColors?.income, AppThemePalette.graphite.incomeColor);
      expect(financeColors?.expense, AppThemePalette.graphite.expenseColor);
      expect(financeColors?.warning, AppThemePalette.graphite.warningColor);
    });

    test('旧主题标识会归并到可选主色', () {
      expect(AppThemePalette.fromId('aurora'), AppThemePalette.cyan);
      expect(AppThemePalette.fromId('obsidian'), AppThemePalette.plasma);
      expect(AppThemePalette.fromId('rose'), AppThemePalette.violet);
      expect(AppThemePalette.fromId('unknown'), AppThemePalette.teal);
    });

    test('主题切换动效使用统一高级节奏', () {
      expect(
        AppTheme.themeAnimationDuration,
        const Duration(milliseconds: 360),
      );
      expect(AppTheme.themeAnimationCurve, Curves.fastOutSlowIn);
    });

    test('输入框视觉跟随主题模板', () {
      final theme = AppTheme.lightTheme(AppThemePalette.plasma);
      final inputTheme = theme.inputDecorationTheme;
      final focusedBorder = inputTheme.focusedBorder as OutlineInputBorder;

      expect(inputTheme.filled, isTrue);
      expect(inputTheme.fillColor, isNotNull);
      expect(focusedBorder.borderRadius, BorderRadius.circular(12));
      expect(focusedBorder.borderSide.color, theme.colorScheme.primary);
      expect(focusedBorder.borderSide.width, 1.2);
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
      expect(snackBarTheme.actionTextColor, theme.colorScheme.primary);
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

      expect(selectedColor, theme.colorScheme.primary);
      expect(minimumSize, const Size(48, 44));
      expect(segmentedTheme.selectedIcon, isA<SizedBox>());
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

      expect(chipTheme.showCheckmark, isFalse);
      expect(chipTheme.checkmarkColor, theme.colorScheme.primary);
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
      expect(appBarTheme.actionsIconTheme?.color, theme.colorScheme.primary);
      expect(appBarTheme.titleTextStyle?.fontWeight, FontWeight.w700);
      expect(appBarTheme.toolbarHeight, 64);
    });

    test('开关和复选框使用主题化交互状态', () {
      final theme = AppTheme.lightTheme(AppThemePalette.violet);
      final switchTheme = theme.switchTheme;
      final checkboxTheme = theme.checkboxTheme;

      expect(
        switchTheme.thumbColor?.resolve({WidgetState.selected}),
        theme.colorScheme.primary,
      );
      expect(
        checkboxTheme.fillColor?.resolve({WidgetState.selected}),
        theme.colorScheme.primary,
      );
      expect(checkboxTheme.shape, isA<RoundedRectangleBorder>());
      expect(switchTheme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(checkboxTheme.materialTapTargetSize, MaterialTapTargetSize.padded);
    });

    test('浮动操作按钮使用主题化高级样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.plasma);
      final fabTheme = theme.floatingActionButtonTheme;

      expect(fabTheme.backgroundColor, theme.colorScheme.primary);
      expect(fabTheme.foregroundColor, theme.colorScheme.onPrimary);
      expect(fabTheme.enableFeedback, isTrue);
      expect(fabTheme.elevation, 0);
      expect(fabTheme.shape, isA<CircleBorder>());
      expect(fabTheme.extendedTextStyle?.fontWeight, FontWeight.w600);
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
        theme.colorScheme.primary,
      );
      expect(outlinedStyle?.minimumSize?.resolve({}), const Size(48, 48));
      expect(textStyle?.minimumSize?.resolve({}), const Size(44, 44));
      expect(elevatedStyle?.elevation?.resolve({}), 0);
      expect(iconStyle?.minimumSize?.resolve({}), const Size(48, 48));
      expect(
        iconStyle?.backgroundColor?.resolve({WidgetState.selected}),
        theme.colorScheme.primary.withValues(alpha: 0.14),
      );
    });

    test('列表和弹出菜单使用主题化信息层级', () {
      final theme = AppTheme.lightTheme(AppThemePalette.rose);
      final listTileTheme = theme.listTileTheme;
      final popupMenuTheme = theme.popupMenuTheme;

      expect(listTileTheme.selectedColor, theme.colorScheme.primary);
      expect(listTileTheme.minTileHeight, 52);
      expect(listTileTheme.shape, isA<RoundedRectangleBorder>());
      expect(listTileTheme.tileColor, isNull);
      expect(listTileTheme.selectedTileColor, isNull);
      expect(popupMenuTheme.iconColor, theme.colorScheme.primary);
      expect(popupMenuTheme.position, PopupMenuPosition.under);
      expect(popupMenuTheme.surfaceTintColor, Colors.transparent);
      expect(popupMenuTheme.shape, isA<RoundedRectangleBorder>());
    });

    test('进度反馈和分隔线使用主题化数据质感', () {
      final theme = AppTheme.lightTheme(AppThemePalette.aurora);
      final progressTheme = theme.progressIndicatorTheme;
      final dividerTheme = theme.dividerTheme;

      expect(progressTheme.color, theme.colorScheme.primary);
      expect(progressTheme.linearMinHeight, 4);
      expect(progressTheme.strokeWidth, 3);
      expect(progressTheme.strokeCap, StrokeCap.round);
      expect(progressTheme.borderRadius, BorderRadius.circular(999));
      expect(dividerTheme.thickness, 0.6);
      expect(dividerTheme.space, 1);
      expect(dividerTheme.radius, BorderRadius.circular(1));
    });

    test('对话框和底部弹层使用主题化高级表面', () {
      final theme = AppTheme.darkTheme(AppThemePalette.plasma);
      final dialogTheme = theme.dialogTheme;
      final bottomSheetTheme = theme.bottomSheetTheme;

      expect(dialogTheme.backgroundColor, isNotNull);
      expect(dialogTheme.elevation, 0);
      expect(dialogTheme.surfaceTintColor, Colors.transparent);
      expect(dialogTheme.shape, isA<RoundedRectangleBorder>());
      expect(dialogTheme.iconColor, theme.colorScheme.primary);
      expect(dialogTheme.titleTextStyle?.fontWeight, FontWeight.w700);
      expect(dialogTheme.clipBehavior, Clip.antiAlias);

      expect(bottomSheetTheme.backgroundColor, isNotNull);
      expect(bottomSheetTheme.modalBackgroundColor, isNotNull);
      expect(bottomSheetTheme.elevation, 0);
      expect(bottomSheetTheme.modalElevation, 0);
      expect(bottomSheetTheme.surfaceTintColor, Colors.transparent);
      expect(bottomSheetTheme.shape, isA<RoundedRectangleBorder>());
      expect(bottomSheetTheme.showDragHandle, isTrue);
      expect(bottomSheetTheme.dragHandleSize, const Size(36, 5));
      expect(bottomSheetTheme.clipBehavior, Clip.antiAlias);
    });

    test('日期和时间选择器使用主题化数据录入样式', () {
      final theme = AppTheme.lightTheme(AppThemePalette.cyan);
      final datePickerTheme = theme.datePickerTheme;
      final timePickerTheme = theme.timePickerTheme;

      expect(datePickerTheme.backgroundColor, isNotNull);
      expect(datePickerTheme.elevation, 0);
      expect(datePickerTheme.surfaceTintColor, Colors.transparent);
      expect(datePickerTheme.headerBackgroundColor, theme.colorScheme.surface);
      expect(datePickerTheme.headerHeadlineStyle?.fontWeight, FontWeight.w700);
      expect(
        datePickerTheme.dayShape?.resolve({}),
        isA<RoundedRectangleBorder>(),
      );
      expect(
        datePickerTheme.dayBackgroundColor?.resolve({WidgetState.selected}),
        theme.colorScheme.primary,
      );
      expect(
        datePickerTheme.todayForegroundColor?.resolve({}),
        theme.colorScheme.primary,
      );
      expect(datePickerTheme.confirmButtonStyle, isNotNull);

      expect(timePickerTheme.backgroundColor, isNotNull);
      expect(timePickerTheme.elevation, 0);
      expect(timePickerTheme.shape, isA<RoundedRectangleBorder>());
      expect(timePickerTheme.entryModeIconColor, theme.colorScheme.primary);
      expect(timePickerTheme.hourMinuteTextColor, theme.colorScheme.onSurface);
      expect(timePickerTheme.dialHandColor, theme.colorScheme.primary);
      expect(timePickerTheme.dayPeriodShape, isA<RoundedRectangleBorder>());
      expect(timePickerTheme.confirmButtonStyle, isNotNull);
    });

    test('下拉菜单和菜单项使用主题化选择器样式', () {
      final theme = AppTheme.darkTheme(AppThemePalette.aurora);
      final dropdownTheme = theme.dropdownMenuTheme;
      final menuTheme = theme.menuTheme;
      final menuButtonTheme = theme.menuButtonTheme;

      expect(dropdownTheme.textStyle?.fontWeight, FontWeight.w500);
      expect(dropdownTheme.inputDecorationTheme?.filled, isTrue);
      expect(dropdownTheme.menuStyle, isNotNull);
      expect(dropdownTheme.disabledColor, isNotNull);

      final menuStyle = menuTheme.style;
      expect(menuStyle?.backgroundColor?.resolve({}), isNotNull);
      expect(menuStyle?.surfaceTintColor?.resolve({}), Colors.transparent);
      expect(menuStyle?.elevation?.resolve({}), 6);
      expect(menuStyle?.shape?.resolve({}), isA<RoundedRectangleBorder>());
      expect(menuStyle?.minimumSize?.resolve({}), const Size(180, 44));

      final buttonStyle = menuButtonTheme.style;
      expect(buttonStyle?.minimumSize?.resolve({}), const Size(44, 44));
      expect(buttonStyle?.iconColor?.resolve({}), theme.colorScheme.primary);
      expect(buttonStyle?.enableFeedback, isTrue);
    });

    test('文本选择和滚动条使用主题化细节', () {
      final theme = AppTheme.lightTheme(AppThemePalette.rose);
      final textSelectionTheme = theme.textSelectionTheme;
      final scrollbarTheme = theme.scrollbarTheme;

      expect(textSelectionTheme.cursorColor, theme.colorScheme.primary);
      expect(
        textSelectionTheme.selectionHandleColor,
        theme.colorScheme.primary,
      );
      expect(textSelectionTheme.selectionColor, isNotNull);

      expect(scrollbarTheme.radius, const Radius.circular(999));
      expect(scrollbarTheme.interactive, isTrue);
      expect(scrollbarTheme.thickness?.resolve({}), 4);
      expect(scrollbarTheme.thickness?.resolve({WidgetState.hovered}), 7);
      expect(scrollbarTheme.thumbColor?.resolve({}), isNotNull);
      expect(scrollbarTheme.trackVisibility?.resolve({}), isFalse);
      expect(scrollbarTheme.minThumbLength, 48);
    });

    test('主题设置只暴露少量主色', () {
      final ids = AppThemePalette.values.map((palette) => palette.id).toSet();
      final labels = AppThemePalette.selectableValues.map(
        (palette) => palette.label,
      );

      expect(ids.length, AppThemePalette.values.length);
      expect(labels, ['绿色', '蓝色', '青色', '紫色', '橙色', '灰色']);
      expect(AppThemePalette.selectableValues.length, 6);
    });
  });
}
