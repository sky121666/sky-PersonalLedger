import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_ledger/features/attachments/data/attachment_models.dart';
import 'package:personal_ledger/features/attachments/data/attachment_picker_service.dart';
import 'package:personal_ledger/features/attachments/presentation/attachment_picker_field.dart';

void main() {
  group('AttachmentPickerField', () {
    testWidgets('展示已上传和待上传附件并支持分别移除', (tester) async {
      await _pumpField(tester);

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('已上传'), findsOneWidget);
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(find.text('待上传'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);

      await tester.tap(find.byTooltip('移除').first);
      await tester.pumpAndSettle();

      expect(find.text('invoice.pdf'), findsNothing);
      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(find.text('1/5'), findsOneWidget);

      await tester.tap(find.byTooltip('移除'));
      await tester.pumpAndSettle();

      expect(find.text('receipt.jpg'), findsNothing);
      expect(find.text('0/5'), findsOneWidget);
    });

    testWidgets('选择文件时按剩余容量追加待上传附件', (tester) async {
      await _pumpField(
        tester,
        maxFiles: 2,
        attachments: const [
          LedgerAttachment(
            path: 'uploaded/invoice.pdf',
            filename: 'invoice.pdf',
          ),
        ],
        pendingFiles: const [],
        pickerService: const _FakeAttachmentPickerService(
          files: [
            PendingAttachmentFile(path: '/tmp/a.jpg', name: 'a.jpg'),
            PendingAttachmentFile(path: '/tmp/b.jpg', name: 'b.jpg'),
          ],
        ),
      );

      await tester.tap(find.text('添加附件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('a.jpg'), findsOneWidget);
      expect(find.text('b.jpg'), findsNothing);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.text('添加附件'), findsNothing);
    });

    testWidgets('上传进度展示百分比和完成状态', (tester) async {
      await _pumpField(
        tester,
        attachments: const [],
        pendingFiles: const [],
        uploadProgress: const [
          AttachmentUploadProgress(fileName: 'receipt.jpg', progress: 0.5),
          AttachmentUploadProgress(
            fileName: 'invoice.pdf',
            progress: 1,
            completed: true,
          ),
        ],
      );

      expect(find.text('receipt.jpg'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('invoice.pdf'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });
  });
}

Future<void> _pumpField(
  WidgetTester tester, {
  List<LedgerAttachment> attachments = const [
    LedgerAttachment(path: 'uploaded/invoice.pdf', filename: 'invoice.pdf'),
  ],
  List<PendingAttachmentFile> pendingFiles = const [
    PendingAttachmentFile(path: '/tmp/receipt.jpg', name: 'receipt.jpg'),
  ],
  List<AttachmentUploadProgress> uploadProgress = const [],
  int maxFiles = 5,
  AttachmentPickerService pickerService = const _FakeAttachmentPickerService(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        attachmentPickerServiceProvider.overrideWithValue(pickerService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: _AttachmentFieldHarness(
              attachments: attachments,
              pendingFiles: pendingFiles,
              uploadProgress: uploadProgress,
              maxFiles: maxFiles,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _AttachmentFieldHarness extends StatefulWidget {
  const _AttachmentFieldHarness({
    required this.attachments,
    required this.pendingFiles,
    required this.uploadProgress,
    required this.maxFiles,
  });

  final List<LedgerAttachment> attachments;
  final List<PendingAttachmentFile> pendingFiles;
  final List<AttachmentUploadProgress> uploadProgress;
  final int maxFiles;

  @override
  State<_AttachmentFieldHarness> createState() =>
      _AttachmentFieldHarnessState();
}

class _AttachmentFieldHarnessState extends State<_AttachmentFieldHarness> {
  late List<LedgerAttachment> _attachments;
  late List<PendingAttachmentFile> _pendingFiles;

  @override
  void initState() {
    super.initState();
    _attachments = widget.attachments;
    _pendingFiles = widget.pendingFiles;
  }

  @override
  Widget build(BuildContext context) {
    return AttachmentPickerField(
      attachments: _attachments,
      pendingFiles: _pendingFiles,
      uploadProgress: widget.uploadProgress,
      maxFiles: widget.maxFiles,
      onAttachmentsChanged: (attachments) {
        setState(() => _attachments = attachments);
      },
      onPendingFilesChanged: (files) {
        setState(() => _pendingFiles = files);
      },
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
