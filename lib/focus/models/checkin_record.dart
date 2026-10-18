// ========== 打卡记录模型 ==========

class CheckinRecord {
  const CheckinRecord({
    required this.id,
    required this.userId,
    required this.date,
    this.studySeconds = 0,
    this.pomodoroCount = 0,
    this.pointsEarned = 0,
    this.isMakeup = false,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final DateTime date;
  final int studySeconds;
  final int pomodoroCount;
  final int pointsEarned;
  final bool isMakeup;
  final DateTime createdAt;

  String get dateKey => _dateKey(date);

  String get weekdayLabel {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return '周${weekdays[date.weekday - 1]}';
  }

  Duration get studyDuration => Duration(seconds: studySeconds);

  String get studyLabel {
    final h = studyDuration.inHours;
    final m = studyDuration.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '$m分钟';
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Map<String, Object?> toMap() {
    return {
      'user_id': userId,
      'date': dateKey,
      'study_seconds': studySeconds,
      'pomodoro_count': pomodoroCount,
      'points_earned': pointsEarned,
      'is_makeup': isMakeup ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory CheckinRecord.fromMap(Map<String, Object?> map) {
    final dateStr = (map['date'] as String?) ?? '';
    DateTime date;
    try {
      final parts = dateStr.split('-');
      date = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    } catch (_) {
      date = DateTime.now();
    }

    return CheckinRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      date: date,
      studySeconds: (map['study_seconds'] as int?) ?? 0,
      pomodoroCount: (map['pomodoro_count'] as int?) ?? 0,
      pointsEarned: (map['points_earned'] as int?) ?? 0,
      isMakeup: (map['is_makeup'] as int?) == 1,
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}
