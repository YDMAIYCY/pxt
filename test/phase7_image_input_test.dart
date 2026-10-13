import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/camera/document_input_contract.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/pipeline/document_ingest_service.dart';

void main() {
  group('Phase 7 image input', () {
    late Directory tempDirectory;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync('phase7-image-test');
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test('source document record maps database fields into UI data', () {
      final record = SourceDocumentRecord.fromMap({
        'id': 7,
        'user_id': 1,
        'library_id': 2,
        'source_type': SourceDocumentSourceType.galleryImport,
        'image_path': '${tempDirectory.path}\\gallery_note.jpg',
        'original_title': '高数讲义',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'ocr_done': 1,
        'ai_done': 0,
      });

      expect(record.id, 7);
      expect(record.userId, 1);
      expect(record.libraryId, 2);
      expect(record.title, '高数讲义');
      expect(record.sourceTypeLabel, '相册');
      expect(record.ocrDone, isTrue);
      expect(record.aiDone, isFalse);
    });

    test('document ingest stores a normalized gallery import', () async {
      final repository = _RecordingSourceDocumentRepository();
      final ingestService = DocumentIngestService(
        imageInputPort: _FakeImageInputPort(
          StoredImageSelection(
            savedPath: '${tempDirectory.path}\\stored.jpg',
            originalName: 'math_note_final',
            inputSource: ImageInputSource.gallery,
          ),
        ),
        sourceDocumentRepository: repository,
      );

      final createdDocument = await ingestService.importFromInput(
        userId: 11,
        libraryId: 3,
        source: ImageInputSource.gallery,
      );

      expect(repository.lastUserId, 11);
      expect(repository.lastLibraryId, 3);
      expect(repository.lastSourceType, SourceDocumentSourceType.galleryImport);
      expect(repository.lastTitle, 'math note final');
      expect(createdDocument?.title, 'math note final');
      expect(
        createdDocument?.sourceType,
        SourceDocumentSourceType.galleryImport,
      );
    });

    test(
      'document ingest deletes orphaned file when database insert fails',
      () async {
        final storedFile = File('${tempDirectory.path}\\orphan.jpg');
        await storedFile.writeAsBytes(<int>[1, 2, 3]);

        final ingestService = DocumentIngestService(
          imageInputPort: _FakeImageInputPort(
            StoredImageSelection(
              savedPath: storedFile.path,
              originalName: 'physics_note',
              inputSource: ImageInputSource.gallery,
            ),
          ),
          sourceDocumentRepository: _ThrowingSourceDocumentRepository(),
        );

        await expectLater(
          ingestService.importFromInput(
            userId: 1,
            libraryId: 5,
            source: ImageInputSource.gallery,
          ),
          throwsException,
        );

        expect(storedFile.existsSync(), isFalse);
      },
    );
  });
}

// ========== 测试假对象 ==========
// 用轻量假实现隔离真实数据库和平台输入，专注验证第七阶段业务逻辑。

class _FakeImageInputPort implements ImageInputPort {
  _FakeImageInputPort(this.selection);

  final StoredImageSelection? selection;

  @override
  Future<StoredImageSelection?> pickAndStoreImage({
    required ImageInputSource source,
  }) async {
    return selection;
  }
}

class _RecordingSourceDocumentRepository extends SourceDocumentRepository {
  int? lastUserId;
  int? lastLibraryId;
  String? lastSourceType;
  String? lastImagePath;
  String? lastTitle;

  @override
  Future<SourceDocumentRecord> createSourceDocument({
    required int userId,
    int? libraryId,
    required String sourceType,
    required String imagePath,
    required String title,
    String? operationId,
  }) async {
    lastUserId = userId;
    lastLibraryId = libraryId;
    lastSourceType = sourceType;
    lastImagePath = imagePath;
    lastTitle = title;

    return SourceDocumentRecord(
      id: 99,
      userId: userId,
      libraryId: 1,
      sourceType: sourceType,
      imagePath: imagePath,
      title: title,
      createdAt: DateTime.now(),
      ocrStatus: SourceDocumentOcrStatus.pending,
      aiDone: false,
    );
  }
}

class _ThrowingSourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<SourceDocumentRecord> createSourceDocument({
    required int userId,
    int? libraryId,
    required String sourceType,
    required String imagePath,
    required String title,
    String? operationId,
  }) async {
    throw Exception('database write failed');
  }
}
