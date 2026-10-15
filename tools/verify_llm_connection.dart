import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/llm_model_catalog.dart';
import 'package:pxt1/llm/llm_request_support.dart';
import 'package:pxt1/llm/minimax_client.dart';

// Run with dart, then enter the key at the hidden prompt. Never put keys in args.
Future<void> main(List<String> args) async {
  final provider = args.isEmpty ? LlmProvider.opencodeGo : args.first;
  final preset = LlmModelCatalog.providerPresets.firstWhere(
    (p) => p.provider == provider,
  );
  final model = args.length > 1 ? args[1] : 'step-5-preview-free';
  stdout.write('API Key (hidden): ');
  if (stdin.hasTerminal) stdin.echoMode = false;
  final key = stdin.readLineSync()?.trim() ?? '';
  if (stdin.hasTerminal) stdin.echoMode = true;
  stdout.writeln();
  if (key.isEmpty) {
    stderr.writeln('No key supplied.');
    exitCode = 1;
    return;
  }
  final transport = http.Client();
  final config = LlmProviderConfig.emptyForUser(0).copyWith(
    provider: provider,
    apiMode: provider == LlmProvider.opencodeGo
        ? LlmApiMode.auto
        : LlmApiMode.openAiCompatible,
    apiKey: key,
    baseUrl: preset.baseUrl,
    model: model,
    maxTokens: 4096,
  );
  try {
    try {
      final models = await LlmModelCatalog.fetchModels(
        provider: provider,
        baseUrl: preset.baseUrl,
        apiKey: key,
        httpClient: transport,
      );
      stdout.writeln(
        jsonEncode({
          'model_count': models.length,
          'requested_model_listed': models.any((m) => m.id == model),
        }),
      );
    } catch (error) {
      stdout.writeln(LlmRequestSupport.redact('Model list: $error', key));
    }
    final client = MiniMaxClient.fromConfig(config, httpClient: transport);
    final reply = await client.generateChatReply(
      systemPrompt: '这是智学帮模型接口连接测试，请简短回复。',
      messages: [
        {'role': 'user', 'content': '请只回复：连接成功'},
      ],
    );
    stdout.writeln(
      jsonEncode({
        'chat_success': reply.trim().isNotEmpty,
        'model': model,
        'endpoint': config.effectiveEndpoint.toString(),
        'reply': LlmRequestSupport.redact(reply, key),
      }),
    );
    final structured = await client.generateStructuredJson(
      systemPrompt: '请只返回有效 JSON 对象。',
      userPrompt: '返回 {"ok":true}',
    );
    stdout.writeln(
      jsonEncode({'structured_success': structured['ok'] == true}),
    );
    if (structured['ok'] != true) exitCode = 1;
  } catch (error) {
    stderr.writeln(LlmRequestSupport.redact(error.toString(), key));
    exitCode = 1;
  } finally {
    transport.close();
  }
}
