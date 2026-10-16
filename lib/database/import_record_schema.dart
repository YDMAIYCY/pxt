import 'package:sqflite/sqflite.dart';

// Additive migration preserves original document IDs and all learning data.
Future<void> createImportRecordSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS import_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_id INTEGER REFERENCES knowledge_libraries(id) ON DELETE SET NULL,
    operation_id TEXT NOT NULL, title TEXT NOT NULL,
    tags_json TEXT NOT NULL DEFAULT '[]',
    needs_library_review INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
    UNIQUE(user_id, operation_id)
  )''');
  Future<void> column(String table, String name, String type) async {
    // Skip a table that was never created: `PRAGMA table_info` returns no rows
    // for it, which would otherwise be read as "column missing" and become an
    // `ALTER TABLE` against a nonexistent table.
    final info = await db.rawQuery('PRAGMA table_info($table)');
    if (info.isEmpty) {
      return;
    }
    if (!info.any((c) => c['name'] == name)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $name $type');
    }
  }

  await column('import_records', 'tags_json', "TEXT NOT NULL DEFAULT '[]'");
  await column(
    'knowledge_libraries',
    'cover_theme',
    "TEXT NOT NULL DEFAULT 'math'",
  );
  await column(
    'knowledge_libraries',
    'cover_color',
    'INTEGER NOT NULL DEFAULT 4284190975',
  );
  await column(
    'source_documents',
    'import_record_id',
    'INTEGER REFERENCES import_records(id) ON DELETE CASCADE',
  );
  await column('source_documents', 'original_file_path', 'TEXT');
  await db.execute('''UPDATE source_documents SET original_file_path =
    CASE WHEN source_type='pdf_page' THEN
      (SELECT b.original_file_path FROM document_batches b WHERE b.id=source_documents.batch_id)
    ELSE image_path END WHERE original_file_path IS NULL''');
  await db.execute('''INSERT OR IGNORE INTO import_records
    (user_id, library_id, operation_id, title, needs_library_review, created_at, updated_at)
    SELECT b.user_id, b.library_id, 'batch:' || b.id, b.title,
      CASE WHEN (SELECT COUNT(DISTINCT d.library_id) FROM source_documents d
        WHERE d.batch_id = b.id AND d.user_id = b.user_id) > 1 THEN 1 ELSE 0 END,
      b.created_at, b.updated_at FROM document_batches b''');
  await db.execute('''INSERT OR IGNORE INTO import_records
    (user_id, library_id, operation_id, title, created_at, updated_at)
    SELECT user_id, library_id, 'document:' || id,
      COALESCE(NULLIF(original_title, ''), '未命名记录'), created_at, created_at
    FROM source_documents WHERE batch_id IS NULL''');
  await db.execute('''UPDATE source_documents SET import_record_id = (
    SELECT r.id FROM import_records r WHERE r.user_id = source_documents.user_id
      AND r.operation_id = CASE WHEN source_documents.batch_id IS NULL
        THEN 'document:' || source_documents.id ELSE 'batch:' || source_documents.batch_id END)
    WHERE import_record_id IS NULL''');
  // Old batches can lack a library. Keep them visible without guessing by date.
  await db.execute(
    '''INSERT INTO knowledge_libraries
    (user_id, name, description, created_at, updated_at)
    SELECT u.id, '待整理', '旧资料待确认归属',
      strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    FROM users u WHERE EXISTS(SELECT 1 FROM import_records r WHERE r.user_id=u.id)
      AND NOT EXISTS(SELECT 1 FROM knowledge_libraries l WHERE l.user_id=u.id)''',
  );
  await db.execute(
    '''UPDATE import_records SET needs_library_review=1,
    library_id=COALESCE(
      (SELECT d.library_id FROM source_documents d JOIN knowledge_libraries l
        ON l.id=d.library_id AND l.user_id=import_records.user_id
        WHERE d.import_record_id=import_records.id ORDER BY d.id LIMIT 1),
      (SELECT l.id FROM knowledge_libraries l WHERE l.user_id=import_records.user_id ORDER BY l.id LIMIT 1))
    WHERE NOT EXISTS(SELECT 1 FROM knowledge_libraries l
      WHERE l.id=import_records.library_id AND l.user_id=import_records.user_id)''',
  );
  await db.execute("""CREATE TABLE IF NOT EXISTS record_source_versions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id INTEGER NOT NULL REFERENCES import_records(id) ON DELETE CASCADE,
    fingerprint TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL,
    UNIQUE(record_id, fingerprint)
  )""");
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_source_record ON source_documents(import_record_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_record_library ON import_records(user_id, library_id, created_at)',
  );
  await db.execute('''CREATE TRIGGER IF NOT EXISTS record_batch_insert
    AFTER INSERT ON document_batches BEGIN
      INSERT OR IGNORE INTO import_records
        (user_id, library_id, operation_id, title, created_at, updated_at)
      VALUES(NEW.user_id, NEW.library_id, 'batch:' || NEW.id, NEW.title, NEW.created_at, NEW.updated_at);
    END''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS record_document_insert
    AFTER INSERT ON source_documents WHEN NEW.import_record_id IS NULL BEGIN
      INSERT OR IGNORE INTO import_records
        (user_id, library_id, operation_id, title, created_at, updated_at)
      SELECT NEW.user_id, NEW.library_id, 'document:' || NEW.id,
        COALESCE(NULLIF(NEW.original_title, ''), '未命名记录'), NEW.created_at, NEW.created_at
        WHERE NEW.batch_id IS NULL;
      UPDATE source_documents SET import_record_id = (
        SELECT id FROM import_records WHERE user_id = NEW.user_id
          AND operation_id = CASE WHEN NEW.batch_id IS NULL
            THEN 'document:' || NEW.id ELSE 'batch:' || NEW.batch_id END)
      WHERE id = NEW.id;
    END''');
  await db.execute('''CREATE TRIGGER IF NOT EXISTS record_source_delete
    AFTER DELETE ON source_documents BEGIN
      DELETE FROM import_records WHERE id = OLD.import_record_id
        AND NOT EXISTS (SELECT 1 FROM source_documents WHERE import_record_id = OLD.import_record_id);
    END''');
}
