import '../database/models/ai_result_records.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';

// ========== AI Interview Feedback ==========
// Structured result returned after the interviewer evaluates an answer.

class AiInterviewFeedback {
  const AiInterviewFeedback({
    required this.score,
    required this.hitPoints,
    required this.missingPoints,
    required this.misconceptions,
    required this.correction,
    required this.standardAnswer,
    required this.nextFollowUp,
  });

  final int score;
  final List<String> hitPoints;
  final List<String> missingPoints;
  final List<String> misconceptions;
  final String correction;
  final String standardAnswer;
  final String nextFollowUp;
}

// ========== AI Interview Service ==========
// Uses generated practice questions as interview prompts and scores answers.

class AiInterviewService {
  AiInterviewService({MiniMaxClient? miniMaxClient})
    : _miniMaxClient = miniMaxClient;

  final MiniMaxClient? _miniMaxClient;

  Future<AiInterviewFeedback> evaluateAnswer({
    required PracticeQuestionWithDocument question,
    required String userAnswer,
    required LlmProviderConfig config,
  }) async {
    final client = _miniMaxClient ?? MiniMaxClient.fromConfig(config);
    final response = await client.generateStructuredJson(
      systemPrompt:
          'You are a supportive knowledge interviewer for learners of any age and field. Score against the supplied sources and reference answer. Follow-up questions may differ from the original question: use the source context and conversation history, never reuse an unrelated reference answer. In Feynman mode act as a curious beginner and check clarity, reasoning and omissions. Explain uncertainty when the source is insufficient. Return JSON only.',
      userPrompt: _buildPrompt(question: question, userAnswer: userAnswer),
      jsonSchema: _feedbackSchema,
    );
    return parseFeedback(response);
  }

  static AiInterviewFeedback parseFeedback(Map<String, dynamic> data) {
    return AiInterviewFeedback(
      score: _readInt(data['score']).clamp(0, 100),
      hitPoints: _readStringList(data['hit_points']),
      missingPoints: _readStringList(data['missing_points']),
      misconceptions: _readStringList(data['misconceptions']),
      correction: (data['correction'] ?? '').toString().trim(),
      standardAnswer: (data['standard_answer'] ?? '').toString().trim(),
      nextFollowUp: (data['next_follow_up'] ?? '').toString().trim(),
    );
  }

  static String _buildPrompt({
    required PracticeQuestionWithDocument question,
    required String userAnswer,
  }) {
    final record = question.question;
    final options = record.options.isEmpty
        ? 'None'
        : record.options.map((item) => '- $item').join('\n');
    final keywords = record.expectedKeywords.isEmpty
        ? 'None'
        : record.expectedKeywords.join(', ');
    final rubric = record.rubric.isEmpty ? 'None' : record.rubric.toString();

    return '''
Document: ${question.documentTitle}
Question kind: ${record.questionKind}
Question: ${record.questionText}
Options:
$options
Standard answer: ${record.answerText}
Original analysis: ${record.analysisText}
Expected keywords: $keywords
Rubric: $rubric

Learner answer:
$userAnswer

Return:
- score: integer 0-100
- hit_points: concepts the learner answered correctly
- missing_points: important concepts missing from the answer
- misconceptions: incorrect or risky statements
- correction: concise coaching feedback
- standard_answer: a polished correct answer
- next_follow_up: one short but varied follow-up interview question. Do not repeat the current question. Prefer one of these directions each time: counterexample, real-world application, boundary condition, why/how mechanism, comparison with a similar concept, error diagnosis, or asking the learner to teach it in simpler words.
''';
  }

  static List<String> _readStringList(Object? value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return const <String>[];
    }
    return [text];
  }

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  static const Map<String, dynamic> _feedbackSchema = {
    'name': 'ai_interview_feedback',
    'schema': {
      'type': 'object',
      'properties': {
        'score': {'type': 'integer'},
        'hit_points': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'missing_points': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'misconceptions': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'correction': {'type': 'string'},
        'standard_answer': {'type': 'string'},
        'next_follow_up': {'type': 'string'},
      },
      'required': [
        'score',
        'hit_points',
        'missing_points',
        'misconceptions',
        'correction',
        'standard_answer',
        'next_follow_up',
      ],
    },
  };
}
