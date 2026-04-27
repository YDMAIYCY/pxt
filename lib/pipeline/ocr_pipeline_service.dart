import '../database/models/ocr_text_record.dart';
import '../database/models/source_document_record.dart';
import '../database/ocr_text_repository.dart';
import '../ocr/local_ocr_client.dart';

class OcrRunResult {
  const OcrRunResult({
    required this.success,
    required this.message,
    this.record,
  });

  final bool success;
  final String message;
  final OcrTextRecord? record;
}

class OcrPipelineService {
  OcrPipelineService({
    LocalOcrClient? localOcrClient,
    OcrTextRepository? ocrTextRepository,
  }) : _localOcrClient = localOcrClient ?? LocalOcrClient(),
       _ocrTextRepository = ocrTextRepository ?? OcrTextRepository();

  final LocalOcrClient _localOcrClient;
  final OcrTextRepository _ocrTextRepository;

  Future<OcrRunResult> runForDocument({
    required SourceDocumentRecord document,
    String language = 'zh-CN',
  }) async {
    await _ocrTextRepository.markOcrProcessing(documentId: document.id);

    try {
      final result = await _localOcrClient.recognizeImage(
        imagePath: document.imagePath,
        language: language,
      );

      final rawText = result.rawText.trim();
      final cleanText = result.cleanText.trim();
      if (rawText.isEmpty && cleanText.isEmpty) {
        throw const EmptyOcrResultException('识别为空，请重试或更换清晰图片');
      }

      await _ocrTextRepository.upsertOcrText(
        documentId: document.id,
        rawText: rawText.isEmpty ? cleanText : rawText,
        cleanText: cleanText.isEmpty ? rawText : cleanText,
        language: result.language,
      );

      final savedRecord = await _ocrTextRepository.getByDocumentId(document.id);
      if (savedRecord == null) {
        throw const LocalOcrException('OCR 结果保存失败，请重试');
      }

      return OcrRunResult(
        success: true,
        message: 'OCR 识别成功',
        record: savedRecord,
      );
    } catch (error) {
      final message = _friendlyMessage(error);
      await _ocrTextRepository.markOcrFailed(
        documentId: document.id,
        errorMessage: message,
      );
      return OcrRunResult(success: false, message: message);
    }
  }

  String _friendlyMessage(Object error) {
    if (error is LocalOcrException) {
      return error.message;
    }

    final rawMessage = error.toString().trim();
    if (rawMessage.isEmpty) {
      return 'OCR 识别失败，请稍后重试';
    }

    return 'OCR 识别失败：$rawMessage';
  }
}
