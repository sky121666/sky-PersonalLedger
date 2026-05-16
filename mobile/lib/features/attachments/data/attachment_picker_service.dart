import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'attachment_models.dart';

final attachmentPickerServiceProvider = Provider<AttachmentPickerService>((
  ref,
) {
  return AttachmentPickerService(imagePicker: ImagePicker());
});

class AttachmentPickerService {
  const AttachmentPickerService({required ImagePicker imagePicker})
    : _imagePicker = imagePicker;

  final ImagePicker _imagePicker;

  Future<PendingAttachmentFile?> pickImageFromGallery() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      return null;
    }
    return PendingAttachmentFile.fromXFile(image);
  }

  Future<PendingAttachmentFile?> pickImageFromCamera() async {
    final image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image == null) {
      return null;
    }
    return PendingAttachmentFile.fromXFile(image);
  }

  Future<List<PendingAttachmentFile>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'txt',
      ],
    );
    if (result == null) {
      return const [];
    }
    return result.files
        .where((file) => file.path != null && file.path!.isNotEmpty)
        .map(PendingAttachmentFile.fromPlatformFile)
        .toList();
  }
}
