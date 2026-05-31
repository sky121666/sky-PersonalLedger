import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/tags/data/tag_repository.dart';
import 'package:personal_ledger/features/tags/presentation/tag_page.dart';

void main() {
  group('TagPage', () {
    testWidgets('展示系统标签和自定义标签', (tester) async {
      final repository = _FakeTagRepository();
      await _pumpPage(tester, repository);

      expect(find.text('标签管理'), findsOneWidget);
      expect(find.text('工资收入'), findsOneWidget);
      expect(find.text('系统标签 · 使用 8 次'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
      expect(find.text('自定义标签 · 使用 2 次'), findsOneWidget);
    });

    testWidgets('标签头部和卡片使用分段入场动效', (tester) async {
      final repository = _FakeTagRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(3));
    });

    testWidgets('标签头部展示数量和使用信号', (tester) async {
      final repository = _FakeTagRepository();
      await _pumpPage(tester, repository);

      expect(find.text('标签颜色系统'), findsOneWidget);
      expect(find.text('自定义占比 50%'), findsOneWidget);
      expect(find.text('高频 工资收入 · 8 次'), findsOneWidget);
      expect(find.byKey(const ValueKey('tag-spectrum-panel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tag-governance-radar')),
        findsOneWidget,
      );
      expect(find.text('标签治理雷达'), findsOneWidget);
      expect(find.text('颜色覆盖'), findsOneWidget);
      expect(find.text('图标覆盖'), findsOneWidget);
      expect(find.text('自定义率'), findsOneWidget);
      expect(find.text('使用集中'), findsOneWidget);
      expect(find.text('高频标签 · 工资收入 · 8 次'), findsOneWidget);
    });

    testWidgets('新增标签时提交表单字段并刷新列表', (tester) async {
      final repository = _FakeTagRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增标签'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('tag-name')), '周末');
      await tester.enterText(find.byKey(const ValueKey('tag-icon')), 'star');
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, '周末');
      expect(repository.createCalls.single.icon, 'star');
      expect(find.text('周末'), findsOneWidget);
      expect(find.text('标签已保存'), findsOneWidget);
    });

    testWidgets('编辑标签时提交更新字段', (tester) async {
      final repository = _FakeTagRepository();
      await _pumpPage(tester, repository);

      final editButtons = find.byTooltip('编辑标签');
      await tester.tap(editButtons.last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('tag-name')), '旅行支出');
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'custom-1');
      expect(repository.updateCalls.single.$2.name, '旅行支出');
      expect(find.text('旅行支出'), findsOneWidget);
    });

    testWidgets('删除自定义标签前需要确认', (tester) async {
      final repository = _FakeTagRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('删除标签'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['custom-1']);
      expect(find.text('旅行'), findsNothing);
      expect(find.text('标签已删除'), findsOneWidget);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeTagRepository()..listErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('标签加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('旅行'), findsOneWidget);
      expect(repository.listCalls, 2);
    });

    testWidgets('没有标签时展示空状态', (tester) async {
      final repository = _FakeTagRepository()..tags = const [];
      await _pumpPage(tester, repository);

      expect(find.text('暂无标签'), findsOneWidget);
      expect(find.text('添加标签后，记账时可以快速标记交易来源或用途。'), findsOneWidget);
    });

    testWidgets('新增标签失败时展示错误且保留输入', (tester) async {
      final repository = _FakeTagRepository()..createError = '新增标签失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.text('新增标签'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('tag-name')), '周末');
      await tester.enterText(find.byKey(const ValueKey('tag-icon')), 'star');
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(find.textContaining('新增标签失败'), findsOneWidget);
      expect(find.text('标签已保存'), findsNothing);
      expect(find.text('周末'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
    });

    testWidgets('编辑标签失败时展示错误且保留原列表', (tester) async {
      final repository = _FakeTagRepository()..updateError = '编辑标签失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('编辑标签').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('tag-name')), '旅行支出');
      await tester.tap(find.byKey(const ValueKey('tag-save')));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(find.textContaining('编辑标签失败'), findsOneWidget);
      expect(find.text('标签已保存'), findsNothing);
      expect(find.text('旅行支出'), findsOneWidget);
      expect(find.text('旅行'), findsOneWidget);
    });

    testWidgets('删除标签失败时展示错误且保留标签', (tester) async {
      final repository = _FakeTagRepository()..deleteError = '删除标签失败';
      await _pumpPage(tester, repository);

      await tester.tap(find.byTooltip('删除标签'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['custom-1']);
      expect(find.textContaining('删除标签失败'), findsOneWidget);
      expect(find.text('标签已删除'), findsNothing);
      expect(find.text('旅行'), findsOneWidget);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeTagRepository repository,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [tagRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: TagPage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeTagRepository implements TagRepository {
  var tags = <TagItem>[
    const TagItem(
      id: 'system-1',
      userId: 1,
      name: '工资收入',
      color: '#22C55E',
      icon: 'wallet',
      isSystem: true,
      usedCount: 8,
    ),
    const TagItem(
      id: 'custom-1',
      userId: 1,
      name: '旅行',
      color: '#3B82F6',
      icon: 'label',
      usedCount: 2,
    ),
  ];

  final List<TagRequest> createCalls = [];
  final List<(String, TagRequest)> updateCalls = [];
  final List<String> deleteCalls = [];
  var listCalls = 0;
  var listErrors = 0;
  String? createError;
  String? updateError;
  String? deleteError;

  @override
  Future<TagItem> create(TagRequest request) async {
    createCalls.add(request);
    final error = createError;
    if (error != null) {
      throw StateError(error);
    }
    final tag = TagItem(
      id: 'custom-${tags.length + 1}',
      userId: 1,
      name: request.name,
      color: request.color,
      icon: request.icon,
    );
    tags = [...tags, tag];
    return tag;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    final error = deleteError;
    if (error != null) {
      throw StateError(error);
    }
    tags = tags.where((tag) => tag.id != id).toList();
  }

  @override
  Future<List<TagItem>> list() async {
    listCalls += 1;
    if (listErrors > 0) {
      listErrors -= 1;
      throw StateError('标签加载失败');
    }
    return tags;
  }

  @override
  Future<TagItem> update(String id, TagRequest request) async {
    updateCalls.add((id, request));
    final error = updateError;
    if (error != null) {
      throw StateError(error);
    }
    late TagItem updated;
    tags = [
      for (final tag in tags)
        if (tag.id == id)
          updated = TagItem(
            id: tag.id,
            userId: tag.userId,
            name: request.name,
            color: request.color,
            icon: request.icon,
            isSystem: tag.isSystem,
            usedCount: tag.usedCount,
          )
        else
          tag,
    ];
    return updated;
  }
}
