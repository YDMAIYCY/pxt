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
  // Preserve publication/source mappings; saved copies are scoped to a library.
  await db.execute('''CREATE TABLE IF NOT EXISTS community_knowledge_saves (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    auth_uuid TEXT NOT NULL,
    library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
    question_id TEXT NOT NULL, answer_id TEXT,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL
  )''');
  await db.execute(
    '''CREATE UNIQUE INDEX IF NOT EXISTS community_save_per_library
    ON community_knowledge_saves(user_id,library_id,question_id,COALESCE(answer_id,''))''',
  );
  await db.execute(
    '''INSERT OR IGNORE INTO community_knowledge_saves
    (user_id,auth_uuid,library_id,question_id,answer_id,document_id,created_at)
    SELECT c.user_id,c.auth_uuid,d.library_id,c.question_id,c.answer_id,c.document_id,c.created_at
    FROM community_knowledge_links c JOIN source_documents d ON d.id=c.document_id
    WHERE d.source_type='community' AND d.library_id IS NOT NULL AND d.user_id=c.user_id''',
  );
}
