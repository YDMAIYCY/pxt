import 'dart:io';

import 'package:path/path.dart' as p;

import '../camera/document_input_contract.dart';
import '../camera/image_input_service.dart';
import '../database/models/source_document_record.dart';
import '../database/source_document_repository.dart';

// ========== 资料导入编排 ==========
// 将图片输入、文件持久化和 source_documents 入库串成第七阶段的完整闭环。

class DocumentIngestService {
  DocumentIngestService({
    ImageInputPort? imageInputPort,
    SourceDocumentRepository? sourceDocumentRepository,
  }) : _imageInputPort = imageInputPort ?? ImageInputService(),
       _sourceDocumentRepository =
           sourceDocumentRepository ?? SourceDocumentRepository();

  final ImageInputPort _imageInputPort;
  final SourceDocumentRepository _sourceDocumentRepository;

  Future<SourceDocumentRecord?> importFromInput({
    required int userId,
    int? libraryId,
    required ImageInputSource source,
  }) async {
    final storedImage = await _imageInputPort.pickAndStoreImage(source: source);

    if (storedImage == null) {
      return null;
    }

    try {
      return await _sourceDocumentRepository.createSourceDocument(
        userId: userId,
        libraryId: libraryId,
        sourceType: _mapSourceType(source),
        imagePath: storedImage.savedPath,
        title: _buildDocumentTitle(storedImage),
      );
    } catch (_) {
      await _cleanupStoredFile(storedImage.savedPath);
      rethrow;
    }
  }

  String _mapSourceType(ImageInputSource source) {
    switch (source) {
      case ImageInputSource.camera:
        return SourceDocumentSourceType.cameraCapture;
      case ImageInputSource.gallery:
        return SourceDocumentSourceType.galleryImport;
    }
  }

  String _buildDocumentTitle(StoredImageSelection storedImage) {
    final cleanedName = _normalizeOriginalName(storedImage.originalName);
    final timestamp = _formatTimestamp(DateTime.now());

    if (storedImage.inputSource == ImageInputSource.gallery &&
        cleanedName.isNotEmpty) {
      return cleanedName;
    }

    if (storedImage.inputSource == ImageInputSource.camera) {
      return '拍照资料 $timestamp';
    }

    if (cleanedName.isNotEmpty) {
      return cleanedName;
    }

    return '相册导入 $timestamp';
  }

  String _normalizeOriginalName(String originalName) {
    final trimmed = originalName.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final withoutExtension = p.basenameWithoutExtension(trimmed).trim();
    return withoutExtension.replaceAll(RegExp(r'[_\-]+'), ' ');
  }

  String _formatTimestamp(DateTime value) {
    final localTime = value.toLocal();
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');

    return '$month-$day $hour:$minute';
  }

  Future<void> _cleanupStoredFile(String savedPath) async {
    try {
      final storedFile = File(savedPath);
      if (await storedFile.exists()) {
        await storedFile.delete();
      }
    } catch (_) {
      // 保持原始错误向上抛出，清理失败不覆盖真正的入库失败原因。
    }
  }
}
