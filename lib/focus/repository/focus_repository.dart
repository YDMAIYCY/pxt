import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../database/app_database.dart';
import '../../learning/learning_events.dart';
import '../models/pomodoro_task.dart';
import '../models/pomodoro_record.dart';
import '../models/checkin_record.dart';

// ========== 积分常量 ==========
class FocusPoints {
  FocusPoints._();

  /// 每专注 1 分钟获得的基础积分
  static const int pointsPerMinute = 1;

  /// 连续打卡 7 天额外奖励
  static const int streak7Bonus = 50;

  /// 连续打卡 30 天额外奖励
  static const int streak30Bonus = 200;

  /// 补签消耗积分
  static const int makeupCost = 30;

  /// 每完成一个番茄额外积分
  static const int pomodoroBonus = 5;
}

// ========== 统计模型 ==========
class FocusStats {
  const FocusStats({
    required this.todaySeconds,
    required this.todayPomodoros,
    required this.weekSeconds,
    required this.monthSeconds,
    required this.totalPoints,
    required this.currentStreak,
    required this.longestStreak,
    required this.isCheckedInToday,
  });

  final int todaySeconds;
  final int todayPomodoros;
  final int weekSeconds;
  final int monthSeconds;
  final int totalPoints;
  final int currentStreak;
  final int longestStreak;
  final bool isCheckedInToday;
}

class TaskTimeStat {
  const TaskTimeStat({
    required this.taskId,
    required this.taskTitle,
    required this.totalSeconds,
    required this.colorIndex,
  });

  final int taskId;
  final String taskTitle;
  final int totalSeconds;
  final int colorIndex;

  double get totalMinutes => totalSeconds / 60.0;

  double get totalHours => totalSeconds / 3600.0;
}

// ========== 专注仓库 ==========
class FocusRepository {
  FocusRepository({AppDatabase? database, DateTime Function()? now})
    : _database = database ?? AppDatabase.instance,
      _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;

  Future<void> ensureInitialized() async {
    await _database.database;
  }

  // ========== 番茄任务 CRUD ==========

  Future<PomodoroTask> createTask({
    required int userId,
    required String title,
    int estimatedPomodoros = 1,
    String? operationKey,
    String kind = 'personal',
    String? sourceKey,
    int? documentId,
    int? conceptId,
    int? questionId,
    DateTime? dueAt,
  }) async {
    if (title.trim().isEmpty || estimatedPomodoros < 1) {
      throw ArgumentError('任务名称不能为空，预估番茄数至少为 1');
    }
    final db = await _database.database;
    final id = await db.transaction((txn) async {
      if (operationKey != null) {
        final receipts = await txn.query(
          'agent_operation_receipts',
          where: 'operation_key = ? AND user_id = ?',
          whereArgs: [operationKey, userId],
        );
        if (receipts.isNotEmpty) {
          return (jsonDecode(receipts.single['result_json'] as String)
                  as Map)['taskId']
              as int;
        }
      }
      int? taskId;
      if (sourceKey != null) {
        final existing = await txn.query(
          AppDatabase.tablePomodoroTasks,
          where: 'user_id = ? AND source_key = ?',
          whereArgs: [userId, sourceKey],
        );
        if (existing.isNotEmpty) taskId = existing.single['id'] as int;
      }
      if (taskId == null) {
        final order = await txn.rawQuery(
          'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM pomodoro_tasks WHERE user_id = ?',
          [userId],
        );
        taskId = await txn.insert(AppDatabase.tablePomodoroTasks, {
          'user_id': userId,
          'title': title.trim(),
          'estimated_pomodoros': estimatedPomodoros,
          'sort_order': (order.single['max_order'] as int) + 1,
          'is_archived': 0,
          'created_at': _now().toUtc().toIso8601String(),
          'kind': kind,
          'status': 'pending',
          'source_key': sourceKey,
          'document_id': documentId,
          'concept_id': conceptId,
          'question_id': questionId,
          'due_at': dueAt?.toUtc().toIso8601String(),
          'focused_seconds': 0,
        });
      }
      if (operationKey != null) {
        await txn.insert('agent_operation_receipts', {
          'operation_key': operationKey,
          'user_id': userId,
          'result_json': jsonEncode({'taskId': taskId}),
        });
      }
      return taskId;
    });
    LearningEvents.notify();
    return PomodoroTask.fromMap(
      (await db.query(
        AppDatabase.tablePomodoroTasks,
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, userId],
      )).single,
    );
  }

  Future<List<PomodoroTask>> fetchTasks(int userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      """
      SELECT t.*, d.original_title AS document_title, l.name AS library_name
      FROM pomodoro_tasks t
      LEFT JOIN source_documents d ON d.id = t.document_id AND d.user_id = t.user_id
      LEFT JOIN knowledge_libraries l ON l.id = d.library_id AND l.user_id = t.user_id
      WHERE t.user_id = ? AND t.is_archived = 0
        AND t.status IN ('pending', 'in_progress', 'paused')
      ORDER BY t.sort_order ASC, t.id ASC
    """,
      [userId],
    );
    return rows.map(PomodoroTask.fromMap).toList();
  }

  Future<void> updateTask(PomodoroTask task) async {
    if (task.title.trim().isEmpty || task.estimatedPomodoros < 1) {
      throw ArgumentError('任务名称不能为空，预估番茄数至少为 1');
    }
    final db = await _database.database;
    // Editing an old UI snapshot must not overwrite focused time or task state.
    final changed = await db.update(
      AppDatabase.tablePomodoroTasks,
      {
        'title': task.title.trim(),
        'estimated_pomodoros': task.estimatedPomodoros,
        'sort_order': task.sortOrder,
      },
      where:
          "id = ? AND user_id = ? AND is_archived = 0 AND status IN ('pending', 'in_progress', 'paused')",
      whereArgs: [task.id, task.userId],
    );
    if (changed == 0) throw StateError('任务已不可编辑，请刷新');
    LearningEvents.notify();
  }

  Future<void> updateTaskState({
    required int userId,
    required int taskId,
    required String status,
  }) async {
    if (!const [
      'pending',
      'in_progress',
      'paused',
      'cancelled',
      'deleted',
      'archived',
    ].contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final db = await _database.database;
    final changed = await db.transaction((txn) async {
      if (const ['cancelled', 'deleted', 'archived'].contains(status)) {
        await _requireNoOpenRecord(txn, taskId, userId: userId);
      }
      return txn.update(
        AppDatabase.tablePomodoroTasks,
        {
          'status': status,
          'is_archived': status == 'deleted' || status == 'archived' ? 1 : 0,
        },
        where:
            "id = ? AND user_id = ? AND is_archived = 0 AND status IN ('pending', 'in_progress', 'paused')",
        whereArgs: [taskId, userId],
      );
    });
    if (changed == 0) throw StateError('任务不存在或已结束');
    LearningEvents.notify();
  }

  Future<void> _requireNoOpenRecord(
    DatabaseExecutor db,
    int taskId, {
    int? userId,
  }) async {
    final open = await db.query(
      AppDatabase.tablePomodoroRecords,
      columns: ['id'],
      where:
          'task_id = ? AND ended_at IS NULL AND completed = 0${userId == null ? '' : ' AND user_id = ?'}',
      whereArgs: [taskId, ?userId],
      limit: 1,
    );
    if (open.isNotEmpty) throw StateError('请先结束该任务的专注');
  }

  Future<void> deleteTask(int taskId, {int? userId}) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await _requireNoOpenRecord(txn, taskId, userId: userId);
      await txn.update(
        AppDatabase.tablePomodoroTasks,
        {'status': 'deleted', 'is_archived': 1},
        where: 'id = ?${userId == null ? '' : ' AND user_id = ?'}',
        whereArgs: [taskId, ?userId],
      );
    });
    LearningEvents.notify();
  }

  Future<void> archiveTask(int taskId, {int? userId}) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await _requireNoOpenRecord(txn, taskId, userId: userId);
      await txn.update(
        AppDatabase.tablePomodoroTasks,
        {'status': 'archived', 'is_archived': 1},
        where: 'id = ?${userId == null ? '' : ' AND user_id = ?'}',
        whereArgs: [taskId, ?userId],
      );
    });
    LearningEvents.notify();
  }

  // A single persisted anchor is authoritative; UI tick frequency is irrelevant.
  Future<PomodoroRecord> startRecord({
    required int userId,
    required int taskId,
    required String pomodoroMode,
    int? targetSeconds,
  }) async {
    final target =
        targetSeconds ??
        switch (pomodoroMode) {
          '25/5' => 25 * 60,
          '45/15' => 45 * 60,
          '50/10' => 50 * 60,
          _ => 0,
        };
    if (target < 0) throw ArgumentError.value(target, 'targetSeconds');
    final db = await _database.database;
    final result = await db.transaction((txn) async {
      final tasks = await txn.query(
        AppDatabase.tablePomodoroTasks,
        where:
            "id = ? AND user_id = ? AND is_archived = 0 AND status IN ('pending', 'in_progress', 'paused')",
        whereArgs: [taskId, userId],
      );
      if (tasks.isEmpty) throw StateError('请选择当前用户的有效任务');
      final open = await txn.query(
        AppDatabase.tablePomodoroRecords,
        where: 'user_id = ? AND ended_at IS NULL AND completed = 0',
        whereArgs: [userId],
      );
      if (open.isNotEmpty) throw StateError('请先结束当前专注');
      final now = _now().toUtc().toIso8601String();
      final id = await txn.insert(AppDatabase.tablePomodoroRecords, {
        'user_id': userId,
        'task_id': taskId,
        'started_at': now,
        'resumed_at': now,
        'timer_state': 'running',
        'duration_seconds': 0,
        'target_seconds': target,
        'active_segments_json': '[]',
        'completed': 0,
        'pomodoro_mode': pomodoroMode,
      });
      await _setActiveTaskState(txn, taskId, userId, 'in_progress');
      return _readRecord(txn, id);
    });
    LearningEvents.notify();
    return result;
  }

  Future<void> _setActiveTaskState(
    DatabaseExecutor db,
    int taskId,
    int userId,
    String status,
  ) => db.update(
    AppDatabase.tablePomodoroTasks,
    {'status': status},
    where:
        "id = ? AND user_id = ? AND is_archived = 0 AND status IN ('pending', 'in_progress', 'paused')",
    whereArgs: [taskId, userId],
  );

  Future<PomodoroRecord> _readRecord(DatabaseExecutor db, int id) async {
    final rows = await db.rawQuery(
      "SELECT r.*, COALESCE(t.title, '已删除的任务') AS task_title FROM pomodoro_records r LEFT JOIN pomodoro_tasks t ON r.task_id = t.id AND r.user_id = t.user_id WHERE r.id = ?",
      [id],
    );
    if (rows.isEmpty) throw StateError('专注记录不存在');
    return PomodoroRecord.fromMap(rows.single);
  }

  Future<PomodoroRecord?> restoreActiveRecord(int userId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tablePomodoroRecords,
      where: 'user_id = ? AND ended_at IS NULL AND completed = 0',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _readRecord(db, rows.single['id'] as int);
  }

  Future<PomodoroRecord> pauseRecord(int recordId) async {
    final db = await _database.database;
    final result = await db.transaction((txn) async {
      final record = await _readRecord(txn, recordId);
      if (!record.isRunning) return record;
      final now = _now();
      final elapsed = record.elapsedSecondsAt(now);
      final rows = await txn.query(
        AppDatabase.tablePomodoroRecords,
        where: 'id = ?',
        whereArgs: [recordId],
      );
      final segments = _segments(rows.single);
      final activeSeconds = elapsed - record.durationSeconds;
      if (activeSeconds > 0) {
        final start = record.resumedAt ?? record.startedAt;
        segments.add([
          start.toUtc().toIso8601String(),
          start.add(Duration(seconds: activeSeconds)).toUtc().toIso8601String(),
        ]);
      }
      await txn.update(
        AppDatabase.tablePomodoroRecords,
        {
          'timer_state': 'paused',
          'resumed_at': null,
          'duration_seconds': elapsed,
          'active_segments_json': jsonEncode(segments),
        },
        where: 'id = ? AND ended_at IS NULL AND completed = 0',
        whereArgs: [recordId],
      );
      await _setActiveTaskState(txn, record.taskId, record.userId, 'paused');
      return _readRecord(txn, recordId);
    });
    LearningEvents.notify();
    return result;
  }

  Future<PomodoroRecord> resumeRecord(int recordId) async {
    final db = await _database.database;
    final result = await db.transaction((txn) async {
      final record = await _readRecord(txn, recordId);
      if (record.completed ||
          record.endedAt != null ||
          record.timerState != 'paused') {
        return record;
      }
      await txn.update(
        AppDatabase.tablePomodoroRecords,
        {
          'timer_state': 'running',
          'resumed_at': _now().toUtc().toIso8601String(),
        },
        where:
            "id = ? AND ended_at IS NULL AND completed = 0 AND timer_state = 'paused'",
        whereArgs: [recordId],
      );
      await _setActiveTaskState(
        txn,
        record.taskId,
        record.userId,
        'in_progress',
      );
      return _readRecord(txn, recordId);
    });
    LearningEvents.notify();
    return result;
  }

  List<List<String>> _segments(Map<String, Object?> row) =>
      (jsonDecode((row['active_segments_json'] as String?) ?? '[]') as List)
          .map((value) => (value as List).cast<String>())
          .toList();

  /// durationSeconds is retained for callers; only persisted wall time is trusted.
  Future<void> completeRecord(int recordId, int durationSeconds) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final record = await _readRecord(txn, recordId);
      if (record.completed || record.endedAt != null) return;
      final now = _now();
      final elapsed = record.elapsedSecondsAt(now);
      final rows = await txn.query(
        AppDatabase.tablePomodoroRecords,
        where: 'id = ?',
        whereArgs: [recordId],
      );
      final segments = _segments(rows.single);
      if (record.isRunning && elapsed > record.durationSeconds) {
        final start = record.resumedAt ?? record.startedAt;
        segments.add([
          start.toUtc().toIso8601String(),
          start
              .add(Duration(seconds: elapsed - record.durationSeconds))
              .toUtc()
              .toIso8601String(),
        ]);
      }
      final changed = await txn.update(
        AppDatabase.tablePomodoroRecords,
        {
          'ended_at': now.toUtc().toIso8601String(),
          'duration_seconds': elapsed,
          'timer_state': 'finished',
          'resumed_at': null,
          'completed': 1,
          'active_segments_json': jsonEncode(segments),
        },
        where: 'id = ? AND ended_at IS NULL AND completed = 0',
        whereArgs: [recordId],
      );
      if (changed == 0) return;
      await txn.rawUpdate(
        'UPDATE pomodoro_tasks SET focused_seconds = COALESCE(focused_seconds, 0) + ? WHERE id = ? AND user_id = ?',
        [elapsed, record.taskId, record.userId],
      );
      if (elapsed <= 0) return;
      final perDay = <String, int>{};
      for (final segment in segments) {
        var start = DateTime.parse(segment[0]).toLocal();
        final end = DateTime.parse(segment[1]).toLocal();
        while (start.isBefore(end)) {
          final midnight = DateTime(start.year, start.month, start.day + 1);
          final until = midnight.isBefore(end) ? midnight : end;
          final key = _dateKey(start);
          perDay[key] = (perDay[key] ?? 0) + until.difference(start).inSeconds;
          start = until;
        }
      }
      // Legacy records can have accumulated time without an interval history.
      final assigned = perDay.values.fold(0, (a, b) => a + b);
      final finishDay = segments.isEmpty
          ? _dateKey(now)
          : _dateKey(
              DateTime.parse(
                segments.last[1],
              ).subtract(const Duration(microseconds: 1)).toLocal(),
            );
      if (assigned < elapsed) {
        perDay[finishDay] = (perDay[finishDay] ?? 0) + elapsed - assigned;
      }
      for (final entry in perDay.entries) {
        final old = await txn.query(
          AppDatabase.tableCheckinRecords,
          where: 'user_id = ? AND date = ?',
          whereArgs: [record.userId, entry.key],
        );
        final previousSeconds = old.isEmpty
            ? 0
            : old.single['study_seconds'] as int;
        final previousCount = old.isEmpty
            ? 0
            : old.single['pomodoro_count'] as int;
        final count = previousCount + (entry.key == finishDay ? 1 : 0);
        final seconds = previousSeconds + entry.value;
        final pointsDelta =
            _calculatePoints(seconds, count) -
            _calculatePoints(previousSeconds, previousCount);
        if (old.isEmpty) {
          await txn.insert(AppDatabase.tableCheckinRecords, {
            'user_id': record.userId,
            'date': entry.key,
            'study_seconds': seconds,
            'pomodoro_count': count,
            'points_earned': pointsDelta,
            'is_makeup': 0,
            'created_at': now.toUtc().toIso8601String(),
          });
        } else {
          await txn.update(
            AppDatabase.tableCheckinRecords,
            {
              'study_seconds': seconds,
              'pomodoro_count': count,
              'points_earned':
                  (old.single['points_earned'] as int) + pointsDelta,
            },
            where: 'id = ?',
            whereArgs: [old.single['id']],
          );
        }
      }
    });
    LearningEvents.notify();
  }

  Future<void> cancelRecord(int recordId) async {
    final db = await _database.database;
    await db.update(
      AppDatabase.tablePomodoroRecords,
      {
        'timer_state': 'cancelled',
        'resumed_at': null,
        'ended_at': _now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND ended_at IS NULL AND completed = 0',
      whereArgs: [recordId],
    );
    LearningEvents.notify();
  }

  Future<List<PomodoroRecord>> fetchRecords({
    required int userId,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    final db = await _database.database;
    final conditions = <String>['r.user_id = ?'];
    final args = <dynamic>[userId];

    if (fromDate != null) {
      conditions.add('COALESCE(r.ended_at, r.started_at) >= ?');
      args.add(fromDate.toUtc().toIso8601String());
    }
    if (toDate != null) {
      conditions.add('r.started_at <= ?');
      args.add(toDate.toUtc().toIso8601String());
    }

    final rows = await db.rawQuery('''
      SELECT r.*, COALESCE(t.title, '已删除的任务') as task_title
      FROM ${AppDatabase.tablePomodoroRecords} r
      LEFT JOIN ${AppDatabase.tablePomodoroTasks} t ON r.task_id = t.id
      WHERE ${conditions.join(' AND ')}
      ORDER BY r.started_at DESC
      ''', args);
    return rows.map(PomodoroRecord.fromMap).toList();
  }

  // ========== 打卡 ==========

  Future<CheckinRecord?> checkInToday(int userId) async {
    final db = await _database.database;
    final today = _now();
    final dateKey = _dateKey(today);
    final now = _now().toUtc().toIso8601String();

    final result = await db.transaction((txn) async {
      final existing = await txn.query(
        AppDatabase.tableCheckinRecords,
        where: 'user_id = ? AND date = ?',
        whereArgs: [userId, dateKey],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        return (CheckinRecord.fromMap(existing.first), false);
      }

      final id = await txn.insert(AppDatabase.tableCheckinRecords, {
        'user_id': userId,
        'date': dateKey,
        'study_seconds': 0,
        'pomodoro_count': 0,
        'points_earned': 0,
        'is_makeup': 0,
        'created_at': now,
      });

      return (
        CheckinRecord(id: id, userId: userId, date: today, createdAt: _now()),
        true,
      );
    });
    if (result.$2) LearningEvents.notify();
    return result.$1;
  }

  Future<void> updateCheckinStudyTime(
    int userId,
    int seconds,
    int pomodoroCount,
  ) async {
    final db = await _database.database;
    final dateKey = _dateKey(_now());
    final points = _calculatePoints(seconds, pomodoroCount);

    await db.update(
      AppDatabase.tableCheckinRecords,
      {
        'study_seconds': seconds,
        'pomodoro_count': pomodoroCount,
        'points_earned': points,
        'is_makeup': 0,
      },
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, dateKey],
    );
    LearningEvents.notify();
  }

  Future<CheckinRecord?> getTodayCheckin(int userId) async {
    final db = await _database.database;
    final dateKey = _dateKey(_now());
    final rows = await db.query(
      AppDatabase.tableCheckinRecords,
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, dateKey],
      limit: 1,
    );
    return rows.isEmpty ? null : CheckinRecord.fromMap(rows.first);
  }

  Future<List<CheckinRecord>> fetchCheckins({
    required int userId,
    required int year,
    required int month,
  }) async {
    final db = await _database.database;
    final prefix = '$year-${month.toString().padLeft(2, '0')}';
    final rows = await db.query(
      AppDatabase.tableCheckinRecords,
      where: 'user_id = ? AND date LIKE ?',
      whereArgs: [userId, '$prefix%'],
      orderBy: 'date ASC',
    );
    return rows.map(CheckinRecord.fromMap).toList();
  }

  Future<bool> makeupCheckin(int userId, DateTime date) async {
    final db = await _database.database;
    final dateKey = _dateKey(date);
    final now = _now().toUtc().toIso8601String();

    // 检查日期是否有效（只能补签过去30天内的）
    final daysAgo = _now().difference(date).inDays;
    if (daysAgo < 1 || daysAgo > 30) return false;

    final success = await db.transaction((txn) async {
      final existing = await txn.query(
        AppDatabase.tableCheckinRecords,
        where: 'user_id = ? AND date = ?',
        whereArgs: [userId, dateKey],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;

      // 检查积分是否足够
      final points = await txn.rawQuery(
        'SELECT COALESCE(SUM(points_earned), 0) AS total FROM checkin_records WHERE user_id = ?',
        [userId],
      );
      final totalPoints = points.single['total'] as int;
      if (totalPoints < FocusPoints.makeupCost) return false;

      // 扣除积分并创建补签记录
      await txn.insert(AppDatabase.tableCheckinRecords, {
        'user_id': userId,
        'date': dateKey,
        'study_seconds': 0,
        'pomodoro_count': 0,
        'points_earned': -FocusPoints.makeupCost,
        'is_makeup': 1,
        'created_at': now,
      });

      return true;
    });
    if (success) LearningEvents.notify();
    return success;
  }

  // ========== 统计 ==========

  Future<FocusStats> fetchStats(int userId) async {
    final db = await _database.database;
    final today = _now();
    final todayKey = _dateKey(today);

    // 今日数据
    final todayResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(study_seconds), 0) as seconds,
             COALESCE(SUM(pomodoro_count), 0) as pomodoros
      FROM ${AppDatabase.tableCheckinRecords}
      WHERE user_id = ? AND date = ?
      ''',
      [userId, todayKey],
    );
    final todaySeconds = (todayResult.first['seconds'] as int?) ?? 0;
    final todayPomodoros = (todayResult.first['pomodoros'] as int?) ?? 0;
    final todayCheckin = await db.query(
      AppDatabase.tableCheckinRecords,
      columns: ['id'],
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, todayKey],
      limit: 1,
    );
    final isCheckedInToday = todayCheckin.isNotEmpty;

    // 本周
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(study_seconds), 0) as seconds
      FROM ${AppDatabase.tableCheckinRecords}
      WHERE user_id = ? AND date >= ? AND date <= ?
      ''',
      [userId, _dateKey(weekStart), todayKey],
    );
    final weekSeconds = (weekResult.first['seconds'] as int?) ?? 0;

    // 本月
    final monthResult = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(study_seconds), 0) as seconds
      FROM ${AppDatabase.tableCheckinRecords}
      WHERE user_id = ? AND date LIKE ?
      ''',
      [userId, '${today.year}-${today.month.toString().padLeft(2, '0')}%'],
    );
    final monthSeconds = (monthResult.first['seconds'] as int?) ?? 0;

    // 总积分
    final totalPoints = await _getTotalPoints(userId);

    // 连续打卡天数
    final streak = await _calculateStreak(userId);

    return FocusStats(
      todaySeconds: todaySeconds,
      todayPomodoros: todayPomodoros,
      weekSeconds: weekSeconds,
      monthSeconds: monthSeconds,
      totalPoints: totalPoints,
      currentStreak: streak.current,
      longestStreak: streak.longest,
      isCheckedInToday: isCheckedInToday,
    );
  }

  /// Learning streak excludes a manual check-in with no recorded study.
  Future<int> fetchLearningStreak(int userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT date AS day FROM checkin_records WHERE user_id=? AND study_seconds>0
      UNION SELECT DATE(created_at, 'localtime') AS day FROM practice_submissions WHERE user_id=?
    ''', [userId, userId]);
    final days = rows.map((row) => row['day'] as String?).whereType<String>().toSet();
    final now = _now();
    var day = DateTime(now.year, now.month, now.day);
    if (!days.contains(_dateKey(day))) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var streak = 0;
    while (days.contains(_dateKey(day))) {
      streak++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return streak;
  }

  Future<List<TaskTimeStat>> fetchTaskTimeStats({
    required int userId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final records = await fetchRecords(userId: userId, fromDate: fromDate, toDate: toDate);
    final totals = <int, int>{};
    final titles = <int, String>{};
    for (final record in records.where((r) => r.completed)) {
      final seconds = record.secondsInRange(fromDate, toDate);
      if (seconds <= 0) continue;
      totals[record.taskId] = (totals[record.taskId] ?? 0) + seconds;
      titles[record.taskId] = record.taskTitle;
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.asMap().entries.map((entry) => TaskTimeStat(
      taskId: entry.value.key,
      taskTitle: titles[entry.value.key]!,
      totalSeconds: entry.value.value,
      colorIndex: entry.key,
    )).toList();
  }

  // ========== 私有方法 ==========

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int _calculatePoints(int seconds, int pomodoroCount) {
    final minutes = seconds ~/ 60;
    return minutes * FocusPoints.pointsPerMinute +
        pomodoroCount * FocusPoints.pomodoroBonus;
  }

  Future<int> _getTotalPoints(int userId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(points_earned), 0) as total FROM ${AppDatabase.tableCheckinRecords} WHERE user_id = ?',
      [userId],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  Future<_StreakResult> _calculateStreak(int userId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT date FROM ${AppDatabase.tableCheckinRecords}
      WHERE user_id = ?
      ORDER BY date DESC
      ''',
      [userId],
    );

    if (rows.isEmpty) return const _StreakResult(current: 0, longest: 0);

    final dates =
        rows
            .map((r) {
              final parts = ((r['date'] as String?) ?? '').split('-');
              if (parts.length != 3) return null;
              return DateTime(
                int.parse(parts[0]),
                int.parse(parts[1]),
                int.parse(parts[2]),
              );
            })
            .whereType<DateTime>()
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) return const _StreakResult(current: 0, longest: 0);

    // 计算当前连续
    int current = 0;
    final today = _now();
    final todayDate = DateTime(today.year, today.month, today.day);
    DateTime expected = todayDate;

    for (final date in dates) {
      final checkDate = DateTime(date.year, date.month, date.day);
      if (checkDate == expected) {
        current++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (checkDate.isBefore(expected)) {
        break;
      }
    }

    // 计算最长连续
    int longest = 0;
    int temp = 0;
    DateTime? prev;

    for (final date in dates.reversed) {
      final checkDate = DateTime(date.year, date.month, date.day);
      if (prev == null) {
        temp = 1;
      } else if (checkDate.difference(prev).inDays == 1) {
        temp++;
      } else {
        longest = temp > longest ? temp : longest;
        temp = 1;
      }
      prev = checkDate;
    }
    longest = temp > longest ? temp : longest;

    return _StreakResult(current: current, longest: longest);
  }

  Future<int> getTotalPoints(int userId) => _getTotalPoints(userId);
}

class _StreakResult {
  const _StreakResult({required this.current, required this.longest});
  final int current;
  final int longest;
}
