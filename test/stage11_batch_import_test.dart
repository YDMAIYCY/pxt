import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/camera/document_input_contract.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/pipeline/document_ingest_service.dart';

void main() {
  group('Stage 11 batch import', () {
    test(
      'imports multiple images as one study pack with ordered pages',
      () async {
        final repository = _RecordingDocumentBatchRepository();
        final service = DocumentIngestService(
          batchInputPort: _FakeBatchInputPort(
            StoredBatchSelection(
              source: BatchDocumentInputSource.multiImage,
              title: '课堂笔记',
              originalFilePath: null,
              pages: const [
                StoredDocumentPage(
                  savedPath: 'app/page-a.jpg',
                  originalName: 'page-a',
                ),
                StoredDocumentPage(
                  savedPath: 'app/page-b.jpg',
                  originalName: 'page-b',
                ),
              ],
            ),
          ),
          documentBatchRepository: repository,
        );

        final batch = await service.importBatchFromInput(
          userId: 11,
          libraryId: 3,
          source: BatchDocumentInputSource.multiImage,
        );

        expect(batch?.title, '课堂笔记');
        expect(repository.lastUserId, 11);
        expect(repository.lastLibraryId, 3);
        expect(
          repository.lastBatchSourceType,
          DocumentBatchSourceType.multiImage,
        );
        expect(
          repository.lastPageSourceType,
          SourceDocumentSourceType.galleryImport,
        );
        expect(repository.lastPages.map((page) => page.title), [
          '课堂笔记 第1页',
          '课堂笔记 第2页',
        ]);
        expect(repository.lastPages.map((page) => page.pageNumber), [1, 2]);
      },
    );

    test('imports rendered PDF pages as one study pack', () async {
      final repository = _RecordingDocumentBatchRepository();
      final service = DocumentIngestService(
        batchInputPort: _FakeBatchInputPort(
          StoredBatchSelection(
            source: BatchDocumentInputSource.pdf,
            title: '概率论讲义',
            originalFilePath: 'downloads/probability.pdf',
            pages: const [
              StoredDocumentPage(
                savedPath: 'app/probability-1.png',
                originalName: 'probability-1',
              ),
              StoredDocumentPage(
                savedPath: 'app/probability-2.png',
                originalName: 'probability-2',
              ),
            ],
          ),
        ),
        documentBatchRepository: repository,
      );

      final batch = await service.importBatchFromInput(
        userId: 7,
        libraryId: 4,
        source: BatchDocumentInputSource.pdf,
      );

      expect(batch?.sourceType, DocumentBatchSourceType.pdf);
      expect(repository.lastOriginalFilePath, 'downloads/probability.pdf');
      expect(repository.lastPageSourceType, SourceDocumentSourceType.pdfPage);
      expect(repository.lastPages.map((page) => page.title), [
        '概率论讲义 第1页',
        '概率论讲义 第2页',
      ]);
    });

    test(
      'cleans rendered pages and original PDF copy when batch insert fails',
      () async {
        final tempDirectory = Directory.systemTemp.createTempSync(
          'stage11-batch-cleanup',
        );
        addTearDown(() {
          if (tempDirectory.existsSync()) {
            tempDirectory.deleteSync(recursive: true);
          }
        });

        final pdfCopy = File('${tempDirectory.path}\\stored.pdf');
        final pageOne = File('${tempDirectory.path}\\page-1.png');
        final pageTwo = File('${tempDirectory.path}\\page-2.png');
        await pdfCopy.writeAsBytes(<int>[1]);
        await pageOne.writeAsBytes(<int>[2]);
        await pageTwo.writeAsBytes(<int>[3]);

        final service = DocumentIngestService(
          batchInputPort: _FakeBatchInputPort(
            StoredBatchSelection(
              source: BatchDocumentInputSource.pdf,
              title: 'failed-pdf',
              originalFilePath: pdfCopy.path,
              pages: [
                StoredDocumentPage(
                  savedPath: pageOne.path,
                  originalName: 'page-1',
                ),
                StoredDocumentPage(
                  savedPath: pageTwo.path,
                  originalName: 'page-2',
                ),
              ],
            ),
          ),
          documentBatchRepository: _ThrowingDocumentBatchRepository(),
        );

        await expectLater(
          service.importBatchFromInput(
            userId: 7,
            libraryId: 4,
            source: BatchDocumentInputSource.pdf,
          ),
          throwsException,
        );

        expect(pdfCopy.existsSync(), isFalse);
        expect(pageOne.existsSync(), isFalse);
        expect(pageTwo.existsSync(), isFalse);
      },
    );
  });
}

// ========== 测试假对象 ==========
// 隔离真实平台文件选择和 SQLite，只验证批量导入编排行为。

class _FakeBatchInputPort implements BatchDocumentInputPort {
  const _FakeBatchInputPort(this.selection);

  final StoredBatchSelection? selection;

  @override
  Future<StoredBatchSelection?> pickAndStoreBatch({
    required BatchDocumentInputSource source,
  }) async {
    return selection;
  }
}

class _RecordingDocumentBatchRepository extends DocumentBatchRepository {
  int? lastUserId;
  int? lastLibraryId;
  String? lastBatchSourceType;
  String? lastPageSourceType;
  String? lastOriginalFilePath;
  List<DocumentBatchPageDraft> lastPages = const [];

  @override
  Future<DocumentBatchRecord> createDocumentBatch({
    required int userId,
    int? libraryId,
    required String sourceType,
    required String pageSourceType,
    required String title,
    required String? originalFilePath,
    required List<DocumentBatchPageDraft> pages,
    String? operationId,
  }) async {
    lastUserId = userId;
    lastLibraryId = libraryId;
    lastBatchSourceType = sourceType;
    lastPageSourceType = pageSourceType;
    lastOriginalFilePath = originalFilePath;
    lastPages = List<DocumentBatchPageDraft>.of(pages);

    return DocumentBatchRecord(
      id: 99,
      userId: userId,
      libraryId: libraryId,
      sourceType: sourceType,
      title: title,
      originalFilePath: originalFilePath,
      pageCount: pages.length,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

class _ThrowingDocumentBatchRepository extends DocumentBatchRepository {
  @override
  Future<DocumentBatchRecord> createDocumentBatch({
    required int userId,
    int? libraryId,
    required String sourceType,
    required String pageSourceType,
    required String title,
    required String? originalFilePath,
    required List<DocumentBatchPageDraft> pages,
    String? operationId,
  }) async {
    throw Exception('database write failed');
  }
}
