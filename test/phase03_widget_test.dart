import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/learning_repository.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/ui/pages/book_library_page.dart';
import 'package:pxt1/ui/pages/rich_note_editor_page.dart';
import 'package:pxt1/ui/widgets/record_mindmap_view.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

Future<void> waitFor(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(target, findsWidgets);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const time = '2026-10-13T00:00:00.000Z';
  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'fixture',
      'password_hash': 'test',
      'password_salt': 'test',
      'created_at': time,
      'updated_at': time,
    });
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'fixture',
      'created_at': time,
    });
    await db.insert('knowledge_libraries', {
      'id': 1,
      'user_id': 1,
      'name': '数据库基础',
      'description': '从资料到知识，再用练习验证理解。',
      'created_at': time,
      'updated_at': time,
    });
    final batch = await DocumentBatchRepository(database: app)
        .createDocumentBatch(
          userId: 1,
          libraryId: 1,
          sourceType: 'multi_image',
          pageSourceType: 'gallery_import',
          title: '事务与隔离性',
          originalFilePath: null,
          pages: [
            const DocumentBatchPageDraft(
              savedPath: 'none-a.png',
              title: '事务定义',
              pageNumber: 1,
            ),
            const DocumentBatchPageDraft(
              savedPath: 'none-b.png',
              title: '隔离级别',
              pageNumber: 2,
            ),
          ],
        );
    final record = (await ImportRecordRepository(database: app).list(1)).single;
    expect(record.anchor.batchId, batch.id);
    for (final page in record.pages) {
      await OcrTextRepository(database: app).upsertOcrText(
        documentId: page.id,
        rawText: '事务将多步操作作为整体处理。',
        cleanText: '事务将多步操作作为整体处理。',
      );
    }
    await LearningRepository(database: app).saveResource(
      userId: 1,
      documentId: record.anchor.id,
      type: 'record_summary',
      title: '事务与隔离性',
      content: '{"content":"事务保证多步操作整体成功或失败；隔离性处理并发事务。"}',
      inputText: 'fixture',
      model: 'test',
    );
  });
  tearDown(() async {
    await db.close();
  });
  testWidgets(
    'book opens one batch record, all sources and scoped practice at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final fontFile = File('C:/Windows/Fonts/msyh.ttc');
      if ((await tester.runAsync(fontFile.exists))!) {
        await tester.runAsync(() async {
          final loader = FontLoader('Phase03CJK')
            ..addFont(
              Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
            );
          await loader.load();
        });
      }
      final theme = AppTheme.light.copyWith(
        textTheme: AppTheme.light.textTheme.apply(fontFamily: 'Phase03CJK'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: key,
            child: BookDetailPage(
              database: app,
              library: KnowledgeLibraryRecord(
                id: 1,
                userId: 1,
                name: '数据库基础',
                description: '从资料到知识，再用练习验证理解。',
                createdAt: DateTime.parse(time),
                updatedAt: DateTime.parse(time),
                documentCount: 2,
              ),
            ),
          ),
        ),
      );
      await waitFor(tester, find.textContaining('2 页 / 图片'));
      expect(find.text('事务与隔离性'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      if (Platform.isWindows) {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          await File(
            '${Directory.systemTemp.path}/pxt-phase03-book-render.png',
          ).writeAsBytes(png.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text('事务与隔离性'));
      await waitFor(tester, find.text('来源'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('知识'), findsOneWidget);
      expect(find.text('练习'), findsOneWidget);
      await tester.tap(find.text('来源'));
      await tester.pump(const Duration(milliseconds: 500));
      await waitFor(tester, find.text('事务定义'));
      expect(find.text('隔离级别'), findsOneWidget);
      await tester.tap(find.text('练习'));
      await tester.pump(const Duration(milliseconds: 500));
      await waitFor(tester, find.text('围绕自己的知识练习'));
      expect(find.textContaining('当前范围：0 道题'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'mindmap collapses branches and search locates the selected node',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordMindmapView(
                text: '数据库基础\n  事务\n    原子性\n    隔离性\n  索引',
                onSource: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原子性'), findsOneWidget);
      await tester.tap(find.byTooltip('收起分支').last);
      await tester.pumpAndSettle();
      expect(find.text('原子性'), findsNothing);
      await tester.enterText(find.byType(TextField), '原子性');
      await tester.pumpAndSettle();
      await tester.tap(find.text('原子性').first);
      await tester.pumpAndSettle();
      expect(find.text('原子性'), findsNWidgets(2));
      expect(opened, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Chinese IME updates the rich editor and Delta restores its text',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [FlutterQuillLocalizations.delegate],
          home: RichNoteEditorPage(content: '{"content":"事务是一个整体"}'),
        ),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      final raw = tester.state<QuillRawEditorState>(
        find.byType(QuillRawEditor),
      );
      final current = raw.currentTextEditingValue!;
      const prefix = '原子性：全部成功或全部失败。';
      raw.updateEditingValue(
        TextEditingValue(
          text: '$prefix${current.text}',
          selection: const TextSelection.collapsed(offset: prefix.length),
        ),
      );
      await tester.pumpAndSettle();
      expect(editor.controller.document.toPlainText(), contains(prefix));
      expect(
        Document.fromJson(
          editor.controller.document.toDelta().toJson(),
        ).toPlainText(),
        editor.controller.document.toPlainText(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
