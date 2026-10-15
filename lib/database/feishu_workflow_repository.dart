import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'app_database.dart';

class FeishuWorkflowRepository {
  FeishuWorkflowRepository({AppDatabase? database})
    : database = database ?? AppDatabase.instance;
  final AppDatabase database;
  String get now => DateTime.now().toUtc().toIso8601String();

  Future<void> connection(int userId, Map<String, dynamic> value) async {
    final account = value['account_id'] as String?;
    if (account == null) return;
    final db = await database.database;
    await db.insert('feishu_connections', {
      'user_id': userId,
      'account_id': account,
      'connection_id': value['connection_id'] ?? account,
      'tenant_id': value['tenant_id'] ?? account.split(':').first,
      'auth_status': value['status'],
      'scopes_json': jsonEncode(value['scopes'] ?? []),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> cache(int userId, List<Map<String, dynamic>> resources) async {
    final db = await database.database;
    final batch = db.batch();
    for (final resource in resources) {
      batch.insert('feishu_resources', {
        'user_id': userId,
        'account_id': resource['account_id'],
        'resource_key': resource['key'],
        'parent_key': resource['parent_key'],
        'resource_json': jsonEncode(resource),
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, Object?>>> sources(int userId, int libraryId) async {
    final db = await database.database;
    return db.query(
      'feishu_containers',
      where: 'user_id=? AND library_id=?',
      whereArgs: [userId, libraryId],
    );
  }

  Future<List<Map<String, Object?>>> jobs(int userId) async {
    final db = await database.database;
    return db.query(
      'feishu_import_jobs',
      where: 'user_id=?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: 30,
    );
  }

  Future<int> alreadyImported(int userId, Map<String, dynamic> plan) async {
    final db = await database.database;
    var count = 0;
    for (final root in plan['roots'] as List) {
      final source = await db.query(
        'feishu_containers',
        where: 'user_id=? AND container_type=? AND container_id=?',
        whereArgs: [
          userId,
          root['kind'] == 'docx' ? 'document' : root['kind'],
          root['id'],
        ],
      );
      final library =
          root['target_library_id'] ??
          (root['kind'] == 'docx' ? null : source.firstOrNull?['library_id']);
      if (library == null) continue;
      for (final doc in root['documents'] as List) {
        if ((await db.query(
          'feishu_documents',
          columns: ['source_id'],
          where: 'user_id=? AND library_id=? AND document_id=?',
          whereArgs: [userId, library, doc['document_id']],
        )).isNotEmpty) {
          count++;
        }
      }
    }
    return count;
  }

  Future<int> createJob(int userId, Map<String, dynamic> plan, int mode) async {
    await database.ensureSchemaReady();
    final db = await database.database;
    return db.transaction((txn) async {
      if ((await txn.query(
        'feishu_import_jobs',
        where: "user_id=? AND status IN ('queued','running','paused')",
        whereArgs: [userId],
      )).isNotEmpty) {
        throw StateError('已有未完成任务，请先恢复或取消');
      }
      int? looseLibrary;
      for (final root in plan['roots'] as List) {
        final kind = root['kind'] == 'docx' ? 'document' : root['kind'];
        int? target = root['target_library_id'];
        if (kind == 'document' && target == null) {
          final draft = plan['new_library'] as Map<String, dynamic>?;
          if (draft == null || '${draft['name'] ?? ''}'.trim().isEmpty) {
            throw StateError('请为单篇文档选择或创建知识库');
          }
          looseLibrary ??= await txn.insert('knowledge_libraries', {
            'user_id': userId,
            'name': draft['name'],
            'description': draft['description'] ?? '',
            'cover_theme': draft['cover_theme'] ?? 'math',
            'cover_color': draft['cover_color'] ?? 0xFF5B90FF,
            'created_at': now,
            'updated_at': now,
          });
          target = looseLibrary;
        }
        if (target != null &&
            (await txn.query(
              'knowledge_libraries',
              where: 'user_id=? AND id=?',
              whereArgs: [userId, target],
            )).isEmpty) {
          throw StateError('目标知识库不存在或不属于当前用户');
        }
        final mapping = await txn.query(
          'feishu_containers',
          where:
              'user_id=? AND container_type=? AND container_id=?${kind == 'document' ? ' AND library_id=?' : ''}',
          whereArgs: [userId, kind, root['id'], if (kind == 'document') target],
        );
        target = mapping.firstOrNull?['library_id'] as int? ?? target;
        target ??= await txn.insert('knowledge_libraries', {
          'user_id': userId,
          'name': root['name'],
          'description': '从飞书导入的学习资料',
          'created_at': now,
          'updated_at': now,
        });
        root['target_library_id'] = target;
        final selection = {
          'kind': root['kind'],
          'id': root['id'],
          'space_id': root['space_id'] ?? '',
          'excluded': root['excluded'] ?? [],
          'included': root['included'] ?? [],
          'include_future': (root['sync_mode'] ?? mode) == 2,
          'document_ids': (root['documents'] as List)
              .map((d) => d['document_id'])
              .toList(),
        };
        // Existing-document sync never broadens the previously approved document set.
        if (root['selection'] != null) {
          selection.addAll(Map<String, dynamic>.from(root['selection']));
        }
        selection['include_future'] = (root['sync_mode'] ?? mode) == 2;
        await txn.insert('feishu_containers', {
          'user_id': userId,
          'account_id': plan['account_id'],
          'container_type': kind,
          'container_id': root['id'],
          'library_id': target,
          'sync_mode': root['sync_mode'] ?? mode,
          'sync_status': 'pending',
          'selection_json': jsonEncode(selection),
          'synced_at': mapping.firstOrNull?['synced_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final roots = plan['roots'] as List;
      final id = await txn.insert('feishu_import_jobs', {
        'user_id': userId,
        'account_id': plan['account_id'],
        'status': 'queued',
        'plan_json': jsonEncode(plan),
        'sync_mode': mode,
        'total': roots.fold<int>(
          0,
          (sum, root) => sum + (root['documents'] as List).length,
        ),
        'created_at': now,
        'updated_at': now,
      });
      for (var i = 0; i < roots.length; i++) {
        for (final doc in roots[i]['documents'] as List) {
          await txn.insert('feishu_import_job_items', {
            'job_id': id,
            'root_index': i,
            'document_id': doc['document_id'],
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      return id;
    });
  }
}
