import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_runtime_config.dart';
import '../database/models/llm_provider_config.dart';

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
           maxCompletionTokens ?? AppRuntimeConfig.minimaxMaxCompletionTokens;

  MiniMaxClient.fromConfig(LlmProviderConfig config, {http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _provider = config.provider,
      _apiMode = config.apiMode,
      _apiKey = config.apiKey.trim(),
      _groupId = '',
      _model = config.effectiveModel,
      _endpoint = config.effectiveEndpoint,
      _timeout = Duration(seconds: AppRuntimeConfig.requestTimeoutSeconds),
      _maxCompletionTokens = config.effectiveMaxTokens;

  final http.Client _httpClient;
  final Uri _endpoint;
  final String _apiKey;
  final String _groupId;
  final String _model;
  final String _provider;
  final String _apiMode;
  final Duration _timeout;
  final int _maxCompletionTokens;

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
      case LlmProvider.custom:
        return '自定义模型';
      default:
        return _provider;
    }
  }

  bool get _usesTokenPlan =>
      _provider == LlmProvider.minimax && _apiMode == LlmApiMode.tokenPlan;

  bool get _usesOpenAiCompatible =>
      _provider != LlmProvider.minimax ||
      _provider == LlmProvider.kimi ||
      _apiMode == LlmApiMode.openAiCompatible;

  Future<Map<String, dynamic>> generateStructuredJson({
    required String systemPrompt,
    required String userPrompt,
    Map<String, dynamic>? jsonSchema,
  }) async {
    if (_apiKey.isEmpty) {
      throw MiniMaxException('未配置 $_providerLabel API Key，请先到“我的”页配置大模型。');
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };
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
        throw MiniMaxException(
          '$_providerLabel 请求失败（HTTP ${response.statusCode}）：${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);
      _throwIfApiError(decoded);
      _throwIfOutputTruncated(decoded);
      final jsonContent = _extractModelContent(decoded);
      return _parseStructuredJson(jsonContent);
    } on TimeoutException {
      throw MiniMaxException('$_providerLabel 请求超时，请稍后重试');
    } on FormatException {
      throw MiniMaxException('$_providerLabel 返回内容不是有效 JSON');
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

  Map<String, Object?> _buildMiniMaxChatCompletionBody({
    required String systemPrompt,
    required String userPrompt,
    required Map<String, dynamic>? jsonSchema,
  }) {
    final body = <String, Object?>{
      'model': _model,
      'temperature': 0.2,
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

  Map<String, Object?> _buildTokenPlanBody({
    required String systemPrompt,
    required String userPrompt,
  }) {
    return {
      'model': _model,
      'anthropic_version': 'bedrock-2023-05-31',
      'temperature': 0.2,
      'max_tokens': _maxCompletionTokens,
      'system': systemPrompt,
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
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

  double get _openAiCompatibleTemperature {
    if (_provider == LlmProvider.kimi ||
        _model.trim().toLowerCase().startsWith('kimi-')) {
      return 1.0;
    }
    return 0.2;
  }

  Object? _extractModelContent(Object? decoded) {
    if (decoded is Map<String, dynamic>) {
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
        '${message.isEmpty ? '未返回错误详情' : message}',
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
      '${statusMessage.isEmpty ? '未返回错误详情' : statusMessage}',
    );
  }

  void _throwIfOutputTruncated(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      return;
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
