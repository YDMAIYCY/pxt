// Offline UI fixtures only; these do not establish real Feishu access.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/feishu/feishu_client.dart';
import 'package:pxt1/ui/pages/feishu_import_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/feishu/feishu_controller.dart';

class ConnectedFixtureClient extends FeishuClient {
  ConnectedFixtureClient()
    : super(
        client: MockClient((request) async {
          if (request.url.path == '/connection') {
            return http.Response(
              jsonEncode({
                'status': 'connected',
                'account_id': 'tenant:user',
                'can_refresh': true,
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'items': [
                for (final entry in [
                  ('DocA', 'docx', 'fixture document'),
                  ('SheetA', 'sheet', 'fixture sheet'),
                  ('FolderA', 'folder', 'fixture folder'),
                ])
                  {
                    'key': '${entry.$2}:${entry.$1}',
                    'id': entry.$1,
                    'kind': entry.$2,
                    'name': entry.$3,
                    'account_id': 'tenant:user',
                    'has_children': entry.$2 == 'folder',
                  },
              ],
              'has_more': false,
            }),
            200,
          );
        }),
      );
  @override
  bool get hasSession => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
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
    await FeishuController.forUser(1, database: app).initialize();
  });
  tearDown(() async => db.close());

  testWidgets(
    'unconnected picker renders inside the real themed tab navigator',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            extendBody: true,
            bottomNavigationBar: const SizedBox(height: 92),
            body: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute(
                builder: (_) => FeishuImportPage(userId: 1, database: app),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未连接飞书账号'), findsOneWidget);
      expect(find.text('连接我的飞书账号'), findsOneWidget);
      expect(find.text('下一步：确认导入'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        find.widgetWithText(FilledButton, '下一步：确认导入'),
      );
      expect(button.bottom, closeTo(692,1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'small-screen picker uses normalized resources and retains selection across tabs',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = ConnectedFixtureClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: FeishuImportPage(userId: 1, database: app, client: client),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('我已授权，检查连接状态'));
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pumpAndSettle();
      expect(find.text('fixture document'), findsOneWidget);
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes, hasLength(3));
      expect(boxes[1].onChanged, isNull);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await tester.tap(find.text('文件夹').first);
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);
      await tester.tap(find.text('云文档'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sheet');
      await tester.pumpAndSettle();
      expect(find.text('fixture document'), findsNothing);
      expect(find.text('fixture sheet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );
}
