import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pxt1/llm/llm_model_catalog.dart';

void main() {
  group('LLM model catalog', () {
    test('infers Kimi models from a Moonshot base URL', () {
      final models = LlmModelCatalog.modelsFor(
        provider: '',
        baseUrl: 'https://api.moonshot.cn/v1',
        currentModel: 'kimi-private-preview',
      );

      expect(models.first.id, 'kimi-k2.6');
      expect(models.map((model) => model.id), contains('kimi-k2.5'));
      expect(models.map((model) => model.id), contains('kimi-private-preview'));
    });

    test('builds a model-list endpoint from chat completion URLs', () {
      final endpoint = LlmModelCatalog.buildModelsEndpoint(
        'https://api.moonshot.cn/v1/chat/completions',
      );

      expect(endpoint.toString(), 'https://api.moonshot.cn/v1/models');
    });

    test('parses OpenAI-compatible model list responses', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'https://api.deepseek.com/v1/models');
        expect(request.headers['Authorization'], 'Bearer sk-test');

        return http.Response('''
          {
            "object": "list",
            "data": [
              {"id": "deepseek-v4-flash", "object": "model", "owned_by": "deepseek"},
              {"id": "deepseek-v4-pro", "object": "model", "owned_by": "deepseek"}
            ]
          }
          ''', 200);
      });

      final models = await LlmModelCatalog.fetchModels(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-test',
        httpClient: client,
      );

      expect(models.map((model) => model.id), [
        'deepseek-v4-flash',
        'deepseek-v4-pro',
      ]);
      expect(models.first.description, contains('deepseek'));
    });
  });
}
