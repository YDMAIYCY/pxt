class LlmProvider {
  const LlmProvider._();

  static const String minimax = 'minimax';
  static const String kimi = 'kimi';
  static const String custom = 'custom';
  static const String openai = 'openai';
  static const String deepseek = 'deepseek';
  static const String opencodeGo = 'opencode_go';
  static const String claude = 'claude';
  static const String gemini = 'gemini';
  static const String siliconflow = 'siliconflow';
  static const String zhipu = 'zhipu';

  static String normalize(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    switch (raw) {
      case '':
        return custom;
      case kimi:
      case 'moonshot':
      case 'moonshot_ai':
        return kimi;
      case minimax:
        return minimax;
      case 'opencode-go':
      case 'opencode':
        return opencodeGo;
      case zhipu:
      case 'zhipuai':
      case 'glm':
      case 'bigmodel':
        return zhipu;
      default:
        return raw;
    }
  }
}

class LlmApiMode {
  const LlmApiMode._();

  static const String tokenPlan = 'token_plan';
  static const String openPlatform = 'open_platform';
  static const String openAiCompatible = 'openai_compatible';
  static const String anthropic = 'anthropic_messages';
  static const String responses = 'responses';
  static const String gemini = 'gemini';
  static const String auto = 'auto';

  static String normalize(String? value, {String? provider}) {
    final raw = (value ?? '').trim().toLowerCase();
    switch (raw) {
      case anthropic:
      case responses:
      case gemini:
      case auto:
        return raw;
      case tokenPlan:
      case 'token-plan':
      case 'anthropic':
        return tokenPlan;
      case openAiCompatible:
      case 'openai':
      case 'openai-compatible':
      case 'chat_completions':
        return openAiCompatible;
      case openPlatform:
      case 'chatcompletion':
      case 'chat_completion':
        return openPlatform;
      default:
        return LlmProvider.normalize(provider) == LlmProvider.minimax
            ? tokenPlan
            : openAiCompatible;
    }
  }
}

class LlmProviderConfig {
  const LlmProviderConfig({
    required this.id,
    required this.userId,
    required this.provider,
    required this.apiMode,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    required this.maxTokens,
    required this.createdAt,
    required this.updatedAt,
    this.displayName = '',
    this.temperature,
    this.responseFormat = 'auto',
  });

  final int? id;
  final int userId;
  final String provider;
  final String apiMode;
  final String apiKey;
  final String baseUrl;
  final String model;
  final int? maxTokens;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String displayName;
  final double? temperature;
  final String responseFormat;

  String get effectiveApiMode {
    if (provider == LlmProvider.claude) return LlmApiMode.anthropic;
    if (provider == LlmProvider.gemini) return LlmApiMode.gemini;
    if (provider == LlmProvider.opencodeGo && apiMode == LlmApiMode.auto) {
      final id = model.toLowerCase();
      if (id.startsWith('claude-') ||
          id.startsWith('minimax-') ||
          id.startsWith('qwen3.7-') ||
          id.startsWith('qwen3.8-')) {
        return LlmApiMode.anthropic;
      }
      if (id.startsWith('gpt-') ||
          id.startsWith('grok-') ||
          id.startsWith('muse-')) {
        return LlmApiMode.responses;
      }
      if (id.startsWith('gemini-')) return LlmApiMode.gemini;
      return LlmApiMode.openAiCompatible;
    }
    return apiMode;
  }

  bool get isMiniMax => provider == LlmProvider.minimax;

  bool get isKimi => provider == LlmProvider.kimi;

  bool get usesTokenPlan => apiMode == LlmApiMode.tokenPlan;

  bool get usesOpenAiCompatible =>
      effectiveApiMode == LlmApiMode.openAiCompatible ||
      (!isMiniMax &&
          !const [
            LlmApiMode.anthropic,
            LlmApiMode.responses,
            LlmApiMode.gemini,
          ].contains(effectiveApiMode));

  bool get isConfigured {
    if (apiKey.trim().isEmpty) {
      return false;
    }
    if (usesTokenPlan) {
      return true;
    }
    return effectiveBaseUrl.trim().isNotEmpty &&
        effectiveModel.trim().isNotEmpty;
  }

  String get effectiveBaseUrl {
    final normalized = _stripTrailingSlash(baseUrl.trim());
    if (normalized.isNotEmpty) {
      if (usesTokenPlan && _isMiniMaxCompatibleBase(normalized)) {
        return 'https://api.minimax.io/anthropic';
      }
      return normalized;
    }

    if (usesTokenPlan) {
      return 'https://api.minimax.io/anthropic';
    }
    if (isMiniMax) {
      return 'https://api.minimax.io';
    }
    return '';
  }

  String get effectivePath {
    if (effectiveApiMode == LlmApiMode.anthropic) return '/messages';
    if (effectiveApiMode == LlmApiMode.responses) return '/responses';
    if (effectiveApiMode == LlmApiMode.gemini) {
      return '/models/${effectiveModel.replaceFirst(RegExp(r'^models/'), '')}:generateContent';
    }
    if (usesOpenAiCompatible) {
      return '/chat/completions';
    }
    return usesTokenPlan ? '/v1/messages' : '/v1/text/chatcompletion_v2';
  }

  String get effectiveModel {
    final normalized = model.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }

    if (usesOpenAiCompatible) {
      return '';
    }
    return usesTokenPlan ? 'MiniMax-M2.7' : 'MiniMax-Text-01';
  }

  int get effectiveMaxTokens {
    final value = maxTokens ?? 4096;
    if (value < 512) {
      return 512;
    }
    if (value > 32768) {
      return 32768;
    }
    return value;
  }

  Uri get effectiveEndpoint => _buildUri(effectiveBaseUrl, effectivePath);

  LlmProviderConfig copyWith({
    int? id,
    int? userId,
    String? provider,
    String? apiMode,
    String? apiKey,
    String? baseUrl,
    String? model,
    Object? maxTokens = _sentinel,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? displayName,
    double? temperature,
    String? responseFormat,
  }) {
    final nextProvider = provider == null
        ? this.provider
        : LlmProvider.normalize(provider);
    return LlmProviderConfig(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      provider: nextProvider,
      apiMode: apiMode == null
          ? this.apiMode
          : LlmApiMode.normalize(apiMode, provider: nextProvider),
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      maxTokens: maxTokens == _sentinel ? this.maxTokens : maxTokens as int?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      displayName: displayName ?? this.displayName,
      temperature: temperature ?? this.temperature,
      responseFormat: responseFormat ?? this.responseFormat,
    );
  }

  Map<String, Object?> toDatabaseMap() {
    return {
      'user_id': userId,
      'provider': provider,
      'api_mode': apiMode,
      'api_key': '',
      'base_url': _stripTrailingSlash(baseUrl.trim()),
      'model': model.trim(),
      'max_tokens': effectiveMaxTokens,
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  Map<String, Object?> toSecureMap() => {
    ...toDatabaseMap(),
    'api_key': apiKey.trim(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'display_name': displayName,
    'temperature': temperature,
    'response_format': responseFormat,
  };

  factory LlmProviderConfig.emptyForUser(int userId) {
    final now = DateTime.now();
    return LlmProviderConfig(
      id: null,
      userId: userId,
      provider: LlmProvider.custom,
      apiMode: LlmApiMode.openAiCompatible,
      apiKey: '',
      baseUrl: '',
      model: '',
      maxTokens: 4096,
      createdAt: now,
      updatedAt: now,
    );
  }

  static String inferApiMode({
    required String provider,
    required String apiKey,
    required String baseUrl,
    String? currentApiMode,
  }) {
    final normalizedProvider = LlmProvider.normalize(provider);
    final normalizedCurrent = LlmApiMode.normalize(
      currentApiMode,
      provider: normalizedProvider,
    );

    if (normalizedProvider != LlmProvider.minimax) {
      return LlmApiMode.openAiCompatible;
    }

    final normalizedApiKey = apiKey.trim().toLowerCase();
    final normalizedBaseUrl = _stripTrailingSlash(baseUrl).toLowerCase();
    if (normalizedApiKey.startsWith('sk-cp-') ||
        normalizedBaseUrl.contains('/anthropic')) {
      return LlmApiMode.tokenPlan;
    }

    if (normalizedCurrent == LlmApiMode.tokenPlan &&
        normalizedBaseUrl.isEmpty) {
      return LlmApiMode.tokenPlan;
    }

    return LlmApiMode.openAiCompatible;
  }

  factory LlmProviderConfig.fromMap(Map<String, Object?> map) {
    final rawCreatedAt = (map['created_at'] as String?)?.trim() ?? '';
    final rawUpdatedAt = (map['updated_at'] as String?)?.trim() ?? '';
    final normalizedProvider = LlmProvider.normalize(
      map['provider'] as String?,
    );

    return LlmProviderConfig(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      provider: normalizedProvider,
      apiMode: LlmApiMode.normalize(
        map['api_mode'] as String?,
        provider: normalizedProvider,
      ),
      apiKey: (map['api_key'] as String?)?.trim() ?? '',
      baseUrl: _stripTrailingSlash((map['base_url'] as String?)?.trim() ?? ''),
      model: (map['model'] as String?)?.trim() ?? '',
      maxTokens: map['max_tokens'] as int?,
      createdAt: DateTime.tryParse(rawCreatedAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(rawUpdatedAt)?.toLocal() ?? DateTime.now(),
      displayName: map['display_name'] as String? ?? '',
      temperature: (map['temperature'] as num?)?.toDouble(),
      responseFormat: map['response_format'] as String? ?? 'auto',
    );
  }

  static Uri _buildUri(String baseUrl, String path) {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final baseUri = Uri.parse(_stripTrailingSlash(baseUrl));
    final baseSegments = baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);
    final pathSegments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (pathSegments.isEmpty || _endsWithSegments(baseSegments, pathSegments)) {
      return baseUri;
    }

    if (baseSegments.isNotEmpty &&
        pathSegments.isNotEmpty &&
        baseSegments.last == pathSegments.first) {
      baseSegments.addAll(pathSegments.skip(1));
    } else {
      baseSegments.addAll(pathSegments);
    }

    return baseUri.replace(pathSegments: baseSegments);
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

  static bool _isMiniMaxCompatibleBase(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.host.toLowerCase().contains('minimax')) {
      return false;
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .map((segment) => segment.toLowerCase())
        .toList(growable: false);
    return segments.isEmpty ||
        segments.contains('v1') ||
        _endsWithSegments(segments, const ['chat', 'completions']);
  }
}

const Object _sentinel = Object();
