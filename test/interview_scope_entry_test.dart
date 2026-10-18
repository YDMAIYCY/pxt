import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/import_record.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/import_record_detail_page.dart';
import 'package:pxt1/ui/pages/interview/interview_history_page.dart';
import 'package:pxt1/ui/pages/interview/interview_prepare_page.dart';
import 'package:pxt1/ui/pages/knowledge_record_list_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late KnowledgeLibraryRecord library;
  late ImportRecord record;

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    final db = await app.database;
    const now = '2026-10-18T09:00:00.000Z';
    await db.insert('users', {
      'id': 1,
      'username': 'fixture',
      'password_hash': 'fixture',
      'password_salt': 'fixture',
      'created_at': now,
      'updated_at': now,
    });
    library = await KnowledgeLibraryRepository(
      database: app,
    ).createLibrary(userId: 1, name: '当前课程');
    final document = await SourceDocumentRepository(database: app)
        .createSourceDocument(
          userId: 1,
          libraryId: library.id,
          sourceType: 'camera_capture',
          imagePath: '',
          title: '当前资料',
        );
    record = (await ImportRecordRepository(
      database: app,
    ).forDocument(1, document.id))!;
  });

  tearDown(() async => (await app.database).close());

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 16; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> show(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(390, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: page));
    await flush(tester);
  }

  testWidgets('library interview starts with the current library selected', (
    tester,
  ) async {
    await show(tester, BookDetailPage(library: library, database: app));
    await tester.ensureVisible(find.text('AI 面试'));
    await tester.tap(find.text('AI 面试'));
    await flush(tester);
    final page = tester.widget<InterviewPreparePage>(
      find.byType(InterviewPreparePage),
    );
    expect(page.userId, 1);
    expect(page.libraryId, library.id);
    expect(page.recordId, isNull);
    expect(find.text('当前课程'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library history keeps the current library scope', (
    tester,
  ) async {
    await show(tester, BookDetailPage(library: library, database: app));
    await tester.ensureVisible(find.text('面试历史'));
    await tester.tap(find.text('面试历史'));
    await flush(tester);
    final sheet = tester.widget<InterviewHistorySheet>(
      find.byType(InterviewHistorySheet),
    );
    expect(sheet.userId, 1);
    expect(sheet.libraryId, library.id);
    expect(sheet.recordId, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('record interview preserves the exact record and library scope', (
    tester,
  ) async {
    await show(
      tester,
      ImportRecordDetailPage(recordId: record.id, userId: 1, database: app),
    );
    await tester.scrollUntilVisible(
      find.text('AI 面试'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('AI 面试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI 面试'));
    await flush(tester);
    final page = tester.widget<InterviewPreparePage>(
      find.byType(InterviewPreparePage),
    );
    expect(page.userId, 1);
    expect(page.libraryId, library.id);
    expect(page.recordId, record.id);
    expect(find.text('当前资料'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
