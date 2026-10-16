import 'package:sqflite/sqflite.dart';

Future<void> createCommunityLocalSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS chat_outbox (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    auth_uuid TEXT NOT NULL, conversation_id TEXT NOT NULL,
    body TEXT NOT NULL, image_bytes BLOB, image_extension TEXT, image_path TEXT,
    created_at TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS cloud_identity_links (
    local_user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    auth_uuid TEXT NOT NULL UNIQUE,
    linked_at TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS community_knowledge_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    auth_uuid TEXT NOT NULL,
    question_id TEXT NOT NULL,
    answer_id TEXT,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    UNIQUE(user_id, question_id, answer_id)
  )''');
  await db.execute(
    '''CREATE UNIQUE INDEX IF NOT EXISTS community_question_source_once
    ON community_knowledge_links(user_id, question_id, COALESCE(answer_id, ''))''',
  );
}
