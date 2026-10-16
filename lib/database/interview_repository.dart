import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../interview/interview_models.dart';
import 'app_database.dart';
import '../learning/learning_events.dart';

class InterviewRepository {
  InterviewRepository({AppDatabase? database, Directory? appDocumentsDirectory})
    : _database = database ?? AppDatabase.instance,
      _appDocumentsDirectory = appDocumentsDirectory;

  final AppDatabase _database;
  final Directory? _appDocumentsDirectory;

  Future<InterviewSession> createSession({
    required int userId,
    required int libraryId,
    int? recordId,
    required String scopeName,
    required String mode,
    required String difficulty,
    int targetQuestionCount = 5,
    bool voiceEnabled = true,
    bool autoPlay = true,
    double voiceRate = .5,
    double voiceVolume = 1,
  }) async {
    if (scopeName.trim().isEmpty ||
        mode.trim().isEmpty ||
        difficulty.trim().isEmpty ||
        targetQuestionCount <= 0 ||
        !voiceRate.isFinite ||
        voiceRate < 0 ||
        voiceRate > 1 ||
        !voiceVolume.isFinite ||
        voiceVolume < 0 ||
        voiceVolume > 1) {
      throw ArgumentError('Invalid interview settings');
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      await _validateScope(txn, userId, libraryId, recordId);
      final id = await txn.insert('interview_sessions', {
        'user_id': userId,
        'library_id': libraryId,
        'record_id': recordId,
        'scope_name': scopeName.trim(),
        'mode': mode.trim(),
        'difficulty': difficulty.trim(),
        'target_question_count': targetQuestionCount,
        'voice_enabled': voiceEnabled ? 1 : 0,
        'auto_play': autoPlay ? 1 : 0,
        'voice_rate': voiceRate,
        'voice_volume': voiceVolume,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      });
      return (await _session(txn, userId, id))!;
    });
  }

  Future<InterviewSession?> getSession(int userId, int sessionId) async =>
      _session(await _database.database, userId, sessionId);

  Future<List<InterviewSession>> listSessions(
    int userId, {
    int? libraryId,
    int? recordId,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'interview_sessions',
      where:
          'user_id = ? ${libraryId == null ? '' : 'AND library_id = ?'} '
          '${recordId == null ? '' : 'AND record_id = ?'}',
      whereArgs: [userId, ?libraryId, ?recordId],
      orderBy: 'started_at DESC, id DESC',
    );
    return rows.map(InterviewSession.fromMap).toList(growable: false);
  }

  Future<List<InterviewQuestion>> saveQuestions(
    int userId,
    int sessionId,
    List<InterviewQuestionDraft> drafts,
  ) async {
    // Copy the caller's list before awaiting; models also freeze their arrays.
    final input = List<InterviewQuestionDraft>.of(drafts);
    final db = await _database.database;
    final session = await _writable(
      txn: db,
      userId: userId,
      sessionId: sessionId,
    );
    await _validateDrafts(db, session, input);
    return db.transaction((txn) async {
      final current = await _writable(
        txn: txn,
        userId: userId,
        sessionId: sessionId,
      );
      // Recheck inside the transaction in case a source was moved or deleted.
      await _validateDrafts(txn, current, input);
      final existing = await _questions(txn, sessionId);
      if (existing.isNotEmpty) return existing;
      for (final draft in input) {
        await txn.insert('interview_questions', {
          ...draft.toMap(),
          'session_id': sessionId,
        });
      }
      return _questions(txn, sessionId);
    });
  }

  Future<List<InterviewQuestion>> questions(int userId, int sessionId) async {
    final db = await _database.database;
    await _requireSession(db, userId, sessionId);
    return _questions(db, sessionId);
  }

  Future<List<InterviewTurn>> turns(int userId, int sessionId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT t.* FROM interview_turns t
      JOIN interview_sessions s ON s.id = t.session_id
      WHERE s.user_id = ? AND s.id = ? ORDER BY t.created_at, t.id''',
      [userId, sessionId],
    );
    return rows.map(InterviewTurn.fromMap).toList(growable: false);
  }

  Future<Map<String, Object?>?> answerDraft(int userId, int sessionId) async {
    final db = await _database.database;
    await _requireSession(db, userId, sessionId);
    return (await db.query(
      'interview_answer_drafts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    )).firstOrNull;
  }

  Future<void> saveAnswerDraft(
    int userId,
    int sessionId,
    Map<String, Object?> draft,
  ) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await _writable(txn: txn, userId: userId, sessionId: sessionId);
      final question = await _question(
        txn,
        sessionId,
        draft['question_id'] as int,
      );
      if (question.status == 'completed') return;
      await txn.insert('interview_answer_drafts', {
        ...draft,
        'session_id': sessionId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> clearAnswerDraft(int userId, int sessionId) async {
    final db = await _database.database;
    await _requireSession(db, userId, sessionId);
    await db.delete(
      'interview_answer_drafts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// A request key fixes question/speaker/round identity. Non-final turns may
  /// recover from errors; final turns are immutable and exact retries return
  /// their original ID. Evaluated or completed answers cannot be rewritten.
  Future<InterviewTurn> upsertTurn({
    required int userId,
    required int sessionId,
    required int questionId,
    required String speaker,
    required String text,
    String? rawText,
    String? audioPath,
    int? durationMs,
    int round = 0,
    bool isFollowUp = false,
    String status = 'final',
    required String requestKey,
  }) async {
    if (!['user', 'assistant', 'system'].contains(speaker) ||
        requestKey.trim().isEmpty ||
        status.trim().isEmpty ||
        (status == 'final' && text.trim().isEmpty) ||
        round < 0 ||
        (durationMs != null && durationMs < 0)) {
      throw ArgumentError('Invalid interview turn');
    }
    final db = await _database.database;
    return db.transaction((txn) async {
      await _writable(txn: txn, userId: userId, sessionId: sessionId);
      final question = await _question(txn, sessionId, questionId);
      final matches = await txn.query(
        'interview_turns',
        where: 'session_id = ? AND request_key = ?',
        whereArgs: [sessionId, requestKey],
      );
      final values = <String, Object?>{
        'session_id': sessionId,
        'question_id': questionId,
        'speaker': speaker,
        'text': text,
        'raw_text': rawText,
        'audio_path': audioPath,
        'duration_ms': durationMs,
        'round': round,
        'is_follow_up': isFollowUp ? 1 : 0,
        'status': status,
        'request_key': requestKey,
      };
      int id;
      if (matches.isNotEmpty) {
        final old = matches.single;
        for (final key in ['question_id', 'speaker', 'round', 'is_follow_up']) {
          if (old[key] != values[key]) {
            throw StateError('Request key belongs to another turn');
          }
        }
        if (values.keys.every((key) => old[key] == values[key])) {
          return InterviewTurn.fromMap(old);
        }
        if (old['status'] == 'final' || question.status == 'completed') {
          throw StateError('Final answers cannot be rewritten');
        }
        id = old['id'] as int;
        final evaluated = await txn.query(
          'interview_evaluations',
          columns: ['id'],
          where: 'turn_id = ?',
          whereArgs: [id],
        );
        if (evaluated.isNotEmpty) throw StateError('Turn is already evaluated');
        await txn.update(
          'interview_turns',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        if (question.status == 'completed') {
          throw StateError('Question is already completed');
        }
        id = await txn.insert('interview_turns', {
          ...values,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return InterviewTurn.fromMap(
        (await txn.query(
          'interview_turns',
          where: 'id = ?',
          whereArgs: [id],
        )).single,
      );
    });
  }

  /// The first valid evaluation for a turn wins; retries never replace it.
  Future<InterviewEvaluation> saveEvaluation(
    int userId,
    InterviewEvaluation e,
  ) async {
    if (e.id < 0 ||
        e.accuracyScore < 0 ||
        e.accuracyScore > 50 ||
        e.completenessScore < 0 ||
        e.completenessScore > 20 ||
        e.logicScore < 0 ||
        e.logicScore > 15 ||
        e.expressionScore < 0 ||
        e.expressionScore > 15 ||
        e.totalScore !=
            e.accuracyScore +
                e.completenessScore +
                e.logicScore +
                e.expressionScore) {
      throw ArgumentError('Invalid interview score or total');
    }
    final db = await _database.database;
    final result = await db.transaction((txn) async {
      await _writable(txn: txn, userId: userId, sessionId: e.sessionId);
      final q = await _question(txn, e.sessionId, e.questionId);
      final turn = await txn.query(
        'interview_turns',
        where: 'id = ? AND question_id = ? AND session_id = ?',
        whereArgs: [e.turnId, e.questionId, e.sessionId],
      );
      if (turn.isEmpty || turn.single['status'] != 'final') {
        throw StateError(
          'Evaluation requires a final turn in this question/session',
        );
      }
      // Evidence references are page IDs from this session's saved snapshots.
      for (final pageId in e.evidenceRefs) {
        final pages = await txn.query(
          'interview_questions',
          columns: ['id'],
          where: 'session_id = ? AND source_page_id = ?',
          whereArgs: [e.sessionId, pageId],
          limit: 1,
        );
        if (pages.isEmpty) {
          throw StateError('Evidence is outside the interview scope');
        }
      }
      final existing = await txn.query(
        'interview_evaluations',
        where: 'turn_id = ?',
        whereArgs: [e.turnId],
      );
      if (existing.isNotEmpty) {
        if (e.id != 0 && e.id != existing.single['id']) {
          throw StateError('Evaluation ID belongs to another evaluation');
        }
        return InterviewEvaluation.fromMap(existing.single);
      }
      if (e.id != 0 || q.status == 'completed') {
        throw StateError('Evaluation does not exist or question is completed');
      }
      final values = e.toMap()..remove('id');
      final id = await txn.insert('interview_evaluations', values);
      // Keep the real interview score and its source. A generated question alone
      // is never learning evidence, and an interview score does not certify mastery.
      final concepts = q.knowledgePointId == null
          ? <Map<String, Object?>>[]
          : await txn.rawQuery(
              '''SELECT c.* FROM knowledge_concepts c JOIN source_documents d ON d.id=c.document_id
        WHERE c.id=? AND c.user_id=? AND d.user_id=? AND d.id=?''',
              [q.knowledgePointId, userId, userId, q.sourcePageId],
            );
      if (concepts.isNotEmpty) {
        final evidence = {
          'user_id': userId,
          'document_id': q.sourcePageId,
          'concept_id': q.knowledgePointId,
          'interview_evaluation_id': id,
          'origin': 'interview',
          'prompt': q.questionText,
          'answer': turn.single['text'],
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        await txn.insert('learning_attempts', {
          ...evidence,
          'score': e.totalScore,
          'feedback': [...e.weaknesses, ...e.suggestions].join('；'),
        });
        if (e.totalScore < 60) {
          await txn.insert('learning_errors', {
            ...evidence,
            'correction': e.suggestions.join('；'),
          });
        }
        final old = concepts.single['mastery_score'] as int;
        final mastery = old == 100 && e.totalScore >= 80
            ? 100
            : ((old * 2 + e.totalScore) / 3).round().clamp(0, 90);
        await txn.update(
          'knowledge_concepts',
          {
            'mastery_score': mastery,
            'weakness_score': 100 - mastery,
            'updated_at': evidence['created_at'],
          },
          where: 'id=? AND user_id=?',
          whereArgs: [q.knowledgePointId, userId],
        );
      }
      return InterviewEvaluation.fromMap(
        (await txn.query(
          'interview_evaluations',
          where: 'id = ?',
          whereArgs: [id],
        )).single,
      );
    });
    LearningEvents.notify();
    return result;
  }

  Future<List<InterviewEvaluation>> evaluations(
    int userId,
    int sessionId,
  ) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT e.* FROM interview_evaluations e
      JOIN interview_sessions s ON s.id = e.session_id
      WHERE s.user_id = ? AND s.id = ? ORDER BY e.id''',
      [userId, sessionId],
    );
    return rows.map(InterviewEvaluation.fromMap).toList(growable: false);
  }

  /// Returns zero for a missing, unowned or terminal session. Terminal states
  /// must go through finishSession so report and endedAt are saved together.
  /// Other nonempty statuses are retained verbatim for controller recovery.
  Future<int> setSessionState(
    int userId,
    int sessionId, {
    required String status,
    int? currentOrder,
    int? currentRound,
    String? errorMessage,
  }) async {
    if (status.trim().isEmpty ||
        _terminal(status) ||
        (currentOrder != null && currentOrder < 0) ||
        (currentRound != null && currentRound < 0)) {
      throw ArgumentError(
        'Invalid session state; use finishSession for terminal states',
      );
    }
    final db = await _database.database;
    return db.update(
      'interview_sessions',
      {
        'status': status,
        'error_message': errorMessage,
        'current_order': ?currentOrder,
        'current_round': ?currentRound,
      },
      where:
          "id = ? AND user_id = ? AND status NOT IN ('completed', 'cancelled')",
      whereArgs: [sessionId, userId],
    );
  }

  Future<int> completeQuestion(
    int userId,
    int sessionId,
    int questionId,
  ) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final s = await _session(txn, userId, sessionId);
      if (s == null || _terminal(s.status)) return 0;
      final q = await _question(txn, sessionId, questionId);
      if (q.status == 'completed') return 0;
      final n = await txn.update(
        'interview_questions',
        {'status': 'completed'},
        where: 'id = ? AND session_id = ? AND status != ?',
        whereArgs: [questionId, sessionId, 'completed'],
      );
      await txn.rawUpdate(
        '''UPDATE interview_sessions SET completed_question_count =
        (SELECT COUNT(*) FROM interview_questions WHERE session_id = ? AND status = 'completed')
        WHERE id = ? AND user_id = ?''',
        [sessionId, sessionId, userId],
      );
      return n;
    });
  }

  Future<int> finishSession(
    int userId,
    int sessionId, {
    required Map<String, Object?> report,
    bool cancelled = false,
  }) async {
    final reportJson = jsonEncode(report);
    final db = await _database.database;
    return db.update(
      'interview_sessions',
      {
        'status': cancelled ? 'cancelled' : 'completed',
        'report_json': reportJson,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'error_message': null,
      },
      where:
          "id = ? AND user_id = ? AND status NOT IN ('completed', 'cancelled')",
      whereArgs: [sessionId, userId],
    );
  }

  Future<void> deleteSession(int userId, int sessionId) async {
    final db = await _database.database;
    final paths = await db.transaction((txn) async {
      await _requireSession(txn, userId, sessionId);
      final rows = await txn.query(
        'interview_turns',
        columns: ['audio_path'],
        where: 'session_id = ? AND audio_path IS NOT NULL',
        whereArgs: [sessionId],
      );
      final n = await txn.delete(
        'interview_sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );
      if (n == 0) throw StateError('Session does not exist or is not owned');
      return rows.map((r) => r['audio_path'] as String).toSet();
    });
    await _deleteUnreferencedAudio(db, paths);
  }

  /// Only unreferenced files under the app's interview audio directory may go.
  Future<void> discardUnsubmittedAudio(
    int userId,
    int sessionId,
    String path,
  ) async {
    final db = await _database.database;
    await _requireSession(db, userId, sessionId);
    await _deleteUnreferencedAudio(db, {path});
  }

  Future<InterviewSession?> _session(
    DatabaseExecutor db,
    int userId,
    int id,
  ) async {
    final rows = await db.query(
      'interview_sessions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
    return rows.isEmpty ? null : InterviewSession.fromMap(rows.single);
  }

  Future<InterviewSession> _requireSession(
    DatabaseExecutor db,
    int userId,
    int id,
  ) async {
    final session = await _session(db, userId, id);
    if (session == null) {
      throw StateError('Session does not exist or is not owned');
    }
    return session;
  }

  Future<InterviewSession> _writable({
    required DatabaseExecutor txn,
    required int userId,
    required int sessionId,
  }) async {
    final session = await _requireSession(txn, userId, sessionId);
    if (_terminal(session.status)) {
      throw StateError('Session is already finished');
    }
    return session;
  }

  bool _terminal(String status) =>
      status == 'completed' || status == 'cancelled';

  Future<List<InterviewQuestion>> _questions(
    DatabaseExecutor db,
    int sessionId,
  ) async {
    final rows = await db.query(
      'interview_questions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'order_index, id',
    );
    return rows.map(InterviewQuestion.fromMap).toList(growable: false);
  }

  Future<InterviewQuestion> _question(
    DatabaseExecutor db,
    int sessionId,
    int id,
  ) async {
    final rows = await db.query(
      'interview_questions',
      where: 'id = ? AND session_id = ?',
      whereArgs: [id, sessionId],
    );
    if (rows.isEmpty) throw StateError('Question is outside this session');
    return InterviewQuestion.fromMap(rows.single);
  }

  Future<void> _validateScope(
    DatabaseExecutor db,
    int userId,
    int libraryId,
    int? recordId,
  ) async {
    final libraries = await db.query(
      'knowledge_libraries',
      columns: ['id'],
      where: 'id = ? AND user_id = ?',
      whereArgs: [libraryId, userId],
    );
    if (libraries.isEmpty) {
      throw StateError('Library is not owned by this user');
    }
    if (recordId != null) {
      final records = await db.query(
        'import_records',
        columns: ['id'],
        where: 'id = ? AND user_id = ? AND library_id = ?',
        whereArgs: [recordId, userId, libraryId],
      );
      if (records.isEmpty) {
        throw StateError('Record is outside the selected library');
      }
    }
  }

  Future<void> _validateDrafts(
    DatabaseExecutor db,
    InterviewSession s,
    List<InterviewQuestionDraft> drafts,
  ) async {
    if (drafts.isEmpty ||
        drafts.length > s.targetQuestionCount ||
        drafts.map((d) => d.orderIndex).toSet().length != drafts.length) {
      throw ArgumentError('Invalid question count or duplicate order');
    }
    await _validateScope(db, s.userId, s.libraryId, s.recordId);
    for (final d in drafts) {
      if (d.questionText.trim().isEmpty ||
          d.knowledgePoint.trim().isEmpty ||
          d.evidenceText.trim().isEmpty ||
          d.sourceKind.trim().isEmpty ||
          d.orderIndex < 0) {
        throw ArgumentError('Invalid question draft');
      }
      final sources = await db.rawQuery(
        '''SELECT d.id FROM source_documents d
        JOIN import_records r ON r.id = d.import_record_id
        JOIN knowledge_libraries l ON l.id = r.library_id
        WHERE d.id = ? AND r.id = ? AND d.user_id = ? AND r.user_id = ?
          AND l.user_id = ? AND r.library_id = ?
          ${s.recordId == null ? '' : 'AND r.id = ?'}''',
        [
          d.sourcePageId,
          d.sourceRecordId,
          s.userId,
          s.userId,
          s.userId,
          s.libraryId,
          ?s.recordId,
        ],
      );
      if (sources.isEmpty) {
        throw StateError('Question source is outside the interview scope');
      }
      if (d.knowledgePointId != null) {
        final concepts = await db.query(
          'knowledge_concepts',
          columns: ['id'],
          where: 'id = ? AND user_id = ? AND document_id = ?',
          whereArgs: [d.knowledgePointId, s.userId, d.sourcePageId],
        );
        if (concepts.isEmpty) {
          throw StateError('Knowledge point is outside the question source');
        }
      }
    }
  }

  Future<void> _deleteUnreferencedAudio(Database db, Set<String> paths) async {
    if (paths.isEmpty) return;
    final Directory documents;
    try {
      documents =
          _appDocumentsDirectory ?? await getApplicationDocumentsDirectory();
    } catch (_) {
      return; // A missing platform directory must not undo database deletion.
    }
    final root = p.normalize(
      p.absolute(p.join(documents.path, 'interview_audio')),
    );
    final String realRoot;
    try {
      final realDocuments = await documents.resolveSymbolicLinks();
      realRoot = await Directory(root).resolveSymbolicLinks();
      if (!p.equals(realRoot, p.join(realDocuments, 'interview_audio'))) return;
    } on FileSystemException {
      return;
    }
    // Serialize the reference check and unlink with other SQLite writes. The
    // session deletion has already committed; filesystem failures leave orphans.
    await db.transaction((txn) async {
      final refs = await txn.query(
        'interview_turns',
        columns: ['audio_path'],
        where: 'audio_path IS NOT NULL',
      );
      final referenced = <String>{};
      for (final row in refs) {
        final path = row['audio_path'] as String;
        referenced.add(p.normalize(p.absolute(path)));
        try {
          referenced.add(await File(path).resolveSymbolicLinks());
        } on FileSystemException {
          // Still retain the lexical reference for missing files.
        }
      }
      for (final path in paths) {
        try {
          // Relative paths are never authority to delete a managed file.
          if (!p.isAbsolute(path)) continue;
          final normalized = p.normalize(path);
          if (!p.isWithin(root, normalized)) continue;
          if (await FileSystemEntity.type(path, followLinks: false) !=
              FileSystemEntityType.file) {
            continue;
          }
          final real = await File(path).resolveSymbolicLinks();
          if (!p.isWithin(realRoot, real) ||
              referenced.any(
                (r) => p.equals(r, normalized) || p.equals(r, real),
              )) {
            continue;
          }
          await File(path).delete();
        } on FileSystemException {
          // Best-effort cleanup cannot hide a successful session deletion.
        }
      }
    });
  }
}
