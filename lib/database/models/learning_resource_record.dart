class LearningResourceType {
  static const labels = {
    'knowledge_cards': '知识卡片',
    'review_outline': '复习提纲',
    'mindmap_text': '思维导图',
    'practice_questions': '练习题',
    'notes': '分层学习笔记',
    'knowledge_tree': '知识树',
    'interview_bank': 'AI 面试题库',
    'flashcards': '记忆闪卡',
    'deep_explanation': '深度讲解与举一反三',
    'application_questions': '概念辨析与应用题',
    'annotation': '我的补充与批注',
  };
}

class LearningResourceRecord {
  const LearningResourceRecord({
    required this.id,
    required this.documentId,
    required this.type,
    required this.title,
    required this.content,
    required this.version,
    required this.fingerprint,
    required this.model,
  });
  final int id;
  final int documentId;
  final String type;
  final String title;
  final String content;
  final int version;
  final String fingerprint;
  final String model;

  factory LearningResourceRecord.fromMap(Map<String, Object?> row) =>
      LearningResourceRecord(
        id: row['id'] as int,
        documentId: row['document_id'] as int,
        type: row['type'] as String,
        title: row['title'] as String,
        content: row['content'] as String,
        version: row['version'] as int,
        fingerprint: row['input_fingerprint'] as String,
        model: row['model'] as String,
      );
}

class LearningErrorRecord {
  const LearningErrorRecord({
    required this.id,
    required this.documentId,
    required this.origin,
    required this.prompt,
    required this.answer,
    required this.correction,
    required this.resolved,
    this.conceptId,
    this.questionId,
  });
  final int id;
  final int documentId;
  final int? conceptId;
  final int? questionId;
  final String origin;
  final String prompt;
  final String answer;
  final String correction;
  final bool resolved;

  factory LearningErrorRecord.fromMap(Map<String, Object?> row) =>
      LearningErrorRecord(
        id: row['id'] as int,
        documentId: row['document_id'] as int,
        conceptId: row['concept_id'] as int?,
        questionId: row['question_id'] as int?,
        origin: row['origin'] as String,
        prompt: row['prompt'] as String,
        answer: row['answer'] as String,
        correction: row['correction'] as String,
        resolved: row['resolved'] == 1,
      );
}
