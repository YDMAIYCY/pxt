import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';

// ========== v17 → v18 迁移测试 ==========
// 约束：升级必须是增量式的，不能删库重建；既有资料与学习数据必须保留。

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;
  const now = '2026-10-14T01:00:00.000Z';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pxt_graph_migration');
    dbPath = '${tempDir.path}/legacy.db';
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 建立一个最小化的 v17 数据库：只包含迁移会触碰到的核心表与数据。
  Future<void> createLegacyV17Database() async {
    final db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 17,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE users (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              username TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              password_salt TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE knowledge_libraries (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              description TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE source_documents (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              library_id INTEGER,
              batch_id INTEGER,
              page_number INTEGER,
              source_type TEXT NOT NULL,
              image_path TEXT NOT NULL,
              original_title TEXT,
              ocr_status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE ocr_texts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              document_id INTEGER NOT NULL UNIQUE,
              raw_text TEXT NOT NULL,
              clean_text TEXT,
              language TEXT NOT NULL DEFAULT 'zh-CN',
              created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );

    await db.insert('users', {
      'id': 1,
      'username': 'legacy',
      'password_hash': 'hash',
      'password_salt': 'salt',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('knowledge_libraries', {
      'id': 7,
      'user_id': 1,
      'name': '高等数学',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('source_documents', {
      'id': 42,
      'user_id': 1,
      'library_id': 7,
      'source_type': 'camera_capture',
      'image_path': '/legacy/page.png',
      'original_title': '旧讲义',
      'ocr_status': 'success',
      'created_at': now,
    });
    await db.insert('ocr_texts', {
      'document_id': 42,
      'raw_text': '函数极限的定义',
      'clean_text': '函数极限的定义',
      'created_at': now,
    });
    await db.close();
  }

  test('v17 升级到 v18 是增量式的：既有数据全部保留，新表被创建', () async {
    await createLegacyV17Database();

    final app = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: dbPath,
    );
    final db = await app.database;

    // 旧数据仍然存在，ID 未被重排。
    final users = await db.query('users');
    expect(users, hasLength(1));
    expect(users.single['username'], 'legacy');

    final libraries = await db.query('knowledge_libraries');
    expect(
      libraries.where((row) => row['id'] == 7),
      hasLength(1),
      reason: '迁移不得删除或重建知识库',
    );
    expect(
      libraries.firstWhere((row) => row['id'] == 7)['name'],
      '高等数学',
    );

    final documents = await db.query('source_documents');
    expect(documents.where((row) => row['id'] == 42), hasLength(1));

    final ocr = await db.query('ocr_texts');
    expect(ocr, hasLength(1));
    expect(ocr.single['raw_text'], '函数极限的定义');

    // 新表与新列被补齐。
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final names = tables.map((row) => row['name']).toSet();
    for (final expected in [
      'graph_nodes',
      'graph_edges',
      'graph_node_sources',
      'graph_edge_evidence',
      'graph_build_jobs',
      'graph_view_prefs',
      'import_records',
      'favorites',
      'knowledge_concepts',
      'knowledge_concept_links',
    ]) {
      expect(names, contains(expected), reason: '$expected 应被补齐');
    }

    // 外键与完整性检查。
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    expect(integrity.first.values.first, 'ok');
    final foreignKeys = await db.rawQuery('PRAGMA foreign_key_check');
    expect(foreignKeys, isEmpty, reason: '迁移后不应有外键违规');

    await db.close();
  });

  test('升级后新图谱表可以立即写入并查询', () async {
    await createLegacyV17Database();
    final app = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: dbPath,
    );
    final db = await app.database;

    final nodeId = await db.insert('graph_nodes', {
      'user_id': 1,
      'canonical_key': '函数极限|概念',
      'canonical_name': '函数极限',
      'display_name': '函数极限',
      'entity_type': '概念',
      'aliases_json': '[]',
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    });
    expect(nodeId, greaterThan(0));

    final rows = await db.query(
      'graph_nodes',
      where: 'user_id = ?',
      whereArgs: [1],
    );
    expect(rows, hasLength(1));
    expect(rows.single['display_name'], '函数极限');

    await db.close();
  });

  test('唯一约束阻止同一用户重复建立同一实体', () async {
    final app = await AppDatabase.openForTesting(databaseFactoryFfi);
    final db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'u',
      'password_hash': 'x',
      'password_salt': 'x',
      'created_at': now,
      'updated_at': now,
    });
    final values = {
      'user_id': 1,
      'canonical_key': '梯度|概念',
      'canonical_name': '梯度',
      'display_name': '梯度',
      'entity_type': '概念',
      'aliases_json': '[]',
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    };
    await db.insert('graph_nodes', values);
    await expectLater(
      db.insert('graph_nodes', values),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });
}
