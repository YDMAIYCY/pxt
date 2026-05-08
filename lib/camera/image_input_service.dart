import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_render_maintained/pdf_render_maintained.dart';

import 'document_input_contract.dart';

// ========== 图片输入服务 ==========
// 负责调用 image_picker，并将选中的图片复制到应用私有目录。

class ImageInputService implements ImageInputPort, BatchDocumentInputPort {
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
    final savedPath = await _copyIntoStorage(
      sourcePath: pickedFile.path,
      storageDirectory: storageDirectory,
      prefix: 'source',
    );
    final baseName = p.basenameWithoutExtension(pickedFile.path).trim();

    return StoredImageSelection(
      savedPath: savedPath,
      originalName: baseName,
      inputSource: source,
    );
  }

  @override
  Future<StoredBatchSelection?> pickAndStoreBatch({
    required BatchDocumentInputSource source,
  }) {
    switch (source) {
      case BatchDocumentInputSource.multiImage:
        return _pickAndStoreMultipleImages();
      case BatchDocumentInputSource.pdf:
        return _pickAndRenderPdfPages();
    }
  }

  Future<StoredBatchSelection?> _pickAndStoreMultipleImages() async {
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 92);
    if (pickedFiles.isEmpty) {
      return null;
    }

    final storageDirectory = await _ensureStorageDirectory();
    final pages = <StoredDocumentPage>[];

    for (final pickedFile in pickedFiles) {
      final savedPath = await _copyIntoStorage(
        sourcePath: pickedFile.path,
        storageDirectory: storageDirectory,
        prefix: 'batch_image',
      );
      pages.add(
        StoredDocumentPage(
          savedPath: savedPath,
          originalName: p.basenameWithoutExtension(pickedFile.path).trim(),
        ),
      );
    }

    return StoredBatchSelection(
      source: BatchDocumentInputSource.multiImage,
      title: _buildMultiImageBatchTitle(pages),
      originalFilePath: null,
      pages: pages,
    );
  }

  Future<StoredBatchSelection?> _pickAndRenderPdfPages() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final sourcePath = picked.files.single.path;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return null;
    }

    final storageDirectory = await _ensureStorageDirectory();
    final pdfCopyPath = await _copyIntoStorage(
      sourcePath: sourcePath,
      storageDirectory: storageDirectory,
      prefix: 'source_pdf',
      fallbackExtension: '.pdf',
    );
    final title = p.basenameWithoutExtension(sourcePath).trim();
    final pages = <StoredDocumentPage>[];
    PdfDocument? document;

    try {
      document = await PdfDocument.openFile(pdfCopyPath);
      for (var pageNumber = 1; pageNumber <= document.pageCount; pageNumber++) {
        final page = await document.getPage(pageNumber);
        final pageImage = await page.render(
          width: (page.width * 2).round(),
          height: (page.height * 2).round(),
        );
        final image = await pageImage.createImageDetached();
        final pngBytes = await _encodeImageAsPng(image);
        pageImage.dispose();
        image.dispose();

        final savedPath = p.join(
          storageDirectory.path,
          'pdf_page_${DateTime.now().microsecondsSinceEpoch}_$pageNumber.png',
        );
        await File(savedPath).writeAsBytes(pngBytes, flush: true);
        pages.add(
          StoredDocumentPage(
            savedPath: savedPath,
            originalName: '${title.isEmpty ? 'PDF' : title}-$pageNumber',
          ),
        );
      }

      return StoredBatchSelection(
        source: BatchDocumentInputSource.pdf,
        title: title.isEmpty ? 'PDF 资料' : title,
        originalFilePath: pdfCopyPath,
        pages: pages,
      );
    } catch (_) {
      await _deleteStoredPath(pdfCopyPath);
      for (final page in pages) {
        await _deleteStoredPath(page.savedPath);
      }
      rethrow;
    } finally {
      await document?.dispose();
    }
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

  Future<String> _copyIntoStorage({
    required String sourcePath,
    required Directory storageDirectory,
    required String prefix,
    String? fallbackExtension,
  }) async {
    final extension = _normalizeExtension(
      sourcePath,
      fallbackExtension: fallbackExtension,
    );
    final fileName =
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}$extension';
    final savedPath = p.join(storageDirectory.path, fileName);
    await File(sourcePath).copy(savedPath);
    return savedPath;
  }

  Future<List<int>> _encodeImageAsPng(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PDF 页面转图片失败');
    }
    return byteData.buffer.asUint8List();
  }

  String _buildMultiImageBatchTitle(List<StoredDocumentPage> pages) {
    if (pages.length == 1) {
      final name = pages.first.originalName.trim();
      if (name.isNotEmpty) {
        return name;
      }
    }

    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '批量图片 $month-$day $hour:$minute';
  }

  Future<void> _deleteStoredPath(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 清理失败不覆盖原始导入错误。
    }
  }

  String _normalizeExtension(String path, {String? fallbackExtension}) {
    final extension = p.extension(path).trim().toLowerCase();
    if (extension.isEmpty) {
      return fallbackExtension ?? '.jpg';
    }

    return extension;
  }
}
