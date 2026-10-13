import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../common/source_document_file_store.dart';
import 'app_database.dart';
import 'models/import_record.dart';
import 'models/source_document_record.dart';

class ImportRecordRepository {
  ImportRecordRepository({
    AppDatabase? database,
    SourceDocumentFileStore? fileStore,
  }) : _database = database ?? AppDatabase.instance,
       _files = fileStore ?? const SourceDocumentFileStore();
  final AppDatabase _database;
  final SourceDocumentFileStore _files;
  static const resultTables = [
    'knowledge_cards',
    'review_outlines',
    'mindmap_texts',
    'practice_questions',
  ];

  Future<Map<int, int>> countsByLibrary(int userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT library_id, COUNT(*) n FROM import_records WHERE user_id = ? GROUP BY library_id',
      [userId],
    );
    return {
      for (final r in rows)
        if (r['library_id'] != null) r['library_id'] as int: r['n'] as int,
    };
  }

  Future<List<ImportRecord>> list(
    int userId, {
    int? libraryId,
    String query = '',
    String? source,
    bool oldestFirst = false,
  }) async {
    final db = await _database.database;
    final args = <Object?>[userId];
    var filter = 'r.user_id = ?';
    if (libraryId != null) {
      filter += ' AND r.library_id = ?';
      args.add(libraryId);
    }
    if (source != null) {
      filter +=
          ' AND EXISTS (SELECT 1 FROM source_documents s WHERE s.import_record_id = r.id AND s.source_type ${source == 'pdf' ? "IN ('pdf_document', 'pdf_page')" : "= 'camera_capture'"})';
    }
    if (query.trim().isNotEmpty) {
      // instr treats user input literally, including SQL wildcard characters.
      final searches = ["r.title", "r.tags_json"];
      final clauses = searches
          .map((s) => 'instr(lower($s), lower(?)) > 0')
          .toList();
      args.addAll(List.filled(searches.length, query.trim()));
      for (final entry in {
        'ocr_texts': "COALESCE(t.final_text, t.clean_text, t.raw_text)",
        'knowledge_cards': "t.title || ' ' || t.content",
        'review_outlines': "t.title || ' ' || t.outline_text",
        'mindmap_texts': 't.mindmap_text',
        'practice_questions':
            "t.question_text || ' ' || COALESCE(t.analysis_text, '')",
      }.entries) {
        clauses.add(
          'EXISTS (SELECT 1 FROM ${entry.key} t JOIN source_documents s ON s.id = t.document_id WHERE s.import_record_id = r.id AND s.user_id = r.user_id AND instr(lower(${entry.value}), lower(?)) > 0)',
        );
        args.add(query.trim());
      }
      filter += ' AND (${clauses.join(' OR ')})';
    }
    final rows = await db.rawQuery(
      'SELECT r.* FROM import_records r WHERE $filter ORDER BY r.created_at ${oldestFirst ? 'ASC' : 'DESC'}, r.id ${oldestFirst ? 'ASC' : 'DESC'}',
      args,
    );
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as int).toList();
    // A single scoped source query avoids one query per book on large shelves.
    final sources = await db.rawQuery(
      'SELECT s.*, EXISTS(SELECT 1 FROM ai_generation_tasks a WHERE a.document_id=s.id AND a.status=\'completed\') ai_done FROM source_documents s JOIN import_records r ON r.id=s.import_record_id WHERE r.user_id=? ORDER BY s.page_number, s.id',
      [userId],
    );
    final byRecord = <int, List<SourceDocumentRecord>>{};
    for (final s in sources) {
      (byRecord[s['import_record_id'] as int] ??= []).add(
        SourceDocumentRecord.fromMap(s),
      );
    }
    final counts = <int, Map<String, int>>{};
    for (final table in resultTables) {
      final stats = await db.rawQuery(
        'SELECT s.import_record_id id, COUNT(*) n FROM $table t JOIN source_documents s ON s.id=t.document_id WHERE s.user_id=? GROUP BY s.import_record_id',
        [userId],
      );
      for (final stat in stats) {
        (counts[stat['id'] as int] ??= {})[table] = stat['n'] as int;
      }
    }
    final wrong = await db.rawQuery(
      "SELECT s.import_record_id id, COUNT(*) n FROM practice_questions t JOIN source_documents s ON s.id=t.document_id WHERE s.user_id=? AND t.review_status='wrong' AND t.wrong_count>0 GROUP BY s.import_record_id",
      [userId],
    );
    for (final stat in wrong) {
      (counts[stat['id'] as int] ??= {})['wrong_questions'] = stat['n'] as int;
    }
    final tasks = await db.rawQuery(
      "SELECT s.import_record_id id, a.status, a.error_message FROM ai_generation_tasks a JOIN source_documents s ON s.id=a.document_id WHERE s.user_id=? AND a.id IN (SELECT MAX(id) FROM ai_generation_tasks GROUP BY document_id, task_type)",
      [userId],
    );
    return rows
        .where((r) => (byRecord[r['id']] ?? []).isNotEmpty)
        .map((r) {
          final id = r['id'] as int;
          final group = tasks.where((t) => t['id'] == id).toList();
          final pages = byRecord[id]!;
          return ImportRecord(
            id: id,
            userId: userId,
            libraryId: r['library_id'] as int?,
            title: r['title'] as String,
            createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
            sources: pages,
            counts: counts[id] ?? {},
            tags: (jsonDecode(r['tags_json'] as String? ?? '[]') as List)
                .cast<String>(),
            needsLibraryReview: r['needs_library_review'] == 1,
            runningTasks: group.where((t) => t['status'] == 'running').length,
            failedTasks: group.where((t) => t['status'] == 'failed').length,
            errors: [
              ...pages
                  .where((s) => s.ocrFailed)
                  .map((s) => s.ocrErrorMessage ?? 'OCR 识别失败'),
              ...group
                  .where((t) => t['status'] == 'failed')
                  .map((t) => t['error_message'] as String? ?? 'AI 生成失败'),
            ],
          );
        })
        .where((r) => ids.contains(r.id))
        .toList();
  }

  Future<ImportRecord?> get(int userId, int recordId) async =>
      (await list(userId)).where((r) => r.id == recordId).firstOrNull;
  // Preserve the existing snapshot API for source-version consumers.
  Future<
    ({
      int id,
      String text,
      String fingerprint,
      List<Map<String, Object?>> sources,
    })
  >
  sourceSnapshot(int userId, int documentId) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final docs = await txn.rawQuery(
        """SELECT d.*, o.raw_text, o.clean_text, o.final_text
        FROM source_documents d LEFT JOIN ocr_texts o ON o.document_id=d.id
        WHERE d.user_id=? AND (d.id=? OR d.import_record_id=(
          SELECT import_record_id FROM source_documents WHERE id=? AND user_id=?))
        ORDER BY d.page_number, d.id""",
        [userId, documentId, documentId, userId],
      );
      if (docs.isEmpty) throw StateError('资料不存在或无权访问');
      final sources = <Map<String, Object?>>[];
      for (final d in docs) {
        if (d['ocr_status'] != 'success' ||
            d['source_type'] == 'pdf_document') {
          continue;
        }
        final text =
            [d['final_text'], d['clean_text'], d['raw_text']]
                .where((t) => t != null && t.toString().trim().isNotEmpty)
                .firstOrNull
                ?.toString() ??
            '';
        if (text.isEmpty) continue;
        sources.add({
          'document_id': d['id'],
          'title': d['original_title'],
          'page': d['page_number'],
          'text': text,
        });
      }
      final content = jsonEncode({'sources': sources});
      final fingerprint = sha256.convert(utf8.encode(content)).toString();
      final recordId = docs.first['import_record_id'];
      if (recordId == null) throw StateError('资料缺少导入记录');
      await txn.insert('record_source_versions', {
        'record_id': recordId,
        'fingerprint': fingerprint,
        'content': content,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final version =
          (await txn.query(
                'record_source_versions',
                columns: ['id'],
                where: 'record_id=? AND fingerprint=?',
                whereArgs: [recordId, fingerprint],
              )).single['id']
              as int;
      return (
        id: version,
        fingerprint: fingerprint,
        sources: sources,
        text: sources
            .map((s) => '来源 #${s['document_id']}：${s['title']}\n${s['text']}')
            .join('\n\n'),
      );
    });
  }

  // Legacy callers can still move a record; this module now has one parent library.
  Future<void> setLibraries(int userId, int recordId, List<int> ids) async {
    if (ids.toSet().length != 1) throw ArgumentError('一条导入记录只能归档到一个知识库');
    await move(userId, recordId, ids.toSet().single);
  }

  Future<ImportRecord?> forDocument(int userId, int documentId) async {
    final db = await _database.database;
    final rows = await db.query(
      'source_documents',
      columns: ['import_record_id'],
      where: 'user_id=? AND id=?',
      whereArgs: [userId, documentId],
    );
    if (rows.isEmpty || rows.first['import_record_id'] == null) return null;
    return get(userId, rows.first['import_record_id'] as int);
  }

  Future<String> sourceText(ImportRecord record) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT s.id, s.page_number, COALESCE(NULLIF(t.final_text, \'\'), NULLIF(t.clean_text, \'\'), t.raw_text) text FROM source_documents s JOIN ocr_texts t ON t.document_id=s.id WHERE s.import_record_id=? AND s.user_id=? AND s.source_type!=\'pdf_document\' ORDER BY s.page_number, s.id',
      [record.id, record.userId],
    );
    return rows
        .where((r) => (r['text'] as String? ?? '').trim().isNotEmpty)
        .map(
          (r) => '【资料 ${r['id']} / 第 ${r['page_number'] ?? 1} 页】\n${r['text']}',
        )
        .join('\n\n');
  }

  Future<List<Map<String, Object?>>> results(
    int userId,
    int recordId,
    String type, {
    String query = '',
  }) async {
    final wrong = type == 'wrong_questions';
    final table = wrong ? 'practice_questions' : type;
    if (!resultTables.contains(table)) throw ArgumentError('未知成果类型');
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT t.*, s.original_title document_title FROM $table t JOIN source_documents s ON s.id=t.document_id WHERE s.import_record_id=? AND s.user_id=? ${wrong ? "AND t.review_status='wrong' AND t.wrong_count>0" : ''} ORDER BY t.id DESC',
      [recordId, userId],
    );
    return rows
        .where(
          (r) =>
              query.trim().isEmpty ||
              r.values
                  .join(' ')
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()),
        )
        .toList();
  }

  Future<void> rename(int userId, int id, String title) async {
    if (title.trim().isEmpty) throw ArgumentError('名称不能为空');
    final db = await _database.database;
    await db.update(
      'import_records',
      {
        'title': title.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id=? AND user_id=?',
      whereArgs: [id, userId],
    );
  }

  Future<void> setTags(int userId, int id, List<String> tags) async {
    final db = await _database.database;
    await db.update(
      'import_records',
      {
        'tags_json': jsonEncode(
          tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet().toList(),
        ),
      },
      where: 'id=? AND user_id=?',
      whereArgs: [id, userId],
    );
  }

  Future<void> move(int userId, int id, int libraryId) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      if ((await txn.query(
        'knowledge_libraries',
        where: 'id=? AND user_id=?',
        whereArgs: [libraryId, userId],
      )).isEmpty) {
        throw StateError('目标知识库不存在');
      }
      final record = await txn.query(
        'import_records',
        where: 'id=? AND user_id=?',
        whereArgs: [id, userId],
      );
      if (record.isEmpty) throw StateError('记录不存在');
      await txn.update(
        'import_records',
        {'library_id': libraryId, 'needs_library_review': 0},
        where: 'id=? AND user_id=?',
        whereArgs: [id, userId],
      );
      await txn.update(
        'source_documents',
        {'library_id': libraryId},
        where: 'import_record_id=? AND user_id=?',
        whereArgs: [id, userId],
      );
      final op = record.first['operation_id'] as String;
      if (op.startsWith('batch:')) {
        await txn.update(
          'document_batches',
          {'library_id': libraryId},
          where: 'id=? AND user_id=?',
          whereArgs: [int.parse(op.substring(6)), userId],
        );
      }
    });
  }

  Future<void> delete(int userId, int id) async {
    final db = await _database.database;
    final paths = <String?>[];
    await db.transaction((txn) async {
      final records = await txn.query(
        'import_records',
        where: 'id=? AND user_id=?',
        whereArgs: [id, userId],
      );
      if (records.isEmpty) return;
      final sources = await txn.query(
        'source_documents',
        where: 'import_record_id=? AND user_id=?',
        whereArgs: [id, userId],
      );
      paths.addAll(
        sources.expand(
          (s) => [
            s['image_path'] as String?,
            s['original_file_path'] as String?,
          ],
        ),
      );
      // Favorites are polymorphic; remove only those belonging to these sources.
      for (final entry in {
        'knowledge_cards': 'knowledge_card',
        'review_outlines': 'review_outline',
        'mindmap_texts': 'mindmap_text',
        'practice_questions': 'practice_question',
      }.entries) {
        final children = await txn.rawQuery(
          'SELECT t.id FROM ${entry.key} t JOIN source_documents s ON s.id=t.document_id WHERE s.import_record_id=? AND s.user_id=?',
          [id, userId],
        );
        for (final child in children) {
          await txn.delete(
            'favorites',
            where: 'user_id=? AND target_type=? AND target_id=?',
            whereArgs: [userId, entry.value, child['id']],
          );
          if (entry.key == 'practice_questions') {
            await txn.delete(
              'favorites',
              where: 'user_id=? AND target_type=? AND target_id=?',
              whereArgs: [userId, 'wrong_question', child['id']],
            );
          }
        }
      }
      await txn.delete(
        'source_documents',
        where: 'import_record_id=? AND user_id=?',
        whereArgs: [id, userId],
      );
      final op = records.first['operation_id'] as String;
      if (op.startsWith('batch:')) {
        final batch = await txn.query(
          'document_batches',
          where: 'id=? AND user_id=?',
          whereArgs: [int.parse(op.substring(6)), userId],
        );
        paths.addAll(batch.map((b) => b['original_file_path'] as String?));
        await txn.delete(
          'document_batches',
          where: 'id=? AND user_id=?',
          whereArgs: [int.parse(op.substring(6)), userId],
        );
      }
      await txn.delete(
        'import_records',
        where: 'id=? AND user_id=?',
        whereArgs: [id, userId],
      );
    });
    // Never remove a path that another record still references.
    for (final path in paths.toSet()) {
      if (path == null || path.isEmpty) continue;
      if ((await db.rawQuery(
        'SELECT id FROM source_documents WHERE image_path=? OR original_file_path=? UNION ALL SELECT id FROM document_batches WHERE original_file_path=?',
        [path, path, path],
      )).isEmpty) {
        await _files.deleteAllIfManaged([path]);
      }
    }
  }
}
