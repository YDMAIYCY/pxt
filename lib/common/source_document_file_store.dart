import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// ========== Source document file cleanup ==========
// Deletes only files copied into the app-managed source_documents directory.
class SourceDocumentFileStore {
  const SourceDocumentFileStore({String? managedDirectoryPath})
    : _managedDirectoryPath = managedDirectoryPath;

  final String? _managedDirectoryPath;

  Future<void> deleteAllIfManaged(Iterable<String?> filePaths) async {
    final uniquePaths = <String>{};
    for (final filePath in filePaths) {
      final normalizedPath = filePath?.trim();
      if (normalizedPath == null || normalizedPath.isEmpty) {
        continue;
      }
      uniquePaths.add(normalizedPath);
    }

    if (uniquePaths.isEmpty) {
      return;
    }

    final Directory managedDirectory;
    try {
      managedDirectory = await _resolveManagedDirectory();
    } catch (_) {
      return;
    }
    final rootPath = path.normalize(managedDirectory.path).toLowerCase();
    final safeRoot = '$rootPath${path.separator}';

    for (final filePath in uniquePaths) {
      try {
        final file = File(filePath);
        final targetPath = path.normalize(file.path).toLowerCase();
        if (targetPath != rootPath && !targetPath.startsWith(safeRoot)) {
          continue;
        }
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Cleanup must not hide the original delete/import failure.
      }
    }
  }

  Future<Directory> _resolveManagedDirectory() async {
    if (_managedDirectoryPath != null) {
      return Directory(_managedDirectoryPath);
    }

    final appDirectory = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDirectory.path, 'source_documents'));
  }
}
