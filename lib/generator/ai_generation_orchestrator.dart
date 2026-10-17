import 'dart:convert';

import '../database/ai_generation_repository.dart';
import '../database/knowledge_graph_repository.dart';
import '../database/models/ai_generation_task_record.dart';
import '../database/models/ai_result_records.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';
import 'graph_builder_service.dart';
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
    KnowledgeGraphBuilder? knowledgeGraphBuilder,
  }) : _miniMaxClient = miniMaxClient ?? MiniMaxClient(),
       _aiGenerationRepository =
           aiGenerationRepository ?? AiGenerationRepository(),
       _knowledgeGraphRepository =
           knowledgeGraphRepository ?? KnowledgeGraphRepository(),
       _knowledgeGraphExtractionService =
           knowledgeGraphExtractionService ?? KnowledgeGraphExtractionService(),
       _knowledgeGraphBuilder =
           knowledgeGraphBuilder ?? KnowledgeGraphBuilder();

  final MiniMaxClient _miniMaxClient;
  final AiGenerationRepository _aiGenerationRepository;
  final KnowledgeGraphRepository _knowledgeGraphRepository;
  final KnowledgeGraphExtractionService _knowledgeGraphExtractionService;
  final KnowledgeGraphBuilder _knowledgeGraphBuilder;

  Future<AiSingleTaskResult> generateSingle({
    required int documentId,
    required String ocrText,
    required String taskType,
    LlmProviderConfig? llmConfig,
    bool appendResults = false,
  }) {
    return _runTask(
      documentId: documentId,
      ocrText: ocrText,
      taskType: taskType,
      llmConfig: llmConfig,
      appendResults: appendResults,
    );
  }

  Future<AiSingleTaskResult> regenerateWithFeedback({
    required int documentId,
    required String ocrText,
    required String taskType,
    required String currentResultText,
    required String feedback,
    LlmProviderConfig? llmConfig,
    bool appendResults = false,
  }) {
    return _runTask(
      documentId: documentId,
      ocrText: ocrText,
      taskType: taskType,
      llmConfig: llmConfig,
      appendResults: appendResults,
      currentResultText: currentResultText,
      feedback: feedback,
    );
  }

  Future<AiBatchResult> generateAll({
    required int documentId,
    required String ocrText,
    LlmProviderConfig? llmConfig,
    bool appendResults = false,
  }) async {
    final results = <AiSingleTaskResult>[];

    for (final taskType in AiTaskType.all) {
      final result = await _runTask(
        documentId: documentId,
        ocrText: ocrText,
        taskType: taskType,
        llmConfig: llmConfig,
        appendResults: appendResults,
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
    String? currentResultText,
    String? feedback,
    bool appendResults = false,
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
        userPrompt: _buildUserPrompt(
          taskType: taskType,
          ocrText: trimmedText,
          currentResultText: currentResultText,
          feedback: feedback,
        ),
        jsonSchema: _jsonSchemaOf(taskType),
      );

      await _persistTaskResult(
        documentId: documentId,
        taskType: taskType,
        response: response,
        appendResults: appendResults,
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
    bool appendResults = false,
  }) async {
    switch (taskType) {
      case AiTaskType.knowledgeCards:
        await _aiGenerationRepository.replaceKnowledgeCards(
          documentId: documentId,
          append: appendResults,
          cards: _parseKnowledgeCards(response),
        );
        return;
      case AiTaskType.reviewOutline:
        final outline = _parseReviewOutline(response);
        await _aiGenerationRepository.replaceReviewOutline(
          documentId: documentId,
          append: appendResults,
          title: outline.$1,
          outlineText: outline.$2,
        );
        return;
      case AiTaskType.mindmapText:
        await _aiGenerationRepository.replaceMindmapText(
          documentId: documentId,
          append: appendResults,
          mindmapText: _parseMindmapText(response),
        );
        return;
      case AiTaskType.practiceQuestions:
        await _aiGenerationRepository.replacePracticeQuestions(
          documentId: documentId,
          append: appendResults,
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

    // 同步增量更新跨知识库规范图谱：新资料进入图谱，旧内容不会被全量重建。
    try {
      await _knowledgeGraphBuilder.buildForDocument(
        userId: scope.userId,
        documentId: documentId,
        llmConfig: llmConfig,
      );
    } catch (_) {
      // 规范图谱是二次增强；失败不影响本次 AI 成果。
    }
  }

  static List<Map<String, String>> parsePracticeQuestionsForTest(
    Map<String, dynamic> data,
  ) {
    return AiGenerationOrchestrator()._parsePracticeQuestions(data);
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
      final lines = <String>[];
      void addBranches(List items, int depth) {
        for (final item in items) {
          final map = item is Map ? item.cast<String, Object?>() : null;
          final title = map == null
              ? item.toString().trim()
              : _pickFirstString(map, const [
                  'topic',
                  'title',
                  'name',
                  'text',
                  'content',
                ]);
          if (title.isEmpty) continue;
          lines.add(
            '${'  ' * depth}- ${title.replaceAll(RegExp(r'\s+'), ' ')}',
          );
          if (map != null) {
            final children = _pickFirstList(map, const [
              'children',
              'branches',
              'items',
            ]);
            if (children is List) addBranches(children, depth + 1);
          }
        }
      }

      addBranches(branches, 0);
      final branchLines = lines.join('\n');

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
        final parsed = [
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
            'question_kind': PracticeQuestionKind.normalize(
              _pickFirstString(data, const ['question_kind', 'kind', 'type']),
            ),
            'options_json': _jsonListText(data['options'] ?? data['choices']),
            'rubric_json': _jsonMapText(data['rubric'] ?? data['scoring']),
            'expected_keywords_json': _jsonListText(
              data['expected_keywords'] ?? data['keywords'],
            ),
          },
        ];
        _validatePracticeQuestions(parsed);
        return parsed;
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
            'question_kind': PracticeQuestionKind.normalize(
              (item['question_kind'] ?? item['kind'] ?? item['type'] ?? '')
                  .toString(),
            ),
            'options_json': _jsonListText(item['options'] ?? item['choices']),
            'rubric_json': _jsonMapText(item['rubric'] ?? item['scoring']),
            'expected_keywords_json': _jsonListText(
              item['expected_keywords'] ?? item['keywords'],
            ),
          },
        )
        .where((item) => (item['question_text'] ?? '').isNotEmpty)
        .toList(growable: false);

    if (parsed.isEmpty) {
      throw const FormatException('复习题为空');
    }

    _validatePracticeQuestions(parsed);
    return parsed;
  }

  void _validatePracticeQuestions(List<Map<String, String>> questions) {
    for (final question in questions) {
      final kind = question['question_kind'] ?? '';
      if (kind != PracticeQuestionKind.multipleChoice) {
        continue;
      }

      final options = _decodeStringList(question['options_json']);
      if (options.length < 2) {
        throw const FormatException('选择题必须包含 options 选项');
      }
    }
  }

  List<String> _decodeStringList(String? jsonText) {
    final raw = (jsonText ?? '').trim();
    if (raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
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

  String _buildUserPrompt({
    required String taskType,
    required String ocrText,
    String? currentResultText,
    String? feedback,
  }) {
    final taskSchema = _schemaOf(taskType);
    final mindmapInstructions = taskType == AiTaskType.mindmapText
        ? '''
思维导图结构要求：
- 首行只写一个中心主题；围绕中心主题组织并列的一级分支，资料充足时建议 3 至 8 个，不要把所有知识点串在单一分支下。
- 每个一级分支按内容分成 2 至 5 个二级要点，必要时增加第三级，通常保持 2 至 4 层。资料较少时按实际内容组织，不凑数量、不编造知识。
- 每个节点用简洁关键词或短句，通常 4 至 18 个字；概念、公式、例子、易错点分成独立子节点，不把整段说明塞进一个节点，但不要遗漏关键条件和公式。
- mindmap_text 使用缩进列表：中心主题不加符号，一级分支以“- ”开头，二级分支以“  - ”开头，每深入一级增加两个空格。一行一个节点，同级分支保持相同缩进。
- 不要输出 Mermaid、坐标、颜色代码或 Markdown 代码围栏。界面会按一级分支向左右展开，并为不同分支使用不同颜色。
'''
        : '';
    final refinementBlock = _buildRefinementBlock(
      currentResultText: currentResultText,
      feedback: feedback,
    );

    return '''
请基于以下 OCR 文本进行处理。

输出要求：
1. 必须只返回 JSON 对象，不要输出额外解释。
2. JSON 必须严格符合下面 schema。
3. 内容使用中文，准确、清晰、便于学习复习。
4. 如果 question_kind 是 multiple_choice，必须提供 4 个 options，且每个选项必须带 A./B./C./D. 前缀，answer_text 必须能对应其中一个选项。
$mindmapInstructions

Schema:
$taskSchema

OCR 文本:
$ocrText
$refinementBlock
''';
  }

  String _buildRefinementBlock({String? currentResultText, String? feedback}) {
    final currentResult = (currentResultText ?? '').trim();
    final userFeedback = (feedback ?? '').trim();
    if (currentResult.isEmpty && userFeedback.isEmpty) {
      return '';
    }

    return '''

当前已有 AI 结果:
$currentResult

用户修改意见:
$userFeedback

请基于 OCR 原文、当前结果和用户修改意见，重新生成同一种类型的结果。保留正确内容，重点修正用户不满意的地方。
''';
  }

  String _schemaOf(String taskType) {
    if (taskType == AiTaskType.practiceQuestions) {
      return '{"questions":[{"question_kind":"multiple_choice|fill_blank|true_false|short_answer|calculation|application|error_analysis|oral","question_text":"question","options":["A. 选项内容","B. 选项内容","C. 选项内容","D. 选项内容"],"answer_text":"answer","analysis_text":"analysis","difficulty":"easy|medium|hard","expected_keywords":["keyword"],"rubric":{"point":40}}]}';
    }

    switch (taskType) {
      case AiTaskType.knowledgeCards:
        return '{"cards":[{"title":"卡片标题","content":"卡片内容"}]}';
      case AiTaskType.reviewOutline:
        return '{"title":"提纲标题","outline_text":"- 要点1\\n- 要点2"}';
      case AiTaskType.mindmapText:
        return '{"mindmap_text":"中心主题\\n- 核心概念\\n  - 定义与条件\\n  - 关键公式\\n- 方法与步骤\\n  - 适用情形\\n  - 操作步骤\\n- 例子与易错点\\n  - 典型例子\\n  - 常见误区"}';
      case AiTaskType.practiceQuestions:
        return '{"questions":[{"question_text":"题目","answer_text":"参考答案","analysis_text":"解析","difficulty":"easy|medium|hard"}]}';
      default:
        return '{}';
    }
  }

  Map<String, dynamic> _jsonSchemaOf(String taskType) {
    if (taskType == AiTaskType.practiceQuestions) {
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
                  'question_kind': {'type': 'string'},
                  'question_text': {'type': 'string'},
                  'options': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                  'answer_text': {'type': 'string'},
                  'analysis_text': {'type': 'string'},
                  'difficulty': {'type': 'string'},
                  'expected_keywords': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                  'rubric': {'type': 'object'},
                },
                'required': [
                  'question_kind',
                  'question_text',
                  'options',
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
    }

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

  static String _jsonListText(Object? value) {
    if (value == null) return '';
    if (value is List) {
      return jsonEncode(
        value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
      );
    }
    final text = value.toString().trim();
    return text.isEmpty ? '' : jsonEncode([text]);
  }

  static String _jsonMapText(Object? value) {
    if (value == null) return '';
    if (value is Map) {
      return jsonEncode(value);
    }
    final text = value.toString().trim();
    return text.isEmpty ? '' : jsonEncode({'rubric': text});
  }

  static const String _systemPrompt =
      '你是一名学习资料生成助手，只能返回可解析 JSON，不要包含 markdown 代码块。';
}
