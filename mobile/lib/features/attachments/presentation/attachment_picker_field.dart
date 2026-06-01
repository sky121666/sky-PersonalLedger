import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/widgets/finance_dashboard_widgets.dart';
import '../../../app/widgets/premium_surface.dart';
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
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final capacity = maxFiles <= 0
        ? 0.0
        : (totalCount / maxFiles).clamp(0, 1).toDouble();
    final accent = canAdd ? financeColors.asset : financeColors.warning;

    return PremiumSurface(
      accentColor: accent,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.attach_file,
                color: accent,
                size: 40,
                iconSize: 21,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '附件工作台',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      totalCount == 0 ? '支持图片、文件与凭证留存' : '已关联 $totalCount 个附件',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _AttachmentCapacityPill(
                totalCount: totalCount,
                maxFiles: maxFiles,
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AttachmentSignalDeck(
            totalCount: totalCount,
            maxFiles: maxFiles,
            uploadedCount: attachments.length,
            pendingCount: pendingFiles.length,
            uploadProgress: uploadProgress,
            accent: accent,
          ),
          const SizedBox(height: 12),
          _AttachmentEvidenceMatrix(
            uploadedCount: attachments.length,
            pendingCount: pendingFiles.length,
            canAdd: canAdd,
            accent: accent,
          ),
          const SizedBox(height: 12),
          _AttachmentSaveEvidenceRail(
            totalCount: totalCount,
            maxFiles: maxFiles,
            uploadedCount: attachments.length,
            pendingCount: pendingFiles.length,
            uploadProgress: uploadProgress,
            enabled: enabled,
            accent: accent,
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: capacity,
              color: accent,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
          if (attachments.isNotEmpty || pendingFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Column(
              children: [
                for (final attachment in attachments)
                  _AttachmentTile(
                    title: attachment.filename,
                    subtitle: '已上传',
                    isImage: attachment.isImage,
                    stateColor: financeColors.income,
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
                    stateColor: financeColors.warning,
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
          ],
          for (final progress in uploadProgress) ...[
            const SizedBox(height: 8),
            _UploadProgressTile(progress: progress),
          ],
          if (canAdd) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => _showPickSheet(context, ref),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('添加附件'),
            ),
          ],
        ],
      ),
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _AttachmentPickOption(
                    icon: Icons.photo_library_outlined,
                    title: '从相册选择',
                    subtitle: '添加现有图片凭证',
                    onTap: () async {
                      final file = await picker.pickImageFromGallery();
                      if (context.mounted) {
                        Navigator.of(
                          context,
                        ).pop(file == null ? const [] : [file]);
                      }
                    },
                  ),
                  _AttachmentPickOption(
                    icon: Icons.photo_camera_outlined,
                    title: '拍照',
                    subtitle: '现场拍摄新的凭证',
                    onTap: () async {
                      final file = await picker.pickImageFromCamera();
                      if (context.mounted) {
                        Navigator.of(
                          context,
                        ).pop(file == null ? const [] : [file]);
                      }
                    },
                  ),
                  _AttachmentPickOption(
                    icon: Icons.folder_outlined,
                    title: '选择文件',
                    subtitle: '上传 PDF、图片或其他文件',
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

class _AttachmentSaveEvidenceRail extends StatelessWidget {
  const _AttachmentSaveEvidenceRail({
    required this.totalCount,
    required this.maxFiles,
    required this.uploadedCount,
    required this.pendingCount,
    required this.uploadProgress,
    required this.enabled,
    required this.accent,
  });

  final int totalCount;
  final int maxFiles;
  final int uploadedCount;
  final int pendingCount;
  final List<AttachmentUploadProgress> uploadProgress;
  final bool enabled;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final withinCapacity = maxFiles > 0 && totalCount <= maxFiles;
    final hasSource = totalCount > 0;
    final hasActiveUploads = uploadProgress.any((progress) {
      return !progress.completed && progress.progress < 1;
    });
    final syncReady = pendingCount == 0 && !hasActiveUploads;
    final completed = [
      withinCapacity,
      hasSource,
      syncReady,
    ].where((item) => item).length;
    final ready = completed == 3;
    final stateColor = ready ? financeColors.income : accent;
    return Container(
      key: const ValueKey('attachment-save-evidence-rail'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          stateColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.14
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stateColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready ? Icons.task_alt_outlined : Icons.fact_check_outlined,
                color: stateColor,
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '保存证据',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _AttachmentMatrixPill(
                label: '证据 $completed/3',
                color: stateColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AttachmentEvidenceChip(
                icon: Icons.inventory_2_outlined,
                label: withinCapacity ? '容量合规' : '容量超限',
                value: '$totalCount/$maxFiles',
                color: withinCapacity ? financeColors.income : accent,
              ),
              _AttachmentEvidenceChip(
                icon: enabled
                    ? Icons.add_to_photos_outlined
                    : Icons.lock_outline,
                label: hasSource ? '来源已选' : '来源待选',
                value: uploadedCount > 0 ? '已留存' : '本机',
                color: hasSource ? financeColors.income : accent,
              ),
              _AttachmentEvidenceChip(
                icon: syncReady
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
                label: syncReady ? '同步完成' : '待同步',
                value: pendingCount > 0 ? '$pendingCount 个' : '0 个',
                color: syncReady ? financeColors.income : financeColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentEvidenceChip extends StatelessWidget {
  const _AttachmentEvidenceChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 34, minWidth: 102),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentEvidenceMatrix extends StatelessWidget {
  const _AttachmentEvidenceMatrix({
    required this.uploadedCount,
    required this.pendingCount,
    required this.canAdd,
    required this.accent,
  });

  final int uploadedCount;
  final int pendingCount;
  final bool canAdd;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Container(
      key: const ValueKey('attachment-evidence-matrix'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.primary.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.10
                : 0.045,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route_outlined, size: 18, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '凭证链路矩阵',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              _AttachmentMatrixPill(
                label: canAdd ? '可继续补充' : '容量已满',
                color: canAdd ? financeColors.income : financeColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _AttachmentMatrixTile(
                  icon: Icons.add_to_photos_outlined,
                  label: '采集入口',
                  value: canAdd ? '本机选择' : '已锁定',
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AttachmentMatrixTile(
                  icon: Icons.hourglass_top_rounded,
                  label: '待同步',
                  value: '$pendingCount',
                  color: financeColors.warning,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AttachmentMatrixTile(
                  icon: Icons.verified_outlined,
                  label: '已留存',
                  value: '$uploadedCount',
                  color: financeColors.income,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttachmentMatrixTile extends StatelessWidget {
  const _AttachmentMatrixTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.15
                : 0.07,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentMatrixPill extends StatelessWidget {
  const _AttachmentMatrixPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.11),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AttachmentSignalDeck extends StatelessWidget {
  const _AttachmentSignalDeck({
    required this.totalCount,
    required this.maxFiles,
    required this.uploadedCount,
    required this.pendingCount,
    required this.uploadProgress,
    required this.accent,
  });

  final int totalCount;
  final int maxFiles;
  final int uploadedCount;
  final int pendingCount;
  final List<AttachmentUploadProgress> uploadProgress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final financeColors = AppTheme.financeColors(context);
    final colorScheme = Theme.of(context).colorScheme;
    final remaining = (maxFiles - totalCount).clamp(0, maxFiles);
    final uploadingCount = uploadProgress
        .where((progress) => !progress.completed)
        .length;
    return Container(
      key: const ValueKey('attachment-signal-deck'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.13
                : 0.06,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AttachmentSignalTile(
              icon: Icons.cloud_done_outlined,
              label: '已留存',
              value: '$uploadedCount',
              color: financeColors.income,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AttachmentSignalTile(
              icon: Icons.pending_actions_outlined,
              label: '待上传',
              value: '$pendingCount',
              color: financeColors.warning,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _AttachmentSignalTile(
              icon: uploadingCount > 0
                  ? Icons.cloud_upload_outlined
                  : Icons.inventory_2_outlined,
              label: uploadingCount > 0 ? '上传中' : '剩余',
              value: uploadingCount > 0 ? '$uploadingCount' : '$remaining',
              color: uploadingCount > 0 ? accent : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentSignalTile extends StatelessWidget {
  const _AttachmentSignalTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentCapacityPill extends StatelessWidget {
  const _AttachmentCapacityPill({
    required this.totalCount,
    required this.maxFiles,
    required this.color,
  });

  final int totalCount;
  final int maxFiles;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$totalCount/$maxFiles',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _AttachmentPickOption extends StatelessWidget {
  const _AttachmentPickOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Color.alphaBlend(
          financeColors.asset.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(icon, color: financeColors.asset),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colorScheme.outline, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.title,
    required this.subtitle,
    required this.isImage,
    required this.stateColor,
    required this.onPreview,
    required this.onDownload,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final bool isImage;
  final Color stateColor;
  final VoidCallback? onPreview;
  final VoidCallback? onDownload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final fileTypeLabel = isImage ? '图片凭证' : '文件凭证';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Color.alphaBlend(
          stateColor.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPreview,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconBadge(
                      icon: isImage
                          ? Icons.image_outlined
                          : Icons.insert_drive_file,
                      color: stateColor,
                      size: 40,
                      iconSize: 20,
                    ),
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: stateColor.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Icon(
                          subtitle == '已上传'
                              ? Icons.check_rounded
                              : Icons.schedule_rounded,
                          color: stateColor,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _AttachmentStateChip(
                            label: subtitle,
                            color: stateColor,
                          ),
                          _AttachmentStateChip(
                            label: fileTypeLabel,
                            color: isImage
                                ? financeColors.asset
                                : colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  tooltip: '预览 $title',
                ),
                if (onDownload != null)
                  IconButton(
                    onPressed: onDownload,
                    icon: const Icon(Icons.download_outlined),
                    tooltip: '下载 $title',
                  ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                    tooltip: '移除 $title',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentStateChip extends StatelessWidget {
  const _AttachmentStateChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.10),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w800,
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
    final colorScheme = Theme.of(context).colorScheme;
    final financeColors = AppTheme.financeColors(context);
    final color = progress.completed
        ? financeColors.income
        : financeColors.asset;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          ),
          colorScheme.surface,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                progress.completed
                    ? Icons.check_circle_outline
                    : Icons.cloud_upload_outlined,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  progress.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                progress.completed ? '完成' : '$percent%',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: progress.progress.clamp(0, 1).toDouble(),
              color: color,
              backgroundColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
