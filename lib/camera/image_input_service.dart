import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_input_contract.dart';

// ========== 图片输入服务 ==========
// 负责调用 image_picker，并将选中的图片复制到应用私有目录。

class ImageInputService implements ImageInputPort {
  ImageInputService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<StoredImageSelection?> pickAndStoreImage({
    required ImageInputSource source,
  }) async {
    final pickedFile = await _picker.pickImage(
      source: source == ImageInputSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 92,
    );

    if (pickedFile == null) {
      return null;
    }

    final storageDirectory = await _ensureStorageDirectory();
    final extension = _normalizeExtension(pickedFile.path);
    final fileName =
        'source_${DateTime.now().microsecondsSinceEpoch}$extension';
    final savedPath = p.join(storageDirectory.path, fileName);

    await File(pickedFile.path).copy(savedPath);

    final baseName = p.basenameWithoutExtension(pickedFile.path).trim();

    return StoredImageSelection(
      savedPath: savedPath,
      originalName: baseName,
      inputSource: source,
    );
  }

  Future<Directory> _ensureStorageDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final storageDirectory = Directory(
      p.join(appDirectory.path, 'source_documents'),
    );

    if (!await storageDirectory.exists()) {
      await storageDirectory.create(recursive: true);
    }

    return storageDirectory;
  }

  String _normalizeExtension(String path) {
    final extension = p.extension(path).trim().toLowerCase();
    if (extension.isEmpty) {
      return '.jpg';
    }

    return extension;
  }
}
