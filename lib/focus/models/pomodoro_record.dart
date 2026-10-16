import 'dart:convert';

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
    this.pomodoroMode = '正向',
    this.taskTitle = '',
    this.timerState = 'running',
    this.resumedAt,
    this.targetSeconds = 0,
    this.activeSegments = const [],
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
  final String timerState;
  final DateTime? resumedAt;
  final int targetSeconds;
  final List<List<DateTime>> activeSegments;

  /// Only active interval overlap counts toward a selected calendar period.
  int secondsInRange(DateTime from, DateTime to) {
    final segments = activeSegments.isEmpty
        ? [[startedAt, startedAt.add(Duration(seconds: durationSeconds))]]
        : activeSegments;
    var seconds = 0;
    for (final segment in segments) {
      final start = segment[0].isAfter(from) ? segment[0] : from;
      final end = segment[1].isBefore(to) ? segment[1] : to;
      if (end.isAfter(start)) seconds += end.difference(start).inSeconds;
    }
    return seconds;
  }

  bool get isRunning =>
      !completed && endedAt == null && timerState == 'running';

  /// The persisted duration excludes the active interval beginning at resumedAt.
  int elapsedSecondsAt(DateTime now) {
    final anchor = resumedAt ?? startedAt;
    final delta = isRunning ? now.difference(anchor).inSeconds : 0;
    final seconds = durationSeconds + (delta > 0 ? delta : 0);
    return targetSeconds > 0 && seconds > targetSeconds
        ? targetSeconds
        : seconds;
  }

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
      case '正向':
        return '正向';
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
      'timer_state': timerState,
      'resumed_at': resumedAt?.toUtc().toIso8601String(),
      'target_seconds': targetSeconds,
      'active_segments_json': jsonEncode(activeSegments.map((segment) =>
          segment.map((date) => date.toUtc().toIso8601String()).toList()).toList()),
    };
  }

  factory PomodoroRecord.fromMap(Map<String, Object?> map) {
    return PomodoroRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      taskId: map['task_id'] as int,
      startedAt:
          DateTime.tryParse((map['started_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)?.toLocal()
          : null,
      durationSeconds: (map['duration_seconds'] as int?) ?? 0,
      completed: (map['completed'] as int?) == 1,
      pomodoroMode: (map['pomodoro_mode'] as String?) ?? '正向',
      taskTitle: (map['task_title'] as String?) ?? '',
      timerState: (map['timer_state'] as String?) ?? 'running',
      resumedAt: DateTime.tryParse(
        (map['resumed_at'] as String?) ?? '',
      )?.toLocal(),
      targetSeconds: (map['target_seconds'] as int?) ?? 0,
      activeSegments: (jsonDecode(map['active_segments_json'] as String? ?? '[]') as List)
          .map((segment) => (segment as List).map((date) => DateTime.parse(date as String).toLocal()).toList()).toList(),
    );
  }
}
