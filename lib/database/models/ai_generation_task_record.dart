class AiTaskType {
  const AiTaskType._();

  static const String knowledgeCards = 'knowledge_cards';
  static const String reviewOutline = 'review_outline';
  static const String mindmapText = 'mindmap_text';
  static const String practiceQuestions = 'practice_questions';

  static const List<String> all = [
    knowledgeCards,
    reviewOutline,
    mindmapText,
    practiceQuestions,
  ];

  static String labelOf(String taskType) {
    switch (taskType) {
      case knowledgeCards:
        return '知识卡片';
      case reviewOutline:
        return '复习提纲';
      case mindmapText:
        return '思维导图文字版';
      case practiceQuestions:
        return '复习题';
      default:
        return taskType;
    }
  }
}

class AiTaskStatus {
  const AiTaskStatus._();

  static const String pending = 'pending';
  static const String running = 'running';
  static const String completed = 'completed';
  static const String failed = 'failed';
}

class AiGenerationTaskRecord {
  const AiGenerationTaskRecord({
    required this.id,
    required this.documentId,
    required this.taskType,
    required this.inputText,
    required this.status,
    required this.provider,
    required this.createdAt,
    required this.updatedAt,
    this.promptTemplate,
    this.resultText,
    this.errorMessage,
    this.completedAt,
  });

  final int id;
  final int documentId;
  final String taskType;
  final String inputText;
  final String? promptTemplate;
  final String status;
  final String provider;
  final String? resultText;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  factory AiGenerationTaskRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final updatedAt = (map['updated_at'] as String?) ?? '';
    final completedAt = (map['completed_at'] as String?) ?? '';

    return AiGenerationTaskRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      taskType: (map['task_type'] as String?)?.trim() ?? '',
      inputText: (map['input_text'] as String?)?.trim() ?? '',
      promptTemplate: (map['prompt_template'] as String?)?.trim(),
      status: (map['status'] as String?)?.trim() ?? AiTaskStatus.pending,
      provider: (map['provider'] as String?)?.trim() ?? 'unknown',
      resultText: (map['result_text'] as String?)?.trim(),
      errorMessage: (map['error_message'] as String?)?.trim(),
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
      completedAt: completedAt.isEmpty
          ? null
          : DateTime.tryParse(completedAt)?.toLocal(),
    );
  }

  String get taskLabel => AiTaskType.labelOf(taskType);
}
