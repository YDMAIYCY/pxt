import 'package:sqflite/sqflite.dart';

/// Call during fresh creation and the additive v17 -> v18 migration.
/// Library, record, page and concept IDs are snapshots: deleting or moving a
/// source must never cascade into interview history or its report.
Future<void> createInterviewSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS interview_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id INTEGER NOT NULL, record_id INTEGER,
    scope_name TEXT NOT NULL, mode TEXT NOT NULL, difficulty TEXT NOT NULL,
    target_question_count INTEGER NOT NULL CHECK(target_question_count > 0),
    completed_question_count INTEGER NOT NULL DEFAULT 0
      CHECK(completed_question_count BETWEEN 0 AND target_question_count),
    status TEXT NOT NULL DEFAULT 'preparing',
    current_order INTEGER NOT NULL DEFAULT 0 CHECK(current_order >= 0),
    current_round INTEGER NOT NULL DEFAULT 0 CHECK(current_round >= 0),
    voice_enabled INTEGER NOT NULL CHECK(voice_enabled IN (0, 1)),
    auto_play INTEGER NOT NULL CHECK(auto_play IN (0, 1)),
    voice_rate REAL NOT NULL CHECK(voice_rate BETWEEN 0 AND 1),
    voice_volume REAL NOT NULL CHECK(voice_volume BETWEEN 0 AND 1),
    started_at TEXT NOT NULL, ended_at TEXT, error_message TEXT, report_json TEXT
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS interview_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES interview_sessions(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL, reference_points_json TEXT NOT NULL,
    knowledge_point TEXT NOT NULL, knowledge_point_id INTEGER,
    source_record_id INTEGER NOT NULL, source_page_id INTEGER NOT NULL,
    evidence_text TEXT NOT NULL, source_kind TEXT NOT NULL,
    order_index INTEGER NOT NULL CHECK(order_index >= 0),
    status TEXT NOT NULL DEFAULT 'pending',
    UNIQUE(session_id, order_index), UNIQUE(id, session_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS interview_turns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES interview_sessions(id) ON DELETE CASCADE,
    question_id INTEGER NOT NULL,
    speaker TEXT NOT NULL, text TEXT NOT NULL, raw_text TEXT, audio_path TEXT,
    duration_ms INTEGER CHECK(duration_ms >= 0),
    round INTEGER NOT NULL DEFAULT 0 CHECK(round >= 0),
    is_follow_up INTEGER NOT NULL DEFAULT 0 CHECK(is_follow_up IN (0, 1)),
    status TEXT NOT NULL DEFAULT 'final', request_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(question_id, session_id)
      REFERENCES interview_questions(id, session_id) ON DELETE CASCADE,
    UNIQUE(session_id, request_key), UNIQUE(id, question_id, session_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS interview_evaluations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL REFERENCES interview_sessions(id) ON DELETE CASCADE,
    question_id INTEGER NOT NULL, turn_id INTEGER NOT NULL UNIQUE,
    accuracy_score INTEGER NOT NULL CHECK(accuracy_score BETWEEN 0 AND 50),
    completeness_score INTEGER NOT NULL CHECK(completeness_score BETWEEN 0 AND 20),
    logic_score INTEGER NOT NULL CHECK(logic_score BETWEEN 0 AND 15),
    expression_score INTEGER NOT NULL CHECK(expression_score BETWEEN 0 AND 15),
    total_score INTEGER NOT NULL CHECK(total_score = accuracy_score +
      completeness_score + logic_score + expression_score),
    strengths_json TEXT NOT NULL, weaknesses_json TEXT NOT NULL,
    suggestions_json TEXT NOT NULL, evidence_refs_json TEXT NOT NULL,
    follow_up_text TEXT, follow_up_reference_points_json TEXT NOT NULL,
    FOREIGN KEY(turn_id, question_id, session_id)
      REFERENCES interview_turns(id, question_id, session_id) ON DELETE CASCADE
  )''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_interview_sessions_scope
    ON interview_sessions(user_id, library_id, record_id, started_at)''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_interview_turns_history
    ON interview_turns(session_id, created_at, id)''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_interview_turns_audio
    ON interview_turns(audio_path) WHERE audio_path IS NOT NULL''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_interview_evaluations_session
    ON interview_evaluations(session_id, id)''');
}
