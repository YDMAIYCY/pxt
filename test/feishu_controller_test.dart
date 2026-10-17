// Offline workflow regression. Uses the real SQLite repositories, never live API evidence.
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/feishu/feishu_client.dart';
import 'package:pxt1/feishu/feishu_controller.dart';
import 'package:pxt1/ui/pages/feishu_import_confirm_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

class _DocumentClient extends FeishuClient {
  int reads = 0;
  bool reject = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    reads++;
    if (reject) throw FeishuException('fixture no access', statusCode: 403);
    if (pending != null) return pending!.future;
    return jsonDecode(
          '{"document_id":"DocA","title":"Fixture","text":"body","blocks":[{"block_id":"b","block_type":2}],"revision_id":1}',
        )
        as Map<String, dynamic>;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late FeishuController controller;
  late _DocumentClient client;
  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'fixture',
      'password_hash': 'fixture',
      'password_salt': 'fixture',
      'created_at': '2026-10-15',
      'updated_at': '2026-10-15',
    });
    client = _DocumentClient();
    controller = FeishuController(userId: 1, database: app, client: client)
      ..connected = true
      ..connection = {'account_id': 'tenant:user'};
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    client.close();
    await db.close();
  });

  test(
    'confirmed selection runs through controller to persisted completion and resumes idempotently',
    () async {
      final plan =
          jsonDecode(
                '{"account_id":"tenant:user","roots":[{"kind":"docx","id":"DocA","name":"Fixture","documents":[{"document_id":"DocA","title":"Fixture","relative_path":"Fixture"}]}],"errors":[],"new_library":{"name":"Fixture Library"}}',
              )
              as Map<String, dynamic>;
      final id = await controller.importPlan(plan, 1);
      await Future<void>(() async {
        while (controller.running) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }).timeout(const Duration(seconds: 5));
      final job = (await db.query(
        'feishu_import_jobs',
        where: 'id=?',
        whereArgs: [id],
      )).single;
      expect(
        job['status'],
        'done',
        reason:
            '${job['error']} ${(await db.query('feishu_import_job_items')).single['error']}',
      );
      expect(controller.running, isFalse);
      expect(controller.total, 1);
      expect(controller.completed, 1);
      expect(
        (await db.query('feishu_import_job_items')).single['status'],
        'done',
      );
      final source = (await db.query('source_documents')).single['id'];
      await controller.run(id);
      expect((await db.query('source_documents')).single['id'], source);
      expect(client.reads, 1);
    },
  );

  test(
    'failed item can resume without recreating its knowledge library',
    () async {
      client.reject = true;
      final plan =
          jsonDecode(
                '{"account_id":"tenant:user","roots":[{"kind":"folder","id":"FolderA","name":"Fixture","documents":[{"document_id":"DocA","title":"Fixture","relative_path":"Fixture"}]}],"errors":[]}',
              )
              as Map<String, dynamic>;
      final id = await controller.importPlan(plan, 1);
      while (controller.running) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        (await db.query('feishu_import_jobs')).single['status'],
        'partial',
      );
      expect(controller.message, contains('失败 1'));
      final library = (await db.query(
        'feishu_containers',
      )).single['library_id'];
      client.reject = false;
      await controller.run(id).timeout(const Duration(seconds: 5));
      expect((await db.query('feishu_import_jobs')).single['status'], 'done');
      expect(
        (await db.query('feishu_containers')).single['library_id'],
        library,
      );
      expect(
        (await db.query('feishu_documents')).single['library_id'],
        library,
      );
    },
  );

  testWidgets(
    'confirmation navigates to progress, then completion replaces the spinner',
    (tester) async {
      client.pending = Completer<Map<String, dynamic>>();
      final plan =
          jsonDecode(
                '{"account_id":"tenant:user","roots":[{"kind":"folder","id":"FolderA","name":"Fixture","documents":[{"document_id":"DocA","title":"Fixture","relative_path":"Fixture"}]}],"errors":[],"covered_selections":[],"scan_complete":true}',
              )
              as Map<String, dynamic>;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: FeishuImportConfirmPage(controller: controller, plan: plan),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.text('开始导入 1 篇文档').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
      }
      expect(
        find.text('开始导入 1 篇文档'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('\n'),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('开始导入 1 篇文档'));
        while (client.reads == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('0/1 篇'), findsOneWidget);
      expect(find.text('正在读取 Fixture'), findsOneWidget);
      await tester.runAsync(() async {
        client.pending!.complete(
          jsonDecode(
                '{"document_id":"DocA","title":"Fixture","text":"body","blocks":[{"block_id":"b","block_type":2}],"revision_id":1}',
              )
              as Map<String, dynamic>,
        );
        await Future<void>(() async {
          while (controller.running) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }).timeout(const Duration(seconds: 5));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      for (
        var i = 0;
        i < 100 && find.text('已完成').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 500));
      // The status is now a tag beside the job number rather than a suffix of
      // the same string, so assert both halves.
      expect(find.text('任务 1'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('成功 1 / 1 篇'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
