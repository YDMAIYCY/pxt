import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/learning/learning_events.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/knowledge_record_list_page.dart';
import 'package:pxt1/ui/pages/learning_concept_page.dart';
import 'package:pxt1/ui/pages/library_practice_page.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  final now = DateTime.now().toUtc();

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    for (final id in [1, 2]) {
      await db.insert('users', {'id': id, 'username': 'user$id',
        'password_hash': 'test', 'password_salt': 'test',
        'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String()});
    }
    await db.insert('auth_sessions', {'user_id': 1, 'session_token': 'fixture',
      'created_at': now.toIso8601String()});
    for (final id in [1, 2, 3]) {
      await db.insert('knowledge_libraries', {'id': id, 'user_id': id == 3 ? 2 : 1,
        'name': 'Library $id', 'created_at': now.toIso8601String(),
        'updated_at': now.subtract(Duration(days: id)).toIso8601String()});
      await db.insert('source_documents', {'id': id, 'user_id': id == 3 ? 2 : 1,
        'library_id': id, 'source_type': 'gallery_import', 'image_path': '',
        'original_title': 'Source $id', 'created_at': now.toIso8601String()});
    }
    await db.insert('knowledge_concepts', {'id': 10, 'user_id': 1,
      'library_id': 2, 'document_id': 2, 'name': 'Atomicity',
      'summary': 'Commit all changes together.', 'evidence_text': 'All or nothing.',
      'mastery_score': 40, 'weakness_score': 60,
      'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String()});
    for (final id in [1, 2, 3, 4, 5]) {
      await db.insert('practice_questions', {'id': id,
        'document_id': id == 1 ? 1 : id == 5 ? 3 : 2,
        'question_text': 'Question $id', 'answer_text': 'A',
        'review_status': id == 4 ? 'wrong' : 'pending',
        'wrong_count': id == 2 ? 1 : 0,
        'next_review_at': now.add(Duration(days: id == 3 ? 2 : -2)).toIso8601String(),
        'created_at': now.toIso8601String()});
    }
    for (final id in [2, 3, 4]) {
      await db.insert('question_concepts', {'question_id': id, 'concept_id': 10});
    }
  });

  tearDown(() async => db.close());

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await flush(tester);
  }

  testWidgets('task question uses its document library and starts that exact question', (tester) async {
    await show(tester, LibraryPracticePage(initialQuestionId: 2, documentId: 2, database: app));
    expect(find.text('当前范围：1 道题'), findsOneWidget);
    final library = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>).first);
    expect(library.initialValue, 2);
    await tester.tap(find.text('开始练习'));
    await flush(tester);
    expect(find.text('Question 2'), findsOneWidget);
    expect(find.text('Question 1'), findsNothing);
    expect(tester.widget<ScopedPracticeRunner>(find.byType(ScopedPracticeRunner))
        .scope.documentId, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exact question list preserves initial question and never includes other questions', (tester) async {
    await show(tester, LibraryPracticePage(questionIds: const [1, 3, 2],
        initialQuestionId: 3, database: app));
    await tester.tap(find.text('开始练习'));
    await flush(tester);
    final runner = tester.widget<ScopedPracticeRunner>(find.byType(ScopedPracticeRunner));
    expect(runner.questions.map((q) => q.question.id), [3, 1, 2]);
    expect(runner.scope.libraryId, isNull);
    expect(find.text('Question 3'), findsOneWidget);
  });

  testWidgets('task scope can switch libraries and practice the newly selected questions', (tester) async {
    await show(tester, LibraryPracticePage(initialQuestionId: 2, documentId: 2, database: app));
    final fields = find.byType(DropdownButtonFormField<int>);
    for (final field in tester.widgetList<DropdownButtonFormField<int>>(fields)) {
      expect(field.onChanged, isNotNull);
    }
    await tester.tap(fields.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Library 1').last);
    await flush(tester);
    expect(find.text('当前范围：1 道题'), findsOneWidget);
    await tester.tap(find.text('开始练习'));
    await flush(tester);
    final runner = tester.widget<ScopedPracticeRunner>(find.byType(ScopedPracticeRunner));
    expect(runner.scope.libraryId, 1);
    expect(runner.scope.documentId, isNull);
    expect(runner.questions.map((q) => q.question.id), [1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing imported material resets concept and original question restrictions', (tester) async {
    await tester.runAsync(() async {
      for (final id in [20, 21]) {
        await db.insert('import_records', {'id': id, 'user_id': 1,
          'library_id': 2, 'operation_id': 'record-$id', 'title': 'Material $id',
          'created_at': now.toIso8601String(), 'updated_at': now.toIso8601String()});
      }
      await db.update('source_documents', {'import_record_id': 20}, where: 'id=2');
      await db.insert('source_documents', {'id': 4, 'user_id': 1, 'library_id': 2,
        'import_record_id': 21, 'source_type': 'gallery_import', 'image_path': '',
        'original_title': 'Source 4', 'created_at': now.toIso8601String()});
      await db.insert('practice_questions', {'id': 6, 'document_id': 4,
        'question_text': 'Question 6', 'review_status': 'pending',
        'created_at': now.toIso8601String()});
    });
    await show(tester, LibraryPracticePage(initialConceptId: 10,
        initialQuestionId: 2, documentId: 2, database: app));
    expect(find.text('Material 20'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Material 21').last);
    await flush(tester);
    expect(find.text('全部知识点'), findsOneWidget);
    await tester.tap(find.text('开始练习'));
    await flush(tester);
    final runner = tester.widget<ScopedPracticeRunner>(find.byType(ScopedPracticeRunner));
    expect(runner.scope.recordId, 21);
    expect(runner.scope.conceptId, isNull);
    expect(runner.questions.map((q) => q.question.id), [6]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exact question filters can be empty without reporting deleted questions', (tester) async {
    await show(tester, LibraryPracticePage(questionIds: const [2, 3], database: app));
    await tester.tap(find.text('到期复习'));
    await flush(tester);
    expect(find.text('当前范围：1 道题'), findsOneWidget);
    await tester.tap(find.text('只练错题'));
    await flush(tester);
    expect(find.text('当前范围：1 道题'), findsOneWidget);
    await tester.tap(find.text('只练错题'));
    await flush(tester);
    await tester.tap(find.text('到期复习'));
    await flush(tester);
    expect(find.text('当前范围：2 道题'), findsOneWidget);
    await show(tester, LibraryPracticePage(questionIds: const [3], database: app,
        key: const ValueKey('empty-filter')));
    await tester.tap(find.text('只练错题'));
    await flush(tester);
    expect(find.text('当前范围：0 道题'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始练习')).onPressed, isNull);
    expect(find.text('无法加载练习范围'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('concept selector filters real questions and generation settings are separate', (tester) async {
    await show(tester, LibraryPracticePage(libraryId: 2, database: app));
    await tester.tap(find.byType(DropdownButtonFormField<int>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atomicity').last);
    await flush(tester);
    expect(find.text('当前范围：3 道题'), findsOneWidget);
    expect(find.text('出题设置'), findsNothing);
    await tester.tap(find.text('AI 出新题'));
    await tester.pumpAndSettle();
    expect(find.text('筛选已有题'), findsNothing);
    await tester.ensureVisible(find.text('10 道'));
    await tester.tap(find.text('10 道'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('生成 10 道题并练习'));
    await tester.tap(find.text('生成 10 道题并练习'));
    await flush(tester);
    expect(find.textContaining('请先在“我的”配置 AI 模型'), findsOneWidget);
    expect(await tester.runAsync(() => db.query('practice_questions')), hasLength(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicting and foreign question scopes do not fall back to another library', (tester) async {
    await show(tester, LibraryPracticePage(initialQuestionId: 2, documentId: 1, database: app));
    expect(find.textContaining('所选练习来源不存在或无权访问'), findsOneWidget);
    await show(tester, LibraryPracticePage(initialQuestionId: 5, database: app,
        key: const ValueKey('foreign')));
    expect(find.textContaining('所选练习来源不存在或无权访问'), findsOneWidget);
    expect(find.text('开始练习'), findsNothing);
  });

  testWidgets('concept displays actual content and wrong questions without completing on open', (tester) async {
    await tester.runAsync(() => db.insert('pomodoro_tasks', {'user_id': 1, 'title': 'Review atomicity',
      'kind': 'concept_review', 'concept_id': 10, 'document_id': 2,
      'created_at': now.toIso8601String()}));
    await show(tester, LearningConceptPage(conceptId: 10, database: app));
    expect(find.text('Commit all changes together.'), findsOneWidget);
    expect(find.text('All or nothing.'), findsOneWidget);
    expect(find.text('实际作答 0 次 · 待巩固错题 2 道'), findsOneWidget);
    final tasks = await tester.runAsync(() => db.query('pomodoro_tasks'));
    expect(tasks!.single['status'], 'pending');
    expect(await tester.runAsync(() => db.query('practice_submissions')), isEmpty);
    await tester.tap(find.text('练习这个知识点'));
    await flush(tester);
    final page = tester.widget<LibraryPracticePage>(find.byType(LibraryPracticePage));
    expect(page.initialConceptId, 10);
    expect(page.documentId, 2);
    expect(find.text('当前范围：3 道题'), findsOneWidget);
  });

  testWidgets('record concepts open the matching learning concept detail', (tester) async {
    final library = (await tester.runAsync(() => KnowledgeLibraryRepository(database: app).fetchLibraries(1)))!
        .firstWhere((l) => l.id == 2);
    await show(tester, BookDetailPage(library: library, database: app));
    await tester.tap(find.text('本次记录的知识点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atomicity'));
    await flush(tester);
    expect(find.byType(LearningConceptPage), findsOneWidget);
    expect(find.text('Commit all changes together.'), findsOneWidget);
  });

  testWidgets('home wrong count and exact link include pending errors and refresh on learning events', (tester) async {
    await show(tester, HomeTabPage(database: app,
      authRepository: AuthRepository(database: app),
      sourceDocumentRepository: SourceDocumentRepository(database: app),
      knowledgeLibraryRepository: KnowledgeLibraryRepository(database: app)));
    Finder metric() => find.ancestor(of: find.text('待处理错题').first,
        matching: find.byType(InkWell)).first;
    expect(find.descendant(of: metric(), matching: find.text('2')), findsOneWidget);
    await tester.runAsync(() => db.update('practice_questions', {'wrong_count': 1},
        where: 'id=?', whereArgs: [3]));
    LearningEvents.notify();
    await flush(tester);
    expect(find.descendant(of: metric(), matching: find.text('3')), findsOneWidget);
    await tester.tap(find.text('待处理错题').first);
    await flush(tester);
    final page = tester.widget<LibraryPracticePage>(find.byType(LibraryPracticePage));
    expect(page.questionIds, unorderedEquals([2, 3, 4]));
    expect(find.text('当前范围：3 道题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
