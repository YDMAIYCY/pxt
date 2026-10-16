import 'package:sqflite/sqflite.dart';

Future<void> createPracticeEvidenceSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS practice_submissions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    request_id TEXT NOT NULL, answer TEXT NOT NULL,
    correct INTEGER NOT NULL, revision INTEGER NOT NULL DEFAULT 0,
    question_snapshot TEXT NOT NULL,
    source_version_id INTEGER REFERENCES record_source_versions(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL, UNIQUE(user_id, request_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS practice_revisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    submission_id INTEGER NOT NULL REFERENCES practice_submissions(id) ON DELETE CASCADE,
    previous_correct INTEGER NOT NULL, correct INTEGER NOT NULL,
    reason TEXT NOT NULL, created_at TEXT NOT NULL
  )''');
  // A missing table means the evidence layer was never introduced; there is no
  // column to add, and altering a nonexistent table would abort the upgrade.
  final columns = await db.rawQuery('PRAGMA table_info(learning_attempts)');
  if (columns.isNotEmpty && !columns.any((c) => c['name'] == 'submission_id')) {
    await db.execute(
      'ALTER TABLE learning_attempts ADD COLUMN submission_id '
      'INTEGER REFERENCES practice_submissions(id) ON DELETE CASCADE',
    );
  }
  final errors = await db.rawQuery('PRAGMA table_info(learning_errors)');
  if (errors.isNotEmpty && !errors.any((c) => c['name'] == 'submission_id')) {
    await db.execute(
      'ALTER TABLE learning_errors ADD COLUMN submission_id '
      'INTEGER REFERENCES practice_submissions(id) ON DELETE CASCADE',
    );
  }
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_submission_question '
    'ON practice_submissions(question_id, created_at)',
  );
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS wrong_question_training_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    fingerprint TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL,
    UNIQUE(question_id, fingerprint)
  )''',
  );
}
