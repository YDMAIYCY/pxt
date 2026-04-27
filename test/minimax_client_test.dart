import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  group('MiniMaxClient', () {
    test('sends MiniMax structured output schema when provided', () async {
      Map<String, dynamic>? requestBody;
      final client = MiniMaxClient(
        apiKey: 'test-key',
        endpoint: Uri.parse('https://example.com/v1/text/chatcompletion_v2'),
        httpClient: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': '{"cards":[{"title":"导数","content":"变化率"}]}',
                },
              },
            ],
          });
        }),
      );

      await client.generateStructuredJson(
        systemPrompt: '只返回 JSON',
        userPrompt: '生成知识卡片',
        jsonSchema: {
          'name': 'knowledge_cards_response',
          'schema': {
            'type': 'object',
            'properties': {
              'cards': {'type': 'array'},
            },
            'required': ['cards'],
          },
        },
      );

      expect(requestBody?['response_format'], isA<Map>());
      expect(requestBody?['max_completion_tokens'], 4096);
    });

    test('reports truncated MiniMax output instead of generic JSON format', () {
      final client = MiniMaxClient(
        apiKey: 'test-key',
        endpoint: Uri.parse('https://example.com/v1/text/chatcompletion_v2'),
        httpClient: MockClient((request) async {
          return _jsonResponse({
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': '{"questions":[{"question_text":"未完成"'},
              },
            ],
          });
        }),
      );

      expect(
        () => client.generateStructuredJson(
          systemPrompt: '只返回 JSON',
          userPrompt: '生成复习题',
        ),
        throwsA(
          isA<MiniMaxException>().having(
            (error) => error.message,
            'message',
            contains('输出被截断'),
          ),
        ),
      );
    });

    test(
      'uses Anthropic-compatible request format for Token Plan keys',
      () async {
        Uri? requestUrl;
        Map<String, dynamic>? requestBody;
        final client = MiniMaxClient(
          apiKey: 'sk-cp-test-token-plan-key',
          endpoint: Uri.parse('https://example.com/anthropic/v1/messages'),
          httpClient: MockClient((request) async {
            requestUrl = request.url;
            requestBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _jsonResponse({
              'content': [
                {
                  'type': 'text',
                  'text': '{"cards":[{"title":"极限","content":"函数趋近"}]}',
                },
              ],
              'stop_reason': 'end_turn',
            });
          }),
        );

        final result = await client.generateStructuredJson(
          systemPrompt: '只返回 JSON',
          userPrompt: '生成知识卡片',
        );

        expect(requestUrl?.path, '/anthropic/v1/messages');
        expect(requestBody?['model'], 'MiniMax-M2.7');
        expect(requestBody?['anthropic_version'], 'bedrock-2023-05-31');
        expect(requestBody?['max_tokens'], 4096);
        expect(requestBody?['system'], '只返回 JSON');
        expect(requestBody?['messages'], [
          {'role': 'user', 'content': '生成知识卡片'},
        ]);
        expect(requestBody?.containsKey('response_format'), isFalse);
        expect(result['cards'], isA<List>());
      },
    );

    test('uses OpenAI-compatible request format for Kimi configs', () async {
      Uri? requestUrl;
      Map<String, dynamic>? requestBody;
      final config = LlmProviderConfig(
        id: 1,
        userId: 7,
        provider: LlmProvider.kimi,
        apiMode: LlmApiMode.openAiCompatible,
        apiKey: 'sk-kimi-key',
        baseUrl: 'https://api.moonshot.cn/v1',
        model: 'kimi-k2.5',
        maxTokens: 4096,
        createdAt: DateTime.utc(2026, 4, 26),
        updatedAt: DateTime.utc(2026, 4, 26),
      );
      final client = MiniMaxClient.fromConfig(
        config,
        httpClient: MockClient((request) async {
          requestUrl = request.url;
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _jsonResponse({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'role': 'assistant',
                  'content': '{"cards":[{"title":"导数","content":"变化率"}]}',
                },
              },
            ],
          });
        }),
      );

      final result = await client.generateStructuredJson(
        systemPrompt: '只返回 JSON',
        userPrompt: '生成知识卡片',
      );

      expect(
        requestUrl.toString(),
        'https://api.moonshot.cn/v1/chat/completions',
      );
      expect(requestBody?['model'], 'kimi-k2.5');
      expect(requestBody?['temperature'], 1.0);
      expect(requestBody?['max_tokens'], 4096);
      expect(requestBody?['response_format'], {'type': 'json_object'});
      expect(requestBody?['messages'], [
        {'role': 'system', 'content': '只返回 JSON'},
        {'role': 'user', 'content': '生成知识卡片'},
      ]);
      expect(result['cards'], isA<List>());
    });

    test(
      'uses OpenAI-compatible request format for arbitrary providers',
      () async {
        Uri? requestUrl;
        Map<String, dynamic>? requestBody;
        final config = LlmProviderConfig(
          id: 1,
          userId: 7,
          provider: 'deepseek',
          apiMode: LlmApiMode.openAiCompatible,
          apiKey: 'sk-deepseek-key',
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-chat',
          maxTokens: 4096,
          createdAt: DateTime.utc(2026, 4, 26),
          updatedAt: DateTime.utc(2026, 4, 26),
        );
        final client = MiniMaxClient.fromConfig(
          config,
          httpClient: MockClient((request) async {
            requestUrl = request.url;
            requestBody = jsonDecode(request.body) as Map<String, dynamic>;
            return _jsonResponse({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'role': 'assistant',
                    'content': '{"cards":[{"title":"导数","content":"变化率"}]}',
                  },
                },
              ],
            });
          }),
        );

        await client.generateStructuredJson(
          systemPrompt: '只返回 JSON',
          userPrompt: '生成知识卡片',
        );

        expect(
          requestUrl.toString(),
          'https://api.deepseek.com/v1/chat/completions',
        );
        expect(requestBody?['model'], 'deepseek-chat');
        expect(requestBody?['response_format'], {'type': 'json_object'});
      },
    );
  });
}

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}
