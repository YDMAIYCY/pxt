import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';
import 'package:pxt1/learning/study_activity_repository.dart';
import 'package:pxt1/learning/study_activity_tracker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late Directory directory;
  late StudyActivityRepository activity;
  late StudyActivityTracker tracker;
  late int userId;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pxt-study-activity-');
    app = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: '${directory.path}/study.db',
    );
    db = await app.database;
    final auth = AuthRepository(database: app);
    await auth.register(username: 'learner', password: 'test-password');
    userId = (await db.query('users')).single['id'] as int;
    now = DateTime(2026, 10, 17, 10);
    activity = StudyActivityRepository(database: app, now: () => now);
    tracker = StudyActivityTracker(repository: activity, now: () => now);
  });

  tearDown(() async {
    await tracker.pause();
    tracker.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'entry counts today immediately, repeated flushes do not duplicate time',
    () async {
      final focus = FocusRepository(database: app, now: () => now);
      expect(await focus.fetchLearningStreak(userId), 0);
      await tracker.start(userId);
      expect(await focus.fetchLearningStreak(userId), 1);
      expect(await activity.todaySeconds(userId), 0);
      now = now.add(const Duration(minutes: 3));
      await tracker.flush();
      await tracker.flush();
      expect(await activity.todaySeconds(userId), 180);
      expect((await focus.fetchStats(userId)).todaySeconds, 0);
      expect(await db.query('checkin_records'), isEmpty);
    },
  );

  test(
    'background time is excluded and foreground resumes from the new time',
    () async {
      await tracker.start(userId);
      now = now.add(const Duration(seconds: 45));
      await tracker.pause();
      now = now.add(const Duration(hours: 2));
      await tracker.resume();
      now = now.add(const Duration(seconds: 15));
      await tracker.pause();
      expect(await activity.todaySeconds(userId), 60);
    },
  );

  test(
    'cross-midnight usage is split and missing days break the streak',
    () async {
      now = DateTime(2026, 10, 17, 23, 59, 30);
      await tracker.start(userId);
      now = DateTime(2026, 10, 18, 0, 0, 30);
      await tracker.pause();
      final days = await db.query('study_activity_days', orderBy: 'day');
      expect(days.map((day) => day['foreground_seconds']), [30, 30]);
      final focus = FocusRepository(database: app, now: () => now);
      expect(await activity.todaySeconds(userId), 30);
      expect(await focus.fetchLearningStreak(userId), 2);
      now = DateTime(2026, 10, 20, 10);
      await tracker.resume();
      expect(await focus.fetchLearningStreak(userId), 1);
      expect(await activity.todaySeconds(userId), 0);
    },
  );

  test(
    'account switches keep usage isolated and reopen preserves totals',
    () async {
      await tracker.start(userId);
      now = now.add(const Duration(seconds: 90));
      await AuthRepository(
        database: app,
      ).register(username: 'other', password: 'test-password');
      final other =
          (await db.query(
                'users',
                where: 'username=?',
                whereArgs: ['other'],
              )).single['id']
              as int;
      await tracker.start(other);
      now = now.add(const Duration(seconds: 30));
      await tracker.pause();
      expect(await activity.todaySeconds(userId), 90);
      expect(await activity.todaySeconds(other), 30);
      await db.close();
      app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: '${directory.path}/study.db',
      );
      db = await app.database;
      final restored = StudyActivityRepository(database: app, now: () => now);
      expect(await restored.todaySeconds(userId), 90);
      expect(await restored.todaySeconds(other), 30);
    },
  );

  test(
    'v25 upgrade backs up and preserves users, sessions and focus records',
    () async {
      final auth = AuthRepository(database: app);
      await auth.login(username: 'learner', password: 'test-password');
      await db.insert('checkin_records', {
        'user_id': userId,
        'date': '2026-10-17',
        'study_seconds': 1800,
        'pomodoro_count': 1,
        'points_earned': 30,
        'is_makeup': 0,
        'created_at': now.toUtc().toIso8601String(),
      });
      await db.execute('DROP TABLE study_activity_days');
      await db.setVersion(25);
      await db.close();
      app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: '${directory.path}/study.db',
      );
      db = await app.database;
      expect(await db.getVersion(), AppDatabase.databaseVersion);
      expect((await db.query('users')).single['id'], userId);
      expect((await db.query('auth_sessions')).single['user_id'], userId);
      expect((await db.query('checkin_records')).single['study_seconds'], 1800);
      expect(await db.query('study_activity_days'), isEmpty);
      final backups = await directory
          .list()
          .where((file) => file.path.contains('.before-community-v25-'))
          .toList();
      expect(backups, hasLength(1));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 25);
      expect((await backup.query('users')).single['id'], userId);
      expect((await backup.query('auth_sessions')).single['user_id'], userId);
      expect(
        (await backup.query('checkin_records')).single['study_seconds'],
        1800,
      );
      await backup.close();
    },
  );
}
