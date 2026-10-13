import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/ui/pages/book_library_page.dart';
import 'package:pxt1/ui/pages/knowledge_record_list_page.dart';
import 'package:pxt1/ui/pages/import_record_detail_page.dart';
import 'package:pxt1/ui/pages/record_source_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const now = '2026-10-13T01:00:00.000Z';
  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'fixture',
      'password_hash': 'fixture',
      'password_salt': 'fixture',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'test-session',
      'created_at': now,
    });
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: page),
      ),
    );
    // Real SQLite FFI runs outside fake widget time.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'shelf creates a persistent custom book and opens its empty record list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester, BookLibraryPage(database: app));
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '知识库名称'), '自定义课程');
      await tester.tap(find.text('网络节点'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建知识库'));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('自定义课程'), findsOneWidget);
      final libraries = await tester.runAsync(
        () => KnowledgeLibraryRepository(database: app).fetchLibraries(1),
      );
      expect(
        libraries!.singleWhere((l) => l.name == '自定义课程').coverTheme,
        'network',
      );
      await tester.tap(find.text('自定义课程'));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('还没有导入记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'returning from source refreshes the same record without a Future setState assertion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final lib = await tester.runAsync(
        () => KnowledgeLibraryRepository(
          database: app,
        ).createLibrary(userId: 1, name: '返回测试'),
      );
      final doc = await tester.runAsync(
        () => SourceDocumentRepository(database: app).createSourceDocument(
          userId: 1,
          libraryId: lib!.id,
          sourceType: 'camera_capture',
          imagePath: '/fixture.png',
          title: '同一条记录',
        ),
      );
      final record = await tester.runAsync(
        () => ImportRecordRepository(database: app).forDocument(1, doc!.id),
      );
      await pump(
        tester,
        ImportRecordDetailPage(recordId: record!.id, userId: 1, database: app),
      );
      await tester.scrollUntilVisible(
        find.text('原始资料 / OCR 文本'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('原始资料 / OCR 文本'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordSourcePage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(ImportRecordDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [360.0, 390.0, 430.0]) {
    testWidgets(
      'three real-data pages fit ${width.toInt()}dp with long titles and enlarged text',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 850));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final lib = await tester.runAsync(
          () => KnowledgeLibraryRepository(database: app).createLibrary(
            userId: 1,
            name: '很长的课程名称与知识体系',
            coverTheme: 'letters',
          ),
        );
        final doc = await tester.runAsync(
          () => SourceDocumentRepository(database: app).createSourceDocument(
            userId: 1,
            libraryId: lib!.id,
            sourceType: 'camera_capture',
            imagePath: '/nonexistent-fixture.png',
            title: '一条很长的多章节函数与极限学习资料记录标题',
          ),
        );
        final record = await tester.runAsync(
          () => ImportRecordRepository(database: app).forDocument(1, doc!.id),
        );
        await pump(tester, BookLibraryPage(database: app), scale: 1.3);
        expect(find.text('学习资料知识库'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await pump(
          tester,
          BookDetailPage(library: lib!, database: app),
          scale: 1.3,
        );
        expect(find.textContaining('一条很长'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await pump(
          tester,
          ImportRecordDetailPage(
            recordId: record!.id,
            userId: 1,
            database: app,
          ),
          scale: 1.3,
        );
        expect(find.text('尚未生成 · 点击生成'), findsWidgets);
        expect(find.text('1 张卡片'), findsNothing);
        await tester.drag(find.byType(ListView).first, const Offset(0, -650));
        await tester.pumpAndSettle();
        expect(find.text('错题解析'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await pump(
          tester,
          RecordSourcePage(record: record, database: app),
          scale: 1.3,
        );
        expect(find.text('第 1 页 OCR 文本'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
