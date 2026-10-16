import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';
import 'package:pxt1/ui/pages/home_page.dart';
import 'package:pxt1/ui/pages/community/community_page.dart';
import 'package:pxt1/ui/pages/tabs/focus_tab_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'five-tab shell preserves task focus routing and community selection',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        final dir = await Directory.systemTemp.createTemp('pxt-shell-test-');
        await databaseFactory.setDatabasesPath(dir.path);
        final db = await AppDatabase.instance.database;
        final auth = AuthRepository();
        await auth.register(username: 'shell-test', password: 'local-test');
        final login = await auth.login(
          username: 'shell-test',
          password: 'local-test',
        );
        final task = await FocusRepository().createTask(
          userId: login.userId!,
          title: '导航验收任务',
        );
        return (db: db, dir: dir, task: task, login: login);
      }))!;
      final db = fixture.db;
      final dir = fixture.dir;
      final task = fixture.task;
      final login = fixture.login;
      Future<void> flush() async {
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
      }

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const HomePage(initialTab: 3)),
      );
      await flush();
      expect(tester.takeException(), isNull);
      final shell = find.byType(HomePage);
      expect(
        find.descendant(of: shell, matching: find.text('社区')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: shell, matching: find.text('知识库')),
        findsOneWidget,
      );
      await tester.tap(find.text('导航验收任务').first);
      await flush();
      await tester.tap(find.text('专注学习'));
      await flush();
      final focus = tester.widget<FocusTabPage>(find.byType(FocusTabPage));
      expect(focus.initialTaskId, task.id);
      await tester.pageBack();
      await flush();
      await tester.tap(find.text('社区'));
      await flush();
      expect(find.byType(CommunityPage), findsOneWidget);
      final stack = tester.widget<IndexedStack>(
        find.byType(IndexedStack).first,
      );
      expect(stack.index, 2);
      await tester.tap(find.text('我的'));
      await flush();
      expect(
        tester.widget<IndexedStack>(find.byType(IndexedStack).first).index,
        4,
      );
      expect(find.text('我的学习空间'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        (await tester.runAsync(
          () => db.query('pomodoro_tasks', where: 'id=?', whereArgs: [task.id]),
        ))!.single['user_id'],
        login.userId,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await db.close();
        await dir.delete(recursive: true);
      });
    },
  );
}
