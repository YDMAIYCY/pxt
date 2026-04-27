import 'dart:convert';

import 'app_database.dart';
import 'models/ai_generation_task_record.dart';
import 'models/ai_result_records.dart';

class AiGenerationRepository {
  AiGenerationRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<AiGenerationTaskRecord> markTaskRunning({
    required int documentId,
    required String taskType,
    required String inputText,
    String? promptTemplate,
    String provider = 'MiniMax-2.7',
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final taskId = await db.transaction((txn) async {
      final existing = await txn.query(
        AppDatabase.tableAiGenerationTasks,
        columns: ['id'],
        where: 'document_id = ? AND task_type = ?',
        whereArgs: [documentId, taskType],
        orderBy: 'id DESC',
        limit: 1,
      );

      if (existing.isEmpty) {
        return txn.insert(AppDatabase.tableAiGenerationTasks, {
          'document_id': documentId,
          'task_type': taskType,
          'input_text': inputText,
          'prompt_template': promptTemplate,
          'status': AiTaskStatus.running,
          'provider': provider,
          'result_text': null,
          'error_message': null,
          'created_at': now,
          'updated_at': now,
          'completed_at': null,
        });
      }

      final latestTaskId = existing.first['id'] as int;
      await txn.update(
        AppDatabase.tableAiGenerationTasks,
        {
          'input_text': inputText,
          'prompt_template': promptTemplate,
          'status': AiTaskStatus.running,
          'provider': provider,
          'result_text': null,
          'error_message': null,
          'updated_at': now,
          'completed_at': null,
        },
        where: 'id = ?',
        whereArgs: [latestTaskId],
      );

      return latestTaskId;
    });

    final row = await _findTaskById(taskId);
    if (row == null) {
      throw StateError('任务写入后读取失败');
    }

    return row;
  }

  Future<void> markTaskCompleted({
    required int taskId,
    required String resultText,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      AppDatabase.tableAiGenerationTasks,
      {
        'status': AiTaskStatus.completed,
        'result_text': resultText,
        'error_message': null,
        'updated_at': now,
        'completed_at': now,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<void> markTaskFailed({
    required int taskId,
    required String errorMessage,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.update(
      AppDatabase.tableAiGenerationTasks,
      {
        'status': AiTaskStatus.failed,
        'error_message': errorMessage.trim(),
        'updated_at': now,
        'completed_at': now,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<List<AiGenerationTaskRecord>> fetchLatestTasksByDocument(
    int documentId,
  ) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT tasks.*
      FROM ${AppDatabase.tableAiGenerationTasks} tasks
      INNER JOIN (
        SELECT task_type, MAX(id) AS latest_id
        FROM ${AppDatabase.tableAiGenerationTasks}
        WHERE document_id = ?
        GROUP BY task_type
      ) latest
        ON latest.latest_id = tasks.id
      ORDER BY tasks.id DESC
      ''',
      [documentId],
    );

    return rows.map(AiGenerationTaskRecord.fromMap).toList(growable: false);
  }

  Future<List<KnowledgeCardRecord>> fetchKnowledgeCards(int documentId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableKnowledgeCards,
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id ASC',
    );

    return rows.map(KnowledgeCardRecord.fromMap).toList(growable: false);
  }

  Future<ReviewOutlineRecord?> fetchReviewOutline(int documentId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableReviewOutlines,
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ReviewOutlineRecord.fromMap(rows.first);
  }

  Future<MindmapTextRecord?> fetchMindmapText(int documentId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableMindmapTexts,
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return MindmapTextRecord.fromMap(rows.first);
  }

  Future<List<PracticeQuestionRecord>> fetchPracticeQuestions(
    int documentId,
  ) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tablePracticeQuestions,
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'id ASC',
    );

    return rows.map(PracticeQuestionRecord.fromMap).toList(growable: false);
  }

  Future<void> replaceKnowledgeCards({
    required int documentId,
    required List<Map<String, String>> cards,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableKnowledgeCards,
        where: 'document_id = ?',
        whereArgs: [documentId],
      );

      for (final card in cards) {
        await txn.insert(AppDatabase.tableKnowledgeCards, {
          'document_id': documentId,
          'title': (card['title'] ?? '').trim(),
          'content': (card['content'] ?? '').trim(),
          'created_at': now,
        });
      }
    });
  }

  Future<void> replaceReviewOutline({
    required int documentId,
    required String title,
    required String outlineText,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableReviewOutlines,
        where: 'document_id = ?',
        whereArgs: [documentId],
      );

      await txn.insert(AppDatabase.tableReviewOutlines, {
        'document_id': documentId,
        'title': title.trim(),
        'outline_text': outlineText.trim(),
        'created_at': now,
      });
    });
  }

  Future<void> replaceMindmapText({
    required int documentId,
    required String mindmapText,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableMindmapTexts,
        where: 'document_id = ?',
        whereArgs: [documentId],
      );

      await txn.insert(AppDatabase.tableMindmapTexts, {
        'document_id': documentId,
        'mindmap_text': mindmapText.trim(),
        'created_at': now,
      });
    });
  }

  Future<void> replacePracticeQuestions({
    required int documentId,
    required List<Map<String, String>> questions,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tablePracticeQuestions,
        where: 'document_id = ?',
        whereArgs: [documentId],
      );

      for (final question in questions) {
        await txn.insert(AppDatabase.tablePracticeQuestions, {
          'document_id': documentId,
          'question_text': (question['question_text'] ?? '').trim(),
          'answer_text': (question['answer_text'] ?? '').trim(),
          'analysis_text': (question['analysis_text'] ?? '').trim(),
          'difficulty': (question['difficulty'] ?? '').trim(),
          'review_status': PracticeQuestionReviewStatus.pending,
          'last_user_answer': null,
          'last_reviewed_at': null,
          'wrong_count': 0,
          'created_at': now,
        });
      }
    });
  }

  Future<List<GeneratedContentRecord>> fetchRecentGeneratedContents({
    required int userId,
    int? libraryId,
    int limit = 12,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[];
    final libraryClause = _buildLibraryClause(libraryId);
    void addUserAndLibrary() {
      args.add(userId);
      if (libraryId != null) {
        args.add(libraryId);
      }
    }

    addUserAndLibrary();
    addUserAndLibrary();
    addUserAndLibrary();
    addUserAndLibrary();
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT 'knowledge_cards' AS content_type,
             '知识卡片' AS content_label,
             cards.document_id AS document_id,
             COALESCE(documents.original_title, '未命名资料') AS document_title,
             cards.title AS title,
             cards.content AS summary,
             cards.created_at AS created_at
      FROM ${AppDatabase.tableKnowledgeCards} cards
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = cards.document_id
      WHERE documents.user_id = ?
        $libraryClause
      UNION ALL
      SELECT 'review_outline', '复习提纲', outlines.document_id,
             COALESCE(documents.original_title, '未命名资料'),
             outlines.title, outlines.outline_text, outlines.created_at
      FROM ${AppDatabase.tableReviewOutlines} outlines
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = outlines.document_id
      WHERE documents.user_id = ?
        $libraryClause
      UNION ALL
      SELECT 'mindmap_text', '思维导图文字版', mindmaps.document_id,
             COALESCE(documents.original_title, '未命名资料'),
             '思维导图文字版', mindmaps.mindmap_text, mindmaps.created_at
      FROM ${AppDatabase.tableMindmapTexts} mindmaps
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = mindmaps.document_id
      WHERE documents.user_id = ?
        $libraryClause
      UNION ALL
      SELECT 'practice_questions', '复习题', questions.document_id,
             COALESCE(documents.original_title, '未命名资料'),
             questions.question_text, COALESCE(questions.analysis_text, questions.answer_text, ''),
             questions.created_at
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE documents.user_id = ?
        $libraryClause
      ORDER BY created_at DESC
      LIMIT ?
      ''', args);

    return rows.map(_generatedContentFromMap).toList(growable: false);
  }

  Future<List<AiTaskWithDocument>> fetchAiTasksByUser({
    required int userId,
    int? libraryId,
    int limit = 40,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _appendLibraryClause(libraryId, args);
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT tasks.id,
             tasks.document_id,
             COALESCE(documents.original_title, '未命名资料') AS document_title,
             tasks.task_type,
             tasks.status,
             tasks.error_message,
             tasks.updated_at
      FROM ${AppDatabase.tableAiGenerationTasks} tasks
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = tasks.document_id
      WHERE documents.user_id = ?
        $libraryClause
      ORDER BY tasks.updated_at DESC, tasks.id DESC
      LIMIT ?
      ''', args);

    return rows.map(_taskWithDocumentFromMap).toList(growable: false);
  }

  Future<List<PracticeQuestionWithDocument>> fetchPracticeQuestionsByUser({
    required int userId,
    String? reviewStatus,
    int? libraryId,
    int limit = 100,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _appendLibraryClause(libraryId, args);
    final statusClause = reviewStatus == null
        ? ''
        : 'AND questions.review_status = ?';
    if (reviewStatus != null) {
      args.add(reviewStatus);
    }
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT questions.*,
             COALESCE(documents.original_title, '未命名资料') AS document_title
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE documents.user_id = ?
        $libraryClause
        $statusClause
      ORDER BY questions.created_at DESC, questions.id DESC
      LIMIT ?
      ''', args);

    return rows.map(_practiceWithDocumentFromMap).toList(growable: false);
  }

  Future<void> markPracticeQuestionMastered(int questionId) async {
    await _updatePracticeQuestionStatus(
      questionId: questionId,
      status: PracticeQuestionReviewStatus.mastered,
    );
  }

  Future<void> resetPracticeQuestionForReview(
    int questionId, {
    String? userAnswer,
  }) async {
    await _updatePracticeQuestionStatus(
      questionId: questionId,
      status: PracticeQuestionReviewStatus.pending,
      userAnswer: userAnswer,
    );
  }

  Future<void> markPracticeQuestionWrong({
    required int questionId,
    required String userAnswer,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final questionRows = await db.query(
      AppDatabase.tablePracticeQuestions,
      where: 'id = ?',
      whereArgs: [questionId],
      limit: 1,
    );
    if (questionRows.isEmpty) {
      return;
    }

    final question = PracticeQuestionRecord.fromMap(questionRows.first);
    await db.transaction((txn) async {
      await txn.update(
        AppDatabase.tablePracticeQuestions,
        {
          'review_status': PracticeQuestionReviewStatus.wrong,
          'last_user_answer': userAnswer.trim(),
          'last_reviewed_at': now,
          'wrong_count': question.wrongCount + 1,
        },
        where: 'id = ?',
        whereArgs: [questionId],
      );

      await txn.insert(AppDatabase.tableWrongQuestionExplanations, {
        'practice_question_id': questionId,
        'user_answer': userAnswer.trim(),
        'correct_answer': question.answerText ?? '',
        'explanation_text': question.analysisText ?? '',
        'created_at': now,
      });
    });
  }

  Future<void> markPracticeQuestionCorrect({
    required int questionId,
    required String userAnswer,
  }) async {
    await _updatePracticeQuestionStatus(
      questionId: questionId,
      status: PracticeQuestionReviewStatus.mastered,
      userAnswer: userAnswer,
    );
  }

  Future<StudyOverviewStats> fetchStudyOverviewStats(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        (SELECT COUNT(*) FROM ${AppDatabase.tableSourceDocuments} WHERE user_id = ?) AS document_count,
        (SELECT COUNT(*) FROM ${AppDatabase.tableSourceDocuments} WHERE user_id = ? AND ocr_status = 'success') AS ocr_success_count,
        (
          (SELECT COUNT(*) FROM ${AppDatabase.tableKnowledgeCards} cards JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = cards.document_id WHERE documents.user_id = ?) +
          (SELECT COUNT(*) FROM ${AppDatabase.tableReviewOutlines} outlines JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = outlines.document_id WHERE documents.user_id = ?) +
          (SELECT COUNT(*) FROM ${AppDatabase.tableMindmapTexts} mindmaps JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = mindmaps.document_id WHERE documents.user_id = ?) +
          (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ?)
        ) AS generated_result_count,
        (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ?) AS practice_question_count,
        (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ? AND questions.review_status = 'pending') AS pending_practice_count,
        (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ? AND questions.review_status = 'wrong') AS wrong_question_count,
        (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ? AND questions.review_status = 'mastered') AS mastered_question_count
      ''',
      [
        userId,
        userId,
        userId,
        userId,
        userId,
        userId,
        userId,
        userId,
        userId,
        userId,
      ],
    );

    final row = rows.first;
    return StudyOverviewStats(
      documentCount: _readInt(row['document_count']),
      ocrSuccessCount: _readInt(row['ocr_success_count']),
      generatedResultCount: _readInt(row['generated_result_count']),
      practiceQuestionCount: _readInt(row['practice_question_count']),
      pendingPracticeCount: _readInt(row['pending_practice_count']),
      wrongQuestionCount: _readInt(row['wrong_question_count']),
      masteredQuestionCount: _readInt(row['mastered_question_count']),
    );
  }

  Future<Map<String, dynamic>> exportGeneratedData(int documentId) async {
    await _database.ensureSchemaReady();
    final cards = await fetchKnowledgeCards(documentId);
    final outline = await fetchReviewOutline(documentId);
    final mindmap = await fetchMindmapText(documentId);
    final questions = await fetchPracticeQuestions(documentId);

    return {
      'knowledge_cards': cards
          .map((card) => {'title': card.title, 'content': card.content})
          .toList(growable: false),
      'review_outline': outline == null
          ? null
          : {'title': outline.title, 'outline_text': outline.outlineText},
      'mindmap_text': mindmap?.mindmapText,
      'practice_questions': questions
          .map(
            (item) => {
              'question_text': item.questionText,
              'answer_text': item.answerText ?? '',
              'analysis_text': item.analysisText ?? '',
              'difficulty': item.difficulty ?? '',
            },
          )
          .toList(growable: false),
    };
  }

  Future<AiGenerationTaskRecord?> _findTaskById(int taskId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableAiGenerationTasks,
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return AiGenerationTaskRecord.fromMap(rows.first);
  }

  String buildResultSnapshot(Object data) {
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> _updatePracticeQuestionStatus({
    required int questionId,
    required String status,
    String? userAnswer,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      AppDatabase.tablePracticeQuestions,
      {
        'review_status': status,
        'last_user_answer': userAnswer?.trim(),
        'last_reviewed_at': now,
      },
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  GeneratedContentRecord _generatedContentFromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    return GeneratedContentRecord(
      contentType: (map['content_type'] as String?)?.trim() ?? '',
      contentLabel: (map['content_label'] as String?)?.trim() ?? '',
      documentId: map['document_id'] as int,
      documentTitle: (map['document_title'] as String?)?.trim() ?? '未命名资料',
      title: (map['title'] as String?)?.trim() ?? '',
      summary: (map['summary'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
    );
  }

  PracticeQuestionWithDocument _practiceWithDocumentFromMap(
    Map<String, Object?> map,
  ) {
    return PracticeQuestionWithDocument(
      question: PracticeQuestionRecord.fromMap(map),
      documentTitle: (map['document_title'] as String?)?.trim() ?? '未命名资料',
    );
  }

  AiTaskWithDocument _taskWithDocumentFromMap(Map<String, Object?> map) {
    final updatedAt = (map['updated_at'] as String?) ?? '';
    final taskType = (map['task_type'] as String?)?.trim() ?? '';
    return AiTaskWithDocument(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      documentTitle: (map['document_title'] as String?)?.trim() ?? '未命名资料',
      taskType: taskType,
      taskLabel: AiTaskType.labelOf(taskType),
      status: (map['status'] as String?)?.trim() ?? AiTaskStatus.pending,
      errorMessage: (map['error_message'] as String?)?.trim(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
    );
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  String _buildLibraryClause(int? libraryId) {
    return libraryId == null ? '' : 'AND documents.library_id = ?';
  }

  String _appendLibraryClause(int? libraryId, List<Object?> args) {
    if (libraryId == null) {
      return '';
    }
    args.add(libraryId);
    return 'AND documents.library_id = ?';
  }
}
