import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/focus/models/pomodoro_task.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';
import 'package:pxt1/learning/learning_events.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Directory directory;
  late FocusRepository focus;
  late int userId;
  late DateTime now;
  late PomodoroTask task;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pxt-focus-');
    app = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: '${directory.path}/focus.db',
    );
    db = await app.database;
    await AuthRepository(
      database: app,
    ).register(username: 'focus-test', password: 'offline-test');
    userId =
        (await db.query(
              'users',
              where: 'username = ?',
              whereArgs: ['focus-test'],
            )).single['id']
            as int;
    now = DateTime(2026, 10, 15, 10);
    focus = FocusRepository(database: app, now: () => now);
    task = await focus.createTask(
      userId: userId,
      title: '复习数学',
      estimatedPomodoros: 3,
    );
  });

  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> storedTask() async => (await db.query(
    'pomodoro_tasks',
    where: 'id = ?',
    whereArgs: [task.id],
  )).single;

  test(
    'wall clock, pause, process recovery and atomic idempotent finish',
    () async {
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '25/5',
      );
      expect((await storedTask())['status'], 'in_progress');
      now = now.add(const Duration(seconds: 125));
      final paused = await focus.pauseRecord(record.id);
      expect(paused.durationSeconds, 125);
      expect((await storedTask())['status'], 'paused');
      now = now.add(const Duration(hours: 2));
      await db.close();
      app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: '${directory.path}/focus.db',
      );
      db = await app.database;
      focus = FocusRepository(database: app, now: () => now);
      final restored = (await focus.restoreActiveRecord(userId))!;
      expect(restored.timerState, 'paused');
      expect(restored.elapsedSecondsAt(now), 125);
      final resumed = await focus.resumeRecord(record.id);
      expect((await storedTask())['status'], 'in_progress');
      now = now.add(const Duration(seconds: 65));
      expect(resumed.elapsedSecondsAt(now), 190);
      final revision = LearningEvents.changed.value;
      await Future.wait([
        focus.completeRecord(record.id, 999999),
        focus.completeRecord(record.id, 999999),
      ]);
      expect(LearningEvents.changed.value, greaterThan(revision));
      expect(await focus.restoreActiveRecord(userId), isNull);
      final records = await focus.fetchRecords(userId: userId);
      expect(records.single.durationSeconds, 190);
      expect(records.single.completed, isTrue);
      expect((await storedTask())['focused_seconds'], 190);
      expect((await storedTask())['status'], 'in_progress');
      expect((await storedTask())['completed_at'], isNull);
      final stats = await focus.fetchStats(userId);
      expect(stats.todaySeconds, 190);
      expect(stats.todayPomodoros, 1);
      expect(stats.totalPoints, 8);
    },
  );

  test(
    'running restoration uses persisted anchor and caps target after downtime',
    () async {
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '25/5',
      );
      now = now.add(const Duration(hours: 3));
      final fresh = FocusRepository(database: app, now: () => now);
      final restored = (await fresh.restoreActiveRecord(userId))!;
      expect(restored.resumedAt, record.resumedAt);
      expect(restored.elapsedSecondsAt(now), 1500);
      await fresh.completeRecord(record.id, 0);
      expect(
        (await fresh.fetchRecords(userId: userId)).single.durationSeconds,
        1500,
      );
      expect((await fresh.fetchStats(userId)).totalPoints, 30);
    },
  );

  test(
    'start checks ownership, terminal state and serializes concurrent starts',
    () async {
      await AuthRepository(
        database: app,
      ).register(username: 'other', password: 'offline-test');
      final other =
          (await db.query(
                'users',
                where: 'username = ?',
                whereArgs: ['other'],
              )).single['id']
              as int;
      await expectLater(
        focus.startRecord(userId: other, taskId: task.id, pomodoroMode: '正向'),
        throwsStateError,
      );
      final results = await Future.wait(
        List.generate(2, (_) async {
          try {
            await focus.startRecord(
              userId: userId,
              taskId: task.id,
              pomodoroMode: '正向',
            );
            return true;
          } on StateError {
            return false;
          }
        }),
      );
      expect(results.where((success) => success).length, 1);
      final open = (await focus.restoreActiveRecord(userId))!;
      await focus.cancelRecord(open.id);
      await db.update(
        'pomodoro_tasks',
        {'status': 'completed'},
        where: 'id = ?',
        whereArgs: [task.id],
      );
      await expectLater(
        focus.startRecord(userId: userId, taskId: task.id, pomodoroMode: '正向'),
        throwsStateError,
      );
      await expectLater(
        focus.updateTaskState(
          userId: userId,
          taskId: task.id,
          status: 'pending',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'active records block soft deletion; tombstone preserves history and source dedup',
    () async {
      task = await focus.createTask(
        userId: userId,
        title: '来源任务',
        sourceKey: 'fixture:source',
      );
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      await expectLater(
        focus.deleteTask(task.id, userId: userId),
        throwsStateError,
      );
      now = now.add(const Duration(minutes: 1));
      await focus.completeRecord(record.id, 60);
      await focus.deleteTask(task.id, userId: userId);
      expect((await storedTask())['status'], 'deleted');
      expect((await storedTask())['is_archived'], 1);
      expect(
        (await focus.fetchTasks(userId)).any((t) => t.id == task.id),
        isFalse,
      );
      expect(
        (await focus.fetchRecords(userId: userId)).single.taskTitle,
        '来源任务',
      );
      final dedup = await focus.createTask(
        userId: userId,
        title: '不要重新出现',
        sourceKey: 'fixture:source',
      );
      expect(dedup.id, task.id);
      expect(dedup.status, 'deleted');
    },
  );

  test(
    'finish rolls back record, task total and points together on storage failure',
    () async {
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      now = now.add(const Duration(minutes: 2));
      await db.execute(
        "CREATE TRIGGER fail_focus_checkin BEFORE INSERT ON checkin_records BEGIN SELECT RAISE(ABORT, 'fixture failure'); END",
      );
      final revision = LearningEvents.changed.value;
      await expectLater(
        focus.completeRecord(record.id, 120),
        throwsA(isA<DatabaseException>()),
      );
      expect(LearningEvents.changed.value, revision);
      expect((await focus.restoreActiveRecord(userId))!.id, record.id);
      expect((await storedTask())['focused_seconds'], 0);
      expect(await db.query('checkin_records'), isEmpty);
      await db.execute('DROP TRIGGER fail_focus_checkin');
      await focus.completeRecord(record.id, 120);
      expect((await focus.fetchStats(userId)).totalPoints, 7);
    },
  );

  test(
    'midnight allocation excludes paused intervals and awards one bonus',
    () async {
      now = DateTime(2026, 10, 15, 23, 58);
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      now = DateTime(2026, 10, 15, 23, 59);
      await focus.pauseRecord(record.id);
      now = DateTime(2026, 10, 16, 0, 1);
      await focus.resumeRecord(record.id);
      now = DateTime(2026, 10, 16, 0, 3);
      await focus.completeRecord(record.id, 180);
      final days = await focus.fetchCheckins(
        userId: userId,
        year: 2026,
        month: 10,
      );
      expect(days.map((d) => d.studySeconds), [60, 120]);
      expect(days.map((d) => d.pomodoroCount), [0, 1]);
      expect(days.map((d) => d.pointsEarned), [1, 7]);
      expect((await storedTask())['focused_seconds'], 180);
      final todayRecords = await focus.fetchRecords(
        userId: userId,
        fromDate: DateTime(2026, 10, 16),
      );
      expect(todayRecords.single.id, record.id);
    },
  );

  test(
    'continuous interval crossing midnight splits by local calendar date',
    () async {
      now = DateTime(2026, 10, 15, 23, 59);
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      now = DateTime(2026, 10, 16, 0, 1);
      await focus.completeRecord(record.id, 120);
      final days = await focus.fetchCheckins(
        userId: userId,
        year: 2026,
        month: 10,
      );
      expect(days.map((d) => d.studySeconds), [60, 60]);
      expect(days.map((d) => d.pointsEarned), [1, 6]);
    },
  );

  test(
    'focus cannot change question mastery, concept state or an already completed task',
    () async {
      final library = (await KnowledgeLibraryRepository(
        database: app,
      ).fetchLibraries(userId)).single;
      final document = await SourceDocumentRepository(database: app)
          .createSourceDocument(
            userId: userId,
            libraryId: library.id,
            title: '数学.pdf',
            sourceType: 'pdf_document',
            imagePath: 'fixture.pdf',
          );
      final concept = await db.insert('knowledge_concepts', {
        'user_id': userId,
        'library_id': library.id,
        'document_id': document.id,
        'name': '微积分',
        'summary': 'fixture',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      final question = await db.insert('practice_questions', {
        'document_id': document.id,
        'question_text': '求导',
        'answer_text': 'fixture',
        'created_at': now.toIso8601String(),
      });
      task = await focus.createTask(
        userId: userId,
        title: '练习求导',
        kind: 'practice',
        documentId: document.id,
        conceptId: concept,
        questionId: question,
      );
      final questionBefore = await db.query('practice_questions');
      final conceptBefore = await db.query('knowledge_concepts');
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      await db.update(
        'pomodoro_tasks',
        {'status': 'completed', 'completed_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [task.id],
      );
      now = now.add(const Duration(seconds: 60));
      await focus.pauseRecord(record.id);
      await focus.resumeRecord(record.id);
      await focus.completeRecord(record.id, 60);
      expect((await storedTask())['status'], 'completed');
      expect((await storedTask())['focused_seconds'], 60);
      expect(await db.query('practice_questions'), questionBefore);
      expect(await db.query('knowledge_concepts'), conceptBefore);
    },
  );

  test(
    'manual checkin remains checked in at zero seconds and makeup keeps its cost',
    () async {
      await Future.wait([
        focus.checkInToday(userId),
        focus.checkInToday(userId),
      ]);
      expect((await focus.fetchStats(userId)).isCheckedInToday, isTrue);
      expect((await db.query('checkin_records')).length, 1);
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      now = now.add(const Duration(minutes: 30));
      await focus.completeRecord(record.id, 1800);
      expect(
        await focus.makeupCheckin(
          userId,
          now.subtract(const Duration(days: 1)),
        ),
        isTrue,
      );
      expect((await focus.fetchStats(userId)).totalPoints, 5);
      expect(
        await focus.makeupCheckin(
          userId,
          now.subtract(const Duration(days: 1)),
        ),
        isFalse,
      );
    },
  );

  test(
    'task edits retain current focused time and models read optional joined metadata',
    () async {
      final record = await focus.startRecord(
        userId: userId,
        taskId: task.id,
        pomodoroMode: '正向',
      );
      now = now.add(const Duration(seconds: 75));
      await focus.completeRecord(record.id, 75);
      await focus.updateTask(
        task.copyWith(title: '新标题', estimatedPomodoros: 4),
      );
      final updated = (await focus.fetchTasks(userId)).single;
      expect(updated.focusedSeconds, 75);
      expect(updated.status, 'in_progress');
      expect(updated.estimatedPomodoros, 4);
      expect(
        PomodoroTask.fromMap({
          'id': 1,
          'user_id': userId,
          'created_at': now.toIso8601String(),
          'document_title': '文档',
          'library_name': '知识库',
        }).documentTitle,
        '文档',
      );
    },
  );
}
