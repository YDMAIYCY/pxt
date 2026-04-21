import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models/source_document_record.dart';

// ========== 原始资料仓库 ==========
// 统一负责 source_documents 的入库、详情读取和首页最近记录查询。

class SourceDocumentRepository {
  SourceDocumentRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<SourceDocumentRecord> createSourceDocument({
    required int userId,
    required String sourceType,
    required String imagePath,
    required String title,
  }) async {
    final db = await _database.database;
    final createdAt = DateTime.now().toUtc().toIso8601String();

    final documentId = await db.transaction((txn) async {
      final libraryId = await _findDefaultLibraryId(txn, userId);

      return txn.insert(AppDatabase.tableSourceDocuments, {
        'user_id': userId,
        'library_id': libraryId,
        'source_type': sourceType,
        'image_path': imagePath,
        'original_title': title.trim(),
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
    int limit = 5,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        documents.id,
        documents.user_id,
        documents.library_id,
        documents.source_type,
        documents.image_path,
        documents.original_title,
        documents.created_at,
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM ${AppDatabase.tableOcrTexts} ocr
            WHERE ocr.document_id = documents.id
          ) THEN 1
          ELSE 0
        END AS ocr_done,
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
      ORDER BY documents.created_at DESC
      LIMIT ?
      ''',
      [userId, limit],
    );

    return rows.map(SourceDocumentRecord.fromMap).toList(growable: false);
  }

  Future<SourceDocumentRecord?> getSourceDocumentById({
    required int userId,
    required int documentId,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        documents.id,
        documents.user_id,
        documents.library_id,
        documents.source_type,
        documents.image_path,
        documents.original_title,
        documents.created_at,
        CASE
          WHEN EXISTS (
            SELECT 1
            FROM ${AppDatabase.tableOcrTexts} ocr
            WHERE ocr.document_id = documents.id
          ) THEN 1
          ELSE 0
        END AS ocr_done,
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
      return null;
    }

    return rows.first['id'] as int?;
  }
}
