import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/models/llm_provider_config.dart';

class LlmRequestSupport {
  static Map<String, String> headers({
    required String provider,
    required String apiKey,
    String? apiMode,
    String? sessionId,
  }) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider == LlmProvider.opencodeGo) {
      headers['Authorization'] = 'Bearer $apiKey';
      headers['User-Agent'] = 'Zhixuebang/1.0';
      if (sessionId != null) headers['x-opencode-session'] = sessionId;
    } else if (provider == LlmProvider.claude ||
        apiMode == LlmApiMode.anthropic) {
      headers['x-api-key'] = apiKey;
    } else if (provider == LlmProvider.gemini || apiMode == LlmApiMode.gemini) {
      headers['x-goog-api-key'] = apiKey;
    } else {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    if (provider == LlmProvider.claude ||
        apiMode == LlmApiMode.anthropic ||
        apiMode == LlmApiMode.tokenPlan) {
      headers['anthropic-version'] = '2023-06-01';
    }
    return headers;
  }

  static String redact(String text, String apiKey) {
    if (apiKey.isNotEmpty) text = text.replaceAll(apiKey, '[已隐藏]');
    return text.replaceAll(
      RegExp(r'(?:sk-|oc_sk_)[a-zA-Z0-9_\-]{8,}'),
      '[已隐藏]',
    );
  }

  static String httpError(http.Response response, String apiKey) {
    String detail = '';
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map) {
        final error = body['error'];
        detail =
            (error is Map ? error['message'] : error)?.toString() ??
            body['message']?.toString() ??
            '';
      }
    } catch (_) {
      /* Non-JSON upstream error; report the HTTP status. */
    }
    final reason = switch (response.statusCode) {
      401 => 'API Key 无效或已过期',
      403 => '账户无模型访问权限，或服务商限制了此类请求',
      402 => '账户余额不足或需要开通套餐',
      404 => '模型 ID 或接口地址不存在',
      429 => '请求过于频繁或账户额度已用尽',
      _ => '接口请求失败',
    };
    final safe = redact(detail, apiKey);
    return '$reason（HTTP ${response.statusCode}）${safe.isEmpty ? '' : '：${safe.length > 400 ? safe.substring(0, 400) : safe}'}';
  }
}
