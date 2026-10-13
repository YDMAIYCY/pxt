import 'package:sqflite/sqflite.dart';

import '../common/source_document_file_store.dart';
import 'app_database.dart';
import 'models/knowledge_library_record.dart';

// ========== 知识库仓库 ==========
// 管理用户自定义知识库的创建、读取和删除。

class KnowledgeLibraryRepository {
  KnowledgeLibraryRepository({
    AppDatabase? database,
    SourceDocumentFileStore? fileStore,
  }) : _database = database ?? AppDatabase.instance,
       _fileStore = fileStore ?? const SourceDocumentFileStore();

  final AppDatabase _database;
  final SourceDocumentFileStore _fileStore;

  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await _ensureDefaultLibrary(db, userId);

    final rows = await db.rawQuery(
      '''
      SELECT
        libraries.id,
        libraries.user_id,
        libraries.name,
        libraries.description,
        libraries.created_at,
        libraries.updated_at,
        (
          SELECT COUNT(*)
          FROM ${AppDatabase.tableSourceDocuments} documents
          WHERE documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = libraries.id)
        ) AS document_count
      FROM ${AppDatabase.tableKnowledgeLibraries} libraries
      WHERE libraries.user_id = ?
      ORDER BY libraries.updated_at DESC, libraries.id ASC
      ''',
      [userId],
    );

    return rows.map(KnowledgeLibraryRecord.fromMap).toList(growable: false);
  }

  Future<KnowledgeLibraryRecord> ensureDefaultLibrary(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final libraryId = await _ensureDefaultLibrary(db, userId);
    final library = await _findLibraryById(db, userId: userId, id: libraryId);
    if (library == null) {
      throw StateError('默认知识库创建后读取失败');
    }
    return library;
  }

  Future<KnowledgeLibraryRecord> createLibrary({
    required int userId,
    required String name,
    String? description,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('知识库名称不能为空');
    }

    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final libraryId = await db.transaction((txn) async {
      final duplicated = await txn.query(
        AppDatabase.tableKnowledgeLibraries,
        columns: ['id'],
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, trimmedName],
        limit: 1,
      );
      if (duplicated.isNotEmpty) {
        throw StateError('已存在同名知识库');
      }

      return txn.insert(AppDatabase.tableKnowledgeLibraries, {
        'user_id': userId,
        'name': trimmedName,
        'description': description?.trim(),
        'created_at': now,
        'updated_at': now,
      });
    });

    final library = await _findLibraryById(db, userId: userId, id: libraryId);
    if (library == null) {
      throw StateError('知识库创建后读取失败');
    }
    return library;
  }

  Future<void> deleteLibraryAndContents({
    required int userId,
    required int libraryId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final cleanupPaths = <String?>[];

    await db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.tableKnowledgeLibraries,
        columns: ['id'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [libraryId, userId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('知识库不存在或无权删除');
      }

      // A package linked to another library must survive removal of this one.
      final shared = await txn.rawQuery(
        """
        SELECT d.id, MIN(dl.library_id) AS replacement
        FROM source_documents d JOIN document_library_links dl ON dl.document_id = d.id
        WHERE d.user_id = ? AND d.library_id = ? AND dl.library_id != ?
        GROUP BY d.id
      """,
        [userId, libraryId, libraryId],
      );
      for (final row in shared) {
        await txn.update(
          'source_documents',
          {'library_id': row['replacement']},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await txn.rawUpdate(
        """
        UPDATE document_batches SET library_id = (
          SELECT library_id FROM source_documents WHERE batch_id = document_batches.id ORDER BY id LIMIT 1
        ) WHERE user_id = ? AND library_id = ? AND EXISTS (
          SELECT 1 FROM source_documents WHERE batch_id = document_batches.id AND library_id != ?
        )
      """,
        [userId, libraryId, libraryId],
      );

      final documentRows = await txn.query(
        AppDatabase.tableSourceDocuments,
        columns: ['image_path'],
        where: 'user_id = ? AND library_id = ?',
        whereArgs: [userId, libraryId],
      );
      cleanupPaths.addAll(
        documentRows.map((row) => row['image_path'] as String?),
      );

      final batchRows = await txn.query(
        AppDatabase.tableDocumentBatches,
        columns: ['original_file_path'],
        where: 'user_id = ? AND library_id = ?',
        whereArgs: [userId, libraryId],
      );
      cleanupPaths.addAll(
        batchRows.map((row) => row['original_file_path'] as String?),
      );

      await txn.delete(
        AppDatabase.tableSourceDocuments,
        where: 'user_id = ? AND library_id = ?',
        whereArgs: [userId, libraryId],
      );
      await txn.delete(
        AppDatabase.tableDocumentBatches,
        where: 'user_id = ? AND library_id = ?',
        whereArgs: [userId, libraryId],
      );
      await txn.delete(
        AppDatabase.tableKnowledgeLibraries,
        where: 'id = ? AND user_id = ?',
        whereArgs: [libraryId, userId],
      );
      await _ensureDefaultLibrary(txn, userId);
    });
    await _fileStore.deleteAllIfManaged(cleanupPaths);
  }

  Future<int> _ensureDefaultLibrary(DatabaseExecutor db, int userId) async {
    final existing = await db.query(
      AppDatabase.tableKnowledgeLibraries,
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id ASC',
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
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

  Future<KnowledgeLibraryRecord?> _findLibraryById(
    DatabaseExecutor db, {
    required int userId,
    required int id,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        libraries.id,
        libraries.user_id,
        libraries.name,
        libraries.description,
        libraries.created_at,
        libraries.updated_at,
        (
          SELECT COUNT(*)
          FROM ${AppDatabase.tableSourceDocuments} documents
          WHERE documents.id IN (SELECT document_id FROM document_library_links WHERE library_id = libraries.id)
        ) AS document_count
      FROM ${AppDatabase.tableKnowledgeLibraries} libraries
      WHERE libraries.user_id = ?
        AND libraries.id = ?
      LIMIT 1
      ''',
      [userId, id],
    );

    if (rows.isEmpty) {
      return null;
    }
    return KnowledgeLibraryRecord.fromMap(rows.first);
  }
}
