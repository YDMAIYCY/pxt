import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/import_record_schema.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/learning_repository.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/practice_session_repository.dart';
import 'package:pxt1/generator/learning_resource_service.dart';
import 'package:pxt1/generator/library_practice_service.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const time = '2026-10-13T00:00:00.000Z';
  Future<void> seed(Database target) async {
    for (final id in [1, 2]) {
      await target.insert('users', {
        'id': id,
        'username': 'learner$id',
        'password_hash': 'test',
        'password_salt': 'test',
        'created_at': time,
        'updated_at': time,
      });
    }
    for (final id in [1, 2, 3]) {
      await target.insert('knowledge_libraries', {
        'id': id,
        'user_id': id == 3 ? 2 : 1,
        'name': 'book$id',
        'created_at': time,
        'updated_at': time,
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
  Future<int> source({int library = 1, String title = '事务'}) async =>
      (await SourceDocumentRepository(database: app).createSourceDocument(
        userId: 1,
        libraryId: library,
        sourceType: 'gallery_import',
        imagePath: 'fixture.png',
        title: title,
      )).id;
  Future<void> text(int id, String value) async =>
      OcrTextRepository(database: app).upsertOcrText(
        documentId: id,
        rawText: value,
        cleanText: value,
        finalText: value,
      );
  Future<List<int>> questions(int documentId) async {
    await AiGenerationRepository(database: app).appendPracticeQuestions(
      documentId: documentId,
      questions: [
        {
          'question_text': '事务定义？',
          'answer_text': '原子性操作',
          'analysis_text': '事务应整体成功或失败',
        },
        {
          'question_text': '举一个事务应用？',
          'answer_text': '转账',
          'analysis_text': '两边账户需一起更新',
        },
      ],
    );
    return (await db.query(
      'practice_questions',
      columns: ['id'],
      where: 'document_id = ?',
      whereArgs: [documentId],
    )).map((q) => q['id'] as int).toList();
  }
  test('removing a shared primary library keeps record identity, resources and practice', () async {
    final id=await source();
    await text(id,'事务保证原子性');
    final repo=ImportRecordRepository(database:app);
    final record=(await repo.forDocument(1,id))!;
    await repo.setLibraries(1,record.id,[1,2]);
    await questions(id);
    await LearningRepository(database:app).saveResource(userId:1,documentId:id,
      type:'notes',title:'笔记',content:'保留内容',inputText:'事务',model:'test');
    await KnowledgeLibraryRepository(database:app).deleteLibraryAndContents(userId:1,libraryId:1);
    final retained=(await repo.get(1,record.id))!;
    expect(retained.libraryId,2);
    expect(retained.sources.single.id,id);
    expect(retained.resourceCount,1);
    expect(await PracticeSessionRepository(database:app)
      .questions(const PracticeScope(userId:1,libraryId:2)),hasLength(2));
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
  });

  test(
    'explicit import operation replay returns the existing record without duplication',
    () async {
      final repo = SourceDocumentRepository(database: app);
      final first = await repo.createSourceDocument(
        userId: 1,
        libraryId: 1,
        sourceType: 'gallery_import',
        imagePath: 'first.png',
        title: '第一次',
        operationId: 'same-import-operation',
      );
      final replay = await repo.createSourceDocument(
        userId: 1,
        libraryId: 1,
        sourceType: 'gallery_import',
        imagePath: 'second.png',
        title: '重复请求',
        operationId: 'same-import-operation',
      );
      expect(replay.id, first.id);
      expect(await db.query('source_documents'), hasLength(1));
      expect(await db.query('import_records'), hasLength(1));
    },
  );
  test(
    'library generation rejects outside citations before saving any questions',
    () async {
      final doc = await source();
      await text(doc, '事务的原子性');
      final outside = await source(library: 2);
      await text(outside, '网络协议');
      final client = _PracticeClient(
        List.generate(
          5,
          (i) => {
            'question_text': '题目$i',
            'answer_text': '答案$i',
            'analysis_text': '依据$i',
            'question_kind': 'short_answer',
            'source_document_id': i == 4 ? outside : doc,
          },
        ),
      );
      final service = LibraryPracticeService(database: app, client: client);
      await expectLater(
        service.generate(
          const PracticeScope(userId: 1, libraryId: 1),
          LlmProviderConfig.emptyForUser(1),
        ),
        throwsFormatException,
      );
      expect(client.prompt, contains('原子性'));
      expect(client.prompt, isNot(contains('网络协议')));
      expect(await db.query('practice_questions'), isEmpty);
    },
  );
  test(
    'generated scope persists valid immutable citations and handles filtered IDs before limit',
    () async {
      final doc = await source();
      await text(doc, '事务的原子性');
      final client = _PracticeClient(
        List.generate(
          5,
          (i) => {
            'question_text': '专项题$i',
            'answer_text': '整体成功或失败',
            'analysis_text': '根据事务定义',
            'question_kind': 'short_answer',
            'source_document_id': doc,
          },
        ),
      );
      final ids = await LibraryPracticeService(database: app, client: client)
          .generate(
            const PracticeScope(userId: 1, libraryId: 1),
            LlmProviderConfig.emptyForUser(1),
          );
      expect(ids, hasLength(5));
      final filtered = await PracticeSessionRepository(database: app).questions(
        const PracticeScope(userId: 1, libraryId: 1),
        questionIds: [ids.last],
        limit: 1,
      );
      expect(filtered.single.question.id, ids.last);
      expect(filtered.single.question.sourceVersionId, isNotNull);
    },
  );
  test(
    'regrading delayed evidence revokes mastery across the whole variant group',
    () async {
      final doc = await source();
      await text(doc, '事务');
      final ids = await questions(doc);
      await db.update(
        'practice_questions',
        {'parent_question_id': ids.first},
        where: 'id = ?',
        whereArgs: [ids.last],
      );
      final repo = PracticeSessionRepository(database: app);
      const scope = PracticeScope(userId: 1, libraryId: 1);
      final start = DateTime.utc(2026, 10, 10);
      await repo.submit(
        scope: scope,
        questionId: ids.first,
        requestId: 'a',
        answer: '原子性操作',
        correct: true,
        now: start,
      );
      await repo.submit(
        scope: scope,
        questionId: ids.last,
        requestId: 'b',
        answer: '转账',
        correct: true,
        now: start.add(const Duration(minutes: 2)),
      );
      final delayed = await repo.submit(
        scope: scope,
        questionId: ids.first,
        requestId: 'c',
        answer: '原子性操作',
        correct: true,
        now: start.add(const Duration(days: 2)),
      );
      expect(
        (await db.query(
          'practice_questions',
        )).every((q) => q['review_status'] == 'mastered'),
        isTrue,
      );
      await repo.regrade(
        1,
        delayed.id,
        expectedRevision: 0,
        correct: false,
        reason: '遗漏关键点',
      );
      expect(
        (await db.query(
          'practice_questions',
        )).every((q) => q['review_status'] != 'mastered'),
        isTrue,
      );
      expect(await db.query('practice_submissions'), hasLength(3));
    },
  );

  test(
    'one single, five images and a 20 page PDF have three stable parents',
    () async {
      final single = await source();
      final batches = DocumentBatchRepository(database: app);
      for (final count in [5, 20]) {
        await batches.createDocumentBatch(
          userId: 1,
          libraryId: 1,
          sourceType: count == 20 ? 'pdf' : 'multi_image',
          pageSourceType: count == 20 ? 'pdf_page' : 'gallery_import',
          title: 'batch$count',
          originalFilePath: count == 20 ? 'fixture.pdf' : null,
          pages: List.generate(
            count,
            (i) => DocumentBatchPageDraft(
              savedPath: '$i.png',
              title: 'page$i',
              pageNumber: i + 1,
            ),
          ),
        );
      }
      final records = await ImportRecordRepository(database: app).list(1);
      expect(records, hasLength(3));
      expect(records.map((r) => r.pages.length).toSet(), {1, 5, 20});
      final id = (await ImportRecordRepository(
        database: app,
      ).forDocument(1, single))!.id;
      await createImportRecordSchema(db);
      await createImportRecordSchema(db);
      expect(
        (await ImportRecordRepository(
          database: app,
        ).forDocument(1, single))!.id,
        id,
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'separate intentional imports stay separate and membership move keeps history',
    () async {
      final a = await source();
      final b = await source();
      expect((await ImportRecordRepository(database: app).list(1)).length, 2);
      final ids = await questions(a);
      final scope = const PracticeScope(userId: 1, libraryId: 1);
      await PracticeSessionRepository(database: app).submit(
        scope: scope,
        questionId: ids[0],
        requestId: 'attempt',
        answer: 'wrong',
        correct: false,
      );
      await SourceDocumentRepository(
        database: app,
      ).moveDocumentToLibrary(userId: 1, documentId: a, libraryId: 2);
      expect(
        (await ImportRecordRepository(
          database: app,
        ).forDocument(1, a))!.libraryId,
        2,
      );
      expect(
        (await ImportRecordRepository(
          database: app,
        ).forDocument(1, b))!.libraryId,
        1,
      );
      expect(await db.query('practice_submissions'), hasLength(1));
      await expectLater(
        ImportRecordRepository(database: app).setLibraries(
          1,
          (await ImportRecordRepository(database: app).forDocument(1, a))!.id,
          [3],
        ),
        throwsStateError,
      );
    },
  );
  test(
    'all pages feed record context and retain old source versions on edits',
    () async {
      final batch = await DocumentBatchRepository(database: app)
          .createDocumentBatch(
            userId: 1,
            libraryId: 1,
            sourceType: 'multi_image',
            pageSourceType: 'gallery_import',
            title: '两页记录',
            originalFilePath: null,
            pages: [
              const DocumentBatchPageDraft(
                savedPath: 'a.png',
                title: '第一页',
                pageNumber: 1,
              ),
              const DocumentBatchPageDraft(
                savedPath: 'b.png',
                title: '第二页',
                pageNumber: 2,
              ),
            ],
          );
      final pages = (await DocumentBatchRepository(
        database: app,
      ).getBatchWithPages(userId: 1, batchId: batch.id))!.pages;
      await text(pages[0].id, '第一部分介绍事务原子性');
      await text(pages[1].id, '第二部分介绍隔离性');
      final content = await LearningResourceService(
        database: app,
      ).sourceText(pages.first);
      expect(content, contains('原子性'));
      expect(content, contains('隔离性'));
      final resource = await LearningRepository(database: app).saveResource(
        userId: 1,
        documentId: pages.first.id,
        type: 'notes',
        title: '旧笔记',
        content: 'old notes',
        inputText: content,
        model: 'test',
      );
      await text(pages[1].id, '第二页修正后的内容');
      final next = await ImportRecordRepository(
        database: app,
      ).sourceSnapshot(1, pages.first.id);
      expect(resource.sourceVersionId, isNot(next.id));
      final prior = await db.query(
        'record_source_versions',
        where: 'id = ?',
        whereArgs: [resource.sourceVersionId],
      );
      expect(prior.single['content'], contains('隔离性'));
      expect(
        (await LearningRepository(
          database: app,
        ).resources(1, pages.last.id)).single.id,
        resource.id,
      );
    },
  );
  test(
    'scope filters apply before limits and reject out of scope submissions',
    () async {
      final first = await source();
      final second = await source(library: 2);
      await text(first, '事务');
      await text(second, '网络');
      final a = await questions(first);
      final b = await questions(second);
      final repo = PracticeSessionRepository(database: app);
      final found = await repo.questions(
        const PracticeScope(userId: 1, libraryId: 2),
        limit: 1,
      );
      expect(found.single.question.id, b.first);
      await expectLater(
        repo.submit(
          scope: const PracticeScope(userId: 1, libraryId: 2),
          questionId: a.first,
          requestId: 'bad',
          answer: 'x',
          correct: true,
        ),
        throwsStateError,
      );
      await expectLater(
        repo.submit(
          scope: const PracticeScope(userId: 2, libraryId: 3),
          questionId: a.first,
          requestId: 'bad',
          answer: 'x',
          correct: true,
        ),
        throwsStateError,
      );
      expect(await db.query('practice_submissions'), isEmpty);
    },
  );
  test(
    'concurrent replay counts once; correction preserves attempt and source snapshot',
    () async {
      final doc = await source();
      await text(doc, '原始资料');
      final ids = await questions(doc);
      final repo = PracticeSessionRepository(database: app);
      const scope = PracticeScope(userId: 1, libraryId: 1);
      final results = await Future.wait(
        List.generate(
          3,
          (_) => repo.submit(
            scope: scope,
            questionId: ids.first,
            requestId: 'same',
            answer: '我的答案',
            correct: false,
          ),
        ),
      );
      expect(results.map((r) => r.id).toSet(), hasLength(1));
      expect(await db.query('learning_attempts'), hasLength(1));
      await text(doc, '后续修改资料');
      final corrected = await repo.regrade(
        1,
        results.first.id,
        expectedRevision: 0,
        correct: true,
        reason: '参考答案有误，已依据资料核对',
      );
      expect(corrected.id, results.first.id);
      expect(corrected.revision, 1);
      expect(await db.query('practice_submissions'), hasLength(1));
      expect(await db.query('practice_revisions'), hasLength(1));
      expect(await db.query('learning_attempts'), hasLength(1));
      final attempt = (await db.query('practice_submissions')).single;
      final old = (await db.query(
        'record_source_versions',
        where: 'id = ?',
        whereArgs: [attempt['source_version_id']],
      )).single;
      expect(old['content'], contains('原始资料'));
      await expectLater(
        repo.regrade(
          1,
          results.first.id,
          expectedRevision: 0,
          correct: false,
          reason: '过期修改',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'instant repeated same answer cannot master; variants plus delayed success can',
    () async {
      final doc = await source();
      await text(doc, '事务');
      final ids = await questions(doc);
      await db.update(
        'practice_questions',
        {'parent_question_id': ids.first},
        where: 'id = ?',
        whereArgs: [ids.last],
      );
      final repo = PracticeSessionRepository(database: app);
      const scope = PracticeScope(userId: 1, libraryId: 1);
      final start = DateTime.utc(2026, 10, 13);
      for (var i = 0; i < 4; i++) {
        await repo.submit(
          scope: scope,
          questionId: ids.first,
          requestId: 'same$i',
          answer: '原子性操作',
          correct: true,
          now: start.add(Duration(minutes: i)),
        );
      }
      expect((await repo.evidence(1, ids.first)).mastered, isFalse);
      await repo.submit(
        scope: scope,
        questionId: ids.last,
        requestId: 'variant',
        answer: '转账',
        correct: true,
        now: start.add(const Duration(minutes: 5)),
      );
      expect((await repo.evidence(1, ids.first)).mastered, isFalse);
      await repo.submit(
        scope: scope,
        questionId: ids.last,
        requestId: 'delayed',
        answer: '转账',
        correct: true,
        now: start.add(const Duration(days: 2)),
      );
      expect((await repo.evidence(1, ids.first)).mastered, isTrue);
    },
  );
  test('FSRS preserves full scheduling state and review history', () async {
    final doc = await source();
    await text(doc, '事务');
    final learning = LearningRepository(database: app);
    final r = await learning.saveResource(
      userId: 1,
      documentId: doc,
      type: 'flashcards',
      title: '闪卡',
      content: jsonEncode({
        'cards': [
          {'front': '定义', 'back': '事务'},
        ],
      }),
      inputText: '事务',
      model: 'test',
    );
    await learning.reviewCard(1, r.id, 0, 3);
    await learning.reviewCard(1, r.id, 0, 1);
    final state = (await db.query('flashcard_reviews')).single;
    expect(
      jsonDecode(state['fsrs_state_json'] as String),
      contains('stability'),
    );
    expect(await db.query('flashcard_review_history'), hasLength(2));
    expect(
      DateTime.parse(
        state['next_review_at'] as String,
      ).isAfter(DateTime.now().toUtc()),
      isTrue,
    );
  });
  test(
    'real version 15 schema upgrades atomically preserving IDs and old resources',
    () async {
      final folder = await Directory.systemTemp.createTemp('pxt-migration-');
      final path = '${folder.path}/legacy.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 15,
          onCreate: (old, _) async {
            final sql = await File(
              'test/fixtures/phase03_schema_v15.sql',
            ).readAsString();
            for (final statement in sql.split(';')) {
              if (statement.trim().isNotEmpty) await old.execute(statement);
            }
            await seed(old);
            await old.insert('source_documents', {
              'id': 42,
              'user_id': 1,
              'library_id': 1,
              'source_type': 'gallery_import',
              'image_path': 'old.png',
              'original_title': '旧资料',
              'created_at': time,
            });
            await old.insert('learning_resources', {
              'id': 77,
              'document_id': 42,
              'type': 'notes',
              'title': '旧笔记',
              'content': '保留历史',
              'input_fingerprint': 'old',
              'model': 'old',
              'version': 1,
              'created_at': time,
            });
          },
        ),
      );
      await old.close();
      final upgraded = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final migrated = await upgraded.database;
      expect(await migrated.getVersion(), 16);
      expect((await migrated.query('source_documents')).single['id'], 42);
      expect((await migrated.query('learning_resources')).single['id'], 77);
      expect(await migrated.query('import_records'), hasLength(1));
      expect(await migrated.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await migrated.close();
      await folder.delete(recursive: true);
    },
  );
}

class _PracticeClient extends MiniMaxClient {
  _PracticeClient(this.questions);
  final List<Map<String, Object>> questions;
  String prompt = '';
  @override
  Future<Map<String, dynamic>> generateStructuredJson({
    required String systemPrompt,
    required String userPrompt,
    Map<String, dynamic>? jsonSchema,
    List<({String base64, String mimeType})>? images,
  }) async {
    prompt = userPrompt;
    return {'questions': questions};
  }
}
