import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/ocr_text_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/llm/minimax_client.dart';
import 'package:pxt1/ocr/local_ocr_client.dart';
import 'package:pxt1/ocr/models/ocr_result.dart';
import 'package:pxt1/ocr/ocr_text_cleaner.dart';
import 'package:pxt1/ocr/ocr_text_repair_service.dart';
import 'package:pxt1/pipeline/ocr_pipeline_service.dart';

void main() {
  test('cleaner removes UI noise before OCR text is saved', () {
    final cleanText = OcrTextCleaner.clean('''
YCY/pxt
16:34
绘图 素材 PageAgent 视频生成 更多
函数是什么？
函数是一种输入、处理、输出的固定规则。
''');

    expect(cleanText, isNot(contains('YCY/pxt')));
    expect(cleanText, isNot(contains('16:34')));
    expect(cleanText, isNot(contains('PageAgent')));
    expect(cleanText, contains('函数是什么？'));
  });

  test('pipeline saves AI repaired finalText with configured model', () async {
    final ocrRepository = _FakeOcrTextRepository();
    final repairService = _FakeOcrTextRepairService();

    final result = await OcrPipelineService(
      localOcrClient: _FakeLocalOcrClient(),
      ocrTextRepository: ocrRepository,
      llmConfigRepository: _FakeLlmConfigRepository(),
      ocrTextRepairService: repairService,
    ).runForDocument(document: _document);

    expect(result.success, isTrue);
    expect(repairService.repairCalls, 1);
    expect(ocrRepository.savedRawText, contains('PageAgent'));
    expect(ocrRepository.savedCleanText, isNot(contains('PageAgent')));
    expect(ocrRepository.savedFinalText, contains('函数的定义'));
    expect(result.record?.effectiveText, contains('函数的定义'));
  });

  test('pipeline merges rendered PDF page OCR into parent document', () async {
    final ocrRepository = _FakeOcrTextRepository();

    final result = await OcrPipelineService(
      localOcrClient: _FakeLocalOcrClient(),
      ocrTextRepository: ocrRepository,
      sourceDocumentRepository: _FakeSourceDocumentRepository(),
      llmConfigRepository: _EmptyLlmConfigRepository(),
    ).runForDocument(document: _pdfDocument);

    expect(result.success, isTrue);
    expect(
      ocrRepository.records[_pdfDocument.id]?.cleanText,
      contains('第 1 页'),
    );
    expect(
      ocrRepository.records[_pdfDocument.id]?.cleanText,
      contains('第 2 页'),
    );
    expect(ocrRepository.records[101]?.cleanText, contains('函数是什么'));
    expect(ocrRepository.records[102]?.cleanText, contains('函数是什么'));
  });
}

final _document = SourceDocumentRecord(
  id: 9,
  userId: 7,
  libraryId: 1,
  sourceType: SourceDocumentSourceType.galleryImport,
  imagePath: 'page.png',
  title: '函数讲义',
  createdAt: DateTime(2026, 6, 29),
  ocrStatus: SourceDocumentOcrStatus.pending,
  aiDone: false,
);

final _pdfDocument = SourceDocumentRecord(
  id: 100,
  userId: 7,
  libraryId: 1,
  batchId: 88,
  sourceType: SourceDocumentSourceType.pdfDocument,
  imagePath: 'source.pdf',
  title: 'PDF 讲义',
  createdAt: DateTime(2026, 6, 29),
  ocrStatus: SourceDocumentOcrStatus.pending,
  aiDone: false,
);

class _FakeLocalOcrClient extends LocalOcrClient {
  @override
  Future<OcrResult> recognizeImage({
    required String imagePath,
    String language = 'zh-CN',
  }) async {
    final rawText = '''
YCY/pxt
16:34
绘图 素材 PageAgent 视频生成 更多
函数是什么？
函数是一种输入、处理、输出的固定规则。
''';
    return OcrResult(
      rawText: rawText,
      cleanText: OcrTextCleaner.clean(rawText),
      language: language,
    );
  }
}

class _FakeOcrTextRepository extends OcrTextRepository {
  String? savedRawText;
  String? savedCleanText;
  String? savedFinalText;
  String? savedStatus;
  final records = <int, OcrTextRecord>{};

  @override
  Future<void> markOcrProcessing({required int documentId}) async {}

  @override
  Future<void> markOcrFailed({
    required int documentId,
    required String errorMessage,
  }) async {}

  @override
  Future<void> upsertOcrText({
    required int documentId,
    required String rawText,
    required String cleanText,
    String? finalText,
    dynamic quality,
    int? qualityScore,
    String? qualityLevel,
    List<String> qualityReasons = const <String>[],
    String language = 'zh-CN',
    String ocrStatus = SourceDocumentOcrStatus.success,
    String? ocrErrorMessage,
  }) async {
    savedRawText = rawText;
    savedCleanText = cleanText;
    savedFinalText = finalText;
    savedStatus = ocrStatus;
    records[documentId] = OcrTextRecord(
      id: documentId,
      documentId: documentId,
      rawText: rawText,
      cleanText: cleanText,
      finalText: finalText,
      language: language,
      createdAt: DateTime(2026, 6, 29),
      updatedAt: DateTime(2026, 6, 29),
    );
  }

  @override
  Future<OcrTextRecord?> getByDocumentId(int documentId) async {
    final record = records[documentId];
    if (record != null) return record;
    return OcrTextRecord(
      id: 1,
      documentId: documentId,
      rawText: savedRawText ?? '',
      cleanText: savedCleanText ?? '',
      finalText: savedFinalText,
      language: 'zh-CN',
      createdAt: DateTime(2026, 6, 29),
      updatedAt: DateTime(2026, 6, 29),
    );
  }
}

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<List<SourceDocumentRecord>> fetchPdfPageSources({
    required int userId,
    required int batchId,
  }) async {
    return [
      SourceDocumentRecord(
        id: 101,
        userId: userId,
        libraryId: 1,
        batchId: batchId,
        pageNumber: 1,
        sourceType: SourceDocumentSourceType.pdfPage,
        imagePath: 'page-1.png',
        title: 'PDF 讲义 第 1 页',
        createdAt: DateTime(2026, 6, 29),
        ocrStatus: SourceDocumentOcrStatus.pending,
        aiDone: false,
      ),
      SourceDocumentRecord(
        id: 102,
        userId: userId,
        libraryId: 1,
        batchId: batchId,
        pageNumber: 2,
        sourceType: SourceDocumentSourceType.pdfPage,
        imagePath: 'page-2.png',
        title: 'PDF 讲义 第 2 页',
        createdAt: DateTime(2026, 6, 29),
        ocrStatus: SourceDocumentOcrStatus.pending,
        aiDone: false,
      ),
    ];
  }
}

class _FakeLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async {
    return LlmProviderConfig(
      id: 1,
      userId: userId,
      provider: LlmProvider.minimax,
      apiMode: LlmApiMode.tokenPlan,
      apiKey: 'sk-cp-test',
      baseUrl: '',
      model: 'MiniMax-M2.7',
      maxTokens: 4096,
      createdAt: DateTime(2026, 6, 29),
      updatedAt: DateTime(2026, 6, 29),
    );
  }
}

class _EmptyLlmConfigRepository extends LlmConfigRepository {
  @override
  Future<LlmProviderConfig?> getByUserId(int userId) async => null;
}

class _FakeOcrTextRepairService extends OcrTextRepairService {
  _FakeOcrTextRepairService() : super(client: _FakeMiniMaxClient());

  int repairCalls = 0;

  @override
  Future<OcrTextRepairResult> repair({
    required String rawText,
    required String cleanText,
  }) async {
    repairCalls++;
    expect(rawText, contains('PageAgent'));
    expect(cleanText, isNot(contains('PageAgent')));
    return const OcrTextRepairResult(
      finalText: '## 函数的定义\n函数是一种输入、处理、输出的固定规则。',
      summary: '删除了页面工具栏和时间噪声',
    );
  }
}

class _FakeMiniMaxClient extends MiniMaxClient {}
