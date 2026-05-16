import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/attachment_models.dart';
import '../data/attachment_picker_service.dart';
import '../data/attachment_repository.dart';

class AttachmentPickerField extends ConsumerWidget {
  const AttachmentPickerField({
    required this.attachments,
    required this.pendingFiles,
    required this.onAttachmentsChanged,
    required this.onPendingFilesChanged,
    this.uploadProgress = const [],
    this.maxFiles = 5,
    this.enabled = true,
    super.key,
  });

  final List<LedgerAttachment> attachments;
  final List<PendingAttachmentFile> pendingFiles;
  final ValueChanged<List<LedgerAttachment>> onAttachmentsChanged;
  final ValueChanged<List<PendingAttachmentFile>> onPendingFilesChanged;
  final List<AttachmentUploadProgress> uploadProgress;
  final int maxFiles;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCount = attachments.length + pendingFiles.length;
    final canAdd = enabled && totalCount < maxFiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('附件', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(
              '$totalCount/$maxFiles',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (attachments.isNotEmpty || pendingFiles.isNotEmpty)
          Column(
            children: [
              for (final attachment in attachments)
                _AttachmentTile(
                  title: attachment.filename,
                  subtitle: '已上传',
                  isImage: attachment.isImage,
                  onPreview: () => _previewUploaded(context, ref, attachment),
                  onDownload: () =>
                      _downloadAttachment(context, ref, attachment),
                  onRemove: enabled
                      ? () => onAttachmentsChanged(
                          attachments
                              .where((item) => item.path != attachment.path)
                              .toList(),
                        )
                      : null,
                ),
              for (final file in pendingFiles)
                _AttachmentTile(
                  title: file.name,
                  subtitle: '待上传',
                  isImage: file.isImage,
                  onPreview: () => _previewLocal(context, file),
                  onDownload: null,
                  onRemove: enabled
                      ? () => onPendingFilesChanged(
                          pendingFiles
                              .where((item) => item.path != file.path)
                              .toList(),
                        )
                      : null,
                ),
            ],
          ),
        for (final progress in uploadProgress) ...[
          const SizedBox(height: 8),
          _UploadProgressTile(progress: progress),
        ],
        if (canAdd) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showPickSheet(context, ref),
            icon: const Icon(Icons.attach_file),
            label: const Text('添加附件'),
          ),
        ],
      ],
    );
  }

  Future<void> _showPickSheet(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(attachmentPickerServiceProvider);
    final remainingSlots = maxFiles - attachments.length - pendingFiles.length;
    if (remainingSlots <= 0) {
      return;
    }

    final selectedFiles =
        await showModalBottomSheet<List<PendingAttachmentFile>>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择'),
                  onTap: () async {
                    final file = await picker.pickImageFromGallery();
                    if (context.mounted) {
                      Navigator.of(
                        context,
                      ).pop(file == null ? const [] : [file]);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap: () async {
                    final file = await picker.pickImageFromCamera();
                    if (context.mounted) {
                      Navigator.of(
                        context,
                      ).pop(file == null ? const [] : [file]);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('选择文件'),
                  onTap: () async {
                    final files = await picker.pickFiles();
                    if (context.mounted) {
                      Navigator.of(context).pop(files);
                    }
                  },
                ),
              ],
            ),
          ),
        );

    if (selectedFiles == null || selectedFiles.isEmpty) {
      return;
    }
    onPendingFilesChanged([
      ...pendingFiles,
      ...selectedFiles.take(remainingSlots),
    ]);
  }

  Future<void> _previewUploaded(
    BuildContext context,
    WidgetRef ref,
    LedgerAttachment attachment,
  ) async {
    if (!attachment.isImage) {
      await _downloadAttachment(context, ref, attachment);
      return;
    }
    final bytes = await ref
        .read(attachmentRepositoryProvider)
        .downloadBytes(attachment.path);
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _previewLocal(
    BuildContext context,
    PendingAttachmentFile file,
  ) async {
    if (!file.isImage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该文件将在保存交易后可下载')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          child: Image.file(File(file.path), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _downloadAttachment(
    BuildContext context,
    WidgetRef ref,
    LedgerAttachment attachment,
  ) async {
    try {
      final repository = ref.read(attachmentRepositoryProvider);
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/${attachment.filename}';
      await repository.download(attachment.path, filePath);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已下载到 $filePath')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败：$error')));
      }
    }
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.title,
    required this.subtitle,
    required this.isImage,
    required this.onPreview,
    required this.onDownload,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final bool isImage;
  final VoidCallback? onPreview;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(isImage ? Icons.image_outlined : Icons.insert_drive_file),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        onTap: onPreview,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPreview,
              icon: const Icon(Icons.visibility_outlined),
              tooltip: '预览',
            ),
            if (onDownload != null)
              IconButton(
                onPressed: onDownload,
                icon: const Icon(Icons.download_outlined),
                tooltip: '下载',
              ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                tooltip: '移除',
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadProgressTile extends StatelessWidget {
  const _UploadProgressTile({required this.progress});

  final AttachmentUploadProgress progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress.progress * 100).clamp(0, 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(progress.completed ? '完成' : '$percent%'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: progress.progress.clamp(0, 1)),
      ],
    );
  }
}
