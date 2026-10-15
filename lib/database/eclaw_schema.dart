import 'package:sqflite/sqflite.dart';
import 'practice_evidence_schema.dart';

/// Only additive changes. Legacy provider='qsclaw' and message content survive.
Future<void> createEClawSchema(DatabaseExecutor db) async {
  // Complete the evidence tables required by the existing practice service.
  await db.execute('''CREATE TABLE IF NOT EXISTS question_concepts (
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    PRIMARY KEY(question_id,concept_id)
  )''');
  for (final table in ['learning_attempts', 'learning_errors']) {
    await db.execute('''CREATE TABLE IF NOT EXISTS $table (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      document_id INTEGER REFERENCES source_documents(id) ON DELETE SET NULL,
      concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
      question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
      origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
      ${table == 'learning_attempts' ? 'score REAL, feedback TEXT,' : 'correction TEXT, resolved INTEGER NOT NULL DEFAULT 0,'}
      created_at TEXT NOT NULL
    )''');
  }
  await createPracticeEvidenceSchema(db);
  final questionColumns = await db.rawQuery(
    'PRAGMA table_info(practice_questions)',
  );
  if (!questionColumns.any((c) => c['name'] == 'source_version_id')) {
    await db.execute(
      'ALTER TABLE practice_questions ADD COLUMN source_version_id INTEGER REFERENCES record_source_versions(id) ON DELETE SET NULL',
    );
  }
  for (final table in ['ai_chat_sessions', 'ai_chat_messages']) {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final name = table == 'ai_chat_sessions' ? 'context_json' : 'metadata_json';
    if (!columns.any((c) => c['name'] == name)) {
      await db.execute(
        "ALTER TABLE $table ADD COLUMN $name TEXT NOT NULL DEFAULT '{}'",
      );
    }
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS agent_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id INTEGER NOT NULL REFERENCES ai_chat_sessions(id) ON DELETE CASCADE,
    request_key TEXT NOT NULL, command TEXT NOT NULL,
    context_json TEXT NOT NULL, steps_json TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    cancel_requested INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL, UNIQUE(user_id, session_id, request_key)
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_agent_tasks_session ON agent_tasks(user_id, session_id)',
  );
  await db.execute('''CREATE TABLE IF NOT EXISTS agent_operation_receipts (
    operation_key TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    result_json TEXT NOT NULL
  )''');
}
