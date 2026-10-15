// Offline UI integration: real SQLite and existing routes, no provider or model calls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/feishu_import_repository.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/knowledge_context_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/generator/graph_builder_service.dart';
import 'package:pxt1/ui/pages/ai_chat_page.dart';
import 'package:pxt1/ui/pages/feishu_library_detail_page.dart';
import 'package:pxt1/ui/pages/feishu_source_view.dart';
import 'package:pxt1/ui/pages/knowledge_graph_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

Future<void> flushDatabase(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late KnowledgeLibraryRecord library;
  late SourceDocumentRecord source;
  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    final auth = AuthRepository(database: app);
    await auth.register(username: 'feishu-tools', password: 'offline-test');
    final login = await auth.login(
      username: 'feishu-tools',
      password: 'offline-test',
    );
    await FeishuImportRepository(database: app).save(login.userId!, {
      'account_id': 'tenant:user',
      'container_type': 'folder',
      'container_id': 'FolderA',
      'container_name': '飞书测试库',
      'documents': [
        {
          'document_id': 'DocA',
          'title': '函数与极限',
          'text': '函数极限描述函数在某点附近的变化。',
          'blocks': <Map<String, dynamic>>[],
          'revision_id': 1,
        },
      ],
    });
    library = (await KnowledgeLibraryRepository(
      database: app,
    ).fetchLibraries(login.userId!, source: 'feishu')).single;
    source = (await ImportRecordRepository(
      database: app,
    ).list(login.userId!, libraryId: library.id)).single.anchor;
  });
  tearDown(() async => db.close());

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FeishuLibraryDetailPage(library: library, database: app),
                ),
              ),
              child: const Text('打开知识库'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开知识库'));
    await flushDatabase(tester);
    expect(find.text('查看知识图谱'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
    expect(find.byTooltip('问 EClaw'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'Feishu library opens existing EClaw and graph routes scoped to the current library',
    (tester) async {
      await openLibrary(tester);
      await tester.tap(find.byTooltip('问 EClaw'));
      await flushDatabase(tester);
      final chat = tester.widget<AiChatPage>(find.byType(AiChatPage));
      expect(chat.initialContext.knowledgeBaseId, library.id);
      expect(chat.database, same(app));
      Navigator.of(tester.element(find.byType(AiChatPage))).pop();
      await flushDatabase(tester);
      await tester.tap(find.text('查看知识图谱'));
      await flushDatabase(tester);
      final graph = tester.widget<KnowledgeGraphPage>(
        find.byType(KnowledgeGraphPage),
      );
      expect(graph.initialLibraryIds, [library.id]);
      expect(graph.userId, library.userId);
      expect(graph.database, same(app));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Feishu management saves edits and deletion keeps imported content',
    (tester) async {
      await openLibrary(tester);
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('修改名称、简介和封面'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '更新后的飞书知识库');
    await tester.ensureVisible(find.text('保存修改'));
    await tester.tap(find.text('保存修改'));
      await flushDatabase(tester);
      final saved = (await tester.runAsync(
        () => db.query(
          'knowledge_libraries',
          where: 'id=?',
          whereArgs: [library.id],
        ),
      ))!.single;
      expect(saved['name'], '更新后的飞书知识库');
      expect(find.text('更新后的飞书知识库'), findsWidgets);
      await tester.tap(find.text('管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除知识库，保留学习资料'));
      await tester.pumpAndSettle();
      expect(find.textContaining('飞书原文件不会删除'), findsOneWidget);
      await tester.tap(find.text('删除').last);
      await flushDatabase(tester);
      expect(find.text('打开知识库'), findsOneWidget);
      final moved = (await tester.runAsync(
        () =>
            db.query('source_documents', where: 'id=?', whereArgs: [source.id]),
      ))!.single;
      expect(moved['library_id'], isNot(library.id));
      final metadata = (await tester.runAsync(
        () => db.query('feishu_documents'),
      ))!.single;
      expect(metadata['source_id'], source.id);
      expect(metadata['library_id'], moved['library_id']);
      expect(await tester.runAsync(() => db.query('ocr_texts')), hasLength(1));
      expect(
        await tester.runAsync(() => db.query('import_records')),
        hasLength(1),
      );
      expect(
        await tester.runAsync(() => db.query('feishu_containers')),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'single Feishu document opens EClaw with document and record scope',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: FeishuSourceView(source: source, database: app),
        ),
      );
      await flushDatabase(tester);
      await tester.tap(find.byTooltip('问 EClaw'));
      await flushDatabase(tester);
      final scope = tester
          .widget<AiChatPage>(find.byType(AiChatPage))
          .initialContext;
      expect(scope.knowledgeBaseId, library.id);
      expect(scope.importRecordId, source.importRecordId);
      expect(scope.documentId, source.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'existing EClaw retrieval and graph source collection read Feishu text',
    () async {
      final evidence = await KnowledgeContextRepository(database: app).search(
        userId: library.userId,
        query: '函数极限',
        knowledgeBaseId: library.id,
        documentId: source.id,
      );
      expect(evidence, isNotEmpty);
      expect(evidence.every((item) => item.documentId == source.id), isTrue);
      final bundle = await KnowledgeGraphBuilder(
        database: app,
      ).collectSourceBundle(userId: library.userId, documentId: source.id);
      expect(bundle, isNotNull);
      expect(bundle!.hasUsableText, isTrue);
      expect(bundle.libraryId, library.id);
    },
  );
}
