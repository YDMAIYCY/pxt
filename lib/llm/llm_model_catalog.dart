import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/models/llm_provider_config.dart';
import 'llm_request_support.dart';

// ========== 模型目录 ==========
// 这里集中放常见 OpenAI-compatible 服务商的模型预设与在线模型拉取逻辑。
class LlmModelOption {
  const LlmModelOption({
    required this.id,
    required this.label,
    this.description = '',
  });

  final String id;
  final String label;
  final String description;
}

class LlmProviderPreset {
  const LlmProviderPreset({
    required this.provider,
    required this.label,
    required this.baseUrl,
    required this.models,
    this.description = '',
  });

  final String provider;
  final String label;
  final String baseUrl;
  final List<LlmModelOption> models;
  final String description;
}

class LlmModelCatalogException implements Exception {
  const LlmModelCatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LlmModelCatalog {
  const LlmModelCatalog._();

  static const List<LlmProviderPreset> providerPresets = [
    LlmProviderPreset(
      provider: 'kimi',
      label: 'Kimi / Moonshot',
      baseUrl: 'https://api.moonshot.cn/v1',
      description: '适合中文学习总结、长上下文资料整理和视觉理解场景。',
      models: [
        LlmModelOption(
          id: 'kimi-k2.6',
          label: 'Kimi K2.6',
          description: '最新 Kimi 主力模型，256k 上下文，适合复杂学习资料整理。',
        ),
        LlmModelOption(
          id: 'kimi-k2.5',
          label: 'Kimi K2.5',
          description: '通用多模态模型，兼顾 Agent、代码和视觉理解。',
        ),
        LlmModelOption(
          id: 'kimi-k2-thinking',
          label: 'Kimi K2 Thinking',
          description: '长思考版本，适合推理题、错题讲解和多步分析。',
        ),
        LlmModelOption(
          id: 'kimi-k2-thinking-turbo',
          label: 'Kimi K2 Thinking Turbo',
          description: '长思考高速版本，适合需要更快输出的推理场景。',
        ),
        LlmModelOption(
          id: 'kimi-k2-turbo-preview',
          label: 'Kimi K2 Turbo Preview',
          description: '高速 K2 版本，适合批量生成提纲和卡片。',
        ),
        LlmModelOption(
          id: 'kimi-k2-0905-preview',
          label: 'Kimi K2 0905 Preview',
          description: 'K2 预览版本，增强 Agentic Coding 和上下文理解。',
        ),
        LlmModelOption(
          id: 'moonshot-v1-128k',
          label: 'Moonshot V1 128k',
          description: '长文本生成模型，适合超长讲义。',
        ),
        LlmModelOption(
          id: 'moonshot-v1-32k',
          label: 'Moonshot V1 32k',
          description: '中长文本生成模型，适合普通课件和讲义。',
        ),
        LlmModelOption(
          id: 'moonshot-v1-8k',
          label: 'Moonshot V1 8k',
          description: '短文本生成模型，适合题目解析和小段总结。',
        ),
      ],
    ),
    LlmProviderPreset(
      provider: 'deepseek',
      label: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      description: '适合低成本文本生成、推理题拆解和长上下文处理。',
      models: [
        LlmModelOption(
          id: 'deepseek-v4-flash',
          label: 'DeepSeek V4 Flash',
          description: '主力高速模型，支持非思考和思考模式。',
        ),
        LlmModelOption(
          id: 'deepseek-v4-pro',
          label: 'DeepSeek V4 Pro',
          description: '更强版本，适合复杂推理和高质量解释。',
        ),
        LlmModelOption(
          id: 'deepseek-chat',
          label: 'DeepSeek Chat',
          description: '兼容模型名，对应 V4 Flash 非思考模式。',
        ),
        LlmModelOption(
          id: 'deepseek-reasoner',
          label: 'DeepSeek Reasoner',
          description: '兼容模型名，对应 V4 Flash 思考模式。',
        ),
      ],
    ),
    LlmProviderPreset(
      provider: 'minimax',
      label: 'MiniMax',
      baseUrl: 'https://api.minimax.io/v1',
      description: '适合中文文本生成、长资料整理和 Agent 工作流。',
      models: [
        LlmModelOption(
          id: 'MiniMax-M2.7',
          label: 'MiniMax M2.7',
          description: 'MiniMax 当前主力文本模型，204800 token 总上下文。',
        ),
        LlmModelOption(
          id: 'MiniMax-M2.7-highspeed',
          label: 'MiniMax M2.7 Highspeed',
          description: 'M2.7 极速版，适合更快生成学习资料。',
        ),
        LlmModelOption(
          id: 'MiniMax-M2.5',
          label: 'MiniMax M2.5',
          description: '兼顾性能和性价比，适合日常学习生成。',
        ),
        LlmModelOption(
          id: 'MiniMax-M2.5-highspeed',
          label: 'MiniMax M2.5 Highspeed',
          description: 'M2.5 极速版，适合批量任务。',
        ),
        LlmModelOption(
          id: 'MiniMax-M2.1',
          label: 'MiniMax M2.1',
          description: '多语言与编程能力较强的模型。',
        ),
        LlmModelOption(
          id: 'MiniMax-M2.1-highspeed',
          label: 'MiniMax M2.1 Highspeed',
          description: 'M2.1 极速版，适合低等待场景。',
        ),
        LlmModelOption(
          id: 'MiniMax-M2',
          label: 'MiniMax M2',
          description: '面向高效编码和 Agent 工作流的模型。',
        ),
      ],
    ),
    LlmProviderPreset(
      provider: 'openai',
      label: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      description: '适合复杂推理、编码和多模态学习资料处理。',
      models: [
        LlmModelOption(
          id: 'gpt-5.5',
          label: 'GPT-5.5',
          description: 'OpenAI 旗舰模型，适合复杂推理、编码和专业任务。',
        ),
        LlmModelOption(
          id: 'gpt-5.4',
          label: 'GPT-5.4',
          description: '更经济的强模型，适合高质量学习内容生成。',
        ),
        LlmModelOption(
          id: 'gpt-5.4-mini',
          label: 'GPT-5.4 Mini',
          description: '更低成本低延迟，适合日常生成。',
        ),
        LlmModelOption(
          id: 'gpt-5.4-nano',
          label: 'GPT-5.4 Nano',
          description: '更快更省，适合轻量摘要和分类。',
        ),
      ],
    ),
    LlmProviderPreset(
      provider: LlmProvider.opencodeGo,
      label: 'OpenCode Go',
      baseUrl: 'https://opencode.ai/inference/go/v1',
      models: [
        LlmModelOption(
          id: 'step-5-preview-free',
          label: 'Step 5 Preview',
          description: '限时预览模型，实际可用性以接口和账户权限为准。',
        ),
        LlmModelOption(
          id: 'glm-5.3-flash',
          label: 'GLM 5.3 Flash',
          description: '通用快速模型，使用对话协议。',
        ),
        LlmModelOption(
          id: 'gpt-6-luna',
          label: 'GPT 6 Luna',
          description: '推理模型，使用 Responses 协议。',
        ),
        LlmModelOption(
          id: 'claude-haiku-5-5',
          label: 'Claude Haiku 5.5',
          description: '使用 Anthropic Messages 协议。',
        ),
        LlmModelOption(
          id: 'minimax-m2.7',
          label: 'MiniMax M2.7',
          description: '使用 Anthropic Messages 协议。',
        ),
        LlmModelOption(
          id: 'gemini-4-argon-contributor',
          label: 'Gemini 4 Argon',
          description: '使用 Gemini 原生协议。',
        ),
      ],
    ),
    LlmProviderPreset(
      provider: LlmProvider.claude,
      label: 'Claude',
      baseUrl: 'https://api.anthropic.com/v1',
      models: [],
      description: '刷新获取账号可用模型，或手动填写模型 ID。',
    ),
    LlmProviderPreset(
      provider: LlmProvider.gemini,
      label: 'Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      models: [],
      description: '刷新获取支持内容生成的模型，或手动填写模型 ID。',
    ),
    LlmProviderPreset(
      provider: LlmProvider.siliconflow,
      label: '硅基流动',
      baseUrl: 'https://api.siliconflow.cn/v1',
      models: [
        LlmModelOption(
          id: 'deepseek-ai/DeepSeek-V4-Flash',
          label: 'DeepSeek V4 Flash',
          description: '通用文本模型，适合知识生成和问答。',
        ),
      ],
    ),
    LlmProviderPreset(
      provider: LlmProvider.custom,
      label: '自定义',
      baseUrl: '',
      models: [],
      description: '支持 OpenAI-compatible 接口。',
    ),
  ];

  static LlmProviderPreset? presetFor({
    required String provider,
    required String baseUrl,
  }) {
    final providerKey = _normalizeProvider(provider);
    final host = Uri.tryParse(baseUrl.trim())?.host.toLowerCase() ?? '';

    for (final preset in providerPresets) {
      if (providerKey == preset.provider) return preset;
    }
    for (final preset in providerPresets) {
      if (_hostMatches(host, preset)) {
        return preset;
      }
    }

    return null;
  }

  static List<LlmModelOption> modelsFor({
    required String provider,
    required String baseUrl,
    String currentModel = '',
  }) {
    final models = [
      ...?presetFor(provider: provider, baseUrl: baseUrl)?.models,
    ];
    final selected = currentModel.trim();

    if (selected.isNotEmpty &&
        !models.any(
          (model) => model.id.toLowerCase() == selected.toLowerCase(),
        )) {
      models.add(
        LlmModelOption(
          id: selected,
          label: selected,
          description: '当前已保存的自定义模型。',
        ),
      );
    }

    return models;
  }

  static Uri buildModelsEndpoint(String baseUrl) {
    final uri = Uri.parse(_stripTrailingSlash(baseUrl.trim()));
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);

    if (segments.isEmpty) {
      return uri.replace(pathSegments: ['models']);
    }
    if (segments.last == 'models') {
      return uri;
    }
    if (_endsWithSegments(segments, const ['chat', 'completions'])) {
      segments.removeLast();
      segments.removeLast();
    } else if (const ['responses', 'messages'].contains(segments.last)) {
      segments.removeLast();
    }

    if (segments.isEmpty || segments.last != 'models') {
      segments.add('models');
    }

    return uri.replace(pathSegments: segments);
  }

  static Future<List<LlmModelOption>> fetchModels({
    required String baseUrl,
    required String apiKey,
    String provider = LlmProvider.custom,
    http.Client? httpClient,
  }) async {
    final trimmedBaseUrl = baseUrl.trim();
    final trimmedApiKey = apiKey.trim();
    if (trimmedBaseUrl.isEmpty) {
      throw const LlmModelCatalogException('请先填写 Base URL');
    }
    if (trimmedApiKey.isEmpty) {
      throw const LlmModelCatalogException('请先填写 API Key');
    }

    final client = httpClient ?? http.Client();
    final shouldCloseClient = httpClient == null;

    try {
      var endpoint = buildModelsEndpoint(trimmedBaseUrl);
      final models = <LlmModelOption>[];
      do {
        final response = await client
            .get(
              endpoint,
              headers: LlmRequestSupport.headers(
                provider: provider,
                apiKey: trimmedApiKey,
              ),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw LlmModelCatalogException(
            LlmRequestSupport.httpError(response, trimmedApiKey),
          );
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, Object?> ||
            (decoded['data'] is! List && decoded['models'] is! List)) {
          throw const LlmModelCatalogException('模型列表返回格式不正确');
        }

        for (final item
            in (decoded['data'] ?? decoded['models']) as List<Object?>) {
          if (provider == LlmProvider.gemini &&
              item is Map &&
              !(item['supportedGenerationMethods'] as List? ?? []).contains(
                'generateContent',
              )) {
            continue;
          }
          final model = _parseRemoteModel(item);
          if (model != null &&
              !models.any(
                (existing) =>
                    existing.id.toLowerCase() == model.id.toLowerCase(),
              )) {
            models.add(model);
          }
        }
        final pageToken = decoded['nextPageToken'] as String?;
        final lastId = decoded['last_id'] as String?;
        if (provider == LlmProvider.gemini &&
            pageToken != null &&
            pageToken.isNotEmpty) {
          endpoint = endpoint.replace(
            queryParameters: {'pageToken': pageToken},
          );
        } else if (provider == LlmProvider.claude &&
            decoded['has_more'] == true &&
            lastId != null) {
          endpoint = endpoint.replace(queryParameters: {'after_id': lastId});
        } else {
          break;
        }
      } while (true);

      if (models.isEmpty) {
        throw const LlmModelCatalogException('没有从接口返回中读取到可用模型');
      }

      return models;
    } on TimeoutException {
      throw const LlmModelCatalogException('模型列表获取超时，请稍后重试');
    } on FormatException {
      throw const LlmModelCatalogException('模型列表不是有效 JSON');
    } on http.ClientException {
      throw const LlmModelCatalogException('模型列表连接失败，请检查网络和接口地址；也可手动填写模型 ID');
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  static LlmModelOption? _parseRemoteModel(Object? item) {
    if (item is String && item.trim().isNotEmpty) {
      final id = item.trim();
      return LlmModelOption(id: id, label: id);
    }
    if (item is! Map<String, Object?>) {
      return null;
    }

    final id = ((item['id'] ?? item['name']) as String?)?.trim().replaceFirst(
      RegExp(r'^models/'),
      '',
    );
    if (id == null || id.isEmpty) {
      return null;
    }

    final ownedBy = (item['owned_by'] as String?)?.trim() ?? '';
    return LlmModelOption(
      id: id,
      label: (item['displayName'] ?? item['display_name'] ?? id).toString(),
      description:
          (item['description'] ??
                  (ownedBy.isEmpty
                      ? '接口返回的模型；实际访问权限以连接测试为准。'
                      : '接口返回：$ownedBy'))
              .toString(),
    );
  }

  static bool _hostMatches(String host, LlmProviderPreset preset) {
    switch (preset.provider) {
      case 'kimi':
        return host.contains('moonshot') || host.contains('kimi');
      case 'deepseek':
        return host.contains('deepseek');
      case 'minimax':
        return host.contains('minimax') || host.contains('minimaxi');
      case 'openai':
        return host.contains('openai.com');
      default:
        return false;
    }
  }

  static String _normalizeProvider(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'moonshot':
      case 'moonshot_ai':
        return 'kimi';
      case 'minimaxi':
        return 'minimax';
      case 'chatgpt':
        return 'openai';
      default:
        return normalized;
    }
  }

  static bool _endsWithSegments(List<String> source, List<String> suffix) {
    if (suffix.length > source.length) {
      return false;
    }

    final offset = source.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (source[offset + i] != suffix[i]) {
        return false;
      }
    }
    return true;
  }

  static String _stripTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
