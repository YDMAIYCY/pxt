import 'dart:convert';

// Source and scope IDs are historical snapshots, not live source references.

class InterviewSession {
  const InterviewSession({
    required this.id,
    required this.userId,
    required this.libraryId,
    this.recordId,
    required this.scopeName,
    required this.mode,
    required this.difficulty,
    required this.targetQuestionCount,
    required this.completedQuestionCount,
    required this.status,
    required this.currentOrder,
    required this.currentRound,
    required this.voiceEnabled,
    required this.autoPlay,
    required this.voiceRate,
    required this.voiceVolume,
    required this.startedAt,
    this.endedAt,
    this.errorMessage,
    this.reportJson,
  });

  final int id;
  final int userId;
  final int libraryId;
  final int? recordId;
  final String scopeName;
  final String mode;
  final String difficulty;
  final int targetQuestionCount;
  final int completedQuestionCount;
  final String status;
  final int currentOrder;
  final int currentRound;
  final bool voiceEnabled;
  final bool autoPlay;
  final double voiceRate;
  final double voiceVolume;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? errorMessage;
  final String? reportJson;

  factory InterviewSession.fromMap(Map<String, Object?> row) =>
      InterviewSession(
        id: row['id'] as int,
        userId: row['user_id'] as int,
        libraryId: row['library_id'] as int,
        recordId: row['record_id'] as int?,
        scopeName: row['scope_name'] as String,
        mode: row['mode'] as String,
        difficulty: row['difficulty'] as String,
        targetQuestionCount: row['target_question_count'] as int,
        completedQuestionCount: row['completed_question_count'] as int,
        status: row['status'] as String,
        currentOrder: row['current_order'] as int,
        currentRound: row['current_round'] as int,
        voiceEnabled: row['voice_enabled'] == 1,
        autoPlay: row['auto_play'] == 1,
        voiceRate: (row['voice_rate'] as num).toDouble(),
        voiceVolume: (row['voice_volume'] as num).toDouble(),
        startedAt: DateTime.parse(row['started_at'] as String),
        endedAt: row['ended_at'] == null
            ? null
            : DateTime.parse(row['ended_at'] as String),
        errorMessage: row['error_message'] as String?,
        reportJson: row['report_json'] as String?,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'user_id': userId,
    'library_id': libraryId,
    'record_id': recordId,
    'scope_name': scopeName,
    'mode': mode,
    'difficulty': difficulty,
    'target_question_count': targetQuestionCount,
    'completed_question_count': completedQuestionCount,
    'status': status,
    'current_order': currentOrder,
    'current_round': currentRound,
    'voice_enabled': voiceEnabled ? 1 : 0,
    'auto_play': autoPlay ? 1 : 0,
    'voice_rate': voiceRate,
    'voice_volume': voiceVolume,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'error_message': errorMessage,
    'report_json': reportJson,
  };
}

class InterviewQuestionDraft {
  InterviewQuestionDraft({
    required this.questionText,
    required List<String> referencePoints,
    required this.knowledgePoint,
    this.knowledgePointId,
    required this.sourceRecordId,
    required this.sourcePageId,
    required this.evidenceText,
    required this.sourceKind,
    required this.orderIndex,
  }) : referencePoints = List.unmodifiable(referencePoints);

  final String questionText;
  final List<String> referencePoints;
  final String knowledgePoint;
  final int? knowledgePointId;
  final int sourceRecordId;
  final int sourcePageId;
  final String evidenceText;
  final String sourceKind;
  final int orderIndex;

  Map<String, Object?> toMap() => {
    'question_text': questionText,
    'reference_points_json': jsonEncode(referencePoints),
    'knowledge_point': knowledgePoint,
    'knowledge_point_id': knowledgePointId,
    'source_record_id': sourceRecordId,
    'source_page_id': sourcePageId,
    'evidence_text': evidenceText,
    'source_kind': sourceKind,
    'order_index': orderIndex,
  };
}

class InterviewQuestion {
  InterviewQuestion({
    required this.id,
    required this.sessionId,
    required this.questionText,
    required List<String> referencePoints,
    required this.knowledgePoint,
    this.knowledgePointId,
    required this.sourceRecordId,
    required this.sourcePageId,
    required this.evidenceText,
    required this.sourceKind,
    required this.orderIndex,
    required this.status,
  }) : referencePoints = List.unmodifiable(referencePoints);

  final int id;
  final int sessionId;
  final String questionText;
  final List<String> referencePoints;
  final String knowledgePoint;
  final int? knowledgePointId;
  final int sourceRecordId;
  final int sourcePageId;
  final String evidenceText;
  final String sourceKind;
  final int orderIndex;
  final String status;

  factory InterviewQuestion.fromMap(Map<String, Object?> row) =>
      InterviewQuestion(
        id: row['id'] as int,
        sessionId: row['session_id'] as int,
        questionText: row['question_text'] as String,
        referencePoints:
            (jsonDecode(row['reference_points_json'] as String) as List)
                .cast<String>(),
        knowledgePoint: row['knowledge_point'] as String,
        knowledgePointId: row['knowledge_point_id'] as int?,
        sourceRecordId: row['source_record_id'] as int,
        sourcePageId: row['source_page_id'] as int,
        evidenceText: row['evidence_text'] as String,
        sourceKind: row['source_kind'] as String,
        orderIndex: row['order_index'] as int,
        status: row['status'] as String,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'question_text': questionText,
    'reference_points_json': jsonEncode(referencePoints),
    'knowledge_point': knowledgePoint,
    'knowledge_point_id': knowledgePointId,
    'source_record_id': sourceRecordId,
    'source_page_id': sourcePageId,
    'evidence_text': evidenceText,
    'source_kind': sourceKind,
    'order_index': orderIndex,
    'status': status,
  };
}

class InterviewTurn {
  const InterviewTurn({
    required this.id,
    required this.sessionId,
    required this.questionId,
    required this.speaker,
    required this.text,
    this.rawText,
    this.audioPath,
    this.durationMs,
    required this.round,
    required this.isFollowUp,
    required this.status,
    required this.requestKey,
    required this.createdAt,
  });

  final int id;
  final int sessionId;
  final int questionId;
  final String speaker;
  final String text;
  final String? rawText;
  final String? audioPath;
  final int? durationMs;
  final int round;
  final bool isFollowUp;
  final String status;
  final String requestKey;
  final DateTime createdAt;

  factory InterviewTurn.fromMap(Map<String, Object?> row) => InterviewTurn(
    id: row['id'] as int,
    sessionId: row['session_id'] as int,
    questionId: row['question_id'] as int,
    speaker: row['speaker'] as String,
    text: row['text'] as String,
    rawText: row['raw_text'] as String?,
    audioPath: row['audio_path'] as String?,
    durationMs: row['duration_ms'] as int?,
    round: row['round'] as int,
    isFollowUp: row['is_follow_up'] == 1,
    status: row['status'] as String,
    requestKey: row['request_key'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'question_id': questionId,
    'speaker': speaker,
    'text': text,
    'raw_text': rawText,
    'audio_path': audioPath,
    'duration_ms': durationMs,
    'round': round,
    'is_follow_up': isFollowUp ? 1 : 0,
    'status': status,
    'request_key': requestKey,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class InterviewEvaluation {
  InterviewEvaluation({
    required this.id,
    required this.sessionId,
    required this.questionId,
    required this.turnId,
    required this.accuracyScore,
    required this.completenessScore,
    required this.logicScore,
    required this.expressionScore,
    required this.totalScore,
    required List<String> strengths,
    required List<String> weaknesses,
    required List<String> suggestions,
    required List<int> evidenceRefs,
    this.followUpText,
    required List<String> followUpReferencePoints,
  }) : strengths = List.unmodifiable(strengths),
       weaknesses = List.unmodifiable(weaknesses),
       suggestions = List.unmodifiable(suggestions),
       evidenceRefs = List.unmodifiable(evidenceRefs),
       followUpReferencePoints = List.unmodifiable(followUpReferencePoints);

  final int id;
  final int sessionId;
  final int questionId;
  final int turnId;
  final int accuracyScore;
  final int completenessScore;
  final int logicScore;
  final int expressionScore;
  final int totalScore;
  final List<String> strengths;
  final List<String> weaknesses;
  final List<String> suggestions;
  final List<int> evidenceRefs;
  final String? followUpText;
  final List<String> followUpReferencePoints;

  factory InterviewEvaluation.fromMap(Map<String, Object?> row) =>
      InterviewEvaluation(
        id: row['id'] as int,
        sessionId: row['session_id'] as int,
        questionId: row['question_id'] as int,
        turnId: row['turn_id'] as int,
        accuracyScore: row['accuracy_score'] as int,
        completenessScore: row['completeness_score'] as int,
        logicScore: row['logic_score'] as int,
        expressionScore: row['expression_score'] as int,
        totalScore: row['total_score'] as int,
        strengths: (jsonDecode(row['strengths_json'] as String) as List)
            .cast<String>(),
        weaknesses: (jsonDecode(row['weaknesses_json'] as String) as List)
            .cast<String>(),
        suggestions: (jsonDecode(row['suggestions_json'] as String) as List)
            .cast<String>(),
        evidenceRefs: (jsonDecode(row['evidence_refs_json'] as String) as List)
            .cast<int>(),
        followUpText: row['follow_up_text'] as String?,
        followUpReferencePoints:
            (jsonDecode(row['follow_up_reference_points_json'] as String)
                    as List)
                .cast<String>(),
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'session_id': sessionId,
    'question_id': questionId,
    'turn_id': turnId,
    'accuracy_score': accuracyScore,
    'completeness_score': completenessScore,
    'logic_score': logicScore,
    'expression_score': expressionScore,
    'total_score': totalScore,
    'strengths_json': jsonEncode(strengths),
    'weaknesses_json': jsonEncode(weaknesses),
    'suggestions_json': jsonEncode(suggestions),
    'evidence_refs_json': jsonEncode(evidenceRefs),
    'follow_up_text': followUpText,
    'follow_up_reference_points_json': jsonEncode(followUpReferencePoints),
  };
}
