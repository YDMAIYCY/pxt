import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/record_results_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/ui/widgets/record_mindmap_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'record search highlights in-place and keeps all stored diagrams with one search box',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final app = await AppDatabase.openForTesting(databaseFactoryFfi);
        final db = await app.database;
        const now = '2026-10-17T01:00:00Z';
        await db.insert('users', {
          'id': 1,
          'username': 'fixture',
          'password_hash': 'fixture',
          'password_salt': 'fixture',
          'created_at': now,
          'updated_at': now,
        });
        await db.insert('knowledge_libraries', {
          'id': 1,
          'user_id': 1,
          'name': '学习库',
          'created_at': now,
          'updated_at': now,
        });
        final source = await SourceDocumentRepository(database: app)
            .createSourceDocument(
              userId: 1,
              libraryId: 1,
              sourceType: 'gallery_import',
              imagePath: '/fixture/source.png',
              title: '学习记录',
            );
        for (final text in [
          'Storage\n- Hash tables\n- Arrays',
          'Algorithms\n- Binary tree\n- Sorting',
        ]) {
          await db.insert('mindmap_texts', {
            'document_id': source.id,
            'mindmap_text': text,
            'created_at': now,
          });
        }
        final record = (await ImportRecordRepository(
          database: app,
        ).forDocument(1, source.id))!;
        return (app: app, db: db, record: record);
      }))!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RecordResultsPage(
            record: fixture.record,
            type: 'mindmap_texts',
            title: '思维导图',
            database: fixture.app,
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(RecordMindmapView), findsNWidgets(2));
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Hash');
      await tester.pumpAndSettle();
      expect(find.byType(RecordMindmapView), findsNWidgets(2));
      expect(find.text('Binary tree', findRichText: true), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      final title = tester.widget<RichText>(
        find.text('Hash tables', findRichText: true),
      );
      final marked = <TextSpan>[];
      void collect(InlineSpan span) {
        if (span is! TextSpan) return;
        if (span.style?.backgroundColor == const Color(0xFFFFD86B)) {
          marked.add(span);
        }
        for (final child in span.children ?? <InlineSpan>[]) {
          collect(child);
        }
      }

      collect(title.text);
      expect(marked.map((span) => span.text), ['Hash']);
      await tester.enterText(find.byType(TextField), 'no matching phrase');
      await tester.pumpAndSettle();
      expect(find.byType(RecordMindmapView), findsNWidgets(2));
      expect(find.text('没有匹配的内容'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        expect((await fixture.db.query('mindmap_texts')).length, 2);
        await fixture.db.close();
      });
    },
  );
}
