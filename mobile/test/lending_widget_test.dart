import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/app/theme/app_theme.dart';
import 'package:personal_ledger/app/theme/theme_mode_controller.dart';
import 'package:personal_ledger/app/widgets/premium_surface.dart';
import 'package:personal_ledger/app/widgets/staggered_entrance.dart';
import 'package:personal_ledger/features/accounts/application/account_controller.dart';
import 'package:personal_ledger/features/accounts/data/account.dart';
import 'package:personal_ledger/features/accounts/data/account_repository.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/attachments/data/attachment_picker_service.dart';
import 'package:personal_ledger/features/attachments/data/attachment_repository.dart';
import 'package:personal_ledger/features/lendings/data/lending_repository.dart';
import 'package:personal_ledger/features/lendings/presentation/lending_page.dart';

void main() {
  group('LendingPage', () {
    testWidgets('展示借贷汇总和进行中的借出记录', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      expect(find.text('借贷往来'), findsOneWidget);
      expect(find.text('应收'), findsAtLeastNWidgets(1));
      expect(find.text('¥1,200.00'), findsAtLeastNWidgets(1));
      expect(find.text('结清率'), findsNothing);
      expect(find.text('张三'), findsOneWidget);
      expect(find.textContaining('剩余'), findsOneWidget);
      expect(find.text('剩余 ¥800.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('lending-card-lend-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('lending-progress-lend-1')),
        findsNothing,
      );
      expect(find.textContaining('凭证'), findsOneWidget);
      expect(find.text('待补凭证'), findsNothing);
      expect(find.textContaining('本金'), findsAtLeastNWidgets(1));
      expect(find.textContaining('已还'), findsAtLeastNWidgets(1));
      expect(find.text('20%'), findsOneWidget);
      expect(find.textContaining('朋友周转'), findsOneWidget);

      expect(
        find.byKey(const ValueKey('lending-relationship-hub')),
        findsNothing,
      );
      expect(find.text('往来关系中枢'), findsNothing);
      expect(find.byKey(const ValueKey('lending-evidence-rail')), findsNothing);
      expect(find.text('证据覆盖 50%'), findsNothing);
      expect(find.byKey(const ValueKey('lending-risk-radar')), findsNothing);
      expect(find.text('回款风险雷达'), findsNothing);
      expect(
        find.byKey(const ValueKey('lending-recovery-flow-panel')),
        findsNothing,
      );
      expect(find.text('回款动线'), findsNothing);
    });

    testWidgets('借贷总览和借贷卡片使用分段入场动效', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      expect(find.byType(StaggeredEntrance), findsAtLeastNWidgets(4));
    });

    testWidgets('新增借出记录时提交联系人和本金', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byKey(const ValueKey('lending-add-lend-out')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lending-contact-name')),
        '王五',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lending-principal')),
        '500',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(lendingRepository.createCalls, hasLength(1));
      expect(lendingRepository.createCalls.single.type, LendingType.lendOut);
      expect(lendingRepository.createCalls.single.contactName, '王五');
      expect(lendingRepository.createCalls.single.principal, 500);
    });

    testWidgets('记录还款时提交还款金额', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byTooltip('记录还款 张三'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lending-repayment-amount')),
        '300',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(lendingRepository.repaymentCalls, hasLength(1));
      expect(lendingRepository.repaymentCalls.single.id, 'lend-1');
      expect(lendingRepository.repaymentCalls.single.request.amount, 300);
    });

    testWidgets('可以查看借贷还款记录', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await _openLendingMoreMenu(tester, '张三');
      await tester.tap(find.text('还款记录'));
      await tester.pumpAndSettle();

      expect(lendingRepository.recordCalls, ['lend-1']);
      expect(find.text('还款记录'), findsOneWidget);
      expect(find.text('首次还款'), findsOneWidget);
      expect(find.text('现金'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('¥200.00'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('编辑借贷记录时保留已有凭证路径', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await _openLendingMoreMenu(tester, '张三');
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(lendingRepository.updateCalls, hasLength(1));
      expect(
        lendingRepository.updateCalls.single.evidence,
        '["1/lendings/lend-1/contract.pdf"]',
      );
    });

    testWidgets('编辑借贷记录移除已有凭证并保存后清理旧文件', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpPage(
        tester,
        lendingRepository,
        attachmentRepository: attachmentRepository,
      );

      await _openLendingMoreMenu(tester, '张三');
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      final removeButton = find.byTooltip(
        '移除 contract.pdf',
        skipOffstage: false,
      );
      await tester.ensureVisible(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(removeButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(lendingRepository.updateCalls, hasLength(1));
      expect(lendingRepository.updateCalls.single.evidence, '[]');
      expect(attachmentRepository.deleteCalls, [
        '1/lendings/lend-1/contract.pdf',
      ]);
    });

    testWidgets('编辑借贷记录时上传新凭证并回写路径', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      final attachmentRepository = _FakeAttachmentRepository();
      await _pumpPage(
        tester,
        lendingRepository,
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

      await _openLendingMoreMenu(tester, '张三');
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      final addAttachmentButton = find.text('添加附件', skipOffstage: false);
      await tester.ensureVisible(addAttachmentButton);
      await tester.pumpAndSettle();
      await tester.tap(addAttachmentButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(attachmentRepository.uploadCalls, hasLength(1));
      expect(attachmentRepository.uploadCalls.single.category, 'lendings');
      expect(attachmentRepository.uploadCalls.single.refId, 'lend-1');
      expect(lendingRepository.updateCalls, hasLength(2));
      expect(
        lendingRepository.updateCalls.last.evidence,
        '["1/lendings/lend-1/contract.pdf","lendings/lend-1/new.pdf"]',
      );
    });

    testWidgets('删除借贷记录前需要确认', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(tester, lendingRepository);

      await _openLendingMoreMenu(tester, '张三');
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.textContaining('账本交易会保留'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(lendingRepository.deleteCalls, ['lend-1']);
    });

    testWidgets('加载失败时展示错误并可重试', (tester) async {
      final lendingRepository = _FakeLendingRepository()..listErrors = 1;
      await _pumpPage(tester, lendingRepository);

      expect(find.text('出错了'), findsOneWidget);
      expect(find.textContaining('借贷列表加载失败'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pumpAndSettle();

      expect(find.text('张三'), findsOneWidget);
      expect(lendingRepository.listCalls, 2);
    });

    testWidgets('没有借出记录时展示空态', (tester) async {
      final lendingRepository = _FakeLendingRepository()
        ..lendings = const []
        ..summary = const LendingSummary.empty();
      await _pumpPage(tester, lendingRepository);

      expect(find.text('暂无借出记录'), findsOneWidget);
      expect(find.text('可以先从上方按钮新增一笔借贷往来。'), findsNothing);
      expect(find.text('¥0.00'), findsWidgets);
    });

    testWidgets('借贷汇总跟随主题色模板', (tester) async {
      final lendingRepository = _FakeLendingRepository();
      await _pumpPage(
        tester,
        lendingRepository,
        palette: AppThemePalette.graphite,
      );

      final overviewSurface = tester.widget<PremiumSurface>(
        find
            .ancestor(
              of: find.text('往来金额'),
              matching: find.byType(PremiumSurface),
            )
            .first,
      );
      expect(overviewSurface.accentColor, AppThemePalette.graphite.incomeColor);
      expect(find.text('应收'), findsOneWidget);
      expect(find.text('应付'), findsOneWidget);
      expect(find.text('借出 1 笔 · 借入 1 笔 · 已结清 0 笔'), findsOneWidget);
    });

    testWidgets('新增借出失败时展示错误且保留列表', (tester) async {
      final lendingRepository = _FakeLendingRepository()
        ..createError = '新增借出失败';
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byKey(const ValueKey('lending-add-lend-out')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lending-contact-name')),
        '王五',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lending-principal')),
        '500',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(lendingRepository.createCalls, hasLength(1));
      expect(find.textContaining('新增借出失败'), findsOneWidget);
      expect(find.text('借出记录已创建'), findsNothing);
      expect(find.text('张三'), findsOneWidget);
    });

    testWidgets('记录还款失败时展示错误且保留原余额', (tester) async {
      final lendingRepository = _FakeLendingRepository()
        ..repaymentError = '还款失败';
      await _pumpPage(tester, lendingRepository);

      await tester.tap(find.byTooltip('记录还款 张三'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('lending-repayment-amount')),
        '300',
      );
      await tester.tap(find.widgetWithText(FilledButton, '确认还款'));
      await tester.pumpAndSettle();

      expect(lendingRepository.repaymentCalls, hasLength(1));
      expect(find.textContaining('还款失败'), findsOneWidget);
      expect(find.text('还款已记录'), findsNothing);
      expect(find.textContaining('剩余'), findsOneWidget);
      expect(find.text('剩余 ¥800.00'), findsOneWidget);
    });
  });
}

Future<void> _openLendingMoreMenu(WidgetTester tester, String contactName) async {
  await tester.tap(find.byTooltip('更多借贷操作 $contactName'));
  await tester.pumpAndSettle();
}

Future<void> _pumpPage(
  WidgetTester tester,
  _FakeLendingRepository lendingRepository, {
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
        lendingRepositoryProvider.overrideWithValue(lendingRepository),
        themeControllerProvider.overrideWith(
          (ref) => _FixedThemeController(palette),
        ),
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
        home: const LendingPage(),
      ),
    ),
  );
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

class _FakeLendingRepository implements LendingRepository {
  List<LendingItem> lendings = [
    LendingItem(
      id: 'lend-1',
      type: LendingType.lendOut,
      contactName: '张三',
      principal: 1000,
      currentBalance: 800,
      totalRepaid: 200,
      lendDate: DateTime(2026, 5, 1, 9),
      dueDate: DateTime.now().add(const Duration(days: 30)),
      remark: '朋友周转',
      evidence: '["1/lendings/lend-1/contract.pdf"]',
    ),
    LendingItem(
      id: 'borrow-1',
      type: LendingType.borrowIn,
      contactName: '李四',
      principal: 500,
      currentBalance: 400,
      totalRepaid: 100,
      lendDate: DateTime(2026, 5, 2, 9),
    ),
  ];

  LendingSummary summary = const LendingSummary(
    totalLendOut: 1000,
    totalBorrowIn: 500,
    activeLendOut: 1,
    activeBorrowIn: 1,
    settledLendOut: 0,
    settledBorrowIn: 0,
    totalReceivable: 1200,
    totalPayable: 400,
    netLending: 800,
  );

  final List<CreateLendingRequest> createCalls = [];
  final List<UpdateLendingRequest> updateCalls = [];
  final List<_RepaymentCall> repaymentCalls = [];
  final List<String> deleteCalls = [];
  final List<String> recordCalls = [];
  var listCalls = 0;
  var listErrors = 0;
  String? createError;
  String? repaymentError;

  @override
  Future<LendingItem?> create(CreateLendingRequest request) async {
    createCalls.add(request);
    final error = createError;
    if (error != null) {
      throw StateError(error);
    }
    final item = LendingItem(
      id: 'lend-new',
      type: request.type,
      contactName: request.contactName,
      principal: request.principal,
      currentBalance: request.principal,
      totalRepaid: 0,
      lendDate: DateTime.parse(request.lendDate),
      remark: request.remark,
    );
    lendings = [...lendings, item];
    return item;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    lendings = lendings.where((item) => item.id != id).toList();
  }

  @override
  Future<List<LendingItem>?> list({bool includeSettled = false}) async {
    listCalls += 1;
    if (listErrors > 0) {
      listErrors -= 1;
      throw StateError('借贷列表加载失败');
    }
    return lendings;
  }

  @override
  Future<List<LendingRecordItem>?> records(String id) async {
    recordCalls.add(id);
    return [
      LendingRecordItem(
        id: 'record-1',
        lendingId: id,
        type: LendingRecordType.repay,
        amount: 200,
        recordDate: DateTime(2026, 5, 10, 9),
        accountId: 'cash',
        accountName: '现金',
        remark: '首次还款',
      ),
    ];
  }

  @override
  Future<LendingItem?> recordRepayment(
    String id,
    RecordRepaymentRequest request,
  ) async {
    repaymentCalls.add(_RepaymentCall(id, request));
    final error = repaymentError;
    if (error != null) {
      throw StateError(error);
    }
    return lendings.firstWhere((item) => item.id == id);
  }

  @override
  Future<LendingSummary?> summaryOverview() async {
    return summary;
  }

  @override
  Future<LendingItem?> update(String id, UpdateLendingRequest request) async {
    updateCalls.add(request);
    return lendings.firstWhere((item) => item.id == id);
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
          id: 'cash',
          name: '现金',
          type: 'cash',
          icon: 'cash',
          color: '#3B82F6',
          initialBalance: 1000,
          currentBalance: 1000,
          isArchived: false,
          sortOrder: 1,
        ),
      ],
      totalAssets: 1000,
      totalLiabilities: 0,
      netAssets: 1000,
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

class _RepaymentCall {
  const _RepaymentCall(this.id, this.request);

  final String id;
  final RecordRepaymentRequest request;
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
