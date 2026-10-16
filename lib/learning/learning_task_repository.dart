import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'learning_events.dart';
import 'review_priority_policy.dart';

class LearningTask {
  const LearningTask({
    required this.id,
    required this.userId,
    required this.title,
    required this.kind,
    required this.status,
    this.documentId,
    this.conceptId,
    this.questionId,
    this.libraryName = '',
    this.documentTitle = '',
    this.dueAt,
    this.focusedSeconds = 0,
    this.estimatedPomodoros = 1,
    this.completedUnits = 0,
    this.totalUnits = 1,
  });
  final int id,
      userId,
      focusedSeconds,
      estimatedPomodoros,
      completedUnits,
      totalUnits;
  final String title, kind, status, libraryName, documentTitle;
  final int? documentId, conceptId, questionId;
  final DateTime? dueAt;
  bool get active =>
      const ['pending', 'in_progress', 'paused'].contains(status);
  double get progress =>
      totalUnits == 0 ? 0 : (completedUnits / totalUnits).clamp(0, 1);
  String get kindLabel => switch (kind) {
    'practice' => '练习',
    'wrong_review' => '错题复习',
    'concept_review' => '知识点复习',
    _ => '个人学习',
  };
  String get statusLabel => switch (status) {
    'in_progress' => '进行中',
    'paused' => '已暂存',
    'completed' => '已完成',
    'cancelled' => '已取消',
    'deleted' => '已删除',
    _ => '待开始',
  };
  factory LearningTask.fromMap(Map<String, Object?> r) => LearningTask(
    id: r['id'] as int,
    userId: r['user_id'] as int,
    title: r['title'] as String,
    kind: r['kind'] as String,
    status: r['status'] as String,
    documentId: r['document_id'] as int?,
    conceptId: r['concept_id'] as int?,
    questionId: r['question_id'] as int?,
    libraryName: r['library_name'] as String? ?? '',
    documentTitle: r['document_title'] as String? ?? '',
    dueAt: DateTime.tryParse(r['due_at'] as String? ?? '')?.toLocal(),
    focusedSeconds: r['focused_seconds'] as int? ?? 0,
    estimatedPomodoros: r['estimated_pomodoros'] as int? ?? 1,
    completedUnits: r['status'] == 'completed' ? 1 : 0,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind,
    'status': status,
    'documentId': documentId,
    'conceptId': conceptId,
    'questionId': questionId,
    'libraryName': libraryName,
    'documentTitle': documentTitle,
    'dueAt': dueAt?.toUtc().toIso8601String(),
    'focusedSeconds': focusedSeconds,
    'estimatedPomodoros': estimatedPomodoros,
    'progress': progress,
  };
}

class ReviewRecommendation {
  const ReviewRecommendation({
    required this.conceptId,
    required this.documentId,
    required this.name,
    required this.libraryName,
    required this.reason,
    required this.masteryScore,
    required this.score,
  });
  final int conceptId, documentId, masteryScore;
  final String name, libraryName, reason;
  final double score;
  Map<String, Object?> toJson() => {
    'conceptId': conceptId,
    'documentId': documentId,
    'name': name,
    'libraryName': libraryName,
    'reason': reason,
    'masteryScore': masteryScore,
    'score': score,
  };
}

class LearningDashboard {
  const LearningDashboard({
    required this.tasks,
    required this.recommendations,
    required this.pendingPractice,
    required this.overduePractice,
    required this.wrongQuestions,
    required this.inProgress,
  });
  final List<LearningTask> tasks;
  final List<ReviewRecommendation> recommendations;
  final int pendingPractice, overduePractice, wrongQuestions, inProgress;
}

/// 按资料聚合的待练题库：首页“为你推荐”用它给出可立即开始的练习入口。
class PracticeBacklog {
  const PracticeBacklog({
    required this.documentId,
    required this.documentTitle,
    required this.libraryName,
    required this.questionIds,
    required this.wrongCount,
    required this.overdueCount,
  });

  final int documentId, wrongCount, overdueCount;
  final String documentTitle, libraryName;
  final List<int> questionIds;

  int get urgency => wrongCount * 3 + overdueCount;
}

/// Shared by home, tasks, focus selection and EClaw. No model calls here.
class LearningTaskRepository {
  LearningTaskRepository({
    AppDatabase? database,
    this.priorityPolicy = const ReviewPriorityPolicy(),
    DateTime Function()? clock,
  }) : _database = database ?? AppDatabase.instance,
       _clock = clock ?? DateTime.now;
  final AppDatabase _database;
  final ReviewPriorityPolicy priorityPolicy;
  final DateTime Function() _clock;

  /// Midnight at the start of the local day [offset] days from [from], as UTC.
  ///
  /// "Today" is a local-calendar concept, so the boundary has to be built from
  /// local date parts. Reading them straight off [from] would silently shift
  /// the boundary by the timezone offset whenever [from] is not already local.
  String _localDayBoundary(DateTime from, int offset) {
    final local = from.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day + offset,
    ).toUtc().toIso8601String();
  }

  Future<LearningDashboard> dashboard(int userId) async {
    await reconcile(userId);
    final items = await tasks(userId);
    final db = await _database.database;
    final now = _clock();
    final today = _localDayBoundary(now, 0);
    final counts = (await db.rawQuery(
      '''SELECT
      SUM(CASE WHEN q.review_status='pending' THEN 1 ELSE 0 END) pending,
      SUM(CASE WHEN q.next_review_at < ? THEN 1 ELSE 0 END) overdue,
      SUM(CASE WHEN q.review_status='wrong' OR
        (q.wrong_count>0 AND q.review_status!='mastered') THEN 1 ELSE 0 END) wrong
      FROM practice_questions q JOIN source_documents d ON d.id=q.document_id
      WHERE d.user_id=?''',
      [today, userId],
    )).single;
    return LearningDashboard(
      tasks: items,
      recommendations: await recommendations(userId),
      pendingPractice: (counts['pending'] as int?) ?? 0,
      overduePractice: (counts['overdue'] as int?) ?? 0,
      wrongQuestions: (counts['wrong'] as int?) ?? 0,
      inProgress: items.where((t) => t.status == 'in_progress').length,
    );
  }

  Future<List<LearningTask>> tasks(
    int userId, {
    bool includeFinished = false,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT t.*, d.original_title document_title,
      l.name library_name FROM pomodoro_tasks t
      LEFT JOIN source_documents d ON d.id=t.document_id AND d.user_id=t.user_id
      LEFT JOIN knowledge_libraries l ON l.id=d.library_id AND l.user_id=t.user_id
      WHERE t.user_id=? AND t.status!='deleted'
      ${includeFinished ? '' : "AND t.is_archived=0 AND t.status IN ('pending','in_progress','paused')"}
      ORDER BY CASE t.status WHEN 'in_progress' THEN 0 ELSE 1 END,
        COALESCE(t.due_at,'9999'),t.sort_order,t.id''',
      [userId],
    );
    return rows.map(LearningTask.fromMap).toList();
  }

  /// 每份资料下真正待做的练习：错题与到期题，按紧急程度排序。
  Future<List<PracticeBacklog>> practiceBacklog(
    int userId, {
    int limit = 3,
    int maxQuestionsPerDocument = 20,
  }) async {
    final db = await _database.database;
    final now = _clock();
    final today = _localDayBoundary(now, 0);
    final wrongClause =
        "q.review_status='wrong' OR (q.wrong_count>0 AND q.review_status!='mastered')";
    final overdueClause = "q.next_review_at IS NOT NULL AND q.next_review_at < ?";
    final rows = await db.rawQuery(
      '''SELECT d.id document_id, COALESCE(d.original_title,'') document_title,
        COALESCE(l.name,'') library_name, q.id question_id,
        CASE WHEN $wrongClause THEN 1 ELSE 0 END wrong_flag,
        CASE WHEN $overdueClause THEN 1 ELSE 0 END overdue_flag
      FROM practice_questions q
      JOIN source_documents d ON d.id=q.document_id
      LEFT JOIN knowledge_libraries l ON l.id=d.library_id AND l.user_id=d.user_id
      WHERE d.user_id=? AND ($wrongClause OR $overdueClause)
      ORDER BY d.id, COALESCE(q.next_review_at,'9999'), q.id''',
      [today, userId, today],
    );

    final grouped = <int, _MutablePracticeBacklog>{};
    for (final row in rows) {
      final documentId = row['document_id'] as int;
      final group = grouped.putIfAbsent(
        documentId,
        () => _MutablePracticeBacklog(
          documentId: documentId,
          documentTitle: (row['document_title'] as String?)?.trim() ?? '',
          libraryName: (row['library_name'] as String?)?.trim() ?? '',
        ),
      );
      group.wrongCount += row['wrong_flag'] as int? ?? 0;
      group.overdueCount += row['overdue_flag'] as int? ?? 0;
      if (group.questionIds.length < maxQuestionsPerDocument) {
        group.questionIds.add(row['question_id'] as int);
      }
    }

    final items = grouped.values
        .map((group) => group.toImmutable())
        .where((item) => item.questionIds.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) {
        final order = b.urgency.compareTo(a.urgency);
        return order == 0 ? a.documentId.compareTo(b.documentId) : order;
      });
    return items.take(limit).toList(growable: false);
  }

  /// Idempotent projection of real due work. Tombstones prevent cancelled work reappearing.
  Future<void> reconcile(int userId) async {
    final db = await _database.database;
    final now = _clock();
    final end = _localDayBoundary(now, 1);
    await db.transaction((txn) async {
      final questions = await txn.rawQuery(
        '''SELECT q.*,d.original_title FROM practice_questions q
        JOIN source_documents d ON d.id=q.document_id WHERE d.user_id=?
        AND (q.last_reviewed_at IS NULL OR q.next_review_at < ?
          OR q.review_status='wrong' OR (q.wrong_count>0 AND q.review_status!='mastered'))''',
        [userId, end],
      );
      for (final q in questions) {
        final wrong =
            q['review_status'] == 'wrong' ||
            ((q['wrong_count'] as int? ?? 0) > 0 &&
                q['review_status'] != 'mastered');
        final revision = q['last_reviewed_at'] ?? q['created_at'];
        final sourceKey = 'question:${q['id']}:$revision';
        await txn.insert('pomodoro_tasks', {
          'user_id': userId,
          'title': wrong
              ? '复习错题：${q['question_text']}'
              : '完成练习：${q['question_text']}',
          'kind': wrong ? 'wrong_review' : 'practice',
          'source_key': sourceKey,
          'document_id': q['document_id'],
          'question_id': q['id'],
          'due_at': q['next_review_at'] ?? now.toUtc().toIso8601String(),
          'created_at': now.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final plans = await txn.rawQuery(
        '''SELECT s.*,c.name,c.document_id
        FROM concept_review_schedules s JOIN knowledge_concepts c ON c.id=s.concept_id
        JOIN source_documents d ON d.id=c.document_id
        WHERE s.user_id=? AND c.user_id=s.user_id AND d.user_id=s.user_id AND s.due_at < ?''',
        [userId, end],
      );
      for (final s in plans) {
        await txn.insert('pomodoro_tasks', {
          'user_id': userId,
          'title': '复习${s['name']}',
          'kind': 'concept_review',
          'source_key': 'concept:${s['concept_id']}:${s['due_at']}',
          'document_id': s['document_id'],
          'concept_id': s['concept_id'],
          'due_at': s['due_at'],
          'created_at': now.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final interviewErrors = await txn.rawQuery(
        '''SELECT e.interview_evaluation_id,c.id,c.name,c.document_id
        FROM learning_errors e JOIN knowledge_concepts c ON c.id=e.concept_id
        JOIN source_documents d ON d.id=c.document_id
        WHERE e.user_id=? AND c.user_id=e.user_id AND d.user_id=e.user_id
          AND e.origin='interview' AND e.resolved=0 AND e.interview_evaluation_id IS NOT NULL''',
        [userId],
      );
      for (final e in interviewErrors) {
        await txn.insert('pomodoro_tasks', {
          'user_id': userId,
          'title': '巩固面试薄弱知识：${e['name']}',
          'kind': 'concept_review',
          'source_key': 'interview:${e['interview_evaluation_id']}',
          'document_id': e['document_id'],
          'concept_id': e['id'],
          'due_at': now.toUtc().toIso8601String(),
          'created_at': now.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<LearningTask> create({
    required int userId,
    required String title,
    int estimatedPomodoros = 1,
    int? documentId,
    int? conceptId,
    DateTime? dueAt,
    String? operationKey,
  }) async {
    if (title.trim().isEmpty ||
        estimatedPomodoros < 1 ||
        estimatedPomodoros > 99) {
      throw ArgumentError('请填写任务名称，预计番茄数为 1–99');
    }
    final db = await _database.database;
    final id = await db.transaction((txn) async {
      if (operationKey != null) {
        final previous = await txn.query(
          'agent_operation_receipts',
          where: 'operation_key=? AND user_id=?',
          whereArgs: [operationKey, userId],
        );
        if (previous.isNotEmpty) {
          return (jsonDecode(previous.single['result_json'] as String)
                  as Map)['taskId']
              as int;
        }
      }
      final docId = await _ownedDocument(txn, userId, documentId, conceptId);
      final taskId = await txn.insert('pomodoro_tasks', {
        'user_id': userId,
        'title': title.trim(),
        'estimated_pomodoros': estimatedPomodoros,
        'kind': conceptId == null ? 'personal' : 'concept_review',
        'document_id': docId,
        'concept_id': conceptId,
        'due_at': dueAt?.toUtc().toIso8601String(),
        'created_at': _clock().toUtc().toIso8601String(),
      });
      if (operationKey != null) {
        await txn.insert('agent_operation_receipts', {
          'operation_key': operationKey,
          'user_id': userId,
          'result_json': jsonEncode({'taskId': taskId}),
        });
      }
      return taskId;
    });
    LearningEvents.notify();
    return (await tasks(
      userId,
      includeFinished: true,
    )).firstWhere((t) => t.id == id);
  }

  Future<int?> _ownedDocument(
    DatabaseExecutor db,
    int userId,
    int? documentId,
    int? conceptId,
  ) async {
    if (conceptId != null) {
      final rows = await db.query(
        'knowledge_concepts',
        where: 'id=? AND user_id=?',
        whereArgs: [conceptId, userId],
      );
      if (rows.isEmpty || rows.single['document_id'] == null) {
        throw StateError('知识点不在当前账户范围');
      }
      final conceptDoc = rows.single['document_id'] as int;
      if (documentId != null && documentId != conceptDoc) {
        throw StateError('知识点与资料不匹配');
      }
      documentId = conceptDoc;
    }
    if (documentId != null &&
        (await db.query(
          'source_documents',
          where: 'id=? AND user_id=?',
          whereArgs: [documentId, userId],
        )).isEmpty) {
      throw StateError('资料不在当前账户范围');
    }
    return documentId;
  }

  Future<void> setStatus(
    int userId,
    int taskId,
    String status, {
    DateTime? dueAt,
  }) async {
    if (!const [
      'pending',
      'in_progress',
      'paused',
      'completed',
      'cancelled',
      'deleted',
    ].contains(status)) {
      throw ArgumentError('不支持的任务状态');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'pomodoro_tasks',
        where: 'id=? AND user_id=?',
        whereArgs: [taskId, userId],
      );
      if (rows.isEmpty) throw StateError('任务不存在');
      final task = rows.single;
      if (status == 'completed' && task['question_id'] != null) {
        throw StateError('请完成实际答题后更新练习任务');
      }
      if (task['status'] == status && dueAt == null) return;
      if (const [
            'completed',
            'cancelled',
            'deleted',
          ].contains(task['status']) &&
          task['status'] != status &&
          status != 'deleted') {
        throw StateError('任务已结束，请创建新的学习计划');
      }
      if (const ['cancelled', 'deleted'].contains(status) &&
          (await txn.query(
            'pomodoro_records',
            where:
                'task_id=? AND user_id=? AND ended_at IS NULL AND completed=0',
            whereArgs: [taskId, userId],
          )).isNotEmpty) {
        throw StateError('请先结束该任务的专注计时');
      }
      final time = _clock().toUtc();
      await txn.update(
        'pomodoro_tasks',
        {
          'status': status,
          'is_archived': status == 'deleted' ? 1 : 0,
          if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
          if (status == 'completed') 'completed_at': time.toIso8601String(),
        },
        where: 'id=? AND user_id=?',
        whereArgs: [taskId, userId],
      );
      if (status == 'completed' && task['concept_id'] != null) {
        await _advanceConcept(txn, userId, task['concept_id'] as int, time);
      }
    });
    LearningEvents.notify();
  }

  Future<void> addConceptReview(
    int userId,
    int conceptId, {
    DateTime? dueAt,
    int importance = 1,
  }) async {
    if (importance < 1 || importance > 5) throw ArgumentError('重要性应为 1–5');
    final db = await _database.database;
    await db.transaction((txn) async {
      await _ownedDocument(txn, userId, null, conceptId);
      final date = (dueAt ?? _clock()).toUtc().toIso8601String();
      final old = await txn.query(
        'concept_review_schedules',
        where: 'user_id=? AND concept_id=?',
        whereArgs: [userId, conceptId],
      );
      if (old.isEmpty) {
        await txn.insert('concept_review_schedules', {
          'user_id': userId,
          'concept_id': conceptId,
          'due_at': date,
          'importance': importance,
        });
      } else {
        await txn.update(
          'concept_review_schedules',
          {'due_at': date, 'importance': importance},
          where: 'id=?',
          whereArgs: [old.single['id']],
        );
        // Supersede the old occurrence when the user explicitly changes the schedule.
        if (old.single['due_at'] != date) {
          await txn.update(
            'pomodoro_tasks',
            {'status': 'cancelled'},
            where:
                "user_id=? AND concept_id=? AND source_key IS NOT NULL AND status IN ('pending','paused','in_progress')",
            whereArgs: [userId, conceptId],
          );
        }
      }
    });
    await reconcile(userId);
    LearningEvents.notify();
  }

  Future<List<ReviewRecommendation>> recommendations(int userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT c.*,l.name library_name,s.due_at,s.importance,s.last_reviewed_at,
      (SELECT COUNT(*) FROM learning_attempts a WHERE a.user_id=c.user_id AND a.concept_id=c.id) evidence_count
      FROM knowledge_concepts c JOIN source_documents d ON d.id=c.document_id AND d.user_id=c.user_id
      LEFT JOIN knowledge_libraries l ON l.id=d.library_id AND l.user_id=c.user_id
      LEFT JOIN concept_review_schedules s ON s.concept_id=c.id AND s.user_id=c.user_id
      WHERE c.user_id=?''',
      [userId],
    );
    final result = <ReviewRecommendation>[];
    final now = _clock().toUtc();
    for (final c in rows) {
      // Use recent actual submissions; do not infer practice from generated content.
      final attempts = await db.rawQuery(
        '''SELECT s.correct,s.created_at FROM practice_submissions s
        JOIN question_concepts qc ON qc.question_id=s.question_id
        WHERE s.user_id=? AND qc.concept_id=? ORDER BY s.created_at DESC,s.id DESC LIMIT 20''',
        [userId, c['id']],
      );
      final legacy = await db.rawQuery(
        '''SELECT score,created_at,origin FROM learning_attempts
        WHERE user_id=? AND concept_id=? AND submission_id IS NULL ORDER BY created_at DESC LIMIT 20''',
        [userId, c['id']],
      );
      final evidence =
          [
            ...attempts.map(
              (r) => {
                'score': r['correct'] == 1 ? 100 : 0,
                'created_at': r['created_at'],
                'origin': 'practice',
              },
            ),
            ...legacy,
          ]..sort(
            (a, b) => (b['created_at'] as String).compareTo(
              a['created_at'] as String,
            ),
          );
      final recent = evidence.take(20).toList();
      final questionDue = await db.rawQuery(
        '''SELECT MIN(q.next_review_at) due_at
        FROM question_concepts qc JOIN practice_questions q ON q.id=qc.question_id
        JOIN source_documents d ON d.id=q.document_id
        WHERE qc.concept_id=? AND d.user_id=?''',
        [c['id'], userId],
      );
      final scheduleDue = DateTime.tryParse(c['due_at'] as String? ?? '');
      final practiceDue = DateTime.tryParse(
        questionDue.single['due_at'] as String? ?? '',
      );
      final dueAt = scheduleDue == null
          ? practiceDue
          : practiceDue == null
          ? scheduleDue
          : scheduleDue.isBefore(practiceDue)
          ? scheduleDue
          : practiceDue;
      final planned = dueAt != null && !dueAt.isAfter(now);
      final explicitPlanDue = scheduleDue != null && !scheduleDue.isAfter(now);
      if (recent.isEmpty && !explicitPlanDue) continue;
      final mastery = c['mastery_score'] as int? ?? 0;
      if (mastery >= 100 && !planned) continue;
      final errors = recent.where((r) => (r['score'] as num? ?? 0) < 60).length;
      final last = recent.isEmpty
          ? null
          : DateTime.parse(recent.first['created_at'] as String);
      final reviewed = DateTime.tryParse(
        c['last_reviewed_at'] as String? ?? '',
      );
      final latest =
          reviewed != null && (last == null || reviewed.isAfter(last))
          ? reviewed
          : last;
      final interviewWeak = recent.any(
        (r) => r['origin'] == 'interview' && (r['score'] as num? ?? 0) < 60,
      );
      final practiceWeak = recent.any(
        (r) => r['origin'] != 'interview' && (r['score'] as num? ?? 0) < 60,
      );
      final reason = practiceWeak
          ? '该知识点最近练习错误较多，建议优先复习。'
          : interviewWeak
          ? '最近面试中该知识点回答较薄弱，建议巩固。'
          : planned
          ? '复习计划已到期，建议今天巩固。'
          : latest != null && now.difference(latest).inDays >= 7
          ? '距离上次学习已有一段时间，建议复习巩固。'
          : '该知识点仍在巩固中，建议继续练习。';
      result.add(
        ReviewRecommendation(
          conceptId: c['id'] as int,
          documentId: c['document_id'] as int,
          name: c['name'] as String,
          libraryName: c['library_name'] as String? ?? '未分组知识库',
          reason: reason,
          masteryScore: mastery,
          score: priorityPolicy.score(
            mastery: mastery,
            attempts: recent.length,
            errors: errors,
            now: now,
            dueAt: dueAt,
            lastStudiedAt: latest,
            importance: c['importance'] as int? ?? 1,
          ),
        ),
      );
    }
    result.sort((a, b) {
      final order = b.score.compareTo(a.score);
      return order == 0 ? a.conceptId.compareTo(b.conceptId) : order;
    });
    return result;
  }
}

class _MutablePracticeBacklog {
  _MutablePracticeBacklog({
    required this.documentId,
    required this.documentTitle,
    required this.libraryName,
  });

  final int documentId;
  final String documentTitle, libraryName;
  final List<int> questionIds = <int>[];
  int wrongCount = 0;
  int overdueCount = 0;

  PracticeBacklog toImmutable() => PracticeBacklog(
    documentId: documentId,
    documentTitle: documentTitle,
    libraryName: libraryName,
    questionIds: List<int>.unmodifiable(questionIds),
    wrongCount: wrongCount,
    overdueCount: overdueCount,
  );
}

Future<void> _advanceConcept(
  DatabaseExecutor db,
  int userId,
  int conceptId,
  DateTime time,
) async {
  final rows = await db.rawQuery(
    '''SELECT s.interval_days,c.mastery_score FROM concept_review_schedules s
    JOIN knowledge_concepts c ON c.id=s.concept_id WHERE s.user_id=? AND s.concept_id=?''',
    [userId, conceptId],
  );
  if (rows.isEmpty) {
    return;
  }
  final mastery = rows.single['mastery_score'] as int? ?? 0;
  final days = mastery >= 80
      ? ((rows.single['interval_days'] as int) * 2).clamp(1, 30)
      : 1;
  await db.update(
    'concept_review_schedules',
    {
      'last_reviewed_at': time.toIso8601String(),
      'due_at': time.add(Duration(days: days)).toIso8601String(),
      'interval_days': days,
    },
    where: 'user_id=? AND concept_id=?',
    whereArgs: [userId, conceptId],
  );
}

/// Called inside the answer transaction: actual execution is separate from mastery.
Future<void> recordLearningTaskAnswer(
  DatabaseExecutor db,
  int userId,
  int questionId,
  DateTime time,
) async {
  await db.update(
    'pomodoro_tasks',
    {'status': 'completed', 'completed_at': time.toUtc().toIso8601String()},
    where:
        "user_id=? AND question_id=? AND status IN ('pending','in_progress','paused')",
    whereArgs: [userId, questionId],
  );
  for (final c in await db.query(
    'question_concepts',
    where: 'question_id=?',
    whereArgs: [questionId],
  )) {
    final changed = await db.update(
      'pomodoro_tasks',
      {'status': 'completed', 'completed_at': time.toUtc().toIso8601String()},
      where:
          "user_id=? AND concept_id=? AND status IN ('pending','in_progress','paused')",
      whereArgs: [userId, c['concept_id']],
    );
    if (changed > 0) {
      await _advanceConcept(db, userId, c['concept_id'] as int, time.toUtc());
    }
  }
}
