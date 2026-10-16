import 'package:sqflite/sqflite.dart';
import 'dart:convert';

Future<void> createFeishuSchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS feishu_containers (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL, container_type TEXT NOT NULL, container_id TEXT NOT NULL,
    library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
    PRIMARY KEY(user_id, container_type, container_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS feishu_documents (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL, document_id TEXT NOT NULL,
    source_id INTEGER NOT NULL UNIQUE REFERENCES source_documents(id) ON DELETE CASCADE,
    container_type TEXT NOT NULL, container_id TEXT NOT NULL, node_token TEXT,
    source_url TEXT NOT NULL, remote_modified_time TEXT, revision_id INTEGER NOT NULL,
    blocks_json TEXT NOT NULL, content_hash TEXT NOT NULL, synced_at TEXT NOT NULL,
    knowledge_needs_update INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(user_id, document_id)
  )''');
}

Future<void> upgradeFeishuToV22(DatabaseExecutor db) async {
  final columns = await db.rawQuery('PRAGMA table_info(feishu_documents)');
  if (columns.isNotEmpty && !columns.any((c) => c['name'] == 'library_id')) {
    // A legacy database may predate import_records, so the backfill must not
    // require a column that was never created.
    final sourceColumns = await db.rawQuery(
      'PRAGMA table_info(source_documents)',
    );
    final hasImportRecord = sourceColumns.any(
      (c) => c['name'] == 'import_record_id',
    );
    final unfiled = await db.rawQuery(
      '''SELECT s.id,s.user_id${hasImportRecord ? ',s.import_record_id' : ''}
      FROM source_documents s JOIN feishu_documents f ON f.source_id=s.id
      WHERE s.library_id IS NULL''',
    );
    for (final row in unfiled) {
      final libraries = await db.query(
        'knowledge_libraries',
        columns: ['id'],
        where: 'user_id=?',
        whereArgs: [row['user_id']],
        limit: 1,
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final library =
          libraries.firstOrNull?['id'] ??
          await db.insert('knowledge_libraries', {
            'user_id': row['user_id'],
            'name': '待整理',
            'description': '保留迁移前未归档的飞书资料',
            'created_at': now,
            'updated_at': now,
          });
      await db.update(
        'source_documents',
        {'library_id': library},
        where: 'id=?',
        whereArgs: [row['id']],
      );
      if (row['import_record_id'] != null) {
        await db.update(
          'import_records',
          {'library_id': library},
          where: 'id=?',
          whereArgs: [row['import_record_id']],
        );
      }
    }
    await db.execute(
      'ALTER TABLE feishu_documents RENAME TO feishu_documents_v21',
    );
    await db.execute('''CREATE TABLE feishu_documents (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      account_id TEXT NOT NULL, document_id TEXT NOT NULL,
      source_id INTEGER NOT NULL UNIQUE REFERENCES source_documents(id) ON DELETE CASCADE,
      library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
      container_type TEXT NOT NULL, container_id TEXT NOT NULL, node_token TEXT,
      source_url TEXT NOT NULL, remote_modified_time TEXT, revision_id INTEGER NOT NULL,
      blocks_json TEXT NOT NULL, content_hash TEXT NOT NULL, synced_at TEXT NOT NULL,
      knowledge_needs_update INTEGER NOT NULL DEFAULT 0,
      relative_path TEXT NOT NULL DEFAULT '',
      PRIMARY KEY(user_id, library_id, document_id)
    )''');
    await db.execute(
      '''INSERT INTO feishu_documents
      SELECT f.user_id, f.account_id, f.document_id, f.source_id, s.library_id,
        f.container_type, f.container_id, f.node_token, f.source_url,
        f.remote_modified_time, f.revision_id, f.blocks_json, f.content_hash,
        f.synced_at, f.knowledge_needs_update, ''
      FROM feishu_documents_v21 f JOIN source_documents s ON s.id=f.source_id''',
    );
    await db.execute('DROP TABLE feishu_documents_v21');
  }
  final sourceColumns = await db.rawQuery(
    'PRAGMA table_info(feishu_containers)',
  );
  if (sourceColumns.isNotEmpty &&
      !sourceColumns.any((c) => c['name'] == 'sync_mode')) {
    await db.execute(
      'ALTER TABLE feishu_containers RENAME TO feishu_containers_v21',
    );
    await db.execute('''CREATE TABLE feishu_containers (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      account_id TEXT NOT NULL, container_type TEXT NOT NULL, container_id TEXT NOT NULL,
      library_id INTEGER NOT NULL REFERENCES knowledge_libraries(id) ON DELETE CASCADE,
      sync_mode INTEGER NOT NULL DEFAULT 1, sync_status TEXT NOT NULL DEFAULT 'pending',
      selection_json TEXT NOT NULL DEFAULT '{}', synced_at TEXT, error TEXT,
      PRIMARY KEY(user_id, library_id, container_type, container_id)
    )''');
    for (final source in await db.query('feishu_containers_v21')) {
      final docs = await db.query(
        'feishu_documents',
        where: 'user_id=? AND library_id=?',
        whereArgs: [source['user_id'], source['library_id']],
      );
      await db.insert('feishu_containers', {
        ...source,
        'sync_status': 'synced',
        'synced_at': docs.firstOrNull?['synced_at'],
        'selection_json': jsonEncode({
          'kind': source['container_type'],
          'id': source['container_id'],
          'document_ids': docs.map((d) => d['document_id']).toList(),
        }),
      });
    }
    await db.execute('DROP TABLE feishu_containers_v21');
    await db.execute(
      "CREATE UNIQUE INDEX feishu_unique_container ON feishu_containers(user_id,container_type,container_id) WHERE container_type!='document'",
    );
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS feishu_connections (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL, connection_id TEXT NOT NULL, tenant_id TEXT,
    auth_status TEXT NOT NULL, scopes_json TEXT NOT NULL, updated_at TEXT NOT NULL,
    PRIMARY KEY(user_id,account_id)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS feishu_resources (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL, resource_key TEXT NOT NULL, parent_key TEXT,
    resource_json TEXT NOT NULL, updated_at TEXT NOT NULL,
    PRIMARY KEY(user_id,account_id,resource_key)
  )''');
  await db.execute('''CREATE TABLE IF NOT EXISTS feishu_import_jobs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_id TEXT NOT NULL, status TEXT NOT NULL, plan_json TEXT NOT NULL,
    sync_mode INTEGER NOT NULL, completed INTEGER NOT NULL DEFAULT 0,
    total INTEGER NOT NULL, error TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  )''');
  await db.execute(
    "CREATE UNIQUE INDEX IF NOT EXISTS feishu_one_running_job ON feishu_import_jobs(user_id) WHERE status IN ('queued','running')",
  );
  await db.execute('''CREATE TABLE IF NOT EXISTS feishu_import_job_items (
    job_id INTEGER NOT NULL REFERENCES feishu_import_jobs(id) ON DELETE CASCADE,
    root_index INTEGER NOT NULL, document_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', error TEXT,
    PRIMARY KEY(job_id,root_index,document_id)
  )''');
}
