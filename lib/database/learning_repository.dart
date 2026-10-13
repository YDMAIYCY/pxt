import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'import_record_repository.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'models/learning_resource_record.dart';
import 'models/knowledge_graph_records.dart';

class LearningRepository {
  LearningRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;
  static String fingerprint(String text) =>
      sha256.convert(utf8.encode(text.trim())).toString();

  Future<int> sourceVersion(int userId, int documentId) async =>
      (await ImportRecordRepository(
        database: _database,
      ).sourceSnapshot(userId, documentId)).id;

  Future<void> _requireDocument(
    DatabaseExecutor db,
    int userId,
    int documentId,
  ) async {
    final rows = await db.query(
      'source_documents',
      columns: ['id'],
      where: 'id = ? AND user_id = ?',
      whereArgs: [documentId, userId],
    );
    if (rows.isEmpty) throw StateError('资料不存在或无权访问');
  }

  Future<List<LearningResourceRecord>> resources(
    int userId,
    int documentId, {
    String? type,
  }) async {
    final db = await _database.database;
    await _requireDocument(db, userId, documentId);
    final rows = await db.query(
      'learning_resources',
      where: '''document_id IN (SELECT id FROM source_documents WHERE
        import_record_id = (SELECT import_record_id FROM source_documents WHERE id = ?))
        ${type == null ? '' : ' AND type = ?'}''',
      whereArgs: [documentId, ?type],
      orderBy: 'version DESC, id DESC',
    );
    return rows.map(LearningResourceRecord.fromMap).toList();
  }

  Future<LearningResourceRecord> saveResource({
    required int userId,
    required int documentId,
    required String type,
    required String title,
    required String content,
    required String inputText,
    required String model,
    int? sourceVersionId,
  }) async {
    final snapshot = await ImportRecordRepository(
      database: _database,
    ).sourceSnapshot(userId, documentId);
    final db = await _database.database;
    return db.transaction((txn) async {
      await _requireDocument(txn, userId, documentId);
      final versions = await txn.rawQuery(
        'SELECT COALESCE(MAX(version), 0) AS version FROM learning_resources WHERE document_id = ? AND type = ?',
        [documentId, type],
      );
      final id = await txn.insert('learning_resources', {
        'document_id': documentId,
        'source_version_id': sourceVersionId ?? snapshot.id,
        'type': type,
        'title': title,
        'content': content,
        'input_fingerprint': fingerprint(inputText),
        'model': model,
        'version': (versions.first['version'] as int) + 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return LearningResourceRecord.fromMap(
        (await txn.query(
          'learning_resources',
          where: 'id = ?',
          whereArgs: [id],
        )).single,
      );
    });
  }

  Future<List<int>> libraryIds(int userId, int documentId) async {
    final db = await _database.database;
    await _requireDocument(db, userId, documentId);
    return (await db.query(
      'document_library_links',
      where: 'document_id = ?',
      whereArgs: [documentId],
    )).map((r) => r['library_id'] as int).toList();
  }

  Future<void> setLibraries(
    int userId,
    int documentId,
    List<int> libraryIds,
  ) async {
    if (libraryIds.isEmpty) throw ArgumentError('至少选择一个知识库');
    final record = await ImportRecordRepository(
      database: _database,
    ).forDocument(userId, documentId);
    if (record != null) {
      await ImportRecordRepository(
        database: _database,
      ).setLibraries(userId, record.id, libraryIds);
      return;
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      await _requireDocument(txn, userId, documentId);
      for (final id in libraryIds.toSet()) {
        final rows = await txn.query(
          'knowledge_libraries',
          where: 'id = ? AND user_id = ?',
          whereArgs: [id, userId],
        );
        if (rows.isEmpty) throw StateError('知识库不存在或无权访问');
      }
      final scope = (await txn.query(
        'source_documents',
        columns: ['source_type', 'batch_id'],
        where: 'id = ?',
        whereArgs: [documentId],
      )).single;
      if (scope['source_type'] == 'pdf_document' && scope['batch_id'] != null) {
        final batchId = scope['batch_id'] as int;
        await txn.update(
          'document_batches',
          {'library_id': libraryIds.first},
          where: 'id = ?',
          whereArgs: [batchId],
        );
        await txn.update(
          'source_documents',
          {'library_id': libraryIds.first},
          where: 'batch_id = ? AND user_id = ?',
          whereArgs: [batchId, userId],
        );
        final pages = await txn.query(
          'source_documents',
          columns: ['id'],
          where: 'batch_id = ? AND user_id = ?',
          whereArgs: [batchId, userId],
        );
        for (final page in pages) {
          await txn.delete(
            'document_library_links',
            where: 'document_id = ?',
            whereArgs: [page['id']],
          );
          for (final id in libraryIds.toSet()) {
            await txn.insert('document_library_links', {
              'document_id': page['id'],
              'library_id': id,
            });
          }
        }
      }
      await txn.update(
        'source_documents',
        {'library_id': libraryIds.first},
        where: 'id = ?',
        whereArgs: [documentId],
      );
      await txn.delete(
        'document_library_links',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      for (final id in libraryIds.toSet()) {
        await txn.insert('document_library_links', {
          'document_id': documentId,
          'library_id': id,
        });
      }
    });
  }

  Future<List<KnowledgeConceptRecord>> concepts(
    int userId,
    int documentId,
  ) async {
    final db = await _database.database;
    await _requireDocument(db, userId, documentId);
    return (await db.rawQuery(
      '''SELECT c.* FROM knowledge_concepts c
      JOIN concept_documents cd ON cd.concept_id = c.id
      WHERE cd.document_id IN (SELECT id FROM source_documents WHERE
        import_record_id = (SELECT import_record_id FROM source_documents WHERE id = ?))
        AND c.user_id = ? GROUP BY c.id ORDER BY c.id''',
      [documentId, userId],
    )).map(KnowledgeConceptRecord.fromMap).toList();
  }

  Future<void> editConcept(
    int userId,
    int id,
    String name,
    String summary,
  ) async {
    if (name.trim().isEmpty) throw ArgumentError('知识点名称不能为空');
    final db = await _database.database;
    final count = await db.update(
      'knowledge_concepts',
      {
        'name': name.trim(),
        'summary': summary.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
    if (count == 0) throw StateError('知识点不存在');
  }

  Future<void> mergeConcepts(int userId, int fromId, int intoId) async {
    if (fromId == intoId) return;
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'knowledge_concepts',
        where: 'user_id = ? AND id IN (?, ?)',
        whereArgs: [userId, fromId, intoId],
      );
      if (rows.length != 2) throw StateError('只能合并自己的知识点');
      await txn.execute(
        'INSERT OR IGNORE INTO concept_documents SELECT ?, document_id FROM concept_documents WHERE concept_id = ?',
        [intoId, fromId],
      );
      await txn.execute(
        'INSERT OR IGNORE INTO question_concepts SELECT question_id, ? FROM question_concepts WHERE concept_id = ?',
        [intoId, fromId],
      );
      for (final table in [
        'learning_errors',
        'learning_attempts',
        'learning_resources',
      ]) {
        await txn.update(
          table,
          {'concept_id': intoId},
          where: 'concept_id = ?',
          whereArgs: [fromId],
        );
      }
      for (final column in ['from_concept_id', 'to_concept_id']) {
        await txn.update(
          'knowledge_concept_links',
          {column: intoId},
          where: '$column = ?',
          whereArgs: [fromId],
        );
      }
      await txn.delete(
        'knowledge_concept_links',
        where: 'from_concept_id = to_concept_id',
      );
      await txn.delete(
        'knowledge_concepts',
        where: 'id = ?',
        whereArgs: [fromId],
      );
    });
  }

  Future<void> linkConcepts(
    int userId,
    int fromId,
    int toId,
    String relation,
  ) async {
    if (fromId == toId || !['前置', '相似', '应用', '对比'].contains(relation)) {
      throw ArgumentError('请选择有效关系');
    }
    final db = await _database.database;
    final rows = await db.query(
      'knowledge_concepts',
      columns: ['id'],
      where: 'user_id = ? AND id IN (?, ?)',
      whereArgs: [userId, fromId, toId],
    );
    if (rows.length != 2) throw StateError('知识点不存在或无权访问');
    await db.insert('knowledge_concept_links', {
      'user_id': userId,
      'from_concept_id': fromId,
      'to_concept_id': toId,
      'relation_label': relation,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> recordAttempt({
    required int userId,
    required int documentId,
    int? conceptId,
    int? questionId,
    required String origin,
    required String prompt,
    required String answer,
    required int score,
    required String feedback,
    required bool hasError,
  }) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await _requireDocument(txn, userId, documentId);
      if (conceptId != null) {
        final scoped = await txn.rawQuery(
          'SELECT c.id FROM knowledge_concepts c JOIN concept_documents cd ON cd.concept_id = c.id WHERE c.id = ? AND c.user_id = ? AND cd.document_id = ?',
          [conceptId, userId, documentId],
        );
        if (scoped.isEmpty) throw StateError('知识点与来源不匹配');
      }
      final row = <String, Object?>{
        'user_id': userId,
        'document_id': documentId,
        'concept_id': conceptId,
        'question_id': questionId,
        'origin': origin,
        'prompt': prompt,
        'answer': answer,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };
      await txn.insert('learning_attempts', {
        ...row,
        'score': score.clamp(0, 100),
        'feedback': feedback,
      });
      if (hasError) {
        await txn.insert('learning_errors', {...row, 'correction': feedback});
      }
      if (conceptId != null) {
        await txn.update(
          'knowledge_concepts',
          {
            'mastery_score': score.clamp(0, 100),
            'weakness_score': hasError ? 100 - score.clamp(0, 100) : 0,
            'updated_at': row['created_at'],
          },
          where: 'id = ? AND user_id = ?',
          whereArgs: [conceptId, userId],
        );
      }
    });
  }

  Future<List<LearningErrorRecord>> errors(
    int userId, {
    int? documentId,
    int? conceptId,
  }) async {
    final db = await _database.database;
    return (await db.query(
      'learning_errors',
      where:
          'user_id = ? AND resolved = 0${documentId == null ? '' : ' AND document_id = ?'}${conceptId == null ? '' : ' AND concept_id = ?'}',
      whereArgs: [userId, ?documentId, ?conceptId],
      orderBy: 'created_at DESC',
    )).map(LearningErrorRecord.fromMap).toList();
  }

  Future<List<int>> questionsForConcept(int userId, int conceptId) async {
    final db = await _database.database;
    return (await db.rawQuery(
      'SELECT qc.question_id FROM question_concepts qc JOIN knowledge_concepts c ON c.id = qc.concept_id WHERE c.user_id = ? AND c.id = ?',
      [userId, conceptId],
    )).map((r) => r['question_id'] as int).toList();
  }

  Future<void> recordQuestionAttempt(
    int userId,
    int questionId,
    bool correct,
    String answer, {
    int? conceptId,
    String origin = 'practice',
    String? prompt,
    String? feedback,
    int? score,
  }) async {
    final db = await _database.database;
    final questions = await db.rawQuery(
      'SELECT q.* FROM practice_questions q JOIN source_documents d ON d.id = q.document_id WHERE q.id = ? AND d.user_id = ?',
      [questionId, userId],
    );
    if (questions.isEmpty) throw StateError('题目不存在');
    final question = questions.single;
    var conceptIds = (await db.rawQuery(
      'SELECT concept_id FROM question_concepts WHERE question_id = ?',
      [questionId],
    )).map((r) => r['concept_id'] as int).toList();
    if (conceptId != null) conceptIds = [conceptId];
    if (conceptIds.isEmpty) {
      final candidates = await concepts(userId, question['document_id'] as int);
      final text = '${question['question_text']} ${question['answer_text']}';
      conceptIds = candidates
          .where((c) => text.toLowerCase().contains(c.name.toLowerCase()))
          .map((c) => c.id)
          .toList();
      for (final id in conceptIds) {
        await db.insert('question_concepts', {
          'question_id': questionId,
          'concept_id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    for (final id in conceptIds.isEmpty ? <int?>[null] : conceptIds) {
      await recordAttempt(
        userId: userId,
        documentId: question['document_id'] as int,
        conceptId: id,
        questionId: questionId,
        origin: origin,
        prompt: prompt ?? question['question_text'] as String,
        answer: answer,
        score: score ?? (question['mastery_score'] as int? ?? 0),
        feedback: feedback ?? (question['analysis_text'] as String? ?? ''),
        hasError: !correct,
      );
    }
    if (correct && origin == 'practice') {
      await db.update(
        'learning_errors',
        {'resolved': 1},
        where: 'user_id = ? AND question_id = ? AND prompt = ?',
        whereArgs: [userId, questionId, question['question_text']],
      );
    }
  }

  Future<void> resolveError(int userId, int id) async {
    final db = await _database.database;
    await db.update(
      'learning_errors',
      {'resolved': 1},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<int> prepareErrorRetry(int userId, int errorId) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'learning_errors',
        where: 'id = ? AND user_id = ?',
        whereArgs: [errorId, userId],
      );
      if (rows.isEmpty) throw StateError('学习错误不存在');
      final error = LearningErrorRecord.fromMap(rows.single);
      final old = error.questionId == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'practice_questions',
              where: 'id = ? AND question_text = ?',
              whereArgs: [error.questionId, error.prompt],
            );
      if (old.isNotEmpty) return error.questionId!;
      String standardAnswer = error.correction;
      try {
        standardAnswer =
            (jsonDecode(error.correction) as Map)['standard_answer']
                ?.toString() ??
            error.correction;
      } catch (_) {}
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await txn.insert('practice_questions', {
        'document_id': error.documentId,
        'question_text': error.prompt,
        'answer_text': standardAnswer,
        'analysis_text': error.correction,
        'question_kind': 'oral',
        'review_status': 'wrong',
        'wrong_count': 1,
        'last_user_answer': error.answer,
        'created_at': now,
        'next_review_at': now,
      });
      if (error.conceptId != null) {
        await txn.insert('question_concepts', {
          'question_id': id,
          'concept_id': error.conceptId,
        });
      }
      await txn.update(
        'learning_errors',
        {'question_id': id},
        where: 'id = ?',
        whereArgs: [errorId],
      );
      return id;
    });
  }

  Future<void> reviewCard(
    int userId,
    int resourceId,
    int index,
    int rating,
  ) async {
    if (rating < 1 || rating > 4) throw ArgumentError('评分无效');
    final db = await _database.database;
    final resources = await db.rawQuery(
      'SELECT r.* FROM learning_resources r JOIN source_documents d ON d.id = r.document_id WHERE r.id = ? AND d.user_id = ?',
      [resourceId, userId],
    );
    if (resources.isEmpty) throw StateError('记忆卡不存在');
    final data = jsonDecode(resources.single['content'] as String) as Map;
    final cards = data['cards'] as List;
    if (index < 0 || index >= cards.length) throw ArgumentError('卡片不存在');
    final prior = await db.query(
      'flashcard_reviews',
      where: 'resource_id = ? AND card_index = ?',
      whereArgs: [resourceId, index],
    );
    final now = DateTime.now().toUtc();
    final state = prior.firstOrNull?['fsrs_state_json'] as String?;
    final card = state == null
        ? fsrs.Card(cardId: index)
        : fsrs.Card.fromMap(
            Map<String, dynamic>.from(jsonDecode(state) as Map),
          );
    final reviewed = fsrs.Scheduler(
      enableFuzzing: false,
    ).reviewCard(card, fsrs.Rating.fromValue(rating), reviewDateTime: now);
    await db.transaction((txn) async {
      await txn.insert('flashcard_reviews', {
        'resource_id': resourceId,
        'card_index': index,
        'rating': rating,
        'interval_days': reviewed.card.due.difference(now).inDays,
        'next_review_at': reviewed.card.due.toIso8601String(),
        'fsrs_state_json': jsonEncode(reviewed.card.toMap()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('flashcard_review_history', {
        'resource_id': resourceId,
        'card_index': index,
        'review_log': jsonEncode(reviewed.reviewLog.toMap()),
        'created_at': now.toIso8601String(),
      });
    });
  }

  Future<Map<int, DateTime>> cardSchedule(int resourceId) async {
    final db = await _database.database;
    return {
      for (final row in await db.query(
        'flashcard_reviews',
        where: 'resource_id = ?',
        whereArgs: [resourceId],
      ))
        row['card_index'] as int: DateTime.parse(
          row['next_review_at'] as String,
        ).toLocal(),
    };
  }

  Future<List<LearningResourceRecord>> dueFlashcards(int userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT r.* FROM learning_resources r
      JOIN source_documents d ON d.id = r.document_id
      WHERE d.user_id = ? AND r.type = 'flashcards'
        AND r.id IN (SELECT MAX(id) FROM learning_resources WHERE type = 'flashcards' GROUP BY document_id)
        AND EXISTS (SELECT 1 FROM json_each(r.content, '\$.cards') cards
          LEFT JOIN flashcard_reviews f ON f.resource_id = r.id AND f.card_index = CAST(cards.key AS INTEGER)
          WHERE f.next_review_at IS NULL OR f.next_review_at <= ?)
      ORDER BY r.created_at ASC''',
      [userId, DateTime.now().toUtc().toIso8601String()],
    );
    return rows.map(LearningResourceRecord.fromMap).toList();
  }

  Future<Map<String, Object?>> report(int userId, int documentId) async {
    final db = await _database.database;
    await _requireDocument(db, userId, documentId);
    return (await db.rawQuery(
      '''SELECT COUNT(*) AS attempts, COALESCE(AVG(score), 0) AS average_score
      FROM learning_attempts WHERE user_id = ? AND document_id IN (
        SELECT id FROM source_documents WHERE user_id = ? AND
        (id = ? OR import_record_id =
          (SELECT import_record_id FROM source_documents WHERE id = ? AND user_id = ?)))''',
      [userId, userId, documentId, documentId, userId],
    )).single;
  }
}
