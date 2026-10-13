import 'dart:convert';

import 'app_database.dart';
import 'models/ai_generation_task_record.dart';
import 'models/ai_result_records.dart';
import 'knowledge_graph_repository.dart';
import '../review/review_schedule_policy.dart';

class AiGenerationRepository {
  AiGenerationRepository({
    AppDatabase? database,
    KnowledgeGraphRepository? knowledgeGraphRepository,
  }) : _database = database ?? AppDatabase.instance,
       _knowledgeGraphRepository =
           knowledgeGraphRepository ??
           KnowledgeGraphRepository(database: database ?? AppDatabase.instance);

  final AppDatabase _database;
  final KnowledgeGraphRepository _knowledgeGraphRepository;

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
      throw StateError('Task write completed but readback failed');
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
    bool append = false,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      if (!append) {
        await txn.delete(
          AppDatabase.tableKnowledgeCards,
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }

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
    bool append = false,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      if (!append) {
        await txn.delete(
          AppDatabase.tableReviewOutlines,
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }

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
    bool append = false,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      if (!append) {
        await txn.delete(
          AppDatabase.tableMindmapTexts,
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }

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
    bool append = false,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      if (!append) {
        await txn.delete(
          AppDatabase.tablePracticeQuestions,
          where: 'document_id = ?',
          whereArgs: [documentId],
        );
      }

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
          'next_review_at': now,
          'mastery_score': 0,
          'review_interval_days': 0,
          'correct_streak': 0,
          'parent_question_id': null,
          'question_kind': PracticeQuestionKind.normalize(
            question['question_kind'],
          ),
          'options_json': _normalizedJsonList(question['options_json']),
          'rubric_json': _normalizedJsonMap(question['rubric_json']),
          'expected_keywords_json': _normalizedJsonList(
            question['expected_keywords_json'],
          ),
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
    args.add(PracticeQuestionKind.similar);
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT 'knowledge_cards' AS content_type,
             cards.id AS source_id,
             '' AS content_label,
             cards.document_id AS document_id,
             COALESCE(documents.original_title, '') AS document_title,
             cards.title AS title,
             cards.content AS summary,
             cards.created_at AS created_at
      FROM ${AppDatabase.tableKnowledgeCards} cards
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = cards.document_id
      WHERE documents.user_id = ?
        $libraryClause
      UNION ALL
      SELECT 'review_outline', outlines.id, '', outlines.document_id,
             COALESCE(documents.original_title, ''),
             outlines.title, outlines.outline_text, outlines.created_at
      FROM ${AppDatabase.tableReviewOutlines} outlines
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = outlines.document_id
      WHERE documents.user_id = ?
        $libraryClause
      UNION ALL
      SELECT 'mindmap_text', mindmaps.id, '', mindmaps.document_id,
             COALESCE(documents.original_title, ''),
             '', mindmaps.mindmap_text, mindmaps.created_at
      FROM ${AppDatabase.tableMindmapTexts} mindmaps
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = mindmaps.document_id
      WHERE documents.user_id = ?
        $libraryClause
      UNION ALL
      SELECT 'practice_questions', questions.id, '', questions.document_id,
             COALESCE(documents.original_title, ''),
             questions.question_text, COALESCE(questions.analysis_text, questions.answer_text, ''),
             questions.created_at
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE documents.user_id = ?
        $libraryClause
        AND questions.question_kind != ?
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
             COALESCE(documents.original_title, '') AS document_title,
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
    int? recordId,
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
    final recordClause = recordId == null
        ? ''
        : 'AND documents.import_record_id = ?';
    if (recordId != null) args.add(recordId);
    args.add(limit);

    final rows = await db.rawQuery('''
      SELECT questions.*,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE documents.user_id = ?
        $libraryClause
        $statusClause
        $recordClause
      ORDER BY questions.created_at DESC, questions.id DESC
      LIMIT ?
      ''', args);

    return rows.map(_practiceWithDocumentFromMap).toList(growable: false);
  }

  Future<PracticeQuestionWithDocument?> fetchPracticeQuestionByUserAndId({
    required int userId,
    required int questionId,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT questions.*,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE documents.user_id = ?
        AND questions.id = ?
      LIMIT 1
      ''',
      [userId, questionId],
    );
    if (rows.isEmpty) {
      return null;
    }

    return _practiceWithDocumentFromMap(rows.first);
  }

  Future<List<PracticeQuestionWithDocument>> fetchTodayPracticeQuestionsByUser({
    required int userId,
    int? libraryId,
    DateTime? now,
    int limit = 100,
  }) {
    final today = now ?? DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    final startOfTomorrow = startOfToday.add(const Duration(days: 1));
    return _fetchPracticeQuestionsByReviewWindow(
      userId: userId,
      libraryId: libraryId,
      from: startOfToday,
      before: startOfTomorrow,
      limit: limit,
    );
  }

  Future<List<PracticeQuestionWithDocument>>
  fetchOverduePracticeQuestionsByUser({
    required int userId,
    int? libraryId,
    DateTime? now,
    int limit = 100,
  }) {
    final today = now ?? DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);
    return _fetchPracticeQuestionsByReviewWindow(
      userId: userId,
      libraryId: libraryId,
      before: startOfToday,
      limit: limit,
    );
  }

  Future<List<PracticeQuestionWithDocument>> fetchReviewQueueByUser({
    required int userId,
    int? libraryId,
    DateTime? now,
    int limit = 100,
  }) {
    final today = now ?? DateTime.now();
    final startOfTomorrow = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(const Duration(days: 1));
    return _fetchPracticeQuestionsByReviewWindow(
      userId: userId,
      libraryId: libraryId,
      before: startOfTomorrow,
      limit: limit,
    );
  }

  Future<bool> hasUnmasteredSimilarQuestions(int questionId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS total_count,
        SUM(CASE WHEN review_status = ? THEN 0 ELSE 1 END) AS unfinished_count
      FROM ${AppDatabase.tablePracticeQuestions}
      WHERE parent_question_id = ?
      ''',
      [PracticeQuestionReviewStatus.mastered, questionId],
    );
    if (rows.isEmpty) {
      return false;
    }

    final totalCount = _readInt(rows.first['total_count']);
    final unfinishedCount = _readInt(rows.first['unfinished_count']);
    return totalCount > 0 && unfinishedCount > 0;
  }

  Future<WrongQuestionTrainingRecord?> fetchWrongQuestionTraining(
    int wrongQuestionId,
  ) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableWrongQuestionTrainings,
      where: 'wrong_question_id = ?',
      whereArgs: [wrongQuestionId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return WrongQuestionTrainingRecord.fromMap(rows.first);
  }

  Future<List<PracticeQuestionRecord>> fetchSimilarQuestions(
    int parentQuestionId,
  ) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tablePracticeQuestions,
      where: 'parent_question_id = ?',
      whereArgs: [parentQuestionId],
      orderBy: 'id ASC',
    );
    return rows.map(PracticeQuestionRecord.fromMap).toList(growable: false);
  }

  Future<void> replaceWrongQuestionTraining({
    required PracticeQuestionRecord wrongQuestion,
    required List<String> causeTags,
    required List<Map<String, String>> similarQuestions,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final tagsJson = jsonEncode(
      causeTags
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.tableWrongQuestionTrainings,
        where: 'wrong_question_id = ?',
        whereArgs: [wrongQuestion.id],
      );
      await txn.delete(
        AppDatabase.tablePracticeQuestions,
        where: 'parent_question_id = ? AND question_kind = ?',
        whereArgs: [wrongQuestion.id, PracticeQuestionKind.similar],
      );

      await txn.insert(AppDatabase.tableWrongQuestionTrainings, {
        'wrong_question_id': wrongQuestion.id,
        'cause_tags_json': tagsJson,
        'status': WrongQuestionTrainingStatus.pending,
        'created_at': now,
        'completed_at': null,
      });

      for (final question in similarQuestions.take(3)) {
        await txn.insert(AppDatabase.tablePracticeQuestions, {
          'document_id': wrongQuestion.documentId,
          'question_text': (question['question_text'] ?? '').trim(),
          'answer_text': (question['answer_text'] ?? '').trim(),
          'analysis_text': (question['analysis_text'] ?? '').trim(),
          'difficulty': (question['difficulty'] ?? '').trim(),
          'review_status': PracticeQuestionReviewStatus.pending,
          'last_user_answer': null,
          'last_reviewed_at': null,
          'wrong_count': 0,
          'next_review_at': now,
          'mastery_score': 0,
          'review_interval_days': 0,
          'correct_streak': 0,
          'parent_question_id': wrongQuestion.id,
          'question_kind': PracticeQuestionKind.similar,
          'options_json': _normalizedJsonList(question['options_json']),
          'rubric_json': _normalizedJsonMap(question['rubric_json']),
          'expected_keywords_json': _normalizedJsonList(
            question['expected_keywords_json'],
          ),
          'created_at': now,
        });
      }
    });
  }

  Future<bool> markPracticeQuestionMastered(int questionId) async {
    if (await hasUnmasteredSimilarQuestions(questionId)) {
      return false;
    }
    await _forceMarkQuestionMastered(questionId);
    return true;
  }

  Future<void> resetPracticeQuestionForReview(
    int questionId, {
    String? userAnswer,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final question = await _findPracticeQuestionById(questionId);
    if (question == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final update = ReviewSchedulePolicy.forManualRetry(
      question: question,
      now: now,
    );
    await db.update(
      AppDatabase.tablePracticeQuestions,
      {
        ..._scheduleUpdateMap(update),
        'last_user_answer': userAnswer?.trim(),
        'last_reviewed_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  Future<void> markPracticeQuestionWrong({
    required int questionId,
    required String userAnswer,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc();
    final question = await _findPracticeQuestionById(questionId);
    if (question == null) {
      return;
    }

    final update = ReviewSchedulePolicy.forWrongAnswer(
      question: question,
      now: now,
    );
    await db.transaction((txn) async {
      await txn.update(
        AppDatabase.tablePracticeQuestions,
        {
          ..._scheduleUpdateMap(update),
          'last_user_answer': userAnswer.trim(),
          'last_reviewed_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [questionId],
      );

      await txn.insert(AppDatabase.tableWrongQuestionExplanations, {
        'practice_question_id': questionId,
        'user_answer': userAnswer.trim(),
        'correct_answer': question.answerText ?? '',
        'explanation_text': question.analysisText ?? '',
        'created_at': now.toIso8601String(),
      });
    });
    await _knowledgeGraphRepository.updateMasteryFromPracticeQuestion(
      questionId: questionId,
      isCorrect: false,
    );
  }

  Future<void> markPracticeQuestionCorrect({
    required int questionId,
    required String userAnswer,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final question = await _findPracticeQuestionById(questionId);
    if (question == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final update = ReviewSchedulePolicy.forCorrectAnswer(
      question: question,
      now: now,
    );
    await db.transaction((txn) async {
      await txn.update(
        AppDatabase.tablePracticeQuestions,
        {
          ..._scheduleUpdateMap(update),
          'last_user_answer': userAnswer.trim(),
          'last_reviewed_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [questionId],
      );

      final parentId = question.parentQuestionId;
      if (parentId == null ||
          update.reviewStatus != PracticeQuestionReviewStatus.mastered) {
        return;
      }

      final pendingSiblings = await txn.rawQuery(
        '''
        SELECT COUNT(*) AS count
        FROM ${AppDatabase.tablePracticeQuestions}
        WHERE parent_question_id = ?
          AND review_status != ?
        ''',
        [parentId, PracticeQuestionReviewStatus.mastered],
      );
      if (_readInt(pendingSiblings.first['count']) > 0) {
        return;
      }

      await txn.update(
        AppDatabase.tablePracticeQuestions,
        {
          'review_status': PracticeQuestionReviewStatus.mastered,
          'mastery_score': 100,
          'correct_streak': 5,
          'review_interval_days': 30,
          'next_review_at': now.add(const Duration(days: 30)).toIso8601String(),
          'last_reviewed_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [parentId],
      );
      await txn.update(
        AppDatabase.tableWrongQuestionTrainings,
        {
          'status': WrongQuestionTrainingStatus.completed,
          'completed_at': now.toIso8601String(),
        },
        where: 'wrong_question_id = ?',
        whereArgs: [parentId],
      );
    });
    await _knowledgeGraphRepository.updateMasteryFromPracticeQuestion(
      questionId: questionId,
      isCorrect: true,
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
          (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ? AND questions.question_kind != ?)
        ) AS generated_result_count,
        (SELECT COUNT(*) FROM ${AppDatabase.tablePracticeQuestions} questions JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id WHERE documents.user_id = ? AND questions.question_kind != ?) AS practice_question_count,
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
        PracticeQuestionKind.similar,
        userId,
        PracticeQuestionKind.similar,
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
              'question_kind': item.questionKind,
              'options_json': item.optionsJson ?? '',
              'rubric_json': item.rubricJson ?? '',
              'expected_keywords_json': item.expectedKeywordsJson ?? '',
            },
          )
          .toList(growable: false),
    };
  }

  Future<List<PracticeQuestionWithDocument>>
  _fetchPracticeQuestionsByReviewWindow({
    required int userId,
    required int limit,
    int? libraryId,
    DateTime? from,
    DateTime? before,
  }) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final args = <Object?>[userId];
    final libraryClause = _appendLibraryClause(libraryId, args);
    final windowClauses = <String>[];

    if (from != null) {
      windowClauses.add('questions.next_review_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (before != null) {
      final beforeClause = from == null
          ? '(questions.next_review_at IS NULL OR questions.next_review_at < ?)'
          : 'questions.next_review_at < ?';
      windowClauses.add(beforeClause);
      args.add(before.toUtc().toIso8601String());
    }

    args.add(limit);
    final windowClause = windowClauses.isEmpty
        ? ''
        : 'AND ${windowClauses.join(' AND ')}';
    final rows = await db.rawQuery('''
      SELECT questions.*,
             COALESCE(documents.original_title, '') AS document_title
      FROM ${AppDatabase.tablePracticeQuestions} questions
      JOIN ${AppDatabase.tableSourceDocuments} documents ON documents.id = questions.document_id
      WHERE documents.user_id = ?
        $libraryClause
        $windowClause
      ORDER BY questions.next_review_at IS NULL DESC,
               questions.next_review_at ASC,
               questions.wrong_count DESC,
               questions.id DESC
      LIMIT ?
      ''', args);

    return rows.map(_practiceWithDocumentFromMap).toList(growable: false);
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

  Future<PracticeQuestionRecord?> _findPracticeQuestionById(
    int questionId,
  ) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tablePracticeQuestions,
      where: 'id = ?',
      whereArgs: [questionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    return PracticeQuestionRecord.fromMap(rows.first);
  }

  String buildResultSnapshot(Object data) {
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> _forceMarkQuestionMastered(int questionId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc();
    await db.update(
      AppDatabase.tablePracticeQuestions,
      {
        'review_status': PracticeQuestionReviewStatus.mastered,
        'mastery_score': 100,
        'review_interval_days': 30,
        'correct_streak': 5,
        'next_review_at': now.add(const Duration(days: 30)).toIso8601String(),
        'last_reviewed_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [questionId],
    );
  }

  Map<String, Object?> _scheduleUpdateMap(ReviewScheduleUpdate update) {
    return {
      'review_status': update.reviewStatus,
      'next_review_at': update.nextReviewAt.toUtc().toIso8601String(),
      'mastery_score': update.masteryScore,
      'review_interval_days': update.reviewIntervalDays,
      'correct_streak': update.correctStreak,
      'wrong_count': update.wrongCount,
    };
  }

  GeneratedContentRecord _generatedContentFromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final contentType = (map['content_type'] as String?)?.trim() ?? '';
    return GeneratedContentRecord(
      contentType: contentType,
      sourceId: _readInt(map['source_id']),
      contentLabel: _contentLabelFromMap(contentType, map),
      documentId: map['document_id'] as int,
      documentTitle: _documentTitleFromMap(map),
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
      documentTitle: _documentTitleFromMap(map),
    );
  }

  AiTaskWithDocument _taskWithDocumentFromMap(Map<String, Object?> map) {
    final updatedAt = (map['updated_at'] as String?) ?? '';
    final taskType = (map['task_type'] as String?)?.trim() ?? '';
    return AiTaskWithDocument(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      documentTitle: _documentTitleFromMap(map),
      taskType: taskType,
      taskLabel: AiTaskType.labelOf(taskType),
      status: (map['status'] as String?)?.trim() ?? AiTaskStatus.pending,
      errorMessage: (map['error_message'] as String?)?.trim(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
    );
  }

  String _contentLabelFromMap(String contentType, Map<String, Object?> map) {
    final label = (map['content_label'] as String?)?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }

    switch (contentType) {
      case 'knowledge_cards':
        return '\u77e5\u8bc6\u5361\u7247';
      case 'review_outline':
        return '\u590d\u4e60\u63d0\u7eb2';
      case 'mindmap_text':
        return '\u601d\u7ef4\u5bfc\u56fe\u6587\u5b57\u7248';
      case 'practice_questions':
        return '\u590d\u4e60\u9898';
      default:
        return '';
    }
  }

  String _documentTitleFromMap(Map<String, Object?> map) {
    final title = (map['document_title'] as String?)?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return '\u672a\u547d\u540d\u8d44\u6599';
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

  String? _normalizedJsonList(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return jsonEncode(decoded);
      }
    } catch (_) {}
    return jsonEncode([text]);
  }

  String? _normalizedJsonMap(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return jsonEncode(decoded);
      }
    } catch (_) {}
    return jsonEncode(<String, Object?>{'rubric': text});
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
