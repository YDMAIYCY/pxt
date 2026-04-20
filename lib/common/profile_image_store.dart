import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// ========== 图片类型 ==========
// 区分头像与背景，便于生成独立文件名。
enum ProfileImageKind { avatar, background }

// ========== 本地图片存储服务 ==========
// 负责从相册选择图片，并复制到应用私有目录用于长期持久化。
class ProfileImageStore {
  ProfileImageStore({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  Future<String?> pickAndPersist(ProfileImageKind kind) async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: kind == ProfileImageKind.avatar ? 1200 : 2400,
    );

    if (pickedFile == null) {
      return null;
    }

    final imageDirectory = await _ensureImageDirectory();
    final extension = _safeExtension(pickedFile.path);
    final fileName =
        '${kind.name}_${DateTime.now().microsecondsSinceEpoch}$extension';
    final targetPath = path.join(imageDirectory.path, fileName);

    await File(pickedFile.path).copy(targetPath);
    return targetPath;
  }

  Future<void> deleteIfManaged(String? filePath) async {
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return;
    }

    final imageDirectory = await _ensureImageDirectory();
    final rootPath = path.normalize(imageDirectory.path).toLowerCase();
    final targetPath = path.normalize(file.path).toLowerCase();
    final safeRoot = '$rootPath${path.separator}';

    if (targetPath == rootPath || targetPath.startsWith(safeRoot)) {
      await file.delete();
    }
  }

  Future<Directory> _ensureImageDirectory() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final imageDirectory = Directory(path.join(appDirectory.path, 'profile_media'));

    if (!await imageDirectory.exists()) {
      await imageDirectory.create(recursive: true);
    }

    return imageDirectory;
  }

  String _safeExtension(String sourcePath) {
    final extension = path.extension(sourcePath).trim();
    if (extension.isEmpty || extension.length > 6) {
      return '.jpg';
    }
    return extension;
  }
}
