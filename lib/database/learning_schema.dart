import 'package:sqflite/sqflite.dart';

/// Extends the original task/session tables so their historical IDs remain valid.
Future<void> createLearningSchema(Database db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS study_activity_days (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    day TEXT NOT NULL,
    foreground_seconds INTEGER NOT NULL DEFAULT 0 CHECK(foreground_seconds >= 0),
    PRIMARY KEY(user_id, day)
  )''');

  Future<bool> hasTable(String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<void> add(String table, Map<String, String> columns) async {
    // A legacy database may predate the table, in which case there is nothing
    // to add. `PRAGMA table_info` returns no rows for a missing table, which
    // must not be read as "every column is missing" — that would turn into an
    // `ALTER TABLE` against a table that does not exist and abort the whole
    // upgrade, leaving the database unable to open.
    final existing = await db.rawQuery('PRAGMA table_info($table)');
    if (existing.isEmpty) {
      return;
    }
    for (final entry in columns.entries) {
      if (!existing.any((c) => c['name'] == entry.key)) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  await add('pomodoro_tasks', {
    'kind': "TEXT NOT NULL DEFAULT 'personal'",
    'status': "TEXT NOT NULL DEFAULT 'pending'",
    'source_key': 'TEXT',
    'document_id': 'INTEGER REFERENCES source_documents(id) ON DELETE CASCADE',
    'concept_id': 'INTEGER REFERENCES knowledge_concepts(id) ON DELETE CASCADE',
    'question_id':
        'INTEGER REFERENCES practice_questions(id) ON DELETE CASCADE',
    'due_at': 'TEXT',
    'completed_at': 'TEXT',
    'focused_seconds': 'INTEGER NOT NULL DEFAULT 0',
  });
  await add('pomodoro_records', {
    'timer_state': "TEXT NOT NULL DEFAULT 'running'",
    'resumed_at': 'TEXT',
    'target_seconds': 'INTEGER NOT NULL DEFAULT 0',
    'active_segments_json': "TEXT NOT NULL DEFAULT '[]'",
  });
  if (await hasTable('pomodoro_tasks')) {
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_learning_task_source
      ON pomodoro_tasks(user_id, source_key) WHERE source_key IS NOT NULL''');
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS concept_review_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    due_at TEXT NOT NULL,
    last_reviewed_at TEXT,
    interval_days INTEGER NOT NULL DEFAULT 1,
    importance INTEGER NOT NULL DEFAULT 1,
    UNIQUE(user_id, concept_id)
  )''');
  for (final table in ['learning_attempts', 'learning_errors']) {
    await add(table, {
      'interview_evaluation_id':
          'INTEGER REFERENCES interview_evaluations(id) ON DELETE SET NULL',
    });
    if (await hasTable(table)) {
      await db.execute(
        '''CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_interview
        ON $table(interview_evaluation_id) WHERE interview_evaluation_id IS NOT NULL''',
      );
    }
  }
}
