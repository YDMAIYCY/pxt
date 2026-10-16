import '../agent/eclaw_context.dart';
import 'app_database.dart';
import 'knowledge_context_repository.dart';
import 'practice_session_repository.dart';
import '../focus/repository/focus_repository.dart';
import '../learning/learning_task_repository.dart';

class LearningStateRepository {
  LearningStateRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;

  /// null means account scope; an empty set must stay empty, never widen it.
  Future<Set<int>?> documentIds(int userId, EClawContext scope) async {
    await KnowledgeContextRepository(
      database: _database,
    ).validateScope(userId, scope);
    if (scope.knowledgeBaseId == null &&
        scope.importRecordId == null &&
        scope.documentId == null &&
        scope.interviewSessionId == null) {
      return null;
    }
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''SELECT d.id FROM source_documents d
      WHERE d.user_id=?
      ${scope.knowledgeBaseId == null ? '' : 'AND d.library_id=?'}
      ${scope.importRecordId == null ? '' : 'AND d.import_record_id=?'}
      ${scope.documentId == null ? '' : 'AND d.id=?'}
      ${scope.interviewSessionId == null ? '' : '''AND EXISTS (
        SELECT 1 FROM interview_sessions i WHERE i.id=? AND i.user_id=d.user_id
        AND i.library_id=d.library_id AND (i.record_id IS NULL OR i.record_id=d.import_record_id))'''}''',
      [
        userId,
        ?scope.knowledgeBaseId,
        ?scope.importRecordId,
        ?scope.documentId,
        ?scope.interviewSessionId,
      ],
    );
    return rows.map((r) => r['id'] as int).toSet();
  }

  Future<List<Map<String, dynamic>>> tasks(
    int userId,
    EClawContext scope,
  ) async {
    final ids = await documentIds(userId, scope);
    final tasks = await LearningTaskRepository(
      database: _database,
    ).tasks(userId);
    return tasks
        .where((t) => ids == null || ids.contains(t.documentId))
        .map((t) => Map<String, dynamic>.from(t.toJson()))
        .toList();
  }

  Future<Map<String, dynamic>> dashboard(int userId, EClawContext scope) async {
    final ids = await documentIds(userId, scope);
    final dashboard = await LearningTaskRepository(
      database: _database,
    ).dashboard(userId);
    final tasks = dashboard.tasks
        .where((t) => ids == null || ids.contains(t.documentId))
        .toList();
    final recommendations = dashboard.recommendations
        .where((r) => ids == null || ids.contains(r.documentId))
        .toList();
    var pending = dashboard.pendingPractice;
    var overdue = dashboard.overduePractice;
    var wrong = dashboard.wrongQuestions;
    if (ids != null) {
      final db = await _database.database;
      final now = DateTime.now();
      final rows = await db.rawQuery(
        '''SELECT
        SUM(CASE WHEN q.review_status='pending' THEN 1 ELSE 0 END) pending,
        SUM(CASE WHEN q.next_review_at<? THEN 1 ELSE 0 END) overdue,
        SUM(CASE WHEN q.review_status='wrong' OR (q.wrong_count>0 AND q.review_status!='mastered') THEN 1 ELSE 0 END) wrong
        FROM practice_questions q JOIN source_documents d ON d.id=q.document_id
        WHERE d.user_id=? AND d.id IN (${ids.isEmpty ? 'NULL' : List.filled(ids.length, '?').join(',')})''',
        [
          DateTime(now.year, now.month, now.day).toUtc().toIso8601String(),
          userId,
          ...ids,
        ],
      );
      pending = (rows.single['pending'] as num?)?.toInt() ?? 0;
      overdue = (rows.single['overdue'] as num?)?.toInt() ?? 0;
      wrong = (rows.single['wrong'] as num?)?.toInt() ?? 0;
    }
    return {
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'recommendations': recommendations.map((r) => r.toJson()).toList(),
      'pendingPractice': pending,
      'overduePractice': overdue,
      'wrongQuestions': wrong,
      'inProgress': ids == null
          ? dashboard.inProgress
          : tasks.where((t) => t.status == 'in_progress').length,
    };
  }

  Future<Map<String, dynamic>> read(int userId, EClawContext scope) async {
    await KnowledgeContextRepository(
      database: _database,
    ).validateScope(userId, scope);
    final db = await _database.database;
    final ids = await documentIds(userId, scope);
    final practiceScope = PracticeScope(
      userId: userId,
      libraryId: scope.knowledgeBaseId,
      recordId: scope.importRecordId,
    );
    final summary = await db.rawQuery(
      '''SELECT COUNT(DISTINCT s.question_id) answeredQuestions,
      COUNT(*) attempts, SUM(s.correct) correctAttempts
      FROM practice_submissions s JOIN practice_questions q ON q.id=s.question_id
      JOIN source_documents d ON d.id=q.document_id
      WHERE s.user_id=? AND ${practiceScope.ownershipClause}
      ${scope.documentId == null ? '' : 'AND d.id=?'}
      ${ids == null ? '' : 'AND d.id IN (${ids.isEmpty ? 'NULL' : List.filled(ids.length, '?').join(',')})'}''',
      [
        userId,
        ...practiceScope.args,
        ?scope.documentId,
        if (ids != null) ...ids,
      ],
    );
    final wrong = await PracticeSessionRepository(database: _database)
        .questions(
          PracticeScope(
            userId: userId,
            libraryId: scope.knowledgeBaseId,
            recordId: scope.importRecordId,
            wrongOnly: true,
            documentId: scope.documentId,
          ),
          limit: 30,
        );
    final reports = await db.query(
      'interview_sessions',
      columns: ['id', 'scope_name', 'report_json', 'ended_at'],
      where:
          "user_id=? AND report_json IS NOT NULL ${scope.knowledgeBaseId == null ? '' : 'AND library_id=?'} ${scope.importRecordId == null ? '' : 'AND record_id=?'} ${scope.interviewSessionId == null ? '' : 'AND id=?'} ${scope.documentId == null ? '' : 'AND record_id IN (SELECT import_record_id FROM source_documents WHERE id=? AND user_id=?)'}",
      whereArgs: [
        userId,
        ?scope.knowledgeBaseId,
        ?scope.importRecordId,
        ?scope.interviewSessionId,
        if (scope.documentId != null) ...[scope.documentId, userId],
      ],
      orderBy: 'id DESC',
      limit: 5,
    );
    final weak = await db.rawQuery(
      '''SELECT c.id,c.name,c.mastery_score,c.weakness_score,
      c.document_id,d.import_record_id FROM knowledge_concepts c
      JOIN source_documents d ON d.id=c.document_id
      WHERE c.user_id=? AND d.user_id=c.user_id
        ${scope.knowledgeBaseId == null ? '' : 'AND d.library_id=?'}
        ${scope.importRecordId == null ? '' : 'AND d.import_record_id=?'}
        ${scope.documentId == null ? '' : 'AND d.id=?'}
        ${ids == null ? '' : 'AND d.id IN (${ids.isEmpty ? 'NULL' : List.filled(ids.length, '?').join(',')})'}
      ORDER BY c.weakness_score DESC,c.mastery_score ASC LIMIT 10''',
      [
        userId,
        ?scope.knowledgeBaseId,
        ?scope.importRecordId,
        ?scope.documentId,
        if (ids != null) ...ids,
      ],
    );
    final learning = await dashboard(userId, scope);
    final stats = ids == null
        ? await FocusRepository(database: _database).fetchStats(userId)
        : null;
    return {
      'practice': summary.single,
      'wrongQuestions': wrong
          .where((q) => ids == null || ids.contains(q.question.documentId))
          .map(
            (q) => {
              'id': q.question.id,
              'documentId': q.question.documentId,
              'question': q.question.questionText,
              'wrongCount': q.question.wrongCount,
            },
          )
          .toList(),
      'interviewReports': reports,
      'weakConcepts': weak,
      'tasks': learning['tasks'],
      'recommendations': learning['recommendations'],
      'pendingPractice': learning['pendingPractice'],
      'overduePractice': learning['overduePractice'],
      'wrongQuestionCount': learning['wrongQuestions'],
      'inProgress': learning['inProgress'],
      'focus': stats == null
          ? {
              'scope': '所选资料',
              'focusedSeconds': (learning['tasks'] as List).fold<int>(
                0,
                (sum, t) => sum + ((t['focusedSeconds'] as num?)?.toInt() ?? 0),
              ),
            }
          : {
              'todaySeconds': stats.todaySeconds,
              'weekSeconds': stats.weekSeconds,
            },
      'note': '无记录表示数据不足，不代表已掌握。任务和复习推荐来自统一学习任务仓库，按当前资料范围过滤。',
    };
  }
}
