import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/attachments/data/attachment_picker_service.dart';
import 'package:personal_ledger/features/attachments/data/attachment_repository.dart';
import 'package:personal_ledger/features/reminders/data/reminder_repository.dart';
import 'package:personal_ledger/features/reminders/presentation/reminder_page.dart';

void main() {
  group('ReminderPage', () {
    testWidgets('展示上岸进度和进行中的负债提醒', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      expect(find.text('负债'), findsOneWidget);
      expect(find.text('还款进度'), findsOneWidget);
      expect(find.text('上岸进度'), findsNothing);
      expect(find.text('稳步推进'), findsNothing);
      expect(find.text('房贷'), findsAtLeastNWidgets(1));
      expect(find.text('待还'), findsAtLeastNWidgets(1));
      expect(find.text('¥80,000.00'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('reminder-card-reminder-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reminder-debt-panel-reminder-1')),
        findsNothing,
      );
      expect(find.textContaining('本金'), findsOneWidget);
      expect(find.textContaining('月供'), findsNothing);
      expect(find.text('贷款账户'), findsNothing);

      expect(
        find.byKey(const ValueKey('repayment-rhythm-radar')),
        findsNothing,
      );
      expect(find.text('还款节奏雷达'), findsNothing);
      expect(
        find.byKey(const ValueKey('reminder-evidence-rail')),
        findsNothing,
      );
      expect(find.text('证据覆盖 100%'), findsNothing);
      expect(
        find.byKey(const ValueKey('reminder-guardrail-matrix-reminder-1')),
        findsNothing,
      );
      expect(find.text('还款守护矩阵'), findsNothing);
      expect(find.text('凭证状态'), findsNothing);
    });

    testWidgets('记一笔默认折叠展示关键字段', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      expect(
        find.byKey(const ValueKey('reminder-toggle-details-reminder-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('reminder-details-reminder-1')),
        findsNothing,
      );
      final toggleButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('reminder-toggle-details-reminder-1')),
      );
      expect((toggleButton.icon as Icon).icon, Icons.add);
      expect(find.text('33%'), findsNothing);
    });

    testWidgets('记一笔点击后详情只需展开', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      final toggleKey = find.byKey(
        const ValueKey('reminder-toggle-details-reminder-1'),
      );
      await tester.tap(toggleKey);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reminder-details-reminder-1')),
        findsOneWidget,
      );
      expect(find.text('33%'), findsOneWidget);
      final toggleButtonAfterExpand = tester.widget<IconButton>(
        find.byKey(const ValueKey('reminder-toggle-details-reminder-1')),
      );
      expect((toggleButtonAfterExpand.icon as Icon).icon, Icons.remove);
    });

    testWidgets('上岸进度和提醒卡片保持清晰层级', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      expect(find.byType(PremiumSurface), findsAtLeastNWidgets(1));
      expect(find.text('负债'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('reminder-card-reminder-1')),
        findsOneWidget,
      );
    });

    testWidgets('负债页面不展示额外状态概览网格', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      expect(find.text('进行中'), findsWidgets);
      expect(find.text('已暂停'), findsNothing);
      expect(find.text('已还清'), findsNothing);
      expect(find.byType(PremiumSurface), findsWidgets);
    });

    testWidgets('可以暂停提醒', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'toggle');
      await tester.pumpAndSettle();

      expect(repository.toggleCalls, ['reminder-1']);
    });

    testWidgets('记录还款时提交还款金额和账户', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'payment');
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).first, '1200');
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(repository.paymentCalls, hasLength(1));
      expect(repository.paymentCalls.single.id, 'reminder-1');
      expect(repository.paymentCalls.single.amount, 1200);
      expect(repository.paymentCalls.single.accountId, 'cash-1');
    });

    testWidgets('记录还款时校验本金利息拆分不能超过总额', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'payment');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '1000');
      await tester.enterText(find.byType(TextFormField).at(1), '1200');
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(find.text('本金+利息必须等于还款金额'), findsOneWidget);
      expect(repository.paymentCalls, isEmpty);
    });

    testWidgets('新增提醒时提交核心表单字段', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await tester.tap(find.byKey(const ValueKey('reminder-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '花呗');
      await tester.enterText(find.byType(TextFormField).at(1), '15');
      await tester.enterText(find.byType(TextFormField).at(3), '3000');
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.name, '花呗');
      expect(repository.createCalls.single.paymentDay, 15);
      expect(repository.createCalls.single.principal, 3000);
      expect(repository.createCalls.single.currentBalance, 3000);
    });

    testWidgets('编辑提醒时提交更新表单', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      expect(find.text('利率'), findsNothing);
      await tester.enterText(find.byType(TextFormField).first, '房贷调整');
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.id, 'reminder-1');
      expect(repository.updateCalls.single.request.name, '房贷调整');
    });

    testWidgets('编辑提醒默认不展开更多字段', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();

      expect(find.text('利率'), findsNothing);
      expect(
        find.byKey(const ValueKey('reminder-more-details')),
        findsOneWidget,
      );
    });

    testWidgets('编辑提醒时保留已有凭证路径', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(
        repository.updateCalls.single.request.evidence,
        '["1/reminders/reminder-1/contract.pdf"]',
      );
    });

    testWidgets('编辑提醒移除已有凭证并保存后清理旧文件', (tester) async {
      final repository = _FakeReminderRepository();
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpPage(
        tester,
        repository,
        attachmentRepository: attachmentRepository,
      );

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-more-details')));
      await tester.pumpAndSettle();
      final removeButton = find.byKey(
        const ValueKey('attachment-remove-contract.pdf'),
      );
      await tester.ensureVisible(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.request.evidence, '[]');
      expect(attachmentRepository.deleteCalls, [
        '1/reminders/reminder-1/contract.pdf',
      ]);
    });

    testWidgets('编辑提醒无待上传文件且旧凭证清理失败时保留已保存状态', (tester) async {
      final repository = _FakeReminderRepository();
      final attachmentRepository = _FakeAttachmentRepository()
        ..failDeletes = true;
      await _pumpPage(
        tester,
        repository,
        attachmentRepository: attachmentRepository,
      );
      final initialListCalls = repository.listCalls;

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-more-details')));
      await tester.pumpAndSettle();
      final removeButton = find.byKey(
        const ValueKey('attachment-remove-contract.pdf'),
      );
      await tester.ensureVisible(removeButton);
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, isEmpty);
      expect(attachmentRepository.deleteCalls, [
        '1/reminders/reminder-1/contract.pdf',
      ]);
      expect(find.textContaining('负债提醒已更新，但部分附件尚未处理'), findsWidgets);
      expect(find.text('负债提醒保存失败'), findsNothing);
      expect(repository.listCalls, greaterThan(initialListCalls));
      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsOneWidget,
      );

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('放弃附件重试？'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, '继续重试'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsOneWidget,
      );

      attachmentRepository.failDeletes = false;
      await tester.tap(find.byKey(const ValueKey('reminder-attachment-retry')));
      await tester.pumpAndSettle();

      expect(attachmentRepository.deleteCalls, [
        '1/reminders/reminder-1/contract.pdf',
        '1/reminders/reminder-1/contract.pdf',
      ]);
      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsNothing,
      );
    });

    testWidgets('附件失败后再次编辑成功会清理旧重试且不覆盖新字段', (tester) async {
      final repository = _FakeReminderRepository();
      final attachmentRepository = _FakeAttachmentRepository()
        ..uploadFailuresRemaining = 1;
      await _pumpPage(
        tester,
        repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: const _FakeAttachmentPickerService(
          files: [
            PendingAttachmentFile(path: '/tmp/retry.pdf', name: 'retry.pdf'),
          ],
        ),
      );

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-more-details')));
      await tester.pumpAndSettle();
      final addAttachmentButton = find.byKey(
        const ValueKey('attachment-add-button'),
        skipOffstage: false,
      );
      await tester.ensureVisible(addAttachmentButton);
      await tester.tap(addAttachmentButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsOneWidget,
      );
      expect(repository.updateCalls, hasLength(1));
      expect(repository.attachmentUpdateCalls, hasLength(1));

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      expect(find.text('先处理附件重试'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '放弃并编辑'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '房贷最新');
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(2));
      expect(repository.updateCalls.last.request.name, '房贷最新');
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsNothing,
      );
    });

    testWidgets('附件元数据已提交但响应丢失后编辑使用最新凭证', (tester) async {
      final repository = _FakeReminderRepository()
        ..attachmentUpdateErrorsAfterCommit = 1;
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpPage(
        tester,
        repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: const _FakeAttachmentPickerService(
          files: [PendingAttachmentFile(path: '/tmp/new.pdf', name: 'new.pdf')],
        ),
      );

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-more-details')));
      await tester.pumpAndSettle();
      final addAttachmentButton = find.byKey(
        const ValueKey('attachment-add-button'),
        skipOffstage: false,
      );
      await tester.ensureVisible(addAttachmentButton);
      await tester.tap(addAttachmentButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsOneWidget,
      );
      expect(
        repository.reminders.single.evidence,
        contains('reminders/reminder-1/new.pdf'),
      );

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      expect(find.text('先处理附件重试'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '放弃并编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-more-details')));
      await tester.pumpAndSettle();
      expect(find.text('new.pdf'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '房贷核心字段最新');
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(2));
      expect(
        repository.updateCalls.last.request.evidence,
        contains('reminders/reminder-1/new.pdf'),
      );
      expect(repository.reminders.single.evidence, contains('new.pdf'));
      expect(
        find.byKey(const ValueKey('reminder-attachment-retry')),
        findsNothing,
      );
    });

    testWidgets('保存进行中拦截返回操作', (tester) async {
      final repository = _FakeReminderRepository()
        ..updateGate = Completer<void>();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('提醒操作正在处理中，请稍候'), findsOneWidget);

      repository.updateGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('编辑提醒时上传新凭证并回写路径', (tester) async {
      final repository = _FakeReminderRepository();
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpPage(
        tester,
        repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: const _FakeAttachmentPickerService(
          files: [
            PendingAttachmentFile(
              path: '/tmp/new-contract.pdf',
              name: 'new.pdf',
            ),
          ],
        ),
      );

      await _openReminderAction(tester, 'edit');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-more-details')));
      await tester.pumpAndSettle();
      final addAttachmentButton = find.byKey(
        const ValueKey('attachment-add-button'),
        skipOffstage: false,
      );
      await tester.ensureVisible(addAttachmentButton);
      await tester.pumpAndSettle();
      await tester.tap(addAttachmentButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存提醒'));
      await tester.pumpAndSettle();

      expect(attachmentRepository.uploadCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls.single.category, 'reminders');
      expect(attachmentRepository.uploadCalls.single.refId, 'reminder-1');
      expect(repository.updateCalls, hasLength(1));
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(
        repository.attachmentUpdateCalls.last.$2,
        '["1/reminders/reminder-1/contract.pdf","reminders/reminder-1/new.pdf"]',
      );
    });

    testWidgets('删除提醒前需要确认', (tester) async {
      final repository = _FakeReminderRepository();
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'delete');
      await tester.pumpAndSettle();

      expect(find.text('删除「房贷」？'), findsOneWidget);
      expect(find.text('关联交易不变。'), findsNothing);
      expect(find.textContaining('账本交易会保留'), findsNothing);
      expect(find.text('提醒记录将移除。'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, ['reminder-1']);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final repository = _FakeReminderRepository()..listErrors = 1;
      await _pumpPage(tester, repository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('负债提醒加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('房贷'), findsAtLeastNWidgets(1));
      expect(repository.listCalls, 2);
    });

    testWidgets('没有提醒时展示空态', (tester) async {
      final repository = _FakeReminderRepository()
        ..reminders = const []
        ..summary = const DebtSummary.empty();
      await _pumpPage(tester, repository);

      expect(find.text('还没有负债提醒'), findsOneWidget);
      expect(find.text('右上角添加'), findsOneWidget);
      expect(find.text('还没有负债提醒，先添加提醒'), findsNothing);
      expect(find.text('暂无数据'), findsNothing);
      expect(find.text('¥0.00'), findsWidgets);
    });

    testWidgets('临近还款提醒跟随主题警示色', (tester) async {
      final repository = _FakeReminderRepository()
        ..reminders = [_activeReminder(paymentDay: DateTime.now().day)];
      await _pumpPage(tester, repository, palette: AppThemePalette.graphite);

      final balanceText = tester.widget<Text>(
        find.textContaining('待还 ¥80,000.00').first,
      );
      expect(balanceText.style?.color, AppThemePalette.graphite.warningColor);
    });

    testWidgets('暂停提醒失败时展示错误且保留原状态', (tester) async {
      final repository = _FakeReminderRepository()..toggleError = '暂停失败';
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'toggle');
      await tester.pumpAndSettle();

      expect(repository.toggleCalls, ['reminder-1']);
      expect(find.text('负债提醒保存失败'), findsOneWidget);
      expect(find.text('提醒已暂停'), findsNothing);
      expect(find.text('进行中'), findsWidgets);
      expect(find.text('房贷'), findsAtLeastNWidgets(1));
    });

    testWidgets('记录还款失败时展示错误且保留待还金额', (tester) async {
      final repository = _FakeReminderRepository()..paymentError = '还款失败';
      await _pumpPage(tester, repository);

      await _openReminderAction(tester, 'payment');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '1200');
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(repository.paymentCalls, hasLength(1));
      expect(find.text('负债提醒保存失败'), findsOneWidget);
      expect(find.text('还款已记录'), findsNothing);
      expect(find.text('待还'), findsAtLeastNWidgets(1));
      expect(find.text('¥80,000.00'), findsAtLeastNWidgets(1));
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeReminderRepository repository, {
  _FakeAttachmentRepository? attachmentRepository,
  _FakeAttachmentPickerService? attachmentPickerService,
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reminderRepositoryProvider.overrideWithValue(repository),
        accountRepositoryProvider.overrideWithValue(_FakeAccountRepository()),
        if (attachmentRepository != null)
          attachmentRepositoryProvider.overrideWithValue(attachmentRepository),
        if (attachmentPickerService != null)
          attachmentPickerServiceProvider.overrideWithValue(
            attachmentPickerService,
          ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: const ReminderPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openReminderAction(WidgetTester tester, String action) async {
  await tester.tap(
    find.byKey(const ValueKey('reminder-toggle-details-reminder-1')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('reminder-more-menu-reminder-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('reminder-action-$action-reminder-1')));
}

class _FakeReminderRepository implements ReminderRepository {
  List<ReminderItem> reminders = [_activeReminder()];
  DebtSummary summary = const DebtSummary(
    totalDebt: 80000,
    totalPaid: 40000,
    totalPrincipal: 120000,
    progress: 33.3,
    activeLoans: 1,
    paidOffLoans: 0,
    nextPaymentDay: 10,
    nextPaymentName: '房贷',
    daysUntilNext: 3,
  );
  final List<String> toggleCalls = [];
  final List<String> deleteCalls = [];
  final List<_PaymentCall> paymentCalls = [];
  final List<ReminderFormRequest> createCalls = [];
  final List<_UpdateCall> updateCalls = [];
  final List<(String, String)> attachmentUpdateCalls = [];
  var listCalls = 0;
  var listErrors = 0;
  String? toggleError;
  String? paymentError;
  Completer<void>? updateGate;
  var attachmentUpdateErrorsAfterCommit = 0;

  @override
  Future<ReminderItem?> createReminder(ReminderFormRequest request) async {
    createCalls.add(request);
    final item = _activeReminder(
      id: 'created-1',
      name: request.name,
      paymentDay: request.paymentDay,
      principal: request.principal,
      currentBalance: request.currentBalance,
    );
    reminders = [...reminders, item];
    return item;
  }

  @override
  Future<void> deleteReminder(String id) async {
    deleteCalls.add(id);
    reminders = reminders.where((item) => item.id != id).toList();
  }

  @override
  Future<DebtSummary?> getDebtSummary() async {
    return summary;
  }

  @override
  Future<List<ReminderItem>?> listReminders({String? accountId}) async {
    listCalls += 1;
    if (listErrors > 0) {
      listErrors -= 1;
      throw StateError('负债提醒加载失败');
    }
    return reminders;
  }

  @override
  Future<ReminderItem?> recordPayment(
    String id, {
    required double amount,
    String? accountId,
    double? principalAmount,
    double? interestAmount,
  }) async {
    paymentCalls.add(
      _PaymentCall(
        id: id,
        amount: amount,
        accountId: accountId,
        principalAmount: principalAmount,
        interestAmount: interestAmount,
      ),
    );
    final error = paymentError;
    if (error != null) {
      throw StateError(error);
    }
    return reminders.firstWhere((item) => item.id == id);
  }

  @override
  Future<ReminderItem?> toggleReminder(String id) async {
    toggleCalls.add(id);
    final error = toggleError;
    if (error != null) {
      throw StateError(error);
    }
    final old = reminders.firstWhere((item) => item.id == id);
    final updated = _activeReminder(isEnabled: !old.isEnabled);
    reminders = [updated];
    return updated;
  }

  @override
  Future<ReminderItem?> updateReminder(
    String id,
    ReminderFormRequest request,
  ) async {
    updateCalls.add(_UpdateCall(id: id, request: request));
    final gate = updateGate;
    if (gate != null) {
      await gate.future;
    }
    final updated = _activeReminder(
      id: id,
      name: request.name,
      paymentDay: request.paymentDay,
      principal: request.principal,
      currentBalance: request.currentBalance,
      evidence: request.evidence,
    );
    reminders = [updated];
    return updated;
  }

  @override
  Future<ReminderItem?> updateAttachments(String id, String evidence) async {
    attachmentUpdateCalls.add((id, evidence));
    final old = reminders.firstWhere((item) => item.id == id);
    final updated = _activeReminder(
      id: old.id,
      name: old.name,
      paymentDay: old.paymentDay,
      principal: old.principal,
      currentBalance: old.currentBalance,
      isEnabled: old.isEnabled,
      evidence: evidence,
    );
    reminders = [updated];
    if (attachmentUpdateErrorsAfterCommit > 0) {
      attachmentUpdateErrorsAfterCommit -= 1;
      throw StateError('attachment metadata response lost after commit');
    }
    return updated;
  }
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<void> archive(String id, bool isArchived) {
    throw UnimplementedError();
  }

  @override
  Future<Account> create(CreateAccountRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(String id) {
    throw UnimplementedError();
  }

  @override
  Future<Account> getById(String id) {
    throw UnimplementedError();
  }

  @override
  Future<AccountListResult> list({bool includeArchived = true}) async {
    return const AccountListResult(
      accounts: [
        Account(
          id: 'cash-1',
          name: '储蓄卡',
          type: 'debit',
          icon: '💳',
          color: '#3B82F6',
          initialBalance: 10000,
          currentBalance: 8000,
          isArchived: false,
          sortOrder: 1,
        ),
      ],
      totalAssets: 8000,
      totalLiabilities: 0,
      netAssets: 8000,
    );
  }

  @override
  Future<Account> update(String id, UpdateAccountRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateSort(List<String> ids) {
    throw UnimplementedError();
  }
}

ReminderItem _activeReminder({
  String id = 'reminder-1',
  String name = '房贷',
  int paymentDay = 10,
  double? principal = 120000,
  double? currentBalance = 80000,
  bool isEnabled = true,
  String evidence = '["1/reminders/reminder-1/contract.pdf"]',
}) {
  return ReminderItem(
    id: id,
    name: name,
    accountId: 'loan-1',
    accountName: '贷款账户',
    loanType: 'mortgage',
    paymentDay: paymentDay,
    billingDay: null,
    advanceDays: 3,
    amount: 1000,
    principal: principal,
    currentBalance: currentBalance,
    interestRate: null,
    totalInterest: null,
    totalPaid: 40000,
    interestPaid: 0,
    startDate: null,
    targetDate: null,
    paidOffAt: null,
    color: '#3B82F6',
    remark: '',
    evidence: evidence,
    isEnabled: isEnabled,
  );
}

class _PaymentCall {
  const _PaymentCall({
    required this.id,
    required this.amount,
    this.accountId,
    this.principalAmount,
    this.interestAmount,
  });

  final String id;
  final double amount;
  final String? accountId;
  final double? principalAmount;
  final double? interestAmount;
}

class _UpdateCall {
  const _UpdateCall({required this.id, required this.request});

  final String id;
  final ReminderFormRequest request;
}

class _FakeAttachmentPickerService implements AttachmentPickerService {
  const _FakeAttachmentPickerService({this.files = const []});

  final List<PendingAttachmentFile> files;

  @override
  bool supportsCamera() => true;

  @override
  Future<PendingAttachmentFile?> pickImageFromCamera() async {
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<PendingAttachmentFile?> pickImageFromGallery() async {
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<List<PendingAttachmentFile>> pickFiles() async {
    return files;
  }
}

class _FakeAttachmentRepository implements AttachmentRepository {
  final List<_UploadCall> uploadCalls = [];
  final List<String> deleteCalls = [];
  var failDeletes = false;
  var uploadFailuresRemaining = 0;

  @override
  Future<void> delete(String path) async {
    deleteCalls.add(path);
    if (failDeletes) {
      throw StateError('delete failed');
    }
  }

  @override
  Future<void> download(String path, String savePath) async {}

  @override
  Future<List<int>> downloadBytes(String path) async {
    return const [];
  }

  @override
  Uri downloadUri(String path) {
    return Uri.parse('https://example.test/download?path=$path');
  }

  @override
  Future<LedgerAttachment> upload({
    required PendingAttachmentFile file,
    required String category,
    required String refId,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    uploadCalls.add(_UploadCall(file: file, category: category, refId: refId));
    if (uploadFailuresRemaining > 0) {
      uploadFailuresRemaining -= 1;
      throw StateError('upload failed');
    }
    onSendProgress?.call(1, 1);
    return LedgerAttachment(
      path: '$category/$refId/${file.name}',
      filename: file.name,
      size: file.size,
      mimeType: file.mimeType ?? '',
    );
  }
}

class _UploadCall {
  const _UploadCall({
    required this.file,
    required this.category,
    required this.refId,
  });

  final PendingAttachmentFile file;
  final String category;
  final String refId;
}
