import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/feishu_import_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final payloadPath = Platform.environment['FEISHU_LIVE_PAYLOAD'];
  test(
    'real Feishu payload persists once and repeated import keeps source ID',
    () async {
      final payload =
          jsonDecode(await File(payloadPath!).readAsString())
              as Map<String, dynamic>;
      final app = await AppDatabase.openForTesting(databaseFactoryFfi);
      final db = await app.database;
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await db.insert('users', {
          'id': 1,
          'username': 'live-verifier',
          'password_hash': 'test-only',
          'password_salt': 'test-only',
          'created_at': now,
          'updated_at': now,
        });
        final repo = FeishuImportRepository(database: app);
        final first = await repo.save(1, payload);
        final sourceIds = (await db.query(
          'source_documents',
        )).map((row) => row['id']).toList();
        final second = await repo.save(1, payload);
        expect(first.created, (payload['documents'] as List).length);
        expect(second.created, 0);
        expect(second.unchanged, first.created);
        expect(
          (await db.query('source_documents')).map((row) => row['id']).toList(),
          sourceIds,
        );
        final meta = (await db.query('feishu_documents')).first;
        expect(meta['container_id'], payload['container_id']);
        expect(meta['document_id'], payload['documents'][0]['document_id']);
        expect(
          meta['remote_modified_time'],
          payload['documents'][0]['modified_time']?.toString(),
        );
      } finally {
        await db.close();
      }
    },
    skip: payloadPath == null ? '未提供真实飞书 payload，绝不使用 Mock 代替真实联调' : false,
  );
}
