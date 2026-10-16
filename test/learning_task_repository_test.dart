import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/database/practice_session_repository.dart';
import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/learning/learning_task_repository.dart';
import 'package:pxt1/learning/review_priority_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase database;
  late Database db;
  late LearningTaskRepository tasks;
  late int userId, documentId, conceptId, questionId;
  late DateTime now;
  setUp(() async {
    database = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await database.database;
    now = DateTime.now().toUtc();
    final auth = await AuthRepository(
      database: database,
    ).register(username: 'learning-test', password: 'offline-test');
    expect(auth.success, isTrue);
    userId = (await db.query('users')).single['id'] as int;
    final library = (await KnowledgeLibraryRepository(
      database: database,
    ).fetchLibraries(userId)).single;
    final document = await SourceDocumentRepository(database: database)
        .createSourceDocument(
          userId: userId,
          libraryId: library.id,
          title: '设计模式.pdf',
          sourceType: 'pdf_document',
          imagePath: 'fixture.pdf',
        );
    documentId = document.id;
    conceptId = await db.insert('knowledge_concepts', {
      'user_id': userId,
      'library_id': library.id,
      'document_id': documentId,
      'name': '策略模式',
      'summary': '封装可替换的算法',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    questionId = await db.insert('practice_questions', {
      'document_id': documentId,
      'question_text': '策略模式如何切换算法？',
      'answer_text': '通过组合替换策略',
      'created_at': now.toIso8601String(),
      'next_review_at': now.toIso8601String(),
    });
    await db.insert('question_concepts', {
      'question_id': questionId,
      'concept_id': conceptId,
    });
    tasks = LearningTaskRepository(database: database, clock: () => now);
  });
  tearDown(() async => db.close());

  test(
    'dashboard projection is stable and cancelled sources stay cancelled',
    () async {
      final first = await tasks.dashboard(userId);
      final id = first.tasks.single.id;
      expect(first.pendingPractice, 1);
      expect(first.wrongQuestions, 0);
      expect(first.recommendations, isEmpty);
      expect((await tasks.dashboard(userId)).tasks.single.id, id);
      await tasks.setStatus(userId, id, 'cancelled');
      expect((await tasks.dashboard(userId)).tasks, isEmpty);
      expect((await db.query('pomodoro_tasks')).length, 1);
    },
  );

  test(
    'actual wrong answer completes occurrence and creates one new wrong review',
    () async {
      final original = (await tasks.dashboard(userId)).tasks.single;
      final practice = PracticeSessionRepository(database: database);
      final submission = await practice.submit(
        scope: PracticeScope(userId: userId),
        questionId: questionId,
        requestId: 'answer-1',
        answer: '错误答案',
        correct: false,
        now: now.add(const Duration(seconds: 5)),
      );
      final after = await tasks.dashboard(userId);
      expect(after.wrongQuestions, 1);
      expect(after.tasks.single.kind, 'wrong_review');
      expect(after.tasks.single.id, isNot(original.id));
      expect(after.recommendations.single.reason, contains('错误较多'));
      expect(
        (await tasks.tasks(
          userId,
          includeFinished: true,
        )).firstWhere((t) => t.id == original.id).status,
        'completed',
      );
      await practice.submit(
        scope: PracticeScope(userId: userId),
        questionId: questionId,
        requestId: 'answer-1',
        answer: '错误答案',
        correct: false,
      );
      expect((await tasks.dashboard(userId)).tasks.length, 1);
      expect(
        (await db.query('practice_submissions')).single['id'],
        submission.id,
      );
      expect((await db.query('knowledge_concepts')).single['mastery_score'], 0);
    },
  );

  test(
    'one correct answer preserves unresolved wrong count without claiming mastery',
    () async {
      final p = PracticeSessionRepository(database: database);
      await p.submit(
        scope: PracticeScope(userId: userId),
        questionId: questionId,
        requestId: 'wrong',
        answer: '错',
        correct: false,
        now: now,
      );
      await tasks.dashboard(userId);
      await p.submit(
        scope: PracticeScope(userId: userId),
        questionId: questionId,
        requestId: 'right',
        answer: '组合策略',
        correct: true,
        now: now.add(const Duration(minutes: 20)),
      );
      expect((await tasks.dashboard(userId)).wrongQuestions, 1);
      expect(
        (await db.query('practice_questions')).single['review_status'],
        'pending',
      );
      expect(
        (await db.query('knowledge_concepts')).single['mastery_score'],
        lessThan(100),
      );
    },
  );

  test(
    'practice tasks cannot be manually completed or completed by merely querying',
    () async {
      final t = (await tasks.dashboard(userId)).tasks.single;
      await expectLater(
        tasks.setStatus(userId, t.id, 'completed'),
        throwsStateError,
      );
      expect((await tasks.tasks(userId)).single.status, 'pending');
      await tasks.setStatus(userId, t.id, 'in_progress');
      await tasks.setStatus(userId, t.id, 'paused');
      final due = now.add(const Duration(days: 3));
      await tasks.setStatus(userId, t.id, 'pending', dueAt: due);
      expect((await tasks.dashboard(userId)).tasks.single.dueAt, due.toLocal());
    },
  );

  test(
    'concept schedule deduplicates, completing advances it without altering mastery',
    () async {
      await tasks.addConceptReview(userId, conceptId, dueAt: now);
      await tasks.addConceptReview(userId, conceptId, dueAt: now);
      final reviews = (await tasks.dashboard(
        userId,
      )).tasks.where((t) => t.kind == 'concept_review').toList();
      expect(reviews.length, 1);
      await tasks.setStatus(userId, reviews.single.id, 'completed');
      expect(
        (await tasks.dashboard(
          userId,
        )).tasks.where((t) => t.kind == 'concept_review'),
        isEmpty,
      );
      expect((await db.query('knowledge_concepts')).single['mastery_score'], 0);
      now = now.add(const Duration(days: 2));
      final next = (await tasks.dashboard(
        userId,
      )).tasks.where((t) => t.kind == 'concept_review').single;
      expect(next.id, isNot(reviews.single.id));
    },
  );

  test('AI creation replay and cross-user scope are enforced', () async {
    final a = await tasks.create(
      userId: userId,
      title: '阅读',
      documentId: documentId,
      operationKey: 'op-1',
    );
    final b = await tasks.create(
      userId: userId,
      title: '阅读',
      documentId: documentId,
      operationKey: 'op-1',
    );
    expect(a.id, b.id);
    await AuthRepository(
      database: database,
    ).register(username: 'other', password: 'offline-test');
    final other =
        (await db.query(
              'users',
              where: 'username=?',
              whereArgs: ['other'],
            )).single['id']
            as int;
    await expectLater(
      tasks.create(userId: other, title: '越权', documentId: documentId),
      throwsStateError,
    );
    await expectLater(
      tasks.addConceptReview(other, conceptId),
      throwsStateError,
    );
    await expectLater(
      tasks.setStatus(other, a.id, 'completed'),
      throwsStateError,
    );
    expect(await tasks.tasks(other), isEmpty);
  });

  test(
    'legacy answer entry writes the shared evidence and updates canonical tasks',
    () async {
      final original = (await tasks.dashboard(userId)).tasks.single;
      await AiGenerationRepository(
        database: database,
      ).markPracticeQuestionWrong(questionId: questionId, userAnswer: '错误');
      expect((await db.query('practice_submissions')).length, 1);
      expect(
        (await tasks.tasks(
          userId,
          includeFinished: true,
        )).firstWhere((t) => t.id == original.id).status,
        'completed',
      );
      expect((await tasks.dashboard(userId)).wrongQuestions, 1);
      expect((await tasks.recommendations(userId)).single.conceptId, conceptId);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'priority weights are configurable and due/error/low mastery increase priority',
    () {
      const policy = ReviewPriorityPolicy();
      final low = policy.score(
        mastery: 95,
        attempts: 10,
        errors: 0,
        now: now,
        lastStudiedAt: now,
      );
      final high = policy.score(
        mastery: 20,
        attempts: 10,
        errors: 8,
        now: now,
        dueAt: now.subtract(const Duration(days: 4)),
        lastStudiedAt: now.subtract(const Duration(days: 12)),
        importance: 5,
      );
      expect(high, greaterThan(low));
      const onlyErrors = ReviewPriorityPolicy(
        weights: ReviewPriorityWeights(
          overdue: 0,
          errors: 100,
          mastery: 0,
          recency: 0,
          importance: 0,
        ),
      );
      expect(
        onlyErrors.score(mastery: 0, attempts: 10, errors: 2, now: now),
        20,
      );
    },
  );

  test(
    'v22 upgrade preserves original task IDs, sessions and legacy defaults',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'pxt-learning-migration-',
      );
      final path = '${folder.path}/legacy.db';
      final old = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final legacy = await old.database;
      final timestamp = now.toIso8601String();
      await legacy.insert('users', {
        'id': 1,
        'username': 'legacy',
        'password_hash': 'x',
        'password_salt': 'x',
        'created_at': timestamp,
        'updated_at': timestamp,
      });
      await legacy.insert('pomodoro_tasks', {
        'id': 42,
        'user_id': 1,
        'title': '原有阅读',
        'created_at': timestamp,
      });
      await legacy.insert('pomodoro_records', {
        'id': 43,
        'task_id': 42,
        'user_id': 1,
        'started_at': timestamp,
        'ended_at': timestamp,
        'duration_seconds': 60,
        'completed': 1,
      });
      await legacy.execute('DROP INDEX idx_learning_task_source');
      for (final column in [
        'kind',
        'status',
        'source_key',
        'document_id',
        'concept_id',
        'question_id',
        'due_at',
        'completed_at',
        'focused_seconds',
      ]) {
        await legacy.execute('ALTER TABLE pomodoro_tasks DROP COLUMN $column');
      }
      for (final column in [
        'timer_state',
        'resumed_at',
        'target_seconds',
        'active_segments_json',
      ]) {
        await legacy.execute(
          'ALTER TABLE pomodoro_records DROP COLUMN $column',
        );
      }
      await legacy.execute('DROP TABLE concept_review_schedules');
      await legacy.setVersion(22);
      await legacy.close();
      final reopened = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final upgraded = await reopened.database;
      expect(await upgraded.getVersion(), AppDatabase.databaseVersion);
      expect((await upgraded.query('pomodoro_tasks')).single['id'], 42);
      expect(
        (await upgraded.query('pomodoro_tasks')).single['kind'],
        'personal',
      );
      expect(
        (await upgraded.query('pomodoro_records')).single['duration_seconds'],
        60,
      );
      expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await upgraded.close();
      await folder.delete(recursive: true);
    },
  );
}
