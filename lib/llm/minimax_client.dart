import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_runtime_config.dart';
import '../database/models/llm_provider_config.dart';
import 'llm_request_support.dart';

class MiniMaxException implements Exception {
  const MiniMaxException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MiniMaxClient {
  MiniMaxClient({
    http.Client? httpClient,
    Uri? endpoint,
    String? apiKey,
    String? groupId,
    String? model,
    String? apiMode,
    String? provider,
    Duration? timeout,
    int? maxCompletionTokens,
    double? temperature,
    String responseFormat = 'auto',
    String? sessionId,
  }) : _httpClient = httpClient ?? http.Client(),
       _provider = LlmProvider.normalize(provider ?? LlmProvider.minimax),
       _apiMode = _resolveApiMode(
         apiMode: apiMode,
         provider: provider ?? LlmProvider.minimax,
         apiKey: apiKey ?? AppRuntimeConfig.minimaxApiKey,
       ),
       _apiKey = (apiKey ?? AppRuntimeConfig.minimaxApiKey).trim(),
       _groupId = (groupId ?? AppRuntimeConfig.minimaxGroupId).trim(),
       _model =
           (model ??
                   (_shouldUseTokenPlan(
                         apiKey ?? AppRuntimeConfig.minimaxApiKey,
                         apiMode ?? AppRuntimeConfig.minimaxApiMode,
                       )
                       ? AppRuntimeConfig.minimaxTokenPlanModel
                       : AppRuntimeConfig.minimaxModel))
               .trim(),
       _endpoint =
           endpoint ??
           (_shouldUseTokenPlan(
                 apiKey ?? AppRuntimeConfig.minimaxApiKey,
                 apiMode ?? AppRuntimeConfig.minimaxApiMode,
               )
               ? AppRuntimeConfig.miniMaxTokenPlanEndpoint
               : AppRuntimeConfig.miniMaxChatEndpoint),
       _timeout =
           timeout ?? Duration(seconds: AppRuntimeConfig.requestTimeoutSeconds),
       _maxCompletionTokens =
           maxCompletionTokens ?? AppRuntimeConfig.minimaxMaxCompletionTokens,
       _temperature = temperature,
       _responseFormat = responseFormat,
       _sessionId = sessionId ?? 'zxb-${DateTime.now().microsecondsSinceEpoch}';

  MiniMaxClient.fromConfig(
    LlmProviderConfig config, {
    http.Client? httpClient,
    String? sessionId,
  }) : _httpClient = httpClient ?? http.Client(),
       _provider = config.provider,
       _apiMode = config.effectiveApiMode,
       _apiKey = config.apiKey.trim(),
       _groupId = '',
       _model = config.effectiveModel,
       _endpoint = config.effectiveEndpoint,
       _timeout = Duration(seconds: AppRuntimeConfig.requestTimeoutSeconds),
       _maxCompletionTokens = config.effectiveMaxTokens,
       _temperature = config.temperature,
       _responseFormat = config.responseFormat,
       _sessionId = sessionId ?? 'zxb-${DateTime.now().microsecondsSinceEpoch}';

  final http.Client _httpClient;
  final Uri _endpoint;
  final String _apiKey;
  final String _groupId;
  final String _model;
  final String _provider;
  final String _apiMode;
  final Duration _timeout;
  final int _maxCompletionTokens;
  final double? _temperature;
  final String _responseFormat;
  final String _sessionId;

  Map<String, String> get _headers => LlmRequestSupport.headers(
    provider: _provider,
    apiKey: _apiKey,
    apiMode: _apiMode,
    sessionId: _sessionId,
  );

  Uri get debugEndpoint => _endpoint;

  String get debugModel => _model;

  bool get debugUsesTokenPlan => _usesTokenPlan;

  bool get debugUsesOpenAiCompatible => _usesOpenAiCompatible;

  int get debugMaxCompletionTokens => _maxCompletionTokens;

  String get _providerLabel {
    switch (_provider) {
      case LlmProvider.kimi:
        return 'Kimi';
      case LlmProvider.minimax:
        return 'MiniMax';
      case LlmProvider.zhipu:
        return '智谱 GLM';
      case LlmProvider.custom:
        return '自定义模型';
      default:
        return _provider;
    }
  }

  bool get _usesTokenPlan =>
      _provider == LlmProvider.minimax && _apiMode == LlmApiMode.tokenPlan;

  bool get _usesOpenAiCompatible =>
      _apiMode == LlmApiMode.openAiCompatible ||
      (_provider != LlmProvider.minimax &&
          !const [
            LlmApiMode.anthropic,
            LlmApiMode.responses,
            LlmApiMode.gemini,
          ].contains(_apiMode));

  Future<Map<String, dynamic>> generateStructuredJson({
    required String systemPrompt,
    required String userPrompt,
    Map<String, dynamic>? jsonSchema,
  }) async {
    if (_apiKey.isEmpty) {
      throw MiniMaxException('未配置 $_providerLabel API Key，请先到“我的”页配置大模型。');
    }

    final headers = _headers;
    if (_provider == LlmProvider.minimax &&
        !_usesTokenPlan &&
        _groupId.isNotEmpty) {
      headers['Group-Id'] = _groupId;
    }

    final body = _buildRequestBody(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      jsonSchema: jsonSchema,
    );

    try {
      final response = await _httpClient
          .post(_endpoint, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MiniMaxException(LlmRequestSupport.httpError(response, _apiKey));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      _throwIfApiError(decoded);
      _throwIfOutputTruncated(decoded);
      final jsonContent = _extractModelContent(decoded);
      return _parseStructuredJson(jsonContent);
    } on TimeoutException {
      throw MiniMaxException('$_providerLabel 请求超时，请稍后重试');
    } on http.ClientException {
      throw MiniMaxException('$_providerLabel 网络连接中断，请检查网络、代理或接口地址后重试。');
    } on FormatException {
      throw MiniMaxException('$_providerLabel 返回内容不是有效 JSON');
    }
  }

  Future<String> generateChatReply({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) async {
    if (_apiKey.isEmpty) {
      throw MiniMaxException('未配置 $_providerLabel API Key，请先到“我的”页配置大模型。');
    }

    final normalizedMessages = _normalizeChatMessages(messages);
    if (normalizedMessages.isEmpty) {
      throw const MiniMaxException('请输入聊天内容后再发送');
    }

    final headers = _headers;
    if (_provider == LlmProvider.minimax &&
        !_usesTokenPlan &&
        _groupId.isNotEmpty) {
      headers['Group-Id'] = _groupId;
    }

    final body = _buildChatRequestBody(
      systemPrompt: _responseFormat == 'json'
          ? '$systemPrompt\n请只返回有效 JSON 对象。'
          : systemPrompt,
      messages: normalizedMessages,
    );

    try {
      final response = await _httpClient
          .post(_endpoint, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MiniMaxException(LlmRequestSupport.httpError(response, _apiKey));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      _throwIfApiError(decoded);
      _throwIfOutputTruncated(decoded);
      final content = _extractModelContent(decoded);
      final reply = _extractPlainText(content);
      if (reply.isEmpty) {
        throw const FormatException('Empty chat response');
      }
      return reply;
    } on TimeoutException {
      throw MiniMaxException('$_providerLabel 请求超时，请稍后重试');
    } on http.ClientException {
      throw MiniMaxException('$_providerLabel 网络连接中断，请检查网络、代理或接口地址后重试。');
    } on FormatException {
      throw MiniMaxException('$_providerLabel 返回内容不是有效文本');
    }
  }

  static bool _shouldUseTokenPlan(String apiKey, String apiMode) {
    final normalizedMode = apiMode.trim().toLowerCase();
    if (normalizedMode == 'token_plan' || normalizedMode == 'token-plan') {
      return true;
    }
    if (normalizedMode == 'chatcompletion' ||
        normalizedMode == 'chat_completion' ||
        normalizedMode == 'open_platform') {
      return false;
    }

    return apiKey.trim().startsWith('sk-cp-');
  }

  static String _resolveApiMode({
    required String? apiMode,
    required String? provider,
    required String apiKey,
  }) {
    if (provider != null &&
        LlmProvider.normalize(provider) == LlmProvider.kimi) {
      return LlmApiMode.openAiCompatible;
    }
    if (provider != null &&
        LlmProvider.normalize(provider) != LlmProvider.minimax) {
      return LlmApiMode.openAiCompatible;
    }
    if (apiMode != null && apiMode.trim().isNotEmpty) {
      return LlmApiMode.normalize(apiMode, provider: provider);
    }
    return _shouldUseTokenPlan(apiKey, '')
        ? LlmApiMode.tokenPlan
        : LlmApiMode.openPlatform;
  }

  Map<String, Object?> _buildRequestBody({
    required String systemPrompt,
    required String userPrompt,
    required Map<String, dynamic>? jsonSchema,
  }) {
    final native = _nativeBody(
      systemPrompt: '$systemPrompt\n请只返回有效 JSON 对象。',
      messages: [
        {'role': 'user', 'content': userPrompt},
      ],
      json: true,
    );
    if (native != null) return native;
    if (_usesOpenAiCompatible) {
      return _buildOpenAiCompatibleBody(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
    }
    if (_usesTokenPlan) {
      return _buildTokenPlanBody(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
      );
    }
    return _buildMiniMaxChatCompletionBody(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      jsonSchema: jsonSchema,
    );
  }

  Map<String, Object?> _buildChatRequestBody({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) {
    final native = _nativeBody(
      systemPrompt: systemPrompt,
      messages: messages,
      json: _responseFormat == 'json',
    );
    if (native != null) return native;
    if (_usesOpenAiCompatible) {
      return _buildOpenAiCompatibleChatBody(
        systemPrompt: systemPrompt,
        messages: messages,
      );
    }
    if (_usesTokenPlan) {
      return _buildTokenPlanChatBody(
        systemPrompt: systemPrompt,
        messages: messages,
      );
    }
    return _buildMiniMaxChatCompletionChatBody(
      systemPrompt: systemPrompt,
      messages: messages,
    );
  }

  Map<String, Object?> _buildMiniMaxChatCompletionBody({
    required String systemPrompt,
    required String userPrompt,
    required Map<String, dynamic>? jsonSchema,
  }) {
    final body = <String, Object?>{
      'model': _model,
      'temperature': _temperature ?? 0.2,
      'max_completion_tokens': _maxCompletionTokens,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };
    if (jsonSchema != null && jsonSchema.isNotEmpty) {
      body['response_format'] = {
        'type': 'json_schema',
        'json_schema': jsonSchema,
      };
    }

    return body;
  }

  Map<String, Object?> _buildMiniMaxChatCompletionChatBody({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) {
    return {
      'model': _model,
      'temperature': _temperature ?? 0.4,
      'max_completion_tokens': _maxCompletionTokens,
      'messages': _withSystemMessage(systemPrompt, messages),
    };
  }

  Map<String, Object?> _buildTokenPlanBody({
    required String systemPrompt,
    required String userPrompt,
  }) {
    return {
      'model': _model,
      'anthropic_version': 'bedrock-2023-05-31',
      'temperature': _temperature ?? 0.2,
      'max_tokens': _maxCompletionTokens,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
    };
  }

  Map<String, Object?> _buildTokenPlanChatBody({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) {
    return {
      'model': _model,
      'anthropic_version': 'bedrock-2023-05-31',
      'temperature': _temperature ?? 0.4,
      'max_tokens': _maxCompletionTokens,
      'system': systemPrompt,
      'messages': messages,
    };
  }

  Map<String, Object?> _buildOpenAiCompatibleBody({
    required String systemPrompt,
    required String userPrompt,
  }) {
    return {
      'model': _model,
      'temperature': _openAiCompatibleTemperature,
      'max_tokens': _maxCompletionTokens,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    };
  }

  Map<String, Object?> _buildOpenAiCompatibleChatBody({
    required String systemPrompt,
    required List<Map<String, String>> messages,
  }) {
    return {
      'model': _model,
      'temperature': _openAiCompatibleTemperature,
      'max_tokens': _maxCompletionTokens,
      'messages': _withSystemMessage(systemPrompt, messages),
      if (_responseFormat == 'json') 'response_format': {'type': 'json_object'},
    };
  }

  double get _openAiCompatibleTemperature {
    if (_provider == LlmProvider.kimi ||
        _model.trim().toLowerCase().startsWith('kimi-')) {
      return 1.0;
    }
    return _temperature ?? 0.2;
  }

  Map<String, Object?>? _nativeBody({
    required String systemPrompt,
    required List<Map<String, String>> messages,
    required bool json,
  }) {
    if (_apiMode == LlmApiMode.anthropic) {
      return {
        'model': _model,
        'max_tokens': _maxCompletionTokens,
        'temperature': _temperature ?? 0.2,
        if (systemPrompt.isNotEmpty) 'system': systemPrompt,
        'messages': messages.where((m) => m['role'] != 'system').toList(),
      };
    }
    if (_apiMode == LlmApiMode.responses) {
      return {
        'model': _model,
        'max_output_tokens': _maxCompletionTokens,
        'store': false,
        'instructions': systemPrompt,
        'input': messages,
        if (json)
          'text': {
            'format': {'type': 'json_object'},
          },
      };
    }
    if (_apiMode == LlmApiMode.gemini) {
      return {
        if (systemPrompt.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
        'contents': messages
            .where((m) => m['role'] != 'system')
            .map(
              (m) => {
                'role': m['role'] == 'assistant' ? 'model' : 'user',
                'parts': [
                  {'text': m['content']},
                ],
              },
            )
            .toList(),
        'generationConfig': {
          'temperature': _temperature ?? 0.2,
          'maxOutputTokens': _maxCompletionTokens,
          if (json) 'responseMimeType': 'application/json',
        },
      };
    }
    return null;
  }

  Object? _extractModelContent(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_apiMode == LlmApiMode.responses) {
        final output = decoded['output'];
        if (output is List) {
          return output
              .whereType<Map>()
              .where((item) => item['type'] == 'message')
              .expand((item) => item['content'] as List? ?? [])
              .whereType<Map>()
              .where((part) => part['type'] == 'output_text')
              .map((part) => part['text'] ?? '')
              .join('\n');
        }
        return decoded['output_text'];
      }
      if (_apiMode == LlmApiMode.gemini) {
        final candidates = decoded['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final parts = candidates.first['content']?['parts'] as List? ?? [];
          return parts
              .whereType<Map>()
              .where((p) => p['thought'] != true)
              .map((p) => p['text'] ?? '')
              .join('\n');
        }
        throw const MiniMaxException('模型未返回内容，可能触发了安全限制');
      }
      final topLevelContent = decoded['content'];
      if (topLevelContent != null) {
        if (topLevelContent is List) {
          final normalized = _joinMessageParts(topLevelContent);
          if (normalized.isNotEmpty) {
            return normalized;
          }
        }
        return topLevelContent;
      }

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty && choices.first is Map) {
        final firstChoice = choices.first as Map;
        final message = firstChoice['message'];
        if (message is Map) {
          final content = message['content'];
          if (content != null) {
            if (content is List) {
              final normalized = _joinMessageParts(content);
              if (normalized.isNotEmpty) {
                return normalized;
              }
            }
            return content;
          }
        }

        final text = firstChoice['text'];
        if (text != null) {
          return text;
        }
      }

      if (decoded['reply'] != null) {
        return decoded['reply'];
      }
      if (decoded['output_text'] != null) {
        return decoded['output_text'];
      }
      if (decoded['data'] != null) {
        return decoded['data'];
      }
    }

    return decoded;
  }

  Map<String, dynamic> _parseStructuredJson(Object? content) {
    if (content is Map<String, dynamic>) {
      return content;
    }

    if (content is List && content.length == 1) {
      return _parseStructuredJson(content.first);
    }

    if (content is String) {
      final trimmed = content.trim();
      if (trimmed.isEmpty) {
        throw const FormatException('Empty response');
      }

      final normalized = _stripMarkdownCodeFence(trimmed);
      final jsonCandidate = _extractFirstJsonBlock(normalized);

      final decoded = jsonDecode(jsonCandidate);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is List) {
        if (decoded.length == 1 && decoded.first is Map<String, dynamic>) {
          return decoded.first as Map<String, dynamic>;
        }

        if (decoded.isNotEmpty) {
          return {'items': decoded};
        }
      }

      throw const FormatException('Response JSON is not an object');
    }

    throw const FormatException('Unsupported response content');
  }

  String _extractPlainText(Object? content) {
    if (content == null) {
      return '';
    }
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      return _joinMessageParts(content).trim();
    }
    if (content is Map) {
      final map = content.cast<String, Object?>();
      for (final key in const ['text', 'content', 'reply', 'output_text']) {
        final value = map[key];
        final text = _extractPlainText(value);
        if (text.isNotEmpty) {
          return text;
        }
      }
    }
    return '';
  }

  List<Map<String, String>> _withSystemMessage(
    String systemPrompt,
    List<Map<String, String>> messages,
  ) {
    final trimmedSystem = systemPrompt.trim();
    if (trimmedSystem.isEmpty) {
      return messages;
    }
    return [
      {'role': 'system', 'content': trimmedSystem},
      ...messages,
    ];
  }

  List<Map<String, String>> _normalizeChatMessages(
    List<Map<String, String>> messages,
  ) {
    return messages
        .map((message) {
          final role = _normalizeRole(message['role']);
          final content = (message['content'] ?? '').trim();
          if (content.isEmpty) {
            return null;
          }
          return {'role': role, 'content': content};
        })
        .whereType<Map<String, String>>()
        .toList(growable: false);
  }

  String _normalizeRole(String? role) {
    final raw = (role ?? '').trim().toLowerCase();
    switch (raw) {
      case 'assistant':
        return 'assistant';
      case 'system':
        return 'system';
      case 'user':
      default:
        return 'user';
    }
  }

  void _throwIfApiError(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final error = decoded['error'];
    if (error is Map) {
      final errorType = error['type']?.toString().trim();
      final message = error['message']?.toString().trim() ?? '';
      throw MiniMaxException(
        '$_providerLabel 请求失败'
        '${errorType == null || errorType.isEmpty ? '' : '（$errorType）'}：'
        '${message.isEmpty ? '未返回错误详情' : LlmRequestSupport.redact(message, _apiKey)}',
      );
    }

    final baseResponse = decoded['base_resp'];
    if (baseResponse is! Map) {
      return;
    }

    final statusCode = baseResponse['status_code'];
    if (statusCode == null || statusCode == 0) {
      return;
    }

    final statusMessage =
        (baseResponse['status_msg'] ?? baseResponse['message'])
            .toString()
            .trim();
    throw MiniMaxException(
      '$_providerLabel 请求失败（业务码 $statusCode）：'
      '${statusMessage.isEmpty ? '未返回错误详情' : LlmRequestSupport.redact(statusMessage, _apiKey)}',
    );
  }

  void _throwIfOutputTruncated(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    if (decoded['status'] == 'failed' || decoded['status'] == 'incomplete') {
      throw const MiniMaxException('模型响应失败或输出未完成，请检查额度或提高最大 Tokens');
    }
    final candidates = decoded['candidates'];
    if (candidates is List &&
        candidates.isNotEmpty &&
        candidates.first['finishReason'] == 'MAX_TOKENS') {
      throw const MiniMaxException('模型输出被截断，请提高最大 Tokens');
    }

    final stopReason = decoded['stop_reason']?.toString().trim();
    if (stopReason == 'max_tokens') {
      throw MiniMaxException(
        '$_providerLabel 输出被截断，请提高最大输出 Token 或缩短 OCR 文本后重试',
      );
    }

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return;
    }

    final firstChoice = choices.first as Map;
    final finishReason = firstChoice['finish_reason']?.toString().trim();
    if (finishReason == 'length') {
      throw MiniMaxException(
        '$_providerLabel 输出被截断，请提高最大输出 Token 或缩短 OCR 文本后重试',
      );
    }
  }

  String _stripMarkdownCodeFence(String source) {
    if (!source.startsWith('```')) {
      return source;
    }

    final lines = source.split('\n');
    if (lines.length < 3) {
      return source;
    }

    if (lines.first.startsWith('```')) {
      lines.removeAt(0);
    }
    if (lines.isNotEmpty && lines.last.trim() == '```') {
      lines.removeLast();
    }

    return lines.join('\n').trim();
  }

  String _joinMessageParts(List parts) {
    final chunks = <String>[];

    for (final part in parts) {
      if (part is Map) {
        final directText = part['text'];
        if (directText is String && directText.trim().isNotEmpty) {
          chunks.add(directText.trim());
          continue;
        }

        final nestedText = part['content'];
        if (nestedText is String && nestedText.trim().isNotEmpty) {
          chunks.add(nestedText.trim());
        }
      } else if (part is String && part.trim().isNotEmpty) {
        chunks.add(part.trim());
      }
    }

    return chunks.join('\n').trim();
  }

  String _extractFirstJsonBlock(String source) {
    final objectStart = source.indexOf('{');
    final arrayStart = source.indexOf('[');

    var start = -1;
    var openChar = '';
    var closeChar = '';

    if (objectStart >= 0 && (arrayStart < 0 || objectStart < arrayStart)) {
      start = objectStart;
      openChar = '{';
      closeChar = '}';
    } else if (arrayStart >= 0) {
      start = arrayStart;
      openChar = '[';
      closeChar = ']';
    }

    if (start < 0) {
      throw const FormatException('No JSON object found');
    }

    var depth = 0;
    var inString = false;
    var escaping = false;

    for (var i = start; i < source.length; i++) {
      final char = source[i];

      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (char == '\\') {
          escaping = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        continue;
      }

      if (char == openChar) {
        depth++;
        continue;
      }

      if (char == closeChar) {
        depth--;
        if (depth == 0) {
          return source.substring(start, i + 1);
        }
      }
    }

    throw const FormatException('No complete JSON object found');
  }
}
