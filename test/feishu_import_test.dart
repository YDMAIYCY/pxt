import 'dart:io';
import 'package:path/path.dart' as path_util;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/feishu_import_repository.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/feishu_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const now = '2026-10-14T00:00:00Z';
  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    for (final user in [1, 2]) {
      await db.insert('users', {
        'id': user,
        'username': 'fixture$user',
        'password_hash': 'fixture',
        'password_salt': 'fixture',
        'created_at': now,
        'updated_at': now,
      });
    }
  });
  tearDown(() async => db.close());
  Map<String, dynamic> payload({
    String folder = 'FolderA',
    String text = 'fixture text',
    int revision = 1,
    String account = 'tenant:user',
  }) => {
    'account_id': account,
    'container_type': 'folder',
    'container_id': folder,
    'container_name': 'fixture folder',
    'documents': [
      {
        'document_id': 'DocA',
        'title': 'fixture title',
        'text': text,
        'blocks': [
          {'block_id': 'block-fixture', 'block_type': 2},
        ],
        'revision_id': revision,
        'modified_time': '1791936000',
        'source_url': 'https://tenant.feishu.cn/docx/DocA',
      },
    ],
    'failures': [],
  };

  test(
    'same document deduplicates within a library and explicit folders stay independent',
    () async {
      final repo = FeishuImportRepository(database: app);
      expect((await repo.save(1, payload())).created, 1);
      expect((await repo.save(1, payload())).unchanged, 1);
      expect((await repo.save(1, payload(folder: 'FolderB'))).created, 1);
      expect(await db.query('source_documents'), hasLength(2));
      expect(await db.query('import_records'), hasLength(2));
      expect(await db.query('record_source_versions'), hasLength(2));
      final meta = (await db.query(
        'feishu_documents',
        where: "container_id='FolderA'",
      )).single;
      expect(meta['container_id'], 'FolderA');
      expect(meta['document_id'], 'DocA');
      expect(meta['remote_modified_time'], '1791936000');
      final records = await ImportRecordRepository(database: app).list(1);
      expect(records.first.sourceLabel, '飞书导入');
      expect(records.first.anchor.ocrDone, true);
    },
  );

  test(
    'sync updates body in place and preserves AI and old source versions',
    () async {
      final repo = FeishuImportRepository(database: app);
      await repo.save(1, payload());
      final source = (await db.query('source_documents')).single;
      await db.insert('knowledge_cards', {
        'document_id': source['id'],
        'title': 'old card',
        'content': 'old content',
        'created_at': now,
      });
      expect(
        (await repo.save(1, payload(text: 'new text', revision: 2))).updated,
        1,
      );
      expect((await db.query('source_documents')).single['id'], source['id']);
      expect((await db.query('ocr_texts')).single['final_text'], 'new text');
      expect(await db.query('knowledge_cards'), hasLength(1));
      expect(await db.query('record_source_versions'), hasLength(2));
      expect(
        (await db.query('feishu_documents')).single['knowledge_needs_update'],
        1,
      );
    },
  );

  test(
    'local users are isolated and switching Feishu accounts cannot duplicate a shared doc',
    () async {
      final repo = FeishuImportRepository(database: app);
      await repo.save(1, payload());
      await repo.save(2, payload());
      await repo.save(1, payload(account: 'tenant:other'));
      expect(await db.query('feishu_documents'), hasLength(2));
      final id =
          (await db.query('source_documents', where: 'user_id=1')).first['id']
              as int;
      expect(await repo.sourceInfo(2, id), isNull);
    },
  );

  test(
    'failed local import rolls back library and records atomically',
    () async {
      await app.ensureSchemaReady();
      final librariesBefore = await db.query('knowledge_libraries');
      final data = payload();
      (data['documents'] as List).add({'document_id': 'bad'});
      await expectLater(
        FeishuImportRepository(database: app).save(1, data),
        throwsA(anything),
      );
      expect(await db.query('knowledge_libraries'), librariesBefore);
      expect(await db.query('source_documents'), isEmpty);
      expect(await db.query('feishu_documents'), isEmpty);
    },
  );

  test(
    'v20 upgrade preserves existing records and adds Feishu tables',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'feishu_migration_',
      );
      final path = '${directory.path}/fixture.db';
      final oldApp = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final oldDb = await oldApp.database;
      await oldDb.insert('users', {
        'id': 1,
        'username': 'legacy',
        'password_hash': 'fixture',
        'password_salt': 'fixture',
        'created_at': now,
        'updated_at': now,
      });
      await oldDb.insert('source_documents', {
        'id': 7,
        'user_id': 1,
        'source_type': 'camera_capture',
        'image_path': '/fixture.jpg',
        'original_title': 'legacy',
        'created_at': now,
      });
      await oldDb.insert('knowledge_cards', {
        'document_id': 7,
        'title': 'legacy card',
        'content': 'preserve',
        'created_at': now,
      });
      await oldDb.execute('DROP TABLE feishu_documents');
      await oldDb.execute('DROP TABLE feishu_containers');
      await oldDb.setVersion(20);
      await oldDb.close();
      final migrated = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final migratedDb = await migrated.database;
      expect(await migratedDb.getVersion(), AppDatabase.databaseVersion);
      expect((await migratedDb.query('source_documents')).single['id'], 7);
      expect(
        (await migratedDb.query('knowledge_cards')).single['content'],
        'preserve',
      );
      expect(await migratedDb.query('feishu_documents'), isEmpty);
      expect(await migratedDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await migratedDb.close();
      await databaseFactoryFfi.deleteDatabase(path);
      for (final backup in directory.listSync().where((file) => file is File && path_util.basename(file.path).startsWith('${path_util.basename(path)}.before-community-') && file.path.endsWith('.bak'))) {
        backup.deleteSync();
      }
      directory.deleteSync();
    },
  );

  test(
    'v21 migration preserves source IDs, AI cards and source mappings',
    () async {
      final directory = Directory.systemTemp.createTempSync('feishu_v21_');
      final path = '${directory.path}/legacy.db';
      final oldApp = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final old = await oldApp.database;
      await old.insert('users', {
        'id': 1,
        'username': 'legacy21',
        'password_hash': 'fixture',
        'password_salt': 'fixture',
        'created_at': now,
        'updated_at': now,
      });
      await FeishuImportRepository(database: oldApp).save(1, payload());
      final source = (await old.query('feishu_documents')).single;
      final container = (await old.query('feishu_containers')).single;
      await old.insert('knowledge_cards', {
        'document_id': source['source_id'],
        'title': 'keep',
        'content': 'preserve',
        'created_at': now,
      });
      await old.execute('DROP TABLE feishu_documents');
      await old.execute('DROP TABLE feishu_containers');
      for (final table in [
        'feishu_import_job_items',
        'feishu_import_jobs',
        'feishu_resources',
        'feishu_connections',
      ]) {
        await old.execute('DROP TABLE $table');
      }
      await createFeishuSchema(old);
      final oldSource = Map<String, Object?>.from(source)
        ..remove('library_id')
        ..remove('relative_path');
      await old.insert('feishu_documents', oldSource);
      await old.insert('feishu_containers', {
        for (final key in [
          'user_id',
          'account_id',
          'container_type',
          'container_id',
          'library_id',
        ])
          key: container[key],
      });
      await old.setVersion(21);
      await old.close();
      final upgraded = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final next = await upgraded.database;
      expect(await next.getVersion(), AppDatabase.databaseVersion);
      expect(
        (await next.query('feishu_documents')).single['source_id'],
        source['source_id'],
      );
      expect(
        (await next.query('feishu_documents')).single['library_id'],
        container['library_id'],
      );
      expect(
        (await next.query('knowledge_cards')).single['content'],
        'preserve',
      );
      expect((await next.query('feishu_containers')).single['sync_mode'], 1);
      expect(await next.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await next.close();
      await databaseFactoryFfi.deleteDatabase(path);
      for (final backup in directory.listSync().where((file) => file is File && path_util.basename(file.path).startsWith('${path_util.basename(path)}.before-community-') && file.path.endsWith('.bak'))) {
        backup.deleteSync();
      }
      directory.deleteSync();
    },
  );
}
