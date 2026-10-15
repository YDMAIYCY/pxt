import '../agent/eclaw_context.dart';
import 'app_database.dart';
import 'knowledge_context_repository.dart';
import 'practice_session_repository.dart';
import '../focus/repository/focus_repository.dart';

class LearningStateRepository {
  LearningStateRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;
  final AppDatabase _database;
  Future<Map<String, dynamic>> read(int userId, EClawContext scope) async {
    await KnowledgeContextRepository(
      database: _database,
    ).validateScope(userId, scope);
    final db = await _database.database;
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
      ${scope.documentId == null ? '' : 'AND d.id=?'}''',
      [userId, ...practiceScope.args, ?scope.documentId],
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
          "user_id=? AND report_json IS NOT NULL ${scope.knowledgeBaseId == null ? '' : 'AND library_id=?'} ${scope.importRecordId == null ? '' : 'AND record_id=?'} ${scope.interviewSessionId == null ? '' : 'AND id=?'}",
      whereArgs: [
        userId,
        ?scope.knowledgeBaseId,
        ?scope.importRecordId,
        ?scope.interviewSessionId,
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
      ORDER BY c.weakness_score DESC,c.mastery_score ASC LIMIT 10''',
      [
        userId,
        ?scope.knowledgeBaseId,
        ?scope.importRecordId,
        ?scope.documentId,
      ],
    );
    final tasks = await FocusRepository(database: _database).fetchTasks(userId);
    final stats = await FocusRepository(database: _database).fetchStats(userId);
    final progress = await db.rawQuery(
      '''SELECT task_id,COUNT(*) completedPomodoros,
      SUM(duration_seconds) focusedSeconds FROM pomodoro_records
      WHERE user_id=? AND completed=1 GROUP BY task_id''',
      [userId],
    );
    return {
      'practice': summary.single,
      'wrongQuestions': wrong
          .where(
            (q) =>
                scope.documentId == null ||
                q.question.documentId == scope.documentId,
          )
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
      'tasks': tasks
          .map(
            (t) => {
              'id': t.id,
              'title': t.title,
              'estimatedPomodoros': t.estimatedPomodoros,
              'completedPomodoros':
                  progress
                      .where((p) => p['task_id'] == t.id)
                      .firstOrNull?['completedPomodoros'] ??
                  0,
            },
          )
          .toList(),
      'focus': {
        'todaySeconds': stats.todaySeconds,
        'weekSeconds': stats.weekSeconds,
      },
      'note': '无记录表示数据不足，不代表已掌握。专注任务和专注时长是账户总体数据。',
    };
  }
}
