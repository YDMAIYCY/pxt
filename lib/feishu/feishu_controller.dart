import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/app_database.dart';
import '../database/feishu_import_repository.dart';
import '../database/feishu_workflow_repository.dart';
import 'feishu_client.dart';

class FeishuController extends ChangeNotifier {
  FeishuController({
    required this.userId,
    AppDatabase? database,
    FeishuClient? client,
  }) : database = database ?? AppDatabase.instance,
       client = client ?? FeishuClient();
  static final Map<(AppDatabase, int), FeishuController> _instances = {};
  static FeishuController forUser(int userId, {AppDatabase? database}) =>
      _instances.putIfAbsent((
        database ?? AppDatabase.instance,
        userId,
      ), () => FeishuController(userId: userId, database: database));
  final int userId;
  final AppDatabase database;
  final FeishuClient client;
  static Future<void> signOut(AppDatabase database) async {
    for (final key in _instances.keys.where((k) => k.$1 == database).toList()) {
      final controller = _instances.remove(key)!;
      controller.cancelRequested = true;
      try {
        await controller.client.disconnect().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        // The ephemeral session is discarded even when the connector is offline.
      }
      controller.connected = false;
      controller.client.close();
    }
  }

  Future<void> expire() async {
    connected = false;
    final db = await database.database;
    if (connection?['account_id'] != null) {
      await db.update(
        'feishu_connections',
        {'auth_status': 'expired', 'updated_at': repository.now},
        where: 'user_id=? AND account_id=?',
        whereArgs: [userId, connection!['account_id']],
      );
      await db.update(
        'feishu_containers',
        {'sync_status': 'expired'},
        where: 'user_id=? AND account_id=?',
        whereArgs: [userId, connection!['account_id']],
      );
    }
    notifyListeners();
  }

  Future<bool> disconnect() async {
    cancelRequested = true;
    var revoked = true;
    try {
      await client.disconnect();
    } catch (_) {
      revoked = false;
    } finally {
      await expire();
      connection = null;
    }
    return revoked;
  }

  FeishuWorkflowRepository get repository =>
      FeishuWorkflowRepository(database: database);
  bool connected = false, running = false, cancelRequested = false;
  Future<void>? _initialization;
  Map<String, dynamic>? connection;
  int? jobId;
  int completed = 0, total = 0;
  String message = '';

  Future<void> initialize() => _initialization ??= _restore();
  Future<void> _restore() async {
    await database.ensureSchemaReady();
    final db = await database.database;
    await db.update(
      'feishu_import_jobs',
      {'status': 'paused'},
      where: "user_id=? AND status IN ('running','queued')",
      whereArgs: [userId],
    );
    await db.update(
      'feishu_containers',
      {'sync_status': 'pending'},
      where: "user_id=? AND sync_status='syncing'",
      whereArgs: [userId],
    );
  }

  Future<void> checkConnection() async {
    if (!client.hasSession) {
      connected = false;
      notifyListeners();
      return;
    }
    try {
      connection = await client.request('GET', '/connection');
    } on FeishuException catch (error) {
      if (error.statusCode == 401) await expire();
      rethrow;
    }
    connected = connection!['status'] == 'connected';
    await repository.connection(userId, connection!);
    if (connected) {
      final db = await database.database;
      await db.update(
        'feishu_containers',
        {'sync_status': 'pending'},
        where: "user_id=? AND account_id=? AND sync_status='expired'",
        whereArgs: [userId, connection!['account_id']],
      );
    }
    notifyListeners();
  }

  Future<int> importPlan(Map<String, dynamic> plan, int mode) async {
    await initialize();
    if (!connected || connection?['account_id'] != plan['account_id']) {
      throw StateError('请连接扫描资料所用的飞书账号');
    }
    final id = await repository.createJob(userId, plan, mode);
    unawaited(run(id));
    return id;
  }

  void cancel() {
    cancelRequested = true;
    message = '等待当前请求结束后取消，已导入文档将保留';
    notifyListeners();
  }

  Future<void> run(int id) async {
    if (running) return;
    running = true;
    cancelRequested = false;
    completed = 0;
    total = 0;
    jobId = id;
    message = '正在读取导入任务…';
    notifyListeners();
    try {
      await _runJob(id);
    } catch (error) {
      message = '$error';
      final db = await database.database;
      await db.update(
        'feishu_import_jobs',
        {'status': 'paused', 'error': message, 'updated_at': repository.now},
        where: 'id=? AND user_id=?',
        whereArgs: [id, userId],
      );
    } finally {
      running = false;
      notifyListeners();
    }
  }

  Future<void> _runJob(int id) async {
    await initialize();
    final db = await database.database;
    final job = (await db.query(
      'feishu_import_jobs',
      where: 'id=? AND user_id=?',
      whereArgs: [id, userId],
    )).single;
    if (!connected || connection?['account_id'] != job['account_id']) {
      message = '请连接原飞书账号后恢复任务';
      notifyListeners();
      return;
    }
    jobId = id;
    total = job['total'] as int;
    completed = 0;
    message = '准备导入 $total 篇文档';
    notifyListeners();
    final plan = jsonDecode(job['plan_json'] as String) as Map<String, dynamic>;
    var failed = 0;
    var interrupted = false;
    Future<void> sourceState(Map root, String status, [String? error]) async {
      await db.update(
        'feishu_containers',
        {
          'sync_status': status,
          'error': error,
          if (status == 'synced') 'synced_at': repository.now,
        },
        where:
            'user_id=? AND library_id=? AND container_type=? AND container_id=?',
        whereArgs: [
          userId,
          root['target_library_id'],
          root['kind'] == 'docx' ? 'document' : root['kind'],
          root['id'],
        ],
      );
    }

    try {
      await db.update(
        'feishu_import_jobs',
        {'status': 'running', 'error': null, 'updated_at': repository.now},
        where: 'id=?',
        whereArgs: [id],
      );
      final roots = plan['roots'] as List;
      for (var i = 0; i < roots.length; i++) {
        final root = roots[i] as Map<String, dynamic>;
        await sourceState(root, 'syncing');
        var rootFailures = 0;
        for (final meta in root['documents'] as List) {
          if (cancelRequested) break;
          final item = (await db.query(
            'feishu_import_job_items',
            where: 'job_id=? AND root_index=? AND document_id=?',
            whereArgs: [id, i, meta['document_id']],
          )).single;
          if (item['status'] == 'done') {
            completed++;
            continue;
          }
          message = '正在读取 ${meta['title']}';
          notifyListeners();
          try {
            final doc = await client.request(
              'GET',
              '/documents/${meta['document_id']}',
            );
            if (cancelRequested) break;
            message = '正在保存 ${meta['title']}';
            notifyListeners();
            await FeishuImportRepository(database: database).save(userId, {
              'account_id': plan['account_id'],
              'container_type': root['kind'] == 'docx'
                  ? 'document'
                  : root['kind'],
              'container_id': root['id'],
              'container_name': root['name'],
              'target_library_id': root['target_library_id'],
              'sync_mode': job['sync_mode'],
              'documents': [
                <String, dynamic>{
                  ...Map<String, dynamic>.from(meta as Map),
                  ...doc,
                },
              ],
            });
            await db.update(
              'feishu_import_job_items',
              {'status': 'done', 'error': null},
              where: 'job_id=? AND root_index=? AND document_id=?',
              whereArgs: [id, i, meta['document_id']],
            );
            completed++;
          } catch (error) {
            failed++;
            rootFailures++;
            await db.update(
              'feishu_import_job_items',
              {'status': 'failed', 'error': '$error'},
              where: 'job_id=? AND root_index=? AND document_id=?',
              whereArgs: [id, i, meta['document_id']],
            );
            if (error is FeishuException && error.statusCode == 401) {
              await expire();
              interrupted = true;
              await sourceState(root, 'expired', '$error');
              break;
            }
          }
          await db.update(
            'feishu_import_jobs',
            {'completed': completed, 'updated_at': repository.now},
            where: 'id=?',
            whereArgs: [id],
          );
          notifyListeners();
        }
        if (!interrupted) {
          final rootErrors = (plan['errors'] as List)
              .where((e) => e['root_id'] == root['id'])
              .toList();
          await sourceState(
            root,
            cancelRequested
                ? 'pending'
                : rootFailures > 0 || rootErrors.isNotEmpty
                ? 'failed'
                : 'synced',
            rootFailures > 0
                ? '部分文档未导入，可重试'
                : rootErrors.isNotEmpty
                ? '目录有未读取分支，请重新扫描'
                : null,
          );
        }
        if (cancelRequested || interrupted) break;
      }
      final status = interrupted
          ? 'paused'
          : cancelRequested
          ? 'cancelled'
          : failed > 0 || (plan['errors'] as List).isNotEmpty
          ? 'partial'
          : 'done';
      message = interrupted
          ? '授权已失效，请重新连接后恢复任务'
          : cancelRequested
          ? '已取消，已导入 $completed 篇'
          : '成功 $completed 篇，失败 $failed 篇${(plan['errors'] as List).isEmpty ? '' : '；目录有未读取分支，请重新扫描'}';
      await db.update(
        'feishu_import_jobs',
        {
          'status': status,
          'completed': completed,
          'error': message,
          'updated_at': repository.now,
        },
        where: 'id=?',
        whereArgs: [id],
      );
    } catch (error) {
      message = '$error';
      for (final root in plan['roots'] as List) {
        await sourceState(root as Map, 'pending', message);
      }
      await db.update(
        'feishu_import_jobs',
        {'status': 'paused', 'error': message, 'updated_at': repository.now},
        where: 'id=?',
        whereArgs: [id],
      );
    } finally {
      running = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> syncPlan(int libraryId) async {
    await checkConnection();
    if (!connected) throw StateError('请先连接飞书账号');
    final sources = await repository.sources(userId, libraryId);
    final eligible = sources.where((s) => s['sync_mode'] != 0).toList();
    if (eligible.isEmpty) throw StateError('此知识库选择了“仅导入一次”，请重新选择资料以启用同步');
    if (eligible.any((s) => s['account_id'] != connection!['account_id'])) {
      throw StateError('请连接该知识库原来的飞书账号');
    }
    final roots = eligible.map((s) {
      final selection =
          jsonDecode(s['selection_json'] as String) as Map<String, dynamic>;
      return {...selection, if (s['sync_mode'] == 2) 'document_ids': null};
    }).toList();
    final plan = await client.request(
      'POST',
      '/imports/scan',
      body: {'roots': roots},
    );
    final db = await database.database;
    for (final failure in plan['errors'] as List) {
      await db.update(
        'feishu_containers',
        {'sync_status': 'failed', 'error': '${failure['detail']['message']}'},
        where: 'user_id=? AND library_id=? AND container_id=?',
        whereArgs: [userId, libraryId, failure['root_id']],
      );
    }
    if ((plan['roots'] as List).isEmpty) throw StateError('未能读取同步来源，请检查权限后重试');
    for (final root in plan['roots'] as List) {
      final source = eligible.firstWhere(
        (s) => s['container_id'] == root['id'],
      );
      root['target_library_id'] = libraryId;
      root['selection'] = jsonDecode(source['selection_json'] as String);
      root['sync_mode'] = source['sync_mode'];
    }
    return plan;
  }
}
