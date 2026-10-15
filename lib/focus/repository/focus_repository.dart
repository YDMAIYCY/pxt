import 'dart:convert';

import '../../database/app_database.dart';
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
  FocusRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> ensureInitialized() async {
    await _database.database;
  }

  // ========== 番茄任务 CRUD ==========

  Future<PomodoroTask> createTask({
    required int userId,
    required String title,
    int estimatedPomodoros = 1,
    String? operationKey,
  }) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    final id = await db.transaction((txn) async {
      if(operationKey!=null) {
        final receipts=await txn.query('agent_operation_receipts',where:'operation_key=? AND user_id=?',whereArgs:[operationKey,userId]);
        if(receipts.isNotEmpty) return (jsonDecode(receipts.single['result_json'] as String) as Map)['taskId'] as int;
      }
    final maxOrder = await txn.rawQuery(
      'SELECT COALESCE(MAX(sort_order), -1) as max_order FROM ${AppDatabase.tablePomodoroTasks} WHERE user_id = ? AND is_archived = 0',
      [userId],
    );
    final sortOrder = ((maxOrder.first['max_order'] as int?) ?? -1) + 1;

    final taskId = await txn.insert(AppDatabase.tablePomodoroTasks, {
      'user_id': userId,
      'title': title.trim(),
      'estimated_pomodoros': estimatedPomodoros,
      'sort_order': sortOrder,
      'is_archived': 0,
      'created_at': now,
    });

      if(operationKey!=null) await txn.insert('agent_operation_receipts',{'operation_key':operationKey,'user_id':userId,'result_json':jsonEncode({'taskId':taskId})});
      return taskId;
    });
    return PomodoroTask.fromMap((await db.query(AppDatabase.tablePomodoroTasks,
      where:'id=? AND user_id=?',whereArgs:[id,userId])).single);
  }

  Future<List<PomodoroTask>> fetchTasks(int userId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tablePomodoroTasks,
      where: 'user_id = ? AND is_archived = 0',
      whereArgs: [userId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(PomodoroTask.fromMap).toList();
  }

  Future<void> updateTask(PomodoroTask task) async {
    final db = await _database.database;
    await db.update(
      AppDatabase.tablePomodoroTasks,
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> deleteTask(int taskId) async {
    final db = await _database.database;
    await db.delete(
      AppDatabase.tablePomodoroTasks,
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<void> archiveTask(int taskId) async {
    final db = await _database.database;
    await db.update(
      AppDatabase.tablePomodoroTasks,
      {'is_archived': 1},
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  // ========== 计时记录 ==========

  Future<PomodoroRecord> startRecord({
    required int userId,
    required int taskId,
    required String pomodoroMode,
  }) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();

    // 获取任务标题
    final tasks = await db.query(
      AppDatabase.tablePomodoroTasks,
      columns: ['title'],
      where: 'id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    final taskTitle = tasks.isNotEmpty ? (tasks.first['title'] as String?) ?? '' : '';

    final id = await db.insert(AppDatabase.tablePomodoroRecords, {
      'user_id': userId,
      'task_id': taskId,
      'started_at': now,
      'duration_seconds': 0,
      'completed': 0,
      'pomodoro_mode': pomodoroMode,
    });

    return PomodoroRecord(
      id: id,
      userId: userId,
      taskId: taskId,
      startedAt: DateTime.now(),
      pomodoroMode: pomodoroMode,
      taskTitle: taskTitle,
    );
  }

  Future<void> completeRecord(int recordId, int durationSeconds) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      AppDatabase.tablePomodoroRecords,
      {
        'ended_at': now,
        'duration_seconds': durationSeconds,
        'completed': 1,
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> cancelRecord(int recordId) async {
    final db = await _database.database;
    await db.delete(
      AppDatabase.tablePomodoroRecords,
      where: 'id = ?',
      whereArgs: [recordId],
    );
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
      conditions.add('r.started_at >= ?');
      args.add(fromDate.toUtc().toIso8601String());
    }
    if (toDate != null) {
      conditions.add('r.started_at <= ?');
      args.add(toDate.toUtc().toIso8601String());
    }

    final rows = await db.rawQuery(
      '''
      SELECT r.*, COALESCE(t.title, '已删除的任务') as task_title
      FROM ${AppDatabase.tablePomodoroRecords} r
      LEFT JOIN ${AppDatabase.tablePomodoroTasks} t ON r.task_id = t.id
      WHERE ${conditions.join(' AND ')}
      ORDER BY r.started_at DESC
      ''',
      args,
    );
    return rows.map(PomodoroRecord.fromMap).toList();
  }

  // ========== 打卡 ==========

  Future<CheckinRecord?> checkInToday(int userId) async {
    final db = await _database.database;
    final today = DateTime.now();
    final dateKey = _dateKey(today);
    final now = DateTime.now().toUtc().toIso8601String();

    // 检查今天是否已打卡
    final existing = await db.query(
      AppDatabase.tableCheckinRecords,
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, dateKey],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return CheckinRecord.fromMap(existing.first);
    }

    final id = await db.insert(AppDatabase.tableCheckinRecords, {
      'user_id': userId,
      'date': dateKey,
      'study_seconds': 0,
      'pomodoro_count': 0,
      'points_earned': 0,
      'is_makeup': 0,
      'created_at': now,
    });

    return CheckinRecord(
      id: id,
      userId: userId,
      date: today,
      createdAt: DateTime.now(),
    );
  }

  Future<void> updateCheckinStudyTime(int userId, int seconds, int pomodoroCount) async {
    final db = await _database.database;
    final dateKey = _dateKey(DateTime.now());
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
  }

  Future<CheckinRecord?> getTodayCheckin(int userId) async {
    final db = await _database.database;
    final dateKey = _dateKey(DateTime.now());
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
    final now = DateTime.now().toUtc().toIso8601String();

    // 检查日期是否有效（只能补签过去30天内的）
    final daysAgo = DateTime.now().difference(date).inDays;
    if (daysAgo < 1 || daysAgo > 30) return false;

    // 检查是否已打卡
    final existing = await db.query(
      AppDatabase.tableCheckinRecords,
      where: 'user_id = ? AND date = ?',
      whereArgs: [userId, dateKey],
      limit: 1,
    );
    if (existing.isNotEmpty) return false;

    // 检查积分是否足够
    final totalPoints = await _getTotalPoints(userId);
    if (totalPoints < FocusPoints.makeupCost) return false;

    // 扣除积分并创建补签记录
    await db.insert(AppDatabase.tableCheckinRecords, {
      'user_id': userId,
      'date': dateKey,
      'study_seconds': 0,
      'pomodoro_count': 0,
      'points_earned': -FocusPoints.makeupCost,
      'is_makeup': 1,
      'created_at': now,
    });

    return true;
  }

  // ========== 统计 ==========

  Future<FocusStats> fetchStats(int userId) async {
    final db = await _database.database;
    final today = DateTime.now();
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
    final isCheckedInToday = todaySeconds > 0 || todayPomodoros > 0;

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

  Future<List<TaskTimeStat>> fetchTaskTimeStats({
    required int userId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT r.task_id,
             COALESCE(t.title, '已删除的任务') as task_title,
             COALESCE(SUM(r.duration_seconds), 0) as total_seconds
      FROM ${AppDatabase.tablePomodoroRecords} r
      LEFT JOIN ${AppDatabase.tablePomodoroTasks} t ON r.task_id = t.id
      WHERE r.user_id = ?
        AND r.started_at >= ?
        AND r.started_at <= ?
        AND r.completed = 1
      GROUP BY r.task_id
      ORDER BY total_seconds DESC
      ''',
      [userId, fromDate.toUtc().toIso8601String(), toDate.toUtc().toIso8601String()],
    );
    return rows.asMap().entries.map((entry) {
      final row = entry.value;
      return TaskTimeStat(
        taskId: (row['task_id'] as int?) ?? 0,
        taskTitle: (row['task_title'] as String?) ?? '',
        totalSeconds: (row['total_seconds'] as int?) ?? 0,
        colorIndex: entry.key,
      );
    }).toList();
  }

  // ========== 私有方法 ==========

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  int _calculatePoints(int seconds, int pomodoroCount) {
    final minutes = seconds ~/ 60;
    return minutes * FocusPoints.pointsPerMinute + pomodoroCount * FocusPoints.pomodoroBonus;
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

    final dates = rows
        .map((r) {
          final parts = ((r['date'] as String?) ?? '').split('-');
          if (parts.length != 3) return null;
          return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        })
        .whereType<DateTime>()
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (dates.isEmpty) return const _StreakResult(current: 0, longest: 0);

    // 计算当前连续
    int current = 0;
    final today = DateTime.now();
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
