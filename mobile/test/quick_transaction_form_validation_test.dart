import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
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
      expect(find.text('日常'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '20.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-remark')),
        '早餐更新',
      );
      await _tapSaveButton(tester, label: '保存修改');
      await tester.pumpAndSettle();

      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'transaction-1');
      expect(repository.updateCalls.single.$2.amount, 20.5);
      expect(repository.updateCalls.single.$2.remark, '早餐更新');
      expect(repository.updateCalls.single.$2.tags, contains('日常'));
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
      await tester.tap(find.byTooltip('移除'));
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
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加附件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(find.text('待上传'), findsOneWidget);

      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls.single.file.name, 'receipt.jpg');
      expect(attachmentRepository.uploadCalls.single.category, 'transactions');
      expect(attachmentRepository.uploadCalls.single.refId, 'transaction-1');
      expect(repository.updateCalls, hasLength(1));
      expect(repository.updateCalls.single.$1, 'transaction-1');
      expect(decodeAttachmentPaths(repository.updateCalls.single.$2.images), [
        'transactions/transaction-1/receipt.jpg',
      ]);
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
      await _selectDropdownItem(tester, fieldLabel: '成员', itemText: '成员A');
      await _tapSaveButton(tester);
      await tester.pumpAndSettle();

      expect(repository.createCalls, hasLength(1));
      expect(repository.createCalls.single.memberId, 'member-1');
      expect(repository.createCalls.single.paidByMemberId, 'member-1');
    });

    testWidgets('嵌入式快速记账使用高级表单结构', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        embedded: true,
      );

      expect(find.text('记一笔'), findsOneWidget);
      expect(find.byKey(const ValueKey('transaction-amount')), findsOneWidget);
      expect(find.text('选择支出分类'), findsOneWidget);
      expect(find.text('金额、账户和分类是保存前的关键字段'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
      expect(find.byType(PremiumSurface), findsWidgets);
    });

    testWidgets('金额工作台会随输入和类型切换更新', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(tester, repository: repository);

      expect(find.text('支出金额'), findsOneWidget);
      expect(find.text('¥0.00'), findsOneWidget);
      expect(find.byType(SegmentedButton<TransactionType>), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount')),
        '66.60',
      );
      await tester.pump();

      expect(find.text('¥66.60'), findsOneWidget);

      await tester.tap(find.text('收入'));
      await tester.pumpAndSettle();

      expect(find.text('收入金额'), findsOneWidget);
      expect(find.text('记录收入来源'), findsOneWidget);

      await tester.tap(find.text('转账'));
      await tester.pumpAndSettle();

      expect(find.text('转账金额'), findsOneWidget);
      expect(find.text('确认转入账户'), findsOneWidget);
      expect(find.text('转出账户和转入账户不能相同'), findsOneWidget);
    });

    testWidgets('账户区域跟随主题色模板', (tester) async {
      final repository = _FakeTransactionRepository();
      await _pumpTransactionPage(
        tester,
        repository: repository,
        palette: AppThemePalette.graphite,
      );

      final surfaces = tester.widgetList<PremiumSurface>(
        find.byType(PremiumSurface),
      );
      expect(
        surfaces.any(
          (surface) =>
              surface.accentColor == AppThemePalette.graphite.assetColor,
        ),
        isTrue,
      );
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
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(palette),
        darkTheme: AppTheme.darkTheme(palette),
        home: QuickTransactionPage(
          editingTransaction: editingTransaction,
          embedded: embedded,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapSaveButton(WidgetTester tester, {String label = '保存'}) async {
  await tester.drag(find.byType(ListView), const Offset(0, -1000));
  await tester.pumpAndSettle();

  await tester.tap(find.widgetWithText(FilledButton, label));
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

class _FakeTransactionRepository implements TransactionRepository {
  final List<TransactionFormData> createCalls = [];
  final List<(String, TransactionFormData)> updateCalls = [];

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
    return const [LedgerTag(id: 'tag-1', name: '日常')];
  }

  @override
  Future<TransactionItem> create(TransactionFormData formData) async {
    createCalls.add(formData);
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
}

class _FakeAttachmentPickerService implements AttachmentPickerService {
  const _FakeAttachmentPickerService({this.files = const []});

  final List<PendingAttachmentFile> files;

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

  @override
  Future<void> delete(String path) async {
    deleteCalls.add(path);
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
