import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  group('LLM provider config', () {
    test('normalizes a MiniMax Token Plan config for runtime use', () {
      final config = LlmProviderConfig.fromMap({
        'id': 1,
        'user_id': 7,
        'provider': 'minimax',
        'api_mode': 'token_plan',
        'api_key': '  sk-cp-user-key  ',
        'base_url': '',
        'model': '',
        'max_tokens': null,
        'created_at': '2026-04-26T00:00:00Z',
        'updated_at': '2026-04-26T00:00:00Z',
      });

      expect(config.isConfigured, isTrue);
      expect(config.apiKey, 'sk-cp-user-key');
      expect(config.apiMode, LlmApiMode.tokenPlan);
      expect(config.effectiveBaseUrl, 'https://api.minimax.io/anthropic');
      expect(
        config.effectiveEndpoint.toString(),
        'https://api.minimax.io/anthropic/v1/messages',
      );
      expect(config.effectiveModel, 'MiniMax-M2.7');
      expect(config.effectiveMaxTokens, 4096);
    });

    test(
      'normalizes a Kimi OpenAI-compatible config without double v1 path',
      () {
        final config = LlmProviderConfig.fromMap({
          'id': 2,
          'user_id': 7,
          'provider': 'kimi',
          'api_mode': 'openai_compatible',
          'api_key': '  sk-kimi-key  ',
          'base_url': 'https://api.moonshot.cn/v1/',
          'model': 'kimi-k2-0905-preview',
          'max_tokens': 8192,
          'created_at': '2026-04-26T00:00:00Z',
          'updated_at': '2026-04-26T00:00:00Z',
        });

        expect(config.provider, LlmProvider.kimi);
        expect(config.apiMode, LlmApiMode.openAiCompatible);
        expect(
          config.effectiveEndpoint.toString(),
          'https://api.moonshot.cn/v1/chat/completions',
        );
        expect(config.effectiveModel, 'kimi-k2-0905-preview');
        expect(config.effectiveMaxTokens, 8192);
      },
    );

    test('does not append duplicate endpoint segments', () {
      final kimiConfig = LlmProviderConfig.fromMap({
        'id': 2,
        'user_id': 7,
        'provider': 'kimi',
        'api_mode': 'openai_compatible',
        'api_key': 'sk-kimi-key',
        'base_url': 'https://api.moonshot.cn/v1/chat/completions',
        'model': 'kimi-k2.5',
        'max_tokens': 4096,
        'created_at': '2026-04-26T00:00:00Z',
        'updated_at': '2026-04-26T00:00:00Z',
      });
      final miniMaxConfig = LlmProviderConfig.fromMap({
        'id': 3,
        'user_id': 7,
        'provider': 'minimax',
        'api_mode': 'open_platform',
        'api_key': 'sk-user-key',
        'base_url': 'https://api.minimax.io/v1',
        'model': 'MiniMax-Text-01',
        'max_tokens': 4096,
        'created_at': '2026-04-26T00:00:00Z',
        'updated_at': '2026-04-26T00:00:00Z',
      });

      expect(
        kimiConfig.effectiveEndpoint.toString(),
        'https://api.moonshot.cn/v1/chat/completions',
      );
      expect(
        miniMaxConfig.effectiveEndpoint.toString(),
        'https://api.minimax.io/v1/text/chatcompletion_v2',
      );
    });

    test('preserves arbitrary OpenAI-compatible provider configs', () {
      final config = LlmProviderConfig.fromMap({
        'id': 4,
        'user_id': 7,
        'provider': 'deepseek',
        'api_mode': 'openai_compatible',
        'api_key': 'sk-deepseek-key',
        'base_url': 'https://api.deepseek.com/v1',
        'model': 'deepseek-chat',
        'max_tokens': 4096,
        'created_at': '2026-04-26T00:00:00Z',
        'updated_at': '2026-04-26T00:00:00Z',
      });

      expect(config.provider, 'deepseek');
      expect(config.usesOpenAiCompatible, isTrue);
      expect(
        config.effectiveEndpoint.toString(),
        'https://api.deepseek.com/v1/chat/completions',
      );
      expect(config.effectiveModel, 'deepseek-chat');
    });

    test('builds MiniMaxClient from a Kimi config', () {
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

      final client = MiniMaxClient.fromConfig(config);

      expect(
        client.debugEndpoint.toString(),
        'https://api.moonshot.cn/v1/chat/completions',
      );
      expect(client.debugModel, 'kimi-k2.5');
      expect(client.debugUsesOpenAiCompatible, isTrue);
      expect(client.debugUsesTokenPlan, isFalse);
    });

    test('defaults new user config to custom OpenAI-compatible fields', () {
      final config = LlmProviderConfig.emptyForUser(7);

      expect(config.provider, LlmProvider.custom);
      expect(config.apiMode, LlmApiMode.openAiCompatible);
      expect(config.baseUrl, isEmpty);
      expect(config.model, isEmpty);
      expect(config.isConfigured, isFalse);
    });
  });
}
