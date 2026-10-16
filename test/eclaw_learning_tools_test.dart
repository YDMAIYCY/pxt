import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/agent/agent_task_executor.dart';
import 'package:pxt1/agent/eclaw_context.dart';
import 'package:pxt1/agent/eclaw_planner.dart';
import 'package:pxt1/agent/eclaw_task.dart';
import 'package:pxt1/agent/eclaw_tool_registry.dart';
import 'package:pxt1/database/agent_task_repository.dart';
import 'package:pxt1/database/ai_chat_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/learning_state_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/learning/learning_events.dart';
import 'package:pxt1/learning/learning_task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase database;
  late EClawToolRegistry registry;
  late LearningTaskRepository learning;
  late int userId, libraryId, documentId, recordId, conceptId;

  Future<Map<String, dynamic>> run(
    String tool,
    Map<String, dynamic> args, {
    EClawContext scope = const EClawContext(),
    bool confirmed = false,
    String key = 'operation',
  }) => registry.run(
    tool,
    EClawToolCall(
      userId: userId,
      context: scope,
      args: args,
      operationKey: key,
    ),
    confirmed: confirmed,
  );

  Future<int> concept(int docId, int libId, String name) async {
    final db = await database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.insert('knowledge_concepts', {
      'user_id': userId,
      'library_id': libId,
      'document_id': docId,
      'name': name,
      'mastery_score': 25,
      'weakness_score': 75,
      'created_at': now,
      'updated_at': now,
    });
  }

  setUp(() async {
    database = await AppDatabase.openForTesting(databaseFactoryFfi);
    final auth = AuthRepository(database: database);
    await auth.register(username: 'eclaw-learning', password: 'offline-test');
    final login = await auth.login(
      username: 'eclaw-learning',
      password: 'offline-test',
    );
    expect(login.success, isTrue, reason: login.message);
    userId = login.userId!;
    libraryId = (await KnowledgeLibraryRepository(
      database: database,
    ).fetchLibraries(userId)).single.id;
    final doc = await SourceDocumentRepository(database: database)
        .createSourceDocument(
          userId: userId,
          libraryId: libraryId,
          title: '函数与极限',
          sourceType: 'pdf_document',
          imagePath: 'fixture.pdf',
        );
    documentId = doc.id;
    recordId = doc.importRecordId!;
    conceptId = await concept(documentId, libraryId, '函数极限');
    registry = EClawToolRegistry(database: database);
    learning = LearningTaskRepository(database: database);
  });
  tearDown(() async => (await database.database).close());

  test(
    'canonical queries filter library, record, document and empty scopes',
    () async {
      final libraries = KnowledgeLibraryRepository(database: database);
      final otherLibrary = await libraries.createLibrary(
        userId: userId,
        name: '其他知识库',
      );
      final otherDoc = await SourceDocumentRepository(database: database)
          .createSourceDocument(
            userId: userId,
            libraryId: otherLibrary.id,
            title: '其他资料',
            sourceType: 'pdf_document',
            imagePath: 'other.pdf',
          );
      final secondDoc = await SourceDocumentRepository(database: database)
          .createSourceDocument(
            userId: userId,
            libraryId: libraryId,
            title: '同库另一记录',
            sourceType: 'pdf_document',
            imagePath: 'second.pdf',
          );
      final otherConcept = await concept(otherDoc.id, otherLibrary.id, '其他知识点');
      final due = DateTime.now().subtract(const Duration(days: 2));
      await learning.addConceptReview(userId, conceptId, dueAt: due);
      await learning.addConceptReview(userId, otherConcept, dueAt: due);
      await learning.create(
        userId: userId,
        title: '同库其他记录任务',
        documentId: secondDoc.id,
      );
      await learning.create(userId: userId, title: '账户个人任务');
      final canonical = await learning.dashboard(userId);
      final global = await LearningStateRepository(
        database: database,
      ).read(userId, const EClawContext());
      expect(global['tasks'], canonical.tasks.map((t) => t.toJson()).toList());
      expect(
        global['recommendations'],
        canonical.recommendations.map((r) => r.toJson()).toList(),
      );
      for (final scope in [
        EClawContext(importRecordId: recordId),
        EClawContext(documentId: documentId),
      ]) {
        final result = await run('query_today_tasks', {}, scope: scope);
        expect(
          (result['tasks'] as List).map((t) => t['documentId']),
          everyElement(documentId),
        );
        expect(result['tasks'], hasLength(1));
        final recommendations = await run(
          'get_review_recommendations',
          {},
          scope: scope,
        );
        expect(
          (recommendations['recommendations'] as List).single['conceptId'],
          conceptId,
        );
        final state = await LearningStateRepository(
          database: database,
        ).read(userId, scope);
        expect(state['tasks'], result['tasks']);
        expect(state['focus'].toString(), isNot(contains('todaySeconds')));
      }
      final libraryTasks = await run(
        'query_learning_tasks',
        {},
        scope: EClawContext(knowledgeBaseId: libraryId),
      );
      expect(libraryTasks['tasks'], hasLength(2));
      final empty = await libraries.createLibrary(userId: userId, name: '空知识库');
      final result = await run(
        'query_today_tasks',
        {},
        scope: EClawContext(knowledgeBaseId: empty.id),
      );
      expect(result['tasks'], isEmpty);
      expect(result['recommendations'], isEmpty);
      expect(result['pendingPractice'], 0);
      expect(result['wrongQuestions'], 0);
    },
  );

  test(
    'today query excludes future dates but retains overdue and undated tasks',
    () async {
      final now = DateTime.now();
      for (final entry in {
        '逾期': now.subtract(const Duration(days: 2)),
        '今天': DateTime(now.year, now.month, now.day, 23, 59),
        '明天': DateTime(now.year, now.month, now.day + 1),
        '未定日期': null,
      }.entries) {
        await learning.create(
          userId: userId,
          title: entry.key,
          documentId: documentId,
          dueAt: entry.value,
        );
      }
      final today = await run('query_today_tasks', {});
      expect(
        (today['tasks'] as List).map((t) => t['title']),
        unorderedEquals(['逾期', '今天', '未定日期']),
      );
      expect((await run('query_learning_tasks', {}))['tasks'], hasLength(4));
    },
  );

  test(
    'creation waits for confirmation, commits canonical task and deduplicates replay',
    () async {
      final chats = AiChatRepository(database: database);
      final session = await chats.createSession(userId: userId, title: '安排学习');
      final repository = AgentTaskRepository(database: database);
      final executor = AgentTaskExecutor(
        registry: registry,
        repository: repository,
      );
      final task = await repository.create(
        userId: userId,
        sessionId: session.id,
        requestKey: 'create',
        command: '创建学习任务',
        context: EClawContext(importRecordId: recordId),
        steps: [
          AgentTaskStep(
            tool: 'create_learning_task',
            label: '创建任务',
            args: {'title': '复习函数', 'minutes': 50},
          ),
        ],
      );
      final revision = LearningEvents.changed.value;
      await executor.run(task);
      expect(task.status, 'waiting_confirmation');
      expect(await learning.tasks(userId), isEmpty);
      expect(LearningEvents.changed.value, revision);
      await executor.run(task, confirm: true);
      expect(task.status, 'completed');
      final saved = (await learning.tasks(userId)).single;
      expect(saved.documentId, documentId);
      expect(saved.estimatedPomodoros, 2);
      expect(task.steps.single.result['destination'], 'tasks');
      expect(LearningEvents.changed.value, greaterThan(revision));
      await run(
        'create_learning_task',
        {'title': '复习函数', 'minutes': 50},
        scope: EClawContext(importRecordId: recordId),
        confirmed: true,
        key: 'eclaw:$userId:${task.id}:0',
      );
      expect((await learning.tasks(userId)).single.id, saved.id);
    },
  );

  test(
    'write tools reject unconfirmed, foreign and other-scope targets',
    () async {
      final otherLibrary = await KnowledgeLibraryRepository(
        database: database,
      ).createLibrary(userId: userId, name: '其他');
      final otherDoc = await SourceDocumentRepository(database: database)
          .createSourceDocument(
            userId: userId,
            libraryId: otherLibrary.id,
            title: '其他',
            sourceType: 'pdf_document',
            imagePath: 'other.pdf',
          );
      final otherTask = await learning.create(
        userId: userId,
        title: '其他任务',
        documentId: otherDoc.id,
      );
      final otherConcept = await concept(otherDoc.id, otherLibrary.id, '其他概念');
      final scope = EClawContext(importRecordId: recordId);
      final date = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String();
      await expectLater(
        run('create_learning_task', {'title': '未确认'}),
        throwsStateError,
      );
      await expectLater(
        run(
          'adjust_review_schedule',
          {'taskId': otherTask.id, 'dueAt': date},
          scope: scope,
          confirmed: true,
        ),
        throwsStateError,
      );
      await expectLater(
        run(
          'create_learning_task',
          {'title': '越界', 'conceptId': otherConcept},
          scope: scope,
          confirmed: true,
        ),
        throwsStateError,
      );
      await expectLater(
        run('navigate_to_page', {
          'target': 'concept',
          'conceptId': otherConcept,
        }, scope: scope),
        throwsStateError,
      );
      final auth = AuthRepository(database: database);
      await auth.register(username: 'foreign', password: 'offline-test');
      final foreignUser = (await auth.login(
        username: 'foreign',
        password: 'offline-test',
      )).userId!;
      final foreignTask = await learning.create(
        userId: foreignUser,
        title: '他人任务',
      );
      await expectLater(
        run('adjust_review_schedule', {
          'taskId': foreignTask.id,
          'dueAt': date,
        }, confirmed: true),
        throwsStateError,
      );
      final empty = await KnowledgeLibraryRepository(
        database: database,
      ).createLibrary(userId: userId, name: '空库');
      await expectLater(
        run(
          'create_learning_task',
          {'title': '无来源'},
          scope: EClawContext(knowledgeBaseId: empty.id),
          confirmed: true,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'schedule changes require confirmation and receipt replay preserves later changes',
    () async {
      final task = await learning.create(
        userId: userId,
        title: '复习',
        documentId: documentId,
      );
      final date = DateTime.now().add(const Duration(days: 1));
      final args = {'taskId': task.id, 'dueAt': date.toIso8601String()};
      await expectLater(run('adjust_review_schedule', args), throwsStateError);
      expect((await learning.tasks(userId)).single.dueAt, isNull);
      final result = await run(
        'adjust_review_schedule',
        args,
        confirmed: true,
        key: 'adjust',
      );
      expect(
        (await learning.tasks(userId)).single.dueAt!.isAtSameMomentAs(date),
        isTrue,
      );
      final later = date.add(const Duration(days: 3));
      await learning.setStatus(userId, task.id, task.status, dueAt: later);
      expect(
        await run(
          'adjust_review_schedule',
          args,
          confirmed: true,
          key: 'adjust',
        ),
        result,
      );
      expect(
        (await learning.tasks(userId)).single.dueAt!.isAtSameMomentAs(later),
        isTrue,
      );
      await expectLater(
        run('adjust_review_schedule', {
          'taskId': task.id,
          'dueAt': '明天',
        }, confirmed: true),
        throwsArgumentError,
      );
    },
  );

  test(
    'concept review schedule uses fixed date and emits validated concept navigation',
    () async {
      final scope = EClawContext(documentId: documentId);
      final date = DateTime.now().subtract(const Duration(hours: 1));
      final args = {'conceptId': conceptId, 'dueAt': date.toIso8601String()};
      await run(
        'adjust_review_schedule',
        args,
        scope: scope,
        confirmed: true,
        key: 'concept-review',
      );
      await run(
        'adjust_review_schedule',
        args,
        scope: scope,
        confirmed: true,
        key: 'concept-review',
      );
      final db = await database.database;
      expect(
        await db.query(
          'concept_review_schedules',
          where: 'concept_id=?',
          whereArgs: [conceptId],
        ),
        hasLength(1),
      );
      expect(
        (await learning.tasks(userId)).where((t) => t.conceptId == conceptId),
        hasLength(1),
      );
      final result = await run('navigate_to_page', {
        'target': 'concept',
        'conceptId': conceptId,
      }, scope: scope);
      expect(result['destination'], 'concept');
      expect(result['conceptId'], conceptId);
      expect(result['documentId'], documentId);
    },
  );

  test(
    'today planning reads real data and stops at canonical creation confirmation',
    () async {
      await learning.addConceptReview(
        userId,
        conceptId,
        dueAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final scope = EClawContext(importRecordId: recordId);
      final steps = await EClawPlanner().plan('帮我安排今天学习', scope, registry);
      expect(steps.map((s) => s.tool).take(2), [
        'query_today_tasks',
        'get_review_recommendations',
      ]);
      expect(steps.any((s) => s.tool == 'create_practice_task'), isFalse);
      final session = await AiChatRepository(
        database: database,
      ).createSession(userId: userId, title: '今日安排');
      final repository = AgentTaskRepository(database: database);
      final task = await repository.create(
        userId: userId,
        sessionId: session.id,
        requestKey: 'today-plan',
        command: '帮我安排今天学习',
        context: scope,
        steps: steps,
      );
      final executor = AgentTaskExecutor(
        registry: registry,
        repository: repository,
      );
      final count = (await learning.tasks(userId)).length;
      await executor.run(task);
      expect(task.status, 'waiting_confirmation');
      expect(task.waitingStep!.tool, 'create_learning_task');
      expect((await learning.tasks(userId)).length, count);
      final proposal = task.steps
          .singleWhere((s) => s.tool == 'prepare_learning_plan')
          .result;
      expect(proposal['recommendations'], isNotEmpty);
      expect(
        proposal['reason'],
        (proposal['recommendations'] as List).first['reason'],
      );
      await executor.run(task, confirm: true);
      expect(task.status, 'completed');
      expect((await learning.tasks(userId)).length, count + 1);
      expect(task.steps.last.result['task']['documentId'], documentId);
    },
  );
}
