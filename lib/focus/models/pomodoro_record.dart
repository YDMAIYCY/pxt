// ========== 番茄计时记录模型 ==========

class PomodoroRecord {
  const PomodoroRecord({
    required this.id,
    required this.userId,
    required this.taskId,
    required this.startedAt,
    this.endedAt,
    this.durationSeconds = 0,
    this.completed = false,
    this.pomodoroMode = '25/5',
    this.taskTitle = '',
  });

  final int id;
  final int userId;
  final int taskId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final bool completed;
  final String pomodoroMode;
  final String taskTitle;

  Duration get duration => Duration(seconds: durationSeconds);

  String get durationLabel {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '$m分钟';
  }

  String get modeLabel {
    switch (pomodoroMode) {
      case '25/5':
        return '25+5';
      case '45/15':
        return '45+15';
      case '50/10':
        return '50+10';
      default:
        return pomodoroMode;
    }
  }

  Map<String, Object?> toMap() {
    return {
      'user_id': userId,
      'task_id': taskId,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'duration_seconds': durationSeconds,
      'completed': completed ? 1 : 0,
      'pomodoro_mode': pomodoroMode,
    };
  }

  factory PomodoroRecord.fromMap(Map<String, Object?> map) {
    return PomodoroRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      taskId: map['task_id'] as int,
      startedAt: DateTime.tryParse((map['started_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)?.toLocal()
          : null,
      durationSeconds: (map['duration_seconds'] as int?) ?? 0,
      completed: (map['completed'] as int?) == 1,
      pomodoroMode: (map['pomodoro_mode'] as String?) ?? '25/5',
      taskTitle: (map['task_title'] as String?) ?? '',
    );
  }
}
