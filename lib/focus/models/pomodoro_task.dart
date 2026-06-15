// ========== 番茄任务模型 ==========

class PomodoroTask {
  const PomodoroTask({
    required this.id,
    required this.userId,
    required this.title,
    this.estimatedPomodoros = 1,
    this.sortOrder = 0,
    this.isArchived = false,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String title;
  final int estimatedPomodoros;
  final int sortOrder;
  final bool isArchived;
  final DateTime createdAt;

  PomodoroTask copyWith({
    int? id,
    int? userId,
    String? title,
    int? estimatedPomodoros,
    int? sortOrder,
    bool? isArchived,
    DateTime? createdAt,
  }) {
    return PomodoroTask(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      estimatedPomodoros: estimatedPomodoros ?? this.estimatedPomodoros,
      sortOrder: sortOrder ?? this.sortOrder,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'user_id': userId,
      'title': title,
      'estimated_pomodoros': estimatedPomodoros,
      'sort_order': sortOrder,
      'is_archived': isArchived ? 1 : 0,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  factory PomodoroTask.fromMap(Map<String, Object?> map) {
    return PomodoroTask(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      title: (map['title'] as String?) ?? '',
      estimatedPomodoros: (map['estimated_pomodoros'] as int?) ?? 1,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isArchived: (map['is_archived'] as int?) == 1,
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '')
              ?.toLocal() ??
          DateTime.now(),
    );
  }
}
