import 'package:sqflite/sqflite.dart';

import '../common/source_document_file_store.dart';
import 'app_database.dart';
import 'models/document_batch_record.dart';
import 'models/source_document_record.dart';

// ========== 学习包仓库 ==========
// 管理 PDF / 多图批量导入形成的学习包，以及学习包下的页资料。

class DocumentBatchRepository {
  DocumentBatchRepository({
    AppDatabase? database,
    SourceDocumentFileStore? fileStore,
  }) : _database = database ?? AppDatabase.instance,
       _fileStore = fileStore ?? const SourceDocumentFileStore();

  final AppDatabase _database;
  final SourceDocumentFileStore _fileStore;

  Future<DocumentBatchRecord> createDocumentBatch({
    required int userId,
    int? libraryId,
    required String sourceType,
    required String pageSourceType,
    required String title,
    required String? originalFilePath,
    required List<DocumentBatchPageDraft> pages,
  }) async {
    if (pages.isEmpty) {
      throw ArgumentError('学习包至少需要包含 1 页资料');
    }

    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final batchId = await db.transaction((txn) async {
      final resolvedLibraryId = await _resolveLibraryId(
        txn,
        userId: userId,
        libraryId: libraryId,
      );

      final createdBatchId = await txn
          .insert(AppDatabase.tableDocumentBatches, {
            'user_id': userId,
            'library_id': resolvedLibraryId,
            'source_type': sourceType,
            'title': title.trim().isEmpty ? '未命名学习包' : title.trim(),
            'original_file_path': originalFilePath,
            'page_count': pages.length,
            'created_at': now,
            'updated_at': now,
          });

      if (sourceType == DocumentBatchSourceType.pdf) {
        await txn.insert(AppDatabase.tableSourceDocuments, {
          'user_id': userId,
          'library_id': resolvedLibraryId,
          'batch_id': createdBatchId,
          'page_number': null,
          'source_type': SourceDocumentSourceType.pdfDocument,
          'image_path': originalFilePath ?? '',
          'original_title': title.trim().isEmpty ? 'PDF 资料' : title.trim(),
          'ocr_status': SourceDocumentOcrStatus.pending,
          'ocr_error_message': null,
          'ocr_updated_at': now,
          'created_at': now,
        });
      }

      for (final page in pages) {
        await txn.insert(AppDatabase.tableSourceDocuments, {
          'user_id': userId,
          'library_id': resolvedLibraryId,
          'batch_id': createdBatchId,
          'page_number': page.pageNumber,
          'source_type': pageSourceType,
          'image_path': page.savedPath,
          'original_title': page.title,
          'ocr_status': SourceDocumentOcrStatus.pending,
          'ocr_error_message': null,
          'ocr_updated_at': now,
          'created_at': now,
        });
      }

      await txn.update(
        AppDatabase.tableKnowledgeLibraries,
        {'updated_at': now},
        where: 'id = ? AND user_id = ?',
        whereArgs: [resolvedLibraryId, userId],
      );

      return createdBatchId;
    });

    final batch = await getBatchById(userId: userId, batchId: batchId);
    if (batch == null) {
      throw StateError('学习包创建后读取失败');
    }
    return batch;
  }

  Future<List<DocumentBatchRecord>> fetchRecentBatches({
    required int userId,
    int? libraryId,
    int limit = 20,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _appendLibraryClause(libraryId, args);
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT
        batches.id,
        batches.user_id,
        batches.library_id,
        batches.source_type,
        batches.title,
        batches.original_file_path,
        COUNT(CASE WHEN documents.page_number IS NOT NULL THEN 1 END) AS page_count,
        batches.created_at,
        batches.updated_at
      FROM ${AppDatabase.tableDocumentBatches} batches
      LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
        ON documents.batch_id = batches.id
      WHERE batches.user_id = ?
        $libraryClause
      GROUP BY batches.id
      ORDER BY batches.updated_at DESC, batches.id DESC
      LIMIT ?
      ''', args);

    return rows.map(DocumentBatchRecord.fromMap).toList(growable: false);
  }

  Future<DocumentBatchRecord?> getBatchById({
    required int userId,
    required int batchId,
  }) async {
    final batchWithPages = await getBatchWithPages(
      userId: userId,
      batchId: batchId,
    );
    return batchWithPages?.batch;
  }

  Future<DocumentBatchWithPages?> getBatchWithPages({
    required int userId,
    required int batchId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final batchRows = await db.rawQuery(
      '''
      SELECT
        batches.id,
        batches.user_id,
        batches.library_id,
        batches.source_type,
        batches.title,
        batches.original_file_path,
        COUNT(CASE WHEN documents.page_number IS NOT NULL THEN 1 END) AS page_count,
        batches.created_at,
        batches.updated_at
      FROM ${AppDatabase.tableDocumentBatches} batches
      LEFT JOIN ${AppDatabase.tableSourceDocuments} documents
        ON documents.batch_id = batches.id
      WHERE batches.user_id = ?
        AND batches.id = ?
      GROUP BY batches.id
      LIMIT 1
      ''',
      [userId, batchId],
    );

    if (batchRows.isEmpty) {
      return null;
    }

    final pageRows = await db.rawQuery(
      '''
      SELECT
        documents.id,
        documents.user_id,
        documents.library_id,
        documents.batch_id,
        documents.page_number,
        documents.source_type,
        documents.image_path,
        documents.original_title,
        documents.ocr_status,
        documents.ocr_error_message,
        documents.ocr_updated_at,
        documents.created_at,
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM ${AppDatabase.tableAiGenerationTasks} tasks
            WHERE tasks.document_id = documents.id
              AND tasks.status = 'completed'
          ) THEN 1
          ELSE 0
        END AS ai_done
      FROM ${AppDatabase.tableSourceDocuments} documents
      WHERE documents.user_id = ?
        AND documents.batch_id = ?
        AND documents.page_number IS NOT NULL
      ORDER BY documents.page_number ASC, documents.id ASC
      ''',
      [userId, batchId],
    );

    return DocumentBatchWithPages(
      batch: DocumentBatchRecord.fromMap(batchRows.first),
      pages: pageRows.map(SourceDocumentRecord.fromMap).toList(growable: false),
    );
  }

  Future<void> deleteBatch({required int userId, required int batchId}) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final cleanupPaths = <String?>[];
    final deleted = await db.transaction((txn) async {
      final batchRows = await txn.query(
        AppDatabase.tableDocumentBatches,
        columns: ['original_file_path'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [batchId, userId],
        limit: 1,
      );
      if (batchRows.isEmpty) {
        return 0;
      }
      cleanupPaths.add(batchRows.first['original_file_path'] as String?);

      final pageRows = await txn.query(
        AppDatabase.tableSourceDocuments,
        columns: ['image_path'],
        where: 'batch_id = ? AND user_id = ?',
        whereArgs: [batchId, userId],
      );
      cleanupPaths.addAll(pageRows.map((row) => row['image_path'] as String?));

      await txn.delete(
        AppDatabase.tableSourceDocuments,
        where: 'batch_id = ? AND user_id = ?',
        whereArgs: [batchId, userId],
      );
      return txn.delete(
        AppDatabase.tableDocumentBatches,
        where: 'id = ? AND user_id = ?',
        whereArgs: [batchId, userId],
      );
    });
    if (deleted == 0) {
      throw StateError('学习包不存在或无权删除');
    }
    await _fileStore.deleteAllIfManaged(cleanupPaths);
  }

  Future<int?> _resolveLibraryId(
    DatabaseExecutor db, {
    required int userId,
    int? libraryId,
  }) async {
    if (libraryId != null) {
      final rows = await db.query(
        AppDatabase.tableKnowledgeLibraries,
        columns: ['id'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [libraryId, userId],
        limit: 1,
      );

      if (rows.isEmpty) {
        throw StateError('知识库不存在或无权使用');
      }
      return libraryId;
    }

    final rows = await db.query(
      AppDatabase.tableKnowledgeLibraries,
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      return rows.first['id'] as int?;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert(AppDatabase.tableKnowledgeLibraries, {
      'user_id': userId,
      'name': '默认知识库',
      'description': '系统为用户自动创建的默认知识库',
      'created_at': now,
      'updated_at': now,
    });
  }

  String _appendLibraryClause(int? libraryId, List<Object?> args) {
    if (libraryId == null) {
      return '';
    }
    args.add(libraryId);
    return 'AND batches.library_id = ?';
  }
}
