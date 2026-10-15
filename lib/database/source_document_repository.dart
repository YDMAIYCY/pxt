import 'package:sqflite/sqflite.dart';

import '../common/source_document_file_store.dart';
import 'app_database.dart';
import 'import_record_repository.dart';
import 'graph_repository.dart';
import 'models/source_document_record.dart';

// ========== 原始资料仓库 ==========
// 统一负责 source_documents 的入库、详情读取和首页最近记录查询。

class SourceDocumentRepository {
  SourceDocumentRepository({
    AppDatabase? database,
    SourceDocumentFileStore? fileStore,
  }) : _database = database ?? AppDatabase.instance,
       _fileStore = fileStore ?? const SourceDocumentFileStore();

  final AppDatabase _database;
  final SourceDocumentFileStore _fileStore;

  Future<SourceDocumentRecord> createSourceDocument({
    required int userId,
    int? libraryId,
    required String sourceType,
    required String imagePath,
    required String title,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final createdAt = DateTime.now().toUtc().toIso8601String();

    final documentId = await db.transaction((txn) async {
      final resolvedLibraryId = await _resolveLibraryId(
        txn,
        userId: userId,
        libraryId: libraryId,
      );

      return txn.insert(AppDatabase.tableSourceDocuments, {
        'user_id': userId,
        'library_id': resolvedLibraryId,
        'source_type': sourceType,
        'image_path': imagePath,
        'original_file_path': imagePath,
        'original_title': title.trim(),
        'ocr_status': SourceDocumentOcrStatus.pending,
        'ocr_error_message': null,
        'ocr_updated_at': createdAt,
        'created_at': createdAt,
      });
    });

    final createdDocument = await getSourceDocumentById(
      userId: userId,
      documentId: documentId,
    );
    if (createdDocument == null) {
      throw StateError('资料入库成功后未能重新读取记录');
    }

    return createdDocument;
  }

  Future<List<SourceDocumentRecord>> fetchRecentSourceDocuments({
    required int userId,
    int? libraryId,
    bool includeBatchPages = true,
    int limit = 5,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _buildLibraryClause(libraryId, args);
    final batchClause = includeBatchPages
        ? ''
        : 'AND documents.batch_id IS NULL';
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT
        documents.id,
        documents.import_record_id,
        documents.original_file_path,
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
        $libraryClause
        $batchClause
        AND NOT (
          documents.source_type = '${SourceDocumentSourceType.pdfPage}'
          AND documents.batch_id IS NOT NULL
        )
      ORDER BY documents.created_at DESC
      LIMIT ?
      ''', args);

    return rows.map(SourceDocumentRecord.fromMap).toList(growable: false);
  }

  Future<List<SourceDocumentRecord>> fetchAllSourceDocuments({
    required int userId,
    int? libraryId,
    int limit = 100,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _buildLibraryClause(libraryId, args);
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT
        documents.id,
        documents.import_record_id,
        documents.original_file_path,
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
        $libraryClause
        AND NOT (
          documents.source_type = '${SourceDocumentSourceType.pdfPage}'
          AND documents.batch_id IS NOT NULL
        )
      ORDER BY documents.created_at DESC
      LIMIT ?
      ''', args);

    return rows.map(SourceDocumentRecord.fromMap).toList(growable: false);
  }

  Future<SourceDocumentRecord?> getSourceDocumentById({
    required int userId,
    required int documentId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        documents.id,
        documents.import_record_id,
        documents.original_file_path,
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
        AND documents.id = ?
      LIMIT 1
      ''',
      [userId, documentId],
    );

    if (rows.isEmpty) {
      return null;
    }

    return SourceDocumentRecord.fromMap(rows.first);
  }

  Future<List<SourceDocumentRecord>> fetchPdfPageSources({
    required int userId,
    required int batchId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        documents.id,
        documents.import_record_id,
        documents.original_file_path,
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
        AND documents.source_type = ?
        AND documents.page_number IS NOT NULL
      ORDER BY documents.page_number ASC, documents.id ASC
      ''',
      [userId, batchId, SourceDocumentSourceType.pdfPage],
    );

    return rows.map(SourceDocumentRecord.fromMap).toList(growable: false);
  }

  Future<void> moveDocumentToLibrary({
    required int userId,
    required int documentId,
    required int libraryId,
  }) async {
    await _database.ensureSchemaReady();
    final records=ImportRecordRepository(database:_database);
    final record=await records.forDocument(userId,documentId);
    if(record!=null) {
      await records.move(userId,record.id,libraryId);
      return;
    }
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final resolvedLibraryId = await _resolveLibraryId(
        txn,
        userId: userId,
        libraryId: libraryId,
      );
      final documentRows = await txn.query(
        AppDatabase.tableSourceDocuments,
        columns: ['source_type', 'batch_id'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [documentId, userId],
        limit: 1,
      );
      if (documentRows.isEmpty) {
        throw StateError('资料不存在或无权移动');
      }
      final batchId = documentRows.first['batch_id'] as int?;
      final isPdfDocument =
          documentRows.first['source_type'] ==
              SourceDocumentSourceType.pdfDocument &&
          batchId != null;

      final updated = await txn.update(
        AppDatabase.tableSourceDocuments,
        {'library_id': resolvedLibraryId},
        where: isPdfDocument
            ? 'batch_id = ? AND user_id = ?'
            : 'id = ? AND user_id = ?',
        whereArgs: [isPdfDocument ? batchId : documentId, userId],
      );
      if (updated == 0) {
        throw StateError('资料不存在或无权移动');
      }

      if (isPdfDocument) {
        await txn.update(
          AppDatabase.tableDocumentBatches,
          {'library_id': resolvedLibraryId, 'updated_at': now},
          where: 'id = ? AND user_id = ?',
          whereArgs: [batchId, userId],
        );
      }

      await txn.update(
        AppDatabase.tableKnowledgeLibraries,
        {'updated_at': now},
        where: 'id = ? AND user_id = ?',
        whereArgs: [resolvedLibraryId, userId],
      );
    });
  }

  Future<void> updateDocumentImagePath({
    required int userId,
    required int documentId,
    required String imagePath,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await db.update(
      AppDatabase.tableSourceDocuments,
      {
        'image_path': imagePath.trim(),
        'ocr_status': SourceDocumentOcrStatus.pending,
        'ocr_error_message': null,
        'ocr_updated_at': now,
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [documentId, userId],
    );

    if (updated == 0) {
      throw StateError('资料不存在或无权更新图片');
    }
  }

  Future<void> deleteDocument({
    required int userId,
    required int documentId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableSourceDocuments,
      columns: ['image_path', 'original_file_path', 'source_type', 'batch_id'],
      where: 'id = ? AND user_id = ?',
      whereArgs: [documentId, userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('资料不存在或无权删除');
    }

    final cleanupPaths = <String?>[
      rows.first['image_path'] as String?,
      rows.first['original_file_path'] as String?,
    ];
    final batchId = rows.first['batch_id'] as int?;
    final isPdfDocument =
        rows.first['source_type'] == SourceDocumentSourceType.pdfDocument &&
        batchId != null;

    final deleted = await db.transaction((txn) async {
      if (isPdfDocument) {
        final batchRows = await txn.query(
          AppDatabase.tableDocumentBatches,
          columns: ['original_file_path'],
          where: 'id = ? AND user_id = ?',
          whereArgs: [batchId, userId],
          limit: 1,
        );
        if (batchRows.isNotEmpty) {
          cleanupPaths.add(batchRows.first['original_file_path'] as String?);
        }
        final pageRows = await txn.query(
          AppDatabase.tableSourceDocuments,
          columns: ['image_path'],
          where: 'batch_id = ? AND user_id = ?',
          whereArgs: [batchId, userId],
        );
        cleanupPaths.addAll(
          pageRows.map((row) => row['image_path'] as String?),
        );
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
      }

      return txn.delete(
        AppDatabase.tableSourceDocuments,
        where: 'id = ? AND user_id = ?',
        whereArgs: [documentId, userId],
      );
    });
    if (deleted == 0) {
      throw StateError('资料不存在或无权删除');
    }
    await _fileStore.deleteAllIfManaged(cleanupPaths);
    // 资料的图谱来源映射随外键级联删除；这里只失效变成孤立的实体，
    // 其他记录仍在引用的知识点不受影响。
    await GraphRepository(database: _database).pruneOrphans(userId);
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

    return _findDefaultLibraryId(db, userId);
  }

  Future<int?> _findDefaultLibraryId(DatabaseExecutor db, int userId) async {
    final rows = await db.query(
      AppDatabase.tableKnowledgeLibraries,
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
      limit: 1,
    );

    if (rows.isEmpty) {
      final now = DateTime.now().toUtc().toIso8601String();
      return db.insert(AppDatabase.tableKnowledgeLibraries, {
        'user_id': userId,
        'name': '默认知识库',
        'description': '系统为用户自动创建的默认知识库',
        'created_at': now,
        'updated_at': now,
      });
    }

    return rows.first['id'] as int?;
  }

  String _buildLibraryClause(int? libraryId, List<Object?> args) {
    if (libraryId == null) {
      return '';
    }

    args.add(libraryId);
    return 'AND documents.library_id = ?';
  }
}
