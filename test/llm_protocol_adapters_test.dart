import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/llm_model_catalog.dart';
import 'package:pxt1/llm/minimax_client.dart';

LlmProviderConfig config(String provider, String model, {String? mode}) {
  final preset = LlmModelCatalog.providerPresets.firstWhere(
    (p) => p.provider == provider,
  );
  return LlmProviderConfig.emptyForUser(1).copyWith(
    provider: provider,
    apiMode:
        mode ??
        (provider == LlmProvider.opencodeGo
            ? LlmApiMode.auto
            : LlmApiMode.openAiCompatible),
    apiKey: 'secret-test-key',
    baseUrl: preset.baseUrl.isEmpty ? 'https://example.com/v1' : preset.baseUrl,
    model: model,
    temperature: 0.7,
  );
}

http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('catalog contains exactly the nine requested providers', () {
    expect(LlmModelCatalog.providerPresets.map((p) => p.provider).toSet(), {
      'openai',
      'deepseek',
      'kimi',
      'minimax',
      'opencode_go',
      'claude',
      'gemini',
      'siliconflow',
      'custom',
    });
    expect(LlmModelCatalog.providerPresets, hasLength(9));
  });

  for (final provider in [
    'openai',
    'deepseek',
    'kimi',
    'minimax',
    'siliconflow',
    'custom',
  ]) {
    test(
      '$provider preserves compatible chat and structured generation',
      () async {
        final transport = MockClient((request) async {
          expect(request.url.path, endsWith('/chat/completions'));
          expect(request.headers['Authorization'], 'Bearer secret-test-key');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'test-model');
          expect(body['max_tokens'], 4096);
          expect(body['temperature'], provider == 'kimi' ? 1.0 : 0.7);
          return jsonResponse({
            'choices': [
              {
                'message': {'content': '{"ok":true}'},
              },
            ],
          });
        });
        final client = MiniMaxClient.fromConfig(
          config(provider, 'test-model'),
          httpClient: transport,
        );
        expect(
          await client.generateChatReply(
            systemPrompt: '测试',
            messages: [
              {'role': 'user', 'content': '你好'},
            ],
          ),
          '{"ok":true}',
        );
        expect(
          await client.generateStructuredJson(
            systemPrompt: 'JSON',
            userPrompt: '测试',
          ),
          {'ok': true},
        );
      },
    );
  }

  for (final provider in ['claude', 'opencode_go']) {
    test(
      '$provider uses native Messages and separates system prompt',
      () async {
        final transport = MockClient((request) async {
          expect(request.url.path, endsWith('/v1/messages'));
          expect(request.headers['anthropic-version'], '2023-06-01');
          expect(
            request.headers[provider == 'claude'
                ? 'x-api-key'
                : 'Authorization'],
            provider == 'claude' ? 'secret-test-key' : 'Bearer secret-test-key',
          );
          final body = jsonDecode(request.body) as Map;
          expect(body['system'], contains('测试'));
          expect(body['messages'], [
            {'role': 'user', 'content': '你好'},
          ]);
          expect(body.containsKey('response_format'), isFalse);
          return jsonResponse({
            'content': [
              {'type': 'text', 'text': '{"ok":true}'},
            ],
          });
        });
        final client = MiniMaxClient.fromConfig(
          config(provider, 'claude-haiku-5-5'),
          httpClient: transport,
        );
        expect(
          await client.generateChatReply(
            systemPrompt: '测试',
            messages: [
              {'role': 'user', 'content': '你好'},
            ],
          ),
          '{"ok":true}',
        );
        expect(
          await client.generateStructuredJson(
            systemPrompt: '测试',
            userPrompt: '你好',
          ),
          {'ok': true},
        );
      },
    );
  }

  test('Go Responses parses only message output, never reasoning', () async {
    final transport = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://opencode.ai/inference/go/v1/responses',
      );
      expect(request.headers['x-opencode-session'], isNotEmpty);
      expect(request.headers['User-Agent'], 'Zhixuebang/1.0');
      final body = jsonDecode(request.body) as Map;
      expect(body['max_output_tokens'], 4096);
      expect(body.containsKey('messages'), isFalse);
      expect(body.containsKey('temperature'), isFalse);
      expect(body['text'], {
        'format': {'type': 'json_object'},
      });
      return jsonResponse({
        'status': 'completed',
        'output': [
          {
            'type': 'reasoning',
            'content': [
              {'text': 'private'},
            ],
          },
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '{"ok":true}'},
            ],
          },
        ],
      });
    });
    final client = MiniMaxClient.fromConfig(
      config('opencode_go', 'gpt-6-luna'),
      httpClient: transport,
    );
    expect(
      await client.generateStructuredJson(
        systemPrompt: 'JSON',
        userPrompt: '测试',
      ),
      {'ok': true},
    );
  });

  for (final provider in ['gemini', 'opencode_go']) {
    test('$provider uses native Gemini and ignores thought parts', () async {
      final transport = MockClient((request) async {
        expect(
          request.url.path,
          endsWith('/models/gemini-test:generateContent'),
        );
        final auth = provider == 'gemini' ? 'x-goog-api-key' : 'Authorization';
        expect(
          request.headers[auth],
          provider == 'gemini' ? 'secret-test-key' : 'Bearer secret-test-key',
        );
        final body = jsonDecode(request.body) as Map;
        expect(
          body['generationConfig']['responseMimeType'],
          'application/json',
        );
        expect(body['contents'][0]['role'], 'user');
        return jsonResponse({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'thought': true, 'text': 'private'},
                  {'text': '{"ok":true}'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        });
      });
      final client = MiniMaxClient.fromConfig(
        config(provider, 'gemini-test'),
        httpClient: transport,
      );
      expect(
        await client.generateStructuredJson(
          systemPrompt: 'JSON',
          userPrompt: '测试',
        ),
        {'ok': true},
      );
    });
  }

  test('Go Step routes to chat and errors never leak credentials', () async {
    final transport = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://opencode.ai/inference/go/v1/chat/completions',
      );
      return http.Response(
        '{"error":{"message":"invalid secret-test-key"}}',
        403,
      );
    });
    final client = MiniMaxClient.fromConfig(
      config('opencode_go', 'step-5-preview-free'),
      httpClient: transport,
    );
    await expectLater(
      client.generateChatReply(
        systemPrompt: '测试',
        messages: [
          {'role': 'user', 'content': '你好'},
        ],
      ),
      throwsA(
        isA<MiniMaxException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('403'),
            contains('访问权限'),
            isNot(contains('secret-test-key')),
          ),
        ),
      ),
    );
  });

  test('200 with empty response is not a successful connection', () async {
    final client = MiniMaxClient.fromConfig(
      config('deepseek', 'test'),
      httpClient: MockClient((_) async => jsonResponse({'choices': []})),
    );
    await expectLater(
      client.generateChatReply(
        systemPrompt: '测试',
        messages: [
          {'role': 'user', 'content': '你好'},
        ],
      ),
      throwsA(isA<MiniMaxException>()),
    );
  });

  test(
    'Gemini list filters generation models and follows pagination',
    () async {
      var calls = 0;
      final transport = MockClient((request) async {
        expect(request.headers['x-goog-api-key'], 'secret-test-key');
        calls++;
        if (calls == 1) {
          return jsonResponse({
            'models': [
              {
                'name': 'models/embedding',
                'supportedGenerationMethods': ['embedContent'],
              },
              {
                'name': 'models/gemini-one',
                'displayName': 'Gemini One',
                'supportedGenerationMethods': ['generateContent'],
              },
            ],
            'nextPageToken': 'page2',
          });
        }
        expect(request.url.queryParameters['pageToken'], 'page2');
        return jsonResponse({
          'models': [
            {
              'name': 'models/gemini-two',
              'supportedGenerationMethods': ['generateContent'],
            },
          ],
        });
      });
      final models = await LlmModelCatalog.fetchModels(
        provider: 'gemini',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        apiKey: 'secret-test-key',
        httpClient: transport,
      );
      expect(models.map((m) => m.id), ['gemini-one', 'gemini-two']);
    },
  );
}
