import 'dart:convert';

import '../database/ai_generation_repository.dart';
import '../database/knowledge_graph_repository.dart';
import '../database/models/ai_generation_task_record.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';
import 'knowledge_graph_extraction_service.dart';

class AiSingleTaskResult {
  const AiSingleTaskResult({
    required this.taskType,
    required this.success,
    required this.message,
  });

  final String taskType;
  final bool success;
  final String message;
}

class AiBatchResult {
  const AiBatchResult({required this.results});

  final List<AiSingleTaskResult> results;

  bool get hasFailure => results.any((item) => !item.success);
}

class AiGenerationOrchestrator {
  AiGenerationOrchestrator({
    MiniMaxClient? miniMaxClient,
    AiGenerationRepository? aiGenerationRepository,
    KnowledgeGraphRepository? knowledgeGraphRepository,
    KnowledgeGraphExtractionService? knowledgeGraphExtractionService,
  }) : _miniMaxClient = miniMaxClient ?? MiniMaxClient(),
       _aiGenerationRepository =
           aiGenerationRepository ?? AiGenerationRepository(),
       _knowledgeGraphRepository =
           knowledgeGraphRepository ?? KnowledgeGraphRepository(),
       _knowledgeGraphExtractionService =
           knowledgeGraphExtractionService ?? KnowledgeGraphExtractionService();

  final MiniMaxClient _miniMaxClient;
  final AiGenerationRepository _aiGenerationRepository;
  final KnowledgeGraphRepository _knowledgeGraphRepository;
  final KnowledgeGraphExtractionService _knowledgeGraphExtractionService;

  Future<AiSingleTaskResult> generateSingle({
    required int documentId,
    required String ocrText,
    required String taskType,
    LlmProviderConfig? llmConfig,
  }) {
    return _runTask(
      documentId: documentId,
      ocrText: ocrText,
      taskType: taskType,
      llmConfig: llmConfig,
    );
  }

  Future<AiBatchResult> generateAll({
    required int documentId,
    required String ocrText,
    LlmProviderConfig? llmConfig,
  }) async {
    final results = <AiSingleTaskResult>[];

    for (final taskType in AiTaskType.all) {
      final result = await _runTask(
        documentId: documentId,
        ocrText: ocrText,
        taskType: taskType,
        llmConfig: llmConfig,
      );
      results.add(result);
    }

    return AiBatchResult(results: results);
  }

  Future<AiSingleTaskResult> _runTask({
    required int documentId,
    required String ocrText,
    required String taskType,
    LlmProviderConfig? llmConfig,
  }) async {
    final trimmedText = ocrText.trim();
    if (trimmedText.isEmpty) {
      return AiSingleTaskResult(
        taskType: taskType,
        success: false,
        message: 'OCR 文本为空，无法开始生成',
      );
    }

    final promptTemplate = _promptTemplateOf(taskType);
    final taskRecord = await _aiGenerationRepository.markTaskRunning(
      documentId: documentId,
      taskType: taskType,
      inputText: trimmedText,
      promptTemplate: promptTemplate,
      provider: llmConfig == null
          ? 'MiniMax'
          : '${llmConfig.provider}/${llmConfig.effectiveModel}',
    );

    try {
      final client = llmConfig == null
          ? _miniMaxClient
          : MiniMaxClient.fromConfig(llmConfig);
      final response = await client.generateStructuredJson(
        systemPrompt: _systemPrompt,
        userPrompt: _buildUserPrompt(taskType: taskType, ocrText: trimmedText),
        jsonSchema: _jsonSchemaOf(taskType),
      );

      await _persistTaskResult(
        documentId: documentId,
        taskType: taskType,
        response: response,
      );

      await _aiGenerationRepository.markTaskCompleted(
        taskId: taskRecord.id,
        resultText: const JsonEncoder.withIndent('  ').convert(response),
      );
      await _refreshKnowledgeGraph(
        documentId: documentId,
        ocrText: trimmedText,
        response: response,
        llmConfig: llmConfig,
      );

      return AiSingleTaskResult(
        taskType: taskType,
        success: true,
        message: '${AiTaskType.labelOf(taskType)}生成成功',
      );
    } catch (error) {
      final errorMessage = _friendlyError(error);
      await _aiGenerationRepository.markTaskFailed(
        taskId: taskRecord.id,
        errorMessage: errorMessage,
      );

      return AiSingleTaskResult(
        taskType: taskType,
        success: false,
        message: errorMessage,
      );
    }
  }

  Future<void> _persistTaskResult({
    required int documentId,
    required String taskType,
    required Map<String, dynamic> response,
  }) async {
    switch (taskType) {
      case AiTaskType.knowledgeCards:
        await _aiGenerationRepository.replaceKnowledgeCards(
          documentId: documentId,
          cards: _parseKnowledgeCards(response),
        );
        return;
      case AiTaskType.reviewOutline:
        final outline = _parseReviewOutline(response);
        await _aiGenerationRepository.replaceReviewOutline(
          documentId: documentId,
          title: outline.$1,
          outlineText: outline.$2,
        );
        return;
      case AiTaskType.mindmapText:
        await _aiGenerationRepository.replaceMindmapText(
          documentId: documentId,
          mindmapText: _parseMindmapText(response),
        );
        return;
      case AiTaskType.practiceQuestions:
        await _aiGenerationRepository.replacePracticeQuestions(
          documentId: documentId,
          questions: _parsePracticeQuestions(response),
        );
        return;
      default:
        throw FormatException('不支持的任务类型：$taskType');
    }
  }

  Future<void> _refreshKnowledgeGraph({
    required int documentId,
    required String ocrText,
    required Map<String, dynamic> response,
    LlmProviderConfig? llmConfig,
  }) async {
    final scope = await _knowledgeGraphRepository.findDocumentScope(documentId);
    if (scope == null) {
      return;
    }

    try {
      await _knowledgeGraphExtractionService.generateForDocument(
        userId: scope.userId,
        libraryId: scope.libraryId,
        documentId: documentId,
        sourceText:
            '$ocrText\n\nAI 生成结果：\n${const JsonEncoder.withIndent('  ').convert(response)}',
        llmConfig: llmConfig,
      );
    } catch (_) {
      // Knowledge graph extraction is a secondary enrichment step. Keep the
      // generated learning material available even when graph extraction fails.
    }
  }

  List<Map<String, String>> _parseKnowledgeCards(Map<String, dynamic> data) {
    final rawCards = _pickFirstList(data, const [
      'cards',
      'knowledge_cards',
      'items',
      'data',
      'list',
    ]);
    if (rawCards == null) {
      final title = _pickFirstString(data, const ['title', 'card_title']);
      final content = _pickFirstString(data, const [
        'content',
        'text',
        'summary',
      ]);
      if (title.isNotEmpty || content.isNotEmpty) {
        return [
          {'title': title.isEmpty ? '知识点' : title, 'content': content},
        ];
      }

      throw const FormatException('cards 字段缺失或格式错误');
    }

    final cards = rawCards
        .whereType<Map>()
        .toList(growable: false)
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key;
          final item = entry.value.cast<String, Object?>();
          final title = _pickFirstString(item, const [
            'title',
            'card_title',
            'name',
          ]);
          final content = _pickFirstString(item, const [
            'content',
            'text',
            'description',
            'summary',
          ]);

          return {
            'title': title.isEmpty ? '知识点 ${index + 1}' : title,
            'content': content,
          };
        })
        .where((item) => (item['content'] ?? '').isNotEmpty)
        .toList(growable: false);

    if (cards.isEmpty) {
      throw const FormatException('知识卡片为空');
    }

    return cards;
  }

  (String, String) _parseReviewOutline(Map<String, dynamic> data) {
    final title = _pickFirstString(data, const ['title', 'outline_title']);
    final outlineText = _pickFirstString(data, const [
      'outline_text',
      'outline',
      'content',
      'text',
      'markdown',
    ]);

    if (title.isNotEmpty && outlineText.isNotEmpty) {
      return (title, outlineText);
    }

    final outline = _pickFirstList(data, const [
      'outline',
      'sections',
      'items',
    ]);
    if (outline is List) {
      final lines = outline
          .map((item) {
            if (item is Map) {
              final heading = _pickFirstString(
                item.cast<String, Object?>(),
                const ['title', 'heading', 'name'],
              );
              final points = _pickFirstList(
                item.cast<String, Object?>(),
                const ['points', 'children'],
              );
              if (points != null && points.isNotEmpty) {
                final joined = points
                    .map((point) => point.toString().trim())
                    .where((point) => point.isNotEmpty)
                    .map((point) => '  - $point')
                    .join('\n');
                if (joined.isNotEmpty) {
                  return '${heading.isEmpty ? '要点' : heading}\n$joined';
                }
              }
              return heading;
            }
            return item.toString().trim();
          })
          .where((line) => line.isNotEmpty)
          .toList(growable: false);

      if (lines.isNotEmpty) {
        return (
          title.isEmpty ? '复习提纲' : title,
          lines.map((line) => '- $line').join('\n'),
        );
      }
    }

    throw const FormatException('复习提纲格式错误');
  }

  String _parseMindmapText(Map<String, dynamic> data) {
    final mindmapText = _pickFirstString(data, const [
      'mindmap_text',
      'mind_map_text',
      'mindmap',
      'content',
      'text',
      'markdown',
    ]);
    if (mindmapText.isNotEmpty) {
      return mindmapText;
    }

    final rootTopic = _pickFirstString(data, const [
      'root_topic',
      'topic',
      'title',
    ]);
    final branches = _pickFirstList(data, const [
      'branches',
      'children',
      'items',
    ]);
    if (rootTopic.isNotEmpty && branches is List && branches.isNotEmpty) {
      final branchLines = branches
          .map((item) {
            if (item is Map) {
              return _pickFirstString(item.cast<String, Object?>(), const [
                'topic',
                'title',
                'name',
                'text',
                'content',
              ]);
            }
            return item.toString().trim();
          })
          .where((item) => item.isNotEmpty)
          .map((item) => '- $item')
          .join('\n');

      if (branchLines.isNotEmpty) {
        return '$rootTopic\n$branchLines';
      }
    }

    throw const FormatException('思维导图文字版格式错误');
  }

  List<Map<String, String>> _parsePracticeQuestions(Map<String, dynamic> data) {
    final questions = _pickFirstList(data, const [
      'questions',
      'practice_questions',
      'exercises',
      'items',
      'data',
    ]);
    if (questions is! List) {
      final singleQuestion = _pickFirstString(data, const [
        'question_text',
        'question',
      ]);
      if (singleQuestion.isNotEmpty) {
        return [
          {
            'question_text': singleQuestion,
            'answer_text': _pickFirstString(data, const [
              'answer_text',
              'answer',
              'reference_answer',
            ]),
            'analysis_text': _pickFirstString(data, const [
              'analysis_text',
              'analysis',
              'explanation',
            ]),
            'difficulty': _pickFirstString(data, const ['difficulty']),
          },
        ];
      }

      throw const FormatException('questions 字段缺失或格式错误');
    }

    final parsed = questions
        .whereType<Map>()
        .map(
          (item) => {
            'question_text': (item['question_text'] ?? item['question'] ?? '')
                .toString()
                .trim(),
            'answer_text': (item['answer_text'] ?? item['answer'] ?? '')
                .toString()
                .trim(),
            'analysis_text': (item['analysis_text'] ?? item['analysis'] ?? '')
                .toString()
                .trim(),
            'difficulty': (item['difficulty'] ?? '').toString().trim(),
          },
        )
        .where((item) => (item['question_text'] ?? '').isNotEmpty)
        .toList(growable: false);

    if (parsed.isEmpty) {
      throw const FormatException('复习题为空');
    }

    return parsed;
  }

  String _friendlyError(Object error) {
    if (error is MiniMaxException) {
      return error.message;
    }

    if (error is FormatException) {
      return 'AI 返回格式不符合预期，请重试一次；若仍失败，可先缩短 OCR 文本后再生成。';
    }

    final message = error.toString().trim();
    if (message.isEmpty) {
      return 'AI 生成失败，请重试';
    }

    return 'AI 生成失败：$message';
  }

  String _buildUserPrompt({required String taskType, required String ocrText}) {
    final taskSchema = _schemaOf(taskType);

    return '''
请基于以下 OCR 文本进行处理。

输出要求：
1. 必须只返回 JSON 对象，不要输出额外解释。
2. JSON 必须严格符合下面 schema。
3. 内容使用中文，准确、简洁、便于学习复习。

Schema:
$taskSchema

OCR 文本:
$ocrText
''';
  }

  String _schemaOf(String taskType) {
    switch (taskType) {
      case AiTaskType.knowledgeCards:
        return '{"cards":[{"title":"卡片标题","content":"卡片内容"}]}';
      case AiTaskType.reviewOutline:
        return '{"title":"提纲标题","outline_text":"- 要点1\\n- 要点2"}';
      case AiTaskType.mindmapText:
        return '{"mindmap_text":"中心主题\\n- 分支1\\n- 分支2"}';
      case AiTaskType.practiceQuestions:
        return '{"questions":[{"question_text":"题目","answer_text":"参考答案","analysis_text":"解析","difficulty":"easy|medium|hard"}]}';
      default:
        return '{}';
    }
  }

  Map<String, dynamic> _jsonSchemaOf(String taskType) {
    switch (taskType) {
      case AiTaskType.knowledgeCards:
        return {
          'name': 'knowledge_cards_response',
          'schema': {
            'type': 'object',
            'properties': {
              'cards': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'title': {'type': 'string'},
                    'content': {'type': 'string'},
                  },
                  'required': ['title', 'content'],
                },
              },
            },
            'required': ['cards'],
          },
        };
      case AiTaskType.reviewOutline:
        return {
          'name': 'review_outline_response',
          'schema': {
            'type': 'object',
            'properties': {
              'title': {'type': 'string'},
              'outline_text': {'type': 'string'},
            },
            'required': ['title', 'outline_text'],
          },
        };
      case AiTaskType.mindmapText:
        return {
          'name': 'mindmap_text_response',
          'schema': {
            'type': 'object',
            'properties': {
              'mindmap_text': {'type': 'string'},
            },
            'required': ['mindmap_text'],
          },
        };
      case AiTaskType.practiceQuestions:
        return {
          'name': 'practice_questions_response',
          'schema': {
            'type': 'object',
            'properties': {
              'questions': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'question_text': {'type': 'string'},
                    'answer_text': {'type': 'string'},
                    'analysis_text': {'type': 'string'},
                    'difficulty': {'type': 'string'},
                  },
                  'required': [
                    'question_text',
                    'answer_text',
                    'analysis_text',
                    'difficulty',
                  ],
                },
              },
            },
            'required': ['questions'],
          },
        };
      default:
        return {
          'name': 'generic_ai_response',
          'schema': {'type': 'object'},
        };
    }
  }

  String _promptTemplateOf(String taskType) {
    return _schemaOf(taskType);
  }

  List? _pickFirstList(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is List) {
        return value;
      }
    }

    return null;
  }

  String _pickFirstString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return '';
  }

  static const String _systemPrompt =
      '你是一名学习资料生成助手，只能返回可解析 JSON，不要包含 markdown 代码块。';
}
