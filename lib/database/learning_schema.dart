import 'package:sqflite/sqflite.dart';

// Section II additions keep existing document and result IDs intact.
Future<void> createLearningSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS document_library_links (
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
    PRIMARY KEY(document_id, library_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS concept_documents (
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    PRIMARY KEY(concept_id, document_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS learning_resources (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    type TEXT NOT NULL, title TEXT NOT NULL, content TEXT NOT NULL,
    input_fingerprint TEXT NOT NULL, model TEXT NOT NULL,
    version INTEGER NOT NULL, created_at TEXT NOT NULL,
    UNIQUE(document_id, type, version)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS question_concepts (
    question_id INTEGER NOT NULL REFERENCES practice_questions(id) ON DELETE CASCADE,
    concept_id INTEGER NOT NULL REFERENCES knowledge_concepts(id) ON DELETE CASCADE,
    PRIMARY KEY(question_id, concept_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS learning_errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
    origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
    correction TEXT NOT NULL, resolved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS learning_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    document_id INTEGER NOT NULL REFERENCES source_documents(id) ON DELETE CASCADE,
    concept_id INTEGER REFERENCES knowledge_concepts(id) ON DELETE SET NULL,
    question_id INTEGER REFERENCES practice_questions(id) ON DELETE SET NULL,
    origin TEXT NOT NULL, prompt TEXT NOT NULL, answer TEXT NOT NULL,
    score INTEGER NOT NULL, feedback TEXT NOT NULL, created_at TEXT NOT NULL
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS flashcard_reviews (
    resource_id INTEGER NOT NULL REFERENCES learning_resources(id) ON DELETE CASCADE,
    card_index INTEGER NOT NULL, interval_days INTEGER NOT NULL DEFAULT 0,
    rating INTEGER NOT NULL DEFAULT 0, next_review_at TEXT NOT NULL,
    PRIMARY KEY(resource_id, card_index)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS image_understandings (
    document_id INTEGER PRIMARY KEY REFERENCES source_documents(id) ON DELETE CASCADE,
    content TEXT NOT NULL, model TEXT NOT NULL, created_at TEXT NOT NULL
  )''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_resource_document_type ON learning_resources(document_id, type, version)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_error_user ON learning_errors(user_id, resolved)',
  );
  await db.execute(
    '''INSERT OR IGNORE INTO document_library_links
    SELECT id, library_id FROM source_documents WHERE library_id IS NOT NULL''',
  );
  await db.execute(
    '''INSERT OR IGNORE INTO concept_documents
    SELECT id, document_id FROM knowledge_concepts WHERE document_id IS NOT NULL''',
  );
  await db.execute(
    '''INSERT OR IGNORE INTO learning_resources
    (document_id, type, title, content, input_fingerprint, model, version, created_at)
    SELECT document_id, task_type, task_type, result_text, '', provider, 1, created_at
    FROM ai_generation_tasks
    WHERE status = 'completed' AND result_text IS NOT NULL
      AND id IN (SELECT MAX(id) FROM ai_generation_tasks GROUP BY document_id, task_type)''',
  );
  // Reassign the primary source before deleting it so a shared concept survives.
  await db.execute(
    '''CREATE TRIGGER IF NOT EXISTS preserve_shared_concept_source
    BEFORE DELETE ON source_documents BEGIN
      UPDATE knowledge_concepts SET document_id = (
        SELECT MIN(document_id) FROM concept_documents
        WHERE concept_id = knowledge_concepts.id AND document_id != OLD.id
      ) WHERE document_id = OLD.id AND EXISTS (
        SELECT 1 FROM concept_documents WHERE concept_id = knowledge_concepts.id AND document_id != OLD.id
      );
    END''',
  );
  await db.execute(
    '''CREATE TRIGGER IF NOT EXISTS preserve_shared_concept_library
    BEFORE DELETE ON knowledge_libraries BEGIN
      UPDATE knowledge_concepts SET library_id = NULL WHERE library_id = OLD.id;
      UPDATE knowledge_concept_links SET library_id = NULL WHERE library_id = OLD.id;
    END''',
  );
  await db.execute('''CREATE TRIGGER IF NOT EXISTS link_document_library_insert
    AFTER INSERT ON source_documents WHEN NEW.library_id IS NOT NULL BEGIN
      INSERT OR IGNORE INTO document_library_links VALUES(NEW.id, NEW.library_id);
    END''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS link_document_library_update
    AFTER UPDATE OF library_id ON source_documents WHEN NEW.library_id IS NOT NULL BEGIN
      INSERT OR IGNORE INTO document_library_links VALUES(NEW.id, NEW.library_id);
    END''');
}
