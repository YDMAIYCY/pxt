import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'models/knowledge_library_record.dart';

// ========== 知识库仓库 ==========
// 管理用户自定义知识库的创建、读取和删除。

class KnowledgeLibraryRepository {
  KnowledgeLibraryRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

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
          WHERE documents.library_id = libraries.id
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

      await txn.delete(
        AppDatabase.tableSourceDocuments,
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
          WHERE documents.library_id = libraries.id
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
