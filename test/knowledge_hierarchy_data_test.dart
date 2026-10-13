import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/import_record_schema.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/models/document_batch_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const now = '2026-10-13T01:00:00.000Z';
  Future<void> seed(Database target) async {
    for (final id in [1, 2]) {
      await target.insert('users', {
        'id': id,
        'username': 'test$id',
        'password_hash': 'fixture',
        'password_salt': 'fixture',
        'created_at': now,
        'updated_at': now,
      });
      await target.insert('knowledge_libraries', {
        'id': id,
        'user_id': id,
        'name': '测试库$id',
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await seed(db);
  });
  tearDown(() async {
    await db.close();
  });
  Future<int> source({
    String type = 'camera_capture',
    int user = 1,
    String title = '函数资料',
  }) async =>
      (await SourceDocumentRepository(database: app).createSourceDocument(
        userId: user,
        libraryId: user,
        sourceType: type,
        imagePath: '/fixture/$title.png',
        title: title,
      )).id;
  ImportRecordRepository repo() => ImportRecordRepository(database: app);
  Future<void> cards(int id, String title) =>
      AiGenerationRepository(database: app).replaceKnowledgeCards(
        documentId: id,
        cards: [
          {'title': title, 'content': '$title 定义与推导'},
        ],
        append: true,
      );

  test('two single camera operations create two distinct records', () async {
    await source();
    await source();
    final records = await repo().list(1);
    expect(records, hasLength(2));
    expect(records.map((r) => r.pages.length), everyElement(1));
    expect(await repo().countsByLibrary(1), {1: 2});
  });
  for (final type in ['multi_image', 'pdf']) {
    test('one $type batch creates one record with every page', () async {
      final batch = await DocumentBatchRepository(database: app)
          .createDocumentBatch(
            userId: 1,
            libraryId: 1,
            sourceType: type,
            pageSourceType: type == 'pdf' ? 'pdf_page' : 'gallery_import',
            title: '整份资料',
            originalFilePath: type == 'pdf' ? '/fixture/original.pdf' : null,
            pages: List.generate(
              5,
              (i) => DocumentBatchPageDraft(
                savedPath: '/fixture/page$i.png',
                title: '第${i + 1}页',
                pageNumber: i + 1,
              ),
            ),
          );
      final records = await repo().list(1);
      expect(records, hasLength(1));
      expect(records.single.pages, hasLength(5));
      expect(records.single.isPdf, type == 'pdf');
      expect(
        records.single.sources.every(
          (s) => s.batchId == batch.id && s.importRecordId == records.single.id,
        ),
        isTrue,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }
  test(
    'append preserves previous answers and keeps different records isolated',
    () async {
      final a = await source(title: 'A'), b = await source(title: 'B');
      await cards(a, '极限');
      await cards(b, '导数');
      await cards(a, '连续性');
      final recordA = (await repo().forDocument(1, a))!,
          recordB = (await repo().forDocument(1, b))!;
      expect(recordA.counts['knowledge_cards'], 2);
      expect(recordB.counts['knowledge_cards'], 1);
      expect(
        (await repo().results(
          1,
          recordA.id,
          'knowledge_cards',
        )).map((r) => r['title']),
        containsAll(['极限', '连续性']),
      );
      expect(await repo().results(2, recordA.id, 'knowledge_cards'), isEmpty);
      final ai = AiGenerationRepository(database: app);
      await ai.replacePracticeQuestions(
        documentId: a,
        questions: [
          {
            'question_text': '极限定义？',
            'answer_text': '趋近',
            'analysis_text': '注意趋近',
          },
        ],
        append: true,
      );
      final q = (await ai.fetchPracticeQuestions(a)).single;
      await ai.markPracticeQuestionWrong(questionId: q.id, userAnswer: '错误回答');
      await ai.replacePracticeQuestions(
        documentId: a,
        questions: [
          {'question_text': '连续性？', 'answer_text': '连续'},
        ],
        append: true,
      );
      expect((await ai.fetchPracticeQuestions(a)).first.wrongCount, 1);
      expect((await repo().get(1, recordA.id))!.counts['wrong_questions'], 1);
      expect(
        await ai.fetchPracticeQuestionsByUser(userId: 1, recordId: recordB.id),
        isEmpty,
      );
      expect(await db.query('import_records'), hasLength(2));
    },
  );
  test('all outcome types append without replacing existing IDs', () async {
    final id = await source();
    final ai = AiGenerationRepository(database: app);
    for (var i = 0; i < 2; i++) {
      await ai.replaceReviewOutline(
        documentId: id,
        title: '提纲$i',
        outlineText: '# 一级\n## 二级',
        append: true,
      );
      await ai.replaceMindmapText(
        documentId: id,
        mindmapText: '主题\n  分支$i',
        append: true,
      );
    }
    final r = (await repo().forDocument(1, id))!;
    expect(r.counts['review_outlines'], 2);
    expect(r.counts['mindmap_texts'], 2);
    expect(await repo().results(1, r.id, 'review_outlines'), hasLength(2));
  });
  test(
    'search inspects real OCR and knowledge content, source filters and sorting',
    () async {
      final a = await source(title: '无关键词');
      final b = await source(type: 'gallery_import', title: '相册记录');
      await OcrTextRepository(database: app).upsertOcrText(
        documentId: a,
        rawText: '三角函数',
        cleanText: '三角函数',
        finalText: '三角函数',
      );
      await cards(b, '机器学习');
      expect((await repo().list(1, query: '三角函数')).single.anchor.id, a);
      expect((await repo().list(1, query: '机器学习')).single.anchor.id, b);
      expect(await repo().list(1, source: 'camera'), hasLength(1));
      expect(await repo().list(1, source: 'pdf'), isEmpty);
      expect((await repo().list(1, oldestFirst: true)).first.anchor.id, a);
      expect(await repo().list(1, query: '%'), isEmpty);
    },
  );
  test(
    'source text includes all pages in order and uses corrected OCR',
    () async {
      final batch = await DocumentBatchRepository(database: app)
          .createDocumentBatch(
            userId: 1,
            libraryId: 1,
            sourceType: 'multi_image',
            pageSourceType: 'gallery_import',
            title: '两页',
            originalFilePath: null,
            pages: [
              const DocumentBatchPageDraft(
                savedPath: '/fixture/1.png',
                title: '1',
                pageNumber: 1,
              ),
              const DocumentBatchPageDraft(
                savedPath: '/fixture/2.png',
                title: '2',
                pageNumber: 2,
              ),
            ],
          );
      final pages = (await DocumentBatchRepository(
        database: app,
      ).getBatchWithPages(userId: 1, batchId: batch.id))!.pages;
      for (var i = 0; i < pages.length; i++) {
        await OcrTextRepository(database: app).upsertOcrText(
          documentId: pages[i].id,
          rawText: 'raw',
          cleanText: 'clean',
          finalText: '校对${i + 1}',
        );
      }
      final r = (await repo().list(1)).single;
      final text = await repo().sourceText(r);
      expect(text, contains('校对1'));
      expect(text, contains('校对2'));
      expect(text.indexOf('校对1'), lessThan(text.indexOf('校对2')));
    },
  );
  test(
    'source snapshots retain old text after correction and cropping preserves original file',
    () async {
      final id = await source();
      final ocr = OcrTextRepository(database: app);
      await ocr.upsertOcrText(
        documentId: id,
        rawText: '原文',
        cleanText: '原文',
        finalText: '第一版',
      );
      final first = await repo().sourceSnapshot(1, id);
      await ocr.upsertOcrText(
        documentId: id,
        rawText: '原文',
        cleanText: '原文',
        finalText: '校对新版',
      );
      final next = await repo().sourceSnapshot(1, id);
      expect(first.id, isNot(next.id));
      expect(first.text, contains('第一版'));
      expect(next.text, contains('校对新版'));
      final saved = await db.query(
        'record_source_versions',
        where: 'id=?',
        whereArgs: [first.id],
      );
      expect(saved.single['content'], contains('第一版'));
      final original = (await SourceDocumentRepository(
        database: app,
      ).getSourceDocumentById(userId: 1, documentId: id))!.imagePath;
      await SourceDocumentRepository(database: app).updateDocumentImagePath(
        userId: 1,
        documentId: id,
        imagePath: '/cropped.png',
      );
      final changed = (await SourceDocumentRepository(
        database: app,
      ).getSourceDocumentById(userId: 1, documentId: id))!;
      expect(changed.originalFilePath, original);
      expect(changed.imagePath, '/cropped.png');
    },
  );

  test(
    'rename tags move and library removal preserve identities and history',
    () async {
      final id = await source();
      await cards(id, '保留卡片');
      final r = (await repo().forDocument(1, id))!;
      final lib = await KnowledgeLibraryRepository(database: app).createLibrary(
        userId: 1,
        name: '新库',
        coverTheme: 'network',
        coverColor: 0xFF62BBA0,
      );
      await repo().rename(1, r.id, '新标题');
      await repo().setTags(1, r.id, [' 标签 ', '标签', '']);
      await repo().move(1, r.id, lib.id);
      final moved = (await repo().get(1, r.id))!;
      expect(moved.title, '新标题');
      expect(moved.tags, ['标签']);
      expect(moved.libraryId, lib.id);
      expect(moved.anchor.id, id);
      await KnowledgeLibraryRepository(
        database: app,
      ).deleteLibraryKeepingRecords(userId: 1, libraryId: lib.id);
      expect((await repo().get(1, r.id))!.counts['knowledge_cards'], 1);
      expect((await repo().get(1, r.id))!.libraryId, isNot(lib.id));
      await expectLater(repo().move(1, r.id, 2), throwsStateError);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'record deletion cascades only its own content and removes only its favorites',
    () async {
      final a = await source(title: 'A'), b = await source(title: 'B');
      await cards(a, 'A');
      await cards(b, 'B');
      final ai = AiGenerationRepository(database: app);
      final ca = (await ai.fetchKnowledgeCards(a)).single,
          cb = (await ai.fetchKnowledgeCards(b)).single;
      for (final c in [ca, cb]) {
        await db.insert('favorites', {
          'user_id': 1,
          'target_type': 'knowledge_card',
          'target_id': c.id,
          'created_at': now,
          'updated_at': now,
        });
      }
      final r = (await repo().forDocument(1, a))!;
      await repo().delete(2, r.id);
      expect(await repo().list(1), hasLength(2));
      await repo().delete(1, r.id);
      expect(await repo().list(1), hasLength(1));
      expect(await ai.fetchKnowledgeCards(b), hasLength(1));
      expect((await db.query('favorites')).single['target_id'], cb.id);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'failure and partial completion reflect actual task and OCR state',
    () async {
      final id = await source();
      final ai = AiGenerationRepository(database: app);
      final r = (await repo().forDocument(1, id))!;
      expect(r.counts, isEmpty);
      expect(r.statusLabel, '待 OCR 识别');
      final task = await ai.markTaskRunning(
        documentId: id,
        taskType: 'knowledge_cards',
        inputText: '原文',
      );
      expect((await repo().get(1, r.id))!.statusLabel, 'AI 生成中');
      await ai.markTaskFailed(taskId: task.id, errorMessage: '测试接口失败');
      expect((await repo().get(1, r.id))!.statusLabel, '处理失败');
      expect((await repo().get(1, r.id))!.errors, ['测试接口失败']);
      await cards(id, '真实卡片');
      expect((await repo().get(1, r.id))!.statusLabel, '部分完成');
    },
  );
  test(
    'v14 upgrade preserves old document IDs OCR outcomes answers and is idempotent after reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('knowledge-migration-');
      final path = '${dir.path}/v14.db';
      final old = await databaseFactoryFfi.openDatabase(path);
      for (final sql in File(
        'test/fixtures/knowledge_schema_v14.sql',
      ).readAsStringSync().split(';').where((s) => s.trim().isNotEmpty)) {
        await old.execute(sql);
      }
      await seed(old);
      await old.insert('source_documents', {
        'id': 41,
        'user_id': 1,
        'library_id': 1,
        'source_type': 'camera_capture',
        'image_path': 'old.png',
        'original_title': '旧资料',
        'ocr_status': 'success',
        'created_at': now,
      });
      await old.insert('knowledge_cards', {
        'id': 51,
        'document_id': 41,
        'title': '旧卡片',
        'content': '仍在',
        'created_at': now,
      });
      await old.insert('practice_questions', {
        'id': 61,
        'document_id': 41,
        'question_text': '旧题',
        'wrong_count': 2,
        'last_user_answer': '旧答案',
        'created_at': now,
      });
      await old.setVersion(14);
      await old.close();
      var upgraded = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      var current = await upgraded.database;
      final records = ImportRecordRepository(database: upgraded);
      final r = (await records.list(1)).single;
      expect(r.anchor.id, 41);
      expect(r.counts['knowledge_cards'], 1);
      expect(
        (await current.query('practice_questions')).single['last_user_answer'],
        '旧答案',
      );
      await createImportRecordSchema(current);
      expect(await current.query('import_records'), hasLength(1));
      expect(await current.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await records.rename(1, r.id, '重启保留');
      await records.setTags(1, r.id, ['持久化']);
      await current.close();
      upgraded = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      current = await upgraded.database;
      final reopened = (await ImportRecordRepository(
        database: upgraded,
      ).get(1, r.id))!;
      expect(reopened.title, '重启保留');
      expect(reopened.tags, ['持久化']);
      expect(reopened.anchor.id, 41);
      await current.close();
      await dir.delete(recursive: true);
    },
  );
}
