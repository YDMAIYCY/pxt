import 'dart:convert';

class KnowledgeCardRecord {
  const KnowledgeCardRecord({
    required this.id,
    required this.documentId,
    required this.title,
    required this.content,
    required this.createdAt,
  });

  final int id;
  final int documentId;
  final String title;
  final String content;
  final DateTime createdAt;

  factory KnowledgeCardRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';

    return KnowledgeCardRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      title: (map['title'] as String?)?.trim() ?? '',
      content: (map['content'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
    );
  }
}

class ReviewOutlineRecord {
  const ReviewOutlineRecord({
    required this.id,
    required this.documentId,
    required this.title,
    required this.outlineText,
    required this.createdAt,
  });

  final int id;
  final int documentId;
  final String title;
  final String outlineText;
  final DateTime createdAt;

  factory ReviewOutlineRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';

    return ReviewOutlineRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      title: (map['title'] as String?)?.trim() ?? '',
      outlineText: (map['outline_text'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
    );
  }
}

class MindmapTextRecord {
  const MindmapTextRecord({
    required this.id,
    required this.documentId,
    required this.mindmapText,
    required this.createdAt,
  });

  final int id;
  final int documentId;
  final String mindmapText;
  final DateTime createdAt;

  factory MindmapTextRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';

    return MindmapTextRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      mindmapText: (map['mindmap_text'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
    );
  }
}

class PracticeQuestionRecord {
  const PracticeQuestionRecord({
    required this.id,
    required this.documentId,
    required this.questionText,
    required this.answerText,
    required this.analysisText,
    required this.difficulty,
    required this.reviewStatus,
    required this.wrongCount,
    required this.createdAt,
    this.lastUserAnswer,
    this.lastReviewedAt,
    this.nextReviewAt,
    this.masteryScore = 0,
    this.reviewIntervalDays = 0,
    this.correctStreak = 0,
    this.parentQuestionId,
    this.questionKind = PracticeQuestionKind.normal,
  });

  final int id;
  final int documentId;
  final String questionText;
  final String? answerText;
  final String? analysisText;
  final String? difficulty;
  final String reviewStatus;
  final String? lastUserAnswer;
  final DateTime? lastReviewedAt;
  final DateTime? nextReviewAt;
  final int wrongCount;
  final int masteryScore;
  final int reviewIntervalDays;
  final int correctStreak;
  final int? parentQuestionId;
  final String questionKind;
  final DateTime createdAt;

  bool get isPending => reviewStatus == PracticeQuestionReviewStatus.pending;

  bool get isWrong => reviewStatus == PracticeQuestionReviewStatus.wrong;

  bool get isMastered => reviewStatus == PracticeQuestionReviewStatus.mastered;

  bool get isSimilarQuestion => questionKind == PracticeQuestionKind.similar;

  factory PracticeQuestionRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final reviewedAt = (map['last_reviewed_at'] as String?) ?? '';
    final nextReviewAt = (map['next_review_at'] as String?) ?? '';

    return PracticeQuestionRecord(
      id: map['id'] as int,
      documentId: map['document_id'] as int,
      questionText: (map['question_text'] as String?)?.trim() ?? '',
      answerText: (map['answer_text'] as String?)?.trim(),
      analysisText: (map['analysis_text'] as String?)?.trim(),
      difficulty: (map['difficulty'] as String?)?.trim(),
      reviewStatus: PracticeQuestionReviewStatus.normalize(
        map['review_status'] as String?,
      ),
      lastUserAnswer: (map['last_user_answer'] as String?)?.trim(),
      lastReviewedAt: reviewedAt.isEmpty
          ? null
          : DateTime.tryParse(reviewedAt)?.toLocal(),
      nextReviewAt: nextReviewAt.isEmpty
          ? null
          : DateTime.tryParse(nextReviewAt)?.toLocal(),
      wrongCount: _readInt(map['wrong_count']),
      masteryScore: _readInt(map['mastery_score']),
      reviewIntervalDays: _readInt(map['review_interval_days']),
      correctStreak: _readInt(map['correct_streak']),
      parentQuestionId: _readNullableInt(map['parent_question_id']),
      questionKind: PracticeQuestionKind.normalize(
        map['question_kind'] as String?,
      ),
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
    );
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _readNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}

class PracticeQuestionReviewStatus {
  const PracticeQuestionReviewStatus._();

  static const String pending = 'pending';
  static const String wrong = 'wrong';
  static const String mastered = 'mastered';

  static String normalize(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case wrong:
        return wrong;
      case mastered:
        return mastered;
      case pending:
      default:
        return pending;
    }
  }
}

class PracticeQuestionKind {
  const PracticeQuestionKind._();

  static const String normal = 'normal';
  static const String similar = 'similar';

  static String normalize(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case similar:
        return similar;
      case normal:
      default:
        return normal;
    }
  }
}

class WrongQuestionTrainingRecord {
  const WrongQuestionTrainingRecord({
    required this.id,
    required this.wrongQuestionId,
    required this.causeTags,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  final int id;
  final int wrongQuestionId;
  final List<String> causeTags;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;

  bool get isCompleted => status == WrongQuestionTrainingStatus.completed;

  factory WrongQuestionTrainingRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?) ?? '';
    final completedAt = (map['completed_at'] as String?) ?? '';

    return WrongQuestionTrainingRecord(
      id: map['id'] as int,
      wrongQuestionId: map['wrong_question_id'] as int,
      causeTags: _decodeTags((map['cause_tags_json'] as String?) ?? '[]'),
      status:
          (map['status'] as String?)?.trim() ??
          WrongQuestionTrainingStatus.pending,
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
      completedAt: completedAt.isEmpty
          ? null
          : DateTime.tryParse(completedAt)?.toLocal(),
    );
  }

  static List<String> _decodeTags(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      return const <String>[];
    }
    return decoded
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

class WrongQuestionTrainingStatus {
  const WrongQuestionTrainingStatus._();

  static const String pending = 'pending';
  static const String completed = 'completed';
}

class GeneratedContentRecord {
  const GeneratedContentRecord({
    required this.contentType,
    required this.contentLabel,
    required this.documentId,
    required this.documentTitle,
    required this.title,
    required this.summary,
    required this.createdAt,
  });

  final String contentType;
  final String contentLabel;
  final int documentId;
  final String documentTitle;
  final String title;
  final String summary;
  final DateTime createdAt;
}

class PracticeQuestionWithDocument {
  const PracticeQuestionWithDocument({
    required this.question,
    required this.documentTitle,
  });

  final PracticeQuestionRecord question;
  final String documentTitle;
}

class AiTaskWithDocument {
  const AiTaskWithDocument({
    required this.id,
    required this.documentId,
    required this.documentTitle,
    required this.taskType,
    required this.taskLabel,
    required this.status,
    required this.updatedAt,
    this.errorMessage,
  });

  final int id;
  final int documentId;
  final String documentTitle;
  final String taskType;
  final String taskLabel;
  final String status;
  final String? errorMessage;
  final DateTime updatedAt;
}

class StudyOverviewStats {
  const StudyOverviewStats({
    required this.documentCount,
    required this.ocrSuccessCount,
    required this.generatedResultCount,
    required this.practiceQuestionCount,
    required this.pendingPracticeCount,
    required this.wrongQuestionCount,
    required this.masteredQuestionCount,
  });

  final int documentCount;
  final int ocrSuccessCount;
  final int generatedResultCount;
  final int practiceQuestionCount;
  final int pendingPracticeCount;
  final int wrongQuestionCount;
  final int masteredQuestionCount;
}
