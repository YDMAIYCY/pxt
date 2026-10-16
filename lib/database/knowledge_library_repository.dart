import 'package:sqflite/sqflite.dart';
import 'dart:convert';

import '../common/source_document_file_store.dart';
import 'app_database.dart';
import 'models/knowledge_library_record.dart';

// ========== 知识库仓库 ==========
// 管理用户自定义知识库的创建、读取和删除。

/// 知识库的学习概览：知识点/题目规模与掌握进度，供首页工作台使用。
class KnowledgeLibraryStudySummary {
  const KnowledgeLibraryStudySummary({
    required this.libraryId,
    required this.name,
    required this.coverTheme,
    required this.coverColor,
    required this.conceptCount,
    required this.questionCount,
    required this.progress,
    this.lastActiveAt,
  });

  final int libraryId, coverColor, conceptCount, questionCount, progress;
  final String name, coverTheme;
  final DateTime? lastActiveAt;

  bool get hasContent => conceptCount + questionCount > 0;
}

/// 跨知识库的内容检索结果：知识点、练习题或资料。
class StudySearchHit {
  const StudySearchHit({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.conceptId,
    this.questionId,
    this.documentId,
  });

  final String kind, title, subtitle;
  final int? conceptId, questionId, documentId;
}

class KnowledgeLibraryRepository {
  KnowledgeLibraryRepository({
    AppDatabase? database,
    SourceDocumentFileStore? fileStore,
  }) : _database = database ?? AppDatabase.instance,
       _fileStore = fileStore ?? const SourceDocumentFileStore();

  final AppDatabase _database;
  final SourceDocumentFileStore _fileStore;

  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId, {String source = 'all'}) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await _ensureDefaultLibrary(db, userId);

    final rows = await db.rawQuery(
      '''
      SELECT
        libraries.*,
        COALESCE((SELECT c.container_type FROM feishu_containers c WHERE c.user_id=libraries.user_id AND c.library_id=libraries.id LIMIT 1), 'local') AS source_type,
        (SELECT c.sync_status FROM feishu_containers c WHERE c.user_id=libraries.user_id AND c.library_id=libraries.id
          ORDER BY CASE c.sync_status WHEN 'expired' THEN 0 WHEN 'syncing' THEN 1 WHEN 'failed' THEN 2 WHEN 'pending' THEN 3 ELSE 4 END LIMIT 1) AS sync_status,
        (SELECT MAX(c.synced_at) FROM feishu_containers c WHERE c.user_id=libraries.user_id AND c.library_id=libraries.id) AS synced_at,
        (
          SELECT COUNT(*)
          FROM ${AppDatabase.tableSourceDocuments} documents
          WHERE documents.library_id = libraries.id
        ) AS document_count
      FROM ${AppDatabase.tableKnowledgeLibraries} libraries
      WHERE libraries.user_id = ?
        ${source == 'feishu' ? 'AND EXISTS' : source == 'local' ? 'AND NOT EXISTS' : ''}
        ${source == 'all' ? '' : '(SELECT 1 FROM feishu_containers c WHERE c.library_id=libraries.id AND c.user_id=libraries.user_id)'}
      ORDER BY libraries.updated_at DESC, libraries.id ASC
      ''',
      [userId],
    );

    return rows.map(KnowledgeLibraryRecord.fromMap).toList(growable: false);
  }

  /// 最近有学习活动的知识库，含知识点/题目规模与掌握进度。首页“我的知识库”使用。
  /// 按最近活动倒序返回全部知识库，由调用方决定展示数量。
  Future<List<KnowledgeLibraryStudySummary>> fetchStudySummaries({
    required int userId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    await _ensureDefaultLibrary(db, userId);

    final rows = await db.rawQuery(
      '''
      SELECT
        libraries.id,
        libraries.name,
        libraries.cover_theme,
        libraries.cover_color,
        libraries.updated_at,
        (SELECT COUNT(*) FROM knowledge_concepts c
          WHERE c.user_id = libraries.user_id AND c.library_id = libraries.id) AS concept_count,
        (SELECT COALESCE(AVG(c.mastery_score), 0) FROM knowledge_concepts c
          WHERE c.user_id = libraries.user_id AND c.library_id = libraries.id) AS concept_mastery,
        (SELECT COUNT(*) FROM practice_questions q
          JOIN source_documents d ON d.id = q.document_id
          WHERE d.user_id = libraries.user_id AND d.library_id = libraries.id) AS question_count,
        (SELECT COALESCE(AVG(q.mastery_score), 0) FROM practice_questions q
          JOIN source_documents d ON d.id = q.document_id
          WHERE d.user_id = libraries.user_id AND d.library_id = libraries.id) AS question_mastery,
        (SELECT MAX(d.created_at) FROM source_documents d
          WHERE d.user_id = libraries.user_id AND d.library_id = libraries.id) AS document_active_at,
        (SELECT MAX(c.updated_at) FROM knowledge_concepts c
          WHERE c.user_id = libraries.user_id AND c.library_id = libraries.id) AS concept_active_at,
        (SELECT MAX(s.created_at) FROM practice_submissions s
          JOIN practice_questions q ON q.id = s.question_id
          JOIN source_documents d ON d.id = q.document_id
          WHERE s.user_id = libraries.user_id AND d.library_id = libraries.id) AS practice_active_at
      FROM ${AppDatabase.tableKnowledgeLibraries} libraries
      WHERE libraries.user_id = ?
      ''',
      [userId],
    );

    final summaries = rows.map((row) {
      final conceptCount = _readCount(row['concept_count']);
      final questionCount = _readCount(row['question_count']);
      return KnowledgeLibraryStudySummary(
        libraryId: row['id'] as int,
        name: (row['name'] as String?)?.trim() ?? '未命名知识库',
        coverTheme: row['cover_theme'] as String? ?? 'math',
        coverColor: _readCount(row['cover_color']),
        conceptCount: conceptCount,
        questionCount: questionCount,
        progress: conceptCount > 0
            ? _readCount(row['concept_mastery'])
            : questionCount > 0
            ? _readCount(row['question_mastery'])
            : 0,
        lastActiveAt: _latestMoment([
          row['updated_at'],
          row['document_active_at'],
          row['concept_active_at'],
          row['practice_active_at'],
        ]),
      );
    }).toList(growable: false);

    final sorted = summaries.toList()
      ..sort((a, b) {
        final left = a.lastActiveAt;
        final right = b.lastActiveAt;
        if (left == null && right == null) {
          return a.libraryId.compareTo(b.libraryId);
        }
        if (left == null) return 1;
        if (right == null) return -1;
        final order = right.compareTo(left);
        return order == 0 ? a.libraryId.compareTo(b.libraryId) : order;
      });
    return sorted;
  }

  /// 在用户自己的知识点、练习题和资料里做关键词检索。
  Future<List<StudySearchHit>> searchStudyContent({
    required int userId,
    required String query,
    int limit = 12,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final pattern = _likePattern(keyword);

    final concepts = await db.rawQuery(
      '''
      SELECT c.id, c.name, COALESCE(l.name, '') AS library_name
      FROM knowledge_concepts c
      LEFT JOIN source_documents d ON d.id = c.document_id AND d.user_id = c.user_id
      LEFT JOIN ${AppDatabase.tableKnowledgeLibraries} l
        ON l.id = d.library_id AND l.user_id = c.user_id
      WHERE c.user_id = ? AND c.name LIKE ? ESCAPE '\\'
      ORDER BY c.updated_at DESC, c.id DESC LIMIT ?
      ''',
      [userId, pattern, limit],
    );
    final questions = await db.rawQuery(
      '''
      SELECT q.id, q.question_text, q.document_id,
        COALESCE(d.original_title, '') AS document_title
      FROM practice_questions q
      JOIN source_documents d ON d.id = q.document_id
      WHERE d.user_id = ? AND q.question_text LIKE ? ESCAPE '\\'
      ORDER BY q.created_at DESC, q.id DESC LIMIT ?
      ''',
      [userId, pattern, limit],
    );
    final documents = await db.rawQuery(
      '''
      SELECT d.id, d.original_title, COALESCE(l.name, '') AS library_name
      FROM source_documents d
      LEFT JOIN ${AppDatabase.tableKnowledgeLibraries} l
        ON l.id = d.library_id AND l.user_id = d.user_id
      WHERE d.user_id = ? AND d.original_title LIKE ? ESCAPE '\\'
      ORDER BY d.created_at DESC, d.id DESC LIMIT ?
      ''',
      [userId, pattern, limit],
    );

    final hits = <StudySearchHit>[
      ...concepts.map((row) {
        final library = (row['library_name'] as String?)?.trim() ?? '';
        return StudySearchHit(
          kind: '知识点',
          title: (row['name'] as String?)?.trim() ?? '',
          subtitle: library.isEmpty ? '知识点' : '知识点 · $library',
          conceptId: row['id'] as int,
        );
      }),
      ...questions.map((row) {
        final document = (row['document_title'] as String?)?.trim() ?? '';
        return StudySearchHit(
          kind: '练习题',
          title: (row['question_text'] as String?)?.trim() ?? '',
          subtitle: document.isEmpty ? '练习题' : '练习题 · $document',
          questionId: row['id'] as int,
          documentId: row['document_id'] as int,
        );
      }),
      ...documents.map((row) {
        final library = (row['library_name'] as String?)?.trim() ?? '';
        return StudySearchHit(
          kind: '资料',
          title: (row['original_title'] as String?)?.trim() ?? '',
          subtitle: library.isEmpty ? '资料' : '资料 · $library',
          documentId: row['id'] as int,
        );
      }),
    ];
    return hits
        .where((hit) => hit.title.isNotEmpty)
        .take(limit)
        .toList(growable: false);
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
    String coverTheme = 'math',
    int coverColor = 0xFF5B90FF,
    String? operationKey,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('知识库名称不能为空');
    }

    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final libraryId = await db.transaction((txn) async {
      if(operationKey!=null) {
        final receipt=await txn.query('agent_operation_receipts',where:'operation_key=? AND user_id=?',whereArgs:[operationKey,userId]);
        if(receipt.isNotEmpty) return (jsonDecode(receipt.single['result_json'] as String) as Map)['libraryId'] as int;
      }
      final duplicated = await txn.query(
        AppDatabase.tableKnowledgeLibraries,
        columns: ['id'],
        where: 'user_id = ? AND name = ?',
        whereArgs: [userId, trimmedName],
        limit: 1,
      );
      if (duplicated.isNotEmpty) {
        if(operationKey!=null) {
          final id=duplicated.single['id'] as int;
          await txn.insert('agent_operation_receipts',{'operation_key':operationKey,'user_id':userId,'result_json':jsonEncode({'libraryId':id})});
          return id;
        }
        throw StateError('已存在同名知识库');
      }

      final id=await txn.insert(AppDatabase.tableKnowledgeLibraries, {
        'user_id': userId,
        'name': trimmedName,
        'description': description?.trim(),
        'cover_theme': coverTheme,
        'cover_color': coverColor,
        'created_at': now,
        'updated_at': now,
      });
      if(operationKey!=null) await txn.insert('agent_operation_receipts',{'operation_key':operationKey,'user_id':userId,'result_json':jsonEncode({'libraryId':id})});
      return id;
    });

    final library = await _findLibraryById(db, userId: userId, id: libraryId);
    if (library == null) {
      throw StateError('知识库创建后读取失败');
    }
    return library;
  }

  Future<KnowledgeLibraryRecord> updateLibrary({
    required int userId,
    required int libraryId,
    required String name,
    String? description,
    required String coverTheme,
    required int coverColor,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('知识库名称不能为空');
    final db = await _database.database;
    await db.transaction((txn) async {
      final duplicate = await txn.query(
        'knowledge_libraries',
        where: 'user_id=? AND name=? AND id!=?',
        whereArgs: [userId, name.trim(), libraryId],
      );
      if (duplicate.isNotEmpty) throw StateError('已存在同名知识库');
      final n = await txn.update(
        'knowledge_libraries',
        {
          'name': name.trim(),
          'description': description?.trim(),
          'cover_theme': coverTheme,
          'cover_color': coverColor,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id=? AND user_id=?',
        whereArgs: [libraryId, userId],
      );
      if (n == 0) throw StateError('知识库不存在');
    });
    return (await _findLibraryById(db, userId: userId, id: libraryId))!;
  }

  // Removing a classification never discards learning history.
  Future<void> deleteLibraryKeepingRecords({
    required int userId,
    required int libraryId,
  }) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final current = await txn.query(
        'knowledge_libraries',
        where: 'id=? AND user_id=?',
        whereArgs: [libraryId, userId],
      );
      if (current.isEmpty) throw StateError('知识库不存在');
      final others = await txn.query(
        'knowledge_libraries',
        where: 'user_id=? AND id!=? AND name=?',
        whereArgs: [userId, libraryId, '待整理'],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final target = others.isEmpty
          ? await txn.insert('knowledge_libraries', {
              'user_id': userId,
              'name': '待整理',
              'description': '删除知识库后保留的资料',
              'created_at': now,
              'updated_at': now,
            })
          : others.first['id'] as int;
      for (final table in [
        'import_records',
        'source_documents',
        'document_batches',
        'feishu_documents',
      ]) {
        await txn.update(
          table,
          {'library_id': target},
          where: 'user_id=? AND library_id=?',
          whereArgs: [userId, libraryId],
        );
      }
      await txn.delete(
        'knowledge_libraries',
        where: 'id=? AND user_id=?',
        whereArgs: [libraryId, userId],
      );
    });
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
        libraries.*,
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

int _readCount(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _latestMoment(List<Object?> rawValues) {
  DateTime? latest;
  for (final raw in rawValues) {
    final moment = DateTime.tryParse((raw as String?) ?? '')?.toLocal();
    if (moment != null && (latest == null || moment.isAfter(latest))) {
      latest = moment;
    }
  }
  return latest;
}

String _likePattern(String keyword) => '%${keyword
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_')}%';
