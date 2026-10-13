import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/knowledge_graph_repository.dart';
import 'package:pxt1/database/knowledge_context_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/learning_repository.dart';
import 'package:pxt1/database/learning_schema.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/generator/learning_resource_service.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late LearningRepository learning;
  late KnowledgeGraphRepository graph;
  late SourceDocumentRecord document;
  late int library;
  const now = '2026-10-13T00:00:00.000Z';

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'learner',
      'password_hash': 'test',
      'password_salt': 'salt',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('users', {
      'id': 2,
      'username': 'other',
      'password_hash': 'test',
      'password_salt': 'salt',
      'created_at': now,
      'updated_at': now,
    });
    library = (await KnowledgeLibraryRepository(
      database: app,
    ).ensureDefaultLibrary(1)).id;
    document = await SourceDocumentRepository(database: app)
        .createSourceDocument(
          userId: 1,
          libraryId: library,
          sourceType: 'gallery_import',
          imagePath: 'fixture.png',
          title: 'Attention',
        );
    learning = LearningRepository(database: app);
    graph = KnowledgeGraphRepository(database: app);
  });
  tearDown(() => db.close());

  const draft = KnowledgeGraphDraft(
    concepts: [
      KnowledgeConceptDraft(
        name: 'Attention',
        summary: '加权聚合',
        evidenceText: '图示',
        masteryScore: 95,
        weaknessScore: 5,
      ),
    ],
    links: [],
  );

  test(
    'fresh database creates the full schema without foreign key errors',
    () async {
      expect(await db.getVersion(), 15);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(await learning.libraryIds(1, document.id), [library]);
    },
  );

  test(
    'schema migration backfills old memberships and results idempotently',
    () async {
      await db.delete('document_library_links');
      await db.insert('ai_generation_tasks', {
        'document_id': document.id,
        'task_type': 'knowledge_cards',
        'input_text': 'old',
        'status': 'completed',
        'provider': 'old-model',
        'result_text': '{"cards":[]}',
        'created_at': now,
        'updated_at': now,
      });
      await createLearningSchema(db);
      await createLearningSchema(db);
      expect(await learning.libraryIds(1, document.id), [library]);
      expect(await learning.resources(1, document.id), hasLength(1));
    },
  );

  test('resource versions persist and reject another user', () async {
    for (final text in ['first', 'corrected']) {
      await learning.saveResource(
        userId: 1,
        documentId: document.id,
        type: 'notes',
        title: '笔记',
        content: text,
        inputText: 'source',
        model: 'user',
      );
    }
    final resources = await learning.resources(1, document.id);
    expect(resources.map((r) => r.version), [2, 1]);
    expect(resources.first.content, 'corrected');
    expect(
      (await SourceDocumentRepository(
        database: app,
      ).getSourceDocumentById(userId: 1, documentId: document.id))!.aiDone,
      isTrue,
    );
    await expectLater(learning.resources(2, document.id), throwsStateError);
    await expectLater(
      learning.saveResource(
        userId: 2,
        documentId: document.id,
        type: 'notes',
        title: 'x',
        content: 'x',
        inputText: 'x',
        model: 'user',
      ),
      throwsStateError,
    );
  });

  test(
    'opening a genuine version 14 database migrates data to version 15',
    () async {
      await db.insert('ai_generation_tasks', {
        'document_id': document.id,
        'task_type': 'notes',
        'input_text': 'old',
        'status': 'completed',
        'provider': 'old-model',
        'result_text': '{"content":"old note"}',
        'created_at': now,
        'updated_at': now,
      });
      final temp = await Directory.systemTemp.createTemp(
        'pxt_section2_migration_',
      );
      final path = '${temp.path}/legacy.db';
      await db.execute('VACUUM INTO ?', [path]);
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute('PRAGMA foreign_keys = OFF');
      for (final name in [
        'link_document_library_insert',
        'link_document_library_update',
        'preserve_shared_concept_source',
        'preserve_shared_concept_library',
      ]) {
        await legacy.execute('DROP TRIGGER IF EXISTS $name');
      }
      for (final name in [
        'flashcard_reviews',
        'learning_attempts',
        'learning_errors',
        'learning_resources',
        'question_concepts',
        'image_understandings',
        'concept_documents',
        'document_library_links',
      ]) {
        await legacy.execute('DROP TABLE $name');
      }
      await legacy.setVersion(14);
      await legacy.close();
      final migrated = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final migratedDb = await migrated.database;
      expect(await migratedDb.getVersion(), 15);
      expect(
        await LearningRepository(database: migrated).libraryIds(1, document.id),
        [library],
      );
      expect(
        (await LearningRepository(
          database: migrated,
        ).resources(1, document.id)).single.content,
        '{"content":"old note"}',
      );
      expect(await migratedDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await migratedDb.close();
      await temp.delete(recursive: true);
    },
  );

  test(
    'one concept is shared across sources and regeneration preserves learning',
    () async {
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        libraryId: library,
        draft: draft,
      );
      final id = (await learning.concepts(1, document.id)).single.id;
      await learning.recordAttempt(
        userId: 1,
        documentId: document.id,
        conceptId: id,
        origin: 'interview',
        prompt: '什么是 Attention',
        answer: '不确定',
        score: 40,
        feedback: '遗漏权重',
        hasError: true,
      );
      final other = await SourceDocumentRepository(database: app)
          .createSourceDocument(
            userId: 1,
            sourceType: 'gallery_import',
            imagePath: 'other.png',
            title: 'Attention 数学',
          );
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: other.id,
        draft: draft,
      );
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        draft: draft,
      );
      final shared = (await learning.concepts(1, other.id)).single;
      expect(shared.id, id);
      expect(shared.masteryScore, 40);
      expect(await learning.errors(1, conceptId: id), hasLength(1));
      await db.delete(
        'source_documents',
        where: 'id = ?',
        whereArgs: [document.id],
      );
      expect((await learning.concepts(1, other.id)).single.id, id);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'classification applies only existing libraries owned by this user',
    () async {
      final otherLibrary = await KnowledgeLibraryRepository(
        database: app,
      ).createLibrary(userId: 2, name: 'private');
      await expectLater(
        learning.setLibraries(1, document.id, [otherLibrary.id]),
        throwsStateError,
      );
      expect(await learning.libraryIds(1, document.id), [library]);
    },
  );

  test(
    'cross-library search and deleting one library preserve a shared package',
    () async {
      final second = await KnowledgeLibraryRepository(
        database: app,
      ).createLibrary(userId: 1, name: '数学');
      await learning.setLibraries(1, document.id, [library, second.id]);
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        libraryId: library,
        draft: draft,
      );
      expect(
        await SourceDocumentRepository(
          database: app,
        ).fetchAllSourceDocuments(userId: 1, libraryId: second.id),
        hasLength(1),
      );
      expect(
        await graph.fetchWeakConcepts(userId: 1, libraryId: second.id),
        hasLength(1),
      );
      await learning.saveResource(
        userId: 1,
        documentId: document.id,
        type: 'notes',
        title: 'Attention 笔记',
        content: 'Attention 加权聚合',
        inputText: 'source',
        model: 'user',
      );
      expect(
        await KnowledgeContextRepository(
          database: app,
        ).search(userId: 1, query: 'Attention', libraryId: second.id),
        isNotEmpty,
      );
      await KnowledgeLibraryRepository(
        database: app,
      ).deleteLibraryAndContents(userId: 1, libraryId: library);
      expect(await learning.libraryIds(1, document.id), [second.id]);
      expect(await learning.concepts(1, document.id), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'interview follow-up errors become the same targeted retry and close after practice',
    () async {
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        draft: draft,
      );
      final concept = (await learning.concepts(1, document.id)).single;
      final ai = AiGenerationRepository(database: app);
      await ai.appendPracticeQuestions(
        documentId: document.id,
        questions: [
          {'question_text': 'Attention 定义', 'answer_text': '加权聚合'},
        ],
      );
      final base = (await ai.fetchPracticeQuestions(document.id)).single;
      await learning.recordQuestionAttempt(
        1,
        base.id,
        false,
        '不知道',
        conceptId: concept.id,
        origin: 'interview',
        prompt: 'Attention 权重怎样归一化？',
        score: 30,
        feedback: jsonEncode({
          'standard_answer': '使用 Softmax',
          'correction': '遗漏归一化',
        }),
      );
      final error = (await learning.errors(1)).single;
      final retry = await learning.prepareErrorRetry(1, error.id);
      expect(await learning.prepareErrorRetry(1, error.id), retry);
      final question = await ai.fetchPracticeQuestionByUserAndId(
        userId: 1,
        questionId: retry,
      );
      expect(question!.question.questionText, 'Attention 权重怎样归一化？');
      expect(question.question.answerText, '使用 Softmax');
      expect(
        await learning.questionsForConcept(1, concept.id),
        contains(retry),
      );
      await ai.markPracticeQuestionCorrect(
        questionId: retry,
        userAnswer: '使用 Softmax',
      );
      expect(await learning.errors(1), isEmpty);
      expect((await learning.report(1, document.id))['attempts'], 2);
    },
  );

  test(
    'regenerated practice questions keep old answer and error history',
    () async {
      final ai = AiGenerationRepository(database: app);
      await ai.replacePracticeQuestions(
        documentId: document.id,
        questions: [
          {'question_text': 'Attention 是什么？', 'answer_text': '加权聚合'},
        ],
      );
      final original = (await ai.fetchPracticeQuestions(document.id)).single;
      await ai.markPracticeQuestionWrong(
        questionId: original.id,
        userAnswer: '不知道',
      );
      await ai.replacePracticeQuestions(
        documentId: document.id,
        questions: [
          {'question_text': 'Attention 是什么？', 'answer_text': '加权聚合'},
          {'question_text': '权重如何计算？', 'answer_text': 'Softmax'},
        ],
      );
      final all = await ai.fetchPracticeQuestions(document.id);
      expect(all, hasLength(2));
      final retained = all.firstWhere((q) => q.id == original.id);
      expect(retained.wrongCount, 1);
      expect(retained.lastUserAnswer, '不知道');
      expect(await learning.errors(1), hasLength(1));
    },
  );

  test(
    'merging concepts rewires learning history and document associations',
    () async {
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        draft: KnowledgeGraphDraft(
          concepts: [
            draft.concepts.single,
            const KnowledgeConceptDraft(
              name: '注意力',
              summary: '聚合',
              evidenceText: '',
              masteryScore: 0,
              weaknessScore: 0,
            ),
          ],
          links: [],
        ),
      );
      final concepts = await learning.concepts(1, document.id);
      await learning.recordAttempt(
        userId: 1,
        documentId: document.id,
        conceptId: concepts.last.id,
        origin: 'interview',
        prompt: '问题',
        answer: '回答',
        score: 20,
        feedback: '遗漏',
        hasError: true,
      );
      await learning.mergeConcepts(1, concepts.last.id, concepts.first.id);
      expect(await learning.concepts(1, document.id), hasLength(1));
      expect((await learning.errors(1)).single.conceptId, concepts.first.id);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('flashcard ratings persist future review schedules', () async {
    final resource = await learning.saveResource(
      userId: 1,
      documentId: document.id,
      type: 'flashcards',
      title: '闪卡',
      content: '{"cards":[{"front":"Attention?","back":"加权聚合"}]}',
      inputText: 'source',
      model: 'vision',
    );
    expect(await learning.dueFlashcards(1), hasLength(1));
    await learning.reviewCard(1, resource.id, 0, 3);
    expect(await learning.dueFlashcards(1), isEmpty);
    final next = (await learning.cardSchedule(resource.id))[0]!;
    expect(next.isAfter(DateTime.now()), isTrue);
    await expectLater(
      learning.reviewCard(2, resource.id, 0, 3),
      throwsStateError,
    );
  });

  test(
    'generated resources are cached until source or model changes',
    () async {
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        draft: draft,
      );
      var calls = 0;
      final client = MiniMaxClient(
        apiKey: 'test',
        provider: 'custom',
        model: 'vision-model',
        httpClient: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '{"title":"笔记","content":"Attention 机制"}',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final config = LlmProviderConfig.emptyForUser(1).copyWith(
        provider: 'custom',
        apiKey: 'test',
        model: 'vision-model',
        baseUrl: 'https://example.com',
      );
      final service = LearningResourceService(database: app, client: client);
      final first = await service.generate(document, config, 'notes');
      final cached = await service.generate(document, config, 'notes');
      expect(cached.id, first.id);
      expect(calls, 1);
      await service.generate(document, config, 'notes', force: true);
      expect(calls, 2);
      expect(
        await learning.resources(1, document.id, type: 'notes'),
        hasLength(2),
      );
      await learning.editConcept(
        1,
        (await learning.concepts(1, document.id)).single.id,
        'Attention',
        '修订后的知识',
      );
      await service.generate(document, config, 'notes');
      expect(calls, 3);
    },
  );

  test(
    'shared graph relationships survive deletion of the original library',
    () async {
      final second = await KnowledgeLibraryRepository(
        database: app,
      ).createLibrary(userId: 1, name: '数学');
      await learning.setLibraries(1, document.id, [library, second.id]);
      await graph.replaceGraphForDocument(
        userId: 1,
        documentId: document.id,
        libraryId: library,
        draft: KnowledgeGraphDraft(
          concepts: [
            draft.concepts.single,
            const KnowledgeConceptDraft(
              name: 'Softmax',
              summary: '归一化',
              evidenceText: '',
              masteryScore: 0,
              weaknessScore: 0,
            ),
          ],
          links: [
            const KnowledgeConceptLinkDraft(
              fromName: 'Softmax',
              toName: 'Attention',
              relationLabel: '前置',
            ),
          ],
        ),
      );
      expect(
        await graph.fetchLinksByLibrary(userId: 1, libraryId: second.id),
        hasLength(1),
      );
      await KnowledgeLibraryRepository(
        database: app,
      ).deleteLibraryAndContents(userId: 1, libraryId: library);
      expect(
        await graph.fetchLinksByLibrary(userId: 1, libraryId: second.id),
        hasLength(1),
      );
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('selected learning direction is sent with the original image', () async {
    final temp = await Directory.systemTemp.createTemp('pxt_direction_');
    final path = '${temp.path}/fixture.png';
    await File(path).writeAsBytes([1, 2, 3]);
    Map? payload;
    final client = MiniMaxClient(
      provider: 'custom',
      apiKey: 'test',
      model: 'vision',
      httpClient: MockClient((request) async {
        payload = jsonDecode(request.body) as Map;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({'title': '原理', 'summary': '所选方向的解释'}),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final config = LlmProviderConfig.emptyForUser(
      1,
    ).copyWith(provider: 'custom', apiKey: 'test', model: 'vision');
    final result = await LearningResourceService(database: app, client: client)
        .focusTopic(
          document,
          config,
          {'visible_text': 'diagram'},
          {'title': '机械结构'},
          '学习原理',
          imagePath: path,
        );
    final content =
        ((payload!['messages'] as List).last as Map)['content'] as List;
    expect(content.first['image_url']['url'], 'data:image/png;base64,AQID');
    expect(content.last['text'], contains('学习方向：学习原理'));
    expect(result['summary'], '所选方向的解释');
    await temp.delete(recursive: true);
  });

  test(
    'OpenAI-compatible vision request includes the original image',
    () async {
      Map? payload;
      final client = MiniMaxClient(
        provider: 'custom',
        apiKey: 'test',
        model: 'vision',
        httpClient: MockClient((request) async {
          payload = jsonDecode(request.body) as Map;
          return http.Response(
            '{"choices":[{"message":{"content":"{\\"topics\\":[]}"}}]}',
            200,
          );
        }),
      );
      await client.generateStructuredJson(
        systemPrompt: 'system',
        userPrompt: 'understand',
        images: [(base64: 'YWJj', mimeType: 'image/png')],
      );
      final content =
          ((payload!['messages'] as List).last as Map)['content'] as List;
      expect(
        (content.first as Map)['image_url']['url'],
        'data:image/png;base64,YWJj',
      );
      expect((content.last as Map)['text'], 'understand');
    },
  );
}
