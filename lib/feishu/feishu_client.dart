import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

Map<String, dynamic> _decode(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

class FeishuException implements Exception {
  FeishuException(this.message, {this.statusCode, this.retryAfter});
  final String message;
  final int? statusCode, retryAfter;
  @override
  String toString() =>
      '$message${retryAfter == null || retryAfter == 0 ? '' : '，请在 $retryAfter 秒后重试'}';
}

class FeishuClient {
  FeishuClient({http.Client? client, String? baseUrl})
    : _http = client ?? http.Client(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'FEISHU_SERVICE_BASE_URL',
            defaultValue: 'http://127.0.0.1:8787',
          );
  final http.Client _http;
  final String baseUrl;
  String? _session;
  bool get hasSession => _session != null;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_session != null) 'Authorization': 'Bearer $_session',
    };
    try {
      final response =
          await (method == 'POST'
                  ? _http.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? {}),
                    )
                  : method == 'DELETE'
                  ? _http.delete(uri, headers: headers)
                  : _http.get(uri, headers: headers))
              .timeout(
                path == '/health' || path == '/oauth/feishu/start'
                    ? const Duration(seconds: 12)
                    : const Duration(minutes: 5),
              );
      final result = await compute(_decode, response.bodyBytes);
      if (response.statusCode >= 400) {
        final detail = result['detail'];
        final message = detail is Map ? detail['message'] : detail;
        throw FeishuException(
          '${message ?? '连接服务请求失败'}（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
          retryAfter: detail is Map ? detail['retry_after'] as int? : null,
        );
      }
      return result;
    } on SocketException {
      throw FeishuException('网络不可用或连接服务未启动，请检查网络与服务地址');
    } on TimeoutException {
      throw FeishuException('请求超时，请重试；已保存的任务进度会保留');
    } on http.ClientException {
      throw FeishuException('连接中断，请检查网络后重试');
    } on FormatException {
      throw FeishuException('连接服务返回了无法解析的数据');
    }
  }

  Future<Uri> connect() async {
    final health = await request('GET', '/health');
    if (health['ready'] != true) {
      throw FeishuException('飞书连接服务尚未配置完成，请先在电脑上完成配置并启动服务');
    }
    final result = await request('POST', '/oauth/feishu/start');
    _session = result['session_token'] as String;
    return Uri.parse(result['authorization_url'] as String);
  }

  Future<void> disconnect() async {
    try {
      if (_session != null) {
        await request(
          'DELETE',
          '/connection',
        ).timeout(const Duration(seconds: 3));
      }
    } finally {
      _session = null;
    }
  }

  void close() {
    _session = null;
    _http.close();
  }
}
