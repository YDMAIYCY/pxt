import '../database/llm_config_repository.dart';
import '../database/models/ocr_text_record.dart';
import '../database/models/source_document_record.dart';
import '../database/ocr_text_repository.dart';
import '../database/source_document_repository.dart';
import '../llm/minimax_client.dart';
import '../ocr/local_ocr_client.dart';
import '../ocr/ocr_text_quality_evaluator.dart';
import '../ocr/ocr_text_repair_service.dart';

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
    SourceDocumentRepository? sourceDocumentRepository,
    LlmConfigRepository? llmConfigRepository,
    OcrTextRepairService? ocrTextRepairService,
  }) : _localOcrClient = localOcrClient ?? LocalOcrClient(),
       _ocrTextRepository = ocrTextRepository ?? OcrTextRepository(),
       _sourceDocumentRepository =
           sourceDocumentRepository ?? SourceDocumentRepository(),
       _llmConfigRepository = llmConfigRepository ?? LlmConfigRepository(),
       _ocrTextRepairService = ocrTextRepairService;

  final LocalOcrClient _localOcrClient;
  final OcrTextRepository _ocrTextRepository;
  final SourceDocumentRepository _sourceDocumentRepository;
  final LlmConfigRepository _llmConfigRepository;
  final OcrTextRepairService? _ocrTextRepairService;

  Future<OcrRunResult> runForDocument({
    required SourceDocumentRecord document,
    String language = 'zh-CN',
    String? imagePathOverride,
  }) async {
    if (document.sourceType == SourceDocumentSourceType.pdfDocument) {
      return _runForPdfDocument(document: document, language: language);
    }

    await _ocrTextRepository.markOcrProcessing(documentId: document.id);

    try {
      final result = await _localOcrClient.recognizeImage(
        imagePath: imagePathOverride?.trim().isNotEmpty == true
            ? imagePathOverride!.trim()
            : document.imagePath,
        language: language,
      );

      final rawText = result.rawText.trim();
      final cleanText = result.cleanText.trim();
      if (rawText.isEmpty && cleanText.isEmpty) {
        throw const EmptyOcrResultException('识别为空，请重试或更换清晰图片');
      }

      final rawForSave = rawText.isEmpty ? cleanText : rawText;
      final cleanForSave = cleanText.isEmpty ? rawText : cleanText;
      final quality = OcrTextQualityEvaluator.evaluate(
        rawText: rawForSave,
        cleanText: cleanForSave,
      );
      final repairOutcome = await _tryRepairWithConfiguredModel(
        userId: document.userId,
        rawText: rawForSave,
        cleanText: cleanForSave,
      );
      final hasFinalText = repairOutcome.finalText?.trim().isNotEmpty == true;
      final needsReview = !hasFinalText && !quality.isUsableForAutomation;
      final message = _buildSuccessMessage(
        needsReview: needsReview,
        repairOutcome: repairOutcome,
      );

      await _ocrTextRepository.upsertOcrText(
        documentId: document.id,
        rawText: rawForSave,
        cleanText: cleanForSave,
        finalText: repairOutcome.finalText,
        quality: quality,
        language: result.language,
        ocrStatus: needsReview
            ? SourceDocumentOcrStatus.needsReview
            : SourceDocumentOcrStatus.success,
        ocrErrorMessage: needsReview ? message : null,
      );

      final savedRecord = await _ocrTextRepository.getByDocumentId(document.id);
      if (savedRecord == null) {
        throw const LocalOcrException('OCR 结果保存失败，请重试');
      }

      return OcrRunResult(
        success: !needsReview,
        message: message,
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

  Future<OcrRunResult> _runForPdfDocument({
    required SourceDocumentRecord document,
    required String language,
  }) async {
    await _ocrTextRepository.markOcrProcessing(documentId: document.id);

    try {
      final batchId = document.batchId;
      if (batchId == null) {
        throw const LocalOcrException('PDF 资料缺少页面来源，无法执行整份 OCR');
      }

      final pages = await _sourceDocumentRepository.fetchPdfPageSources(
        userId: document.userId,
        batchId: batchId,
      );
      if (pages.isEmpty) {
        throw const LocalOcrException('PDF 没有可识别的页面来源');
      }

      final rawParts = <String>[];
      final cleanParts = <String>[];
      final failures = <String>[];

      for (final page in pages) {
        await _ocrTextRepository.markOcrProcessing(documentId: page.id);
        try {
          final result = await _localOcrClient.recognizeImage(
            imagePath: page.imagePath,
            language: language,
          );
          final rawText = result.rawText.trim();
          final cleanText = result.cleanText.trim();
          if (rawText.isEmpty && cleanText.isEmpty) {
            throw const EmptyOcrResultException('OCR 未识别到可用文本');
          }

          final rawForSave = rawText.isEmpty ? cleanText : rawText;
          final cleanForSave = cleanText.isEmpty ? rawText : cleanText;
          final pageLabel = '第 ${page.pageNumber ?? rawParts.length + 1} 页';
          rawParts.add('[$pageLabel]\n$rawForSave');
          cleanParts.add('[$pageLabel]\n$cleanForSave');
          final pageQuality = OcrTextQualityEvaluator.evaluate(
            rawText: rawForSave,
            cleanText: cleanForSave,
          );
          await _ocrTextRepository.upsertOcrText(
            documentId: page.id,
            rawText: rawForSave,
            cleanText: cleanForSave,
            quality: pageQuality,
            language: result.language,
            ocrStatus: pageQuality.isUsableForAutomation
                ? SourceDocumentOcrStatus.success
                : SourceDocumentOcrStatus.needsReview,
            ocrErrorMessage: pageQuality.isUsableForAutomation
                ? null
                : 'PDF 单页 OCR 质量较低，已合并到整份 PDF 文本中',
          );
        } catch (error) {
          final message = _friendlyMessage(error);
          failures.add(
            '第 ${page.pageNumber ?? failures.length + 1} 页：$message',
          );
          await _ocrTextRepository.markOcrFailed(
            documentId: page.id,
            errorMessage: message,
          );
        }
      }

      if (cleanParts.isEmpty && rawParts.isEmpty) {
        throw LocalOcrException(
          failures.isEmpty ? 'PDF OCR 未识别到可用文本' : failures.join('\n'),
        );
      }

      final rawForSave = rawParts.join('\n\n').trim();
      final cleanForSave = cleanParts.join('\n\n').trim();
      final quality = OcrTextQualityEvaluator.evaluate(
        rawText: rawForSave,
        cleanText: cleanForSave,
      );
      final repairOutcome = await _tryRepairWithConfiguredModel(
        userId: document.userId,
        rawText: rawForSave,
        cleanText: cleanForSave,
      );
      final hasFinalText = repairOutcome.finalText?.trim().isNotEmpty == true;
      final needsReview = !hasFinalText && !quality.isUsableForAutomation;
      final message = failures.isEmpty
          ? _buildSuccessMessage(
              needsReview: needsReview,
              repairOutcome: repairOutcome,
            )
          : '${_buildSuccessMessage(needsReview: needsReview, repairOutcome: repairOutcome)}；部分页面失败：${failures.join('；')}';

      await _ocrTextRepository.upsertOcrText(
        documentId: document.id,
        rawText: rawForSave,
        cleanText: cleanForSave,
        finalText: repairOutcome.finalText,
        quality: quality,
        language: language,
        ocrStatus: needsReview
            ? SourceDocumentOcrStatus.needsReview
            : SourceDocumentOcrStatus.success,
        ocrErrorMessage: needsReview || failures.isNotEmpty ? message : null,
      );

      final savedRecord = await _ocrTextRepository.getByDocumentId(document.id);
      if (savedRecord == null) {
        throw const LocalOcrException('PDF OCR 结果保存失败，请重试');
      }

      return OcrRunResult(
        success: !needsReview && failures.isEmpty,
        message: message,
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

  Future<_OcrRepairOutcome> _tryRepairWithConfiguredModel({
    required int userId,
    required String rawText,
    required String cleanText,
  }) async {
    try {
      final config = await _llmConfigRepository.getByUserId(userId);
      if (config == null || !config.isConfigured) {
        return const _OcrRepairOutcome.skipped('未配置 AI 大模型，已保存 OCR 原文和清洗文本');
      }

      final repairService =
          _ocrTextRepairService ??
          OcrTextRepairService(client: MiniMaxClient.fromConfig(config));
      final repaired = await repairService.repair(
        rawText: rawText,
        cleanText: cleanText,
      );
      return _OcrRepairOutcome.repaired(repaired.finalText, repaired.summary);
    } catch (error) {
      return _OcrRepairOutcome.failed(error.toString());
    }
  }

  String _buildSuccessMessage({
    required bool needsReview,
    required _OcrRepairOutcome repairOutcome,
  }) {
    if (repairOutcome.finalText?.trim().isNotEmpty == true) {
      return repairOutcome.summary.trim().isEmpty
          ? 'OCR 识别成功，已使用已配置的大模型生成 finalText'
          : 'OCR 识别成功，AI 已修正：${repairOutcome.summary}';
    }
    if (needsReview) {
      return repairOutcome.message.trim().isEmpty
          ? 'OCR 质量较低，已保存为“待校对”，请 AI 修复或人工确认 finalText'
          : 'OCR 质量较低，${repairOutcome.message}';
    }
    return repairOutcome.message.trim().isEmpty
        ? 'OCR 识别成功'
        : 'OCR 识别成功，${repairOutcome.message}';
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

class _OcrRepairOutcome {
  const _OcrRepairOutcome._({
    this.finalText,
    this.summary = '',
    this.message = '',
  });

  const _OcrRepairOutcome.repaired(String finalText, String summary)
    : this._(finalText: finalText, summary: summary);

  const _OcrRepairOutcome.skipped(String message) : this._(message: message);

  const _OcrRepairOutcome.failed(String message)
    : this._(message: 'AI 修复失败：$message');

  final String? finalText;
  final String summary;
  final String message;
}
