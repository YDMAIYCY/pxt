import '../database/knowledge_graph_repository.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';

class KnowledgeGraphExtractionService {
  KnowledgeGraphExtractionService({
    MiniMaxClient? miniMaxClient,
    KnowledgeGraphRepository? knowledgeGraphRepository,
  }) : _miniMaxClient = miniMaxClient ?? MiniMaxClient(),
       _knowledgeGraphRepository =
           knowledgeGraphRepository ?? KnowledgeGraphRepository();

  final MiniMaxClient _miniMaxClient;
  final KnowledgeGraphRepository _knowledgeGraphRepository;

  Future<KnowledgeGraphDraft> generateForDocument({
    required int userId,
    required int documentId,
    required String sourceText,
    int? libraryId,
    LlmProviderConfig? llmConfig,
  }) async {
    final trimmedText = sourceText.trim();
    if (trimmedText.isEmpty) {
      throw const FormatException('source text is empty');
    }

    final client = llmConfig == null
        ? _miniMaxClient
        : MiniMaxClient.fromConfig(llmConfig);
    final response = await client.generateStructuredJson(
      systemPrompt: _systemPrompt,
      userPrompt: _buildPrompt(trimmedText),
      jsonSchema: _jsonSchema,
    );
    final draft = parseGraphResponse(response);
    await _knowledgeGraphRepository.replaceGraphForDocument(
      userId: userId,
      libraryId: libraryId,
      documentId: documentId,
      draft: draft,
    );
    return draft;
  }

  static KnowledgeGraphDraft parseGraphResponse(Map<String, dynamic> data) {
    final rawConcepts = _pickFirstList(data, const [
      'concepts',
      'nodes',
      'knowledge_points',
      'items',
    ]);
    final concepts = (rawConcepts ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .map(
          (item) => KnowledgeConceptDraft(
            name: _pickFirstString(item, const ['name', 'title', 'concept']),
            summary: _pickFirstString(item, const [
              'summary',
              'description',
              'content',
            ]),
            evidenceText: _pickFirstString(item, const [
              'evidence_text',
              'evidence',
              'source',
            ]),
            masteryScore: _pickFirstInt(item, const [
              'mastery_score',
              'mastery',
            ]),
            weaknessScore: _pickFirstInt(item, const [
              'weakness_score',
              'weakness',
              'risk_score',
            ]),
          ),
        )
        .where((item) => item.name.trim().isNotEmpty)
        .toList(growable: false);

    if (concepts.isEmpty) {
      throw const FormatException('concepts is empty');
    }

    final rawLinks = _pickFirstList(data, const [
      'relationships',
      'links',
      'edges',
      'relations',
    ]);
    final links = (rawLinks ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .map(
          (item) => KnowledgeConceptLinkDraft(
            fromName: _pickFirstString(item, const [
              'from',
              'source',
              'from_name',
            ]),
            toName: _pickFirstString(item, const ['to', 'target', 'to_name']),
            relationLabel: _pickFirstString(item, const [
              'relation',
              'label',
              'type',
            ]),
          ),
        )
        .where(
          (item) =>
              item.fromName.trim().isNotEmpty && item.toName.trim().isNotEmpty,
        )
        .toList(growable: false);

    return KnowledgeGraphDraft(concepts: concepts, links: links);
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

  static int _pickFirstInt(Map<String, Object?> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is int) {
        return value.clamp(0, 100).toInt();
      }
      if (value is num) {
        return value.clamp(0, 100).toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed.clamp(0, 100).toInt();
        }
      }
    }
    return 0;
  }

  static String _buildPrompt(String sourceText) {
    return '''
请从下面的学习资料中抽取个人知识图谱。

要求：
1. concepts 是知识点节点，尽量使用短名称。
2. mastery_score 表示当前掌握度，0-100；weakness_score 表示薄弱风险，0-100。
3. relationships 表示知识点之间的依赖、包含、易错关联。
4. 只返回 JSON，不要输出 markdown。

学习资料：
$sourceText
''';
  }

  static const String _systemPrompt =
      '你是学习诊断助手，只返回可解析 JSON。不要编造资料中没有的知识点；不确定时降低 mastery_score 并提高 weakness_score。';

  static const Map<String, dynamic> _jsonSchema = {
    'name': 'knowledge_graph_response',
    'schema': {
      'type': 'object',
      'properties': {
        'concepts': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'summary': {'type': 'string'},
              'evidence_text': {'type': 'string'},
              'mastery_score': {'type': 'number'},
              'weakness_score': {'type': 'number'},
            },
            'required': [
              'name',
              'summary',
              'evidence_text',
              'mastery_score',
              'weakness_score',
            ],
          },
        },
        'relationships': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'from': {'type': 'string'},
              'to': {'type': 'string'},
              'relation': {'type': 'string'},
            },
            'required': ['from', 'to', 'relation'],
          },
        },
      },
      'required': ['concepts', 'relationships'],
    },
  };
}
