import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_input_contract.dart';

// ========== 图片输入服务 ==========
// 负责调用 image_picker，并将选中的图片复制到应用私有目录。

const int _maxPdfImportPages = 80;
const int _maxPdfRenderLongestSide = 1600;
const int _maxPdfRenderedPixels = 2200000;

class ImageInputService implements ImageInputPort, BatchDocumentInputPort {
  ImageInputService({ImagePicker? picker, PdfPageRenderer? pdfPageRenderer})
    : _picker = picker ?? ImagePicker(),
      _pdfPageRenderer = pdfPageRenderer ?? const PdfPageRenderer();

  final ImagePicker _picker;
  final PdfPageRenderer _pdfPageRenderer;

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
      case BatchDocumentInputSource.files:
        return _pickAndStoreFiles();
      case BatchDocumentInputSource.cameraSequence:
        return _captureSequence();
    }
  }

  Future<StoredBatchSelection?> _captureSequence() async {
    final pages = <StoredDocumentPage>[];
    while (pages.length < 20) {
      final selected = await pickAndStoreImage(source: ImageInputSource.camera);
      if (selected == null) break;
      pages.add(
        StoredDocumentPage(
          savedPath: selected.savedPath,
          originalName: '拍照第 ${pages.length + 1} 张',
        ),
      );
    }
    if (pages.isEmpty) return null;
    return StoredBatchSelection(
      source: BatchDocumentInputSource.cameraSequence,
      title: '连续拍照 · ${pages.length} 张',
      originalFilePath: null,
      pages: pages,
    );
  }

  Future<StoredBatchSelection?> _pickAndStoreFiles() async {
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
      withData: false,
    );
    if (selected == null || selected.files.isEmpty) return null;
    final directory = await _ensureStorageDirectory();
    final pages = <StoredDocumentPage>[];
    final stored = <String>[];
    try {
      for (final file in selected.files) {
        if (file.path == null) throw StateError('文件无法读取：${file.name}');
        final isPdf = p.extension(file.name).toLowerCase() == '.pdf';
        final copy = await _copyIntoStorage(
          sourcePath: file.path!,
          storageDirectory: directory,
          prefix: isPdf ? 'source_pdf' : 'source',
        );
        stored.add(copy);
        if (isPdf) {
          final rendered = await _pdfPageRenderer.renderPdf(
            pdfPath: copy,
            outputDirectoryPath: directory.path,
            outputPrefix: 'pdf_page_${DateTime.now().microsecondsSinceEpoch}',
            maxPages: _maxPdfImportPages,
            maxLongestSide: _maxPdfRenderLongestSide,
            maxRenderedPixels: _maxPdfRenderedPixels,
          );
          if (rendered.isEmpty) throw StateError('PDF 没有可导入页面：${file.name}');
          for (final page in rendered) {
            stored.add(page.savedPath);
            pages.add(
              StoredDocumentPage(
                savedPath: page.savedPath,
                originalName: '${file.name} · 第 ${page.pageNumber} 页',
                originalFilePath: copy,
                filePageNumber: page.pageNumber,
              ),
            );
          }
        } else {
          pages.add(
            StoredDocumentPage(savedPath: copy, originalName: file.name),
          );
        }
      }
      return StoredBatchSelection(
        source: BatchDocumentInputSource.files,
        title: selected.files.length == 1
            ? selected.files.single.name
            : '文件导入 · ${selected.files.length} 个文件',
        originalFilePath: null,
        pages: pages,
      );
    } catch (_) {
      for (final path in stored) {
        await _deleteStoredPath(path);
      }
      rethrow;
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

    try {
      final renderedPages = await _pdfPageRenderer.renderPdf(
        pdfPath: pdfCopyPath,
        outputDirectoryPath: storageDirectory.path,
        outputPrefix: 'pdf_page_${DateTime.now().microsecondsSinceEpoch}',
        maxPages: _maxPdfImportPages,
        maxLongestSide: _maxPdfRenderLongestSide,
        maxRenderedPixels: _maxPdfRenderedPixels,
      );
      if (renderedPages.isEmpty) {
        throw StateError('PDF 没有可导入的页面');
      }

      for (final page in renderedPages) {
        pages.add(
          StoredDocumentPage(
            savedPath: page.savedPath,
            originalName: '${title.isEmpty ? 'PDF' : title}-${page.pageNumber}',
            originalFilePath: pdfCopyPath,
            filePageNumber: page.pageNumber,
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

// ========== PDF 页面渲染 ==========
// Android 端用系统 PdfRenderer，避开第三方 PDF 插件 JNI 崩溃问题。

class PdfPageRenderer {
  const PdfPageRenderer();

  static const MethodChannel _channel = MethodChannel('pxt1/pdf_renderer');

  Future<List<RenderedPdfPage>> renderPdf({
    required String pdfPath,
    required String outputDirectoryPath,
    required String outputPrefix,
    required int maxPages,
    required int maxLongestSide,
    required int maxRenderedPixels,
  }) async {
    try {
      final result = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'renderPdf',
        <String, Object>{
          'pdfPath': pdfPath,
          'outputDirectoryPath': outputDirectoryPath,
          'outputPrefix': outputPrefix,
          'maxPages': maxPages,
          'maxLongestSide': maxLongestSide,
          'maxRenderedPixels': maxRenderedPixels,
        },
      );

      return (result ?? const <Map<dynamic, dynamic>>[])
          .map(RenderedPdfPage.fromPlatformMap)
          .toList(growable: false);
    } on MissingPluginException catch (error) {
      throw StateError('当前平台暂不支持 PDF 导入：$error');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'PDF 渲染失败：${error.code}');
    }
  }
}

class RenderedPdfPage {
  const RenderedPdfPage({required this.pageNumber, required this.savedPath});

  factory RenderedPdfPage.fromPlatformMap(Map<dynamic, dynamic> map) {
    final pageNumber = map['pageNumber'];
    final savedPath = map['savedPath'];
    if (pageNumber is! int || savedPath is! String || savedPath.isEmpty) {
      throw StateError('PDF 渲染结果异常');
    }
    return RenderedPdfPage(pageNumber: pageNumber, savedPath: savedPath);
  }

  final int pageNumber;
  final String savedPath;
}

_PdfRenderSize _resolvePdfPageRenderSize({
  required double pageWidth,
  required double pageHeight,
}) {
  if (pageWidth <= 0 || pageHeight <= 0) {
    throw StateError('PDF 页面尺寸异常，无法导入');
  }

  final longestSide = math.max(pageWidth, pageHeight);
  var scale = math.min(2.0, _maxPdfRenderLongestSide / longestSide);
  final estimatedPixels = pageWidth * scale * pageHeight * scale;
  if (estimatedPixels > _maxPdfRenderedPixels) {
    scale *= math.sqrt(_maxPdfRenderedPixels / estimatedPixels);
  }

  return _PdfRenderSize(
    width: math.max(1, (pageWidth * scale).round()),
    height: math.max(1, (pageHeight * scale).round()),
  );
}

@visibleForTesting
Map<String, int> resolvePdfPageRenderSizeForTest({
  required double pageWidth,
  required double pageHeight,
}) {
  final size = _resolvePdfPageRenderSize(
    pageWidth: pageWidth,
    pageHeight: pageHeight,
  );
  return {'width': size.width, 'height': size.height};
}

class _PdfRenderSize {
  const _PdfRenderSize({required this.width, required this.height});

  final int width;
  final int height;
}
