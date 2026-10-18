import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';

// ========== Cloud Speech Transcription ==========
// Uploads locally recorded answer audio to an OpenAI-compatible
// /audio/transcriptions endpoint and returns recognized text.

class CloudSpeechTranscriptionService {
  CloudSpeechTranscriptionService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<String> transcribeAudioFile({
    required String audioPath,
    required LlmProviderConfig config,
    String model = 'gpt-4o-mini-transcribe',
  }) async {
    if (config.apiKey.trim().isEmpty) {
      throw const MiniMaxException('请先到“我的”页配置支持语音转写的 API Key');
    }

    final endpoint = _transcriptionEndpoint(config);
    final request = http.MultipartRequest('POST', endpoint)
      ..headers['Authorization'] = 'Bearer ${config.apiKey.trim()}'
      ..fields['model'] = model
      ..fields['language'] = 'zh'
      ..fields['response_format'] = 'json'
      ..files.add(await http.MultipartFile.fromPath('file', audioPath));

    try {
      final streamed = await _httpClient
          .send(request)
          .timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MiniMaxException(_transcriptionError(response));
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final text = decoded['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          return text;
        }
      }
      throw const FormatException('Empty transcription response');
    } on TimeoutException {
      throw const MiniMaxException('语音转写请求超时，请稍后重试');
    } on http.ClientException {
      throw const MiniMaxException('语音转写网络连接中断，请检查网络或接口地址');
    } on FormatException {
      throw const MiniMaxException('语音转写返回内容无法解析');
    }
  }

  Uri _transcriptionEndpoint(LlmProviderConfig config) {
    final baseUrl = config.effectiveBaseUrl.trim();
    if (baseUrl.isEmpty) {
      throw const MiniMaxException('请先配置支持语音转写的 Base URL');
    }

    final uri = Uri.parse(_stripTrailingSlash(baseUrl));
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: true);

    if (_endsWith(segments, const ['chat', 'completions'])) {
      segments.removeLast();
      segments.removeLast();
    } else if (_endsWith(segments, const ['responses'])) {
      segments.removeLast();
    }

    segments.addAll(const ['audio', 'transcriptions']);
    return uri.replace(pathSegments: segments);
  }

  String _transcriptionError(http.Response response) {
    final body = response.body.trim();
    if (response.statusCode == 404) {
      return '当前模型服务不支持 /audio/transcriptions，请换成 OpenAI 或兼容语音转写的服务';
    }
    if (body.isEmpty) {
      return '语音转写失败（HTTP ${response.statusCode}）';
    }
    return '语音转写失败（HTTP ${response.statusCode}）：$body';
  }

  static bool _endsWith(List<String> source, List<String> suffix) {
    if (suffix.length > source.length) {
      return false;
    }
    final offset = source.length - suffix.length;
    for (var i = 0; i < suffix.length; i++) {
      if (source[offset + i].toLowerCase() != suffix[i].toLowerCase()) {
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
