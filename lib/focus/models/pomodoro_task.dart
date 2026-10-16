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
    this.kind = 'personal',
    this.status = 'pending',
    this.sourceKey,
    this.documentId,
    this.conceptId,
    this.questionId,
    this.dueAt,
    this.completedAt,
    this.focusedSeconds = 0,
    this.documentTitle,
    this.libraryName,
  });

  final int id;
  final int userId;
  final String title;
  final int estimatedPomodoros;
  final int sortOrder;
  final bool isArchived;
  final DateTime createdAt;
  final String kind;
  final String status;
  final String? sourceKey;
  final int? documentId;
  final int? conceptId;
  final int? questionId;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final int focusedSeconds;
  final String? documentTitle;
  final String? libraryName;

  bool get isActive =>
      !isArchived &&
      const ['pending', 'in_progress', 'paused'].contains(status);

  PomodoroTask copyWith({
    int? id,
    int? userId,
    String? title,
    int? estimatedPomodoros,
    int? sortOrder,
    bool? isArchived,
    DateTime? createdAt,
    String? kind,
    String? status,
    String? sourceKey,
    int? documentId,
    int? conceptId,
    int? questionId,
    DateTime? dueAt,
    DateTime? completedAt,
    int? focusedSeconds,
    String? documentTitle,
    String? libraryName,
  }) {
    return PomodoroTask(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      estimatedPomodoros: estimatedPomodoros ?? this.estimatedPomodoros,
      sortOrder: sortOrder ?? this.sortOrder,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      sourceKey: sourceKey ?? this.sourceKey,
      documentId: documentId ?? this.documentId,
      conceptId: conceptId ?? this.conceptId,
      questionId: questionId ?? this.questionId,
      dueAt: dueAt ?? this.dueAt,
      completedAt: completedAt ?? this.completedAt,
      focusedSeconds: focusedSeconds ?? this.focusedSeconds,
      documentTitle: documentTitle ?? this.documentTitle,
      libraryName: libraryName ?? this.libraryName,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'user_id': userId,
      'kind': kind,
      'status': status,
      'source_key': sourceKey,
      'document_id': documentId,
      'concept_id': conceptId,
      'question_id': questionId,
      'due_at': dueAt?.toUtc().toIso8601String(),
      'completed_at': completedAt?.toUtc().toIso8601String(),
      'focused_seconds': focusedSeconds,

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
      kind: map['kind'] as String? ?? 'personal',
      status: map['status'] as String? ?? 'pending',
      sourceKey: map['source_key'] as String?,
      documentId: map['document_id'] as int?,
      conceptId: map['concept_id'] as int?,
      questionId: map['question_id'] as int?,
      dueAt: DateTime.tryParse((map['due_at'] as String?) ?? '')?.toLocal(),
      completedAt: DateTime.tryParse(
        (map['completed_at'] as String?) ?? '',
      )?.toLocal(),
      focusedSeconds: map['focused_seconds'] as int? ?? 0,
      documentTitle: map['document_title'] as String?,
      libraryName: map['library_name'] as String?,

      userId: map['user_id'] as int,
      title: (map['title'] as String?) ?? '',
      estimatedPomodoros: (map['estimated_pomodoros'] as int?) ?? 1,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      isArchived: (map['is_archived'] as int?) == 1,
      createdAt:
          DateTime.tryParse((map['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
