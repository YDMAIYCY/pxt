import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'app_database.dart';
import 'import_record_repository.dart';
import 'models/ai_result_records.dart';

class PracticeScope {
  const PracticeScope({
    required this.userId,
    this.libraryId,
    this.recordId,
    this.conceptId,
    this.documentId,
    this.wrongOnly = false,
  });
  final int userId;
  final int? libraryId;
  final int? recordId;
  final int? conceptId;
  final int? documentId;
  final bool wrongOnly;
  String get ownershipClause =>
      '''d.user_id = ?
    ${libraryId == null ? '' : '''AND d.library_id = ? AND EXISTS (SELECT 1 FROM knowledge_libraries l
      WHERE l.id=d.library_id AND l.user_id=d.user_id)'''}
    ${recordId == null ? '' : 'AND d.import_record_id = ?'}
    ${conceptId == null ? '' : '''AND EXISTS (SELECT 1 FROM question_concepts qc
          WHERE qc.question_id = q.id AND qc.concept_id = ?)'''}
    ${documentId == null ? '' : 'AND d.id = ?'}''';
  String get clause =>
      '$ownershipClause '
      '${wrongOnly ? "AND q.wrong_count > 0 AND q.review_status != 'mastered'" : ''}';
  List<Object?> get args => [
    userId,
    ?libraryId,
    ?recordId,
    ?conceptId,
    ?documentId,
  ];
}

class PracticeSubmission {
  const PracticeSubmission({
    required this.id,
    required this.correct,
    required this.revision,
    required this.answer,
    required this.createdAt,
  });
  final int id;
  final bool correct;
  final int revision;
  final String answer;
  final DateTime createdAt;
  factory PracticeSubmission.fromMap(Map<String, Object?> row) =>
      PracticeSubmission(
        id: row['id'] as int,
        correct: row['correct'] == 1,
        revision: row['revision'] as int,
        answer: row['answer'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

class MasteryEvidence {
  const MasteryEvidence({
    required this.distinctQuestions,
    required this.correctCount,
    required this.delayedSuccess,
    required this.mastered,
    required this.nextReview,
  });
  final int distinctQuestions;
  final int correctCount;
  final bool delayedSuccess;
  final bool mastered;
  final DateTime? nextReview;
  String get label => mastered
      ? (nextReview?.isBefore(DateTime.now()) == true ? '到期复习' : '已掌握')
      : correctCount == 0
      ? '学习中'
      : '待巩固';
}

class PracticeSessionRepository {
  PracticeSessionRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;
  Future<List<PracticeQuestionWithDocument>> questions(
    PracticeScope scope, {
    bool dueOnly = false,
    List<int>? questionIds,
    int limit = 500,
  }) async {
    if (questionIds?.isEmpty == true) return [];
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT q.*, d.original_title AS document_title
      FROM practice_questions q JOIN source_documents d ON d.id = q.document_id
      WHERE ${scope.clause}
      ${questionIds == null ? '' : 'AND q.id IN (${List.filled(questionIds.length, '?').join(',')})'}
      ${dueOnly ? 'AND (q.next_review_at IS NULL OR q.next_review_at <= ?)' : ''}
      ORDER BY COALESCE(q.next_review_at, q.created_at), q.id LIMIT ?''',
      [
        ...scope.args,
        if (questionIds != null) ...questionIds,
        if (dueOnly) DateTime.now().toUtc().toIso8601String(),
        limit,
      ],
    );
    return rows
        .map(
          (r) => PracticeQuestionWithDocument(
            question: PracticeQuestionRecord.fromMap(r),
            documentTitle: r['document_title'] as String? ?? '来源资料',
          ),
        )
        .toList();
  }

  Future<PracticeSubmission> submit({
    required PracticeScope scope,
    required int questionId,
    required String requestId,
    required String answer,
    required bool correct,
    DateTime? now,
  }) async {
    if (answer.trim().isEmpty || requestId.trim().isEmpty) {
      throw ArgumentError('答案和提交标识不能为空');
    }
    final db = await _database.database;
    final owned = await db.rawQuery(
      '''SELECT q.document_id FROM practice_questions q
      JOIN source_documents d ON d.id = q.document_id
      WHERE q.id = ? AND ${scope.ownershipClause}''',
      [questionId, ...scope.args],
    );
    if (owned.isEmpty) throw StateError('题目不在当前知识库或记录范围内');
    final source = await ImportRecordRepository(
      database: _database,
    ).sourceSnapshot(scope.userId, owned.single['document_id'] as int);
    return db.transaction((txn) async {
      final existing = await txn.query(
        'practice_submissions',
        where: 'user_id = ? AND request_id = ?',
        whereArgs: [scope.userId, requestId],
      );
      if (existing.isNotEmpty) {
        final row = existing.single;
        if (row['question_id'] != questionId ||
            row['answer'] != answer.trim()) {
          throw StateError('同一次提交标识对应了不同答案');
        }
        return PracticeSubmission.fromMap(row);
      }
      final rows = await txn.rawQuery(
        '''SELECT q.* FROM practice_questions q
        JOIN source_documents d ON d.id = q.document_id
        WHERE q.id = ? AND ${scope.ownershipClause}''',
        [questionId, ...scope.args],
      );
      if (rows.isEmpty) throw StateError('题目范围已变化，请刷新');
      final q = rows.single;
      final time = (now ?? DateTime.now()).toUtc();
      final id = await txn.insert('practice_submissions', {
        'user_id': scope.userId,
        'question_id': questionId,
        'request_id': requestId,
        'answer': answer.trim(),
        'correct': correct ? 1 : 0,
        'question_snapshot': jsonEncode(q),
        'source_version_id': q['source_version_id'] ?? source.id,
        'created_at': time.toIso8601String(),
      });
      final concepts = await txn.query(
        'question_concepts',
        where: 'question_id = ?',
        whereArgs: [questionId],
      );
      for (final concept
          in concepts.isEmpty ? <Map<String, Object?>>[{}] : concepts) {
        final values = {
          'user_id': scope.userId,
          'document_id': q['document_id'],
          'concept_id': concept['concept_id'],
          'question_id': questionId,
          'submission_id': id,
          'origin': 'practice',
          'prompt': q['question_text'],
          'answer': answer.trim(),
          'created_at': time.toIso8601String(),
        };
        await txn.insert('learning_attempts', {
          ...values,
          'score': correct ? 100 : 0,
          'feedback': q['analysis_text'] ?? '',
        });
        if (!correct) {
          await txn.insert('learning_errors', {
            ...values,
            'correction': q['analysis_text'] ?? q['answer_text'] ?? '',
          });
        }
      }
      await _syncRelatedQuestions(txn, scope.userId, questionId, time);
      return PracticeSubmission.fromMap(
        (await txn.query(
          'practice_submissions',
          where: 'id = ?',
          whereArgs: [id],
        )).single,
      );
    });
  }

  Future<PracticeSubmission> regrade(
    int userId,
    int submissionId, {
    required int expectedRevision,
    required bool correct,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw ArgumentError('请填写纠正原因');
    final db = await _database.database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'practice_submissions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [submissionId, userId],
      );
      if (rows.isEmpty) throw StateError('作答不存在或无权修改');
      final row = rows.single;
      if (row['revision'] != expectedRevision) throw StateError('作答已被修正，请刷新');
      await txn.insert('practice_revisions', {
        'submission_id': submissionId,
        'previous_correct': row['correct'],
        'correct': correct ? 1 : 0,
        'reason': reason.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await txn.update(
        'practice_submissions',
        {'correct': correct ? 1 : 0, 'revision': expectedRevision + 1},
        where: 'id = ?',
        whereArgs: [submissionId],
      );
      await txn.update(
        'learning_attempts',
        {'score': correct ? 100 : 0, 'feedback': '用户纠正：${reason.trim()}'},
        where: 'submission_id = ?',
        whereArgs: [submissionId],
      );
      final errors = await txn.query(
        'learning_errors',
        where: 'submission_id = ?',
        whereArgs: [submissionId],
      );
      if (!correct && errors.isEmpty) {
        for (final a in await txn.query(
          'learning_attempts',
          where: 'submission_id = ?',
          whereArgs: [submissionId],
        )) {
          final values = Map<String, Object?>.from(a)
            ..remove('id')
            ..remove('score')
            ..remove('feedback');
          await txn.insert('learning_errors', {
            ...values,
            'correction': reason.trim(),
          });
        }
      }
      await txn.update(
        'learning_errors',
        {'resolved': correct ? 1 : 0},
        where: 'submission_id = ?',
        whereArgs: [submissionId],
      );
      await _syncRelatedQuestions(
        txn,
        userId,
        row['question_id'] as int,
        DateTime.now().toUtc(),
      );
      return PracticeSubmission.fromMap(
        (await txn.query(
          'practice_submissions',
          where: 'id = ?',
          whereArgs: [submissionId],
        )).single,
      );
    });
  }

  Future<List<Map<String, Object?>>> history(int userId, int questionId) async {
    final db = await _database.database;
    final current = await db.query(
      'practice_submissions',
      where: 'user_id = ? AND question_id = ?',
      whereArgs: [userId, questionId],
      orderBy: 'created_at DESC, id DESC',
    );
    final legacy = await db.query(
      'learning_attempts',
      where: 'user_id = ? AND question_id = ? AND submission_id IS NULL',
      whereArgs: [userId, questionId],
      orderBy: 'created_at DESC, id DESC',
    );
    final result = <Map<String, Object?>>[
      ...current,
      ...legacy.map(
        (r) => {
          'id': r['id'],
          'answer': r['answer'],
          'created_at': r['created_at'],
          'correct': null,
          'revision': null,
          'legacy': 1,
          'question_snapshot': null,
          'feedback': r['feedback'],
          'score': r['score'],
        },
      ),
    ];
    result.sort(
      (a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String),
    );
    return result;
  }

  Future<MasteryEvidence> evidence(int userId, int questionId) async {
    final db = await _database.database;
    return _evidence(db, userId, questionId);
  }

  Future<void> _syncRelatedQuestions(
    DatabaseExecutor db,
    int userId,
    int questionId,
    DateTime now,
  ) async {
    final related = await db.rawQuery(
      '''SELECT DISTINCT q.id FROM practice_questions q
      JOIN source_documents d ON d.id = q.document_id WHERE d.user_id = ? AND (
        q.id = ? OR q.parent_question_id = ? OR
        q.id = (SELECT parent_question_id FROM practice_questions WHERE id = ?) OR
        q.parent_question_id = (SELECT parent_question_id FROM practice_questions WHERE id = ?) OR
        EXISTS (SELECT 1 FROM question_concepts qc JOIN question_concepts target
          ON qc.concept_id = target.concept_id
          WHERE qc.question_id = q.id AND target.question_id = ?))''',
      [userId, questionId, questionId, questionId, questionId, questionId],
    );
    for (final row in related) {
      await _syncQuestion(db, userId, row['id'] as int, now);
    }
  }

  Future<MasteryEvidence> _evidence(
    DatabaseExecutor db,
    int userId,
    int questionId,
  ) async {
    final rows = await db.rawQuery(
      '''SELECT s.*, q.parent_question_id
      FROM practice_submissions s JOIN practice_questions q ON q.id = s.question_id
      WHERE s.user_id = ? AND (
        q.id = ? OR q.parent_question_id = ? OR
        q.id = (SELECT parent_question_id FROM practice_questions WHERE id = ?) OR
        q.parent_question_id = (SELECT parent_question_id FROM practice_questions WHERE id = ?) OR
        EXISTS (SELECT 1 FROM question_concepts qc JOIN question_concepts target
          ON qc.concept_id = target.concept_id
          WHERE qc.question_id = q.id AND target.question_id = ?))
      ORDER BY s.created_at, s.id''',
      [userId, questionId, questionId, questionId, questionId, questionId],
    );
    final current = await db.query(
      'practice_questions',
      columns: ['next_review_at'],
      where: 'id = ?',
      whereArgs: [questionId],
    );
    return _summarize(
      rows,
      nextReview: DateTime.tryParse(
        current.firstOrNull?['next_review_at'] as String? ?? '',
      ),
    );
  }

  MasteryEvidence _summarize(
    List<Map<String, Object?>> rows, {
    DateTime? nextReview,
  }) {
    // Only evidence after the most recent mistake contributes to current mastery.
    var correct = <Map<String, Object?>>[];
    for (final row in rows) {
      if (row['correct'] != 1) {
        correct = [];
      } else {
        correct.add(row);
      }
    }
    final distinct = correct.map((r) => r['question_id']).toSet().length;
    final delayed =
        correct.length > 1 &&
        DateTime.parse(correct.last['created_at'] as String)
                .difference(
                  DateTime.parse(correct.first['created_at'] as String),
                )
                .inHours >=
            24;
    final mastered = distinct >= 2 && correct.length >= 3 && delayed;
    return MasteryEvidence(
      distinctQuestions: distinct,
      correctCount: correct.length,
      delayedSuccess: delayed,
      mastered: mastered,
      nextReview: nextReview,
    );
  }

  Future<void> _syncQuestion(
    DatabaseExecutor db,
    int userId,
    int questionId,
    DateTime now,
  ) async {
    final history = await db.query(
      'practice_submissions',
      where: 'user_id = ? AND question_id = ?',
      whereArgs: [userId, questionId],
      orderBy: 'created_at, id',
    );
    if (history.isEmpty) return;
    var streak = 0;
    for (final item in history) {
      streak = item['correct'] == 1 ? streak + 1 : 0;
    }
    final correct = history.last['correct'] == 1;
    final e = await _evidence(db, userId, questionId);
    final days = e.mastered
        ? 7
        : correct
        ? 1
        : 0;
    await db.update(
      'practice_questions',
      {
        'review_status': e.mastered
            ? 'mastered'
            : correct
            ? 'pending'
            : 'wrong',
        'last_user_answer': history.last['answer'],
        'last_reviewed_at': history.last['created_at'],
        'wrong_count': history.where((r) => r['correct'] == 0).length,
        'correct_streak': streak,
        'mastery_score': e.mastered ? 100 : (e.correctCount * 20).clamp(0, 70),
        'review_interval_days': days,
        'next_review_at': now
            .add(correct ? Duration(days: days) : const Duration(minutes: 10))
            .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [questionId],
    );
    // One correct answer doesn't silently remove an unresolved knowledge error.
    await db.rawUpdate(
      '''UPDATE learning_errors SET resolved =
      CASE WHEN ? = 1 OR submission_id IN (
        SELECT id FROM practice_submissions WHERE revision > 0 AND correct = 1)
        THEN 1 ELSE 0 END WHERE user_id = ? AND question_id = ?''',
      [e.mastered ? 1 : 0, userId, questionId],
    );
    for (final c in await db.query(
      'question_concepts',
      where: 'question_id = ?',
      whereArgs: [questionId],
    )) {
      final conceptRows = await db.rawQuery(
        '''SELECT s.* FROM practice_submissions s
        JOIN question_concepts qc ON qc.question_id = s.question_id
        WHERE s.user_id = ? AND qc.concept_id = ? ORDER BY s.created_at, s.id''',
        [userId, c['concept_id']],
      );
      final conceptEvidence = _summarize(conceptRows);
      await db.update(
        'knowledge_concepts',
        {
          'mastery_score': conceptEvidence.mastered
              ? 100
              : (conceptEvidence.correctCount * 20).clamp(0, 70),
          'weakness_score': conceptEvidence.mastered
              ? 0
              : 100 - (conceptEvidence.correctCount * 20).clamp(0, 70),
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [c['concept_id'], userId],
      );
    }
  }
}
