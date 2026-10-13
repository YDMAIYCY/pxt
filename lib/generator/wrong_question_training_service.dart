import '../database/ai_generation_repository.dart';
import '../database/models/ai_result_records.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';
import 'dart:convert';

class WrongQuestionTrainingDraft {
  const WrongQuestionTrainingDraft({
    required this.causeTags,
    required this.similarQuestions,
  });

  final List<String> causeTags;
  final List<Map<String, String>> similarQuestions;
}

class WrongQuestionTrainingService {
  WrongQuestionTrainingService({
    MiniMaxClient? miniMaxClient,
    AiGenerationRepository? aiGenerationRepository,
  }) : _miniMaxClient = miniMaxClient ?? MiniMaxClient(),
       _aiGenerationRepository =
           aiGenerationRepository ?? AiGenerationRepository();

  final MiniMaxClient _miniMaxClient;
  final AiGenerationRepository _aiGenerationRepository;

  Future<WrongQuestionTrainingDraft> generateForQuestion({
    required PracticeQuestionRecord question,
    LlmProviderConfig? llmConfig,
  }) async {
    final client = llmConfig == null
        ? _miniMaxClient
        : MiniMaxClient.fromConfig(llmConfig);
    final response = await client.generateStructuredJson(
      systemPrompt: _systemPrompt,
      userPrompt: _buildPrompt(question),
      jsonSchema: _jsonSchema,
    );
    final draft = parseTrainingResponse(response);
    final texts = draft.similarQuestions
        .map((q) => q['question_text']!.trim())
        .toList();
    if (texts.length < 2 ||
        texts.toSet().length != texts.length ||
        texts.contains(question.questionText.trim()) ||
        draft.similarQuestions.any(
          (q) => (q['answer_text'] ?? '').trim().isEmpty,
        )) {
      throw const FormatException('变式训练需要至少两道不同的新题及有效参考答案');
    }
    await _aiGenerationRepository.replaceWrongQuestionTraining(
      wrongQuestion: question,
      causeTags: draft.causeTags,
      similarQuestions: draft.similarQuestions,
    );
    return draft;
  }

  static WrongQuestionTrainingDraft parseTrainingResponse(
    Map<String, dynamic> data,
  ) {
    final rawTags = _pickFirstList(data, const [
      'cause_tags',
      'tags',
      'mistake_tags',
    ]);
    final causeTags = (rawTags ?? const <Object?>[])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final rawQuestions = _pickFirstList(data, const [
      'similar_questions',
      'questions',
      'items',
    ]);
    final similarQuestions = (rawQuestions ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .map(
          (item) => {
            'question_text': _pickFirstString(item, const [
              'question_text',
              'question',
            ]),
            'answer_text': _pickFirstString(item, const [
              'answer_text',
              'answer',
              'reference_answer',
            ]),
            'analysis_text': _pickFirstString(item, const [
              'analysis_text',
              'analysis',
              'explanation',
            ]),
            'difficulty': _pickFirstString(item, const ['difficulty']),
            'question_kind': _pickFirstString(item, const ['question_kind']),
            if (item['options'] is List)
              'options_json': jsonEncode(item['options']),
            if (item['rubric'] is Map)
              'rubric_json': jsonEncode(item['rubric']),
            if (item['expected_keywords'] is List)
              'expected_keywords_json': jsonEncode(item['expected_keywords']),
          },
        )
        .where((item) => (item['question_text'] ?? '').isNotEmpty)
        .take(3)
        .toList(growable: false);

    if (similarQuestions.isEmpty) {
      throw const FormatException('similar_questions is empty');
    }

    return WrongQuestionTrainingDraft(
      causeTags: causeTags.isEmpty ? const ['待分析'] : causeTags,
      similarQuestions: similarQuestions,
    );
  }

  static List? _pickFirstList(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value;
      }
    }
    return null;
  }

  static String _pickFirstString(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  static String _buildPrompt(PracticeQuestionRecord question) {
    return '''
请分析下面这道错题，输出错因标签和 2-3 道相似强化训练题。

题目：
${question.questionText}

参考答案：
${question.answerText ?? ''}

解析：
${question.analysisText ?? ''}

用户上次作答：
${question.lastUserAnswer ?? ''}

要求：
1. 必须返回 JSON，不要返回 markdown。
2. similar_questions 至少 2 道，最多 3 道。
3. 每道题都要有 question_text、answer_text、analysis_text、difficulty。
4. 题目应围绕原错因进行变式训练，不要照抄原题。
''';
  }

  static const String _systemPrompt =
      '你是学习诊断助手。你必须只返回可解析 JSON，不要包含 markdown 代码块。';

  static const Map<String, dynamic> _jsonSchema = {
    'name': 'wrong_question_training_response',
    'schema': {
      'type': 'object',
      'properties': {
        'cause_tags': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'similar_questions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'question_text': {'type': 'string'},
              'answer_text': {'type': 'string'},
              'analysis_text': {'type': 'string'},
              'difficulty': {'type': 'string'},
            },
            'required': ['question_text', 'answer_text', 'analysis_text'],
          },
        },
      },
      'required': ['cause_tags', 'similar_questions'],
    },
  };
}
