import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/attachments/data/attachment_picker_service.dart';
import 'package:personal_ledger/features/attachments/data/attachment_repository.dart';
import 'package:personal_ledger/features/family/data/family_repository.dart';
import 'package:personal_ledger/features/transactions/data/transaction_models.dart';
import 'package:personal_ledger/features/transactions/data/transaction_repository.dart';
import 'package:personal_ledger/features/transactions/presentation/quick_transaction_page.dart';

void main() {
  group('QuickTransactionPage 表单校验', () {
    testWidgets('空表单提交时显示金额和分类必填错误', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      await _tapSaveButton(tester);
      await tester.pump();

      expect(find.text('请输入有效金额'), findsOneWidget);
      expect(find.text('请选择分类'), findsOneWidget);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('金额必须大于 0', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '0',
      );
      await _tapSaveButton(tester);
      await tester.pump();

      expect(find.text('请输入有效金额'), findsOneWidget);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('支出交易选择分类后可成功提交', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '12.34',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.enterText(
        find.byKey(const ValueKey('transaction-remark')),
        '午餐',
      );
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      final formData = repository.createCalls.single;
      expect(formData.type, TransactionType.expense);
      expect(formData.amount, 12.34);
      expect(formData.accountId, 'account-1');
      expect(formData.categoryId, 'category-expense');
      expect(formData.remark, '午餐');
    });

    testWidgets('转账交易必须选择转入账户', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '20',
      );
      await _tapSaveButton(tester);
      await tester.pump();

      expect(find.text('请选择转入账户'), findsOneWidget);
      expect(repository.createCalls, isEmpty);
    });

    testWidgets('转账交易选择转入账户后可成功提交且不带分类', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '20',
      );
      await _selectDropdownItem(tester, fieldLabel: '转入账户', itemText: '储蓄卡');
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      final formData = repository.createCalls.single;
      expect(formData.type, TransactionType.transfer);
      expect(formData.accountId, 'account-1');
      expect(formData.toAccountId, 'account-2');
      expect(formData.categoryId, isNull);
    });

    testWidgets('编辑交易时预填字段并提交更新', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        editingTransaction: TransactionItem(
          id: 'transaction-1',
          type: TransactionType.expense,
          amount: 18,
          accountId: 'account-1',
          categoryId: 'category-expense',
          transactionDate: DateTime(2026, 5, 18, 8, 30),
          remark: '早餐',
          tags: const ['日常'],
        ),
      );

      expect(find.text('编辑交易'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('transaction-amount')),
            )
            .controller
            ?.text,
        '18.00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '20.5',
      );
      await _tapSaveButton(tester, label: '保存修改');
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'transaction-1');
      expect(repository.updateCalls.single.$2.amount, 20.5);
      expect(repository.updateCalls.single.$2.remark, '早餐');
      expect(repository.updateCalls.single.$2.tags, contains('日常'));
    });

    testWidgets('编辑交易默认收起可选字段', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        editingTransaction: TransactionItem(
          id: 'transaction-1',
          type: TransactionType.expense,
          amount: 18,
          accountId: 'account-1',
          categoryId: 'category-expense',
          transactionDate: DateTime(2026, 5, 18, 8, 30),
          remark: '早餐',
          tags: const ['日常'],
          memberId: 'member-1',
          images: '["1/transactions/transaction-1/old.pdf"]',
        ),
      );

      expect(
        find.byKey(const ValueKey('transaction-more-options')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('transaction-remark')), findsNothing);
    });

    testWidgets('编辑交易移除已有附件并保存后清理旧文件', (tester) async {
      final repository = _FakeTransactionRepository();
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        editingTransaction: TransactionItem(
          id: 'transaction-1',
          type: TransactionType.expense,
          amount: 18,
          accountId: 'account-1',
          categoryId: 'category-expense',
          transactionDate: DateTime(2026, 5, 18, 8, 30),
          images: '["1/transactions/transaction-1/old.pdf"]',
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await _expandMoreOptions(tester);
      final removeOldAttachment = find.byKey(
        const ValueKey('attachment-remove-old.pdf'),
      );
      await tester.pumpAndSettle();
      await tester.tap(removeOldAttachment);
      await tester.pumpAndSettle();
      await _tapSaveButton(tester, label: '保存修改');
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(
        decodeAttachmentPaths(repository.updateCalls.single.$2.images),
        isEmpty,
      );
      expect(attachmentRepository.deleteCalls, [
        '1/transactions/transaction-1/old.pdf',
      ]);
      expect(find.textContaining('旧附件清理失败'), findsNothing);
    });

    testWidgets('编辑交易清理旧附件失败时展示轻量反馈', (tester) async {
      final repository = _FakeTransactionRepository();
      final attachmentRepository = _FakeAttachmentRepository()
        ..failDeletes = true;
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        editingTransaction: TransactionItem(
          id: 'transaction-1',
          type: TransactionType.expense,
          amount: 18,
          accountId: 'account-1',
          categoryId: 'category-expense',
          transactionDate: DateTime(2026, 5, 18, 8, 30),
          images: '["1/transactions/transaction-1/old.pdf"]',
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await _expandMoreOptions(tester);
      final removeOldAttachment = find.byKey(
        const ValueKey('attachment-remove-old.pdf'),
      );
      await tester.pumpAndSettle();
      await tester.tap(removeOldAttachment);
      await tester.pumpAndSettle();
      await _tapSaveButton(tester, label: '保存修改');
      await tester.pumpAndSettle();

      expect(attachmentRepository.deleteCalls, [
        '1/transactions/transaction-1/old.pdf',
      ]);
      expect(find.textContaining('旧附件清理失败'), findsNothing);
    });

    testWidgets('新增交易带附件时上传文件并回写附件路径', (tester) async {
      final repository = _FakeTransactionRepository();
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
              size: 120,
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.jpg'), findsOneWidget);

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls.single.file.name, 'receipt.jpg');
      expect(attachmentRepository.uploadCalls.single.category, 'transactions');
      expect(attachmentRepository.uploadCalls.single.refId, 'transaction-1');
      expect(repository.updateCalls, isEmpty);
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(repository.attachmentUpdateCalls.single.$1, 'transaction-1');
      expect(
        decodeAttachmentPaths(repository.attachmentUpdateCalls.single.$2),
        ['transactions/transaction-1/receipt.jpg'],
      );
    });

    testWidgets('附件上传失败后明确保留交易且重试不会重复创建', (tester) async {
      final repository = _FakeTransactionRepository();
      final attachmentRepository = _FakeAttachmentRepository()
        ..uploadFailuresRemaining = 1;
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
              size: 120,
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, hasLength(1));
      expect(repository.updateCalls, isEmpty);
      expect(repository.attachmentUpdateCalls, isEmpty);
      expect(find.textContaining('交易已保存'), findsWidgets);
      expect(find.widgetWithText(FilledButton, '重试附件'), findsOneWidget);

      await _tapSaveButton(tester, label: '重试附件');
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, hasLength(2));
      expect(repository.updateCalls, isEmpty);
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(repository.attachmentUpdateCalls.single.$1, 'transaction-1');
    });

    testWidgets('附件待重试时返回操作要求明确确认后才关闭', (tester) async {
      final repository = _FakeTransactionRepository();
      final attachmentRepository = _FakeAttachmentRepository()
        ..uploadFailuresRemaining = 1;
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
            ),
          ],
        ),
        pushAsRoute: true,
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('放弃附件重试？'), findsOneWidget);
      expect(find.text('继续重试'), findsOneWidget);
      expect(find.text('仍然关闭'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试附件'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, '继续重试'));
      await tester.pumpAndSettle();

      expect(find.text('放弃附件重试？'), findsNothing);
      expect(find.widgetWithText(FilledButton, '重试附件'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '仍然关闭'));
      await tester.pumpAndSettle();

      expect(find.byType(QuickTransactionPage), findsNothing);
      expect(
        find.byKey(const ValueKey('open-quick-transaction-page')),
        findsOneWidget,
      );
    });

    testWidgets('交易提交进行中拦截返回操作', (tester) async {
      final repository = _FakeTransactionRepository()
        ..createGate = Completer<void>();
      await _pumpTransactionPage(tester, repository: repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _tapSaveButton(tester);
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('交易正在保存，请稍候'), findsOneWidget);
      expect(repository.createCalls, hasLength(1));

      repository.createGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('附件重试前修改核心表单会正常保存一次', (tester) async {
      final repository = _FakeTransactionRepository();
      final attachmentRepository = _FakeAttachmentRepository()
        ..uploadFailuresRemaining = 1;
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
              size: 120,
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '重试附件'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '50',
      );
      await _tapSaveButton(tester, label: '重试附件');
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'transaction-1');
      expect(repository.updateCalls.single.$2.amount, 50);
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, hasLength(2));
    });

    testWidgets('附件重试已保存核心修改后不误报为未保存', (tester) async {
      final repository = _FakeTransactionRepository()
        ..attachmentUpdateErrors = 1;
      final attachmentRepository = _FakeAttachmentRepository()
        ..uploadFailuresRemaining = 1;
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
              size: 120,
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '50',
      );
      await _tapSaveButton(tester, label: '重试附件');
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$2.amount, 50);
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(find.textContaining('本次表单修改未保存'), findsNothing);
      expect(find.textContaining('交易已保存，但附件信息同步失败'), findsOneWidget);
    });

    testWidgets('附件元数据同步失败后重试不重写核心交易', (tester) async {
      final repository = _FakeTransactionRepository()
        ..attachmentUpdateErrors = 1;
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
              size: 120,
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.updateCalls, isEmpty);
      expect(repository.attachmentUpdateCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, hasLength(1));
      expect(find.widgetWithText(FilledButton, '重试附件'), findsOneWidget);

      await _tapSaveButton(tester, label: '重试附件');
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.updateCalls, isEmpty);
      expect(repository.attachmentUpdateCalls, hasLength(2));
      expect(attachmentRepository.uploadCalls, hasLength(1));
    });

    testWidgets('元数据响应丢失后移除附件会在重试时强制回写目标状态', (tester) async {
      final repository = _FakeTransactionRepository()
        ..attachmentUpdateErrors = 1
        ..attachmentUpdateCommitsBeforeError = true;
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        attachmentRepository: attachmentRepository,
        attachmentPickerService: _FakeAttachmentPickerService(
          files: const [
            PendingAttachmentFile(
              path: '/tmp/receipt.jpg',
              name: 'receipt.jpg',
              size: 120,
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('attachment-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.serverAttachmentImages, contains('receipt.jpg'));
      final removeAttachment = find.byKey(
        const ValueKey('attachment-remove-receipt.jpg'),
      );
      await tester.ensureVisible(removeAttachment);
      await tester.tap(removeAttachment);
      await tester.pumpAndSettle();

      await _tapSaveButton(tester, label: '重试附件');
      await tester.pumpAndSettle();

      expect(repository.attachmentUpdateCalls, hasLength(2));
      expect(repository.attachmentUpdateCalls.last.$2, '[]');
      expect(repository.serverAttachmentImages, '[]');
      expect(attachmentRepository.uploadCalls, hasLength(1));
    });

    testWidgets('核心创建失败不会误报交易已保存', (tester) async {
      final repository = _FakeTransactionRepository()..createErrors = 1;
      await _pumpTransactionPage(tester, repository: repository);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '45',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(find.text('记账失败'), findsOneWidget);
      expect(find.textContaining('交易已保存'), findsNothing);
    });

    testWidgets('编辑核心更新失败不会误报交易已保存', (tester) async {
      final repository = _FakeTransactionRepository()..updateErrors = 1;
      await _pumpTransactionPage(
        tester,
        repository: repository,
        editingTransaction: TransactionItem(
          id: 'transaction-1',
          type: TransactionType.expense,
          amount: 18,
          accountId: 'account-1',
          categoryId: 'category-expense',
          transactionDate: DateTime(2026, 5, 18, 8, 30),
        ),
      );

      await _tapSaveButton(tester, label: '保存修改');
      await tester.pumpAndSettle();

      expect(find.text('交易保存失败'), findsOneWidget);
      expect(find.textContaining('交易已保存'), findsNothing);
    });

    testWidgets('存在家庭成员时显示成员选择器并提交成员字段', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        familyMembers: const [
          FamilyMember(
            id: 'member-1',
            name: '成员A',
            relationship: '家人',
            color: '#2563EB',
            isDefault: true,
            isEnabled: true,
          ),
        ],
      );

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '88',
      );
      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _expandMoreOptions(tester);
      await _selectDropdownItem(tester, fieldLabel: '成员', itemText: '成员A');
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.memberId, 'member-1');
      expect(repository.createCalls.single.paidByMemberId, 'member-1');
    });

    testWidgets('可选数据失败时提示且可以重试', (tester) async {
      final repository = _FakeTransactionRepository()..tagErrors = 1;
      await _pumpTransactionPage(tester, repository: repository);

      await _expandMoreOptions(tester);

      expect(find.text('标签或家庭成员暂未加载'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-secondary-data-warning')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('标签或家庭成员暂未加载'), findsNothing);
      expect(repository.listTagCalls, 2);
    });

    testWidgets('嵌入式快速记账使用金额优先的原生感 sheet', (tester) async {
      final semantics = tester.ensureSemantics();
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        embedded: true,
      );

      expect(find.text('记一笔'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('transaction-sheet-handle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-amount-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-required-fields')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-sheet-action-bar')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('transaction-amount')), findsOneWidget);
      expect(find.text('账户'), findsOneWidget);
      expect(find.text('分类'), findsOneWidget);
      expect(find.text('时间'), findsOneWidget);
      expect(find.text('更多选项'), findsNothing);
      expect(
        find.byKey(const ValueKey('transaction-more-options')),
        findsOneWidget,
      );
      expect(find.text('备注'), findsNothing);
      await _expandMoreOptions(tester);
      expect(find.text('备注'), findsOneWidget);
      expect(find.text('新标签'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('transaction-add-custom-tag')),
      );
      await tester.pumpAndSettle();
      expect(find.text('新标签'), findsOneWidget);
      expect(find.text('记账指挥条'), findsNothing);
      expect(find.text('录入质量层'), findsNothing);
      expect(find.text('记账动线'), findsNothing);
      expect(find.text('等待金额'), findsNothing);
      expect(find.widgetWithText(FilledButton, '记一笔'), findsOneWidget);
      expect(find.byType(PremiumSurface), findsNothing);
      expect(find.bySemanticsLabel('支出'), findsOneWidget);
      expect(find.bySemanticsLabel('收入'), findsOneWidget);
      expect(find.bySemanticsLabel('转账'), findsOneWidget);
      expect(find.bySemanticsLabel('支出 支出'), findsNothing);
      semantics.dispose();
    });

    testWidgets('类型切换保留纯表单字段', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      expect(find.byKey(const ValueKey('transaction-amount')), findsOneWidget);
      expect(find.byType(SegmentedButton<TransactionType>), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '66.60',
      );
      await tester.pump();

      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('transaction-amount')),
            )
            .controller
            ?.text,
        '66.60',
      );

      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();

      expect(find.text('分类'), findsOneWidget);
      expect(find.text('记录收入来源'), findsNothing);

      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();

      expect(find.text('转入账户'), findsOneWidget);
      expect(find.text('转账动线'), findsNothing);
      expect(find.text('确认转入账户'), findsNothing);
    });

    testWidgets('纯表单通过字段校验进入可保存状态', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      expect(find.text('录入质量层'), findsNothing);
      expect(find.text('待补齐'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '66.60',
      );
      await tester.pump();
      expect(find.text('已输入'), findsNothing);

      await _selectDropdownItem(tester, fieldLabel: '分类', itemText: '餐饮');
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(find.text('可保存'), findsNothing);
    });

    testWidgets('核心表单首屏不依赖装饰卡片', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        palette: AppThemePalette.graphite,
      );

      expect(find.byType(PremiumSurface), findsNothing);
      expect(find.text('金额'), findsOneWidget);
      expect(find.text('账户'), findsOneWidget);
      expect(find.text('分类'), findsOneWidget);
    });
  });
}

Future<void> _pumpTransactionPage(
  WidgetTester tester, {
  required _FakeTransactionRepository repository,
  TransactionItem? editingTransaction,
  _FakeAttachmentRepository? attachmentRepository,
  AttachmentPickerService? attachmentPickerService,
  List<FamilyMember> familyMembers = const [],
  bool embedded = false,
  bool pushAsRoute = false,
  AppThemePalette palette = AppThemePalette.teal,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transactionRepositoryProvider.overrideWithValue(repository),
        if (attachmentRepository != null)
          attachmentRepositoryProvider.overrideWithValue(attachmentRepository),
        if (attachmentPickerService != null)
          attachmentPickerServiceProvider.overrideWithValue(
            attachmentPickerService,
          ),
        familyMembersProvider.overrideWith((ref) async => familyMembers),
        themeControllerProvider.overrideWith(
          (ref) => _FixedThemeController(palette),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: pushAsRoute
            ? Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      key: const ValueKey('open-quick-transaction-page'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => QuickTransactionPage(
                            editingTransaction: editingTransaction,
                            embedded: embedded,
                          ),
                        ),
                      ),
                      child: const Text('打开记账'),
                    ),
                  ),
                ),
              )
            : QuickTransactionPage(
                editingTransaction: editingTransaction,
                embedded: embedded,
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushAsRoute) {
    await tester.tap(find.byKey(const ValueKey('open-quick-transaction-page')));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapSaveButton(WidgetTester tester, {String label = '记一笔'}) async {
  await tester.drag(find.byType(ListView), const Offset(0, -1000));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, label));
}

Future<void> _expandMoreOptions(WidgetTester tester) async {
  final more = find.byKey(
    const ValueKey('transaction-more-options'),
    skipOffstage: false,
  );
  for (var attempt = 0; attempt < 5 && more.evaluate().isEmpty; attempt += 1) {
    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
  }
  expect(more, findsOneWidget);
  await tester.scrollUntilVisible(
    more,
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('transaction-more-options')).hitTestable(),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectDropdownItem(
  WidgetTester tester, {
  required String fieldLabel,
  required String itemText,
}) async {
  final dropdown = find.ancestor(
    of: find.text(fieldLabel),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

class _FixedThemeController extends ThemeController {
  _FixedThemeController(AppThemePalette palette) {
    state = AppThemeSettings(palette: palette);
  }

  @override
  Future<void> load() async {}

  @override
  Future<void> setPalette(AppThemePalette palette) async {
    state = state.copyWith(palette: palette);
  }
}

class _FakeTransactionRepository implements TransactionRepository {
  final List<TransactionFormData> createCalls = [];
  final List<(String, TransactionFormData)> updateCalls = [];
  final List<(String, String)> attachmentUpdateCalls = [];
  var tagErrors = 0;
  var listTagCalls = 0;
  var createErrors = 0;
  var updateErrors = 0;
  var attachmentUpdateErrors = 0;
  var attachmentUpdateCommitsBeforeError = false;
  String serverAttachmentImages = '[]';
  Completer<void>? createGate;

  @override
  Future<void> batchDelete(List<String> ids) async {}

  @override
  Future<List<LedgerAccount>> listAccounts() async {
    return const [
      LedgerAccount(id: 'account-1', name: '现金', type: 'cash'),
      LedgerAccount(id: 'account-2', name: '储蓄卡', type: 'bank_card'),
    ];
  }

  @override
  Future<List<LedgerCategory>> listCategories({String? type}) async {
    return const [
      LedgerCategory(id: 'category-expense', name: '餐饮', type: 'expense'),
      LedgerCategory(id: 'category-income', name: '工资', type: 'income'),
    ];
  }

  @override
  Future<List<LedgerTag>> listTags() async {
    listTagCalls += 1;
    if (tagErrors > 0) {
      tagErrors -= 1;
      throw StateError('tag load failed');
    }
    return const [LedgerTag(id: 'tag-1', name: '日常')];
  }

  @override
  Future<TransactionItem> create(TransactionFormData formData) async {
    createCalls.add(formData);
    final gate = createGate;
    if (gate != null) {
      await gate.future;
    }
    if (createErrors > 0) {
      createErrors -= 1;
      throw StateError('create failed');
    }
    return TransactionItem(
      id: 'transaction-${createCalls.length}',
      type: formData.type,
      amount: formData.amount,
      accountId: formData.accountId,
      categoryId: formData.categoryId,
      transactionDate: formData.transactionDate,
      remark: formData.remark,
      images: formData.images,
      tags: formData.tags,
      toAccountId: formData.toAccountId,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<TransactionItem> getById(String id) async {
    return TransactionItem(
      id: id,
      type: TransactionType.expense,
      amount: 1,
      accountId: 'account-1',
      categoryId: 'category-expense',
      transactionDate: DateTime(2026, 5, 14),
    );
  }

  @override
  Future<TransactionListResult> list(TransactionListQuery query) async {
    return const TransactionListResult(
      list: [],
      total: 0,
      page: 1,
      pageSize: 20,
    );
  }

  @override
  Future<TransactionItem> update(
    String id,
    TransactionFormData formData,
  ) async {
    updateCalls.add((id, formData));
    if (updateErrors > 0) {
      updateErrors -= 1;
      throw StateError('update failed');
    }
    return TransactionItem(
      id: id,
      type: formData.type,
      amount: formData.amount,
      accountId: formData.accountId,
      categoryId: formData.categoryId,
      transactionDate: formData.transactionDate,
      remark: formData.remark,
      images: formData.images,
      tags: formData.tags,
      toAccountId: formData.toAccountId,
    );
  }

  @override
  Future<TransactionItem> updateAttachments(String id, String images) async {
    attachmentUpdateCalls.add((id, images));
    if (attachmentUpdateErrors > 0) {
      attachmentUpdateErrors -= 1;
      if (attachmentUpdateCommitsBeforeError) {
        serverAttachmentImages = images;
      }
      throw StateError('attachment update failed');
    }
    serverAttachmentImages = images;
    return TransactionItem(
      id: id,
      type: TransactionType.expense,
      amount: 1,
      accountId: 'account-1',
      transactionDate: DateTime(2026, 5, 14),
      images: images,
    );
  }
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
